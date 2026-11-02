local FORM = require(script.Parent)

local Union = {}

local EPSILON = 1e-4

local function planes(solid)
    local result = {}
    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a).Unit
        local distance = normal:Dot(a)
        local duplicate = false

        for _, existing in result do
            if normal:Dot(existing.normal) > 1 - 1e-6
                and math.abs(distance - existing.distance) < EPSILON then
                duplicate = true
                break
            end
        end

        if not duplicate then
            result[#result + 1] = {normal = normal, distance = distance}
        end
    end
    return result
end

local function clip(polygon, plane, keepInside)
    local result = {}
    if #polygon == 0 then return result end

    local function distance(v)
        return v:Dot(plane.normal) - plane.distance
    end

    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        local da, db = distance(a), distance(b)
        local insideA = if keepInside then da <= 0 else da >= 0
        local insideB = if keepInside then db <= 0 else db >= 0

        if insideA then result[#result + 1] = a end
        if insideA ~= insideB then
            local t = da / (da - db)
            result[#result + 1] = a:Lerp(b, t)
        end
    end

    return result
end

local function append(output, polygon, normal)
    if #polygon < 3 then return false end
    local first = polygon[1]
    local written = false

    for i = 2, #polygon - 1 do
        local b, c = polygon[i], polygon[i + 1]
        if (b - first):Cross(c - first).Magnitude > EPSILON * EPSILON then
            local base = #output.vertices
            output.vertices[base + 1] = first
            output.vertices[base + 2] = b
            output.vertices[base + 3] = c
            local facing = (b - first):Cross(c - first):Dot(normal)
            output.triangles[#output.triangles + 1] = if facing >= 0
                then {base + 1, base + 2, base + 3}
                else {base + 1, base + 3, base + 2}
            written = true
        end
    end

    return written
end

function Union.surface(pieces)
    assert(type(pieces) == 'table' and #pieces > 0, 'Expected convex pieces')

    local output = {vertices = {}, triangles = {}}
    local geometry = {}
    for i, piece in pieces do
        assert(FORM.validate(piece).ok, 'Invalid piece ' .. i)
        geometry[i] = planes(piece)
    end

    local stats = {inputTriangles = 0, outputTriangles = 0, splitFragments = 0}

    for i, piece in pieces do
        for _, face in piece.triangles do
            stats.inputTriangles += 1
            local a, b, c = piece.vertices[face[1]], piece.vertices[face[2]], piece.vertices[face[3]]
            local normal = (b - a):Cross(c - a).Unit
            local fragments = {{a, b, c}}

            for j in pieces do
                if i == j then continue end

                local nextFragments = {}
                for _, fragment in fragments do
                    local pending = {fragment}
                    for _, plane in geometry[j] do
                        local nextPending = {}
                        local adjusted = {
                            normal = plane.normal,
                            distance = plane.distance - normal:Dot(plane.normal) * EPSILON,
                        }

                        for _, polygon in pending do
                            local outside = clip(polygon, adjusted, false)
                            local inside = clip(polygon, adjusted, true)
                            if #outside >= 3 then nextFragments[#nextFragments + 1] = outside end
                            if #inside >= 3 then nextPending[#nextPending + 1] = inside end
                        end
                        pending = nextPending
                        if #pending == 0 then break end
                    end
                end
                fragments = nextFragments
                if #fragments == 0 then break end
            end

            for _, fragment in fragments do
                if append(output, fragment, normal) then stats.splitFragments += 1 end
            end
        end
    end

    stats.outputTriangles = #output.triangles
    return output, stats
end

return Union
