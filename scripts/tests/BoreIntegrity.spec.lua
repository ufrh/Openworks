--!strict
return function(BoreIntegrity, GeometryReferences, MechanicalResolver)
	local count = 0
	local function check(value: boolean, message: string)
		assert(value, message)
		count += 1
	end
	local housing = {
		id = 10,
		nodes = {{kind = "Block", size = Vector3.one}},
		operations = {
			{ id = 1, kind = "DrillFace", origin = Vector3.new(0, 0.5, 0),
				normal = Vector3.yAxis, diameter = 0.11, depth = 1, through = true },
			{ id = 2, kind = "DrillFace", origin = Vector3.new(0.3, 0.5, 0),
				normal = Vector3.yAxis, diameter = 0.11, depth = 1, through = true },
		},
	}
	local shaft = {
		id = 11,
		nodes = {{kind = "Cylinder", size = Vector3.new(0.1, 2, 0.1)}},
		operations = {},
	}
	local hole = GeometryReferences.get(housing, "hole:1")
	local accepted, reason = BoreIntegrity.check(housing, hole)
	check(accepted, reason or "Separated manufacturing bores should retain their walls")

	local parts = {[10] = housing, [11] = shaft}
	local poses = {["10"] = CFrame.identity, ["11"] = CFrame.identity}
	local joint = {model = "BoreSupportV1", bodyId = 10, shaftId = 11, featureId = "hole:1"}
	check(MechanicalResolver.resolve(joint, parts, poses) ~= nil,
		"A bearing housing can have additional independent mounting holes")

	housing.operations[2].origin = Vector3.new(0.05, 0.5, 0)
	hole = GeometryReferences.get(housing, "hole:1")
	check(not BoreIntegrity.check(housing, hole),
		"Physically overlapping drill holes may not be certified as separate bearings")
	check(MechanicalResolver.resolve(joint, parts, poses) == nil,
		"Merged bore paths cannot create an ideal bearing")

	housing.operations[2].origin = Vector3.new(0.3, 0.5, 0)
	table.insert(housing.operations, {id = 3, kind = "Saw", enabled = true})
	check(not BoreIntegrity.check(housing, hole),
		"Uncertified material removal must invalidate structural bore support")
	housing.operations[3].enabled = false
	check(BoreIntegrity.check(housing, hole),
		"Disabled manufacturing operations must not invalidate bores")
	table.insert(housing.operations, {
		id = 4, kind = "AddPrimitive", primitive = "Block",
		size = Vector3.new(0.4, 0.1, 0.4),
		position = Vector3.new(0, 0.55, 0), rotation = Vector3.zero,
	})
	check(BoreIntegrity.check(housing, hole),
		"Added housing material must not be mistaken for removed bore wall")
	housing.operations[4] = {
		id = 4, kind = "SketchExtrude", mode = "Add", enabled = true,
	}
	check(BoreIntegrity.check(housing, hole),
		"Additive sketches should be allowed before final-solid interference checks")

	return count
end
