--!strict
-- FORM uses a stud-space construction grid, not integer voxels.
local Quantize = {}

Quantize.Grid = 0.05
Quantize.Size = 1/280 -- size specs and scale controls resolve to 1 mm
Quantize.Rotation = 15
Quantize.MinSize = 0.05
Quantize.MaxSize = 128
Quantize.MaxComponentVolume = 8 -- studs cubed; build larger assemblies from separate components
Quantize.MaxPosition = 512

function Quantize.isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Quantize.snap(value: number, increment: number): number
	return math.round(value / increment) * increment
end

function Quantize.vector(value: Vector3, increment: number): Vector3
	return Vector3.new(
		Quantize.snap(value.X, increment),
		Quantize.snap(value.Y, increment),
		Quantize.snap(value.Z, increment)
	)
end

return Quantize
