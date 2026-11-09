--!strict
local RS = game:GetService("ReplicatedStorage")
local FORGE = require(RS:WaitForChild("FORGE"))
local docs = FORGE:GetService("OpenWorksDocuments")
local assembly = FORGE:GetService("OpenWorksAssembly")
local made = {}
local function expect(ok, value)
	assert(ok, tostring(value))
	return value
end
local function layout()
	return expect(assembly:GetLayout())
end
local function place(component, pose)
	return expect(assembly:SetPose(component.id, component.revision, layout().revision, pose))
end
local success, problem = xpcall(function()
	local square = {
		Vector2.new(-0.3, -0.3),
		Vector2.new(0.3, -0.3),
		Vector2.new(0.3, 0.3),
		Vector2.new(-0.3, 0.3),
	}
	for index = 1, 2 do
		local body = expect(
			docs:CreateSketchBody(
				"CAD_TEST_" .. index,
				Vector3.new(index * 2, 3, 0),
				Vector3.new(-0.3, 200, -0.3),
				Vector3.new(0.6, 1, 0.6),
				square,
				0.2
			)
		)
		made[#made + 1] = body
		body = expect(docs:ApplyOperation(body.id, body.revision, "DrillFace", {
			origin = Vector3.new(0, body.nodes[1].size.Y * 0.5, 0),
			normal = Vector3.yAxis,
			diameter = 31 / 280,
			depth = 0.2,
			through = true,
		}))
		made[#made] = body
	end
	local shaft = expect(
		docs:CreateCylinder(
			"CAD_TEST_SHAFT",
			Vector3.new(6, 3, 0),
			Vector3.new(-0.3, 200, -0.3),
			Vector3.new(0.6, 1, 0.6),
			0.1,
			0.8
		)
	)
	table.insert(made, shaft)
	local origin = Vector3.new(140, 205, 20)
	place(made[1], CFrame.new(origin))
	place(made[2], CFrame.new(origin + Vector3.new(0, 0.4, 0)))
	place(shaft, CFrame.new(origin + Vector3.new(0, 0.2, 0)))
	local state = layout()
	local before = state.poses[tostring(shaft.id)]
	local rejected = assembly:SetPose(
		shaft.id,
		shaft.revision,
		state.revision,
		CFrame.new(origin + Vector3.new(0.2, 0, 0))
	)
	assert(not rejected, "Penetrating shaft placement accepted")
	assert(layout().poses[tostring(shaft.id)] == before, "Rejected placement changed saved pose")
	local tooLarge = expect(
		docs:CreateCylinder(
			"CAD_TEST_OVERSIZED",
			Vector3.new(8, 3, 0),
			Vector3.new(-0.3, 200, -0.3),
			Vector3.new(0.6, 1, 0.6),
			0.2,
			0.8
		)
	)
	table.insert(made, tooLarge)
	assert(
		not assembly:SetPose(tooLarge.id, tooLarge.revision, layout().revision, CFrame.new(origin)),
		"Oversized shaft was accepted inside bore"
	)
	assert(
		not assembly:Install(
			"Revolute",
			made[1].id,
			"hole:1",
			made[2].id,
			"hole:1",
			shaft.id,
			CFrame.identity,
			CFrame.identity
		)
	)
	local featureId = "hole:" .. made[1].operations[1].id
	expect(assembly:RegisterSupport(made[1].id, featureId, shaft.id, layout().revision))
	expect(assembly:SetGrounded(made[1].id, layout().revision, true))
	local poses = layout().poses
	local revision = shaft.revision
	for _ = 1, 3 do
		expect(assembly:StartSimulation(layout().revision))
		local paused = expect(assembly:SimulationControl("Pause"))
		assert(paused.paused, "Pause did not stick")
		assert(
			not assembly:TestImpulse(shaft.id, "Spin", "Motion", 90),
			"Paused body accepted impulse"
		)
		local reset = expect(assembly:SimulationControl("Reset"))
		assert(
			reset.paused and reset.supports == 1 and reset.released == 0,
			"Paused reset lost support"
		)
		expect(assembly:SimulationControl("Resume"))
		expect(assembly:TestImpulse(shaft.id, "Spin", "Motion", 90))
		task.wait(0.2)
		expect(assembly:SimulationControl("Reset"))
		expect(assembly:TestImpulse(shaft.id, "Push", "Motion", 100))
		task.wait(0.2)
		expect(assembly:StopSimulation())
		expect(assembly:StopSimulation())
		local restored = layout()
		for id, pose in pairs(poses) do
			assert(restored.poses[id] == pose, "Simulation changed authored pose")
		end
	end
	local current = expect(docs:GetSnapshot(shaft.id))
	assert(current.revision == revision, "Simulation changed FORM history")
end, debug.traceback)
assembly:StopSimulation()
for _, component in ipairs(made) do
	local ok, current = docs:GetSnapshot(component.id)
	if ok then
		docs:DeleteComponent(component.id, current.revision)
	end
end
assert(success, problem)
print(
	"CAD WORKFLOW PASS: manufactured components, server clearance, rejection rollback, UI through-drill, explicit support, pause/spin/push/reset, repeated simulation restoration"
)
