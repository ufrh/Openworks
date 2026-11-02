local FORM = require(script.Parent)

local Weld = {}

local MAX_FACES = 8000
local MAX_VERTICES = 15000
local MAX_SCANS = 1000000
local MAX_REPAIRS = 5000

local function key(x, y, z)
    return tostring(x) .. ':' .. tostring(y) .. ':' .. tostring(z)
end

local function edgeKey(a, b)
    return key(math.min(a, b), math.max(a, b), 0)
end

local function coordinate(vector, axis)
    if axis == 1 then return vector.X end
    if axis == 2 then return vector.Y end
    return vector.Z
end

local function edgeCoordinate(a, b)
    local delta = b - a
    local x, y, z = math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z)
    if x >= y and x >= z then return 1 end
    if y >= z then return 2 end
    return 3
end

local function findFirst(sorted, vertices, axis, value)
    local lower, upper = 1, #sorted + 1
    while lower < upper do
        local midpoint = math.floor((lower + upper) / 2)
        if coordinate(vertices[sorted[midpoint]], axis) < value then
            lower = midpoint + 1
        else
            upper = midpoint
        end
    end
    return lower
end

local function onEdge(vertex, a, b, tolerance)
    local delta = b - a
    local squared = delta:Dot(delta)
    if squared <= tolerance * tolerance then return nil end
    local t = (vertex - a):Dot(delta) / squared
    local margin = tolerance / math.sqrt(squared)
    if t <= margin or t >= 1 - margin then return nil end
    if (vertex - (a + delta * t)).Magnitude > tolerance then return nil end
    return t
end

