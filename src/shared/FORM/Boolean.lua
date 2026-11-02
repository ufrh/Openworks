local FORM = require(script.Parent)
local Cut = require(script.Parent.Cut)

local Boolean = {}

local EPSILON = 1e-5

local function planes(solid)
    local result = {}
    for _, face in solid.triangles do
        local a, b, c = solid.vertices[face[1]], solid.vertices[face[2]], solid.vertices[face[3]]
        local normal = (b - a):Cross(c - a).Unit
        local distance = a:Dot(normal)
        local exists = false
        for _, plane in result do
            if normal:Dot(plane.normal) >= 1 - 1e-6
                and math.abs(distance - plane.distance) <= EPSILON then
                exists = true
                break
            end
        end
        if not exists then
            result[#result + 1] = {point = a, normal = normal, distance = distance}
        end
    end
    return result
end

function Boolean.subtract(stock, cutter)
    if not FORM.validate(stock).ok or not FORM.validate(cutter).ok then
        return nil, 'INVALID_INPUT'
    end

    local pending = {stock}
    local retained = {}
    local removed = 0

    for planeIndex, plane in planes(cutter) do
        local nextPending = {}
        for _, piece in pending do
            local minimum, maximum = math.huge, -math.huge
            for _, vertex in piece.vertices do
                local distance = vertex:Dot(plane.normal) - plane.distance
                minimum = math.min(minimum, distance)
                maximum = math.max(maximum, distance)
            end

            if minimum >= -EPSILON then
                retained[#retained + 1] = piece
            elseif maximum <= EPSILON then
                nextPending[#nextPending + 1] = piece
            else
                local outside, inside = Cut.split(piece, plane.point, plane.normal)
                if not outside then return nil, 'CUT_FAILED_PLANE_' .. planeIndex .. '_' .. tostring(inside) end
                retained[#retained + 1] = outside
                nextPending[#nextPending + 1] = inside
            end
        end
        pending = nextPending
        if #pending == 0 then break end
    end

    for _, piece in pending do removed += FORM.signedVolume(piece) end

    local remaining = 0
    for _, piece in retained do
        if not FORM.validate(piece).ok then return nil, 'INVALID_OUTPUT' end
        remaining += FORM.signedVolume(piece)
    end

    local original = FORM.signedVolume(stock)
    if not FORM.volumeClose(remaining + removed, original) then
        return nil, 'VOLUME_MISMATCH'
    end

    return retained, removed
end

return Boolean
