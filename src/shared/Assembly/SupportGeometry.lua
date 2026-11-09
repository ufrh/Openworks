--!strict
local Profile = require(script.Parent.Parent.FORM.SketchBodyProfile)
local Geometry = {}
Geometry.Clearance = 4 / 280
Geometry.Wall = 1 / 280

function Geometry.planes(node: any): { any }?
	local planes = {
		{ normal = Vector3.yAxis, distance = node.size.Y * 0.5 },
		{ normal = -Vector3.yAxis, distance = node.size.Y * 0.5 },
	}
	if node.kind == "Block" then
		for _, axis in ipairs({ Vector3.xAxis, Vector3.zAxis }) do
			local extent = math.abs(axis.X) * node.size.X + math.abs(axis.Z) * node.size.Z
			table.insert(planes, { normal = axis, distance = extent * 0.5 })
			table.insert(planes, { normal = -axis, distance = extent * 0.5 })
		end
	elseif node.kind == "SketchBody" then
		local ring = Profile.outline(node)
		local signed = 0
		for i, p in ipairs(ring) do
			local q = ring[i % #ring + 1]
			signed += p.X * q.Y - q.X * p.Y
		end
		for i, p in ipairs(ring) do
			local q = ring[i % #ring + 1]
			local edge = Vector3.new(q.X - p.X, 0, q.Y - p.Y)
			if edge.Magnitude < 1e-6 then
				return nil
			end
			local normal = edge:Cross(Vector3.yAxis).Unit * (if signed > 0 then -1 else 1)
			local distance = normal:Dot(Vector3.new(p.X, 0, p.Y))
			for _, vertex in ipairs(ring) do
				if normal:Dot(Vector3.new(vertex.X, 0, vertex.Y)) > distance + 1e-5 then
					return nil
				end
			end
			table.insert(planes, { normal = normal, distance = distance })
		end
	else
		return nil
	end
	return planes
end

function Geometry.boreSpan(
	node: any,
	point: Vector3,
	axis: Vector3,
	radius: number
): (number?, number?)
	local planes = Geometry.planes(node)
	if not planes then
		return nil, nil
	end
	local low, high = 0, math.huge
	for _, plane in ipairs(planes) do
		local slope = plane.normal:Dot(axis)
		local radial = radius * math.sqrt(math.max(0, 1 - slope * slope))
		local room = plane.distance - plane.normal:Dot(point) - radial
		if math.abs(slope) < 1e-6 then
			if room < -1e-5 then
				return nil, nil
			end
		elseif slope > 0 then
			high = math.min(high, room / slope)
		else
			low = math.max(low, room / slope)
		end
	end
	if high - low < Geometry.Wall then
		return nil, nil
	end
	return low, high
end

function Geometry.box(component: any): Vector3?
	if not component then
		return nil
	end
	for _, op in ipairs(component.operations or {}) do
		if op.enabled ~= false then
			return nil
		end
	end
	local n = component.nodes[1]
	if n.kind == "Block" then
		return n.size
	end
	if n.kind ~= "SketchBody" then
		return nil
	end
	local points = Profile.outline(n)
	if #points ~= 4 then
		return nil
	end
	local halfX, halfZ = 0, 0
	for _, p in ipairs(points) do
		halfX = math.max(halfX, math.abs(p.X))
		halfZ = math.max(halfZ, math.abs(p.Y))
	end
	if halfX < 1e-6 or halfZ < 1e-6 then
		return nil
	end
	local corners = {}
	for _, p in ipairs(points) do
		if math.abs(math.abs(p.X) - halfX) > 1e-5 or math.abs(math.abs(p.Y) - halfZ) > 1e-5 then
			return nil
		end
		corners[tostring(math.sign(p.X)) .. ":" .. tostring(math.sign(p.Y))] = true
	end
	local count = 0
	for _ in pairs(corners) do
		count += 1
	end
	return if count == 4 then Vector3.new(halfX * 2, n.size.Y, halfZ * 2) else nil
end

function Geometry.relativeBox(component: any, pose: CFrame, basis: CFrame): (Vector3?, Vector3?)
	local size = Geometry.box(component)
	if not size then
		return nil, nil
	end
	local frame = basis:ToObjectSpace(pose)
	local axes = { frame.XVector, frame.YVector, frame.ZVector }
	for _, axis in ipairs(axes) do
		if math.max(math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z)) < 0.999999 then
			return nil, nil
		end
	end
	local extent = Vector3.new(
		math.abs(axes[1].X) * size.X + math.abs(axes[2].X) * size.Y + math.abs(axes[3].X) * size.Z,
		math.abs(axes[1].Y) * size.X + math.abs(axes[2].Y) * size.Y + math.abs(axes[3].Y) * size.Z,
		math.abs(axes[1].Z) * size.X + math.abs(axes[2].Z) * size.Y + math.abs(axes[3].Z) * size.Z
	) * 0.5
	return frame.Position, extent
end

function Geometry.axisFrame(point: Vector3, axis: Vector3): CFrame
	local x = axis:Cross(if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	return CFrame.fromMatrix(point, x, axis, x:Cross(axis))
end

function Geometry.stops(
	ids: any,
	components: any,
	poses: any,
	grounded: any,
	basis: CFrame,
	halfSize: Vector3
): (number?, number?, string?)
	if type(ids) ~= "table" or #ids ~= 2 or ids[1] == ids[2] then
		return nil, nil, "Choose two separate end-stop plates"
	end
	local lower, upper = nil, nil
	for _, id in ipairs(ids) do
		if not grounded[tostring(id)] then
			return nil, nil, "Both end stops must be fixed to the bench"
		end
		local pose = poses[tostring(id)]
		local p, h = nil, nil
		if pose then
			p, h = Geometry.relativeBox(components[id], pose, basis)
		end
		if not p or not h then
			return nil, nil, "End stops must be uncut rectangular plates, square to the travel axis"
		end
		if h.X - math.abs(p.X) < halfSize.X - 1e-5 or h.Z - math.abs(p.Z) < halfSize.Z - 1e-5 then
			return nil, nil, "An end-stop plate must cover the moving part end face"
		end
		if p.Y > 0 then
			if upper then
				return nil, nil, "Put one stop at each end"
			end
			upper = p.Y - h.Y - halfSize.Y
		else
			if lower then
				return nil, nil, "Put one stop at each end"
			end
			lower = p.Y + h.Y + halfSize.Y
		end
	end
	if not lower or not upper or lower > 1e-4 or upper < -1e-4 or upper < lower then
		return nil, nil, "End stops intersect the mover or do not enclose it"
	end
	return lower, upper, nil
end
return Geometry
