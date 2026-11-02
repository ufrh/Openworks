local AssetService = game:GetService('AssetService')

local Renderer = {}

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function normalsFor(solid, angle)
    local faces = solid.triangles
    local incident = {}
    local edges = {}
    local normals = {}
    local neighbors = {}

    for i, face in faces do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a)
        assert(normal.Magnitude > 0, 'Degenerate render triangle')
        normals[i] = normal
        neighbors[i] = {}

        for _, vertex in face do
            incident[vertex] = incident[vertex] or {}
            table.insert(incident[vertex], i)
        end

        for j = 1, 3 do
            local u, v = face[j], face[j % 3 + 1]
            local key = edgeKey(u, v)
            edges[key] = edges[key] or {}
            table.insert(edges[key], {face = i, a = u, b = v})
        end
    end

    local threshold = math.cos(math.rad(angle))
    for _, pair in edges do
        if #pair == 2 then
            local a, b = pair[1].face, pair[2].face
            if normals[a].Unit:Dot(normals[b].Unit) >= threshold then
                local u, v = pair[1].a, pair[1].b
                neighbors[a][u] = neighbors[a][u] or {}
                neighbors[a][v] = neighbors[a][v] or {}
                neighbors[b][u] = neighbors[b][u] or {}
                neighbors[b][v] = neighbors[b][v] or {}
                table.insert(neighbors[a][u], b)
                table.insert(neighbors[a][v], b)
                table.insert(neighbors[b][u], a)
                table.insert(neighbors[b][v], a)
            end
        end
    end

    local result = {}
    for i, face in faces do
        result[i] = {}
        for corner, vertex in face do
            local visited = {[i] = true}
            local queue = {i}
            local sum = Vector3.zero
            local head = 1

            while head <= #queue do
                local current = queue[head]
                head += 1
                sum += normals[current]

                for _, other in neighbors[current][vertex] or {} do
                    if not visited[other] then
                        visited[other] = true
                        table.insert(queue, other)
                    end
                end
            end

            result[i][corner] = sum.Unit
        end
    end

    return result
end

function Renderer.create(solid, studsPerMillimeter, smoothAngle)
    assert(type(studsPerMillimeter) == 'number' and studsPerMillimeter > 0, 'Invalid display scale')
    smoothAngle = smoothAngle or 30
    assert(type(smoothAngle) == 'number' and smoothAngle >= 0 and smoothAngle <= 180, 'Invalid smoothing angle')

    local editable = AssetService:CreateEditableMesh()
    assert(editable, 'EditableMesh could not be allocated. Check mesh permissions and memory limits.')

    local ids = {}
    for i, position in solid.vertices do
        ids[i] = editable:AddVertex(position * studsPerMillimeter)
    end

    local shading = normalsFor(solid, smoothAngle)
    for i, triangle in solid.triangles do
        local faceId = editable:AddTriangle(ids[triangle[1]], ids[triangle[2]], ids[triangle[3]])
        local normalIds = {}
        for corner = 1, 3 do
            normalIds[corner] = editable:AddNormal(shading[i][corner])
        end
        editable:SetFaceNormals(faceId, normalIds)
    end

    local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
        CollisionFidelity = Enum.CollisionFidelity.Hull,
    })
    return part, editable
end

function Renderer.createMany(solids, studsPerMillimeter, smoothAngle)
    local combined = {vertices = {}, triangles = {}}

    for _, solid in solids do
        local offset = #combined.vertices
        for _, vertex in solid.vertices do
            combined.vertices[#combined.vertices + 1] = vertex
        end
        for _, triangle in solid.triangles do
            combined.triangles[#combined.triangles + 1] = {
                triangle[1] + offset,
                triangle[2] + offset,
                triangle[3] + offset,
            }
        end
    end

    return Renderer.create(combined, studsPerMillimeter, smoothAngle)
end

return Renderer
