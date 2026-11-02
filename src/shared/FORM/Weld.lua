local FORM = require(script.Parent)

local Weld = {}

local function key(x, y, z)
    return x .. ':' .. y .. ':' .. z
end

function Weld.build(surface, tolerance)
    tolerance = tolerance or 1e-4
    assert(type(tolerance) == 'number' and tolerance > 0, 'Invalid weld tolerance')

    local output = {vertices = {}, triangles = {}}
    local buckets = {}
    local mapped = {}
    local collapsed = 0

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

        if found then
            mapped[i] = found
        else
            local index = #output.vertices + 1
            output.vertices[index] = vertex
            mapped[i] = index
            local bucket = key(x, y, z)
            buckets[bucket] = buckets[bucket] or {}
            table.insert(buckets[bucket], index)
        end
    end

    local faces = {}
    for _, triangle in surface.triangles do
        local a, b, c = mapped[triangle[1]], mapped[triangle[2]], mapped[triangle[3]]
        if a == b or b == c or c == a then
            collapsed += 1
        else
            local indices = {a, b, c}
            local sorted = {a, b, c}
            table.sort(sorted)
            local signature = table.concat(sorted, ':')
            if not faces[signature] then
                faces[signature] = true
                output.triangles[#output.triangles + 1] = indices
            else
                collapsed += 1
            end
        end
    end

    local function splitJunctions()
        local resolved = 0
        for pass = 1, 12 do
            local changed = false
            local nextTriangles = {}

            for _, face in output.triangles do
                local bestEdge, bestVertex, bestT

                for edgeIndex = 1, 3 do
                    local a = face[edgeIndex]
                    local b = face[edgeIndex % 3 + 1]
                    local start = output.vertices[a]
                    local delta = output.vertices[b] - start
                    local lengthSquared = delta:Dot(delta)

                    if lengthSquared > tolerance * tolerance then
                        local margin = tolerance / math.sqrt(lengthSquared)
                        for index, vertex in output.vertices do
                            if index == a or index == b or index == face[(edgeIndex + 1) % 3 + 1] then continue end
                            local t = (vertex - start):Dot(delta) / lengthSquared

                            if t > margin and t < 1 - margin
                                and (vertex - (start + delta * t)).Magnitude <= tolerance then
                                if not bestT or t < bestT then
                                    bestEdge, bestVertex, bestT = edgeIndex, index, t
                                end
                            end
                        end
                    end
                end

                if bestEdge then
                    local a = face[bestEdge]
                    local b = face[bestEdge % 3 + 1]
                    local third = face[(bestEdge + 1) % 3 + 1]
                    nextTriangles[#nextTriangles + 1] = {a, bestVertex, third}
                    nextTriangles[#nextTriangles + 1] = {bestVertex, b, third}
                    resolved += 1
                    changed = true
                else
                    nextTriangles[#nextTriangles + 1] = face
                end
            end

            output.triangles = nextTriangles
            if not changed then return resolved, true end
        end

        return resolved, false
    end

    local resolved, converged = splitJunctions()

    local edges = {}
    local used = {}
    for _, face in output.triangles do
        for _, index in face do used[index] = true end
        for i = 1, 3 do
            local a, b = face[i], face[i % 3 + 1]
            if a > b then a, b = b, a end
            edges[key(a, b, 0)] = {a, b}
        end
    end

    local junctions = 0
    for _, edge in edges do
        local a, b = output.vertices[edge[1]], output.vertices[edge[2]]
        local delta = b - a
        local lengthSquared = delta:Dot(delta)
        if lengthSquared > tolerance * tolerance then
            for i, vertex in output.vertices do
                if not used[i] or i == edge[1] or i == edge[2] then continue end
                local t = (vertex - a):Dot(delta) / lengthSquared
                if t > tolerance / math.sqrt(lengthSquared) and t < 1 - tolerance / math.sqrt(lengthSquared)
                    and (vertex - (a + delta * t)).Magnitude <= tolerance then
                    junctions += 1
                end
            end
        end
    end

    local result = FORM.validate(output)
    local issueCounts = {}
    for _, issue in result.issues do
        issueCounts[issue.code] = (issueCounts[issue.code] or 0) + 1
    end
    return output, {
        valid = result.ok and junctions == 0 and converged,
        issues = result.issues,
        issueCounts = issueCounts,
        tJunctions = junctions,
        collapsedFaces = collapsed,
        repairedJunctions = resolved,
        converged = converged and junctions == 0,
        verticesBefore = #surface.vertices,
        verticesAfter = #output.vertices,
        trianglesAfter = #output.triangles,
    }
end

return Weld
