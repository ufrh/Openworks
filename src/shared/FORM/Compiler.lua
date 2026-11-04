--!strict
-- Native material primitive geometry. All subtractive manufacturing now lives
-- in Fabricator/Cutters rather than in special pre-drilled templates.
local Compiler = {}
local CYLINDER_FRAME = CFrame.Angles(0, 0, math.pi / 2)

function Compiler.geometryKey(node): string
	return table.concat({
		node.kind,
		string.format("%.4f", node.size.X),
		string.format("%.4f", node.size.Y),
		string.format("%.4f", node.size.Z),
	}, "|")
end

function Compiler.pose(node): CFrame
	local r = node.rotation
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(r.X), math.rad(r.Y), math.rad(r.Z)
	)
end

function Compiler.partSize(node): Vector3
	if node.kind == "Cylinder" then
		return Vector3.new(node.size.Y, node.size.X, node.size.X)
	end
	return node.size
end

function Compiler.nativePart(node): Part
	local part = Instance.new("Part")
	part.Shape = if node.kind == "Cylinder"
		then Enum.PartType.Cylinder else Enum.PartType.Block
	part.Size = Compiler.partSize(node)
	part.CFrame = if node.kind == "Cylinder" then CYLINDER_FRAME else CFrame.new()
	part.Anchored = true
	return part
end

return Compiler
