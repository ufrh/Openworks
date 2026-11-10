--!strict
-- Phase 04 server-validated shaft-to-hole positioning.
-- Uses the precompiled collision geometry; does NOT create a joint.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Alignment = require(
    ReplicatedStorage:WaitForChild("Openworks")
        :WaitForChild("Construction"):WaitForChild("AlignmentMath")
)

local Service = {}
Service.__index = Service

function Service.new(deps)
    return setmetatable({ D = deps }, Service)
end

function Service:Align(player, request)
    local d = self.D
    if type(request.sourceId) ~= "string"
        or type(request.targetId) ~= "string"
        or not Alignment.IsOffsetValid(request.offsetUnits) then
        return false, "Invalid alignment request"
    end

    local shaft = d.findOwned(player, request.sourceId)
    local target = d.findOwned(player, request.targetId)
    if not shaft or not target then
        return false, "Both shaft and opening must belong to you"
    end
    if not Alignment.IsShaft(shaft) or not Alignment.TargetAxis(target) then
        return false, "Select a Cylinder and a supported hollow opening"
    end
    if shaft == target then return false, "Cannot align a piece to itself" end
    if not d.nearPlayer(player, target:GetPivot().Position) then
        return false, "Opening is out of construction range"
    end

    local members = { shaft }
    if request.componentId ~= nil then
        if type(request.componentId) ~= "string"
            or shaft:GetAttribute("ComponentId") ~= request.componentId then
            return false, "Shaft does not belong to the selected component"
        end
        members = d.components:Members(player, request.componentId)
        if #members < 2 or #members > 128 then
            return false, "Component membership is invalid"
        end
    end

    for _, member in ipairs(members) do
        if member == target then
            return false, "Opening must be outside the moving component"
        end
    end

    local plan, reason = Alignment.Plan(members, shaft, target, request.offsetUnits)
    if not plan then return false, reason end

    local before, planned, ignored = {}, {}, {}
    for _, item in ipairs(plan.items) do
        local member = item.model
        local old = d.snapshot(member)
        local proposed = {
            instanceId = old.instanceId,
            templateId = old.templateId,
            position = item.position,
            steps = item.steps,
            size = old.size,
            componentId = old.componentId,
            componentAnchorId = old.componentAnchorId,
            assemblyPrecision = true,
            freePosition = true,
        }
        local entry = d.Registry.Get(old.templateId)
        if not entry then return false, "A component template is missing" end
        local ok, why = d.validState(player, entry, proposed)
        if not ok then return false, why end

        ignored[member] = true
        table.insert(before, old)
        table.insert(planned, proposed)
    end

    -- The mutation is applied atomically after all grid/range checks.
    for i, original in ipairs(before) do
        d.applyState(plan.items[i].model, planned[i])
    end

    for _, item in ipairs(plan.items) do
        if d.intersectsConstructed(item.model, ignored, target,
            shaft:GetAttribute("InstanceId")) then
            for i, original in ipairs(before) do
                d.applyState(plan.items[i].model, original)
            end
            return false, "Shaft geometry interferes with the opening or another part"
        end
    end

    if #planned == 1 then
        d.commitRecord(player, before[1], planned[1])
    else
        d.commitBatch(player, before, planned)
    end
    return true, "Shaft aligned; mechanical joint not yet created"
end

return Service
