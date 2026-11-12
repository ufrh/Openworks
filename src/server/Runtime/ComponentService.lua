--!strict
-- Editor-only component group manager. ComponentId identifies primitive
-- selections/transforms, NOT an implicit rigid physics relationship.
-- Mechanical welds must be authored separately; named assemblies define
-- an orthogonal simulation scope.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComponentGeometry = require(
    ReplicatedStorage:WaitForChild("Openworks")
        :WaitForChild("Construction")
        :WaitForChild("ComponentGeometry")
)
local FitOrigin = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("FitOrigin"))
local RotationMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("RotationMath"))

local ComponentService = {}
ComponentService.__index = ComponentService
local MAX_GROUP = 128

local function copied(data)
    local result = table.clone(data)
    result.steps = table.clone(data.steps)
    return result
end

function ComponentService.new(deps)
    return setmetatable({ D = deps }, ComponentService)
end

function ComponentService:Members(player, componentId)
    local d = self.D
    if type(componentId) ~= "string" or #componentId > 64 then return {} end
    local members = {}
    for _, model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId") == player.UserId
            and model:GetAttribute("ComponentId") == componentId then
            table.insert(members, model)
        end
    end
    table.sort(members, function(a, b)
        return tostring(a:GetAttribute("InstanceId")) < tostring(b:GetAttribute("InstanceId"))
    end)
    return members
end

function ComponentService:RequireMembers(player, componentId)
    local members = self:Members(player, componentId)
    if #members < 2 then return nil, "Component not found or has fewer than two pieces" end
    return members
end

function ComponentService:Group(player, payload)
    if type(payload.ids) ~= "table" then return false, "Select multiple primitives" end
    if #payload.ids < 2 or #payload.ids > MAX_GROUP then
        return false, "Select between 2 and 128 primitives"
    end

    local models, ids = {}, {}
    for _, id in ipairs(payload.ids) do
        if type(id) ~= "string" or ids[id] then return false, "Duplicate or invalid selection" end
        ids[id] = true

        local model = self.D.findOwned(player, id)
        if not model or model:GetAttribute("ComponentId") then
            return false, "Only your ungrouped primitives can be combined"
        end
        if not self.D.nearPlayer(player, model:GetPivot().Position) then
            return false, "Selection is too far away"
        end
        table.insert(models, model)
    end

    local before, after = {}, {}
    local componentId = HttpService:GenerateGUID(false)
    -- Construction pivot = most central primitive, never first selection.
    local centerModel = ComponentGeometry.CentralPrimitive(models)
    local anchorId = centerModel:GetAttribute("InstanceId")
    for _, model in ipairs(models) do
        table.insert(before, self.D.snapshot(model))
        model:SetAttribute("ComponentId", componentId)
        model:SetAttribute("ComponentAnchorId", anchorId)
        model:SetAttribute("ComponentFitPivotLocal",nil)
        table.insert(after, self.D.snapshot(model))
    end

    self.D.commitMetadata(player, before, after)
    return true, componentId
end

function ComponentService:Ungroup(player, payload)
    local members, reason = self:RequireMembers(player, payload.componentId)
    if not members then return false, reason end
    local before, after = {}, {}
    for _, model in ipairs(members) do
        if not self.D.nearPlayer(player, model:GetPivot().Position) then
            return false, "Component is too far away"
        end
        table.insert(before, self.D.snapshot(model))
    end
    for _, model in ipairs(members) do
        model:SetAttribute("ComponentId", nil)
        model:SetAttribute("ComponentAnchorId", nil)
        model:SetAttribute("ComponentFitPivotLocal",nil)
        table.insert(after, self.D.snapshot(model))
    end
    self.D.commitMetadata(player, before, after)
    return true, "Ungrouped"
end

local function matchingRotation(rotation, grid)
    for x = 0, 3 do
        for y = 0, 3 do
            for z = 0, 3 do
                local steps = { x = x, y = y, z = z }
                local r = grid.Rotation(steps)
                if r.RightVector:Dot(rotation.RightVector) > 0.99999
                    and r.UpVector:Dot(rotation.UpVector) > 0.99999 then
                    return steps
                end
            end
        end
    end
    return nil
