--!strict
-- GeometryService compiler: parametric input -> ephemeral CSG result.
-- Source nodes are never destroyed, flattened, or modified by compilation.
local GeometryService = game:GetService("GeometryService")

local Compiler = {}
local OPTIONS = { SplitApart = false }

local function pose(node): CFrame
	local r = node.rotation
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(r.X), math.rad(r.Y), math.rad(r.Z)
	)
end

local function makeBlock(size: Vector3, frame: CFrame): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.CFrame = frame
	part.Anchored = true
	return part
end

local function makeCylinder(diameter: number, height: number, frame: CFrame): Part
	-- Roblox cylinders are X-axis aligned; FORM cylinders are Y-axis aligned.
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = frame * CFrame.Angles(0, 0, math.pi / 2)
	part.Anchored = true
	return part
end

local function single(result, name: string): BasePart
	if #result ~= 1 then
		for _, item in ipairs(result) do item:Destroy() end
		error(name .. " must produce exactly one solid (SplitApart=false)", 0)
	end
	return result[1]
end

local function boolean(operation: string, main: BasePart, other: BasePart): BasePart
	local ok, result = pcall(function()
		if operation == "Subtract" then
			return GeometryService:SubtractAsync(main, { other }, OPTIONS)
		end
		return GeometryService:UnionAsync(main, { other }, OPTIONS)
	end)
	-- These parts are unparented temporary inputs; CSG does not consume them.
	main:Destroy()
	other:Destroy()
	if not ok then error(tostring(result), 0) end
	return single(result, operation)
end

local function build(node): BasePart
	local frame = pose(node)
	if node.kind == "Block" then
		return makeBlock(node.size, frame)
	elseif node.kind == "Cylinder" then
		return makeCylinder(node.size.X, node.size.Y, frame)
	elseif node.kind == "Tube" then
		local outer = makeCylinder(node.size.X, node.size.Y, frame)
		local innerDiameter = node.size.X - 2 * node.wall
		if innerDiameter < 0.04999 then return outer end
		local cutter = makeCylinder(innerDiameter, node.size.Y + 0.4, frame)
		return boolean("Subtract", outer, cutter)
	elseif node.kind == "HoleBlock" then
		local outer = makeBlock(node.size, frame)
		if math.min(node.size.X, node.size.Z) < node.bore + 0.09999 then
			return outer
		end
		local cutter = makeCylinder(node.bore, node.size.Y + 0.4, frame)
		return boolean("Subtract", outer, cutter)
	end
	error("Unknown primitive: " .. tostring(node.kind), 0)
end

function Compiler.compile(snapshot): BasePart
	local current: BasePart? = nil
	local ok, result = pcall(function()
		for index, node in ipairs(snapshot.nodes) do
			local nextSolid = build(node)
			if index == 1 then
				assert(node.operation == "Add", "First node must be additive")
				current = nextSolid
			else
				assert(current ~= nil, "Missing additive base")
				-- Subtract and union nodes retain their editable input parameters.
				current = boolean(node.operation, current :: BasePart, nextSolid)
			end
		end
		assert(current, "Empty component")
		current.Name = "CompiledSolid"
		current.Anchored = true
		current.CanCollide = false
		current.CanTouch = false
		current.CanQuery = true
		current.Material = Enum.Material.SmoothPlastic
		current.Color = Color3.fromRGB(170, 190, 196)
		if current:IsA("PartOperation") then
			current.UsePartColor = true
		end
		current.CastShadow = true
		return current
	end)
	if not ok then
		if current then current:Destroy() end
		error(tostring(result), 0)
	end
	return result
end

return Compiler
