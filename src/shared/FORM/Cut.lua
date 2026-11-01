local Cut = {}

local function key(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function point(p, id)
    return {position = p, id = id}
end

function Cut.split(solid, planePoint, planeNormal)
    assert(typeof(planePoint) == 'Vector3' and typeof(planeNormal) == 'Vector3', 'Expected plane vectors')
    assert(planeNormal.Magnitude > 0, 'Plane normal cannot be zero')

    local normal = planeNormal.Unit
    local FORM = require(script.Parent)
    if not FORM.validate(solid).ok then return nil, 'INVALID_INPUT' end

    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local faceNormal = (b - a):Cross(c - a)
        for _, vertex in solid.vertices do
            if (vertex - a):Dot(faceNormal) > 1e-5 * faceNormal.Magnitude then
                return nil, 'NON_CONVEX_INPUT'
            end
        end
    end
    local distances = {}
    local minDistance, maxDistance = math.huge, -math.huge
    local tolerance = 1e-6

    for i, vertex in solid.vertices do
        local d = (vertex - planePoint):Dot(normal)
        distances[i] = d
        minDistance = math.min(minDistance, d)
        maxDistance = math.max(maxDistance, d)
        if math.abs(d) <= tolerance then
            return nil, 'PLANE_TOUCHES_VERTEX'
        end
    end

    if minDistance > 0 or maxDistance < 0 then
        return nil, 'PLANE_DOES_NOT_INTERSECT'
    end

    local sides = {
        {vertices = {}, triangles = {}, originals = {}, intersections = {}},
        {vertices = {}, triangles = {}, originals = {}, intersections = {}},
    }
    local cuts = {}

    local function add(side, node)
        local map = if node.id then side.originals else side.intersections
        local identity = node.id or node.edge
        if map[identity] then return map[identity] end
        local index = #side.vertices + 1
        side.vertices[index] = node.position
        map[identity] = index
        return index
    end

    local function intersection(a, b)
        local identity = key(a.id, b.id)
        if cuts[identity] then return cuts[identity] end
        local da, db = distances[a.id], distances[b.id]
        local t = da / (da - db)
        local result = {position = a.position:Lerp(b.position, t), edge = identity}
        cuts[identity] = result
        return result
    end

    for _, triangle in solid.triangles do
        local nodes = {}
        for _, index in triangle do
            nodes[#nodes + 1] = point(solid.vertices[index], index)
        end

        for sideIndex, side in sides do
            local sign = if sideIndex == 1 then 1 else -1
            local polygon = {}
            for j = 1, 3 do
                local a, b = nodes[j], nodes[j % 3 + 1]
                local insideA = distances[a.id] * sign > 0
                local insideB = distances[b.id] * sign > 0
                if insideA then polygon[#polygon + 1] = a end
                if insideA ~= insideB then polygon[#polygon + 1] = intersection(a, b) end
            end
            if #polygon >= 3 then
                local first = add(side, polygon[1])
                for j = 2, #polygon - 1 do
                    side.triangles[#side.triangles + 1] = {first, add(side, polygon[j]), add(side, polygon[j + 1])}
                end
            end
        end
    end

    local ring = {}
    for _, node in cuts do ring[#ring + 1] = node end
    if #ring < 3 then return nil, 'INSUFFICIENT_INTERSECTION' end

    local center = Vector3.zero
    for _, node in ring do center += node.position end
    center /= #ring

    local reference = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
    local axisX = reference:Cross(normal).Unit
    local axisY = normal:Cross(axisX)
    table.sort(ring, function(a, b)
        local pa, pb = a.position - center, b.position - center
        local aa = math.atan2(pa:Dot(axisY), pa:Dot(axisX))
        local ab = math.atan2(pb:Dot(axisY), pb:Dot(axisX))
        if aa == ab then return a.edge < b.edge end
        return aa < ab
    end)

    for sideIndex, side in sides do
        local centerId = #side.vertices + 1
        side.vertices[centerId] = center
        for i = 1, #ring do
            local a = add(side, ring[i])
            local b = add(side, ring[i % #ring + 1])
            if sideIndex == 1 then
                side.triangles[#side.triangles + 1] = {centerId, b, a}
            else
                side.triangles[#side.triangles + 1] = {centerId, a, b}
            end
        end
        side.originals = nil
        side.intersections = nil
    end

    for _, side in sides do
        if not FORM.validate(side).ok then return nil, 'INVALID_OUTPUT' end
    end

    local initial = FORM.signedVolume(solid)
    local combined = FORM.signedVolume(sides[1]) + FORM.signedVolume(sides[2])
    if math.abs(initial - combined) > math.max(1e-5, initial * 1e-8) then
        return nil, 'VOLUME_MISMATCH'
    end

    return sides[1], sides[2]
end

return Cut
