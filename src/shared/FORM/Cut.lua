local FORM = require(script.Parent)

local Cut = {}

local EPSILON = 1e-5

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function convex(solid)
    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a)
        for _, vertex in solid.vertices do
            if (vertex - a):Dot(normal) > EPSILON * normal.Magnitude then
                return false
            end
        end
    end
    return true
end

function Cut.split(solid, planePoint, planeNormal)
    assert(typeof(planePoint) == 'Vector3' and typeof(planeNormal) == 'Vector3', 'Expected plane vectors')
    assert(planeNormal.Magnitude > 0, 'Plane normal cannot be zero')
    if not FORM.validate(solid).ok then return nil, 'INVALID_INPUT' end
    if not convex(solid) then return nil, 'NON_CONVEX_INPUT' end

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
    local sides = {}

    local function intersection(a, b)
        if math.abs(distances[a]) <= EPSILON then return a end
        if math.abs(distances[b]) <= EPSILON then return b end

        local key = edgeKey(a, b)
        if intersections[key] then return intersections[key] end

        local ratio = distances[a] / (distances[a] - distances[b])
        local index = #solid.vertices + 1
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

        local ring = {}
        local seen = {}
        for _, edge in planeEdges do
            if edge.count == 1 then
                for _, index in {edge.a, edge.b} do
                    if not seen[index] then
                        seen[index] = true
                        ring[#ring + 1] = index
                    end
                end
            end
        end

        if #ring < 3 then return nil, 'INVALID_INTERSECTION_LOOP' end

        local center = Vector3.zero
        for _, index in ring do center += output.vertices[index] end
        center /= #ring

        local reference = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
        local axisX = reference:Cross(normal).Unit
        local axisY = normal:Cross(axisX)

        table.sort(ring, function(a, b)
            local pa, pb = output.vertices[a] - center, output.vertices[b] - center
            return math.atan2(pa:Dot(axisY), pa:Dot(axisX))
                < math.atan2(pb:Dot(axisY), pb:Dot(axisX))
        end)

        local centerId = #output.vertices + 1
        output.vertices[centerId] = center
        for i = 1, #ring do
            local a, b = ring[i], ring[i % #ring + 1]
            if sideIndex == 1 then
                triangle(centerId, b, a)
            else
                triangle(centerId, a, b)
            end
        end

        if not FORM.validate(output).ok then return nil, 'INVALID_OUTPUT' end
        sides[sideIndex] = output
    end

    local before = FORM.signedVolume(solid)
    local after = FORM.signedVolume(sides[1]) + FORM.signedVolume(sides[2])
    if math.abs(before - after) > math.max(1e-5, before * 1e-8) then
        return nil, 'VOLUME_MISMATCH'
    end

    return sides[1], sides[2]
end

return Cut
