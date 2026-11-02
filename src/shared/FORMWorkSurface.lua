local Surface = {}

local AXES = {'X', 'Y', 'Z'}
local VECTORS = {X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis}

local function component(v, axis)
    if axis == 'X' then return v.X end
    if axis == 'Y' then return v.Y end
    return v.Z
end

local function half(part, axis)
    return component(part.Size, axis) * 0.5
end

function Surface.face(part)
    local localUp = part.CFrame:VectorToObjectSpace(Vector3.yAxis)
    local best = 'Y'
    for _, axis in AXES do
        if math.abs(component(localUp, axis)) > math.abs(component(localUp, best)) then
            best = axis
        end
    end
    return best, if component(localUp, best) >= 0 then 1 else -1
end

function Surface.pick(part, worldPoint)
    local face = Surface.face(part)
    local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
    local chosen, distance
    for _, axis in AXES do
        if axis ~= face then
            local d = half(part, axis) - math.abs(component(localPoint, axis))
            if not distance or d < distance then
                chosen = axis
                distance = d
            end
        end
    end
    return chosen, if component(localPoint, chosen) >= 0 then 1 else -1
end

function Surface.path(part, sideAxis, sideSign, stroke, above)
    local face, faceSign = Surface.face(part)
    if sideAxis == face then
        for _, axis in AXES do
            if axis ~= face then
                sideAxis = axis
                break
            end
        end
    end

    local along
    for _, axis in AXES do
        if axis ~= face and axis ~= sideAxis then
            along = axis
            break
        end
    end

    local localPoint = Vector3.zero
        + VECTORS[face] * faceSign * (half(part, face) + (above or 0.025))
        + VECTORS[sideAxis] * sideSign * (half(part, sideAxis) + 0.012)
        + VECTORS[along] * (-math.clamp(stroke or 0, -1, 1))
            * math.max(0.025, half(part, along) - 0.02)

    local forward = part.CFrame:VectorToWorldSpace(VECTORS[along])
    local up = part.CFrame:VectorToWorldSpace(VECTORS[face] * faceSign)
    return part.CFrame:PointToWorldSpace(localPoint), forward, up,
        part.CFrame:PointToWorldSpace(localPoint
            - VECTORS[face] * faceSign * (above or 0.025))
end

function Surface.guide(part, sideAxis, sideSign)
    local face = Surface.face(part)
    if sideAxis == face then
        for _, axis in AXES do
            if axis ~= face then
                sideAxis = axis
                break
            end
        end
    end
    local point, forward, up = Surface.path(part, sideAxis, sideSign, 0, 0.04)
    local side = forward:Cross(up).Unit
    local along
    for _, axis in AXES do
        if axis ~= face and axis ~= sideAxis then along = axis break end
    end
    if not along then return nil end

    local frame = CFrame.fromMatrix(point, forward, up, side)
    return frame, Vector3.new(component(part.Size, along), 0.02, 0.07)
end

return Surface
