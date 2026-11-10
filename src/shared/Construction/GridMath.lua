--!strict
-- All player-facing construction dimensions are in U, never mm.
local UNIT = 0.25
local Grid = { Unit = UNIT, MaxUnits = 64, MaxDistance = 55,
    MinSizeStepU = 0.25, DefaultSizeStepU = 0.5 }

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

local function axisCenter(value, length, increment)
    local cells = math.floor(length / increment + 0.5)
    local offset = (cells % 2 == 1) and increment / 2 or 0
    return nearest(value, increment, offset)
end

function Grid.HasFractionalSize(size)
    if typeof(size) ~= "Vector3" then return false end
    for _, n in ipairs({ size.X, size.Y, size.Z }) do
        if math.abs(n / UNIT - math.round(n / UNIT)) > 0.0001 then
            return true
        end
    end
    return false
end

function Grid.Rotation(steps)
    steps = steps or { x = 0, y = 0, z = 0 }
    return CFrame.Angles(
        (steps.x or 0) * math.pi / 2,
        (steps.y or 0) * math.pi / 2,
        (steps.z or 0) * math.pi / 2
    )
end

function Grid.SnapCenter(position, size, rotation, stepU)
    local extent = dimensions(size, rotation)
    local increment = UNIT * (stepU or 1)
    return Vector3.new(
        axisCenter(position.X, extent.X, increment),
        axisCenter(position.Y, extent.Y, increment),
        axisCenter(position.Z, extent.Z, increment)
    )
end

function Grid.SnapSizeCenter(position, size, rotation)
    return Grid.SnapCenter(position, size, rotation, Grid.MinSizeStepU)
end

function Grid.IsSizeSnapped(position, size, rotation)
    return (position - Grid.SnapSizeCenter(position, size, rotation)).Magnitude < 0.001
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
    local target = if Grid.HasFractionalSize(size)
        then Grid.SnapSizeCenter(desired, size, rotation)
        else Grid.SnapCenter(desired, size, rotation)
    return CFrame.new(target) * rotation
end

function Grid.IsSnapped(position, size, rotation)
    return (position - Grid.SnapCenter(position, size, rotation)).Magnitude < 0.01
end

-- Assembly centers must support HALF of the smallest 0.25-U sizing
-- increment (0.125 U = 0.03125 studs). This preserves perfect coaxial
-- placement even when independently sized profiles have different parity.
-- Ordinary Build/Move still uses its own face-grid rules.
function Grid.SnapAssemblyCenter(position)
    local step = UNIT * Grid.MinSizeStepU / 2
    return Vector3.new(
        nearest(position.X, step, 0),
        nearest(position.Y, step, 0),
        nearest(position.Z, step, 0)
    )
end

function Grid.IsAssemblySnapped(position)
    return (position - Grid.SnapAssemblyCenter(position)).Magnitude < 0.001
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
        local ticks = u / Grid.MinSizeStepU
        return u >= Grid.MinSizeStepU - 0.0001 and u <= Grid.MaxUnits + 0.0001
            and math.abs(ticks - math.floor(ticks + 0.5)) < 0.0001
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
