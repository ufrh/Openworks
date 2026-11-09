--!strict
-- CLIENT Studio Play Command Bar. Real manufacturing/CSG validation and
-- geometry-driven pivot preview/finalize. Test objects are cleaned up.
local RS = game:GetService("ReplicatedStorage")
local FORGE = require(RS:WaitForChild("FORGE"))
local documents = assert(FORGE:GetService("OpenWorksDocuments"))
local assembly = assert(FORGE:GetService("OpenWorksAssembly"))
local made = {}

local function expect(accepted: boolean, result: any)
	assert(accepted, tostring(result))
	return result
end
local function layout(): any
	return expect(assembly:GetLayout())
end
local function newBlock(name: string, size: Vector3)
	local result = expect(documents:CreateBlock(
		name, Vector3.new(70, 4, 0),
		Vector3.new(-0.5, 200, -0.5),
		Vector3.new(1, 1000 / 280, 1), size
	))
	table.insert(made, result.id)
	return result
end

local worked, outcome = xpcall(function()
	local first = newBlock("PIVOT_TEST_FIRST_LINK", Vector3.new(0.6, 0.2, 0.6))
	local second = newBlock("PIVOT_TEST_SECOND_LINK", Vector3.new(0.6, 0.2, 0.6))
	for _, id in ipairs({first.id, second.id}) do
		local current = expect(documents:GetSnapshot(id))
		current = expect(documents:ApplyOperation(id, current.revision, "DrillFace", {
			origin = Vector3.new(0, 0.1, 0),
			normal = Vector3.yAxis,
			diameter = 0.11, depth = 0.2, through = true,
		}))
	end
	local pin = expect(documents:CreateCylinder(
		"PIVOT_TEST_PIN", Vector3.new(72, 4, 0),
		Vector3.new(-0.5, 200, -0.5),
		Vector3.new(1, 1000 / 280, 1), 0.1, 0.7
	))
	table.insert(made, pin.id)
	local capA = newBlock("PIVOT_TEST_CAP_A", Vector3.new(0.2, 0.08, 0.2))
	local capB = newBlock("PIVOT_TEST_CAP_B", Vector3.new(0.2, 0.08, 0.2))
	local center = Vector3.new(120, 205, 28)
	local rev = expect(documents:GetSnapshot(first.id)).revision
	expect(assembly:SetPose(first.id, rev, layout().revision, CFrame.new(center)))
	expect(assembly:SetGrounded(first.id, layout().revision, true))
	local before = layout()
	local approved, proposed = assembly:PreviewPivotPlacement(
		first.id, "hole:1", second.id, "hole:1",
		pin.id, capA.id, capB.id, 56, 25, before.revision
	)
	assert(approved, "Pivot preview failed: " .. tostring(proposed))
	assert(typeof(proposed.poses[tostring(second.id)]) == "CFrame")
	assert(layout().revision == before.revision,
		"Pivot preview must not change authoritative pose revisions")
	for _, id in ipairs({second.id, pin.id, capA.id, capB.id}) do
		assert(layout().poses[tostring(id)] == before.poses[tostring(id)],
			"Pivot preview altered component " .. tostring(id))
	end
	local done, result = assembly:FinalizePivotPlacement(
		first.id, "hole:1", second.id, "hole:1",
		pin.id, capA.id, capB.id, 56, 25, before.revision
	)
	assert(done, "Pivot finalization rejected: " .. tostring(result))
	local accepted = layout()
	assert(accepted.revision == before.revision + 1,
		"Pivot installation must commit exactly one assembly revision")
	local found = false
	for _, item in ipairs(accepted.supports) do
		if item.model == "RetainedPivotV1" and item.pinId == pin.id
			and item.movingId == second.id and item.bodyId == first.id then
			found = true
		end
	end
	assert(found, "Pivot relationship missing after finalize")
	local duplicate = assembly:FinalizePivotPlacement(
		first.id, "hole:1", second.id, "hole:1",
		pin.id, capA.id, capB.id, 56, 25, accepted.revision
	)
	assert(not duplicate, "Duplicate pivot hardware incorrectly accepted")
	local valid, report = assembly:ValidateAssembly(accepted.revision)
	assert(valid and report.valid,
		"Full assembly validation failed: " .. tostring(report and report.message))
	expect(assembly:StartSimulation(accepted.revision))
	local foundDrive = false
	for _, target in ipairs(expect(assembly:ListDriveTargets())) do
		if target.kind == "Revolute" and target.movingId == second.id then
			foundDrive = true
		end
	end
	assert(foundDrive, "Manufactured pivot should expose a rotary bench drive")
	expect(assembly:StopSimulation())
	for id, pose in pairs(accepted.poses) do
		assert(layout().poses[id] == pose, "Simulation changed saved assembly pose")
	end
	return "real CSG pivot fit, atomic finalization, duplicate fastener rejection, motor-capable joint"
end, debug.traceback)

assembly:StopSimulation()
for i = #made, 1, -1 do
	local id = made[i]
	local ok, current = documents:GetSnapshot(id)
	if ok then pcall(function() documents:DeleteComponent(id, current.revision) end) end
end
assert(worked, outcome)
print("PIVOT INSTALLATION PASS:", outcome)
