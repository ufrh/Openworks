--!strict
-- Pure CAD fit tests: location comes from selected source datums, while
-- clearance/penetration is deliberately deferred to compiled solid checks.
return function(Placement, References)
	local count = 0
	local function check(ok: boolean, message: string)
		assert(ok, message)
		count += 1
	end
	local shaft = {
		id = "shaft", kind = "Axis", point = Vector3.zero,
		direction = Vector3.yAxis, diameter = 28 / 280,
	}
	local bore = {
		id = "hole:1", kind = "Axis", point = Vector3.new(0.25, 0, 0),
		direction = Vector3.yAxis, diameter = 31 / 280,
		feature = {through = true},
	}
	local old = CFrame.new(7, 8, 9)
	local housing = CFrame.new(10, 11, 12)
	local inserted, problem = Placement.solve(old, shaft, housing, bore, 140)
	check(inserted ~= nil, tostring(problem))
	local point = inserted:PointToWorldSpace(shaft.point)
	check((point - Vector3.new(10.25, 11.5, 12)).Magnitude < 1e-6,
		"Axial offset should be absolute relative to the selected bore center")
	check(math.abs(inserted:VectorToWorldSpace(Vector3.yAxis):Dot(Vector3.yAxis)) > 0.999999,
		"Parallel shaft should keep its source axis")
	local otherBore = table.clone(bore)
	otherBore.direction = Vector3.xAxis
	local side, err = Placement.solve(old, shaft, housing, otherBore, -56)
	check(side ~= nil, tostring(err))
	local axis = side:VectorToWorldSpace(Vector3.yAxis)
	check(math.abs(axis:Dot(Vector3.xAxis)) > 0.999999,
		"Side-face bore must rotate shaft into the manufactured bore axis")
	local point2 = side:PointToWorldSpace(shaft.point)
	check((point2 - Vector3.new(10.05, 11, 12)).Magnitude < 1e-6,
		"Side-face insertion must preserve signed axial depth")
	check(Placement.solve(old, shaft, housing, bore, math.huge) == nil,
		"Nonfinite axial offset must fail")
	check(Placement.solve(old, shaft, housing, bore, 40000) == nil,
		"Offset beyond workspace must fail")
	check(Placement.solve(old, {kind = "Plane"}, housing, bore, 0) == nil,
		"Non-cylindrical shaft datum must fail")
	local modified = {
		nodes = {{kind = "Cylinder", size = Vector3.new(0.1, 1, 0.1)}},
		operations = {{kind = "SketchExtrude", mode = "Add", enabled = true}},
	}
	check(References.get(modified, "shaft") ~= nil,
		"Manufactured shoulders cannot erase the base shaft axis datum")
	return count
end
