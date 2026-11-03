local Shading = {}

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function cornerAngle(a, b, c)
    local u, v = b - a, c - a
    if u.Magnitude < 1e-9 or v.Magnitude < 1e-9 then return 0 end
    return math.acos(math.clamp(u:Dot(v) / (u.Magnitude * v.Magnitude), -1, 1))
end

function Shading.normals(solid, smoothAngle)
    smoothAngle = smoothAngle or 35
    assert(type(smoothAngle) == 'number' and smoothAngle >= 0 and smoothAngle <= 180,
        'Invalid smoothing angle')
    assert(type(solid) == 'table' and type(solid.triangles) == 'table'
        and type(solid.vertices) == 'table', 'Expected mesh data')

    local faceNormals, faceWeights, corners, edges = {}, {}, {}, {}
    for index, triangle in solid.triangles do
        local a, b, c = solid.vertices[triangle[1]],
            solid.vertices[triangle[2]], solid.vertices[triangle[3]]
        assert(a and b and c, 'Invalid triangle vertex')
        local cross = (b - a):Cross(c - a)
        assert(cross.Magnitude > 1e-10, 'Degenerate render triangle')
        faceNormals[index] = cross.Unit
        faceWeights[index] = cross.Magnitude * 0.5
        corners[index] = {
            cornerAngle(a, b, c),
            cornerAngle(b, c, a),
            cornerAngle(c, a, b),
        }
        for k = 1, 3 do
            local one, two = triangle[k], triangle[k % 3 + 1]
            local key = edgeKey(one, two)
            edges[key] = edges[key] or {}
            edges[key][#edges[key] + 1] = {face = index, a = one, b = two}
        end
    end

    local neighbors = {}
    for index, face in solid.triangles do
        neighbors[index] = {}
        for _, vertex in face do neighbors[index][vertex] = {} end
    end

    local blended = 0
    local threshold = math.cos(math.rad(smoothAngle))
    for _, pair in edges do
        if #pair ~= 2 then continue end
        local a, b = pair[1].face, pair[2].face
        local first, second = faceNormals[a], faceNormals[b]
        if first:Dot(second) < threshold then continue end
        local capA = math.abs(first.Y) > 0.999
        local capB = math.abs(second.Y) > 0.999
        if capA ~= capB then continue end

        blended += 1
        for _, vertex in {pair[1].a, pair[1].b} do
            neighbors[a][vertex][#neighbors[a][vertex] + 1] = b
            neighbors[b][vertex][#neighbors[b][vertex] + 1] = a
        end
    end

    local result = {}
    for index, face in solid.triangles do
        result[index] = {}
        for corner, vertex in face do
            local visited, queue = {[index] = true}, {index}
            local head, blendedNormal = 1, Vector3.zero
            while head <= #queue do
                local current = queue[head]
                head += 1
                local currentFace = solid.triangles[current]
                for j = 1, 3 do
                    if currentFace[j] == vertex then
                        local weight = math.max(0.0001, corners[current][j])
                        blendedNormal += faceNormals[current] * weight
                        break
                    end
                end
                for _, neighbor in neighbors[current][vertex] or {} do
                    if not visited[neighbor] then
                        visited[neighbor] = true
                        queue[#queue + 1] = neighbor
                    end
                end
            end
            result[index][corner] = if blendedNormal.Magnitude > 1e-8
                then blendedNormal.Unit else faceNormals[index]
        end
    end

    return result, {smoothedEdges = blended, faces = #solid.triangles}
end

return Shading
