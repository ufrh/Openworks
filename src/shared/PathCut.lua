local FORM = require(script.Parent.FORM)
local Stock = require(script.Parent.Stock)

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

local function rayExit(point, direction, hx, hz)
    local result, best
    local function try(t, other, bound, target)
        if t < -EPSILON or math.abs(other) > bound + EPSILON then return end
        if best and t >= best then return end
        best = math.max(0, t)
        result = target
    end
    if math.abs(direction.X) > 1e-7 then
        for _, x in {-hx, hx} do
            local t = (x - point.X) / direction.X
            local z = point.Y + direction.Y * t
            try(t, z, hz, Vector2.new(x, math.clamp(z, -hz, hz)))
        end
    end
    if math.abs(direction.Y) > 1e-7 then
        for _, z in {-hz, hz} do
            local t = (z - point.Y) / direction.Y
            local x = point.X + direction.X * t
            try(t, x, hx, Vector2.new(math.clamp(x, -hx, hx), z))
        end
    end
    return result
end

local function offsetPath(points, side, halfKerf, hx, hz)
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
        local candidate = point + miter * (side * halfKerf / factor)
        if math.abs(candidate.X) > hx + EPSILON
            or math.abs(candidate.Y) > hz + EPSILON then
            return nil, 'Score runs too close to a stock edge'
        end
        shifted[#shifted + 1] = candidate
    end
    local firstDirection = (points[2] - points[1]).Unit
    local lastDirection = (points[#points] - points[#points - 1]).Unit
    local start = rayExit(shifted[1], -firstDirection, hx, hz)
    local finish = rayExit(shifted[#shifted], lastDirection, hx, hz)
    if not start or not finish or (start - finish).Magnitude < 0.05 then
        return nil, 'Score must separate two distinct edges of the metal'
    end
    local chain = {start}
    for _, point in shifted do chain[#chain + 1] = point end
    chain[#chain + 1] = finish
    chain = clean(chain, false)
    if #chain < 2 or selfIntersects(chain, false) then
        return nil, 'Score path folds across itself'
    end
    return chain
end

local function perimeter(point, hx, hz)
    local tolerance = 0.0001
    if math.abs(point.Y + hz) < tolerance then return point.X + hx end
    if math.abs(point.X - hx) < tolerance then return 2 * hx + point.Y + hz end
    if math.abs(point.Y - hz) < tolerance then return 2 * hx + 2 * hz + hx - point.X end
    if math.abs(point.X + hx) < tolerance then return 4 * hx + 2 * hz + hz - point.Y end
    return nil
end

local function boundaryForward(from, to, hx, hz)
    local a, b = perimeter(from, hx, hz), perimeter(to, hx, hz)
    if not a or not b then return nil end
    local full = 4 * (hx + hz)
    if b <= a + EPSILON then b += full end
    local corners = {
        {at = 0, pos = Vector2.new(-hx, -hz)},
        {at = 2 * hx, pos = Vector2.new(hx, -hz)},
        {at = 2 * hx + 2 * hz, pos = Vector2.new(hx, hz)},
        {at = 4 * hx + 2 * hz, pos = Vector2.new(-hx, hz)},
    }
    local sequence = {from}
    for winding = 0, 1 do
        for _, corner in corners do
            local at = corner.at + winding * full
            if at > a + EPSILON and at < b - EPSILON then
                sequence[#sequence + 1] = corner.pos
            end
        end
    end
    sequence[#sequence + 1] = to
    return sequence
end

local function contains(polygon, point)
    local inside = false
    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        if (a.Y > point.Y) ~= (b.Y > point.Y) then
            local x = a.X + (point.Y - a.Y) * (b.X - a.X) / (b.Y - a.Y)
            if point.X < x then inside = not inside end
        end
    end
    return inside
end

local function makePolygon(chain, witness, hx, hz)
    local forward = boundaryForward(chain[#chain], chain[1], hx, hz)
    local reversed = boundaryForward(chain[1], chain[#chain], hx, hz)
    if not forward or not reversed then return nil end

    local backward = {}
    for i = #reversed, 1, -1 do backward[#backward + 1] = reversed[i] end

    local function assemble(boundary)
        local polygon = table.clone(chain)
        for i = 2, #boundary do polygon[#polygon + 1] = boundary[i] end
        return clean(polygon, true)
    end
    local first, second = assemble(forward), assemble(backward)
    local a, b = contains(first, witness), contains(second, witness)
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

function PathCut.split(work, points, kerfMM)
    if not work:IsA('Part') or work.Shape ~= Enum.PartType.Block
        or work:GetAttribute('FORMNativeStock') ~= true then
        return nil, 'Curved sawing currently requires native rectangular FORM stock'
    end
    if type(points) ~= 'table' or #points < 3 or #points > 128 then
        return nil, 'Score needs at least three sampled points'
    end
    local size, hx, hz = work.Size, work.Size.X * 0.5, work.Size.Z * 0.5
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
    local left, leftErr = offsetPath(centerLine, 1, half, hx, hz)
    if not left then return nil, leftErr end
    local right, rightErr = offsetPath(centerLine, -1, half, hx, hz)
    if not right then return nil, rightErr end

    local middle = math.max(1, math.floor(#centerLine / 2))
    local tangent = (centerLine[middle + 1] - centerLine[middle]).Unit
    local side = normal(tangent)
    local witnessDistance = half + math.max(0.025, kerf * 0.7)
    local leftWitness = centerLine[middle] + side * witnessDistance
    local rightWitness = centerLine[middle] - side * witnessDistance
    local leftPolygon = makePolygon(left, leftWitness, hx, hz)
    local rightPolygon = makePolygon(right, rightWitness, hx, hz)
    if not leftPolygon or not rightPolygon then
        return nil, 'Score path does not form two valid regions'
    end

    local first, aErr = extrude(leftPolygon, size.Y)
    if not first then return nil, aErr end
    local second, bErr = extrude(rightPolygon, size.Y)
    if not second then return nil, bErr end
    local originalVolume = size.X * size.Y * size.Z / (Stock.SCALE ^ 3)
    local retained = FORM.signedVolume(first) + FORM.signedVolume(second)
    local removed = originalVolume - retained
    if removed <= 0 or removed > originalVolume * 0.2 then
        return nil, 'Curved kerf volume is inconsistent'
    end
    return {first, second}, {removed = removed, retained = retained}
end

return PathCut
