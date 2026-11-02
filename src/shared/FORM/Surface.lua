local FORM = require(script.Parent)

local Surface = {}

local function inside(solid, point, tolerance)
    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a)
        local length = normal.Magnitude
        if length > 0 and (point - a):Dot(normal) > tolerance * length then
            return false
        end
    end
    return true
end

function Surface.extract(pieces)
    assert(type(pieces) == 'table' and #pieces > 0, 'Expected convex pieces')

    local output = {vertices = {}, triangles = {}}
    local discarded = 0
    local uncertain = 0

    for i, piece in pieces do
        assert(FORM.validate(piece).ok, 'Invalid piece ' .. i)

        for _, face in piece.triangles do
            local a, b, c = piece.vertices[face[1]], piece.vertices[face[2]], piece.vertices[face[3]]
            local normal = (b - a):Cross(c - a)
            local midpoint = (a + b + c) / 3
            local direction = normal.Unit
            local offset = 0.001
            local hidden = false
            local partial = false

            for j, neighbor in pieces do
                if i == j then continue end

                local outward = inside(neighbor, midpoint + direction * offset, 0.0001)
                if outward then
                    hidden = true
                    break
                end

                local covered = 0
                for _, corner in {a, b, c} do
                    if inside(neighbor, corner + direction * offset, 0.0001) then
                        covered += 1
                    end
                end
                if covered > 0 then partial = true end
            end

            if hidden then
                discarded += 1
            else
                if partial then uncertain += 1 end
                local index = #output.vertices
                output.vertices[index + 1] = a
                output.vertices[index + 2] = b
                output.vertices[index + 3] = c
                output.triangles[#output.triangles + 1] = {index + 1, index + 2, index + 3}
            end
        end
    end

    return output, {discarded = discarded, uncertain = uncertain, complete = uncertain == 0}
end

return Surface
