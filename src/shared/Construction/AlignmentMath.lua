--!strict
-- Shared, deterministic phase-04 coaxial placement math.
-- This positions geometry ONLY. It does not create a bearing/revolute joint.
-- A shaft is a full Cylinder primitive (local X axis).
-- A target is a circular/square tube (local X) or drilled block (local Y).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local Alignment = {}
Alignment.MaxOffsetUnits = 64

local function family(model)
    -- Look at BOTH fields: a broad family attribute should not conceal the
    -- more descriptive template ID (e.g. "DrilledBlock_050").
    local id = tostring(model:GetAttribute("TemplateId") or model.Name)
    local category = tostring(model:GetAttribute("PrimitiveFamily") or "")
    return string.lower(id .. category):gsub("[%s_%-]", "")
end

local function axisOverride(model)
    local axis = model:GetAttribute("AxialAxis") or model:GetAttribute("OpeningAxis")
    if axis == "X" then return Vector3.xAxis end
    if axis == "Y" then return Vector3.yAxis end
    if axis == "Z" then return Vector3.zAxis end
    return nil
end

function Alignment.IsShaft(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then return false end
    local name = family(model)
    if string.find(name, "halfcylinder", 1, true) then return false end
    return string.find(name, "cylinder", 1, true) ~= nil
end

function Alignment.TargetAxis(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then return nil end
    local name = family(model)
    if string.find(name, "halftube", 1, true) then return nil end
    local explicit = axisOverride(model)
    if explicit then return explicit end
    if string.find(name, "circulartube", 1, true)
        or string.find(name, "squaretube", 1, true)
        or string.find(name, "rectangulartube", 1, true)
        or string.find(name, "recttube", 1, true) then
        return Vector3.xAxis
    end
    if string.find(name, "drilledblock", 1, true)
        or string.find(name, "holeblock", 1, true) then
        -- Studio primitive generator subtracts a Y_AXIS cylinder.
        return Vector3.yAxis
    end
    return nil
end

function Alignment.ShaftIn(members)
    local best = nil
    local bestLength = -1
    for _, model in ipairs(members) do
        if Alignment.IsShaft(model) then
            local length = model.PrimaryPart.Size.X
            if length > bestLength then
                best = model
                bestLength = length
            end
        end
    end
    return best
end

function Alignment.IsOffsetValid(units)
    return type(units) == "number" and units == units
        and math.abs(units * 4 - math.round(units * 4)) < 0.0001
        and math.abs(units) <= Alignment.MaxOffsetUnits
end

function Alignment.MatchSteps(orientation)
    for x = 0, 3 do
        for y = 0, 3 do
            for z = 0, 3 do
                local steps = { x = x, y = y, z = z }
                local candidate = Grid.Rotation(steps)
                if candidate.RightVector:Dot(orientation.RightVector) > 0.99999
                    and candidate.UpVector:Dot(orientation.UpVector) > 0.99999 then
                    return steps
                end
            end
        end
    end
    return nil
end

local function closestOrientation(shaft, targetDirection)
    local current = shaft:GetPivot()
    local desired = if current.RightVector:Dot(targetDirection) >= 0
        then targetDirection else -targetDirection

    local best, score = nil, -math.huge
    for x = 0, 3 do
        for y = 0, 3 do
            for z = 0, 3 do
                local steps = { x = x, y = y, z = z }
                local rotation = Grid.Rotation(steps)
                local along = rotation.RightVector:Dot(desired)
                if along > 0.99999 then
                    local similarity = rotation.UpVector:Dot(current.UpVector)
                        + rotation.LookVector:Dot(current.LookVector)
                    if similarity > score then
                        best, score = steps, similarity
                    end
                end
            end
        end
    end
    return best
end

function Alignment.Plan(members, shaft, target, offsetUnits)
    if not Alignment.IsOffsetValid(offsetUnits) then
        return nil, "Insertion offset must be in 0.25-U increments within +/-64 U"
    end
    if not Alignment.IsShaft(shaft) then
        return nil, "Select a Cylinder shaft or a component containing one"
    end

    local axisLocal = Alignment.TargetAxis(target)
    if not axisLocal then
        return nil, "Select a circular/square tube or a drilled-block opening"
    end

    local direction = target:GetPivot():VectorToWorldSpace(axisLocal).Unit
    local steps = closestOrientation(shaft, direction)
    if not steps then return nil, "Could not align shaft axes" end

    -- No grid rounding during coaxial alignment: the shaft uses the
    -- target's true world-space hole axis and exact axial offset.
    local center = target:GetPivot().Position + direction * (offsetUnits * Grid.Unit)
    local desiredShaft = CFrame.new(center) * Grid.Rotation(steps)
    local delta = desiredShaft * shaft:GetPivot():Inverse()
    local items = {}

    for _, member in ipairs(members) do
        if not member.PrimaryPart then return nil, "Component geometry is incomplete" end
        local world = delta * member:GetPivot()
        local partSteps = Alignment.MatchSteps(world.Rotation)
        if not partSteps then return nil, "A member cannot rotate to a 90-degree orientation" end
        table.insert(items, {
            model = member,
            position = world.Position,
            steps = partSteps,
            size = member.PrimaryPart.Size,
        })
    end

    return {
        delta = delta,
        center = center,
        items = items,
        targetAxis = direction,
    }
end

return table.freeze(Alignment)
