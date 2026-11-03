local ScorePath = require(script.Parent:WaitForChild('ScorePath'))

local PenPath = {}
PenPath.MAX_ANCHORS = 12
PenPath.MAX_STEPS = 22
PenPath.MIN_LENGTH = 0.10

local function finite3(point)
    return typeof(point) == 'Vector3'
        and point.X == point.X and point.Y == point.Y and point.Z == point.Z
        and math.abs(point.X) < 1000 and math.abs(point.Y) < 1000
        and math.abs(point.Z) < 1000
end

local function coordinate(v, axis)
    if axis == 'X' then return v.X end
    if axis == 'Y' then return v.Y end
    return v.Z
end

function PenPath.cubic(a, b, c, d, t)
    local u = 1 - t
    return a * (u * u * u) + b * (3 * u * u * t)
        + c * (3 * u * t * t) + d * (t * t * t)
end

function PenPath.sample(work, anchors, preview)
    if not work or not work:IsA('BasePart')
        or type(anchors) ~= 'table' or #anchors < 2
        or #anchors > PenPath.MAX_ANCHORS then
        return nil, 'Place 2–12 Pen Tool anchors on the metal'
    end

    local axis, sign = ScorePath.face(work)
    local half = work.Size * 0.5
    local extent = coordinate(half, axis) * sign
    local nodes = {}

    for _, node in anchors do
        if type(node) ~= 'table' or not finite3(node.point)
            or not finite3(node.inHandle) or not finite3(node.outHandle) then
            return nil, 'Invalid Bézier anchor or handle'
        end
        local point, incoming, outgoing = node.point, node.inHandle, node.outHandle
        if not ScorePath.valid(work, point, axis, sign)
            or math.abs(coordinate(incoming, axis) - extent) > 0.035
            or math.abs(coordinate(outgoing, axis) - extent) > 0.035
            or (incoming - point).Magnitude > 3
            or (outgoing - point).Magnitude > 3 then
            return nil, 'Pen Tool anchor or handle is outside the supported material face'
        end
        nodes[#nodes + 1] = node
    end

    local output = {nodes[1].point}
    local length = 0

    for i = 1, #nodes - 1 do
        local first, second = nodes[i], nodes[i + 1]
        local a, b = first.point, second.point
        local c1, c2 = first.outHandle, second.inHandle
        local controlLength = (c1 - a).Magnitude + (c2 - c1).Magnitude
            + (b - c2).Magnitude
        local steps = math.clamp(math.ceil(controlLength / 0.035),
            4, PenPath.MAX_STEPS)

        for step = 1, steps do
            local t = step / steps
            local point = PenPath.cubic(a, c1, c2, b, t)
            if not preview and not ScorePath.valid(work, point, axis, sign) then
                return nil, 'Bézier curve extends beyond the metal; adjust its handles'
            end
            local separation = (point - output[#output]).Magnitude
            if separation > 0.001 then
                length += separation
                output[#output + 1] = point
            end
        end
    end

    if #output < 2 or length < PenPath.MIN_LENGTH then
        return nil, 'Pen Tool path is too short to score'
    end
    if #output > ScorePath.MAX_POINTS then
        return nil, 'Pen Tool path exceeds FORM scoring capacity'
    end

    return output, {face = axis, sign = sign, length = length}
end

return PenPath
