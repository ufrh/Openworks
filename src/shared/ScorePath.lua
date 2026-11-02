local HttpService = game:GetService('HttpService')

local ScorePath = {}
ScorePath.ATTRIBUTE = 'FORMScorePaths'
ScorePath.MAX_PATHS = 8
ScorePath.MAX_POINTS = 128

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
    if type(raw) ~= 'string' or #raw > 70000 then return {} end
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

function ScorePath.straight(work, axis, currentOffset, radius)
    local face, sign = ScorePath.face(work)
    local span = if axis == 'X' then work.Size.Z else work.Size.X
    local extent = if axis == 'X' then work.Size.X else work.Size.Z
    local along = if axis == 'X' then 'Z' else 'X'
    local best, distance
    for _, path in ScorePath.read(work) do
        if path.face ~= face or path.sign ~= sign then continue end
        if face ~= 'Y' then continue end
        local low, high = math.huge, -math.huge
        local sum = 0
        for _, point in path.points do
            local value = coordinate(point, along)
            low, high = math.min(low, value), math.max(high, value)
            sum += coordinate(point, axis)
        end
        if high - low < span * 0.8 then continue end
        local offset = sum / #path.points
        if math.abs(offset) > extent * 0.5 - 0.05 then continue end
        local deviation = 0
        for _, point in path.points do
            deviation = math.max(deviation, math.abs(coordinate(point, axis) - offset))
        end
        if deviation > 0.055 then continue end
        local error = math.abs(offset - currentOffset)
        if error <= radius and (not distance or error < distance) then
            best, distance = offset, error
        end
    end
    return best
end

return ScorePath
