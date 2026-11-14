--!strict
-- Server-authoritative Phase 02 construction. Studio prebaked geometry only.
-- Requests never contain trusted instances or arbitrary physical dimensions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Registry = require(construction:WaitForChild("PrimitiveRegistry"))
local Grid = require(construction:WaitForChild("GridMath"))
local Bore = require(construction:WaitForChild("BoreClearance"))
local Alignment = require(construction:WaitForChild("AlignmentMath"))
local MultiFit = require(construction:WaitForChild("MultiFitMath"))
local Smart = require(construction:WaitForChild("SmartPlacement"))
local FitOrigin = require(construction:WaitForChild("FitOrigin"))
local Config = require(construction:WaitForChild("BuildConfig"))
local ComponentService = require(script.Parent:WaitForChild("ComponentService"))
local ComponentBankService = require(script.Parent:WaitForChild("ComponentBankService"))
local AlignmentService = require(script.Parent:WaitForChild("AlignmentService"))
local MechanicalService = require(script.Parent:WaitForChild("MechanicalService"))
local SimulationService = require(script.Parent:WaitForChild("UnifiedSimulationService"))
local GearLibrary = require(script.Parent:WaitForChild("GearLibrary"))
local ProceduralPrefabLibrary = require(construction:WaitForChild("ProceduralPrefabLibrary"))
local PulleyLibrary = require(script.Parent:WaitForChild("PulleyLibrary"))
local FastenerLibrary = require(script.Parent:WaitForChild("FastenerLibrary"))
local HandCrankLibrary = require(script.Parent:WaitForChild("HandCrankLibrary"))
local ShaftLibrary = require(script.Parent:WaitForChild("ShaftLibrary"))
local CompactHoleLibrary = require(script.Parent:WaitForChild("CompactHoleLibrary"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local PlotPersistence = require(script.Parent:WaitForChild("PlotPersistence"))
local RotationMath = require(construction:WaitForChild("RotationMath"))
local HandCrankMath = require(construction:WaitForChild("HandCrankMath"))

local DEFAULT_METAL_COLOR = Color3.fromRGB(78, 83, 91)
local MaterialCatalog=require(construction:WaitForChild("MaterialCatalog"))
local PaintCatalog=require(construction:WaitForChild("PaintCatalog"))
local PrefabCollision=require(construction:WaitForChild("PrefabCollision"))

local Service = {}
local folder
local remote
local histories = {}
local lastRequest = {}
local components
local componentBank
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
    if action=="Undo" or action=="Redo" then
        -- Assembly edits commit the same safe metadata history as Edit.
        -- Allow undo/redo without equipping an unrelated construction tool.
        return hasEquippedTool(player,"AssemblySimulation")
            or hasEquippedTool(player,"Mechanics")
            or hasEquippedTool(player,"Build")
            or hasEquippedTool(player,"Edit")
    end
    -- New authored primitives belong to Build. Edit can create a duplicate
    -- ONLY by referencing an existing, server-owned source primitive.
    -- The dedicated DuplicatePrimitive handler reconstructs trusted state.
    return if action=="Place" then hasEquippedTool(player,"Build")
        else hasEquippedTool(player,"Edit")
end

local function nearPlayer(player, position)
    -- OPENWORKS is a permanent plot-bound free camera. The invisible
    -- immobile avatar is not a meaningful proximity reference.
    -- Ownership, equipped tool and full owned-plot bounds are checked
    -- independently; client camera position is NOT trusted by the server.
    return plots~=nil and plots:Contains(player,position)
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
        fitPivotLocal=model:GetAttribute("FitPivotLocal"),
        componentFitPivotLocal=model:GetAttribute("ComponentFitPivotLocal"),
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
        materialId = model:GetAttribute("ConstructionMaterial") or "Steel",
        paintFinish=model:GetAttribute("PaintFinish") or "Factory",
        paintColorHex=model:GetAttribute("PaintColorHex"),
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
            PrefabCollision.Configure(descendant)
            local isHidden=descendant:GetAttribute("GearPivotOnly")==true
                or descendant:GetAttribute("OpenworksCollisionMode")=="PivotOnly"
                or descendant:GetAttribute("OpenworksCollisionMode")=="Proxy"
            descendant.Reflectance=if isHidden then 0 else 0.045
        end
    end

    MaterialCatalog.Apply(model,"Steel")
    PaintCatalog.Apply(model,"Factory",nil)
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
            local intendedGear=target and GearMath.AutoMeshable(candidate,target)
            -- A gear's pivot has no metal in its center. A valid coaxial
            -- hub fit may have harmless faceted rim broad-phase contacts.
            -- Only exempt the explicitly chosen gear/shaft pair, after
            -- server-verifying actual circular bore clearance.
            local intendedHub=target and target==opening and shaftId
                and candidate:GetAttribute("InstanceId")==shaftId
                and Smart.HubFits(candidate,target)
            local approvedFit=target and fitMap and fitMap[candidate]
                and fitMap[candidate][target] == true
            if not intendedBore and not intendedGear
                and not intendedHub and not approvedFit then
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
    local isCylinder = (id=="shaft" or string.find(id,"cylinder",1,true))
        and not string.find(id,"halfcylinder",1,true)
    if proposed.fitPrecision == true and not isCylinder then
        return false, "Fine-fit precision is reserved for full Cylinder shafts"
    end
    local validSize=if HandCrankMath.IsCrank(entry.Model)
        then HandCrankMath.ValidSize(original.Size,proposed.size)
        else Grid.ValidSize(original.Size, proposed.size,
            entry.ResizeMode, proposed.fitPrecision == true,
            proposed.numericPrecision == true)
    if not validSize then
        return false, "Size does not match allowed Unit increments"
    end

    if (proposed.fitPivotLocal~=nil and not FitOrigin.Valid(proposed.fitPivotLocal))
        or (proposed.componentFitPivotLocal~=nil
            and not FitOrigin.Valid(proposed.componentFitPivotLocal)) then
        return false,"Invalid fitting origin offset"
    end

    -- Only size increments are quantized. A valid world-space position
    -- is no longer required to coincide with ANY grid lattice.
    -- Exact surface support and component offsets must not be rejected.
    return true
end

local function applyState(model, data)
    if HandCrankMath.IsCrank(model) then
        HandCrankMath.ApplySize(model,data.size)
    else
        model.PrimaryPart.Size = data.size
    end
    local rotation = if typeof(data.orientation) == "CFrame"
        then data.orientation.Rotation else Grid.Rotation(data.steps)
    model:PivotTo(CFrame.new(data.position) * rotation)
    model:SetAttribute("RotX", data.steps.x)
    model:SetAttribute("RotY", data.steps.y)
    model:SetAttribute("RotZ", data.steps.z)
    model:SetAttribute("ComponentId", data.componentId)
    model:SetAttribute("ComponentAnchorId", data.componentAnchorId)
    model:SetAttribute("FitPivotLocal",data.fitPivotLocal)
    model:SetAttribute("ComponentFitPivotLocal",data.componentFitPivotLocal)
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
    MaterialCatalog.Apply(model,if MaterialCatalog.IsValid(data.materialId)
        then data.materialId else "Steel")
    PaintCatalog.Apply(model,if PaintCatalog.IsValidFinish(data.paintFinish)
        then data.paintFinish else "Factory",data.paintColorHex)
end


local function commitRecord(player, before, after, preserveRelations)
    local state=historyFor(player)
    local prior=if before then {before} else {}
    local nextStates=if after then {after} else {}
    local disconnected=if mechanical and not preserveRelations
        then mechanical:DisconnectMoved(player,prior,nextStates) else {}
    if #disconnected>0 then
        table.insert(state.undo,{
            kind="Assembly",before=prior,after=nextStates,
            relations=disconnected,removed=true,
        })
    else
        table.insert(state.undo,{before=before,after=after})
    end
    if #state.undo>Config.UndoLimit then table.remove(state.undo,1) end
    table.clear(state.redo)
end

local function commitBatch(player,before,after,preserveRelations)
    local state=historyFor(player)
    local disconnected=if mechanical and not preserveRelations
        then mechanical:DisconnectMoved(player,before,after) else {}
    if #disconnected>0 then
        table.insert(state.undo,{
            kind="Assembly",before=before,after=after,
            relations=disconnected,removed=true,
        })
    else
        table.insert(state.undo,{kind="Batch",before=before,after=after})
    end
    if #state.undo>Config.UndoLimit then table.remove(state.undo,1) end
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
    local created=if batch then relation or {} else if relation then {relation} else {}
    local exemptions={}
    if removed~=true then
        for _,spec in ipairs(created) do
            exemptions[spec.relationId]=true
        end
        for _,edit in ipairs(relationEdits or {}) do
            exemptions[edit.before.relationId]=true
        end
    end
    local disconnected=if mechanical and removed~=true
        then mechanical:DisconnectMoved(player,before,after,exemptions) else {}
    table.insert(state.undo, {
        kind = "Assembly",
        before = before,
        after = after,
        relation = if batch then nil else relation,
        relations = if batch then relation else nil,
        relationEdits=relationEdits,
        disconnected=disconnected,
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

-- Build and Edit-copy use one server-authoritative attachment and history
-- transaction. Copy never inherits old relationships; new fits are explicit.
local function finalizeNewPrimitive(player,model,payload)
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

local function place(player, payload)
    if type(payload.templateId) ~= "string" then return false, "Missing template ID" end
    local entry = Registry.Get(payload.templateId)
    if not entry then return false, "Unknown primitive" end
    local template = entry.Model.PrimaryPart
    if HandCrankMath.IsCrank(entry.Model) and typeof(payload.size)=="Vector3"
        and (payload.size-template.Size).Magnitude>0.001 then
        return false,"Hand crank size is set by coupling to a shaft"
    end
    local proposed = {
        position = payload.position,
        steps = payload.steps,
        size = payload.size or (template and template.Size),
        materialId=if MaterialCatalog.IsValid(payload.materialId)
            then payload.materialId else "Steel",
        paintFinish=if PaintCatalog.IsValidFinish(payload.paintFinish)
            then payload.paintFinish else "Factory",
        paintColorHex=PaintCatalog.NormalizeHex(payload.paintColorHex),
        orientation = if payload.autoMate
            and (payload.autoMate.kind=="BoltHole"
                or payload.autoMate.kind=="Bore"
                or payload.autoMate.kind=="CrankCoupling"
                or payload.autoMate.kind=="Hub")
            then payload.orientation else nil,
        freePosition=payload.autoMate and (payload.autoMate.kind=="BoltHole"
            or payload.autoMate.kind=="Bore"
            or payload.autoMate.kind=="CrankCoupling"
                or payload.autoMate.kind=="Hub"),
    }
    proposed.resizePrecision = Grid.HasFractionalSize(proposed.size)
    proposed.fitPrecision = payload.templateId=="Shaft"
    proposed.numericPrecision = payload.numericPrecision == true
    proposed.fitPivotLocal=payload.fitPivotLocal

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

    return finalizeNewPrimitive(player,model,payload)
end

-- Edit-mode F / Ctrl+D copies an existing owned primitive. NEVER route
-- this through Build-only Place, which rejects Edit tool authority. The
-- source is server-resolved; clients cannot forge template/size/material
-- overrides or inherit another construction's mechanical relationships.
local function duplicatePrimitive(player,payload)
    if type(payload.sourceId)~="string" then
        return false,"Select a primitive in Edit before duplicating"
    end
    local source=findOwned(player,payload.sourceId)
    if not source or not source.PrimaryPart then
        return false,"Selected primitive no longer exists"
    end
    local original=snapshot(source)
    local entry=Registry.Get(original.templateId)
    if not entry then return false,"Original primitive template is unavailable" end

    local duplicate=table.clone(original)
    duplicate.position=payload.position
    duplicate.steps=payload.steps
    -- The exact visible preview pose is authoritative only for orientation;
    -- size, material, finish and geometry always come from the owned source.
    duplicate.orientation=if typeof(payload.orientation)=="CFrame"
        then payload.orientation.Rotation else Grid.Rotation(original.steps)
    duplicate.freePosition=true
    duplicate.componentId=nil
    duplicate.componentAnchorId=nil
    duplicate.componentFitPivotLocal=nil
    duplicate.assemblyId=nil
    duplicate.assemblyName=nil
    duplicate.grounded=false
    duplicate.alignedOpeningId=nil
    duplicate.alignedOffsetU=0
    duplicate.shaftRollDegrees=0
    local valid,reason=validState(player,entry,duplicate)
    if not valid then return false,reason end

    local model,why=createFromTemplate(player,original.templateId)
    if not model then return false,why end
    applyState(model,duplicate)
    -- Fitted copies use the same collision/clearance validation as fresh
    -- Build placements, then authorize a real new joint atomically.
    if payload.autoMate==nil and intersectsConstructed(model) then
        model:Destroy()
        return false,"Duplicate intersects existing geometry"
    end
    model.Parent=folder
    return finalizeNewPrimitive(player,model,payload)
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
        fitPivotLocal=model:GetAttribute("FitPivotLocal"),
        componentFitPivotLocal=model:GetAttribute("ComponentFitPivotLocal"),
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
        materialId=model:GetAttribute("ConstructionMaterial") or "Steel",
        paintFinish=model:GetAttribute("PaintFinish") or "Factory",
        paintColorHex=model:GetAttribute("PaintColorHex"),
    }
    local before=snapshot(model)
    local crankCouplings=if Alignment.IsShaft(model)
        then mechanical:CoupledCranks(player,model) else {}
    -- Moving a coupled shaft independently now DISCONNECTS its rigid weld.
    -- Diameter-only fitting can still resize an attached crank in place.
    local crankDetaching=false
    if #crankCouplings>0 and typeof(proposed.size)=="Vector3"
        and typeof(proposed.position)=="Vector3"
        and Grid.ValidSteps(proposed.steps) then
        local desiredRotation=if typeof(proposed.orientation)=="CFrame"
            then proposed.orientation.Rotation else Grid.Rotation(proposed.steps)
        local existing=model:GetPivot()
        crankDetaching=math.abs(proposed.size.X-before.size.X)>0.001
            or (proposed.position-before.position).Magnitude>0.001
            or (desiredRotation.RightVector-existing.RightVector).Magnitude>0.001
            or (desiredRotation.UpVector-existing.UpVector).Magnitude>0.001
    end
    if HandCrankMath.IsCrank(model)
        and typeof(proposed.size)=="Vector3"
        and (proposed.size-before.size).Magnitude>0.001 then
        return false,"Disconnect and recouple to change the crank output diameter"
    end
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
            -- Normal Edit movement may pull a shaft out of a bearing.
            -- The construction history disconnects the non-spring joint
            -- and clears stale authored alignment in the same transaction.
            proposed.alignedOpeningId=nil
            proposed.alignedOffsetU=0
            proposed.shaftRollDegrees=0
            model:SetAttribute("AlignedOpeningId",nil)
            model:SetAttribute("AlignedOffsetU",0)
            model:SetAttribute("ShaftRollDegrees",0)
        end
    end

    local ignore={[model]=true}
    if model:GetAttribute("ComponentId") then
        for _,member in ipairs(components:Members(
            player,model:GetAttribute("ComponentId"))) do
            ignore[member]=true
        end
    end
    local fitMap=nil
    if stillAligned and opening then
        -- Length/diameter edits must continue to recognize OTHER genuine
        -- hinge lugs penetrated by the same shaft, not just the primary.
        local all={}
        for _,candidate in ipairs(folder:GetChildren()) do
            if candidate:IsA("Model")
                and candidate:GetAttribute("OwnerUserId")==player.UserId
                and candidate~=model then table.insert(all,candidate) end
        end
        local stations=MultiFit.StationarySet({model},opening,all)
        local matches=MultiFit.Find({model},stations)
        if matches then
            local valid=MultiFit.Unique(matches,before.instanceId,
                opening:GetAttribute("InstanceId"))
            fitMap=MultiFit.AllowMap(valid)
        end
    end
    if intersectsConstructed(model,ignore,
        if stillAligned then opening else nil,
        if stillAligned then before.instanceId else nil,fitMap) then
        applyState(model,before)
        return false,"Edit intersects another piece"
    end

    local crankBefore,crankAfter={},{}
    if #crankCouplings>0 and not crankDetaching then
        local reason
        crankBefore,crankAfter,reason=mechanical:ResizeCoupledCranks(player,model)
        if not crankBefore then
            applyState(model,before)
            return false,reason or "Attached crank could not be resized"
        end
    end

    local after=snapshot(model)
    if #crankBefore>0 then
        local prev={before}
        local nextStates={after}
        for i,old in ipairs(crankBefore) do
            table.insert(prev,old)
            table.insert(nextStates,crankAfter[i])
        end
        commitBatch(player,prev,nextStates)
    else
        commitRecord(player,before,after)
    end
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

-- Move a COMPLETE authored component or named Assembly ONLY on world Y.
-- One server-validated batch and one undo record; never trust client
-- positions, arbitrary membership lists, or per-member offsets.
local function verticalMove(player,payload)
    if type(payload)~="table"
        or (payload.direction~=1 and payload.direction~=-1) then
        return false,"Choose an arrow direction"
    end
    local axis=payload.axis or "Y"
    if axis~="X" and axis~="Y" and axis~="Z" then
        return false,"Nudge only along world X, Y or Z"
    end
    local selected={}
    local scope=payload.scope
    local id=payload.id
    if scope=="Primitives" then
        -- The caller's exact Shift-selection; one transaction, no grouping.
        local ids=payload.ids
        if type(ids)~="table" or #ids<2 or #ids>128 then
            return false,"Select 2–128 distinct primitives"
        end
        local seen={}
        for _,primitiveId in ipairs(ids) do
            if type(primitiveId)~="string" or #primitiveId==0
                or #primitiveId>64 or seen[primitiveId] then
                return false,"Invalid or duplicate nudge selection"
            end
            seen[primitiveId]=true
            local model=findOwned(player,primitiveId)
            if not model or model:GetAttribute("ComponentId") then
                return false,"Multi-nudge requires independent primitives"
            end
            table.insert(selected,model)
        end
    else
        if type(id)~="string" or #id==0 or #id>64 then
            return false,"Select an existing primitive, component or assembly"
        end
        if scope=="Component" then
            selected=components:Members(player,id)
        elseif scope=="Assembly" then
            selected=assemblies:Members(player,id)
        elseif scope=="Primitive" then
            -- A deep-selected grouped member can move by itself; its
            -- ComponentId is preserved and incompatible joints disconnect.
            local model=findOwned(player,id)
            if model then selected={model} end
        else
            return false,"Invalid nudge selection scope"
        end
    end
    if #selected==0 or #selected>128 then
        return false,"Selection unavailable or too large"
    end
    -- All Y movement is quantized, with an optional Shift fine-step.
    -- The server chooses the actual increment, not the client.
    local fine=payload.fine==true
    local step=if fine then 0.05 else 0.25
    local delta=(if axis=="X" then Vector3.xAxis
        elseif axis=="Y" then Vector3.yAxis else Vector3.zAxis)
        *payload.direction*step
    local before,after,ignored={}, {}, {}
    for _,model in ipairs(selected) do
        if not model.PrimaryPart or model.Parent~=folder then
            return false,"A selected primitive no longer exists"
        end
        ignored[model]=true
        local old=snapshot(model)
        local nextState=table.clone(old)
        nextState.position=old.position+delta
        nextState.freePosition=true
        local entry=Registry.Get(old.templateId)
        if not entry then return false,"Missing construction template" end
        local ok,reason=validState(player,entry,nextState)
        if not ok then return false,reason end
        table.insert(before,old)
        table.insert(after,nextState)
    end
    -- Validate full target poses as a transaction. Temporarily move all
    -- members so collision checks see the final positions; always roll
    -- back the WHOLE selection on failure.
    for i,model in ipairs(selected) do
        applyState(model,after[i])
    end
    local intersects=false
    for _,model in ipairs(selected) do
        if intersectsConstructed(model,ignored) then
            intersects=true
            break
        end
    end
    if intersects then
        for i,model in ipairs(selected) do
            applyState(model,before[i])
        end
        return false,"Nudge intersects another construction"
    end
    commitBatch(player,before,after)
    return true,"Moved "..tostring(#selected).." primitives "
        ..tostring(step).." studs on "..axis
end

local function setMaterial(player,payload)
    if type(payload)~="table"
        or not MaterialCatalog.IsValid(payload.materialId) then
        return false,"Choose a supported construction material"
    end
    local id=payload.id
    if type(id)~="string" or #id>64 then return false,"Select a part" end
    local members
    if payload.scope=="Component" then
        members=components:Members(player,id)
    elseif payload.scope=="Primitive" then
        local model=findOwned(player,id)
        members=if model then {model} else {}
    else
        return false,"Material applies to a primitive or component"
    end
    if #members==0 then return false,"No owned material targets" end
    local before,after={},{}
    for _,model in ipairs(members) do
        local old=snapshot(model)
        local nextState=table.clone(old)
        nextState.materialId=payload.materialId
        table.insert(before,old)
        table.insert(after,nextState)
    end
    for i,model in ipairs(members) do applyState(model,after[i]) end
    commitBatch(player,before,after)
    return true,"Applied "..payload.materialId.." to "..#members.." primitives"
end

local function setPaint(player,payload)
    if type(payload)~="table"
        or not PaintCatalog.IsValidFinish(payload.paintFinish)
        or (payload.paintColorHex~=nil
            and PaintCatalog.NormalizeHex(payload.paintColorHex)==nil) then
        return false,"Choose a valid finish and six-digit HEX color"
    end
    local id=payload.id
    if type(id)~="string" or #id>64 then return false,"Select a part" end
    local members
    if payload.scope=="Component" then
        members=components:Members(player,id)
    elseif payload.scope=="Primitive" then
        local target=findOwned(player,id)
        members=if target then {target} else {}
    else
        return false,"Paint applies to a primitive or component"
    end
    if #members==0 then return false,"No owned paint targets" end
    local before,after={},{}
    for _,model in ipairs(members) do
        local old=snapshot(model)
        local nextState=table.clone(old)
        nextState.paintFinish=payload.paintFinish
        nextState.paintColorHex=PaintCatalog.NormalizeHex(payload.paintColorHex)
        table.insert(before,old)
        table.insert(after,nextState)
    end
    for i,model in ipairs(members) do applyState(model,after[i]) end
    commitBatch(player,before,after)
    return true,"Applied "..payload.paintFinish.." paint to "
        ..tostring(#members).." primitives"
end

-- A universal editable alignment origin exists for BOTH primitive and
-- component selections. Never move the physics root or manufacture a joint.
-- Validate that the selected point belongs to actual owned component geometry.
local function setFitPivot(player,payload)
    if type(payload)~="table" or (payload.scope~="Primitive"
        and payload.scope~="Component") or type(payload.id)~="string"
        or #payload.id>64 then
        return false,"Select a primitive or component before editing its origin"
    end
    local members,anchor
    if payload.scope=="Component" then
        members=components:Members(player,payload.id)
        if #members<2 then return false,"Select a registered component" end
        anchor=FitOrigin.ComponentAnchor(members)
    else
        anchor=findOwned(player,payload.id)
        members=if anchor then {anchor} else {}
    end
    if not anchor then return false,"Component anchor is unavailable" end
    if not nearPlayer(player,anchor:GetPivot().Position) then
        return false,"Move closer to the selected origin"
    end
    local prior=snapshot(anchor)
    local localPoint=nil
    if payload.reset~=true then
        if typeof(payload.position)~="Vector3"
            or not Grid.ValidPosition(payload.position)
            or type(payload.hitId)~="string" then
            return false,"Look at a surface on the selected construction"
        end
        local hitModel=nil
        for _,member in ipairs(members) do
            if member:GetAttribute("InstanceId")==payload.hitId then
                hitModel=member
                break
            end
        end
        if not hitModel then
            return false,"The pivot point must belong to the selection"
        end
        if not nearPlayer(player,payload.position) then
            return false,"The pivot is outside the plot"
        end
        local inside=false
        for _,part in ipairs(hitModel:GetDescendants()) do
            if part:IsA("BasePart") and part.CanQuery
                and part:GetAttribute("GearPivotOnly")~=true then
                local p=part.CFrame:PointToObjectSpace(payload.position)
                local half=part.Size*0.5+Vector3.one*0.10
                if math.abs(p.X)<=half.X and math.abs(p.Y)<=half.Y
                    and math.abs(p.Z)<=half.Z then
                    inside=true
                    break
                end
            end
        end
        if not inside then
            return false,"Choose a point on the selected physical surface"
        end
        localPoint=anchor:GetPivot():PointToObjectSpace(payload.position)
        if not FitOrigin.Valid(localPoint) then
            return false,"Pivot offset exceeds safe construction range"
        end
    end
    local attribute=if payload.scope=="Component"
        then "ComponentFitPivotLocal" else "FitPivotLocal"
    anchor:SetAttribute(attribute,localPoint)
    commitMetadata(player,{prior},{snapshot(anchor)})
    return true,if payload.reset then "Alignment origin reset to default"
        else "Alignment origin placed • move to align from that point"
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
        model:SetAttribute("FitPivotLocal",state.fitPivotLocal)
        model:SetAttribute("ComponentFitPivotLocal",state.componentFitPivotLocal)
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
    -- Manual Save/Load is available alongside periodic server autosaves.
    -- Only authored geometry is persisted, never temporary physics clones.
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
        or action == "CoupleHandCrank" or action == "TuneBearingMotor"
        or action == "CreateBelt" or action == "RemoveBelt"

    local propertyAction=action=="AdjustJoint" or action=="TuneSpring"
        or action=="TuneBearingMotor"
    local simulationAction = action == "StartSimulation"
        or action == "BeginCrank"
        or action == "BeginRack"
        or action == "StopSimulation"
        or action == "PauseSimulation" or action == "ResetSimulation"
    local materialAction=action=="SetMaterial" or action=="SetPaint"
    local fitOriginAction=action=="SetFitPivot"
    local bankAction=action=="ListComponentBank" or action=="GetComponentBank"
        or action=="RegisterComponentBank" or action=="PlaceComponentBank"
        or action=="RemoveComponentBank"
    local verticalAction=action=="VerticalMove"
    local componentAction = action == "Group" or action == "Ungroup"
        or action == "TransformComponent" or action == "DuplicateComponent"
        or action == "DeleteComponent" or action == "RotateComponent"
        or action == "RotatePrimitiveWorld"
    local smartAction = action == "SmartMate"
    local assemblyAction=action=="CreateAssembly"
        or action=="UpdateAssembly"
    if action ~= "Place" and action ~= "DuplicatePrimitive"
        and action ~= "Update" and action ~= "Delete"
        and action ~= "Undo" and action ~= "Redo"
        and not componentAction and not smartAction and not assemblyAction
        and not verticalAction and not materialAction and not fitOriginAction
        and not bankAction
        and not alignmentAction and not mechanicalAction
        and not simulationAction then
        return { ok = false, message = "Unknown action" }
    end
    if action == "GetMechanismInfo" then
        -- Read-only information is available even during simulation.
    elseif simulationAction then
        if action ~= "StopSimulation" and not hasEquippedTool(player,"AssemblySimulation") then
            return {ok=false,message="Equip Simulate to run a mechanism"}
        end
    elseif simulation and simulation:IsRunning(player) then
        return { ok = false, message = "Stop simulation before changing construction" }
    elseif mechanicalAction then
        if propertyAction or action=="RemoveRelation" then
            -- Contextual right-click editing and relationship removal are
            -- available from any OPENWORKS
            -- native tool. Ownership, relation type, plot and simulation
            -- checks remain server-authoritative in MechanicalService.
            if not hasEquippedTool(player,"Mechanics")
                and not hasEquippedTool(player,"Build")
                and not hasEquippedTool(player,"Edit")
                and not hasEquippedTool(player,"AssemblySimulation") then
                return {ok=false,message="Equip an OPENWORKS tool to edit relationships"}
            end
        elseif action=="SetGrounded" then
            if not hasEquippedTool(player,"AssemblySimulation") then
                return {ok=false,message="Use Assembly & Simulation to ground a body"}
            end
        elseif action=="FitShaft" or action=="PoseShaft" then
            if not hasEquippedTool(player,"Mechanics")
                and not hasEquippedTool(player,"Edit") then
                return {ok=false,message="Equip Edit (2) or Mechanics to fine-fit a shaft"}
            end
        elseif action=="CreateWeld" then
            if not hasEquippedTool(player,"Mechanics") then
                return {ok=false,message="Use Mechanics / Connect to designate a weld"}
            end
        elseif action~="GetMechanismInfo"
            and not hasEquippedTool(player,"Mechanics") then
            return {ok=false,message="Use Mechanics to modify relationships"}
        end
    elseif bankAction then
        local writing=action=="RegisterComponentBank"
            or action=="RemoveComponentBank"
        local allowed=if writing then hasEquippedTool(player,"Edit")
            else hasEquippedTool(player,"Build")
                or hasEquippedTool(player,"Edit")
        if action=="PlaceComponentBank" then
            allowed=hasEquippedTool(player,"Build")
        end
        if not allowed then
            return {ok=false,message=if writing then "Equip Edit to save components"
                else "Equip Build to place saved components"}
        end
    elseif fitOriginAction then
        if not hasEquippedTool(player,"Edit") then
            return {ok=false,message="Equip Edit to change alignment origins"}
        end
    elseif materialAction then
        if not hasEquippedTool(player,"Edit")
            and not hasEquippedTool(player,"Build")
            and not hasEquippedTool(player,"Mechanics")
            and not hasEquippedTool(player,"AssemblySimulation") then
            return {ok=false,message="Equip an OPENWORKS tool to edit appearance"}
        end
    elseif verticalAction then
        if (payload.scope=="Assembly" and not hasEquippedTool(player,"AssemblySimulation"))
            or (payload.scope~="Assembly" and not hasEquippedTool(player,"Edit")) then
            return {ok=false,message="Use Edit for components or Assembly & Simulation for assemblies"}
        end
    elseif assemblyAction then
        if not hasEquippedTool(player,"AssemblySimulation") then
            return {ok=false,message="Use Assembly Editor to create or edit assemblies"}
        end
    elseif componentAction or alignmentAction or smartAction then
        if componentAction and not hasEquippedTool(player,"Edit") then
            return {ok=false,message="Use Edit to modify construction"}
        end
        if smartAction and not hasEquippedTool(player,"Build")
            and not hasEquippedTool(player,"Edit") then
            -- In Mechanics, only explicit free coaxial fits or rigid hub
            -- mounts are allowed. Real geometry remains server-validated.
            local mode=payload.mateKind
            local kind=payload.relationKind
            local approved=(mode=="Bore" and kind=="FreeFit")
                or (mode=="Hub" and (kind=="Weld" or kind=="Rigid"))
            if not approved or not hasEquippedTool(player,"Mechanics") then
                return {ok=false,message="Equip Edit to fit authored geometry"}
            end
        end
        if alignmentAction and not hasEquippedTool(player,"Edit")
            and not hasEquippedTool(player,"Mechanics") then
            return {ok=false,message="Use Edit or Mechanics to align objects"}
        end
    elseif not accessFor(player, action) then
        return { ok = false, message=if action=="DuplicatePrimitive"
            then "Equip Edit (2) to duplicate an existing primitive"
            else "Equip Build" }
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
        if action == "BeginRack" then return simulation:BeginRack(player,payload) end
        if action == "StopSimulation" then return simulation:Stop(player) end
        if action == "PauseSimulation" then return simulation:Pause(player) end
        if action == "ResetSimulation" then return simulation:Reset(player) end
        if bankAction then return componentBank:Handle(player,action,payload) end
        if action=="SetFitPivot" then return setFitPivot(player,payload) end
        if action == "Place" then return place(player, payload) end
        if action == "DuplicatePrimitive" then return duplicatePrimitive(player,payload) end
        if action == "VerticalMove" then return verticalMove(player,payload) end
        if action == "SetMaterial" then return setMaterial(player,payload) end
        if action == "SetPaint" then return setPaint(player,payload) end
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
        if action == "CreateBelt" then return mechanical:CreateBelt(player,payload) end
        if action == "RemoveBelt" then return mechanical:RemoveBelt(player,payload) end
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
        if action == "TuneBearingMotor" then
            return mechanical:TuneBearingMotor(player,payload)
        end
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
    local metadataOnly=bankAction or action=="SetFitPivot"
        or action=="CreateAssembly" or action=="UpdateAssembly"
        or action=="Group" or action=="Ungroup"
        or action=="SetGrounded"
    -- Mark dirty BEFORE optional geometry rebuild: a rebuild error must
    -- not silently discard the already-committed edit from autosaving.
    if result and persistence and not simulationAction
        and (not bankAction or action=="PlaceComponentBank")
        and action~="GetMechanismInfo" then
        persistence:MarkDirty(player)
    end
    if result and mechanical and not simulationAction
        and action~="GetMechanismInfo" and not metadataOnly then
        mechanical:RebuildRelations()
    end
    local message = tostring(extra or "")
    if result and action == "Place" then message = "Placed" end
    if result and action == "DuplicatePrimitive" then message = "Duplicated" end
    if result and action == "Update" then message = "Updated" end
    return {
        ok = result == true,
        message = if result and (action == "Group" or action == "DuplicateComponent")
            then "Component created" else message,
        instanceId = if result and (action == "Place" or action == "DuplicatePrimitive")
            then extra else nil,
        componentId = if result and (action == "Group" or action == "DuplicateComponent")
            then extra else nil,
        assemblyId=if result and assemblyAction then detail else nil,
        data=if result and bankAction then detail else nil,
    }
end

function Service.Start()
    plots=PlotService.new()
    GearLibrary.Ensure()
    PulleyLibrary.Ensure()
    FastenerLibrary.Ensure()
    HandCrankLibrary.Ensure()
    ShaftLibrary.Ensure()
    CompactHoleLibrary.Ensure()
    -- Baked procedural gear / bolt templates are session-scoped static mesh
    -- content; repopulate them for every server before Build catalog access.
    -- Existing native templates still work if Mesh / Image APIs are disabled.
    local generated, prefabErr = pcall(ProceduralPrefabLibrary.Ensure)
    if not generated then
        warn("[OPENWORKS] Precision prefabs unavailable; using legacy stock: " .. tostring(prefabErr))
    elseif RunService:IsStudio() then
        local galleryOK, galleryErr = pcall(ProceduralPrefabLibrary.BuildGallery, false)
        if not galleryOK then
            warn("[OPENWORKS] Prefab Studio gallery unavailable: " .. tostring(galleryErr))
        end
    end
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
        commitMetadata = commitMetadata,
        commitAssembly = commitAssembly,
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

    -- ComponentService is initialized before MechanicalService to avoid
    -- a require cycle. Inject the constructed service afterward so F
    -- duplicates can snapshot/restore authored INTERNAL relationships.
    components.D.mechanical=mechanical
    componentBank=ComponentBankService.new({
        components=components,mechanical=mechanical,
        folder=folder,Grid=Grid,Registry=Registry,Config=Config,
        snapshot=snapshot,createFromTemplate=createFromTemplate,
        ownedCount=ownedCount,validState=validState,applyState=applyState,
        nearPlayer=nearPlayer,intersectsConstructed=intersectsConstructed,
        commitAssembly=commitAssembly,commitBatch=commitBatch,
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
        persistence:Status(player,"Loading","Loading latest saved plot")
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
    persistence:StartAutoSave()
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
        if not hasEquippedTool(player,"AssemblySimulation") then return end
        if type(crankId)~="string" or #crankId>64 then return end
        simulation:InputCrank(player,crankId,speed,dragging,release)
    end)

    local oldRackEvent=ReplicatedStorage:FindFirstChild("OPENWORKS_RackControl")
    if oldRackEvent then oldRackEvent:Destroy() end
    local rackEvent=Instance.new("RemoteEvent")
    rackEvent.Name="OPENWORKS_RackControl"
    rackEvent.Parent=ReplicatedStorage
    rackEvent.OnServerEvent:Connect(function(player,rackId,direction,holding,release)
        if not hasEquippedTool(player,"AssemblySimulation") then return end
        if type(rackId)~="string" or #rackId>64 then return end
        if direction~=-1 and direction~=1 then return end
        simulation:InputRack(player,rackId,direction,holding,release)
    end)

    local oldMotor=ReplicatedStorage:FindFirstChild("OPENWORKS_MotorControl")
    if oldMotor then oldMotor:Destroy() end
    local motorEvent=Instance.new("RemoteEvent")
    motorEvent.Name="OPENWORKS_MotorControl"
    motorEvent.Parent=ReplicatedStorage
    motorEvent.OnServerEvent:Connect(function(player,key,holding)
        if not hasEquippedTool(player,"AssemblySimulation") then return end
        if type(key)~="string" or type(holding)~="boolean" then return end
        simulation:InputMotor(player,key,holding)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if persistence and persistence.Dirty[player] then
            local called,ok,why=pcall(persistence.Flush,
                persistence,player,"Exit")
            if not called or not ok then
                warn("[OPENWORKS] Exit save for "..player.Name
                    .." failed: "..tostring(if called then why else ok))
            end
        end
        if simulation then simulation:ClearPlayer(player) end
        if assemblies then assemblies:ClearPlayer(player) end
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
                model:Destroy()
            end
        end
        if mechanical then mechanical:ClearPlayer(player) end
        if componentBank then componentBank.Cache[player]=nil end
        if persistence then persistence:Clear(player) end
        if plots then plots:Release(player) end
        histories[player] = nil
        lastRequest[player] = nil
    end)

    game:BindToClose(function()
        if not persistence then return end
        persistence:StopAutoSave()
        local remaining=0
        for _,player in ipairs(Players:GetPlayers()) do
            if persistence.Dirty[player] then
                remaining+=1
                task.spawn(function()
                    local called,ok,why=pcall(persistence.Flush,
                        persistence,player,"Shutdown")
                    if not called or not ok then
                        warn("[OPENWORKS] Shutdown save for "..player.Name
                            .." failed: "..tostring(if called then why else ok))
                    end
                    remaining-=1
                end)
            end
        end
        local started=os.clock()
        while remaining>0 and os.clock()-started<25 do
            task.wait(0.1)
        end
        if remaining>0 then
            warn("[OPENWORKS] Shutdown has "
                ..remaining.." unfinished plot save(s)")
        end
    end)

    print("[OPENWORKS] ConstructionService ready: isolated plots / autosave + manual saves / relationships")
end

return Service
