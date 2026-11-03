local FORM = require(script.Parent.FORM)
local Stock = require(script.Parent.Stock)
local Profile = require(script.Parent.PrismProfile)

local PathCut = {}
PathCut.KERF_MM = 0.8

local EPSILON = 1e-5

local function cross(a, b)
    return a.X * b.Y - a.Y * b.X
end

local function distance(a, b)
    return (a - b).Magnitude
end

local function normal(direction)
    return Vector2.new(-direction.Y, direction.X)
end

local function area(points)
    local total = 0
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1]
        total += cross(a, b)
    end
    return total * 0.5
end

local function clean(points, closed)
    local output = {}
    for _, point in points do
        if #output == 0 or distance(point, output[#output]) > EPSILON then
            output[#output + 1] = point
        end
    end
    if closed and #output > 2 and distance(output[1], output[#output]) <= EPSILON then
        table.remove(output)
    end
    local changed = true
    while changed and #output > (if closed then 3 else 2) do
        changed = false
        for i = #output, 1, -1 do
            if not closed and (i == 1 or i == #output) then continue end
            local a = output[(i - 2) % #output + 1]
            local b = output[i]
            local c = output[i % #output + 1]
            local span = c - a
            if span.Magnitude > EPSILON
                and math.abs(cross(b - a, span)) / span.Magnitude < 0.00001 then
                table.remove(output, i)
                changed = true
                break
            end
        end
    end
    return output
end

local function intersect(a, b, c, d)
    local r, s = b - a, d - c
    local denominator = cross(r, s)
    if math.abs(denominator) < 1e-9 then return false end
    local t = cross(c - a, s) / denominator
    local u = cross(c - a, r) / denominator
    return t > 1e-5 and t < 1 - 1e-5 and u > 1e-5 and u < 1 - 1e-5
end

local function selfIntersects(points, closed)
    local count = #points
    local edges = if closed then count else count - 1
    for i = 1, edges do
        for j = i + 2, edges do
            if closed and i == 1 and j == edges then continue end
            local a, b = points[i], points[i % count + 1]
            local c, d = points[j], points[j % count + 1]
            if intersect(a, b, c, d) then return true end
        end
    end
    return false
end

local function clippedChain(shifted, outline)
    local clipped = {}
    for i = 2, #shifted do
        local a, b = shifted[i - 1], shifted[i]
        local interval = {{t = 0, point = a}, {t = 1, point = b}}
        for _, hit in Profile.intersections(outline, a, b) do
            if hit.t > EPSILON and hit.t < 1 - EPSILON then
                interval[#interval + 1] = hit
            end
        end
        table.sort(interval, function(x, y) return x.t < y.t end)

        for k = 2, #interval do
            local first, last = interval[k - 1], interval[k]
            if last.t - first.t < 1e-8 then continue end
            if not Profile.contains(outline, (first.point + last.point) * 0.5) then
                continue
            end
            if #clipped > 0 and (first.point - clipped[#clipped]).Magnitude > 0.0001 then
                return nil, 'Cut leaves the workpiece and re-enters it'
            end
            if #clipped == 0 or (first.point - clipped[#clipped]).Magnitude > EPSILON then
                clipped[#clipped + 1] = first.point
            end
            clipped[#clipped + 1] = last.point
        end
    end

    clipped = clean(clipped, false)
    if #clipped < 2 then return nil, 'Score does not cross the remaining metal' end
    return clipped
end

local function offsetPath(points, side, halfKerf, outline)
    local shifted = {}
    for i, point in points do
        local previous = if i == 1 then (points[2] - point).Unit
            else (point - points[i - 1]).Unit
        local nextDirection = if i == #points then previous
            else (points[i + 1] - point).Unit
        local prevNormal, nextNormal = normal(previous), normal(nextDirection)
        local miter = prevNormal + nextNormal
        if miter.Magnitude < 0.3 then return nil, 'Score reverses too sharply' end
        miter = miter.Unit
        local factor = math.abs(miter:Dot(nextNormal))
        if factor < 0.45 then return nil, 'Score corner is too sharp for saw kerf' end
        shifted[#shifted + 1] = point + miter * (side * halfKerf / factor)
    end

    local clipped, failure = clippedChain(shifted, outline)
    if not clipped then return nil, failure end
    local firstDirection = (clipped[2] - clipped[1]).Unit
    local lastDirection = (clipped[#clipped] - clipped[#clipped - 1]).Unit
    local start = Profile.rayExit(outline, clipped[1], -firstDirection)
    local finish = Profile.rayExit(outline, clipped[#clipped], lastDirection)
    if not start or not finish or (start - finish).Magnitude < 0.05 then
        return nil, 'Score must separate two distinct edges of the metal'
    end
    local chain = {start}
    for _, point in clipped do chain[#chain + 1] = point end
    chain[#chain + 1] = finish
    chain = clean(chain, false)
    if #chain < 2 or selfIntersects(chain, false) then
        return nil, 'Score path folds across itself'
    end
    return chain
end

local function makePolygon(chain, witness, outline)
    local forward = Profile.boundaryForward(outline, chain[#chain], chain[1])
    local reversed = Profile.boundaryForward(outline, chain[1], chain[#chain])
    if not forward or not reversed then return nil end

    local backward = {}
    for i = #reversed, 1, -1 do backward[#backward + 1] = reversed[i] end

    local function assemble(boundary)
        local polygon = table.clone(chain)
        for i = 2, #boundary do polygon[#polygon + 1] = boundary[i] end
        return clean(polygon, true)
    end
    local first, second = assemble(forward), assemble(backward)
    local a, b = Profile.contains(first, witness), Profile.contains(second, witness)
    if a == b then return nil end
    local polygon = if a then first else second
    if #polygon < 3 or selfIntersects(polygon, true)
        or math.abs(area(polygon)) < 0.0001 then return nil end
    if area(polygon) < 0 then
        local flipped = {}
        for i = #polygon, 1, -1 do flipped[#flipped + 1] = polygon[i] end
        return flipped
    end
    return polygon
end

local function triangulate(points)
    local indices = {}
    for i = 1, #points do indices[i] = i end
    local triangles = {}
    local cap = #points * #points
    while #indices > 3 and cap > 0 do
        cap -= 1
        local clipped = false
        for i = 1, #indices do
            local prev = indices[(i - 2) % #indices + 1]
            local curr = indices[i]
            local nextId = indices[i % #indices + 1]
            local a, b, c = points[prev], points[curr], points[nextId]
            if cross(b - a, c - b) <= 1e-8 then continue end
            local ear = true
            for _, index in indices do
                if index == prev or index == curr or index == nextId then continue end
                local p = points[index]
                if cross(b - a, p - a) >= -1e-8
                    and cross(c - b, p - b) >= -1e-8
                    and cross(a - c, p - c) >= -1e-8 then
                    ear = false
                    break
                end
            end
            if not ear then continue end
            triangles[#triangles + 1] = {prev, curr, nextId}
            table.remove(indices, i)
            clipped = true
            break
        end
        if not clipped then return nil end
    end
    if #indices ~= 3 then return nil end
    triangles[#triangles + 1] = {indices[1], indices[2], indices[3]}
    return triangles
end

local function extrude(polygon, thickness)
    local faces = triangulate(polygon)
    if not faces then return nil, 'Score made an untriangulatable boundary' end
    local vertices, triangles = {}, {}
    local half = thickness * 0.5
    for _, point in polygon do
        vertices[#vertices + 1] = Vector3.new(point.X, -half, point.Y) / Stock.SCALE
        vertices[#vertices + 1] = Vector3.new(point.X, half, point.Y) / Stock.SCALE
    end
    for _, triangle in faces do
        local a, b, c = triangle[1], triangle[2], triangle[3]
        triangles[#triangles + 1] = {2 * a - 1, 2 * b - 1, 2 * c - 1}
        triangles[#triangles + 1] = {2 * c, 2 * b, 2 * a}
    end
    for i = 1, #polygon do
        local j = i % #polygon + 1
        local bottomA, topA = 2 * i - 1, 2 * i
        local bottomB, topB = 2 * j - 1, 2 * j
        triangles[#triangles + 1] = {bottomA, topA, topB}
        triangles[#triangles + 1] = {bottomA, topB, bottomB}
    end
    local solid = {vertices = vertices, triangles = triangles}
    local validation = FORM.validate(solid)
    if not validation.ok then
        return nil, 'Invalid curved solid: ' .. tostring(validation.issues[1].code)
    end
    return solid
end

function PathCut.split(work, points, kerfMM, existingSolid)
    if not work:IsA('Part') or work.Shape ~= Enum.PartType.Block
        or work:GetAttribute('FORMNativeStock') ~= true then
        return nil, 'Curved cutting requires a FORM-backed workpiece'
    end
    if type(points) ~= 'table' or #points < 3 or #points > 128 then
        return nil, 'Score needs at least three sampled points'
    end
    local size = work.Size
    local source = existingSolid or FORM.box(size / Stock.SCALE)
    local original = FORM.signedVolume(source)
    if original <= 0 then return nil, 'Invalid source solid volume' end
    local perimeter, thickness = Profile.extract(source)
    if not perimeter then return nil, thickness end
    local outline = {}
    for _, vertex in perimeter do outline[#outline + 1] = vertex * Stock.SCALE end
    local boundsLow, boundsHigh = FORM.bounds(source)
    local hx = math.max(math.abs(boundsLow.X), math.abs(boundsHigh.X)) * Stock.SCALE
    local hz = math.max(math.abs(boundsLow.Z), math.abs(boundsHigh.Z)) * Stock.SCALE
    local centerLine = {}
    for _, point in points do
        if typeof(point) ~= 'Vector3' or point.X ~= point.X or point.Z ~= point.Z
            or math.abs(point.X) > hx + 0.02 or math.abs(point.Z) > hz + 0.02 then
            return nil, 'Score points are outside the material'
        end
        local nextPoint = Vector2.new(point.X, point.Z)
        if #centerLine == 0 or distance(nextPoint, centerLine[#centerLine]) > 0.016 then
            centerLine[#centerLine + 1] = nextPoint
        end
    end
    if #centerLine < 3 or selfIntersects(centerLine, false) then
        return nil, 'Score folds over itself or is too short'
    end
    local kerf = (kerfMM or PathCut.KERF_MM) * Stock.SCALE
    local half = kerf * 0.5
    if kerf <= 0 or kerf >= math.min(size.X, size.Z) * 0.2 then
        return nil, 'Saw kerf is too large for this stock'
    end
    local left, leftErr = offsetPath(centerLine, 1, half, outline)
    if not left then return nil, leftErr end
    local right, rightErr = offsetPath(centerLine, -1, half, outline)
    if not right then return nil, rightErr end

    local middle = math.max(1, math.floor(#centerLine / 2))
    local tangent = (centerLine[middle + 1] - centerLine[middle]).Unit
    local side = normal(tangent)
    local witnessDistance = half + math.max(0.025, kerf * 0.7)
    local leftWitness = centerLine[middle] + side * witnessDistance
    local rightWitness = centerLine[middle] - side * witnessDistance
    if not Profile.contains(outline, leftWitness)
        or not Profile.contains(outline, rightWitness) then
        return nil, 'Not enough metal remains on both sides of the scored cut'
    end
    local leftPolygon = makePolygon(left, leftWitness, outline)
    local rightPolygon = makePolygon(right, rightWitness, outline)
    if not leftPolygon or not rightPolygon then
        return nil, 'Score path does not form two valid regions'
    end

    local first, aErr = extrude(leftPolygon, thickness * Stock.SCALE)
    if not first then return nil, aErr end
    local second, bErr = extrude(rightPolygon, thickness * Stock.SCALE)
    if not second then return nil, bErr end
    local originalVolume = original
    local retained = FORM.signedVolume(first) + FORM.signedVolume(second)
    local removed = originalVolume - retained
    if removed <= 0 or removed > originalVolume * 0.2 then
        return nil, 'Curved kerf volume is inconsistent'
    end
    return {first, second}, {removed = removed, retained = retained}
end

return PathCut
