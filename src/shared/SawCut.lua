local FORM = require(script.Parent.FORM)
local Cut = require(script.Parent.FORM.Cut)
local Stock = require(script.Parent.Stock)

local SawCut = {}
SawCut.KERF_MM = 0.8

local function parameters(item, worldPoint, worldNormal)
    assert(typeof(worldPoint) == 'Vector3' and typeof(worldNormal) == 'Vector3',
        'Saw target requires world-space vectors')
    assert(worldNormal.Magnitude > 0.001, 'Invalid cutting plane')
    local point = item.frame:PointToObjectSpace(worldPoint) / Stock.SCALE
    local normal = item.frame:VectorToObjectSpace(worldNormal).Unit
    return point, normal
end

local function extent(solid, point, normal)
    local low, high = math.huge, -math.huge
    for _, vertex in solid.vertices do
        local distance = (vertex - point):Dot(normal)
        low = math.min(low, distance)
        high = math.max(high, distance)
    end
    return low, high
end

local function crossings(solid, point, normal)
    local unique = {}
    local seen = {}

    local function add(value)
        local key = string.format('%.3f:%.3f:%.3f', value.X, value.Y, value.Z)
        if seen[key] then return end
        seen[key] = true
        unique[#unique + 1] = value
    end

    for _, triangle in solid.triangles do
        for edge = 1, 3 do
            local a = solid.vertices[triangle[edge]]
            local b = solid.vertices[triangle[edge % 3 + 1]]
            local da = (a - point):Dot(normal)
            local db = (b - point):Dot(normal)
            if math.abs(da) < 1e-5 then add(a) end
            if da * db < -1e-10 then
                local t = da / (da - db)
                add(a:Lerp(b, t))
            end
        end
    end

    if #unique < 3 then return nil end
    local center = Vector3.zero
    for _, vertex in unique do center += vertex end
    center /= #unique
    local axis = normal:Cross(Vector3.yAxis)
    if axis.Magnitude < 0.01 then axis = normal:Cross(Vector3.xAxis) end
    axis = axis.Unit
    local side = normal:Cross(axis).Unit
    table.sort(unique, function(a, b)
        local va, vb = a - center, b - center
        return math.atan2(va:Dot(side), va:Dot(axis))
            < math.atan2(vb:Dot(side), vb:Dot(axis))
    end)
    return unique
end

function SawCut.preview(item, worldPoint, worldNormal, kerf)
    kerf = kerf or SawCut.KERF_MM
    assert(type(kerf) == 'number' and kerf >= 0 and kerf <= 3, 'Invalid saw kerf')
    local point, normal = parameters(item, worldPoint, worldNormal)
    local low, high = extent(item.solid, point, normal)
    if low >= -kerf / 2 - 0.25 or high <= kerf / 2 + 0.25 then
        return nil, 'Move the cut farther inside the material'
    end
    local ring = crossings(item.solid, point, normal)
    if not ring then return nil, 'No valid cutting section' end
    local worldRing = {}
    for i, vertex in ring do
        worldRing[i] = item.frame:PointToWorldSpace(vertex * Stock.SCALE)
    end
    return {point = worldPoint, normal = worldNormal.Unit, ring = worldRing, kerf = kerf}
end

function SawCut.split(item, worldPoint, worldNormal, kerf)
    kerf = kerf or SawCut.KERF_MM
    local valid, reason = SawCut.preview(item, worldPoint, worldNormal, kerf)
    if not valid then return nil, reason end

    local point, normal = parameters(item, worldPoint, worldNormal)
    local upper, remainder = Cut.split(item.solid, point + normal * (kerf / 2), normal)
    if not upper then return nil, 'First saw boundary: ' .. tostring(remainder) end

    local waste, lower = Cut.split(remainder, point - normal * (kerf / 2), normal)
    if not waste then return nil, 'Second saw boundary: ' .. tostring(lower) end

    local original = FORM.signedVolume(item.solid)
    local left, right, scrap = FORM.signedVolume(upper), FORM.signedVolume(lower), FORM.signedVolume(waste)
    if not FORM.volumeClose(left + right + scrap, original) then
        return nil, 'Saw result did not conserve volume'
    end
    if not FORM.validate(upper).ok or not FORM.validate(lower).ok then
        return nil, 'Saw generated an invalid piece'
    end
    return {upper, lower}, {removed = scrap, retained = left + right}
end

return SawCut
