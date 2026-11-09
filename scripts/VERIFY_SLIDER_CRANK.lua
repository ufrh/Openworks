--!strict
-- CLIENT Studio Command Bar, during Play.
-- This creates 19 real manufactured components in the active workshop.
-- It does NOT delete them on success: inspect and reuse the mechanism.
-- Studio must have GeometryService / EditableMesh manufacturing available.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local FORGE = require(RS:WaitForChild("FORGE"))
local client = Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local Preset = require(client.Systems.Assembly.SliderCrankPreset)
local documents = assert(FORGE:GetService("OpenWorksDocuments"))
local assembly = assert(FORGE:GetService("OpenWorksAssembly"))

local priorOk, priorLayout = assembly:GetLayout()
assert(priorOk, tostring(priorLayout))
local previousCount = 0
for _ in pairs(priorLayout.poses) do previousCount += 1 end

local generated, crankId = Preset.build(documents, assembly)
assert(generated, "Slider-crank manufacturing failed: " .. tostring(crankId))

local ok, layout = assembly:GetLayout()
assert(ok, tostring(layout))
local componentCount = 0
for _ in pairs(layout.poses) do componentCount += 1 end
assert(componentCount - previousCount == 19,
	"Expected 19 source-authored components; created " .. tostring(componentCount - previousCount))
local pivots = 0
local guides = 0
for _, record in ipairs(layout.supports) do
	if record.model == "RetainedPivotV1" then
		pivots += 1
		assert(type(record.movingFeatureId) == "string")
		assert(record.pinId and type(record.stopIds) == "table" and #record.stopIds == 2)
	elseif record.model == "LimitedGuideV1" and record.travelAxis == "X" then
		guides += 1
	end
end
assert(pivots >= 3 and guides >= 1,
	"Slider-crank requires three retained pivots and one X-axis sliding guide")

local checked, report = assembly:ValidateAssembly(layout.revision)
assert(checked, "Assembly inspection request failed: " .. tostring(report))
assert(report.valid, "Manufactured geometry/relationships invalid: " .. tostring(report.message))
for _, item in ipairs(report.relationships) do
	assert(item.valid, "Relationship #" .. item.index .. ": " .. tostring(item.message))
end

local saved = table.clone(layout.poses)
local started, center = assembly:StartSimulation(layout.revision)
assert(started, "Physics start failed: " .. tostring(center))
local success, result = xpcall(function()
	local listed, targets = assembly:ListDriveTargets()
	assert(listed, tostring(targets))
	local driveIndex = nil
	for _, target in ipairs(targets) do
		if target.kind == "Revolute" and target.movingId == crankId then
			driveIndex = target.index
			break
		end
	end
	assert(driveIndex, "No motor-capable crank pivot found")
	local driven, message = assembly:SetBenchDrive(driveIndex, 2 * math.pi / 6, 5000)
	assert(driven, "Crank motor rejected: " .. tostring(message))
	task.wait(0.5)
	local statusOK, status = assembly:SimulationStatus()
	assert(statusOK and not status.paused, "Simulation failed while actuating")
	local stoppedDrive, stopMessage = assembly:SetBenchDrive(driveIndex, 0, 0)
	assert(stoppedDrive, tostring(stopMessage))
	local reset, resetState = assembly:SimulationControl("Reset")
	assert(reset, "Simulator reset failed: " .. tostring(resetState))
	local freshOK, freshStatus = assembly:SimulationStatus()
	assert(freshOK and freshStatus.released == 0,
		"Reset did not restore retained mechanical joints")
	return driveIndex
end, debug.traceback)

local stopped, problem = assembly:StopSimulation()
assert(stopped, "Cannot stop simulation: " .. tostring(problem))
assert(success, result)

local afterOK, after = assembly:GetLayout()
assert(afterOK, tostring(after))
for id, pose in pairs(saved) do
	assert(after.poses[id] == pose, "Simulation modified the CAD pose of part " .. id)
end
print(
	"SLIDER CRANK VERIFIED:",
	componentCount - previousCount,
	"manufactured parts;",
	pivots,
	"pin pivots;",
	guides,
	"prismatic guide; crank drive joint",
	result
)
