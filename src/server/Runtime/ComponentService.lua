--!strict
-- Phase 03 component graph.
-- A rigid component is a set of authored primitive Models that share a
-- server-assigned ComponentId and stable anchor. Members remain individually
-- editable; FORGE physics compilation/welds are deliberately future work.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComponentGeometry = require(
    ReplicatedStorage:WaitForChild("Openworks")
        :WaitForChild("Construction")
        :WaitForChild("ComponentGeometry")
)

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
        table.insert(after, self.D.snapshot(model))
    end

    self.D.commitBatch(player, before, after)
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
        table.insert(after, self.D.snapshot(model))
    end
    self.D.commitBatch(player, before, after)
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
    if anchor ~= ComponentGeometry.CentralPrimitive(members) then
        return nil, nil, "Component center changed; reselect the component"
    end

    local anchorState = d.snapshot(anchor)
    local anchorEntry = d.Registry.Get(anchorState.templateId)
    if not anchorEntry then return nil, nil, "Missing anchor primitive" end

    local newAnchor = {
        position = payload.position, steps = payload.steps,
        size = anchorState.size,
    }
    local valid, why = d.validState(player, anchorEntry, newAnchor)
    if not valid then return nil, nil, why end

    local delta = (CFrame.new(payload.position) * d.Grid.Rotation(payload.steps))
        * anchor:GetPivot():Inverse()

    local before, planned = {}, {}
    for _, member in ipairs(members) do
        local state = d.snapshot(member)
        local desiredCF = delta * member:GetPivot()
        local steps = matchingRotation(desiredCF, d.Grid)
        if not steps then return nil, nil, "Component rotation is not aligned to 90-degree axes" end
        local target = copied(state)
        target.position = desiredCF.Position
        target.steps = steps

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
        newState.instanceId = idMap[desired.instanceId]
        newState.componentId = componentId
        newState.componentAnchorId = idMap[anchorOldId]

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

    for _, candidate in ipairs(candidates) do candidate.Parent = d.folder end
    d.commitBatch(player, {}, after)
    return true, componentId
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
