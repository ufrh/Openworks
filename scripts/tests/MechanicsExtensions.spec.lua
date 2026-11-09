--!strict
-- Host-domain tests: manufactured pin pivots, sketch-plane normals,
-- horizontal guide datums and external motor/servo validation.
return function(Resolver, Geometry, PinnedPivot, BenchDrive)
	local count = 0
	local function check(condition, message)
		assert(condition, message)
		count += 1
	end

	local function rectangularStock(id, x, y, z)
		return {
			id = id,
			nodes = {{
				kind = "SketchBody",
				size = Vector3.new(x, y, z),
				profileSize = Vector2.new(x, z),
				profilePoints = {
					Vector2.new(-x / 2, -z / 2),
					Vector2.new(x / 2, -z / 2),
					Vector2.new(x / 2, z / 2),
					Vector2.new(-x / 2, z / 2),
				},
			}},
			operations = {},
		}
	end
	local housing = rectangularStock(1, 0.4, 0.1, 0.4)
	local link = rectangularStock(2, 0.4, 0.1, 0.4)
	local pin = {
		id = 3,
		nodes = {{kind = "Cylinder", size = Vector3.new(0.12, 0.7, 0.12)}},
		operations = {},
	}
	local bottom = rectangularStock(4, 0.2, 0.08, 0.2)
	local top = rectangularStock(5, 0.2, 0.08, 0.2)
	local components = {[1] = housing, [2] = link, [3] = pin, [4] = bottom, [5] = top}

	local bore = {
		id = 1,
		kind = "DrillFace",
		origin = Vector3.new(0, 0.05, 0),
		normal = Vector3.yAxis,
		diameter = 0.13,
		depth = 0.1,
		through = true,
	}
	housing.operations = {table.clone(bore)}
	link.operations = {table.clone(bore)}

	local planes = Geometry.planes(housing.nodes[1])
	check(planes and #planes == 6, "Convex sketch should generate six exterior planes")
	local low, high = Geometry.boreSpan(
		housing.nodes[1], bore.origin, -Vector3.yAxis, 0.13 / 2 + Geometry.Wall
	)
	check(low ~= nil and high ~= nil and high > low,
		"Counterclockwise sketch normals incorrectly reject a centered through-bore")

	local poses = {
		["1"] = CFrame.identity,
		["2"] = CFrame.new(0, 0.2, 0),
		["3"] = CFrame.new(0, 0.1, 0),
		["4"] = CFrame.new(0, -0.29, 0),
		["5"] = CFrame.new(0, 0.49, 0),
	}
	local record = {
		model = "RetainedPivotV1", bodyId = 1, movingId = 2,
		featureId = "hole:1", movingFeatureId = "hole:1",
		pinId = 3, stopIds = {4, 5},
	}
	local relation, reason = Resolver.resolve(record, components, poses, {["1"] = true})
	check(relation ~= nil, reason)
	check(relation.kind == "Revolute" and relation.rotation == 1
		and relation.translation == 0 and relation.retained,
		"Manufactured pin must compile to one retained rotational DOF")

	pin.nodes[1].size = Vector3.new(0.16, 0.7, 0.16)
	check(Resolver.resolve(record, components, poses, {["1"] = true}) == nil,
		"Oversize pin incorrectly accepted")
	pin.nodes[1].size = Vector3.new(0.12, 0.7, 0.12)

	poses["5"] = CFrame.new(0.05, 0.49, 0)
	check(Resolver.resolve(record, components, poses, {["1"] = true}) == nil,
		"Off-center manufactured end cap incorrectly accepted")
	poses["5"] = CFrame.new(0, 0.49, 0)

	poses["2"] = CFrame.new(0.03, 0.2, 0)
	check(Resolver.resolve(record, components, poses, {["1"] = true}) == nil,
		"Misaligned link bore incorrectly accepted")
	poses["2"] = CFrame.new(0, 0.2, 0)

	check(#Resolver.dependencies(record) == 5,
		"Deleting a manufactured pin or cap must remove the dependent pivot")
	check(PinnedPivot.resolve(record, components, poses) ~= nil,
		"Independent pivot resolution should agree with the shared resolver")

	local revolute = {kind = "Revolute"}
	local slide = {kind = "Prismatic"}
	check(BenchDrive.validate(revolute, 2 * math.pi, 200, "Motor"),
		"Bounded revolute motor rejected")
	check(BenchDrive.validate(revolute, 1, 200, "Servo", 45),
		"Bounded revolute servo rejected")
	check(BenchDrive.validate(slide, 0.5, 200, "Servo", 0.1),
		"Bounded linear servo rejected")
	check(not BenchDrive.validate(slide, 5, 200, "Motor"),
		"Over-speed linear drive incorrectly accepted")
	check(not BenchDrive.validate(revolute, 1, -1, "Motor"),
		"Negative drive effort incorrectly accepted")
	check(not BenchDrive.validate(revolute, 1, 200, "Servo", math.huge),
		"Nonfinite servo target incorrectly accepted")
	return count
end
