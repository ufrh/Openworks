local HttpService = game:GetService('HttpService')

local ScorePath = {}
ScorePath.ATTRIBUTE = 'FORMScorePaths'
ScorePath.MAX_PATHS = 12
ScorePath.MAX_POINTS = 256
ScorePath.MAX_RAW_POINTS = 512
local decodedCache = setmetatable({}, {__mode = 'k'})

local function coordinate(point, axis)
    if axis == 'X' then return point.X end
    if axis == 'Y' then return point.Y end
    return point.Z
end

local function pointArray(point)
    return {math.round(point.X * 10000) / 10000,
        math.round(point.Y * 10000) / 10000,
        math.round(point.Z * 10000) / 10000}
end

local function vector(point)
    if type(point) ~= 'table' then return nil end
    for i = 1, 3 do
        if type(point[i]) ~= 'number' or point[i] ~= point[i]
            or math.abs(point[i]) > 10000 then return nil end
    end
    return Vector3.new(point[1], point[2], point[3])
end

function ScorePath.face(work)
    local up = work.CFrame:VectorToObjectSpace(Vector3.yAxis)
    local x, y, z = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
    if x >= y and x >= z then return 'X', if up.X >= 0 then 1 else -1 end
    if z >= y then return 'Z', if up.Z >= 0 then 1 else -1 end
    return 'Y', if up.Y >= 0 then 1 else -1
end

function ScorePath.normal(axis, sign)
    if axis == 'X' then return Vector3.new(sign, 0, 0) end
    if axis == 'Y' then return Vector3.new(0, sign, 0) end
    return Vector3.new(0, 0, sign)
end

function ScorePath.project(work, worldPoint)
    local axis, sign = ScorePath.face(work)
    local half = work.Size * 0.5
    local localPoint = work.CFrame:PointToObjectSpace(worldPoint)
    local faceExtent = coordinate(half, axis)
    local margin = 0.06
    for _, other in {'X', 'Y', 'Z'} do
        if other ~= axis and math.abs(coordinate(localPoint, other)) > coordinate(half, other) + margin then
            return nil
        end
    end
    local point = Vector3.new(
        math.clamp(localPoint.X, -half.X, half.X),
        math.clamp(localPoint.Y, -half.Y, half.Y),
        math.clamp(localPoint.Z, -half.Z, half.Z))
    if axis == 'X' then point = Vector3.new(faceExtent * sign, point.Y, point.Z)
    elseif axis == 'Y' then point = Vector3.new(point.X, faceExtent * sign, point.Z)
    else point = Vector3.new(point.X, point.Y, faceExtent * sign) end
    return point, axis, sign
end

function ScorePath.valid(work, point, axis, sign)
    if typeof(point) ~= 'Vector3' then return false end
    if point.X ~= point.X or point.Y ~= point.Y or point.Z ~= point.Z then return false end
    local half = work.Size * 0.5
    for _, a in {'X', 'Y', 'Z'} do
        local value = coordinate(point, a)
        local extent = coordinate(half, a)
        if math.abs(value) > extent + 0.025 then return false end
        if a == axis and math.abs(value - extent * sign) > 0.035 then return false end
    end
    return true
end

