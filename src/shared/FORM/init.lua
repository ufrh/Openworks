local FORM = {}

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function validVector(v)
    return typeof(v) == 'Vector3' and finite(v.X) and finite(v.Y) and finite(v.Z)
end

function FORM.volumeTolerance(volume)
    return math.max(1e-5, math.min(0.002, math.abs(volume) * 1e-6), math.abs(volume) * 1e-7)
end

function FORM.volumeClose(actual, expected)
    return math.abs(actual - expected) <= FORM.volumeTolerance(expected)
end

function FORM.box(size)
    assert(validVector(size) and size.X > 0 and size.Y > 0 and size.Z > 0, 'Invalid box dimensions')

    local x, y, z = size.X / 2, size.Y / 2, size.Z / 2
    local vertices = {
        Vector3.new(-x, -y, -z), Vector3.new(x, -y, -z),
        Vector3.new(x, y, -z), Vector3.new(-x, y, -z),
        Vector3.new(-x, -y, z), Vector3.new(x, -y, z),
        Vector3.new(x, y, z), Vector3.new(-x, y, z),
    }
    local triangles = {
        {1, 3, 2}, {1, 4, 3},
        {5, 6, 7}, {5, 7, 8},
        {1, 2, 6}, {1, 6, 5},
        {4, 8, 7}, {4, 7, 3},
        {1, 5, 8}, {1, 8, 4},
        {2, 3, 7}, {2, 7, 6},
    }
    return {vertices = vertices, triangles = triangles}
end

function FORM.cylinder(radius, height, segments)
    segments = segments or 12
    assert(finite(radius) and radius > 0 and finite(height) and height > 0, 'Invalid cylinder dimensions')
    assert(type(segments) == 'number' and segments % 1 == 0 and segments >= 3 and segments <= 64,
        'Cylinder segments must be between 3 and 64')

    local vertices = {}
    local triangles = {}
    local half = height / 2

    for i = 0, segments - 1 do
        local angle = i * 2 * math.pi / segments
        local x, z = radius * math.cos(angle), radius * math.sin(angle)
        vertices[#vertices + 1] = Vector3.new(x, -half, z)
        vertices[#vertices + 1] = Vector3.new(x, half, z)
    end

    local bottom = #vertices + 1
    vertices[bottom] = Vector3.new(0, -half, 0)
    local top = #vertices + 1
    vertices[top] = Vector3.new(0, half, 0)

    for i = 0, segments - 1 do
        local nextIndex = (i + 1) % segments
        local a, b = 2 * i + 1, 2 * i + 2
        local c, d = 2 * nextIndex + 1, 2 * nextIndex + 2
        triangles[#triangles + 1] = {a, b, c}
        triangles[#triangles + 1] = {c, b, d}
        triangles[#triangles + 1] = {bottom, a, c}
        triangles[#triangles + 1] = {top, d, b}
    end

    return {vertices = vertices, triangles = triangles}
end

function FORM.bounds(solid)
    assert(type(solid) == 'table' and #solid.vertices > 0, 'Expected a solid with vertices')
    local lo, hi = solid.vertices[1], solid.vertices[1]
    for i = 2, #solid.vertices do
        local v = solid.vertices[i]
        assert(validVector(v), 'Invalid vertex')
        lo = Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z))
        hi = Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z))
    end
    return lo, hi
end

function FORM.signedVolume(solid)
    local total = 0
    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        assert(a and b and c, 'Invalid triangle')
        total += a:Dot(b:Cross(c)) / 6
    end
    return total
end

function FORM.validate(solid)
    local issues = {}
    local function report(code, index)
        table.insert(issues, {code = code, index = index})
    end

    if type(solid) ~= 'table' or type(solid.vertices) ~= 'table' or type(solid.triangles) ~= 'table' then
        report('INVALID_SOLID')
        return {ok = false, issues = issues}
    end

    if #solid.vertices < 4 or #solid.triangles < 4 then report('INSUFFICIENT_GEOMETRY') end
    for i, v in solid.vertices do
        if not validVector(v) then report('INVALID_VERTEX', i) end
    end

    local edges = {}
    local usable = true
    for i, face in solid.triangles do
        if type(face) ~= 'table' or #face ~= 3 then
            report('INVALID_FACE', i)
            usable = false
            continue
        end
        local a, b, c = face[1], face[2], face[3]
        local function indexOk(n)
            return type(n) == 'number' and n % 1 == 0 and n >= 1 and n <= #solid.vertices
        end
        if not indexOk(a) or not indexOk(b) or not indexOk(c) or a == b or b == c or c == a then
            report('INVALID_FACE', i)
            usable = false
            continue
        end

        local va, vb, vc = solid.vertices[a], solid.vertices[b], solid.vertices[c]
        if not validVector(va) or not validVector(vb) or not validVector(vc) then
            usable = false
            continue
        end
        if (vb - va):Cross(vc - va).Magnitude <= 1e-10 then report('DEGENERATE_FACE', i) end

        for _, pair in {{a, b}, {b, c}, {c, a}} do
            local u, v = pair[1], pair[2]
            local low, high = math.min(u, v), math.max(u, v)
            local key = tostring(low) .. ':' .. tostring(high)
            local edge = edges[key] or {count = 0, direction = 0}
            edge.count += 1
            edge.direction += if u == low then 1 else -1
            edges[key] = edge
        end
    end

    for key, edge in edges do
        if edge.count ~= 2 then report('NON_MANIFOLD_EDGE', key)
        elseif edge.direction ~= 0 then report('INCONSISTENT_WINDING', key) end
    end
    if usable and #issues == 0 and FORM.signedVolume(solid) <= 0 then report('NON_POSITIVE_VOLUME') end

    return {ok = #issues == 0, issues = issues, edges = edges}
end

return FORM