end

function ComponentService:Plan(player, payload)
    local d = self.D
    local members, reason = self:RequireMembers(player, payload.componentId)
    if not members then return nil, nil, reason end
    if not d.Grid.ValidPosition(payload.position) or not d.Grid.ValidSteps(payload.steps) then
        return nil, nil, "Invalid component transform"
    end

    local anchor
    for _, member in ipairs(members) do
        if member:GetAttribute("InstanceId") == payload.anchorId then
            anchor = member
            break
        end
    end
    if not anchor then return nil, nil, "Invalid component anchor" end
    if anchor ~= FitOrigin.ComponentAnchor(members) then
        return nil, nil, "Component alignment anchor changed; reselect it"
    end

    local anchorState = d.snapshot(anchor)
    local anchorEntry = d.Registry.Get(anchorState.templateId)
    if not anchorEntry then return nil, nil, "Missing anchor primitive" end

    local newAnchor = {
        position = payload.position, steps = payload.steps,
        size = anchorState.size,
        freePosition = true,
        -- A fitted shaft may be the center primitive of its component.
        -- Preserve server-authorized 0.05-U diameter precision when moving it.
        fitPrecision = anchorState.fitPrecision,
        numericPrecision = anchorState.numericPrecision,
    }
    local valid, why = d.validState(player, anchorEntry, newAnchor)
    if not valid then return nil, nil, why end

    local stepDelta = d.Grid.Rotation(payload.steps)
        * d.Grid.Rotation(anchorState.steps):Inverse()
    local wantedRotation = stepDelta * anchor:GetPivot().Rotation
    local delta = (CFrame.new(payload.position) * wantedRotation)
        * anchor:GetPivot():Inverse()

    local before, planned = {}, {}
    for _, member in ipairs(members) do
        local state = d.snapshot(member)
        local desiredCF = delta * member:GetPivot()
        local steps = matchingRotation(desiredCF, d.Grid) or state.steps
        local target = copied(state)
        target.position = desiredCF.Position
        target.steps = steps
        target.orientation = desiredCF.Rotation
        target.freePosition = true

        local entry = d.Registry.Get(state.templateId)
        if not entry then return nil, nil, "Missing primitive template" end
        valid, why = d.validState(player, entry, target)
        if not valid then return nil, nil, why end

        table.insert(before, state)
        table.insert(planned, target)
    end
    return before, planned
end

function ComponentService:Transform(player, payload)
    local d = self.D
    local before, planned, reason = self:Plan(player, payload)
    if not before then return false, reason end
    local ignore = {}
    local models = {}

    for _, old in ipairs(before) do
        local model = d.findOwned(player, old.instanceId)
        if not model then return false, "Component changed during edit" end
        ignore[model] = true
        models[old.instanceId] = model
    end

    for _, nextState in ipairs(planned) do
        d.applyState(models[nextState.instanceId], nextState)
    end

    for _, nextState in ipairs(planned) do
        local model = models[nextState.instanceId]
        if d.intersectsConstructed(model, ignore) then
            for _, old in ipairs(before) do
                d.applyState(models[old.instanceId], old)
            end
            return false, "Component intersects another construction"
        end
    end

    d.commitBatch(player, before, planned)
    return true, "Component moved"
end

-- A grounded setting is a property of the entire rigid BODY; never
-- only the primitive currently under the crosshair.
function ComponentService:SetGrounded(player, payload)
    if type(payload.instanceId) ~= "string" then
        return false, "Aim at a primitive or component to ground"
    end
    local model = self.D.findOwned(player, payload.instanceId)
    if not model then return false, "Choose your own geometry" end
    if not self.D.nearPlayer(player, model:GetPivot().Position) then
        return false, "Ground target is out of range"
    end
    local members = model:GetAttribute("ComponentId")
        and self:Members(player, model:GetAttribute("ComponentId")) or { model }
    local newGrounded = not (model:GetAttribute("Grounded") == true)
    local before, after = {}, {}
    for _, member in ipairs(members) do
        table.insert(before, self.D.snapshot(member))
        member:SetAttribute("Grounded", newGrounded)
        table.insert(after, self.D.snapshot(member))
    end
    self.D.commitMetadata(player, before, after)
    return true, if newGrounded then "Body grounded" else "Body ungrounded"
