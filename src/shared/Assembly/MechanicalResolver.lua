--!strict
local References = require(script.Parent.GeometryReferences)
local Geometry = require(script.Parent.SupportGeometry)
local PinnedPivot = require(script.Parent.PinnedPivot)
local Resolver = {}
Resolver.MinClearance = 1 / 280
Resolver.MaxClearance = 4 / 280

function Resolver.dependencies(record: any): { number }
	local out = {}
	for _, id in ipairs({ record.bodyId or 0, record.shaftId or record.movingId or 0 }) do
		if id ~= 0 then
			table.insert(out, id)
		end
	end
	for _, ids in ipairs({ record.guideIds or {}, record.stopIds or {},
		{record.pinId or 0} }) do
		for _, id in ipairs(ids) do
			if id ~= 0 then table.insert(out, id) end
		end
	end
	return out
end

local function bore(record: any, components: any, poses: any): (any?, string?)
	local body, shaft = components[record.bodyId], components[record.shaftId]
	if not body or not shaft or body.id == shaft.id then
		return nil, "Choose a housing and a separate shaft"
	end
	local hole = References.get(body, record.featureId)
	local cylinder = References.get(shaft, "shaft")
	if not hole or not hole.feature or not cylinder then
		return nil, "Select a through-hole and an uncut cylindrical shaft"
	end
	local active = {}
	for _, op in ipairs(body.operations) do
		if op.enabled ~= false then
			table.insert(active, op)
		end
	end
	if
		#active ~= 1
		or (active[1].kind ~= "Drill" and active[1].kind ~= "DrillFace")
		or not hole.feature.through
	then
		return nil, "Bearing housing needs one through-drill in otherwise unmodified stock"
	end
	local low, high = Geometry.boreSpan(
		body.nodes[1],
		hole.point,
		hole.direction,
		hole.diameter * 0.5 + Geometry.Wall
	)
	if not low or not high then
		return nil, "Bore needs a continuous surrounding wall in convex stock"
	end
	local clearance = hole.diameter - cylinder.diameter
	if clearance < Resolver.MinClearance - 1e-6 then
		return nil, "Shaft needs at least 1 mm diametral clearance"
	end
	if clearance > Resolver.MaxClearance + 1e-6 then
		return nil, "Bearing fit is too loose: maximum diametral clearance is 4 mm"
	end
	local pa, pb = poses[tostring(body.id)], poses[tostring(shaft.id)]
	if not pa or not pb then
		return nil, "Missing assembly placement"
	end
	local a, b = References.world(hole, pa), References.world(cylinder, pb)
	local cosine = math.abs(a.direction:Dot(b.direction))
	if cosine < 0.999999 then
		return nil, "Align the shaft and bore axes first"
	end
	local delta = b.point - a.point
	local axial = delta:Dot(a.direction)
	local radial = (delta - a.direction * axial).Magnitude
	if
		radial + math.sqrt(math.max(0, 1 - cosine * cosine)) * cylinder.length * 0.5
		> clearance * 0.5 - 1e-5
	then
		return nil, "Shaft centerline is outside its radial clearance"
	end
	local overlap = math.min(high, axial + cylinder.length * 0.5)
		- math.max(low, axial - cylinder.length * 0.5)
	if overlap < math.min((high - low) * 0.5, cylinder.diameter) then
		return nil, "Insert the shaft farther into its bore"
	end
	return {
		kind = "Cylindrical",
		model = record.model,
		bodyId = body.id,
		shaftId = shaft.id,
		movingId = shaft.id,
		featureId = record.featureId,
		point = b.point,
		direction = a.direction,
		translation = 1,
		rotation = 1,
		retained = false,
		basis = Geometry.axisFrame(b.point, a.direction),
		halfSize = Vector3.new(cylinder.diameter, cylinder.length, cylinder.diameter) * 0.5,
	},
		nil
end

