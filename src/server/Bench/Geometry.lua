--!strict
-- Shared procedural part and attachment construction.
-- Every point is specified in reference-stud coordinates, scaled by candidate/reference.
local Geometry = {}
Geometry.__index = Geometry

local Y = Vector3.new(0, 1, 0)
local X = Vector3.new(1, 0, 0)
local Z = Vector3.new(0, 0, 1)

function Geometry.new(container, origin, factor)
	return setmetatable({
		container = container,
		origin = origin,
		factor = factor,
		parts = {},
		joints = {},
		motors = {},
		ballasts = {},
		movers = {},
	}, Geometry)
end

function Geometry:at(p)
	return self.origin + p * self.factor
end

function Geometry:frame(position, direction, secondary)
	local axis = direction.Unit
	local up = secondary or (math.abs(axis:Dot(Y)) > 0.95 and Z or Y)
	local z = axis:Cross(up)
	if z.Magnitude < 0.01 then
		up = X
		z = axis:Cross(up)
	end
	z = z.Unit
	local y = z:Cross(axis).Unit
	return CFrame.fromMatrix(position, axis, y, z)
end

function Geometry:part(name, center, size, anchored, color, shape, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = anchored == true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Metal
	p.Color = color or Color3.fromRGB(120, 170, 205)
	p.Size = size * self.factor
	p.Shape = shape or Enum.PartType.Block
	p.CFrame = cf or CFrame.new(self:at(center))
	p.CustomPhysicalProperties = PhysicalProperties.new(2, 0.45, 0, 100, 100)
	p.Parent = self.container
	table.insert(self.parts, p)
	if not p.Anchored then
		table.insert(self.movers, p)
	end
	return p
end

function Geometry:beam(name, a, b, width, anchored, color)
	local v = b - a
	local direction = v.Unit
	local localX = direction:Cross(Z)
	if localX.Magnitude < 0.1 then
		localX = direction:Cross(X)
	end
	localX = localX.Unit
	local localZ = localX:Cross(direction).Unit
	local cf = CFrame.fromMatrix(self:at((a + b) / 2), localX, direction, localZ)
	return self:part(name, (a + b) / 2, Vector3.new(width, v.Magnitude, width), anchored, color, nil, cf)
end

function Geometry:attachment(part, worldPoint, axis, secondary)
	local a = Instance.new("Attachment")
	a.Name = "BenchAttachment"
	local worldCF = self:frame(self:at(worldPoint), axis or X, secondary)
	a.CFrame = part.CFrame:ToObjectSpace(worldCF)
	a.Parent = part
	return a
end

function Geometry:joint(className, part0, part1, position, axis, properties, axis1, secondary)
	local a0 = self:attachment(part0, position, axis, secondary)
	local a1 = self:attachment(part1, position, axis1 or axis, secondary)
	local c = Instance.new(className)
	c.Name = className
	c.Attachment0 = a0
	c.Attachment1 = a1
	for key, value in pairs(properties or {}) do
		c[key] = value
	end
	c.Parent = self.container
	table.insert(self.joints, c)
	if c:IsA("HingeConstraint") and c.ActuatorType == Enum.ActuatorType.Motor then
		table.insert(self.motors, { instance = c, kind = "angular" })
	elseif c:IsA("PrismaticConstraint") and c.ActuatorType == Enum.ActuatorType.Motor then
		table.insert(self.motors, { instance = c, kind = "linear" })
	elseif c:IsA("CylindricalConstraint") then
		if c.AngularActuatorType == Enum.ActuatorType.Motor then
			table.insert(self.motors, { instance = c, kind = "cylAngular" })
		end
		if c.ActuatorType == Enum.ActuatorType.Motor then
			table.insert(self.motors, { instance = c, kind = "linear" })
		end
	end
	return c
end

function Geometry:weld(a, b)
	local c = Instance.new("WeldConstraint")
	c.Part0 = a
	c.Part1 = b
	c.Parent = self.container
	return c
end

function Geometry:ballast(body, offset, density)
	local p = self:part("AdditionalLoad", Vector3.zero, Vector3.new(1, 1, 1), false,
		Color3.fromRGB(212, 153, 69), nil, body.CFrame * CFrame.new(offset * self.factor))
	p.CustomPhysicalProperties = PhysicalProperties.new(density or 12, 0.4, 0, 100, 100)
	p.Massless = true
	self:weld(body, p)
	table.insert(self.ballasts, p)
	return p
end

function Geometry:setLoad(enabled)
	for _, body in ipairs(self.ballasts) do
		body.Massless = not enabled
	end
end

function Geometry:finish()
	-- Deterministic fixture preflight: bad attachments must fail the build before
	-- their errors contaminate the physics/scale comparison.
	for _, c in ipairs(self.joints) do
		local a, b = c.Attachment0, c.Attachment1
		assert(a and b and a.Parent and b.Parent, "Unconnected " .. c.ClassName)
		if not (c:IsA("RodConstraint") or c:IsA("RopeConstraint") or c:IsA("SpringConstraint")) then
			local gap = (a.WorldPosition - b.WorldPosition).Magnitude
			assert(gap < 0.001, string.format("%s attachments start %.5f studs apart", c.ClassName, gap))
		end
		if c:IsA("HingeConstraint") or c:IsA("PrismaticConstraint") then
			assert(math.abs(a.WorldAxis:Dot(b.WorldAxis)) > 0.999,
				c.ClassName .. " axes are misaligned")
		elseif c:IsA("UniversalConstraint") then
			assert(math.abs(a.WorldAxis:Dot(b.WorldAxis)) < 0.001,
				"UniversalConstraint axes must be perpendicular")
		end
	end
	-- Server-owned assemblies avoid ownership changes between benchmark samples.
	for _, body in ipairs(self.movers) do
		if body.Parent and not body.Massless then
			pcall(function()
				body:SetNetworkOwner(nil)
			end)
		end
	end
	return self
end

return Geometry