end

-- R/T/Y are WORLD-axis quarter turns about the whole body's geometric
-- center, not the central primitive's local axes or an arbitrary pivot.
function ComponentService:RotateWorld(player, payload)
    local members, reason = self:RequireMembers(player, payload.componentId)
    if not members then return false, reason end
    local center = ComponentGeometry.Bounds(members)
    local delta = center and RotationMath.Delta(payload.axis, payload.direction, center)
    if not delta then return false, "Choose X, Y or Z rotation" end
    local d = self.D
    local before, planned, ignored = {}, {}, {}
    for _, member in ipairs(members) do
        local old = d.snapshot(member)
        local cf = delta * member:GetPivot()
        local target = table.clone(old)
        target.position = cf.Position
        target.steps = RotationMath.MatchSteps(cf.Rotation) or old.steps
        target.orientation = cf.Rotation
        target.freePosition = true
        local entry = d.Registry.Get(old.templateId)
        if not entry then return false, "Missing component template" end
        local valid, why = d.validState(player, entry, target)
        if not valid then return false, why end
        if not d.nearPlayer(player, target.position) then
            return false, "Rotated component exceeds build range"
        end
        ignored[member] = true
        table.insert(before, old)
        table.insert(planned, target)
    end
    for i, member in ipairs(members) do d.applyState(member, planned[i]) end
    for _, member in ipairs(members) do
        if d.intersectsConstructed(member, ignored) then
            for i, restore in ipairs(members) do d.applyState(restore, before[i]) end
            return false, "Rotation intersects another construction"
        end
    end
    d.commitBatch(player, before, planned)
    return true, "Component rotated about geometric center"
end

