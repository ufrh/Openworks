local FORM = require(script.Parent)
local Weld = require(script.Parent.Weld)

local Union = {}

local EPSILON = 1e-5
local PLANE_TOLERANCE = 1e-4
local SAMPLE_OFFSET = 0.001
local MAX_PLANES = 100
local MAX_FACES = 500
local MAX_CELLS = 3500
local MAX_TRIANGLES = 8000

local function edgeKey(a, b)
    return tostring(math.min(a, b)) .. ':' .. tostring(math.max(a, b))
end

local function samePlane(a, b)
    local dot = a.normal:Dot(b.normal)
    return math.abs(dot) >= 1 - 1e-6
        and math.abs(a.distance - b.distance * dot) <= PLANE_TOLERANCE
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
        local boundary = {}
        for _, face in group.faces do
            for i = 1, 3 do
                local a, b = face[i], face[i % 3 + 1]
                local signature = edgeKey(a, b)
                if boundary[signature] then
                    boundary[signature].count += 1
                else
                    boundary[signature] = {a = a, b = b, count = 1}
                end
            end
        end

        local successor = {}
        local start
        local count = 0

        for _, edge in boundary do
            if edge.count == 1 then
                assert(not successor[edge.a], 'Branched convex face boundary')
                successor[edge.a] = edge.b
                start = edge.a
                count += 1
            else
                assert(edge.count == 2, 'Non-manifold convex face boundary')
            end
        end

        assert(start and count >= 3, 'Invalid convex face boundary')
        local polygon = {}
        local vertex = start
        for _ = 1, count do
            assert(vertex and solid.vertices[vertex], 'Open convex face boundary')
            polygon[#polygon + 1] = solid.vertices[vertex]
            vertex = successor[vertex]
        end
        assert(vertex == start, 'Disjoint convex face boundary')
        group.polygon = polygon
        group.faces = nil
    end

    return groups
end

local function polygonArea(polygon)
    if #polygon < 3 then return 0 end
    local origin = polygon[1]
    local area = Vector3.zero
    for i = 2, #polygon - 1 do
        area += (polygon[i] - origin):Cross(polygon[i + 1] - origin)
    end
    return area.Magnitude / 2
end

local function clean(polygon)
    if #polygon < 3 then return {} end
    local output = {}
    for _, vertex in polygon do
        if #output == 0 or (vertex - output[#output]).Magnitude > EPSILON then
            output[#output + 1] = vertex
        end
    end
    if #output > 1 and (output[1] - output[#output]).Magnitude <= EPSILON then
        table.remove(output)
    end
    if #output < 3 or polygonArea(output) <= EPSILON * EPSILON then return {} end
    return output
end

local function cut(polygon, plane, keepPositive)
    local result = {}
    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        local da = a:Dot(plane.normal) - plane.distance
        local db = b:Dot(plane.normal) - plane.distance
        local accepted = if keepPositive then da >= -EPSILON else da <= EPSILON
        local nextAccepted = if keepPositive then db >= -EPSILON else db <= EPSILON
        if accepted then result[#result + 1] = a end
        if accepted ~= nextAccepted and math.abs(da - db) > EPSILON * 0.01 then
            local ratio = math.clamp(da / (da - db), 0, 1)
            result[#result + 1] = a:Lerp(b, ratio)
        end
    end
    return clean(result)
end

local function occupied(point, shapes)
    for _, shape in shapes do
        local inside = true
        for _, plane in shape do
            if point:Dot(plane.normal) > plane.distance + PLANE_TOLERANCE then
                inside = false
                break
            end
        end
        if inside then return true end
    end
    return false
end

local function polygonKey(polygon, planeId)
    local center = Vector3.zero
    for _, point in polygon do center += point end
    center /= #polygon
    local scale = 10000
    return string.format('%d:%d:%d:%d:%d',
        planeId, math.round(center.X * scale), math.round(center.Y * scale),
        math.round(center.Z * scale), #polygon)
end

local function addPolygon(output, polygon, normal)
    local anchor = polygon[1]
    for i = 2, #polygon - 1 do
        local b, c = polygon[i], polygon[i + 1]
        local cross = (b - anchor):Cross(c - anchor)
        if cross.Magnitude > EPSILON * EPSILON then
            local n = #output.vertices
            output.vertices[n + 1] = anchor
            output.vertices[n + 2] = b
            output.vertices[n + 3] = c
            output.triangles[#output.triangles + 1] = if cross:Dot(normal) > 0
                then {n + 1, n + 2, n + 3}
                else {n + 1, n + 3, n + 2}
            if #output.triangles > MAX_TRIANGLES then return false end
        end
    end
    return true
end

function Union.surface(pieces)
    assert(type(pieces) == 'table' and #pieces > 0, 'Expected convex pieces')
    local shapes = {}
    local planes = {}
    local groups = {}
    local inputTriangles = 0
    local inputFaces = 0

    for i, solid in pieces do
        assert(FORM.validate(solid).ok, 'Invalid piece ' .. i)
        groups[i] = faceGroups(solid)
        shapes[i] = groups[i]
        inputTriangles += #solid.triangles
        inputFaces += #groups[i]

        for _, plane in groups[i] do
            local found = false
            for _, existing in planes do
                if samePlane(plane, existing) then
                    found = true
                    break
                end
            end
            if not found then
                planes[#planes + 1] = {normal = plane.normal, distance = plane.distance}
                if #planes > MAX_PLANES then return nil, 'PLANE_BUDGET_EXCEEDED' end
            end
        end
    end

    if inputFaces > MAX_FACES then return nil, 'FACE_BUDGET_EXCEEDED' end
    local output = {vertices = {}, triangles = {}}
    local seen = {}
    local cells = 0
    local kept = 0

    for _, shape in groups do
        for _, face in shape do
            local supportingPlane = {normal = face.normal, distance = face.distance}
            local planeId
            for i, plane in planes do
                if samePlane(plane, supportingPlane) then planeId = i break end
            end

            local fragments = {face.polygon}

            for _, plane in planes do
                if samePlane(plane, supportingPlane) then continue end
                local nextFragments = {}

                for _, polygon in fragments do
                    local minimum, maximum = math.huge, -math.huge
                    for _, vertex in polygon do
                        local d = vertex:Dot(plane.normal) - plane.distance
                        minimum = math.min(minimum, d)
                        maximum = math.max(maximum, d)
                    end

                    if minimum < -PLANE_TOLERANCE and maximum > PLANE_TOLERANCE then
                        local negative = cut(polygon, plane, false)
                        local positive = cut(polygon, plane, true)
                        if #negative >= 3 then nextFragments[#nextFragments + 1] = negative end
                        if #positive >= 3 then nextFragments[#nextFragments + 1] = positive end
                    else
                        nextFragments[#nextFragments + 1] = polygon
                    end
                end

                fragments = nextFragments
                if #fragments > MAX_CELLS - cells then return nil, 'CELL_BUDGET_EXCEEDED' end
            end

            cells += #fragments
            for _, polygon in fragments do
                local center = Vector3.zero
                for _, vertex in polygon do center += vertex end
                center /= #polygon
                local probe = center + face.normal * SAMPLE_OFFSET
                if not occupied(probe, shapes) then
                    local signature = polygonKey(polygon, planeId)
                    if not seen[signature] then
                        seen[signature] = true
                        if not addPolygon(output, polygon, face.normal) then
                            return nil, 'TRIANGLE_BUDGET_EXCEEDED'
                        end
                        kept += 1
                    end
                end
            end
        end
    end

    return output, {
        inputTriangles = inputTriangles,
        inputFaces = inputFaces,
        outputTriangles = #output.triangles,
        outputFaces = kept,
        planeCount = #planes,
        cellCount = cells,
    }
end

function Union.reconstruct(pieces, expectedVolume, tolerance)
    local surface, surfaceStats = Union.surface(pieces)
    if not surface then return nil, surfaceStats, {stage = 'arrangement'} end
    local welded, weldStats = Weld.build(surface, tolerance)
    local stats = {surface = surfaceStats, weld = weldStats}

    if not weldStats.valid then return nil, 'NON_MANIFOLD_SURFACE', stats end

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
