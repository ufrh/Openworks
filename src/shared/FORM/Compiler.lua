--!strict
-- FORM manufactures individually editable *parametric primitives*.
-- No arbitrary additive/subtractive operations exist in the editor.
-- Only special primitive templates use GeometryService internally.
local GeometryService = game:GetService("GeometryService")

local Compiler = {}
local MIN = 0.05
local OPTIONS = { SplitApart = false }
local CYLINDER_FRAME = CFrame.Angles(0, 0, math.pi / 2)

function Compiler.requiresBoolean(node): boolean
	if node.kind == "Tube" then
		return node.size.X - 2 * node.wall >= MIN - 0.00001
	elseif node.kind == "HoleBlock" then
		return math.min(node.size.X, node.size.Z) >= node.bore + 2 * MIN - 0.00001
	end
	return false
end

function Compiler.geometryKey(node): string
	-- Positions/rotations intentionally excluded: transforming a manufactured
	-- primitive never invokes CSG.
	return table.concat({
		node.kind,
		string.format("%.4f", node.size.X),
		string.format("%.4f", node.size.Y),
		string.format("%.4f", node.size.Z),
		string.format("%.4f", node.bore),
		string.format("%.4f", node.wall),
	}, "|")
end

function Compiler.pose(node): CFrame
	local r = node.rotation
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(r.X), math.rad(r.Y), math.rad(r.Z)
	)
end

function Compiler.partSize(node): Vector3
	if node.kind == "Cylinder" or node.kind == "Tube" then
		return Vector3.new(node.size.Y, node.size.X, node.size.X)
	end
	return node.size
end

function Compiler.nativePart(node): Part
	local part = Instance.new("Part")
	part.Shape = if node.kind == "Cylinder" or node.kind == "Tube"
		then Enum.PartType.Cylinder else Enum.PartType.Block
	part.Size = Compiler.partSize(node)
	-- This frame is template-local. Store it when applying the world pose.
	part.CFrame = if node.kind == "Cylinder" or node.kind == "Tube"
		then CYLINDER_FRAME else CFrame.new()
	part.Anchored = true
	return part
end

local function cutter(diameter: number, height: number): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CYLINDER_FRAME
	part.Anchored = true
	return part
end

function Compiler.compileTemplate(node): BasePart
	if not Compiler.requiresBoolean(node) then
		return Compiler.nativePart(node)
	end

	local outer = Compiler.nativePart(node)
	local bore = if node.kind == "Tube" then node.size.X - 2 * node.wall
		else node.bore
	local drill = cutter(bore, node.size.Y + 0.4)
	local ok, result = pcall(function()
		return GeometryService:SubtractAsync(outer, { drill }, OPTIONS)
	end)
	outer:Destroy()
	drill:Destroy()

	if not ok then error(tostring(result), 0) end
	if #result ~= 1 then
		for _, p in ipairs(result) do p:Destroy() end
		error("Parametric primitive could not produce one solid", 0)
	end
	return result[1]
end

return Compiler
