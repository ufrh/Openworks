local FORM = require(script.Parent)

local Shading = {}

local PLANE_NORMAL_TOLERANCE = 1e-6
local PLANE_DISTANCE_TOLERANCE = 1e-3
local AXIS_TOLERANCE = 1e-3

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function cornerAngle(a, b, c)
    local x, y = b - a, c - a
    if x.Magnitude <= 1e-10 or y.Magnitude <= 1e-10 then return 0 end
    return math.acos(math.clamp(x:Dot(y) / (x.Magnitude * y.Magnitude), -1, 1))
end

local function robustNormal(a, b, c)
    local ax, ay, az = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local bx, by, bz = c.X - a.X, c.Y - a.Y, c.Z - a.Z
    local nx = ay * bz - az * by
    local ny = az * bx - ax * bz
    local nz = ax * by - ay * bx
    local magnitude = math.sqrt(nx * nx + ny * ny + nz * nz)
    assert(magnitude > 1e-10, 'Degenerate render triangle')

    local normal = Vector3.new(nx / magnitude, ny / magnitude, nz / magnitude)
    local planeAxis

    if math.max(a.X, b.X, c.X) - math.min(a.X, b.X, c.X) < AXIS_TOLERANCE
        and math.abs(nx) / magnitude > 0.9999 then
        planeAxis = Vector3.new(if nx >= 0 then 1 else -1, 0, 0)
    elseif math.max(a.Y, b.Y, c.Y) - math.min(a.Y, b.Y, c.Y) < AXIS_TOLERANCE
        and math.abs(ny) / magnitude > 0.9999 then
        planeAxis = Vector3.new(0, if ny >= 0 then 1 else -1, 0)
    elseif math.max(a.Z, b.Z, c.Z) - math.min(a.Z, b.Z, c.Z) < AXIS_TOLERANCE
        and math.abs(nz) / magnitude > 0.9999 then
        planeAxis = Vector3.new(0, 0, if nz >= 0 then 1 else -1)
    end

    return planeAxis or normal, magnitude / 2
end

function Shading.normals(solid, smoothAngle)
    smoothAngle = smoothAngle or 30
    assert(type(smoothAngle) == 'number' and smoothAngle >= 0 and smoothAngle <= 180,
        'Invalid smoothing angle')
    assert(type(solid) == 'table' and type(solid.triangles) == 'table'
        and type(solid.vertices) == 'table', 'Expected mesh data')

    local groups, normals, faceGroups, corners, edges = {}, {}, {}, {}, {}

    for i, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        assert(a and b and c, 'Invalid render triangle indices')
        local normal, area = robustNormal(a, b, c)
        local distance = normal:Dot(a)
        local groupId

        for j, group in groups do
            if normal:Dot(group.normal) >= 1 - PLANE_NORMAL_TOLERANCE
                and math.abs(distance - group.distance) <= PLANE_DISTANCE_TOLERANCE then
                groupId = j
                break
            end
        end

        if not groupId then
            groupId = #groups + 1
            groups[groupId] = {normal = normal, distance = distance, area = 0, faces = 0}
        end

        local group = groups[groupId]
        group.area += area
        group.faces += 1
        faceGroups[i] = groupId
        corners[i] = {
            cornerAngle(a, b, c),
            cornerAngle(b, c, a),
            cornerAngle(c, a, b),
        }

        for j = 1, 3 do
            local p, q = face[j], face[j % 3 + 1]
            local key = edgeKey(p, q)
            edges[key] = edges[key] or {}
            edges[key][#edges[key] + 1] = {face = i, a = p, b = q}
        end
    end

    local maxArea = 0
    for _, group in groups do maxArea = math.max(maxArea, group.area) end
    local protectAbove = maxArea * 0.15

    for i, face in solid.triangles do
        normals[i] = {}
        local normal = groups[faceGroups[i]].normal
        for corner = 1, 3 do normals[i][corner] = normal end
    end

    if smoothAngle == 0 then
        return normals, {planarGroups = #groups, protectedGroups = #groups, smoothedEdges = 0}
    end

    local neighbors = {}
    for i, face in solid.triangles do
        neighbors[i] = {}
        for _, vertex in face do neighbors[i][vertex] = {} end
    end

    local threshold = math.cos(math.rad(smoothAngle))
    local blendedEdges = 0
    for _, pair in edges do
        if #pair ~= 2 then continue end
        local a, b = pair[1].face, pair[2].face
        local groupA, groupB = groups[faceGroups[a]], groups[faceGroups[b]]
        if groupA == groupB or groupA.area >= protectAbove or groupB.area >= protectAbove then
            continue
        end
        if groupA.normal:Dot(groupB.normal) < threshold then continue end

        blendedEdges += 1
        for _, vertex in {pair[1].a, pair[1].b} do
            neighbors[a][vertex][#neighbors[a][vertex] + 1] = b
            neighbors[b][vertex][#neighbors[b][vertex] + 1] = a
        end
    end

    for i, face in solid.triangles do
        local group = groups[faceGroups[i]]
        if group.area >= protectAbove then continue end

        for corner, vertex in face do
            local seen = {[i] = true}
            local queue = {i}
            local head = 1
            local sum = Vector3.zero

            while head <= #queue do
                local current = queue[head]
                head += 1
                local currentFace = solid.triangles[current]
                local index

                for j = 1, 3 do
                    if currentFace[j] == vertex then index = j break end
                end

                if index then
                    local weight = corners[current][index]
                    sum += groups[faceGroups[current]].normal * weight
                end

                for _, other in neighbors[current][vertex] or {} do
                    if not seen[other] then
                        seen[other] = true
                        queue[#queue + 1] = other
                    end
                end
            end

            if sum.Magnitude > 1e-9 then normals[i][corner] = sum.Unit end
        end
    end

    local protected = 0
    for _, group in groups do
        if group.area >= protectAbove then protected += 1 end
    end
    return normals, {
        planarGroups = #groups,
        protectedGroups = protected,
        smoothedEdges = blendedEdges,
    }
end

return Shading
