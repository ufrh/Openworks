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

    local edges = {}
    for _, face in output.triangles do
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
                if i == edge[1] or i == edge[2] then continue end
                local t = (vertex - a):Dot(delta) / lengthSquared
                if t > tolerance / math.sqrt(lengthSquared) and t < 1 - tolerance / math.sqrt(lengthSquared)
                    and (vertex - (a + delta * t)).Magnitude <= tolerance then
                    junctions += 1
                end
            end
        end
    end

    local result = FORM.validate(output)
    return output, {
        valid = result.ok and junctions == 0 and collapsed == 0,
        issues = result.issues,
        tJunctions = junctions,
        collapsedFaces = collapsed,
        verticesBefore = #surface.vertices,
        verticesAfter = #output.vertices,
        trianglesAfter = #output.triangles,
    }
end

return Weld
