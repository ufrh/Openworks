local Shading = {}

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function cornerAngle(a, b, c)
    local u, v = b - a, c - a
    local m = u.Magnitude * v.Magnitude
    if m < 1e-10 then return 0 end
    return math.acos(math.clamp(u:Dot(v) / m, -1, 1))
end

function Shading.normals(solid, smoothAngle)
    smoothAngle = smoothAngle or 35
    assert(type(smoothAngle) == 'number' and smoothAngle >= 0 and smoothAngle <= 180,
        'Invalid smoothing angle')

    local faces, vertices = solid.triangles, solid.vertices
    local normals, corners, edges = {}, {}, {}
    local perVertex = {}

    for index, triangle in faces do
        local a, b, c = vertices[triangle[1]], vertices[triangle[2]], vertices[triangle[3]]
        assert(a and b and c, 'Invalid render triangle')
        local normal = (b - a):Cross(c - a)
        assert(normal.Magnitude > 1e-10, 'Degenerate render triangle')
        normals[index] = normal.Unit
        corners[index] = {
            cornerAngle(a, b, c),
            cornerAngle(b, c, a),
            cornerAngle(c, a, b),
        }

        for k = 1, 3 do
            local vertex = triangle[k]
            perVertex[vertex] = perVertex[vertex] or {}
            perVertex[vertex][#perVertex[vertex] + 1] = {
                face = index, corner = k,
            }
            local nextVertex = triangle[k % 3 + 1]
            local key = edgeKey(vertex, nextVertex)
            edges[key] = edges[key] or {}
            edges[key][#edges[key] + 1] = index
        end
    end

    local neighbors = {}
    local function connect(vertex, a, b)
        neighbors[vertex] = neighbors[vertex] or {}
        local connections = neighbors[vertex]
        connections[a] = connections[a] or {}
        connections[b] = connections[b] or {}
        connections[a][#connections[a] + 1] = b
        connections[b][#connections[b] + 1] = a
    end

    local blended = 0
    local cosThreshold = math.cos(math.rad(smoothAngle))
    for key, pair in edges do
        if #pair ~= 2 then continue end
        local a, b = pair[1], pair[2]
        local na, nb = normals[a], normals[b]
        if na:Dot(nb) < cosThreshold then continue end
        if (math.abs(na.Y) > 0.999) ~= (math.abs(nb.Y) > 0.999) then continue end
        local colon = string.find(key, ':', 1, true)
        local v1 = tonumber(string.sub(key, 1, colon - 1))
        local v2 = tonumber(string.sub(key, colon + 1))
        connect(v1, a, b)
        connect(v2, a, b)
        blended += 1
    end

    local output = {}
    for index, _ in faces do
        output[index] = {normals[index], normals[index], normals[index]}
    end

    for vertex, faceCorners in perVertex do
        local cornerOf = {}
        for _, pair in faceCorners do
            cornerOf[pair.face] = pair.corner
        end
        local seen = {}
        local links = neighbors[vertex] or {}
        for _, pair in faceCorners do
            if seen[pair.face] then continue end
            local head, queue = 1, {pair.face}
            seen[pair.face] = true
            local average = Vector3.zero
            while head <= #queue do
                local current = queue[head]
                head += 1
                local corner = cornerOf[current]
                average += normals[current] * math.max(0.0001, corners[current][corner])
                for _, other in links[current] or {} do
                    if cornerOf[other] and not seen[other] then
                        seen[other] = true
                        queue[#queue + 1] = other
                    end
                end
            end
            local resolved = if average.Magnitude > 1e-9 then average.Unit else normals[pair.face]
            for _, index in queue do
                output[index][cornerOf[index]] = resolved
            end
        end
    end

    return output, {smoothedEdges = blended, faces = #faces}
end

return Shading
