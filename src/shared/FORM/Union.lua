local FORM = require(script.Parent)
local Weld = require(script.Parent.Weld)

local Union = {}
local EPSILON = 1e-5
local PLANE_TOLERANCE = 1e-4

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function faceGroups(solid)
    local groups = {}

    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local cross = (b - a):Cross(c - a)
        assert(cross.Magnitude > EPSILON * EPSILON, 'Degenerate convex face')
        local normal = cross.Unit
        local distance = normal:Dot(a)
        local group

        for _, existing in groups do
            if normal:Dot(existing.normal) >= 1 - 1e-6
                and math.abs(distance - existing.distance) <= PLANE_TOLERANCE then
                group = existing
                break
            end
        end

        if not group then
            group = {normal = normal, distance = distance, faces = {}}
            groups[#groups + 1] = group
        end
        group.faces[#group.faces + 1] = face
    end

    for _, group in groups do
        local edges = {}

        for _, face in group.faces do
            for i = 1, 3 do
                local a, b = face[i], face[i % 3 + 1]
                local key = edgeKey(a, b)
                if not edges[key] then
                    edges[key] = {a = a, b = b, count = 1}
                else
                    edges[key].count += 1
                end
            end
        end

        local nextVertex = {}
        local start, boundaryCount

        for _, edge in edges do
            if edge.count == 1 then
                assert(not nextVertex[edge.a], 'Branching planar face boundary')
                nextVertex[edge.a] = edge.b
                start = edge.a
                boundaryCount = (boundaryCount or 0) + 1
            else
                assert(edge.count == 2, 'Non-manifold planar face')
            end
        end

        assert(start and boundaryCount >= 3, 'Missing planar face boundary')
        local polygon = {}
        local current = start

        for _ = 1, boundaryCount do
            polygon[#polygon + 1] = solid.vertices[current]
            current = nextVertex[current]
            assert(current, 'Open planar face boundary')
        end

        assert(current == start, 'Multiple planar boundary loops')
        group.polygon = polygon
        group.faces = nil
    end

    return groups
end

local function clean(polygon)
    if #polygon < 3 then return {} end

    local result = {}
    for _, vertex in polygon do
        if #result == 0 or (result[#result] - vertex).Magnitude > EPSILON then
            result[#result + 1] = vertex
        end
    end

    if #result > 1 and (result[1] - result[#result]).Magnitude <= EPSILON then
        table.remove(result)
    end
    return if #result >= 3 then result else {}
end

local function clip(polygon, plane, inside)
    local output = {}
    if #polygon < 3 then return output end

    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        local da = a:Dot(plane.normal) - plane.distance
        local db = b:Dot(plane.normal) - plane.distance
        if math.abs(da) <= EPSILON then da = 0 end
        if math.abs(db) <= EPSILON then db = 0 end

        local acceptA = if inside then da <= 0 else da >= 0
        local acceptB = if inside then db <= 0 else db >= 0

        if acceptA then output[#output + 1] = a end
        if acceptA ~= acceptB and da ~= db then
            local t = math.clamp(da / (da - db), 0, 1)
            output[#output + 1] = a:Lerp(b, t)
        end
    end

    return clean(output)
end

local function classify(polygon, plane)
    local minimum, maximum = math.huge, -math.huge
    for _, vertex in polygon do
        local d = vertex:Dot(plane.normal) - plane.distance
        minimum = math.min(minimum, d)
        maximum = math.max(maximum, d)
    end
    if maximum <= EPSILON then return 'inside' end
    if minimum >= -EPSILON then return 'outside' end
    return 'crossing'
end

local function subtractPolygon(polygon, neighbor, sourceNormal)
    local fragments = {}
    local pending = {polygon}

    for _, plane in neighbor do
        local nextPending = {}

        for _, candidate in pending do
            local kind = classify(candidate, plane)
            if kind == 'inside' then
                nextPending[#nextPending + 1] = candidate
            elseif kind == 'outside' then
                fragments[#fragments + 1] = candidate
            else
                local outside = clip(candidate, plane, false)
                local inside = clip(candidate, plane, true)
                if #outside >= 3 then fragments[#fragments + 1] = outside end
                if #inside >= 3 then nextPending[#nextPending + 1] = inside end
            end
        end

        pending = nextPending
        if #pending == 0 then break end
    end

    return fragments
end

local function append(output, polygon, normal)
    local count = 0
    local first = polygon[1]

    for i = 2, #polygon - 1 do
        local b, c = polygon[i], polygon[i + 1]
        local cross = (b - first):Cross(c - first)
        if cross.Magnitude > EPSILON * EPSILON then
            local offset = #output.vertices
            output.vertices[offset + 1] = first
            output.vertices[offset + 2] = b
            output.vertices[offset + 3] = c
            output.triangles[#output.triangles + 1] = if cross:Dot(normal) > 0
                then {offset + 1, offset + 2, offset + 3}
                else {offset + 1, offset + 3, offset + 2}
            count += 1
        end
    end

    return count
end

function Union.surface(pieces)
    assert(type(pieces) == 'table' and #pieces > 0, 'Expected convex pieces')
    local groups = {}
    local stats = {inputTriangles = 0, inputFaces = 0, outputFaces = 0, outputTriangles = 0}

    for index, piece in pieces do
        assert(FORM.validate(piece).ok, 'Invalid convex piece ' .. index)
        stats.inputTriangles += #piece.triangles
        groups[index] = faceGroups(piece)
        stats.inputFaces += #groups[index]
    end

    local output = {vertices = {}, triangles = {}}

    for i, source in groups do
        for _, face in source do
            local visible = {face.polygon}

            for j, neighbor in groups do
                if i == j then continue end

                local sharedExterior = false
                for _, plane in neighbor do
                    if face.normal:Dot(plane.normal) >= 1 - 1e-6
                        and math.abs(face.distance - plane.distance) <= PLANE_TOLERANCE then
                        sharedExterior = true
                        break
                    end
                end

                if not sharedExterior then
                    local nextVisible = {}
                    for _, polygon in visible do
                        local fragments = subtractPolygon(polygon, neighbor, face.normal)
                        for _, fragment in fragments do nextVisible[#nextVisible + 1] = fragment end
                    end
                    visible = nextVisible
                end

                if #visible == 0 then break end
            end

            for _, polygon in visible do
                local n = append(output, polygon, face.normal)
                if n > 0 then stats.outputFaces += 1 end
            end
        end
    end

    stats.outputTriangles = #output.triangles
    return output, stats
end

function Union.reconstruct(pieces, expectedVolume, tolerance)
    local surface, surfaceStats = Union.surface(pieces)
    local welded, weldStats = Weld.build(surface, tolerance)
    local stats = {surface = surfaceStats, weld = weldStats}

    if not weldStats.valid then
        return nil, 'NON_MANIFOLD_SURFACE', stats
    end

    local expected = expectedVolume
    if expected == nil then
        expected = 0
        for _, piece in pieces do expected += FORM.signedVolume(piece) end
    end

    local actual = FORM.signedVolume(welded)
    stats.volume = actual
    stats.expectedVolume = expected
    if not FORM.volumeClose(actual, expected) then
        return nil, 'VOLUME_MISMATCH', stats
    end

    return welded, nil, stats
end

return Union
