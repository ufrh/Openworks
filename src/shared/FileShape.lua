local FORM = require(script.Parent.FORM)
local Cut = require(script.Parent.FORM.Cut)
local Stock = require(script.Parent.Stock)

local FileShape = {}
FileShape.DEFAULT_RADIUS = 3
FileShape.SEGMENTS = 6

local AXES = {
    {name = 'X', direction = Vector3.xAxis},
    {name = 'Y', direction = Vector3.yAxis},
    {name = 'Z', direction = Vector3.zAxis},
}

local function component(v, axis)
    if axis == 'X' then return v.X end
    if axis == 'Y' then return v.Y end
    return v.Z
end

local function axisVector(axis)
    for _, entry in AXES do
        if entry.name == axis then return entry.direction end
    end
    error('Unknown file axis: ' .. tostring(axis))
end

local function finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validateRadius(radius)
    assert(finite(radius) and radius >= 0.5 and radius <= 12, 'File radius must be 0.5-12 mm')
end

function FileShape.preview(item, hitWorld, radius)
    validateRadius(radius)
    if item.shape == 'Tube' or item.tubeProfile then
        return nil, 'Hollow tubes need a dedicated bore-safe filing toolpath'
    end
    if typeof(hitWorld) ~= 'Vector3' then return nil, 'Invalid filing position' end

    local low, high = FORM.bounds(item.solid)
    local hit = item.frame:PointToObjectSpace(hitWorld) / Stock.SCALE
    local candidates = {}
    for _, axis in AXES do
        local value, minimum, maximum = component(hit, axis.name),
            component(low, axis.name), component(high, axis.name)
        local bottomDistance = math.abs(value - minimum)
        local topDistance = math.abs(value - maximum)
        local sign = if topDistance < bottomDistance then 1 else -1
        candidates[#candidates + 1] = {
            axis = axis.name, sign = sign,
            distance = math.min(topDistance, bottomDistance),
        }
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    local first, second = candidates[1], candidates[2]
    local spanA = component(high - low, first.axis)
    local spanB = component(high - low, second.axis)
    if radius >= math.min(spanA, spanB) * 0.45 then
        return nil, 'Choose a smaller rounding radius for this workpiece'
    end
    local edgeAxis
    for _, axis in AXES do
        if axis.name ~= first.axis and axis.name ~= second.axis then
            edgeAxis = axis.name
            break
        end
    end

    local edgeHasMaterial = false
    local limitA = component(if first.sign == 1 then high else low, first.axis)
    local limitB = component(if second.sign == 1 then high else low, second.axis)
    for _, vertex in item.solid.vertices do
        if math.abs(component(vertex, first.axis) - limitA) < 0.001
            and math.abs(component(vertex, second.axis) - limitB) < 0.001 then
            edgeHasMaterial = true
            break
        end
    end
    if not edgeHasMaterial then
        return nil, 'This edge has already been rounded; choose another'
    end

    local a = axisVector(first.axis) * first.sign
    local b = axisVector(second.axis) * second.sign
    local corner = axisVector(first.axis) * component(
        if first.sign == 1 then high else low, first.axis)
        + axisVector(second.axis) * component(
            if second.sign == 1 then high else low, second.axis)
    local center = corner - (a + b) * radius
    local along = axisVector(edgeAxis)
    local strips = {{}, {}}
    for i = 0, FileShape.SEGMENTS do
        local theta = i * math.pi / (2 * FileShape.SEGMENTS)
        local cross = center + a * (radius * math.cos(theta))
            + b * (radius * math.sin(theta))
        strips[1][i + 1] = item.frame:PointToWorldSpace(
            (cross + along * component(low, edgeAxis)) * Stock.SCALE)
        strips[2][i + 1] = item.frame:PointToWorldSpace(
            (cross + along * component(high, edgeAxis)) * Stock.SCALE)
    end

    return {
        axisA = first.axis, signA = first.sign,
        axisB = second.axis, signB = second.sign,
        edgeAxis = edgeAxis, radius = radius,
        boundsLow = low, boundsHigh = high,
        strips = strips,
    }
end

function FileShape.apply(item, spec)
    if not spec or not spec.axisA or spec.axisA == spec.axisB then
        return nil, 'Invalid filing specification'
    end
    if item.shape == 'Tube' or item.tubeProfile then
        return nil, 'Hollow tubes not supported by this filing operation'
    end
    local radius = spec.radius
    validateRadius(radius)
    local lower, upper = FORM.bounds(item.solid)
    if lower ~= spec.boundsLow or upper ~= spec.boundsHigh then
        return nil, 'Workpiece geometry changed since filing preview'
    end

    local a = axisVector(spec.axisA) * spec.signA
    local b = axisVector(spec.axisB) * spec.signB
    local corner = axisVector(spec.axisA) * component(
        if spec.signA == 1 then upper else lower, spec.axisA)
        + axisVector(spec.axisB) * component(
            if spec.signB == 1 then upper else lower, spec.axisB)
    local center = corner - (a + b) * radius
    local remaining = item.solid
    local initial = FORM.signedVolume(remaining)

    for i = 1, FileShape.SEGMENTS - 1 do
        local theta = i * math.pi / (2 * FileShape.SEGMENTS)
        local normal = (a * math.cos(theta) + b * math.sin(theta)).Unit
        local point = center + normal * radius
        local removed, kept = Cut.split(remaining, point, normal)
        if not removed then
            if i == 1 then return nil, 'No material remains at this edge for that radius' end
            return nil, 'Filing plane failed: ' .. tostring(kept)
        end
        remaining = kept
    end
    if not FORM.validate(remaining).ok then return nil, 'Filed surface is not watertight' end
    local finalVolume = FORM.signedVolume(remaining)
    local removed = initial - finalVolume
    if removed <= 0.001 then return nil, 'Filing did not remove measurable material' end
    return remaining, {removed = removed, retained = finalVolume, segments = FileShape.SEGMENTS}
end

function FileShape.chamfer(item, spec)
    if not spec or not spec.axisA or spec.axisA == spec.axisB then
        return nil, 'Invalid chamfer specification'
    end

    local radius = spec.radius
    validateRadius(radius)
    local lower, upper = FORM.bounds(item.solid)
    if lower ~= spec.boundsLow or upper ~= spec.boundsHigh then
        return nil, 'Workpiece geometry changed since chamfer preview'
    end

    local a = axisVector(spec.axisA) * spec.signA
    local b = axisVector(spec.axisB) * spec.signB
    local corner = axisVector(spec.axisA) * component(
        if spec.signA == 1 then upper else lower, spec.axisA)
        + axisVector(spec.axisB) * component(
            if spec.signB == 1 then upper else lower, spec.axisB)

    local outward = (a + b).Unit
    local plane = corner - (a + b) * (radius * 0.5)
    local removed, remaining = Cut.split(item.solid, plane, outward)
    if not removed then return nil, 'Chamfer operation failed: ' .. tostring(remaining) end

    local validation = FORM.validate(remaining)
    if not validation.ok then return nil, 'Chamfer geometry is not watertight' end

    local removedVolume = FORM.signedVolume(item.solid) - FORM.signedVolume(remaining)
    if removedVolume <= 0.001 then return nil, 'Chamfer did not remove measurable material' end

    return remaining, {
        removed = removedVolume,
        retained = FORM.signedVolume(remaining),
        segments = 1,
    }
end

return FileShape
