--!strict
-- Shared pivot selection for logical rigid components.
-- Use the primitive whose center is nearest the complete component bounds:
-- transforms remain 1-U grid-consistent even for uneven/mixed-size groups.
local ComponentGeometry = {}

local function extents(part)
    local r = part.CFrame.RightVector
    local u = part.CFrame.UpVector
    local l = part.CFrame.LookVector
    local half = part.Size / 2
    return Vector3.new(
        math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
        math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
        math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
    )
end

function ComponentGeometry.Bounds(members)
    local low = Vector3.new(math.huge, math.huge, math.huge)
    local high = Vector3.new(-math.huge, -math.huge, -math.huge)
    local found = false

    for _, model in ipairs(members) do
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                local radius = extents(object)
                local center = object.Position
                low = Vector3.new(
                    math.min(low.X, center.X - radius.X),
                    math.min(low.Y, center.Y - radius.Y),
                    math.min(low.Z, center.Z - radius.Z)
                )
                high = Vector3.new(
                    math.max(high.X, center.X + radius.X),
                    math.max(high.Y, center.Y + radius.Y),
                    math.max(high.Z, center.Z + radius.Z)
                )
                found = true
            end
        end
    end

    if not found then return nil, nil end
    return (low + high) / 2, high - low
end

function ComponentGeometry.CentralPrimitive(members)
    if #members == 0 then return nil end
    local center = ComponentGeometry.Bounds(members)
    if not center then return members[1] end

    local best, bestDistance, bestId = nil, math.huge, ""
    for _, model in ipairs(members) do
        local dist = (model:GetPivot().Position - center).Magnitude
        local id = tostring(model:GetAttribute("InstanceId") or "")
        if dist < bestDistance - 0.000001
            or (math.abs(dist - bestDistance) <= 0.000001 and (best == nil or id < bestId)) then
            best = model
            bestDistance = dist
            bestId = id
        end
    end

    return best
end

return table.freeze(ComponentGeometry)
