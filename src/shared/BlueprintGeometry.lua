local HttpService = game:GetService('HttpService')
local Stock = require(script.Parent.Stock)

local Blueprint = {}
Blueprint.ATTRIBUTE = 'OpenworksBlueprint'
Blueprint.SCALE = Stock.SCALE
Blueprint.MAX_LINES = 128

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < 100000
end

local function decodePoint(value)
    if type(value) ~= 'table' or not finite(value[1]) or not finite(value[2]) then
        return nil
    end
    return Vector2.new(value[1], value[2])
end

local function encodedPoint(value)
    return {math.round(value.X * 1000) / 1000, math.round(value.Y * 1000) / 1000}
end

function Blueprint.project(sheet, worldPoint)
    local localPoint = sheet.CFrame:PointToObjectSpace(worldPoint)
    return Vector2.new(localPoint.X, localPoint.Z) / Blueprint.SCALE
end

function Blueprint.inside(sheet, point)
    if not sheet or not sheet:IsA('BasePart') or typeof(point) ~= 'Vector2'
        or not finite(point.X) or not finite(point.Y) then return false end
    local half = sheet.Size * (0.5 / Blueprint.SCALE)
    return math.abs(point.X) <= half.X - 1 and math.abs(point.Y) <= half.Z - 1
end

