local FORM = require(script.Parent)

local Cut = {}

local EPSILON = 1e-5
local lineage = setmetatable({}, {__mode = 'k'})
local MAX_PROPAGATED_DRIFT = 0.01

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function convex(solid)
    local lower, upper = FORM.bounds(solid)
    local extent = (upper - lower).Magnitude
    local threshold = math.max(EPSILON, extent * 1e-5)
    local worst = 0

    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a)
        local length = normal.Magnitude
        if length <= 0 then return false, math.huge, threshold end

        for _, vertex in solid.vertices do
            worst = math.max(worst, (vertex - a):Dot(normal) / length)
        end
    end

    return worst <= threshold, worst, threshold
end

function Cut.split(solid, planePoint, planeNormal)
    assert(typeof(planePoint) == 'Vector3' and typeof(planeNormal) == 'Vector3', 'Expected plane vectors')
    assert(planeNormal.Magnitude > 0, 'Plane normal cannot be zero')
    if not FORM.validate(solid).ok then return nil, 'INVALID_INPUT' end
    local isConvex, violation, threshold = convex(solid)
    if not isConvex then
        if not lineage[solid] then
            return nil, string.format('NON_CONVEX_INPUT max=%.9f mm tolerance=%.9f mm', violation, threshold)
        end
        if violation > math.max(MAX_PROPAGATED_DRIFT, threshold) then
            return nil, string.format('CONVEX_LINEAGE_DRIFT max=%.9f mm limit=%.9f mm',
                violation, math.max(MAX_PROPAGATED_DRIFT, threshold))
        end
    end

    local normal = planeNormal.Unit
    local distances = {}
    local minimum, maximum = math.huge, -math.huge

    for i, vertex in solid.vertices do
        local distance = (vertex - planePoint):Dot(normal)
        distances[i] = distance
        minimum = math.min(minimum, distance)
        maximum = math.max(maximum, distance)
    end

    if minimum >= -EPSILON or maximum <= EPSILON then
        return nil, 'PLANE_DOES_NOT_INTERSECT'
    end

    local intersections = {}
    local nextVertex = #solid.vertices
    local sides = {}

    local function intersection(a, b)
        if math.abs(distances[a]) <= EPSILON then return a end
        if math.abs(distances[b]) <= EPSILON then return b end

        local key = edgeKey(a, b)
        if intersections[key] then return intersections[key] end

        local ratio = distances[a] / (distances[a] - distances[b])
        nextVertex += 1
        local index = nextVertex
        local result = solid.vertices[a]:Lerp(solid.vertices[b], ratio)
        intersections[key] = index
        intersections[index] = result
        return index
    end

    local function position(index)
        return solid.vertices[index] or intersections[index]
    end

    for sideIndex = 1, 2 do
        local sign = if sideIndex == 1 then 1 else -1
        local output = {vertices = {}, triangles = {}}
        local mapped = {}
        local planeEdges = {}

        local function add(index)
            if mapped[index] then return mapped[index] end
            local id = #output.vertices + 1
            output.vertices[id] = position(index)
            mapped[index] = id
            return id
        end

        local function triangle(a, b, c)
            if a == b or b == c or c == a then return end
            local pa, pb, pc = output.vertices[a], output.vertices[b], output.vertices[c]
            if (pb - pa):Cross(pc - pa).Magnitude <= EPSILON * EPSILON then return end
            output.triangles[#output.triangles + 1] = {a, b, c}

            for _, edge in {{a, b}, {b, c}, {c, a}} do
                local p, q = output.vertices[edge[1]], output.vertices[edge[2]]
                if math.abs((p - planePoint):Dot(normal)) <= EPSILON
                    and math.abs((q - planePoint):Dot(normal)) <= EPSILON then
                    local key = edgeKey(edge[1], edge[2])
                    local record = planeEdges[key] or {a = edge[1], b = edge[2], count = 0}
                    record.count += 1
                    planeEdges[key] = record
                end
            end
        end

        for _, face in solid.triangles do
            local polygon = {}
            for j = 1, 3 do
                local a, b = face[j], face[j % 3 + 1]
                local insideA = distances[a] * sign >= -EPSILON
                local insideB = distances[b] * sign >= -EPSILON
                if insideA then polygon[#polygon + 1] = a end
                if insideA ~= insideB then
                    polygon[#polygon + 1] = intersection(a, b)
                end
            end

            local unique = {}
            for _, index in polygon do
                if unique[#unique] ~= index then unique[#unique + 1] = index end
            end
            if #unique > 1 and unique[1] == unique[#unique] then table.remove(unique) end
            if #unique >= 3 then
                local a = add(unique[1])
                for j = 2, #unique - 1 do
                    triangle(a, add(unique[j]), add(unique[j + 1]))
                end
            end
        end

        local boundary = {}
        for _, edge in planeEdges do
            if edge.count == 1 then
                if boundary[edge.a] then return nil, 'BRANCHED_CUT_BOUNDARY' end
                boundary[edge.a] = edge.b
            end
        end

        local start = nil
        for vertex in boundary do
            if not start or vertex < start then start = vertex end
        end
        if not start then return nil, 'INVALID_INTERSECTION_LOOP' end

        local ring = {}
        local visited = {}
        local current = start
        while not visited[current] do
            if not boundary[current] then return nil, 'OPEN_CUT_BOUNDARY' end
            visited[current] = true
            ring[#ring + 1] = current
            current = boundary[current]
        end

        if current ~= start or #ring < 3 then
            return nil, 'INVALID_INTERSECTION_LOOP'
        end
        for vertex in boundary do
            if not visited[vertex] then return nil, 'MULTIPLE_CUT_LOOPS' end
        end

        local center = Vector3.zero
        for _, index in ring do center += output.vertices[index] end
        center /= #ring

        local centerId = #output.vertices + 1
        output.vertices[centerId] = center
        for i = 1, #ring do
            local a, b = ring[i], ring[i % #ring + 1]
            triangle(centerId, b, a)
        end

        if not FORM.validate(output).ok then return nil, 'INVALID_OUTPUT' end
        sides[sideIndex] = output
    end

    local before = FORM.signedVolume(solid)
    local after = FORM.signedVolume(sides[1]) + FORM.signedVolume(sides[2])
    if not FORM.volumeClose(after, before) then
        return nil, string.format('VOLUME_MISMATCH before=%.9f after=%.9f delta=%+.9f', before, after, after - before)
    end

    lineage[sides[1]] = true
    lineage[sides[2]] = true
    return sides[1], sides[2]
end

return Cut
