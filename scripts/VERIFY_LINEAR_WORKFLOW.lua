--!strict
-- Client Play Command Bar; use an otherwise valid workshop. Creates and cleans up its own parts.
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
local center = Vector3.new(140, 205, -20)
local function stock(name, size, offset, fixed)
	local x, z = size.X * 0.5, size.Z * 0.5
	local component = expect(
		docs:CreateSketchBody(
			"GUIDE_TEST_" .. name,
			Vector3.new(30 + #made * 3, 3, 0),
			Vector3.new(-0.5, 200, -0.5),
			Vector3.new(1, 3, 1),
			{ Vector2.new(-x, -z), Vector2.new(x, -z), Vector2.new(x, z), Vector2.new(-x, z) },
			size.Y
		)
	)
	table.insert(made, component)
	expect(
		assembly:SetPose(
			component.id,
			component.revision,
			layout().revision,
			CFrame.new(center + offset)
		)
	)
	if fixed then
		expect(assembly:SetGrounded(component.id, layout().revision, true))
	end
	return component.id
end
local success, problem = xpcall(function()
	local mover = stock("Carriage", Vector3.new(0.2, 0.4, 0.2), Vector3.zero, false)
	local rails = {}
	for i = 1, 4 do
		local sign = if i % 2 == 1 then -1 else 1
		local size = if i <= 2 then Vector3.new(0.1, 2, 0.2) else Vector3.new(0.2, 2, 0.1)
		local offset = if i <= 2
			then Vector3.new(sign * 43 / 280, 0, 0)
			else Vector3.new(0, 0, sign * 43 / 280)
		table.insert(rails, stock("Rail" .. i, size, offset, true))
	end
	expect(assembly:RegisterRelationship("LinearGuideV1", mover, 0, "", rails, layout().revision))
	-- Replace the open guide with the same manufactured guide and two actual end plates.
	local current = layout()
	expect(assembly:RemoveSupport(#current.supports, current.revision))
	table.insert(
		rails,
		stock("LowerStop", Vector3.new(0.2, 0.1, 0.2), Vector3.new(0, -0.75, 0), true)
	)
	table.insert(
		rails,
		stock("UpperStop", Vector3.new(0.2, 0.1, 0.2), Vector3.new(0, 0.75, 0), true)
	)
	expect(assembly:RegisterRelationship("LimitedGuideV1", mover, 0, "", rails, layout().revision))
	local report = expect(assembly:ValidateAssembly(layout().revision))
	assert(report.valid, report.message)
	local before = layout().poses
	for _ = 1, 3 do
		expect(assembly:StartSimulation(layout().revision))
		expect(assembly:SimulationControl("Pause"))
		local status = expect(assembly:SimulationControl("Reset"))
		assert(status.paused and status.supports >= 1 and status.released == 0)
		expect(assembly:SimulationControl("Resume"))
		expect(assembly:TestImpulse(mover, "Push", "Motion", 100))
		task.wait(0.25)
		expect(assembly:SimulationControl("Reset"))
		expect(assembly:StopSimulation())
		for id, pose in pairs(before) do
			assert(layout().poses[id] == pose, "Simulation changed authored placement")
		end
	end
	-- Removing a referenced fixture removes its relationship, without creating replacement hardware.
	local stop = made[#made]
	expect(docs:DeleteComponent(stop.id, stop.revision))
	for _, record in ipairs(layout().supports) do
		assert(record.movingId ~= mover, "Deleted stop left a stale relationship")
	end
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
	"LINEAR WORKFLOW PASS: four grounded rails, physical stops, pause/reset/push/stop, saved poses, dependency cleanup"
)
