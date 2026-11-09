--!strict
return function(PivotPlacement, Resolver)
	local count = 0
	local function check(value: boolean, message: string)
		assert(value, message)
		count += 1
	end
	local function link(id: number)
		return {
			id = id,
			nodes = {{kind = "Block", size = Vector3.new(0.6, 0.2, 0.6)}},
			operations = {{
				id = 1, kind = "DrillFace",
				origin = Vector3.new(0, 0.1, 0),
				normal = Vector3.yAxis,
				diameter = 0.11, depth = 0.2, through = true,
			}},
		}
	end
	local parts = {
		[1] = link(1),
		[2] = link(2),
		[3] = {id = 3, nodes = {{
			kind = "Cylinder", size = Vector3.new(0.1, 0.7, 0.1)
		}}, operations = {}},
	}
	for _, id in ipairs({4, 5}) do
		parts[id] = {id = id, nodes = {{
			kind = "Block", size = Vector3.new(0.2, 0.08, 0.2)
		}}, operations = {}}
	end
	local poses = {
		["1"] = CFrame.new(10, 11, 12),
		["2"] = CFrame.new(7, 8, 9),
		["3"] = CFrame.new(2, 3, 4),
		["4"] = CFrame.new(4, 5, 6),
		["5"] = CFrame.new(1, 2, 3),
	}
	local proposed, record, why = PivotPlacement.propose(
		parts, poses, 1, "hole:1", 2, "hole:1", 3, 4, 5, 56, 20
	)
	check(proposed ~= nil, tostring(why))
	check((poses["2"].Position - Vector3.new(7, 8, 9)).Magnitude < 1e-6,
		"Preview must not mutate source assembly poses")
	local relation, problem = Resolver.resolve(record, parts, proposed, {["1"] = true})
	check(relation ~= nil, tostring(problem))
	check(relation.kind == "Revolute" and relation.retained,
		"Proper pin and retainer geometry must produce retained revolute motion")
	local capA = proposed["4"]
	local capB = proposed["5"]
	check((capA.Position - capB.Position).Magnitude > 0.7,
		"Two retaining caps must be placed at opposite ends of the pin")
	local bad, _, reason = PivotPlacement.propose(
		parts, poses, 1, "hole:1", 2, "hole:1", 3, 4, 4, 56, 0
	)
	check(bad == nil and reason ~= nil,
		"Reused manufactured hardware must fail")
	check(PivotPlacement.propose(
		parts, poses, 1, "hole:1", 2, "hole:1", 3, 4, 5, 35841, 0
	) == nil, "Out-of-range stack spacing must fail")
	return count
end
