local FORM = require(script.Parent)

local Weld = {}

local function key(x, y, z)
    return tostring(x) .. ':' .. tostring(y) .. ':' .. tostring(z)
end

local function edgeKey(a, b)
    return key(math.min(a, b), math.max(a, b), 0)
end

local function vertexOnEdge(vertex, a, b, tolerance)
    local delta = b - a
    local lengthSquared = delta:Dot(delta)
    if lengthSquared <= tolerance * tolerance then return nil end

    local t = (vertex - a):Dot(delta) / lengthSquared
    local margin = tolerance / math.sqrt(lengthSquared)
    if t <= margin or t >= 1 - margin then return nil end
    if (vertex - (a + delta * t)).Magnitude > tolerance then return nil end
    return t
end

local function faceArea(vertices, face)
    local a, b, c = vertices[face[1]], vertices[face[2]], vertices[face[3]]
    return (b - a):Cross(c - a).Magnitude
end

local function compactFaces(solid, tolerance)
    local seen = {}
    local output = {}
    local removed = 0

    for _, face in solid.triangles do
        local a, b, c = face[1], face[2], face[3]
        if a == b or b == c or c == a or faceArea(solid.vertices, face) <= tolerance * tolerance then
            removed += 1
        else
            local sorted = {a, b, c}
            table.sort(sorted)
            local signature = table.concat(sorted, ':')
            if seen[signature] then
                removed += 1
            else
                seen[signature] = true
                output[#output + 1] = face
            end
        end
    end

    solid.triangles = output
    return removed
end

local function findJunction(solid, face, tolerance)
    local vertices = solid.vertices
    local foundEdge, foundVertex, foundT

    for edge = 1, 3 do
        local a = face[edge]
        local b = face[edge % 3 + 1]
        local other = face[(edge + 1) % 3 + 1]

        for index, vertex in vertices do
            if index == a or index == b or index == other then continue end
            local t = vertexOnEdge(vertex, vertices[a], vertices[b], tolerance)
            if t and (not foundT or t < foundT) then
                foundEdge, foundVertex, foundT = edge, index, t
            end
        end
    end

    return foundEdge, foundVertex, foundT
end

local function junctions(solid, tolerance)
    local count = 0
    local details = {}
    local seen = {}
    local used = {}

    for _, face in solid.triangles do
        for _, index in face do used[index] = true end
    end

    for _, face in solid.triangles do
        for edge = 1, 3 do
            local a, b = face[edge], face[edge % 3 + 1]
            local signature = edgeKey(a, b)
            if not seen[signature] then
                seen[signature] = true
                for index, vertex in solid.vertices do
                    if used[index] and index ~= a and index ~= b then
                        local t = vertexOnEdge(vertex, solid.vertices[a], solid.vertices[b], tolerance)
                        if t then
                            count += 1
                            if #details < 12 then
                                details[#details + 1] = string.format('edge %d:%d vertex %d t=%.6f at %s',
                                    a, b, index, t, tostring(vertex))
                            end
                        end
                    end
                end
            end
        end
    end

    return count, details
end

local function fanDefects(solid)
    local incident = {}
    local adjacency = {}

    for i, face in solid.triangles do
        for _, v in face do
            incident[v] = incident[v] or {}
            incident[v][#incident[v] + 1] = i
            adjacency[v] = adjacency[v] or {}
            adjacency[v][i] = {}
        end
    end

    local edges = {}
    for i, face in solid.triangles do
        for edge = 1, 3 do
            local a, b = face[edge], face[edge % 3 + 1]
            local signature = edgeKey(a, b)
            edges[signature] = edges[signature] or {a = a, b = b, faces = {}}
            edges[signature].faces[#edges[signature].faces + 1] = i
        end
    end

    for _, edge in edges do
        if #edge.faces == 2 then
            local a, b = edge.faces[1], edge.faces[2]
            for _, vertex in {edge.a, edge.b} do
                adjacency[vertex][a][b] = true
                adjacency[vertex][b][a] = true
            end
        end
    end

    local defects = 0
    for vertex, faces in incident do
        local visited = {}
        local stack = {faces[1]}
        visited[faces[1]] = true
        while #stack > 0 do
            local current = table.remove(stack)
            for neighbor in adjacency[vertex][current] do
                if not visited[neighbor] then
                    visited[neighbor] = true
                    stack[#stack + 1] = neighbor
                end
            end
        end

        for _, face in faces do
            if not visited[face] then
                defects += 1
                break
            end
        end
    end

    return defects
end

function Weld.build(surface, tolerance)
    tolerance = tolerance or 1e-4
    assert(type(tolerance) == 'number' and tolerance > 0, 'Invalid weld tolerance')
    assert(type(surface) == 'table' and type(surface.vertices) == 'table'
        and type(surface.triangles) == 'table', 'Invalid surface')

    local output = {vertices = {}, triangles = {}}
    local buckets = {}
    local mapped = {}

    for i, vertex in surface.vertices do
        local x = math.floor(vertex.X / tolerance + 0.5)
        local y = math.floor(vertex.Y / tolerance + 0.5)
        local z = math.floor(vertex.Z / tolerance + 0.5)
        local found

        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    for _, index in buckets[key(x + dx, y + dy, z + dz)] or {} do
                        if (output.vertices[index] - vertex).Magnitude <= tolerance then
                            found = index
                            break
                        end
                    end
                    if found then break end
                end
                if found then break end
            end
            if found then break end
        end

        if not found then
            found = #output.vertices + 1
            output.vertices[found] = vertex
            local bucket = key(x, y, z)
            buckets[bucket] = buckets[bucket] or {}
            buckets[bucket][#buckets[bucket] + 1] = found
        end

        mapped[i] = found
    end

    for _, face in surface.triangles do
        output.triangles[#output.triangles + 1] = {
            mapped[face[1]], mapped[face[2]], mapped[face[3]],
        }
    end

    local removed = compactFaces(output, tolerance)
    local repaired = 0
    local converged = false

    for _ = 1, 64 do
        local nextFaces = {}
        local changed = false

        for _, face in output.triangles do
            local edge, vertex = findJunction(output, face, tolerance)
            if edge then
                local a = face[edge]
                local b = face[edge % 3 + 1]
                local other = face[(edge + 1) % 3 + 1]
                nextFaces[#nextFaces + 1] = {a, vertex, other}
                nextFaces[#nextFaces + 1] = {vertex, b, other}
                repaired += 1
                changed = true
            else
                nextFaces[#nextFaces + 1] = face
            end
        end

        output.triangles = nextFaces
        removed += compactFaces(output, tolerance)
        if not changed then
            converged = true
            break
        end
    end

    local remaining, junctionDetails = junctions(output, tolerance)
    local validation = FORM.validate(output)
    local issueCounts = {}
    local issueDetails = {}

    for _, issue in validation.issues do
        issueCounts[issue.code] = (issueCounts[issue.code] or 0) + 1
        if (issue.code == 'NON_MANIFOLD_EDGE' or issue.code == 'INCONSISTENT_WINDING')
            and #issueDetails < 12 then
            local first, second = string.match(tostring(issue.index), '^(%d+):(%d+)$')
            local a, b = tonumber(first), tonumber(second)
            if a and b then
                issueDetails[#issueDetails + 1] = string.format('%s %s: %s -> %s',
                    issue.code, tostring(issue.index), tostring(output.vertices[a]), tostring(output.vertices[b]))
            end
        end
    end

    local usedVertices = {}
    local meshEdges = {}
    local neighbors = {}
    for _, face in output.triangles do
        for edge = 1, 3 do
            local a, b = face[edge], face[edge % 3 + 1]
            usedVertices[a] = true
            usedVertices[b] = true
            meshEdges[edgeKey(a, b)] = true
            neighbors[a] = neighbors[a] or {}
            neighbors[b] = neighbors[b] or {}
            neighbors[a][b] = true
            neighbors[b][a] = true
        end
    end

    local vertexCount, edgeCount, components = 0, 0, 0
    for _ in usedVertices do vertexCount += 1 end
    for _ in meshEdges do edgeCount += 1 end
    local visited = {}
    for vertex in usedVertices do
        if not visited[vertex] then
            components += 1
            local stack = {vertex}
            visited[vertex] = true
            while #stack > 0 do
                local current = table.remove(stack)
                for adjacent in neighbors[current] do
                    if not visited[adjacent] then
                        visited[adjacent] = true
                        stack[#stack + 1] = adjacent
                    end
                end
            end
        end
    end

    local bows = fanDefects(output)
    if bows > 0 then issueCounts.BOWTIE_VERTEX = bows end

    return output, {
        valid = validation.ok and converged and remaining == 0 and bows == 0,
        issues = validation.issues,
        issueCounts = issueCounts,
        issueDetails = issueDetails,
        tJunctions = remaining,
        junctionDetails = junctionDetails,
        collapsedFaces = removed,
        repairedJunctions = repaired,
        converged = converged and remaining == 0,
        bowtieVertices = bows,
        connectedComponents = components,
        eulerCharacteristic = vertexCount - edgeCount + #output.triangles,
        verticesBefore = #surface.vertices,
        verticesAfter = #output.vertices,
        trianglesAfter = #output.triangles,
    }
end

return Weld
