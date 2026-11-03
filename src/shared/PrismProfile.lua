local FORM = require(script.Parent.FORM)

local Profile = {}
local EPSILON = 1e-6

local function cross(a, b)
    return a.X * b.Y - a.Y * b.X
end

function Profile.area(points)
    local result = 0
    for i = 1, #points do
        result += cross(points[i], points[i % #points + 1])
    end
    return result * 0.5
end

function Profile.contains(points, point)
    local inside = false
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1]
        local ab, ap = b - a, point - a
        if math.abs(cross(ab, ap)) <= 1e-6
            and ap:Dot(ab) >= -1e-6 and ap:Dot(ab) <= ab:Dot(ab) + 1e-6 then
            return true
        end
        if (a.Y > point.Y) ~= (b.Y > point.Y) then
            local x = a.X + (point.Y - a.Y) * (b.X - a.X) / (b.Y - a.Y)
            if point.X < x then inside = not inside end
        end
    end
    return inside
end

function Profile.intersections(points, a, b)
    local hits = {}
    local travel = b - a
    for i = 1, #points do
        local p, q = points[i], points[i % #points + 1]
        local edge = q - p
        local denominator = cross(travel, edge)
        if math.abs(denominator) > 1e-10 then
            local t = cross(p - a, edge) / denominator
            local u = cross(p - a, travel) / denominator
            if t >= -EPSILON and t <= 1 + EPSILON
                and u >= -EPSILON and u <= 1 + EPSILON then
                hits[#hits + 1] = {
                    t = math.clamp(t, 0, 1), edge = i,
                    u = math.clamp(u, 0, 1),
                    point = a + travel * math.clamp(t, 0, 1),
                }
            end
        end
    end
    table.sort(hits, function(x, y) return x.t < y.t end)
    local unique = {}
    for _, hit in hits do
        if #unique == 0 or (hit.point - unique[#unique].point).Magnitude > 1e-6 then
            unique[#unique + 1] = hit
        end
    end
    return unique
end

function Profile.rayExit(points, origin, direction)
    if direction.Magnitude < 1e-9 then return nil end
    local directionUnit = direction.Unit
    local best, point
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1]
        local edge = b - a
        local denominator = cross(directionUnit, edge)
        if math.abs(denominator) < 1e-10 then continue end
        local t = cross(a - origin, edge) / denominator
        local u = cross(a - origin, directionUnit) / denominator
        if t >= -EPSILON and u >= -EPSILON and u <= 1 + EPSILON
            and (not best or t < best) then
            best = t
            point = origin + directionUnit * math.max(0, t)
        end
    end
    return point
end

local function onBoundary(points, target)
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1]
        local ab, at = b - a, target - a
        local length = ab:Dot(ab)
        if length > 1e-10 and math.abs(cross(ab, at)) / math.sqrt(length) < 0.0001
            and at:Dot(ab) >= -0.0001 and at:Dot(ab) <= length + 0.0001 then
            return i, math.clamp(at:Dot(ab) / length, 0, 1)
        end
    end
end

function Profile.boundaryForward(points, from, to)
    local edgeA, tA = onBoundary(points, from)
    local edgeB, tB = onBoundary(points, to)
    if not edgeA or not edgeB then return nil end
    local distances, total = {}, 0
    for i = 1, #points do
        distances[i] = total
        total += (points[i % #points + 1] - points[i]).Magnitude
    end
    local start = distances[edgeA] + tA * (points[edgeA % #points + 1] - points[edgeA]).Magnitude
    local finish = distances[edgeB] + tB * (points[edgeB % #points + 1] - points[edgeB]).Magnitude
    if finish <= start + EPSILON then finish += total end
    local sequence = {from}
    for revolution = 0, 1 do
        for i = 1, #points do
            local at = distances[i] + revolution * total
            if at > start + EPSILON and at < finish - EPSILON then
                sequence[#sequence + 1] = points[i]
            end
        end
    end
    sequence[#sequence + 1] = to
    return sequence
end

function Profile.extract(solid)
    if not FORM.validate(solid).ok then return nil, 'FORM solid is invalid' end
    local low, high = FORM.bounds(solid)
    local tolerance = math.max(1e-5, (high.Y - low.Y) * 1e-5)
    for _, vertex in solid.vertices do
        if math.abs(vertex.Y - low.Y) > tolerance
            and math.abs(vertex.Y - high.Y) > tolerance then
            return nil, 'This piece has varying-height surfaces; a volumetric cutter is required'
        end
    end

    local edges = {}
    local directed = {}
    local function add(a, b)
        local u, v = math.min(a, b), math.max(a, b)
        local key = tostring(u) .. ':' .. tostring(v)
        if edges[key] then
            edges[key].count += 1
        else
            edges[key] = {count = 1, a = a, b = b}
        end
    end
    for _, triangle in solid.triangles do
        local a, b, c = triangle[1], triangle[2], triangle[3]
        local va, vb, vc = solid.vertices[a], solid.vertices[b], solid.vertices[c]
        if math.abs(va.Y - high.Y) <= tolerance
            and math.abs(vb.Y - high.Y) <= tolerance
            and math.abs(vc.Y - high.Y) <= tolerance then
            add(a, b)
            add(b, c)
            add(c, a)
        end
    end
    local adj = {}
    local edgeCount = 0
    for _, edge in edges do
        if edge.count == 1 then
            adj[edge.a] = adj[edge.a] or {}
            adj[edge.b] = adj[edge.b] or {}
            adj[edge.a][#adj[edge.a] + 1] = edge.b
            adj[edge.b][#adj[edge.b] + 1] = edge.a
            edgeCount += 1
        elseif edge.count ~= 2 then
            return nil, 'Top-face boundary has non-manifold topology'
        end
    end
    if edgeCount < 3 then return nil, 'No closed top-face perimeter found' end
    local first
    for index, neighbors in adj do
        if #neighbors ~= 2 then return nil, 'Top-face perimeter branches or is open' end
        first = first or index
    end
    local indices, visited = {}, {}
    local previous, current = nil, first
    for _ = 1, edgeCount + 1 do
        if visited[current] then break end
        visited[current] = true
        indices[#indices + 1] = current
        local neighbors = adj[current]
        local nextIndex = if neighbors[1] == previous then neighbors[2] else neighbors[1]
        previous, current = current, nextIndex
    end
    if current ~= first or #indices ~= edgeCount then
        return nil, 'Multiple contours or holes need full polygon-boolean support'
    end

    local points = {}
    for _, index in indices do
        local v = solid.vertices[index]
        points[#points + 1] = Vector2.new(v.X, v.Z)
    end
    if Profile.area(points) < 0 then
        local reversed = {}
        for i = #points, 1, -1 do reversed[#reversed + 1] = points[i] end
        points = reversed
    end
    return points, high.Y - low.Y
end

return Profile
