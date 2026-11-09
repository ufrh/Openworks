--!strict
return function(Integrity)
	local count = 0
	local function check(value: boolean, message: string)
		assert(value, message)
		count += 1
	end
	local function pivot(body, mover, pin, capA, capB)
		return {
			model = "RetainedPivotV1", bodyId = body, movingId = mover,
			pinId = pin, stopIds = {capA, capB},
			featureId = "hole:1", movingFeatureId = "hole:1",
		}
	end
	local first = pivot(1, 2, 3, 4, 5)
	local second = pivot(2, 6, 7, 8, 9)
	check(Integrity.canAdd({}, first), "A valid manufactured pivot should be accepted")
	check(Integrity.canAdd({first}, second),
		"A connecting rod must allow pivots at distinct ends")
	check(not Integrity.canAdd({first}, pivot(1, 2, 10, 11, 12)),
		"Two redundant hinge models between identical members should be rejected")
	check(not Integrity.canAdd({first}, pivot(10, 11, 3, 12, 13)),
		"A manufactured pin cannot be shared across independent joints")
	check(not Integrity.canAdd({first}, pivot(10, 11, 14, 5, 13)),
		"A manufactured retainer cannot be reused across independent joints")
	local rigid = {
		model = "DualPinRigidV1", bodyId = 10, movingId = 11,
		pinIds = {20, 23}, stopIds = {21, 22, 24, 25},
	}
	check(Integrity.canAdd({first, second}, rigid),
		"Rigid dual-pin coupling should coexist with an independent linkage")
	check(not Integrity.canAdd({rigid}, pivot(10, 11, 30, 31, 32)),
		"A fixed coupling cannot also have a revolute constraint across the same bodies")
	check(not Integrity.canAdd({rigid}, pivot(40, 41, 20, 42, 43)),
		"A pin belonging to a fixed coupling is unavailable for another joint")
	local guide = {model = "LimitedGuideV1", movingId = 2}
	check(Integrity.canAdd({first}, guide),
		"A slider should be able to combine guide translation with a separate pivot")
	check(not Integrity.canAdd({guide}, {model = "LinearGuideV1", movingId = 2}),
		"Duplicate guides overconstrain the same moving body")
	check(Integrity.canAdd({guide}, pivot(1, 2, 3, 4, 5)),
		"A guide and independently manufactured crank linkage can coexist")
	return count
end