function ScorePath.read(work)
    local raw = work:GetAttribute(ScorePath.ATTRIBUTE)
    if type(raw) ~= 'string' or #raw > 200000 then return {} end
    local cached = decodedCache[work]
    if cached and cached.raw == raw then return cached.paths end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    local output = {}
    for _, entry in decoded do
        if type(entry) == 'table' and type(entry.points) == 'table'
            and #entry.points >= 2 and #entry.points <= ScorePath.MAX_POINTS
            and (entry.face == 'X' or entry.face == 'Y' or entry.face == 'Z')
            and (entry.sign == 1 or entry.sign == -1) then
            local points = {}
            for _, p in entry.points do
                local v = vector(p)
                if not v then break end
                points[#points + 1] = v
            end
            if #points == #entry.points then
                output[#output + 1] = {face = entry.face, sign = entry.sign, points = points}
            end
        end
        if #output >= ScorePath.MAX_PATHS then break end
    end
    decodedCache[work] = {raw = raw, paths = output}
    return output
end

function ScorePath.write(work, paths)
    local data = {}
    for _, path in paths do
        local points = {}
        for _, point in path.points do
            points[#points + 1] = pointArray(point)
        end
        data[#data + 1] = {face = path.face, sign = path.sign, points = points}
    end
    work:SetAttribute(ScorePath.ATTRIBUTE, HttpService:JSONEncode(data))
end

function ScorePath.reduce(points, tolerance)
    if #points <= 2 then return table.clone(points) end
    local keep = {[1] = true, [#points] = true}
    local function recurse(first, last)
        local origin, finish = points[first], points[last]
        local segment = finish - origin
        local span = segment:Dot(segment)
        local best, index = 0, nil
        for i = first + 1, last - 1 do
            local t = if span < 1e-10 then 0
                else math.clamp((points[i] - origin):Dot(segment) / span, 0, 1)
            local error = (points[i] - (origin + segment * t)).Magnitude
            if error > best then best, index = error, i end
        end
        if index and best > tolerance then
            keep[index] = true
            recurse(first, index)
            recurse(index, last)
        end
    end
    recurse(1, #points)
    local reduced = {}
    for i, point in points do
        if keep[i] then reduced[#reduced + 1] = point end
    end
    return reduced
end

local function capPoint(work, point)
    local half = work.Size * 0.5
    local face, sign = ScorePath.face(work)
    local x = math.clamp(point.X, -half.X, half.X)
    local y = math.clamp(point.Y, -half.Y, half.Y)
    local z = math.clamp(point.Z, -half.Z, half.Z)
    if face == 'X' then x = half.X * sign
    elseif face == 'Y' then y = half.Y * sign
    else z = half.Z * sign end
    return Vector3.new(x, y, z)
end

function ScorePath.smooth(work, points)
    if type(points) ~= 'table' or #points <= 2 then
        return type(points) == 'table' and table.clone(points) or {}
    end

    local knots = {}
    for _, point in points do
        if typeof(point) == 'Vector3'
            and (#knots == 0 or (point - knots[#knots]).Magnitude > 0.002) then
            knots[#knots + 1] = capPoint(work, point)
        end
    end
    if #knots <= 2 then return knots end

    local function blur(input)
        local output = {input[1]}
        for i = 2, #input - 1 do
            local before, here, after = input[i - 1], input[i], input[i + 1]
            local incoming = (here - before).Magnitude
            local outgoing = (after - here).Magnitude
            local scale = math.clamp(
                math.min(incoming, outgoing) /
                math.max(0.0001, math.max(incoming, outgoing)), 0.2, 1)
            output[i] = capPoint(work,
                here * (1 - 0.44 * scale)
                + (before + after) * (0.22 * scale))
        end
        output[#input] = input[#input]
        return output
    end

    knots = blur(blur(knots))
    local total = 0
    for i = 2, #knots do
        total += (knots[i] - knots[i - 1]).Magnitude
    end
    if total < 0.015 then return {knots[1], knots[#knots]} end

    local step = math.max(0.018, total / (ScorePath.MAX_POINTS - 1))
    local output = {knots[1]}
    for i = 1, #knots - 1 do
        local a, b = knots[i], knots[i + 1]
        local distance = (b - a).Magnitude
        if distance < 1e-6 then continue end
        local previous = knots[math.max(1, i - 1)]
        local next = knots[math.min(#knots, i + 2)]
        local previousDistance = math.max(1e-5, (a - previous).Magnitude)
        local nextDistance = math.max(1e-5, (next - b).Magnitude)
        local incoming = (b - previous) * (distance / (previousDistance + distance))
        local outgoing = (next - a) * (distance / (nextDistance + distance))
        if i == 1 then incoming = (b - a) * 0.65 end
        if i == #knots - 1 then outgoing = (b - a) * 0.65 end
        local count = math.clamp(math.ceil(distance / step), 1, 16)
        for k = 1, count do
            local t = k / count
            local t2, t3 = t * t, t * t * t
            local candidate = a * (2 * t3 - 3 * t2 + 1)
                + incoming * (t3 - 2 * t2 + t)
                + b * (-2 * t3 + 3 * t2)
                + outgoing * (t3 - t2)
            candidate = capPoint(work, candidate)
            if (candidate - output[#output]).Magnitude > 0.003 then
                output[#output + 1] = candidate
            end
        end
    end
    if #output > ScorePath.MAX_POINTS then
        local sampled = {}
        for i = 1, ScorePath.MAX_POINTS do
            local index = 1 + (i - 1) * (#output - 1) / (ScorePath.MAX_POINTS - 1)
            local first = math.floor(index)
            local second = math.min(#output, first + 1)
            sampled[i] = output[first]:Lerp(output[second], index - first)
        end
        output = sampled
    end
    output[1], output[#output] = knots[1], knots[#knots]
    return output
end

local function straightLine(work, path)
    local face, sign = ScorePath.face(work)
    if face ~= 'Y' or path.face ~= face or path.sign ~= sign then return nil end

    local points = path.points
    local first, last = points[1], points[#points]
    local delta = Vector3.new(last.X - first.X, 0, last.Z - first.Z)
    local length = delta.Magnitude
    if length < 0.12 then return nil end

    local direction = delta.Unit
    local normal = Vector3.new(-direction.Z, 0, direction.X)
    local midpoint = (first + last) * 0.5
    local deviation = 0
    for _, point in points do
        deviation = math.max(deviation, math.abs((point - midpoint):Dot(normal)))
    end
    if deviation > 0.015 then return nil end

    local axis
    if math.abs(direction.Z) > 0.997 then
        axis = 'X'
    elseif math.abs(direction.X) > 0.997 then
        axis = 'Z'
    end
    local offset = axis and coordinate(midpoint, axis) or nil
    if axis then
        local extent = coordinate(work.Size, axis)
        if math.abs(offset) > math.max(0, extent * 0.5 - 0.17) then return nil end
        if axis == 'X' then
            direction = Vector3.new(0, 0, if direction.Z >= 0 then 1 else -1)
            normal = Vector3.new(-direction.Z, 0, 0)
        else
            direction = Vector3.new(if direction.X >= 0 then 1 else -1, 0, 0)
            normal = Vector3.new(0, 0, direction.X)
        end
    end

    return {axis = axis, offset = offset, length = length,
        point = midpoint, tangent = direction, normal = normal}
end

local function closestOnPath(path, position)
    local nearest = math.huge
    for i = 2, #path.points do
        local a, b = path.points[i - 1], path.points[i]
        local dx, dz = b.X - a.X, b.Z - a.Z
        local denominator = dx * dx + dz * dz
        if denominator > 1e-8 then
            local t = math.clamp(((position.X - a.X) * dx
                + (position.Z - a.Z) * dz) / denominator, 0, 1)
            local px, pz = a.X + dx * t, a.Z + dz * t
            nearest = math.min(nearest, (Vector2.new(position.X - px, position.Z - pz)).Magnitude)
        end
    end
    return nearest
end

function ScorePath.guide(work, position, radius)
    local face, sign = ScorePath.face(work)
    if face ~= 'Y' or typeof(position) ~= 'Vector3' then return nil end
    local nearest, distance
    for _, path in ScorePath.read(work) do
        if path.face ~= face or path.sign ~= sign then continue end
        local error = closestOnPath(path, position)
        if error <= radius and (not distance or error < distance) then
            local line = straightLine(work, path)
            nearest = if line then {
                kind = 'Straight', axis = line.axis, offset = line.offset,
                point = line.point, tangent = line.tangent, normal = line.normal,
                length = line.length, points = path.points,
            } else {kind = 'Curved', points = path.points}
            distance = error
        end
    end
    return nearest
end

function ScorePath.sample(points, travel)
    if type(points) ~= 'table' or #points < 2 then return nil end
    local distance = 0
    for i = 2, #points do
        distance += (points[i] - points[i - 1]).Magnitude
    end
    if distance < 0.01 then return nil end
    if travel == nil then return distance end
    local remaining = math.clamp(travel, 0, distance)
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local delta = b - a
        local length = delta.Magnitude
        if length > 1e-5 then
            if remaining <= length or i == #points then
                return a + delta * math.clamp(remaining / length, 0, 1), delta.Unit, distance
            end
            remaining -= length
        end
    end
    return points[#points], (points[#points] - points[#points - 1]).Unit, distance
end

function ScorePath.contactFrame(work, point, tangent)
    local face, sign = ScorePath.face(work)
    local localNormal = ScorePath.normal(face, sign)
    local up = work.CFrame:VectorToWorldSpace(localNormal)
    local localDirection = tangent or
        (if face == 'X' then Vector3.zAxis else Vector3.xAxis)
    local forward = work.CFrame:VectorToWorldSpace(localDirection)
    forward -= up * forward:Dot(up)
    if forward.Magnitude < 0.001 then
        forward = work.CFrame:VectorToWorldSpace(
            if face == 'X' then Vector3.zAxis else Vector3.xAxis)
    end
    forward = forward.Unit
    local worldPoint = work.CFrame:PointToWorldSpace(point) + up * 0.008
    return CFrame.fromMatrix(worldPoint, forward, up, forward:Cross(up))
end

function ScorePath.straight(work, axis, currentOffset, radius)
    if axis ~= 'X' and axis ~= 'Z' then return nil end
    local nearest, distance
    for _, path in ScorePath.read(work) do
        local line = straightLine(work, path)
        if not line or line.axis ~= axis then continue end
        local error = math.abs(currentOffset - line.offset)
        if error <= radius and (not distance or error < distance) then
            nearest, distance = line.offset, error
        end
    end
    return nearest
end

return ScorePath