local function analyzeFans(solid)
    local incident = {}
    local adjacency = {}
    local edges = {}
    local neighbors = {}
    local used = {}

    for i, face in solid.triangles do
        for _, vertex in face do
            incident[vertex] = incident[vertex] or {}
            incident[vertex][#incident[vertex] + 1] = i
            adjacency[vertex] = adjacency[vertex] or {}
            adjacency[vertex][i] = {}
            used[vertex] = true
        end

        for j = 1, 3 do
            local a, b = face[j], face[j % 3 + 1]
            local signature = edgeKey(a, b)
            edges[signature] = edges[signature] or {a = a, b = b, faces = {}}
            edges[signature].faces[#edges[signature].faces + 1] = i
            neighbors[a] = neighbors[a] or {}
            neighbors[b] = neighbors[b] or {}
            neighbors[a][b] = true
            neighbors[b][a] = true
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

    local bows = 0
    for vertex, faces in incident do
        local visited = {[faces[1]] = true}
        local stack = {faces[1]}
        while #stack > 0 do
            local current = table.remove(stack)
            for other in adjacency[vertex][current] do
                if not visited[other] then
                    visited[other] = true
                    stack[#stack + 1] = other
                end
            end
        end
        for _, face in faces do
            if not visited[face] then
                bows += 1
                break
            end
        end
    end

    local components = 0
    local visited = {}
    local vertices = 0
    for vertex in used do vertices += 1 end

    for vertex in used do
        if visited[vertex] then continue end
        components += 1
        local stack = {vertex}
        visited[vertex] = true
        while #stack > 0 do
            local current = table.remove(stack)
            for other in neighbors[current] do
                if not visited[other] then
                    visited[other] = true
                    stack[#stack + 1] = other
                end
            end
        end
    end

    local edgeCount = 0
    for _ in edges do edgeCount += 1 end
    return bows, components, vertices - edgeCount + #solid.triangles
end

local function invalid(reason, input, output, removed, repaired, scans)
    return output, {
        valid = false,
        issues = {{code = reason}},
        issueCounts = {[reason] = 1},
        issueDetails = {},
        junctionDetails = {},
        tJunctions = 0,
        collapsedFaces = removed,
        repairedJunctions = repaired,
        converged = false,
        connectedComponents = 0,
        eulerCharacteristic = 0,
        verticesBefore = #input.vertices,
        verticesAfter = #output.vertices,
        trianglesAfter = #output.triangles,
        scanned = scans or 0,
        reason = reason,
    }
end

function Weld.build(surface, tolerance)
    tolerance = tolerance or 1e-4
    assert(type(tolerance) == 'number' and tolerance > 0, 'Invalid weld tolerance')
    assert(type(surface) == 'table' and type(surface.vertices) == 'table'
        and type(surface.triangles) == 'table', 'Invalid surface')

    local output = {vertices = {}, triangles = {}}
    if #surface.triangles > MAX_FACES or #surface.vertices > MAX_VERTICES then
        return invalid('INPUT_BUDGET_EXCEEDED', surface, output, 0, 0)
    end

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

    local removed = 0
    local seen = {}
    local used = {}
    for _, face in surface.triangles do
        local a, b, c = mapped[face[1]], mapped[face[2]], mapped[face[3]]
        local pa, pb, pc = output.vertices[a], output.vertices[b], output.vertices[c]
        if a == b or b == c or c == a
            or (pb - pa):Cross(pc - pa).Magnitude <= tolerance * tolerance then
            removed += 1
        else
            local sorted = {a, b, c}
            table.sort(sorted)
            local signature = table.concat(sorted, ':')
            if seen[signature] then
                removed += 1
            else
                seen[signature] = true
                output.triangles[#output.triangles + 1] = {a, b, c}
                used[a], used[b], used[c] = true, true, true
            end
        end
    end

    if #output.triangles == 0 then return invalid('EMPTY_MESH', surface, output, removed, 0) end

    local order = {{}, {}, {}}
    for index in used do
        for axis = 1, 3 do order[axis][#order[axis] + 1] = index end
    end
    for axis = 1, 3 do
        table.sort(order[axis], function(a, b)
            return coordinate(output.vertices[a], axis) < coordinate(output.vertices[b], axis)
        end)
    end

    local edges = {}
    for _, face in output.triangles do
        for j = 1, 3 do
            local a, b = face[j], face[j % 3 + 1]
            local signature = edgeKey(a, b)
            if not edges[signature] then edges[signature] = {a = a, b = b, splits = {}} end
        end
    end

    local scanned = 0
    local repaired = 0

    for _, edge in edges do
        local a, b = output.vertices[edge.a], output.vertices[edge.b]
        local axis = edgeCoordinate(a, b)
        local lo = math.min(coordinate(a, axis), coordinate(b, axis)) - tolerance
        local hi = math.max(coordinate(a, axis), coordinate(b, axis)) + tolerance
        local list = order[axis]
        local index = findFirst(list, output.vertices, axis, lo)

        while index <= #list do
            local vertexId = list[index]
            local vertex = output.vertices[vertexId]
            if coordinate(vertex, axis) > hi then break end
            if vertexId ~= edge.a and vertexId ~= edge.b then
                local t = onEdge(vertex, a, b, tolerance)
                if t then
                    edge.splits[#edge.splits + 1] = {vertex = vertexId, t = t}
                    repaired += 1
                    if repaired > MAX_REPAIRS then
                        return invalid('REPAIR_BUDGET_EXCEEDED', surface, output, removed, repaired, scanned)
                    end
                end
            end
            index += 1
            scanned += 1
            if scanned > MAX_SCANS then
                return invalid('SCAN_BUDGET_EXCEEDED', surface, output, removed, repaired, scanned)
            end
        end

        table.sort(edge.splits, function(first, second) return first.t < second.t end)
    end

    if repaired > 0 then
        local repairedFaces = {}
        for _, face in output.triangles do
            local boundary = {}
            local changed = false

            for i = 1, 3 do
                local a, b = face[i], face[i % 3 + 1]
                boundary[#boundary + 1] = a
                local edge = edges[edgeKey(a, b)]
                if #edge.splits > 0 then
                    changed = true
                    if a == edge.a then
                        for _, split in edge.splits do boundary[#boundary + 1] = split.vertex end
                    else
                        for j = #edge.splits, 1, -1 do
                            boundary[#boundary + 1] = edge.splits[j].vertex
                        end
                    end
                end
            end

            if not changed then
                repairedFaces[#repairedFaces + 1] = face
            else
                local center = Vector3.zero
                for _, index in boundary do center += output.vertices[index] end
                center /= #boundary
                local centerId = #output.vertices + 1
                output.vertices[centerId] = center

                for i = 1, #boundary do
                    local a, b = boundary[i], boundary[i % #boundary + 1]
                    if (output.vertices[a] - center):Cross(output.vertices[b] - center).Magnitude
                        > tolerance * tolerance then
                        repairedFaces[#repairedFaces + 1] = {centerId, a, b}
                    end
                end
            end
        end
        output.triangles = repairedFaces
    end

    if #output.triangles > MAX_FACES * 2 then
        return invalid('OUTPUT_BUDGET_EXCEEDED', surface, output, removed, repaired, scanned)
    end

    local checked = FORM.validate(output)
    local issueCounts = {}
    local issueDetails = {}
    for _, issue in checked.issues do
        issueCounts[issue.code] = (issueCounts[issue.code] or 0) + 1
        if (issue.code == 'NON_MANIFOLD_EDGE' or issue.code == 'INCONSISTENT_WINDING')
            and #issueDetails < 8 then
            local first, second = string.match(tostring(issue.index), '^(%d+):(%d+)$')
            local a, b = tonumber(first), tonumber(second)
            if a and b then
                issueDetails[#issueDetails + 1] = string.format('%s %s: %s -> %s',
                    issue.code, tostring(issue.index), tostring(output.vertices[a]), tostring(output.vertices[b]))
            end
        end
    end

    local bows, components, euler = analyzeFans(output)
    if bows > 0 then issueCounts.BOWTIE_VERTEX = bows end

    return output, {
        valid = checked.ok and bows == 0,
        issues = checked.issues,
        issueCounts = issueCounts,
        issueDetails = issueDetails,
        junctionDetails = {},
        tJunctions = 0,
        collapsedFaces = removed,
        repairedJunctions = repaired,
        converged = true,
        bowtieVertices = bows,
        connectedComponents = components,
        eulerCharacteristic = euler,
        verticesBefore = #surface.vertices,
        verticesAfter = #output.vertices,
        trianglesAfter = #output.triangles,
        scanned = scanned,
    }
end

return Weld
