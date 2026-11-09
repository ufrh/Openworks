--!strict
return function(Session, Compiler, Instance)
	local count = 0
	local function check(v, m)
		assert(v, m)
		count += 1
	end
	local parts = { [1] = Instance.new("Part"), [2] = Instance.new("Part") }
	for id, part in pairs(parts) do
		part.CFrame = CFrame.new(id, 3, 0)
		part.AssemblyLinearVelocity = Vector3.new(id, 0, 0)
		part.AssemblyAngularVelocity = Vector3.new(0, id, 0)
	end
	local root = Instance.new("Folder")
	local relation = {
		kind = "Cylindrical",
		model = "RetainedBoreV1",
		bodyId = 1,
		movingId = 2,
		point = Vector3.new(2, 3, 0),
		direction = Vector3.yAxis,
		limits = { min = -0.05, max = 0.05 },
	}
	local objects, problem = Compiler.compileResolved(relation, parts, root)
	check(objects ~= nil, problem)
	check(
		objects[1].InclinationAngle == 0 and objects[1].LimitsEnabled,
		"Retained bearing compiler lost common axis / limits"
	)
	check(
		objects[1].LowerLimit == -0.05 and objects[1].UpperLimit == 0.05,
		"Derived stop limits changed"
	)
	check(parts[1].CanCollide and parts[2].CanCollide, "Constraint compiler disabled collisions")
	for _, obj in ipairs(objects) do
		check(
			not obj:IsA("Part") and not obj:IsA("WeldConstraint"),
			"Compiler fabricated hardware or fastening"
		)
	end
	local item = { record = {}, relation = relation, objects = objects, localAxis = Vector3.yAxis }
	local session = {
		parts = parts,
		grounded = { ["1"] = true },
		paused = false,
		initial = { [1] = parts[1].CFrame, [2] = parts[2].CFrame },
		root = root,
		relations = { item },
		acceptedRelations = { item },
		released = 0,
	}
	Session.pause(session, true)
	check(
		parts[1].Anchored and parts[2].Anchored and session.paused,
		"Pause did not freeze the whole session"
	)
	parts[2].AssemblyLinearVelocity = Vector3.zero
	Session.pause(session, false)
	check(parts[1].Anchored and not parts[2].Anchored, "Resume forgot grounding")
	check(parts[2].AssemblyLinearVelocity.X == 2, "Resume did not restore velocity")
	parts[2].CFrame = CFrame.new(10, 10, 10)
	local ok, err = Session.reset(session)
	check(ok, err)
	check(
		parts[2].CFrame == session.initial[2] and not session.paused,
		"Running reset did not restore position / state"
	)
	check(
		parts[2].AssemblyLinearVelocity.Magnitude == 0
			and parts[2].AssemblyAngularVelocity.Magnitude == 0,
		"Reset retained motion"
	)
	check(
		objects[1].destroyed and #session.relations == 1,
		"Reset leaked old constraints or lost relationship"
	)
	Session.pause(session, true)
	check(
		Session.reset(session) and session.paused and parts[2].Anchored,
		"Paused reset resumed unexpectedly"
	)
	relation.kind, relation.model = "Prismatic", "LimitedGuideV1"
	local linear = Compiler.compileResolved(relation, parts, root)
	check(
		linear[1]:IsA("PrismaticConstraint") and linear[1].LimitsEnabled,
		"Linear guide compiler incorrect"
	)
	return count
end
