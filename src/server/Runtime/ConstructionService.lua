--!strict
-- Server-authoritative Phase 02 construction. Studio prebaked geometry only.
-- Requests never contain trusted instances or arbitrary physical dimensions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Registry = require(construction:WaitForChild("PrimitiveRegistry"))
local Grid = require(construction:WaitForChild("GridMath"))
local Bore = require(construction:WaitForChild("BoreClearance"))
local Alignment = require(construction:WaitForChild("AlignmentMath"))
local MultiFit = require(construction:WaitForChild("MultiFitMath"))
local Config = require(construction:WaitForChild("BuildConfig"))
local ComponentService = require(script.Parent:WaitForChild("ComponentService"))
local AlignmentService = require(script.Parent:WaitForChild("AlignmentService"))
local MechanicalService = require(script.Parent:WaitForChild("MechanicalService"))
local SimulationService = require(script.Parent:WaitForChild("SimulationService"))
local GearLibrary = require(script.Parent:WaitForChild("GearLibrary"))
local FastenerLibrary = require(script.Parent:WaitForChild("FastenerLibrary"))
local HandCrankLibrary = require(script.Parent:WaitForChild("HandCrankLibrary"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local PlotPersistence = require(script.Parent:WaitForChild("PlotPersistence"))
local RotationMath = require(construction:WaitForChild("RotationMath"))

local DEFAULT_METAL_COLOR = Color3.fromRGB(78, 83, 91)

local Service = {}
local folder
local remote
local histories = {}
local lastRequest = {}
local components
local alignmentService
local mechanical
local simulation
local assemblies
local plots
local persistence

local function historyFor(player)
    local state = histories[player]
    if not state then
        state = { undo = {}, redo = {} }
        histories[player] = state
    end
    return state
end

local function ownedCount(player)
    local n = 0
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
            n += 1
        end
    end
    return n
end

local function hasEquippedTool(player, id)
    local character = player.Character
    if not character then return false end
    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") and object:GetAttribute("OpenworksToolId") == id then
            return true
        end
    end
    return false
end

local function accessFor(player, action)
    if action == "Place" then
        return hasEquippedTool(player, "Build") or hasEquippedTool(player, "Edit")
    end
    return hasEquippedTool(player, "Edit") or hasEquippedTool(player, "Build")
end

local function nearPlayer(player, position)
    if not plots or not plots:Contains(player,position) then return false end
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    return head and (head.Position - position).Magnitude <= Grid.MaxDistance
end

local function findOwned(player, id)
    if type(id) ~= "string" or #id > 64 then return nil end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("InstanceId") == id
            and model:GetAttribute("OwnerUserId") == player.UserId then
            return model
        end
    end
    return nil
end

local function snapshot(model)
    local primary = model.PrimaryPart
    return {
        instanceId = model:GetAttribute("InstanceId"),
        templateId = model:GetAttribute("TemplateId"),
        position = model:GetPivot().Position,
        steps = {
            x = model:GetAttribute("RotX") or 0,
            y = model:GetAttribute("RotY") or 0,
            z = model:GetAttribute("RotZ") or 0,
        },
        size = primary.Size,
        componentId = model:GetAttribute("ComponentId"),
        componentAnchorId = model:GetAttribute("ComponentAnchorId"),
        assemblyPrecision = model:GetAttribute("AssemblyPrecision") == true,
        resizePrecision = model:GetAttribute("ResizePrecision") == true,
        freePosition = model:GetAttribute("FreePosition") == true,
        fitPrecision = model:GetAttribute("FitPrecision") == true,
        numericPrecision = model:GetAttribute("NumericPrecision") == true,
        alignedOpeningId = model:GetAttribute("AlignedOpeningId"),
        grounded = model:GetAttribute("Grounded") == true,
        assemblyId = model:GetAttribute("AssemblyId"),
        assemblyName = model:GetAttribute("AssemblyName"),
        orientation = model:GetAttribute("AuthoredRotation"),
        shaftRollDegrees = model:GetAttribute("ShaftRollDegrees") or 0,
        alignedOffsetU = model:GetAttribute("AlignedOffsetU") or 0,
    }
end

local function createFromTemplate(player, templateId, instanceId, bypassLimit)
    local entry = Registry.Get(templateId)
    if not entry then return nil, "Unknown primitive template" end
    if not bypassLimit and ownedCount(player) >= Config.MaxPartsPerPlayer then
        return nil, "Construction limit reached"
    end

    local model = entry.Model:Clone()
    model.Name = templateId
    model:SetAttribute("TemplateId", templateId)
    model:SetAttribute("InstanceId", instanceId or HttpService:GenerateGUID(false))
    model:SetAttribute("OwnerUserId", player.UserId)

    local primary = model.PrimaryPart or model:FindFirstChild("Geometry")
    if not primary or not primary:IsA("BasePart") then
        model:Destroy()
        return nil, "Template is missing its geometry"
    end

    model.PrimaryPart = primary

    -- All constructed primitives have one consistent dark gray metal finish.
    -- Apply to every BasePart, including precompiled UnionOperations/MeshParts.
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.MaterialVariant = ""
            descendant.Material = Enum.Material.Metal
            descendant.Color = DEFAULT_METAL_COLOR
            if descendant:IsA("PartOperation") then
                -- Precompiled CSG can otherwise retain its original face colors.
                descendant.UsePartColor = true
            end
            descendant.Anchored = true
            local pivotOnly = descendant:GetAttribute("GearPivotOnly") == true
            descendant.CanCollide = not pivotOnly
            descendant.CanQuery = not pivotOnly
            descendant.CanTouch = false
            descendant.Reflectance = if pivotOnly then 0 else 0.045
            if pivotOnly then descendant.Transparency = 1 end
        end
    end

    return model
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.RespectCanCollide = false
overlap.MaxParts = 0

local GearMath = require(construction:WaitForChild("GearMath"))
local function intersectsConstructed(candidate, except, opening: Model?, shaftId: string?, fitMap)
    overlap.FilterDescendantsInstances = { folder }
    for _,solid in ipairs(candidate:GetDescendants()) do
        if not solid:IsA("BasePart") or not solid.CanCollide then continue end
        local probe=solid:Clone()
        probe.Name="OPENWORKS_OverlapProbe"
        probe.Size=Vector3.new(math.max(0.015,solid.Size.X-0.006),
            math.max(0.015,solid.Size.Y-0.006),
            math.max(0.015,solid.Size.Z-0.006))
        probe.CFrame=solid.CFrame
        probe.Transparency=1
        probe.CanCollide=false
        probe.CanTouch=false
        probe.CanQuery=true
        probe.Anchored=true
        probe.Parent=workspace
        local ok,results=pcall(function()
            return workspace:GetPartsInPart(probe,overlap)
        end)
        probe:Destroy()
        if not ok then
            warn("[OPENWORKS] Collision query failed: "..tostring(results))
            return true
        end
        for _,part in ipairs(results) do
            if part:GetAttribute("GearPivotOnly")==true then continue end
            local target=part:FindFirstAncestorOfClass("Model")
            local ignored=false
            if typeof(except)=="Instance" then
                ignored=part:IsDescendantOf(except)
            elseif type(except)=="table" then
                ignored=target~=nil and except[target]==true
            end
            if ignored then continue end
            local intendedBore=target and target==opening and shaftId
                and candidate:GetAttribute("InstanceId")==shaftId
                and Bore.ShaftFits(candidate,target)
            local intendedGear=target and GearMath.Meshable(candidate,target)
            local approvedFit=target and fitMap and fitMap[candidate]
                and fitMap[candidate][target] == true
            if not intendedBore and not intendedGear and not approvedFit then
                return true
            end
        end
    end
    return false
end

local function validState(player, entry, proposed)
    if type(proposed) ~= "table"
        or not Grid.ValidPosition(proposed.position)
        or not Grid.ValidSteps(proposed.steps)
        or typeof(proposed.size) ~= "Vector3" then
        return false, "Invalid construction state"
    end
    if not nearPlayer(player, proposed.position) then
        return false, "Target is outside your plot or too far away"
    end
    if not plots:Contains(player,proposed.position,proposed.size) then
        return false, "Construction extends beyond your plot"
    end

    local original = entry.Model.PrimaryPart
    if not original then return false, "Missing primitive geometry" end
    local id = string.lower(tostring(entry.Id))
    local isCylinder = string.find(id, "cylinder", 1, true)
        and not string.find(id, "halfcylinder", 1, true)
    if proposed.fitPrecision == true and not isCylinder then
        return false, "Fine-fit precision is reserved for full Cylinder shafts"
    end
    if not Grid.ValidSize(original.Size, proposed.size,
        entry.ResizeMode, proposed.fitPrecision == true,
        proposed.numericPrecision == true) then
        return false, "Size does not match allowed Unit increments"
    end

    -- Only size increments are quantized. A valid world-space position
    -- is no longer required to coincide with ANY grid lattice.
    -- Exact surface support and component offsets must not be rejected.
    return true
end

local function applyState(model, data)
    model.PrimaryPart.Size = data.size
    local rotation = if typeof(data.orientation) == "CFrame"
        then data.orientation.Rotation else Grid.Rotation(data.steps)
    model:PivotTo(CFrame.new(data.position) * rotation)
    model:SetAttribute("RotX", data.steps.x)
    model:SetAttribute("RotY", data.steps.y)
    model:SetAttribute("RotZ", data.steps.z)
    model:SetAttribute("ComponentId", data.componentId)
    model:SetAttribute("ComponentAnchorId", data.componentAnchorId)
    model:SetAttribute("AssemblyPrecision", data.assemblyPrecision == true)
    model:SetAttribute("ResizePrecision", data.resizePrecision == true
        or Grid.HasFractionalSize(data.size))
    model:SetAttribute("FreePosition", data.freePosition == true)
    model:SetAttribute("FitPrecision", data.fitPrecision == true)
    model:SetAttribute("NumericPrecision", data.numericPrecision == true)
    model:SetAttribute("AlignedOpeningId", data.alignedOpeningId)
    model:SetAttribute("Grounded", data.grounded == true)
    model:SetAttribute("AssemblyId",data.assemblyId)
    model:SetAttribute("AssemblyName",data.assemblyName)
    model:SetAttribute("AuthoredRotation", data.orientation)
    model:SetAttribute("ShaftRollDegrees", data.shaftRollDegrees or 0)
    model:SetAttribute("AlignedOffsetU", data.alignedOffsetU or 0)
end

local function commitRecord(player, before, after)
    local state = historyFor(player)
    table.insert(state.undo, { before = before, after = after })
    if #state.undo > Config.UndoLimit then
        table.remove(state.undo, 1)
    end
    table.clear(state.redo)
end

local function commitBatch(player, before, after)
    -- Geometry transformations, additions and deletions only.
    local state = historyFor(player)
    table.insert(state.undo, { kind = "Batch", before = before, after = after })
    if #state.undo > Config.UndoLimit then table.remove(state.undo, 1) end
    table.clear(state.redo)
end

local function commitMetadata(player, before, after)
    -- Named assemblies, editor groups and grounding are PROPERTY-ONLY
    -- transactions. Undo/redo must never destroy or recreate geometry,
    -- since doing so invalidates live selection and authored joint links.
    local state = historyFor(player)
    table.insert(state.undo, {kind="Metadata",before=before,after=after})
    if #state.undo > Config.UndoLimit then table.remove(state.undo,1) end
    table.clear(state.redo)
end

local function commitJointEdit(player, before, after)
    local state = historyFor(player)
    table.insert(state.undo,{kind="JointConfig",before=before,after=after})
    if #state.undo > Config.UndoLimit then table.remove(state.undo,1) end
    table.clear(state.redo)
end

local function commitAssembly(player, before, after, relation, removed, relationEdits)
    local state = historyFor(player)
    -- A multi-point fit is ONE history action containing N independently
    -- authored joint specifications. Single-relation history remains intact.
    local batch=type(relation)=="table"
        and (type(relation[1])=="table" or relationEdits~=nil)
    table.insert(state.undo, {
        kind = "Assembly",
        before = before,
        after = after,
        relation = if batch then nil else relation,
        relations = if batch then relation else nil,
        relationEdits=relationEdits,
        removed = removed == true,
    })
    if #state.undo > Config.UndoLimit then table.remove(state.undo, 1) end
    table.clear(state.redo)
end

-- Restore an entire component operation atomically: prepare all replacement
-- primitives, check all collisions against untouched models, then swap.
-- Member IDs and component metadata are restored with geometry.
local function restoreBatch(player, record, undo)
    local target = if undo then record.before else record.after
    local affected, current = {}, {}

    for _, group in ipairs({ record.before, record.after }) do
        for _, data in ipairs(group) do
            local model = findOwned(player, data.instanceId)
            if model and not affected[model] then
                affected[model] = true
                table.insert(current, model)
            end
        end
    end

    local finalCount = ownedCount(player) - #current + #target
    if finalCount > Config.MaxPartsPerPlayer then
        return false, "Construction limit reached"
    end

    local staged = {}
    local function discard()
        for _, model in ipairs(staged) do model:Destroy() end
    end

    for _, desired in ipairs(target) do
        local entry = Registry.Get(desired.templateId)
        if not entry then discard() return false, "Template unavailable" end
        local valid, reason = validState(player, entry, desired)
        if not valid then discard() return false, reason end

        local model, why = createFromTemplate(
            player, desired.templateId, desired.instanceId, true
        )
        if not model then discard() return false, why end
        applyState(model, desired)
        table.insert(staged, model)
    end

    local relation=record.relation
    local relations=table.clone(record.relations or (relation and {relation} or {}))
    for _,edit in ipairs(record.relationEdits or {}) do
        table.insert(relations,if undo then edit.before else edit.after)
    end
    local stagedById={}
    for _,stagedModel in ipairs(staged) do
        stagedById[stagedModel:GetAttribute("InstanceId")]=stagedModel
    end
    local fitMap={}
    for _,spec in ipairs(relations) do
        if spec.kind=="Bearing" or spec.kind=="Slider"
            or spec.kind=="Cylindrical" then
            local source=stagedById[spec.sourceId] or findOwned(player,spec.sourceId)
            local target=stagedById[spec.targetId] or findOwned(player,spec.targetId)
            if source and target then
                -- Revalidate full geometry rather than trusting saved contact
                -- metadata when undo/redo changes a piece's transform.
                local moving=if stagedById[spec.sourceId] then source
                    else if stagedById[spec.targetId] then target else nil
                local stationary=if moving==source then target else source
                if moving then
                    local valid=MultiFit.Check(moving,stationary)
                    if valid then
                        fitMap[moving]=fitMap[moving] or {}
                        fitMap[moving][stationary]=true
                    end
                end
            end
        end
    end
    local opening=nil
    local boreSourceId=nil
    if relation and (relation.kind=="Bearing"
        or relation.kind=="Slider" or relation.kind=="Cylindrical") then
        opening=findOwned(player,relation.targetId)
        boreSourceId=relation.sourceId
    end
    for _, model in ipairs(staged) do
        local ignore=affected
        if relation and relation.kind=="Bolt"
            and model:GetAttribute("InstanceId")==relation.boltId then
            ignore=table.clone(affected)
            local a=findOwned(player,relation.sourceId)
            local b=findOwned(player,relation.targetId)
            if a then ignore[a]=true end
            if b then ignore[b]=true end
            local extra=findOwned(player,relation.secondTargetId)
            if extra then ignore[extra]=true end
        end
        if intersectsConstructed(model,ignore,opening,boreSourceId,fitMap) then
            discard()
            return false,"Undo/redo blocked by another construction"
        end
    end

    for _, model in ipairs(current) do model:Destroy() end
    for _, model in ipairs(staged) do model.Parent = folder end
    return true
end

local function place(player, payload)
    if type(payload.templateId) ~= "string" then return false, "Missing template ID" end
    local entry = Registry.Get(payload.templateId)
    if not entry then return false, "Unknown primitive" end
    local template = entry.Model.PrimaryPart
    local proposed = {
        position = payload.position,
        steps = payload.steps,
        size = payload.size or (template and template.Size),
        orientation = if payload.autoMate
            and (payload.autoMate.kind=="BoltHole"
                or payload.autoMate.kind=="Bore"
                or payload.autoMate.kind=="CrankCoupling")
            then payload.orientation else nil,
        freePosition=payload.autoMate and (payload.autoMate.kind=="BoltHole"
            or payload.autoMate.kind=="Bore"
            or payload.autoMate.kind=="CrankCoupling"),
    }
    proposed.resizePrecision = Grid.HasFractionalSize(proposed.size)
    proposed.numericPrecision = payload.numericPrecision == true

    local valid, reason = validState(player, entry, proposed)
    if not valid then return false, reason end

    local model, why = createFromTemplate(player, payload.templateId)
    if not model then return false, why end
    applyState(model, proposed)

    -- Smart placements first pass through the server's exact compatible
    -- socket/gear transform and full geometry validation. The unsnapped
    -- draft can overlap an opening; it is never committed directly.
    if payload.autoMate == nil and intersectsConstructed(model) then
        model:Destroy()
        return false, "Placement intersects existing geometry"
    end

    model.Parent = folder

    -- A single drag can create BOTH the primitive and its relationship.
    -- SmartMate commits one assembly history entry: undo removes both.
    if payload.autoMate ~= nil then
        if type(payload.autoMate) ~= "table" then
            model:Destroy()
            return false, "Invalid automatic attachment"
        end
        local mate=payload.autoMate
        if mate.kind=="CrankCoupling" then
            local ok,why=mechanical:CoupleHandCrank(player,{
                sourceId=model:GetAttribute("InstanceId"),
                targetId=mate.targetId,
            },true)
            if not ok then model:Destroy() return false,why end
            return true,model:GetAttribute("InstanceId")
        end
        if mate.kind=="BoltHole" then
            local ok,why=mechanical:FastenBolt(player,{
                boltId=model:GetAttribute("InstanceId"),
                targetId=mate.targetId,
            },true)
            if not ok then model:Destroy() return false,why end
            return true,model:GetAttribute("InstanceId")
        end
        local ok,why=mechanical:SmartMate(player,{
            sourceId=model:GetAttribute("InstanceId"),
            targetId=mate.targetId,
            mateKind=mate.kind,
            relationKind=mate.relationKind,
            offsetUnits=mate.offsetUnits,
            rollDegrees=mate.rollDegrees,
            reverse=mate.reverse==true,
            fitTargets=mate.fitTargets,
            approach=payload.position,
            position=payload.position,
            orientation=payload.orientation,
        },true)
        if not ok then
            model:Destroy()
            return false,why
        end
        return true,model:GetAttribute("InstanceId")
    end

    local after = snapshot(model)
    commitRecord(player, nil, after)
    return true, after.instanceId
end

local function update(player, payload)
    local model = findOwned(player, payload.instanceId)
    if not model then return false, "Select a piece you own" end

    local entry = Registry.Get(model:GetAttribute("TemplateId"))
    if not entry then return false, "Primitive template missing" end

    local proposed = {
        position = payload.position,
        steps = payload.steps,
        size = payload.size,
        -- Editing one primitive inside a component must preserve membership.
        componentId = model:GetAttribute("ComponentId"),
        componentAnchorId = model:GetAttribute("ComponentAnchorId"),
        assemblyPrecision = model:GetAttribute("AssemblyPrecision") == true,
        resizePrecision = model:GetAttribute("ResizePrecision") == true
            or payload.resizePrecision == true,
        -- Explicit move operations may retain a precise world-space
        -- position; they still undergo range and full geometry validation.
        freePosition = model:GetAttribute("FreePosition") == true
            or payload.freePosition == true,
        fitPrecision = model:GetAttribute("FitPrecision") == true,
        numericPrecision = model:GetAttribute("NumericPrecision") == true
            or payload.numericPrecision == true,
        alignedOpeningId = model:GetAttribute("AlignedOpeningId"),
        grounded = model:GetAttribute("Grounded") == true,
        assemblyId = model:GetAttribute("AssemblyId"),
        assemblyName = model:GetAttribute("AssemblyName"),
        -- Resizing/moving a fine-rotated shaft must preserve its authored
        -- free-angle orientation. If the discrete steps change, compose the
        -- requested world-axis turn on top of its existing rotation.
        orientation = if typeof(model:GetAttribute("AuthoredRotation"))=="CFrame"
            then (
                Grid.Rotation(payload.steps)
                * Grid.Rotation(snapshot(model).steps):Inverse()
                * model:GetPivot().Rotation
            ) else nil,
        shaftRollDegrees = model:GetAttribute("ShaftRollDegrees") or 0,
        alignedOffsetU = model:GetAttribute("AlignedOffsetU") or 0,
    }
    local before=snapshot(model)
    local opening=before.alignedOpeningId
        and findOwned(player,before.alignedOpeningId) or nil
    if opening and Alignment.IsShaft(model) then
        -- Normal scale grips are length-only. Precise numeric entry may
        -- change the diameter only if the real bore clearance allows it.
        -- Fine-fit diameter remains controlled by the dedicated 0.05 U
        -- fitting workflow, not ordinary scale grips/remote updates.
        if payload.numericPrecision~=true and (
            math.abs(proposed.size.Y-before.size.Y)>0.0001
            or math.abs(proposed.size.Z-before.size.Z)>0.0001) then
            return false,"Aligned shafts resize along length only (X axis)"
        end
    end
    local valid, reason = validState(player, entry, proposed)
    if not valid then return false, reason end

    applyState(model, proposed)
    local stillAligned=false
    if opening and Alignment.IsShaft(model) then
        stillAligned=Bore.ShaftFits(model,opening)
        if stillAligned then
            local axis=opening:GetPivot():VectorToWorldSpace(
                Alignment.TargetAxis(opening)
            ).Unit
            proposed.alignedOffsetU=(model:GetPivot().Position
                -opening:GetPivot().Position):Dot(axis)/Grid.Unit
            model:SetAttribute("AlignedOffsetU",proposed.alignedOffsetU)
        else
            -- Never silently detach a guided or rigidly joined shaft.
            -- Disconnect the relationship/ungroup first, then reposition.
            applyState(model,before)
            return false,
                "Shaft must stay engaged; disconnect or ungroup before removing it"
        end
    end

    local ignore={[model]=true}
    if model:GetAttribute("ComponentId") then
        for _,member in ipairs(components:Members(
            player,model:GetAttribute("ComponentId"))) do
            ignore[member]=true
        end
    end
    if intersectsConstructed(model,ignore,
        if stillAligned then opening else nil,
        if stillAligned then before.instanceId else nil) then
        applyState(model,before)
        return false,"Edit intersects another piece"
    end

    local after=snapshot(model)
    commitRecord(player,before,after)
    return true,after.instanceId
end

local function rotatePrimitiveWorld(player,payload)
    local model=findOwned(player,payload.instanceId)
    if not model then return false,"Select a primitive you own" end
    if model:GetAttribute("ComponentId") then
        return false,"Rotate the complete body or enter component editing"
    end
    local delta=RotationMath.Delta(payload.axis,payload.direction,
        model:GetPivot().Position)
    if not delta then return false,"Choose world X, Y or Z" end
    local before=snapshot(model)
    local wanted=delta*model:GetPivot()
    local proposed=table.clone(before)
    proposed.position=wanted.Position
    proposed.orientation=wanted.Rotation
    proposed.steps=RotationMath.MatchSteps(wanted.Rotation) or before.steps
    proposed.freePosition=true
    local entry=Registry.Get(before.templateId)
    if not entry then return false,"Missing primitive" end
    local valid,reason=validState(player,entry,proposed)
    if not valid then return false,reason end
    applyState(model,proposed)
    if intersectsConstructed(model,model) then
        applyState(model,before)
        return false,"Rotation intersects another construction"
    end
    commitRecord(player,before,snapshot(model))
    return true,"Primitive rotated around world "..tostring(payload.axis)
end

local function delete(player, payload)
    local model = findOwned(player, payload.instanceId)
    if not model then return false, "Select a piece you own" end

    local componentId = model:GetAttribute("ComponentId")
    if not componentId then
        local before = snapshot(model)
        model:Destroy()
        commitRecord(player, before, nil)
        return true, "Deleted"
    end

    -- If removing a primitive from inside a component, update its membership
    -- and anchor atomically with deletion so undo recreates the old component.
    local members = components:Members(player, componentId)
    local before = {}
    for _, member in ipairs(members) do
        table.insert(before, snapshot(member))
    end

    model:Destroy()
    local remaining = {}
    for _, member in ipairs(members) do
        if member ~= model then table.insert(remaining, member) end
    end

    local after = {}
    if #remaining <= 1 then
        for _, member in ipairs(remaining) do
            member:SetAttribute("ComponentId", nil)
            member:SetAttribute("ComponentAnchorId", nil)
            table.insert(after, snapshot(member))
        end
    else
        local anchor = remaining[1]:GetAttribute("ComponentAnchorId")
        if anchor == model:GetAttribute("InstanceId") then
            anchor = remaining[1]:GetAttribute("InstanceId")
        end
        for _, member in ipairs(remaining) do
            member:SetAttribute("ComponentAnchorId", anchor)
            table.insert(after, snapshot(member))
        end
    end

    commitBatch(player, before, after)
    return true, "Primitive removed from component"
end

local function restore(player, data)
    local model = findOwned(player, data.instanceId)
    if not model then
        local reason
        model, reason = createFromTemplate(player, data.templateId, data.instanceId)
        if not model then return false, reason end
    end
    local entry = Registry.Get(data.templateId)
    if not entry then model:Destroy() return false, "Template unavailable" end
    local valid, reason = validState(player, entry, data)
    if not valid then
        if not model.Parent then model:Destroy() end
        return false, reason
    end

    local before = if model.Parent then snapshot(model) else nil
    applyState(model, data)

    local ignore={[model]=true}
    if data.componentId then
        for _,member in ipairs(components:Members(player,data.componentId)) do
            ignore[member]=true
        end
    end
    local opening=data.alignedOpeningId
        and findOwned(player,data.alignedOpeningId) or nil
    if intersectsConstructed(model,ignore,opening,
        if opening then data.instanceId else nil) then
        if before then
            applyState(model,before)
        else
            model:Destroy()
        end
        return false,"Undo/redo blocked by another piece"
    end

    model.Parent = folder
    return true
end

local function restoreMetadata(player,record,undo)
    local states=if undo then record.before else record.after
    if type(states)~="table" then return false,"Invalid metadata history" end
    local targets={}
    -- Validate the complete batch before changing ANY model.
    for _,state in ipairs(states) do
        local model=findOwned(player,state.instanceId)
        if not model or model:GetAttribute("TemplateId")~=state.templateId then
            return false,"A metadata member was deleted or replaced"
        end
        table.insert(targets,{model=model,state=state})
    end
    for _,entry in ipairs(targets) do
        local model,state=entry.model,entry.state
        model:SetAttribute("ComponentId",state.componentId)
        model:SetAttribute("ComponentAnchorId",state.componentAnchorId)
        model:SetAttribute("AssemblyId",state.assemblyId)
        model:SetAttribute("AssemblyName",state.assemblyName)
        model:SetAttribute("Grounded",state.grounded==true)
    end
    return true
end

local function applyRecord(player, record, undo)
    if record.kind == "Metadata" then
        return restoreMetadata(player,record,undo)
    end
    if record.kind == "JointConfig" then
        return mechanical:ApplyJointEdit(player,record,undo)
    end
    if record.kind == "Assembly" then
        return mechanical:ApplyHistory(player, record, undo, restoreBatch)
    end
    if record.kind == "Batch" then
        return restoreBatch(player, record, undo)
    end
    local target = if undo then record.before else record.after
    local other = if undo then record.after else record.before
    if target == nil then
        local model = findOwned(player, other.instanceId)
        if not model then return false, "Piece no longer exists" end
        model:Destroy()
        return true
    end
    return restore(player, target)
end

local function historyAction(player, isUndo)
    local state = historyFor(player)
    local source = if isUndo then state.undo else state.redo
    local destination = if isUndo then state.redo else state.undo
    local record = source[#source]
    if not record then return false, "Nothing to " .. (if isUndo then "undo" else "redo") end

    local ok, reason = applyRecord(player, record, isUndo)
    if not ok then return false, reason end

    table.remove(source)
    table.insert(destination, record)
    return true, if isUndo then "Undone" else "Redone"
end

local function handle(player, payload)
    if type(payload) ~= "table" or type(payload.action) ~= "string" then
        return { ok = false, message = "Invalid request" }
    end

    local action = payload.action
    -- Saving and loading are deliberate, separate GUI actions; never timer,
    -- departure, or server-shutdown callbacks.
    if action=="SavePlot" or action=="LoadPlot" then
        if not persistence or not plots:Get(player) then
            return {ok=false,message="Plot isn't ready"}
        end
        if simulation and simulation:IsRunning(player) then
            return {ok=false,message="Stop simulation before saving or loading"}
        end
        local ok,message=if action=="SavePlot"
            then persistence:Save(player) else persistence:Load(player)
        return {ok=ok==true,message=tostring(message or "")}
    end
    -- API outages must not prevent constructing on the currently owned
    -- plot. They ONLY disable saving, protecting the previous remote save.
    -- During an active load we block edits to avoid racing the swap.
    if not persistence or not plots:Get(player)
        or persistence.Busy[player]
        or player:GetAttribute("OPENWORKS_SaveState")=="Loading" then
        return {ok=false,message="Your plot is still loading"}
    end
    local alignmentAction = action == "Align"
    local mechanicalAction = action == "CreateRelation" or action == "RemoveRelation"
        or action == "FastenBolt"
        or action == "FitShaft" or action == "CreateGearMesh"
        or action == "AdjustJoint" or action == "PoseShaft"
        or action == "SetGrounded" or action == "GetMechanismInfo"
        or action == "CreateSpring" or action == "TuneSpring"
        or action == "CreateWeld" or action == "CreateBolt"
        or action == "CoupleHandCrank"
    local propertyAction=action=="AdjustJoint" or action=="TuneSpring"
    local simulationAction = action == "StartSimulation"
        or action == "BeginCrank"
        or action == "StopSimulation"
        or action == "PauseSimulation" or action == "ResetSimulation"
    local componentAction = action == "Group" or action == "Ungroup"
        or action == "TransformComponent" or action == "DuplicateComponent"
        or action == "DeleteComponent" or action == "RotateComponent"
        or action == "RotatePrimitiveWorld"
    local smartAction = action == "SmartMate"
    local assemblyAction=action=="CreateAssembly"
        or action=="UpdateAssembly"
    if action ~= "Place" and action ~= "Update" and action ~= "Delete"
        and action ~= "Undo" and action ~= "Redo"
        and not componentAction and not smartAction and not assemblyAction
        and not alignmentAction and not mechanicalAction
        and not simulationAction then
        return { ok = false, message = "Unknown action" }
    end
    if action == "GetMechanismInfo" then
        -- Read-only information is available even during simulation.
    elseif simulationAction then
        if action ~= "StopSimulation" and not hasEquippedTool(player,"Simulate") then
            return {ok=false,message="Equip Simulate to run a mechanism"}
        end
    elseif simulation and simulation:IsRunning(player)
        and not propertyAction then
        return { ok = false, message = "Stop simulation before changing construction" }
    elseif mechanicalAction then
        if propertyAction then
            if not hasEquippedTool(player,"Simulate") then
                return {ok=false,message="Use Simulate Properties to edit relationships"}
            end
            if simulation:IsRunning(player)
                and not simulation:HasRelationship(player,payload.relationId) then
                return {ok=false,message="Relation is not in the running mechanism"}
            end
        elseif action=="SetGrounded" then
            if not hasEquippedTool(player,"Simulate")
                and not hasEquippedTool(player,"Edit") then
                return {ok=false,message="Equip Simulate to ground a body"}
            end
        elseif action=="CreateWeld" then
            if not hasEquippedTool(player,"Weld") then
                return {ok=false,message="Equip Weld to designate a physical weld"}
            end
        elseif action~="GetMechanismInfo"
            and not hasEquippedTool(player,"Edit") then
            return {ok=false,message="Equip Edit to modify relationships"}
        end
    elseif assemblyAction then
        if not hasEquippedTool(player,"Assembly") then
            return {ok=false,message="Equip Assembly to create or edit assemblies"}
        end
    elseif componentAction or alignmentAction or smartAction then
        if not hasEquippedTool(player, "Edit") then
            return { ok = false, message = "Equip Edit to modify components" }
        end
    elseif not accessFor(player, action) then
        return { ok = false, message = "Equip Build or Edit" }
    end

    local now = os.clock()
    -- Wheel-fitting is a short, discrete, server-validated operation.
    -- Give it a slightly shorter cooldown than placement so a normal
    -- wheel notch doesn't feel missed, without disabling request throttling.
    local interval = if action == "FitShaft"
        then 0.035 else Config.MinActionInterval
    if now - (lastRequest[player] or 0) < interval then
        return { ok = false, message = "Try again" }
    end
    lastRequest[player] = now

    local ok,result,extra,detail=pcall(function()
        if action == "StartSimulation" then return simulation:Start(player, payload) end
        if action == "BeginCrank" then return simulation:BeginCrank(player,payload) end
        if action == "StopSimulation" then return simulation:Stop(player) end
        if action == "PauseSimulation" then return simulation:Pause(player) end
        if action == "ResetSimulation" then return simulation:Reset(player) end
        if action == "Place" then return place(player, payload) end
        if action == "Update" then return update(player, payload) end
        if action == "Delete" then return delete(player, payload) end
        if componentAction then return components:Handle(player, action, payload) end
        if alignmentAction then return alignmentService:Align(player, payload) end
        if action == "SmartMate" then
            return mechanical:SmartMate(player,payload,false)
        end
        if action == "CreateRelation" then return mechanical:Create(player, payload) end
        if action == "RemoveRelation" then return mechanical:Remove(player, payload) end
        if action == "FitShaft" then return mechanical:Fit(player, payload) end
        if action == "SetGrounded" then return components:SetGrounded(player, payload) end
        if action == "RotateComponent" then return components:RotateWorld(player, payload) end
        if action == "RotatePrimitiveWorld" then
            return rotatePrimitiveWorld(player,payload)
        end
        if action == "CreateGearMesh" then return mechanical:CreateGearMesh(player, payload) end
        if action=="FastenBolt" then
            return mechanical:FastenBolt(player,payload,false)
        end
        if action=="CreateSpring" then
            return mechanical:CreateSpring(player,payload)
        end
        if action=="TuneSpring" then
            return mechanical:TuneSpring(player,payload)
        end
        if action=="CreateWeld" then
            return mechanical:CreateWeld(player,payload)
        end
        if action=="CoupleHandCrank" then
            return mechanical:CoupleHandCrank(player,payload,false)
        end
        if action=="CreateBolt" then
            return false,"Use Build > Fasteners to drag a real bolt through the holes"
        end
        if action=="CreateAssembly" then
            return assemblies:Create(player,payload)
        end
        if action=="UpdateAssembly" then
            return assemblies:Update(player,payload)
        end
        if action == "AdjustJoint" then return mechanical:AdjustJoint(player, payload) end
        if action == "PoseShaft" then return mechanical:PoseShaft(player, payload) end
        if action == "GetMechanismInfo" then
            return simulation:Info(player, payload)
        end
        if action=="Undo" or action=="Redo" then
            return historyAction(player,action=="Undo")
        end
        return false,"Unsupported construction action"
    end)

    if not ok then
        warn("[OPENWORKS] Construction request error: " .. tostring(result))
        return { ok = false, message = "Construction error (check Output)" }
    end
    if result and propertyAction and simulation:IsRunning(player) then
        local relation=mechanical:OwnedRelation(player,payload.relationId)
        if relation then simulation:SyncRelationship(player,relation) end
    end
    local metadataOnly=action=="CreateAssembly" or action=="UpdateAssembly"
        or action=="Group" or action=="Ungroup"
        or action=="SetGrounded"
    if result and mechanical and not simulationAction
        and action~="GetMechanismInfo" and not metadataOnly then
        mechanical:RebuildRelations()
    end
    local message = tostring(extra or "")
    if result and action == "Place" then message = "Placed" end
    if result and action == "Update" then message = "Updated" end
    return {
        ok = result == true,
        message = if result and (action == "Group" or action == "DuplicateComponent")
            then "Component created" else message,
        instanceId = if result and action == "Place" then extra else nil,
        componentId = if result and (action == "Group" or action == "DuplicateComponent")
            then extra else nil,
        assemblyId=if result and assemblyAction then detail else nil,
    }
end

function Service.Start()
    plots=PlotService.new()
    GearLibrary.Ensure()
    FastenerLibrary.Ensure()
    HandCrankLibrary.Ensure()
    folder = workspace:FindFirstChild(Config.FolderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = Config.FolderName
        folder.Parent = workspace
    end

    components = ComponentService.new({
        folder = folder,
        Config = Config,
        Grid = Grid,
        Registry = Registry,
        findOwned = findOwned,
        ownedCount = ownedCount,
        snapshot = snapshot,
        createFromTemplate = createFromTemplate,
        validState = validState,
        applyState = applyState,
        nearPlayer = nearPlayer,
        intersectsConstructed = intersectsConstructed,
        commitBatch = commitBatch,
    })

    alignmentService = AlignmentService.new({
        folder = folder,
        Grid = Grid,
        Registry = Registry,
        findOwned = findOwned,
        nearPlayer = nearPlayer,
        snapshot = snapshot,
        applyState = applyState,
        validState = validState,
        intersectsConstructed = intersectsConstructed,
        commitRecord = commitRecord,
        commitBatch = commitBatch,
        commitMetadata=commitMetadata,
        components = components,
    })

    mechanical = MechanicalService.new({
        folder = folder,
        Grid = Grid,
        Registry = Registry,
        findOwned = findOwned,
        nearPlayer = nearPlayer,
        snapshot = snapshot,
        applyState = applyState,
        validState = validState,
        intersectsConstructed = intersectsConstructed,
        components = components,
        commitAssembly = commitAssembly,
        commitRecord = commitRecord,
        commitBatch = commitBatch,
        commitMetadata=commitMetadata,
        commitJointEdit = commitJointEdit,
        createFromTemplate = createFromTemplate,
    })

    assemblies=AssemblyService.new({
        folder=folder,
        findOwned=findOwned,
        nearPlayer=nearPlayer,
        snapshot=snapshot,
        applyState=applyState,
        commitBatch=commitBatch,
        commitMetadata=commitMetadata,
        mechanical=mechanical,
    })

    simulation = SimulationService.new({
        folder = folder,
        findOwned = findOwned,
        nearPlayer = nearPlayer,
        mechanical = mechanical,
    })
    persistence=PlotPersistence.new({
        folder=folder,
        plots=plots,
        config=Config,
        grid=Grid,
        registry=Registry,
        mechanical=mechanical,
        assemblies=assemblies,
        snapshot=snapshot,
        applyState=applyState,
        createFromTemplate=createFromTemplate,
        histories=histories,
    })

    local function initializePlayer(player)
        local plot,why=plots:Assign(player)
        if not plot then
            warn("[OPENWORKS] Plot assignment failed for "..player.Name..": "..tostring(why))
            player:Kick("All OPENWORKS plots are occupied")
            return
        end
        persistence:Status(player,"Loading","Loading last manually saved plot")
        simulation:SetStatus(player,false)
        player.CharacterAdded:Connect(function(character)
            if simulation:IsRunning(player) then simulation:Stop(player) end
            plots:Spawn(player,character)
        end)
        if player.Character then plots:Spawn(player,player.Character) end
        task.spawn(function()
            local ok,message=persistence:Load(player)
            if not ok then
                warn("[OPENWORKS] Plot load blocked for "..player.Name..": "..
                    tostring(message))
            end
        end)
    end
    Players.PlayerAdded:Connect(initializePlayer)
    for _, present in ipairs(Players:GetPlayers()) do initializePlayer(present) end

    -- The gallery is an Edit-mode inspection aid, never buildable world geometry.
    -- This only moves it during Play; the Studio place remains unchanged.
    local gallery = workspace:FindFirstChild(Config.GalleryName)
    if gallery then
        gallery.Parent = game:GetService("ServerStorage")
    end

    local oldRemote = ReplicatedStorage:FindFirstChild(Config.RequestName)
    if oldRemote then oldRemote:Destroy() end

    remote = Instance.new("RemoteFunction")
    remote.Name = Config.RequestName
    remote.OnServerInvoke = handle
    remote.Parent = ReplicatedStorage

    -- High-frequency manual input is deliberately separate from throttled
    -- construction requests. Only a validated Simulate player with an
    -- active, server-authorized hand crank can provide torque.
    local oldCrankEvent=ReplicatedStorage:FindFirstChild("OPENWORKS_CrankControl")
    if oldCrankEvent then oldCrankEvent:Destroy() end
    local crankEvent=Instance.new("RemoteEvent")
    crankEvent.Name="OPENWORKS_CrankControl"
    crankEvent.Parent=ReplicatedStorage
    crankEvent.OnServerEvent:Connect(function(player,crankId,speed,dragging,release)
        if not hasEquippedTool(player,"Simulate") then return end
        if type(crankId)~="string" or #crankId>64 then return end
        simulation:InputCrank(player,crankId,speed,dragging,release)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if simulation then simulation:ClearPlayer(player) end
        if assemblies then assemblies:ClearPlayer(player) end
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
                model:Destroy()
            end
        end
        if mechanical then mechanical:ClearPlayer(player) end
        if persistence then persistence:Clear(player) end
        if plots then plots:Release(player) end
        histories[player] = nil
        lastRequest[player] = nil
    end)

    print("[OPENWORKS] ConstructionService ready: isolated plots / manual saves / relationships")
end

return Service
