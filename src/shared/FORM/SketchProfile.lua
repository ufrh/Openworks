--!strict
-- FORM polygon sketch validation and ear-clipping triangulation.
-- Pure data module: no Roblox geometry assets are created while sketching.
local SketchProfile = {}
local EPS = 1e-6
local MAX_POINTS = 64

local function cross(a: Vector2, b: Vector2, c: Vector2): number
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

local function onSegment(a: Vector2, b: Vector2, p: Vector2): boolean
	return math.abs(cross(a, b, p)) <= EPS
		and p.X >= math.min(a.X, b.X) - EPS
		and p.X <= math.max(a.X, b.X) + EPS
		and p.Y >= math.min(a.Y, b.Y) - EPS
		and p.Y <= math.max(a.Y, b.Y) + EPS
end

local function segmentsIntersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local abC, abD = cross(a, b, c), cross(a, b, d)
	local cdA, cdB = cross(c, d, a), cross(c, d, b)
	if ((abC > EPS and abD < -EPS) or (abC < -EPS and abD > EPS))
		and ((cdA > EPS and cdB < -EPS) or (cdA < -EPS and cdB > EPS)) then
		return true
	end
	return onSegment(a, b, c) or onSegment(a, b, d)
		or onSegment(c, d, a) or onSegment(c, d, b)
end

local function insideTriangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2): boolean
	return cross(a, b, p) >= -EPS and cross(b, c, p) >= -EPS
		and cross(c, a, p) >= -EPS
end

function SketchProfile.prepare(inputPoints: {Vector2}): ({Vector2}?, {{number}}?, string?)
	if #inputPoints < 3 then return nil, nil, "A profile needs at least three points" end
	if #inputPoints > MAX_POINTS then return nil, nil, "Sketch limit: 64 vertices" end
	local points = {}
	for _, p in ipairs(inputPoints) do
		if typeof(p) ~= "Vector2" or p.X ~= p.X or p.Y ~= p.Y
			or math.abs(p.X) > 512 or math.abs(p.Y) > 512 then
			return nil, nil, "Sketch contains invalid coordinates"
		end
		table.insert(points, p)
	end
	if (points[1] - points[#points]).Magnitude < EPS then
		table.remove(points)
	end
	if #points < 3 then return nil, nil, "A profile needs three distinct corners" end

	-- Remove straight-line intermediate vertices; they only introduce zero-area ears.
	local changed = true
	while changed and #points > 3 do
		changed = false
		for i = #points, 1, -1 do
			local a = points[(i - 2) % #points + 1]
			local b = points[i]
			local c = points[i % #points + 1]
			if (b - a).Magnitude < EPS or (c - b).Magnitude < EPS
				or (math.abs(cross(a, b, c)) < EPS
					and (b - a):Dot(c - b) >= -EPS) then
				table.remove(points, i)
				changed = true
				break
			end
		end
	end

	local n = #points
	for i = 1, n do
		if (points[i] - points[i % n + 1]).Magnitude < 0.025 - EPS then
			return nil, nil, "Two sketch vertices are too close"
		end
		for j = i + 1, n do
			if j ~= i + 1 and not (i == 1 and j == n) then
				if segmentsIntersect(points[i], points[i % n + 1],
					points[j], points[j % n + 1]) then
					return nil, nil, "Sketch edges cross or overlap"
				end
			end
		end
	end

	local signedArea = 0
	for i = 1, n do
		local a, b = points[i], points[i % n + 1]
		signedArea += a.X * b.Y - b.X * a.Y
	end
	if math.abs(signedArea) < 0.0001 then
		return nil, nil, "Sketch has no usable enclosed area"
	end
	if signedArea < 0 then
		local reversed = {}
		for i = n, 1, -1 do table.insert(reversed, points[i]) end
		points = reversed
	end

	local indices = {}
	for i = 1, n do indices[i] = i end
	local triangles = {}
	while #indices > 3 do
		local earFound = false
		for slot = 1, #indices do
			local ai = indices[(slot - 2) % #indices + 1]
			local bi = indices[slot]
			local ci = indices[slot % #indices + 1]
			local a, b, c = points[ai], points[bi], points[ci]
			if cross(a, b, c) <= EPS then continue end
			local occupied = false
			for _, candidate in ipairs(indices) do
				if candidate ~= ai and candidate ~= bi and candidate ~= ci
					and insideTriangle(points[candidate], a, b, c) then
					occupied = true
					break
				end
			end
			if not occupied then
				table.insert(triangles, { ai, bi, ci })
				table.remove(indices, slot)
				earFound = true
				break
			end
		end
		if not earFound then
			return nil, nil, "Could not triangulate the profile; check for overlapping edges"
		end
	end
	table.insert(triangles, { indices[1], indices[2], indices[3] })
	return points, triangles, nil
end

return SketchProfile
