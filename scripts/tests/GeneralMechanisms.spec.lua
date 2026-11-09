--!strict
-- General mechanism domain: two retained pins lock separate authored links;
-- measured CAD references never create a joint or generated hardware.
return function(Resolver, Coupling, FitInspection, Compiler)
	local count = 0
	local function check(condition: boolean, reason: string)
		assert(condition, reason)
		count += 1
	end
	local function box(id: number)
		return {
			id = id,
			nodes = {{kind = "Block", size = Vector3.new(0.8, 0.1, 0.4)}},
			operations = {
				{
					id = 1, kind = "DrillFace",
					origin = Vector3.new(0, 0.05, 0),
					normal = Vector3.yAxis,
					diameter = 0.13, depth = 0.1, through = true,
				},
				{
					id = 2, kind = "DrillFace",
					origin = Vector3.new(0.25, 0.05, 0),
					normal = Vector3.yAxis,
					diameter = 0.13, depth = 0.1, through = true,
				},
			},
		}
	end
	local components = {[1] = box(1), [2] = box(2)}
	local poses = {["1"] = CFrame.identity, ["2"] = CFrame.new(0, 0.2, 0)}
	for _, id in ipairs({3, 6}) do
		components[id] = {
			id = id,
			nodes = {{kind = "Cylinder", size = Vector3.new(0.12, 0.7, 0.12)}},
			operations = {},
		}
		poses[tostring(id)] = CFrame.new(if id == 3 then 0 else 0.25, 0.1, 0)
	end
	for index, id in ipairs({4, 5, 7, 8}) do
		components[id] = {
			id = id,
			nodes = {{kind = "Block", size = Vector3.new(0.2, 0.08, 0.2)}},
			operations = {},
		}
		poses[tostring(id)] = CFrame.new(if index <= 2 then 0 else 0.25,
			if index % 2 == 1 then -0.29 else 0.49, 0)
	end
	local record = {
		model = "DualPinRigidV1", bodyId = 1, movingId = 2,
		featureId = "hole:1", movingFeatureId = "hole:1",
		pinIds = {3, 6},
		stopIds = {4, 5, 7, 8},
	}
	local relation, reason = Resolver.resolve(record, components, poses, {["1"] = true})
	check(relation ~= nil, reason or "Physically valid dual-pin fit rejected")
	check(relation.kind == "Rigid" and relation.rotation == 0 and relation.translation == 0,
		"Dual retained pins must eliminate all relative motion")
	check(#Resolver.dependencies(record) == 8,
		"All joint members and manufactured retainers must be tracked for deletion")
	local found, why = Coupling.resolve(record, components, poses)
	check(found ~= nil and why == nil, "Direct physical coupling validation diverges")

	local fake = {}
	for id in pairs(components) do fake[id] = Instance.new("Part") end
	local constraints, compileProblem = Compiler.compileResolved(relation, fake, Instance.new("Folder"))
	check(constraints ~= nil, compileProblem or "Rigid connection failed to compile")
	check(#constraints == 7, "Weld solver must include both links, two pins, and four retainers")
	for _, joint in ipairs(constraints) do
		check(joint:IsA("WeldConstraint"), "Compiler generated hardware or non-rigid constraints")
	end
	Compiler.destroy(constraints)

	poses["6"] = CFrame.new(0.12, 0.1, 0)
	check(Resolver.resolve(record, components, poses, {["1"] = true}) == nil,
		"Misaligned second physical pin must fail")
	poses["6"] = CFrame.new(0.25, 0.1, 0)

	components[7] = nil
	check(Resolver.resolve(record, components, poses, {["1"] = true}) == nil,
		"Missing retainer must invalidate connection")

	local axisA = {kind = "Axis", point = Vector3.zero,
		direction = Vector3.yAxis, diameter = 0.12}
	local axisB = {kind = "Axis", point = Vector3.new(0.01, 0.2, 0),
		direction = Vector3.yAxis, diameter = 0.13}
	local measure = FitInspection.measure(axisA, axisB)
	check(measure ~= nil and math.abs(measure.radial - 2.8) < 1e-5,
		"Measured axis offset differs from authored geometry")
	check(math.abs(measure.diametralDifference - 2.8) < 1e-5,
		"Measured diametral difference must use physical mm")
	check(not FitInspection.measure(axisA, {kind = "Plane", point = Vector3.zero,
		direction = Vector3.xAxis}),
		"Axis and planar-face measurements must not be conflated")
	return count
end