function Blueprint.read(sheet)
    local raw = sheet:GetAttribute(Blueprint.ATTRIBUTE)
    if type(raw) ~= 'string' or #raw > 40000 then return {} end
    local ok, parsed = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok or type(parsed) ~= 'table' or parsed.version ~= 1
        or type(parsed.lines) ~= 'table' then return {} end

    local lines = {}
    for _, entry in parsed.lines do
        if type(entry) ~= 'table' or entry.kind ~= 'Line' then continue end
        local a, b = decodePoint(entry.a), decodePoint(entry.b)
        if a and b and Blueprint.inside(sheet, a) and Blueprint.inside(sheet, b)
            and (b - a).Magnitude > 0.5 then
            lines[#lines + 1] = {kind = 'Line', a = a, b = b}
        end
        if #lines >= Blueprint.MAX_LINES then break end
    end
    return lines
end

function Blueprint.write(sheet, lines)
    local encoded = {}
    for _, entry in lines do
        encoded[#encoded + 1] = {
            kind = 'Line', a = encodedPoint(entry.a), b = encodedPoint(entry.b),
        }
    end
    sheet:SetAttribute(Blueprint.ATTRIBUTE,
        HttpService:JSONEncode({version = 1, units = 'mm', lines = encoded}))
end

function Blueprint.closestLine(lines, point)
    local best, bestDistance
    for i, entry in lines do
        local delta = entry.b - entry.a
        local d = delta:Dot(delta)
        local t = if d > 1e-7
            then math.clamp((point - entry.a):Dot(delta) / d, 0, 1) else 0
        local closest = entry.a + delta * t
        local distance = (point - closest).Magnitude
        if not bestDistance or distance < bestDistance then
            best, bestDistance = i, distance
        end
    end
    return best, bestDistance
end

function Blueprint.rulerGuide(sheet, ruler, near)
    if not ruler or not ruler:IsA('BasePart')
        or ruler:GetAttribute('DraftingKind') ~= 'Ruler'
        or ruler:GetAttribute('OnWorkbench') ~= true
        or not Blueprint.inside(sheet, near) then return nil end

    local surface = sheet.Position + sheet.CFrame.UpVector * sheet.Size.Y * 0.5
    local height = (ruler.Position - surface):Dot(sheet.CFrame.UpVector)
    if math.abs(height) > 0.5
        or ruler.CFrame.UpVector:Dot(sheet.CFrame.UpVector) < 0.65 then return nil end

    local alongWorld = if ruler.Size.X >= ruler.Size.Z
        then ruler.CFrame.RightVector else ruler.CFrame.LookVector
    local localAlong = sheet.CFrame:VectorToObjectSpace(alongWorld)
    local along = Vector2.new(localAlong.X, localAlong.Z)
    if along.Magnitude < 0.75 then return nil end
    along = along.Unit

    local perpendicular = Vector2.new(-along.Y, along.X)
    local center = Blueprint.project(sheet, ruler.Position)
    local width = (if ruler.Size.X >= ruler.Size.Z
        then ruler.Size.Z else ruler.Size.X) / (2 * Blueprint.SCALE)
    local length = math.max(ruler.Size.X, ruler.Size.Z) / (2 * Blueprint.SCALE)
    local best, nearest
    for _, side in {-1, 1} do
        local origin = center + perpendicular * width * side
        local distance = math.abs((near - origin):Dot(perpendicular))
        local alongDistance = (near - origin):Dot(along)
        if math.abs(alongDistance) <= length + 3
            and distance <= 7 and (not nearest or distance < nearest) then
            best = {origin = origin, direction = along, length = length}
            nearest = distance
        end
    end
    return best
end

function Blueprint.snap(guide, point)
    local distance = (point - guide.origin):Dot(guide.direction)
    return guide.origin + guide.direction
        * math.clamp(distance, -guide.length, guide.length)
end

function Blueprint.append(sheet, a, b)
    if not Blueprint.inside(sheet, a) or not Blueprint.inside(sheet, b)
        or (b - a).Magnitude < 1.5 then return false end
    local lines = Blueprint.read(sheet)
    if #lines >= Blueprint.MAX_LINES then return false end
    lines[#lines + 1] = {kind = 'Line', a = a, b = b}
    Blueprint.write(sheet, lines)
    Blueprint.render(sheet, lines)
    return true
end

function Blueprint.erase(sheet, point, threshold)
    if not Blueprint.inside(sheet, point) then return false end
    local lines = Blueprint.read(sheet)
    local index, distance = Blueprint.closestLine(lines, point)
    if not index or distance > (threshold or 3) then return false end
    table.remove(lines, index)
    Blueprint.write(sheet, lines)
    Blueprint.render(sheet, lines)
    return true
end

function Blueprint.render(sheet, lines)
    local existing = sheet:FindFirstChild('BlueprintInk')
    if existing then existing:Destroy() end
    local folder = Instance.new('Folder')
    folder.Name = 'BlueprintInk'
    folder.Parent = sheet
    local up = sheet.CFrame.UpVector

    for _, entry in lines or Blueprint.read(sheet) do
        local start = Vector3.new(entry.a.X * Blueprint.SCALE,
            sheet.Size.Y * 0.5 + 0.006, entry.a.Y * Blueprint.SCALE)
        local finish = Vector3.new(entry.b.X * Blueprint.SCALE,
            sheet.Size.Y * 0.5 + 0.006, entry.b.Y * Blueprint.SCALE)
        local delta = finish - start
        if delta.Magnitude < 0.001 then continue end
        local worldDirection = sheet.CFrame:VectorToWorldSpace(delta.Unit)
        local midpoint = sheet.CFrame:PointToWorldSpace((start + finish) * 0.5)
        local mark = Instance.new('Part')
        mark.Name = 'DraftLine'
        mark.Size = Vector3.new(delta.Magnitude, 0.007, 0.013)
        mark.CFrame = CFrame.fromMatrix(midpoint, worldDirection,
            up, worldDirection:Cross(up))
        mark.Color = Color3.fromRGB(27, 57, 91)
        mark.Material = Enum.Material.SmoothPlastic
        mark.Anchored = false
        mark.Massless = true
        mark.CanCollide = false
        mark.CanTouch = false
        mark.CanQuery = false
        mark.CastShadow = false
        mark.Parent = folder
        local weld = Instance.new('WeldConstraint')
        weld.Part0 = sheet
        weld.Part1 = mark
        weld.Parent = mark
    end
end

return Blueprint
