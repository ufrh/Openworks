--!strict
-- Studio CLIENT Play Command Bar. Exercises the real FORGE endpoints and
-- Roblox CSG (not the host's mocked Lua/Instance math).
-- Test parts are removed afterward. Run in a clear workshop area.
local RS = game:GetService("ReplicatedStorage")
local FORGE = require(RS:WaitForChild("FORGE"))
local docs = assert(FORGE:GetService("OpenWorksDocuments"))
local assembly = assert(FORGE:GetService("OpenWorksAssembly"))

local made = {}
local function expect(ok: boolean, value: any): any
	assert(ok, tostring(value))
	return value
end
local function layout()
	return expect(assembly:GetLayout())
end
local function create(name: string, size: Vector3)
	local component = expect(docs:CreateBlock(
		name,
		Vector3.new(60, 4, 0),
		Vector3.new(-0.5, 200, -0.5),
		Vector3.new(1, 1000 / 280, 1),
		size
	))
	table.insert(made, component.id)
	return component
end
local success, result = xpcall(function()
	local housing = create("FIT_TEST_HOUSING", Vector3.new(0.6, 0.2, 0.6))
	housing = expect(docs:ApplyOperation(
		housing.id, housing.revision, "DrillFace",
		{origin = Vector3.new(0, 0.1, 0), normal = Vector3.yAxis,
			diameter = 31 / 280, depth = 0.2, through = true}
	))
	local shaft = expect(docs:CreateCylinder(
		"FIT_TEST_STEPPED_SHAFT",
		Vector3.new(62, 4, 0),
		Vector3.new(-0.5, 200, -0.5),
		Vector3.new(1, 1000 / 280, 1),
		28 / 280, 0.8
	))
	table.insert(made, shaft.id)
	shaft = expect(docs:ApplyOperation(shaft.id, shaft.revision, "AddPrimitive", {
		kind = "Cylinder",
		size = Vector3.new(56 / 280, 0.1, 56 / 280),
		position = Vector3.new(0, 0.45 - 1 / 280, 0),
		rotation = Vector3.zero,
	}))
	local disconnected = docs:ApplyOperation(shaft.id, shaft.revision, "AddPrimitive", {
		kind = "Block", size = Vector3.one * 0.1,
		position = Vector3.new(2, 2, 2), rotation = Vector3.zero,
	})
	assert(not disconnected, "Unconnected material was accepted into one component")
	local unchanged = expect(docs:GetSnapshot(shaft.id))
	assert(unchanged.revision == shaft.revision,
		"Rejected additive material unexpectedly mutated FORM history")

	local origin = Vector3.new(120, 205, 20)
	expect(assembly:SetPose(housing.id, housing.revision,
		layout().revision, CFrame.new(origin)))
	local before = layout()
	local initialShaft = before.poses[tostring(shaft.id)]
	local featureId = "hole:" .. housing.operations[1].id
	local valid, preview = assembly:PreviewBearingPlacement(
		housing.id, featureId, shaft.id, 0, before.revision
	)
	assert(valid, "Zero-offset stepped shaft should fit: " .. tostring(preview))
	assert(typeof(preview.pose) == "CFrame", "Preview must return candidate pose")
	assert(layout().revision == before.revision,
		"Preview must not modify authoritative assembly revision")
	assert(layout().poses[tostring(shaft.id)] == initialShaft,
		"Preview must not move authored shaft pose")

	local penetrating, interference = assembly:PreviewBearingPlacement(
		housing.id, featureId, shaft.id, -128, before.revision
	)
	assert(not penetrating,
		"Shoulder penetrating finished housing geometry was incorrectly accepted")
	assert(typeof(interference) == "string",
		"Rejected placement must include an actionable reason")

	local placed, finished = assembly:FinalizeBearingPlacement(
		housing.id, featureId, shaft.id, 0, before.revision
	)
	assert(placed, "Valid bearing finalization rejected: " .. tostring(finished))
	local accepted = layout()
	assert(accepted.revision == before.revision + 1,
		"Finalize must commit exactly one layout revision")
	assert(accepted.poses[tostring(shaft.id)] == preview.pose,
		"Final shaft position must match the approved preview")
	local installed = false
	for _, joint in ipairs(accepted.supports) do
		if joint.model == "BoreSupportV1" and joint.shaftId == shaft.id
			and joint.bodyId == housing.id then
			installed = true
		end
	end
	assert(installed, "Finalize should register the installed cylindrical joint")
	local again = assembly:FinalizeBearingPlacement(
		housing.id, featureId, shaft.id, 0, accepted.revision
	)
	assert(not again, "Duplicate bearing installation should be rejected")

	expect(assembly:StartSimulation(accepted.revision))
	local targets = expect(assembly:ListDriveTargets())
	local actuable = false
	for _, target in ipairs(targets) do
		if target.movingId == shaft.id and target.kind == "Cylindrical" then
			actuable = true
		end
	end
	assert(actuable, "Accepted bearing should produce a rotatable/slidable simulation joint")
	expect(assembly:StopSimulation())
	assert(layout().poses[tostring(shaft.id)] == preview.pose,
		"Stopping physics must preserve manufactured CAD placement")
	return "Bore-first preview, stepped shaft interference, disconnected material, atomic finalize, physics verified"
end, debug.traceback)

assembly:StopSimulation()
for index = #made, 1, -1 do
	local id = made[index]
	local ok, component = docs:GetSnapshot(id)
	if ok then pcall(function() docs:DeleteComponent(id, component.revision) end) end
end
assert(success, result)
print("BORE-FIRST INSTALLATION PASS:", result)