local function guide(record: any, components: any, poses: any, grounded: any): (any?, string?)
	local mover = components[record.movingId]
	local size = Geometry.box(mover)
	local pose = poses[tostring(record.movingId)]
	if not size or not pose then
		return nil, "Linear guides need an uncut rectangular carriage"
	end
	if type(record.guideIds) ~= "table" or #record.guideIds ~= 4 then
		return nil, "Choose four surrounding guide rails"
	end
	local sides, seen = {}, {}
	for _, id in ipairs(record.guideIds) do
		if id == record.movingId or seen[id] then
			return nil, "Guide rails must be four distinct components"
		end
		seen[id] = true
		if not grounded[tostring(id)] then
			return nil, "Fix each guide rail to the bench first"
		end
		local pp = poses[tostring(id)]
		local p, h = nil, nil
		if pp then
			p, h = Geometry.relativeBox(components[id], pp, pose)
		end
		if not p or not h then
			return nil, "Guide rails must be uncut rectangular stock aligned with the carriage"
		end
		local overlap = math.min(size.Y * 0.5, p.Y + h.Y) - math.max(-size.Y * 0.5, p.Y - h.Y)
		if overlap < math.min(size.Y * 0.5, 0.1) then
			return nil, "Carriage has insufficient engagement with a guide rail"
		end
		local side = nil
		for _, axis in ipairs({ "X", "Z" }) do
			local other = if axis == "X" then "Z" else "X"
			local gap = math.abs(p[axis]) - h[axis] - size[axis] * 0.5
			if
				gap >= Geometry.Wall * 0.5 - 1e-5
				and gap <= Geometry.Clearance * 0.5 + 1e-5
				and h[other] - math.abs(p[other]) >= size[other] * 0.5 - 1e-5
			then
				side = axis .. tostring(math.sign(p[axis]))
			end
		end
		if not side or sides[side] then
			return nil, "Rails must cover all four X/Z sides with 0.5–2 mm clearance per side"
		end
		sides[side] = true
	end
	return {
		kind = "Prismatic",
		model = record.model,
		bodyId = record.guideIds[1],
		movingId = mover.id,
		point = pose.Position,
		direction = pose.YVector,
		translation = 1,
		rotation = 0,
		retained = false,
		basis = pose,
		halfSize = size * 0.5,
	},
		nil
end

function Resolver.resolve(record: any, components: any, poses: any, grounded: any?): (any?, string?)
	if type(record) ~= "table" then
		return nil, "Invalid relationship"
	end
	local ground = grounded or {}
	local relation, reason
	if record.model == "BoreSupportV1" or record.model == "RetainedBoreV1" then
		relation, reason = bore(record, components, poses)
	elseif record.model == "RetainedPivotV1" then
		relation, reason = PinnedPivot.resolve(record, components, poses)
	elseif record.model == "LinearGuideV1" or record.model == "LimitedGuideV1" then
		relation, reason = guide(record, components, poses, ground)
	else
		return nil, "Unsupported relationship; legacy joints are not activated"
	end
	if not relation then
		return nil, reason
	end
	if ground[tostring(relation.movingId)] then
		return nil, "Release the moving component from the bench first"
	end
	if record.model == "RetainedBoreV1" or record.model == "LimitedGuideV1" then
		if not ground[tostring(relation.bodyId)] then
			return nil, "A retained bench mechanism needs a fixed housing or guide"
		end
		local low, high, problem = Geometry.stops(
			record.stopIds,
			components,
			poses,
			ground,
			relation.basis,
			relation.halfSize
		)
		if not low or not high then
			return nil, problem
		end
		for _, id in ipairs(record.stopIds) do
			if
				id == relation.movingId
				or id == relation.bodyId
				or table.find(record.guideIds or {}, id)
			then
				return nil, "End-stop plates must be separate from the shaft, housing, and rails"
			end
		end
		for _, distance in ipairs({ low, high }) do
			local atLimit = table.clone(poses)
			atLimit[tostring(relation.movingId)] = poses[tostring(relation.movingId)]
				+ relation.direction * distance
			local supported = if relation.kind == "Cylindrical"
				then bore(record, components, atLimit)
				else guide(record, components, atLimit, ground)
			if not supported then
				return nil,
					"End-stop travel lets the moving part leave its support; move the stops inward"
			end
		end
		relation.limits = { min = low, max = high }
		relation.retained = true
	end
	return relation, nil
end
return Resolver
