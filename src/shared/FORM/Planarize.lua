local Planarize = {}

local MAX_PLANE_VARIATION = 0.03
local MAX_NORMAL_DEVIATION = 0.001
local MAX_VERTEX_SHIFT = 0.03

local function value(v, axis)
    if axis == 1 then return v.X end
    if axis == 2 then return v.Y end
    return v.Z
end

local function replaceAxis(v, axis, scalar)
    if axis == 1 then return Vector3.new(scalar, v.Y, v.Z) end
    if axis == 2 then return Vector3.new(v.X, scalar, v.Z) end
    return Vector3.new(v.X, v.Y, scalar)
end

local function scalarNormal(a, b, c)
    local ux, uy, uz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local vx, vy, vz = c.X - a.X, c.Y - a.Y, c.Z - a.Z
    local nx = uy * vz - uz * vy
    local ny = uz * vx - ux * vz
    local nz = ux * vy - uy * vx
    local magnitude = math.sqrt(nx * nx + ny * ny + nz * nz)
    if magnitude <= 1e-9 then return nil, 0 end
    return {math.abs(nx) / magnitude, math.abs(ny) / magnitude, math.abs(nz) / magnitude},
        magnitude / 2
end

function Planarize.display(solid)
    assert(type(solid) == 'table' and type(solid.vertices) == 'table'
        and type(solid.triangles) == 'table', 'Expected a triangle mesh')

    local vertices = table.clone(solid.vertices)
    local groups = {{}, {}, {}}
    local proposals = {{}, {}, {}}

    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        assert(a and b and c, 'Invalid triangle vertex')
        local normal, area = scalarNormal(a, b, c)
        if not normal then continue end

        for axis = 1, 3 do
            if normal[axis] < 1 - MAX_NORMAL_DEVIATION then continue end
            local va, vb, vc = value(a, axis), value(b, axis), value(c, axis)
            local low, high = math.min(va, vb, vc), math.max(va, vb, vc)
            if high - low > MAX_PLANE_VARIATION then continue end

            local center = (va + vb + vc) / 3
            local groupIndex
            for i, group in groups[axis] do
                if math.abs(group.center - center) <= MAX_PLANE_VARIATION
                    and math.max(group.maximum, high) - math.min(group.minimum, low)
                        <= MAX_PLANE_VARIATION then
                    groupIndex = i
                    break
                end
            end

            if not groupIndex then
                groupIndex = #groups[axis] + 1
                groups[axis][groupIndex] = {
                    center = center,
                    minimum = low,
                    maximum = high,
                    sum = 0,
                    weight = 0,
                    vertices = {},
                }
            end

            local group = groups[axis][groupIndex]
            group.minimum = math.min(group.minimum, low)
            group.maximum = math.max(group.maximum, high)
            group.sum += center * area
            group.weight += area
            for _, vertexId in face do group.vertices[vertexId] = true end
        end
    end

    local modified, maxShift, planarFaces = {}, 0, 0
    local conflicts = 0

    for axis = 1, 3 do
        for _, group in groups[axis] do
            if group.weight <= 0 then continue end
            planarFaces += 1
            local target = group.sum / group.weight
            for index in group.vertices do
                local original = value(solid.vertices[index], axis)
                if math.abs(original - target) <= MAX_VERTEX_SHIFT then
                    local prior = proposals[axis][index]
                    if prior and math.abs(prior - target) > MAX_PLANE_VARIATION then
                        proposals[axis][index] = false
                        conflicts += 1
                    elseif prior ~= false then
                        proposals[axis][index] = target
                    end
                end
            end
        end
    end

    local changed = 0
    for index, original in solid.vertices do
        local position = original
        for axis = 1, 3 do
            local target = proposals[axis][index]
            if type(target) == 'number' then
                local shift = math.abs(value(position, axis) - target)
                if shift > 1e-8 then
                    position = replaceAxis(position, axis, target)
                    maxShift = math.max(maxShift, shift)
                end
            end
        end
        if position ~= original then
            vertices[index] = position
            changed += 1
        end
    end

    return {vertices = vertices, triangles = solid.triangles}, {
        snappedVertices = changed,
        maxAxisShift = maxShift,
        planeGroups = planarFaces,
        conflicts = conflicts,
    }
end

return Planarize
