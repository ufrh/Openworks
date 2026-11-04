--!strict
-- FORM debug grid: visual 0.1-stud spacing; editing snap remains 0.05.
-- A single non-queryable pivot allows LineHandleAdornments to render in 3D.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Quantize = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Quantize)

local GridOverlay = {}
GridOverlay.__index = GridOverlay

local STEP = 0.1 -- Visual grid only. Quantize.Grid remains the 0.05 edit increment.
local HALF_STEPS = 30 -- 6x6 studs, 61 lines per axis
local GRID_HALF = HALF_STEPS * STEP

local function createLine(parent: Instance, pivot: BasePart, axis: string, index: number)
	local amount = index * STEP
	local start: Vector3
	local finish: Vector3
	if axis == "X" then
		start = Vector3.new(-GRID_HALF, 0, amount)
		finish = Vector3.new(GRID_HALF, 0, amount)
	else
		start = Vector3.new(amount, 0, -GRID_HALF)
		finish = Vector3.new(amount, 0, GRID_HALF)
	end
	local isAxis = index == 0
	local major = index % 10 == 0
	local line = Instance.new("LineHandleAdornment")
	line.Name = if isAxis then ("Axis_" .. axis) elseif major then "MajorGrid" else "MinorGrid"
	line.Adornee = pivot
	line.CFrame = CFrame.lookAt(start, finish)
	line.Length = (finish - start).Magnitude
	line.Thickness = if isAxis then 2 elseif major then 1.4 else 0.8
	line.Color3 = if isAxis
		then (if axis == "X" then Color3.fromRGB(189, 89, 89) else Color3.fromRGB(82, 130, 196))
		elseif major then Color3.fromRGB(117, 129, 137)
		else Color3.fromRGB(97, 104, 112)
	line.Transparency = if isAxis then 0.1 elseif major then 0.45 else 0.78
	line.AlwaysOnTop = false
	line.Parent = parent
end

function GridOverlay.new(playerGui: PlayerGui)
	local anchor = Instance.new("Part")
	anchor.Name = "FORM_GridDebugAnchor"
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor.CFrame = CFrame.new()
	anchor.Parent = workspace

	local decorations = Instance.new("Folder")
	decorations.Name = "FORM_DebugGridLines"
	decorations.Parent = playerGui

	for index = -HALF_STEPS, HALF_STEPS do
		createLine(decorations, anchor, "X", index)
		createLine(decorations, anchor, "Z", index)
	end

	return setmetatable({
		anchor = anchor,
		decorations = decorations,
			}, GridOverlay)
end

-- Fixed build plane. The grid never follows the camera or selection.
function GridOverlay:update(_focus: Vector3)
	-- Reserved for the debug overlay API; intentionally immobile at 0,0,0.
end

function GridOverlay:destroy()
	self.decorations:Destroy()
	self.anchor:Destroy()
end

return GridOverlay
