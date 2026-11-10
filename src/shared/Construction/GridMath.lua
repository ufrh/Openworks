--!strict
-- All player-facing construction dimensions are in U, never mm.
local UNIT = 0.25
local Grid = { Unit = UNIT, MaxUnits = 64, MaxDistance = 55 }

local function nearest(value, step, offset)
    return math.floor((value - offset) / step + 0.5) * step + offset
end

local function component(v, axis)
    if axis == 1 then return v.X end
    if axis == 2 then return v.Y end
    return v.Z
end

local function dimensions(size, rotation)
    local x, y, z = rotation.RightVector, rotation.UpVector, rotation.LookVector
    return Vector3.new(
        math.abs(x.X) * size.X + math.abs(y.X) * size.Y + math.abs(z.X) * size.Z,
        math.abs(x.Y) * size.X + math.abs(y.Y) * size.Y + math.abs(z.Y) * size.Z,
        math.abs(x.Z) * size.X + math.abs(y.Z) * size.Y + math.abs(z.Z) * size.Z
    )
end

local function axisCenter(value, length)
    local cells = math.floor(length / UNIT + 0.5)
    local offset = (cells % 2 == 1) and UNIT / 2 or 0
    return nearest(value, UNIT, offset)
end

function Grid.Rotation(steps)
    steps = steps or { x = 0, y = 0, z = 0 }
    return CFrame.Angles(
        (steps.x or 0) * math.pi / 2,
        (steps.y or 0) * math.pi / 2,
        (steps.z or 0) * math.pi / 2
    )
end

function Grid.SnapCenter(position, size, rotation)
    local extent = dimensions(size, rotation)
    return Vector3.new(
        axisCenter(position.X, extent.X),
        axisCenter(position.Y, extent.Y),
        axisCenter(position.Z, extent.Z)
    )
end

function Grid.FromSurface(hitPosition, surfaceNormal, size, rotation)
    local dimensionsWorld = dimensions(size, rotation)
    local ax, ay, az = math.abs(surfaceNormal.X), math.abs(surfaceNormal.Y), math.abs(surfaceNormal.Z)
    local normal
    if ax >= ay and ax >= az then
        normal = Vector3.new(if surfaceNormal.X >= 0 then 1 else -1, 0, 0)
    elseif ay >= az then
        normal = Vector3.new(0, if surfaceNormal.Y >= 0 then 1 else -1, 0)
    else
        normal = Vector3.new(0, 0, if surfaceNormal.Z >= 0 then 1 else -1)
    end
    local depth = math.abs(normal.X) * dimensionsWorld.X
        + math.abs(normal.Y) * dimensionsWorld.Y
        + math.abs(normal.Z) * dimensionsWorld.Z
    local desired = hitPosition + normal * (depth / 2 + 0.001)
    return CFrame.new(Grid.SnapCenter(desired, size, rotation)) * rotation
end

function Grid.IsSnapped(position, size, rotation)
    return (position - Grid.SnapCenter(position, size, rotation)).Magnitude < 0.01
end

function Grid.ValidSteps(steps)
    if type(steps) ~= "table" then return false end
    for _, axis in ipairs({ "x", "y", "z" }) do
        local n = steps[axis]
        if type(n) ~= "number" or n ~= n or n % 1 ~= 0 or n < 0 or n > 3 then
            return false
        end
    end
    return true
end

function Grid.ValidPosition(position)
    if typeof(position) ~= "Vector3" then return false end
    for _, n in ipairs({ position.X, position.Y, position.Z }) do
        if n ~= n or math.abs(n) > 4096 or n == math.huge or n == -math.huge then
            return false
        end
    end
    return true
end

function Grid.ValidSize(templateSize, proposed, resizeMode)
    if typeof(proposed) ~= "Vector3" then return false end
    if typeof(templateSize) ~= "Vector3" then return false end

    local values = { proposed.X, proposed.Y, proposed.Z }
    for _, value in ipairs(values) do
        if value ~= value or value == math.huge or value == -math.huge then return false end
    end

    if resizeMode == "None" then
        return (proposed - templateSize).Magnitude < 0.01
    end

    local function unitValid(value)
        local u = value / UNIT
        return u >= 1 - 0.0001 and u <= Grid.MaxUnits + 0.0001
            and math.abs(u - math.floor(u + 0.5)) < 0.0001
    end

    if resizeMode == "XYZ_1U" then
        return unitValid(proposed.X) and unitValid(proposed.Y) and unitValid(proposed.Z)
    elseif resizeMode == "UniformDiameter_1U" then
        return unitValid(proposed.X)
            and math.abs(proposed.X - proposed.Y) < 0.001
            and math.abs(proposed.X - proposed.Z) < 0.001
    elseif resizeMode == "LengthAndDiameter_1U" then
        return unitValid(proposed.X) and unitValid(proposed.Y)
            and math.abs(proposed.Y - proposed.Z) < 0.001
    elseif resizeMode == "LengthOnly_1U" then
        return unitValid(proposed.X)
            and math.abs(proposed.Y - templateSize.Y) < 0.01
            and math.abs(proposed.Z - templateSize.Z) < 0.01
    end

    return false
end

return table.freeze(Grid)