function ComponentService:Duplicate(player, payload)
    local d = self.D
    local before, planned, reason = self:Plan(player, payload)
    if not before then return false, reason end
    if d.ownedCount(player) + #planned > d.Config.MaxPartsPerPlayer then
        return false, "Construction limit reached"
    end

    local componentId = HttpService:GenerateGUID(false)
    local anchorOldId = payload.anchorId
    local idMap = {}
    for _, part in ipairs(planned) do
        idMap[part.instanceId] = HttpService:GenerateGUID(false)
    end

    -- Copy only fully INTERNAL authored relations. No copied joint may
    -- reach back into the source component or another original component.
    local relationships,fitSetMap={},{}
    if d.mechanical then
        for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
            if not relation:IsA("Folder")
                or relation:GetAttribute("OwnerUserId")~=player.UserId then
                continue
            end
            local original=d.mechanical:Snapshot(relation)
            if not idMap[original.sourceId] or not idMap[original.targetId]
                or (original.boltId and not idMap[original.boltId])
                or (original.secondTargetId
                    and not idMap[original.secondTargetId]) then
                continue
            end
            local spec=table.clone(original)
            spec.relationId=HttpService:GenerateGUID(false)
            spec.sourceId=idMap[original.sourceId]
            spec.targetId=idMap[original.targetId]
            spec.boltId=if original.boltId then idMap[original.boltId]
                else nil
            spec.secondTargetId=if original.secondTargetId then
                idMap[original.secondTargetId] else nil
            spec.componentId=componentId
            if type(original.fitPointsJSON)=="string"
                and original.fitPointsJSON~="" then
                local decodedOK,points=pcall(function()
                    return HttpService:JSONDecode(original.fitPointsJSON)
                end)
                if not decodedOK or type(points)~="table" then
                    return false,"Cannot duplicate invalid fit metadata"
                end
                local remapped={}
                local fullyInternal=true
                for _,point in ipairs(points) do
                    if type(point)~="table"
                        or not idMap[point.movingId]
                        or not idMap[point.stationaryId] then
                        fullyInternal=false
                        break
                    end
                    local mapped=table.clone(point)
                    mapped.movingId=idMap[point.movingId]
                    mapped.stationaryId=idMap[point.stationaryId]
                    table.insert(remapped,mapped)
                end
                if not fullyInternal then continue end
                spec.fitPointsJSON=HttpService:JSONEncode(remapped)
            end
            if type(original.fitSetId)=="string" then
                if not fitSetMap[original.fitSetId] then
                    fitSetMap[original.fitSetId]=HttpService:GenerateGUID(false)
                end
                spec.fitSetId=fitSetMap[original.fitSetId]
            end
            table.insert(relationships,spec)
        end
        if d.mechanical:Count(player)+#relationships>128 then
            return false,"Not enough mechanical relationship slots for copy"
        end
    end

    local candidates, after = {}, {}
    for _, desired in ipairs(planned) do
        local clone, why = d.createFromTemplate(
            player, desired.templateId, idMap[desired.instanceId], true
        )
        if not clone then
            for _, c in ipairs(candidates) do c:Destroy() end
            return false, why
        end

        local newState = copied(desired)
        -- Copy remaps every internal relationship independently. External
        -- attachments and saved assembly membership are not inherited.
        newState.instanceId = idMap[desired.instanceId]
        newState.componentId = componentId
        newState.componentAnchorId = idMap[anchorOldId]
        newState.assemblyId = nil
        newState.assemblyName = nil
        newState.grounded = false
        newState.alignedOpeningId=if type(desired.alignedOpeningId)=="string"
            then idMap[desired.alignedOpeningId] else nil
        if not newState.alignedOpeningId then
            newState.alignedOffsetU=0
            newState.shaftRollDegrees=0
        end
        newState.freePosition = true

        d.applyState(clone, newState)
        table.insert(candidates, clone)
        table.insert(after, newState)
    end

    for _, candidate in ipairs(candidates) do
        if d.intersectsConstructed(candidate) then
            for _, c in ipairs(candidates) do c:Destroy() end
            return false, "Copy intersects existing geometry"
        end
    end

    for _,candidate in ipairs(candidates) do candidate.Parent=d.folder end
    local restored={}
    for _,spec in ipairs(relationships) do
        local ok,detail=d.mechanical:Restore(player,spec)
        if not ok then
            for _,id in ipairs(restored) do
                local rel=d.mechanical:OwnedRelation(player,id)
                if rel then d.mechanical:DestroyRelation(rel) end
            end
            for _,model in ipairs(candidates) do model:Destroy() end
            return false,"Cannot duplicate internal relationship: "..tostring(detail)
        end
        table.insert(restored,spec.relationId)
    end
    if #relationships>0 then
        -- One operation: undo/redo handles BOTH duplicate geometry
        -- and its freshly remapped internal mechanical relationships.
        d.commitAssembly(player,{},after,relationships,false)
    else
        d.commitBatch(player,{},after)
    end
    return true,componentId
end

function ComponentService:Delete(player, payload)
    local members, reason = self:RequireMembers(player, payload.componentId)
    if not members then return false, reason end
    local before = {}
    for _, model in ipairs(members) do
        if not self.D.nearPlayer(player, model:GetPivot().Position) then
            return false, "Component is too far away"
        end
        table.insert(before, self.D.snapshot(model))
    end

    for _, member in ipairs(members) do member:Destroy() end
    self.D.commitBatch(player, before, {})
    return true, "Component deleted"
end

function ComponentService:Handle(player, action, payload)
    if action == "Group" then return self:Group(player, payload) end
    if action == "Ungroup" then return self:Ungroup(player, payload) end
    if action == "TransformComponent" then return self:Transform(player, payload) end
    if action == "DuplicateComponent" then return self:Duplicate(player, payload) end
    if action == "DeleteComponent" then return self:Delete(player, payload) end
    return false, "Unknown component action"
end

return ComponentService
