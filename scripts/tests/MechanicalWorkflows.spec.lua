--!strict
return function(Resolver, Geometry)
	local count = 0
	local function check(value, message)
		assert(value, message)
		count += 1
	end
	local function box(id, size)
		return { id = id, nodes = { { kind = "Block", size = size } }, operations = {} }
	end
	local housing = box(1, Vector3.one)
	housing.operations = {
		{
			id = 1,
			kind = "DrillFace",
			origin = Vector3.new(0, 0.5, 0),
			normal = Vector3.yAxis,
			diameter = 0.11,
			depth = 1,
			through = true,
		},
	}
	local shaft = {
		id = 2,
		nodes = { { kind = "Cylinder", size = Vector3.new(0.1, 2, 0.1) } },
		operations = {},
	}
	local parts = { [1] = housing, [2] = shaft }
	local poses = { ["1"] = CFrame.identity, ["2"] = CFrame.identity }
	local bearing = { model = "BoreSupportV1", bodyId = 1, shaftId = 2, featureId = "hole:1" }
	check(Resolver.resolve(bearing, parts, poses) ~= nil, "UI-created top-face bore rejected")
	housing.operations[1].origin = Vector3.new(0.5, 0, 0)
	housing.operations[1].normal = Vector3.xAxis
	poses["2"] = CFrame.fromAxisAngle(Vector3.zAxis, math.pi * 0.5)
	check(Resolver.resolve(bearing, parts, poses) ~= nil, "Side-face bore rejected")
	housing.operations[1].origin = Vector3.new(0.5, 0.49, 0)
	check(Resolver.resolve(bearing, parts, poses) == nil, "Open-edge hole accepted as full bearing")
	housing.operations[1].origin = Vector3.new(0, 0.5, 0)
	housing.operations[1].normal = Vector3.yAxis
	poses["2"] = CFrame.identity
	housing.operations[1].through = false
	check(Resolver.resolve(bearing, parts, poses) == nil, "Blind bore treated as through-bearing")
	housing.operations[1].through = true
	check(
		Resolver.resolve(bearing, parts, poses, { ["2"] = true }) == nil,
		"Grounded mover accepted"
	)
	local retained = table.clone(bearing)
	retained.model = "RetainedBoreV1"
	retained.stopIds = { 3, 4 }
	parts[3], parts[4] = box(3, Vector3.new(0.3, 0.1, 0.3)), box(4, Vector3.new(0.3, 0.1, 0.3))
	poses["3"], poses["4"] = CFrame.new(0, -1.055, 0), CFrame.new(0, 1.055, 0)
	local ground = { ["1"] = true, ["3"] = true, ["4"] = true }
	local relation, reason = Resolver.resolve(retained, parts, poses, ground)
	check(relation ~= nil, reason)
	check(
		relation.retained and math.abs(relation.limits.max - relation.limits.min - 0.01) < 1e-6,
		"Stop-derived endplay incorrect"
	)
	ground["3"] = nil
	check(
		Resolver.resolve(retained, parts, poses, ground) == nil,
		"Loose stop plate created retention"
	)
	ground["3"] = true
	poses["3"] = CFrame.new(0, 1.06, 0)
	check(Resolver.resolve(retained, parts, poses, ground) == nil, "Two same-side stops accepted")
	poses["3"] = CFrame.new(0, -1.055, 0)
	parts[3].nodes[1].size = Vector3.new(0.01, 0.1, 0.01)
	check(Resolver.resolve(retained, parts, poses, ground) == nil, "Undersized stop cap accepted")

	for _, id in ipairs({ 3, 4 }) do
		parts[id].nodes[1] = {
			kind = "SketchBody",
			size = Vector3.new(1, 0.1, 1),
			profileSize = Vector2.new(1, 1),
			profilePoints = {
				Vector2.new(-0.15, -0.15),
				Vector2.new(0.15, -0.15),
				Vector2.new(0.15, 0.15),
				Vector2.new(-0.15, 0.15),
			},
		}
	end
	check(
		Resolver.resolve(retained, parts, poses, ground) ~= nil,
		"Manufactured sketch bearing end plates rejected"
	)

	local mover = box(10, Vector3.new(0.2, 0.4, 0.2))
	parts = { [10] = mover }
	poses, ground = { ["10"] = CFrame.identity }, {}
	local ids = { 11, 12, 13, 14 }
	for i, id in ipairs(ids) do
		local size = if i <= 2 then Vector3.new(0.1, 2, 0.2) else Vector3.new(0.2, 2, 0.1)
		parts[id] = box(id, size)
		local sign = if i % 2 == 1 then -1 else 1
		poses[tostring(id)] = CFrame.new(
			if i <= 2 then Vector3.new(sign * 0.153, 0, 0) else Vector3.new(0, 0, sign * 0.153)
		)
		ground[tostring(id)] = true
	end
	local guide = { model = "LinearGuideV1", movingId = 10, guideIds = ids }
	relation, reason = Resolver.resolve(guide, parts, poses, ground)
	check(relation ~= nil, reason)
	check(relation.rotation == 0 and relation.translation == 1, "Rectangular guide has wrong DOFs")
	ground["11"] = nil
	check(Resolver.resolve(guide, parts, poses, ground) == nil, "Floating guide rail accepted")
	ground["11"] = true
	poses["11"] = CFrame.new(-0.2, 0, 0)
	check(Resolver.resolve(guide, parts, poses, ground) == nil, "Excess rail clearance accepted")
	poses["11"] = CFrame.new(-0.153, 0, 0)
	poses["10"] = CFrame.new(0, 2, 0)
	check(Resolver.resolve(guide, parts, poses, ground) == nil, "Disengaged carriage retained")
	poses["10"] = CFrame.identity
	local limited = table.clone(guide)
	limited.model, limited.stopIds = "LimitedGuideV1", { 15, 16 }
	parts[15], parts[16] = box(15, Vector3.new(0.2, 0.1, 0.2)), box(16, Vector3.new(0.2, 0.1, 0.2))
	poses["15"], poses["16"] = CFrame.new(0, -0.75, 0), CFrame.new(0, 0.75, 0)
	ground["15"], ground["16"] = true, true
	relation, reason = Resolver.resolve(limited, parts, poses, ground)
	check(relation ~= nil, reason)
	check(
		math.abs(relation.limits.min + 0.5) < 1e-6 and math.abs(relation.limits.max - 0.5) < 1e-6,
		"Guide stroke differs from physical stops"
	)
	check(#Resolver.dependencies(limited) == 7, "Fixture deletion misses relationship dependencies")
	poses["15"], poses["16"] = CFrame.new(0, -3, 0), CFrame.new(0, 3, 0)
	check(
		Resolver.resolve(limited, parts, poses, ground) == nil,
		"Stops beyond guide engagement accepted"
	)
	local malformed = box(20, Vector3.one)
	malformed.nodes[1].kind = "SketchBody"
	malformed.nodes[1].profileSize = Vector2.new(1, 1)
	malformed.nodes[1].profilePoints = {
		Vector2.new(-0.5, -0.5),
		Vector2.new(0.5, -0.5),
		Vector2.new(0, 0),
		Vector2.new(-0.5, 0.5),
	}
	check(Geometry.box(malformed) == nil, "Nonrectangular stock accepted as linear carriage")
	-- Real CreateSketchBody snapshots retain the workspace envelope in node.size.
	for _, component in pairs(parts) do
		local node = component.nodes[1]
		local size = node.size
		if node.kind == "Block" then
			node.kind = "SketchBody"
			node.profileSize = Vector2.new(1, 1)
			node.profilePoints = {
				Vector2.new(-size.X / 2, -size.Z / 2),
				Vector2.new(size.X / 2, -size.Z / 2),
				Vector2.new(size.X / 2, size.Z / 2),
				Vector2.new(-size.X / 2, size.Z / 2),
			}
			node.size = Vector3.new(1, size.Y, 1)
		end
	end
	poses["15"], poses["16"] = CFrame.new(0, -0.75, 0), CFrame.new(0, 0.75, 0)
	check(
		Resolver.resolve(limited, parts, poses, ground) ~= nil,
		"Manufactured sketch guide rejected due to workspace envelope"
	)
	local plate = Geometry.box(parts[15])
	check(
		plate and math.abs(plate.X - 0.2) < 1e-6,
		"End plate dimensions use workspace instead of material"
	)
	return count
end
