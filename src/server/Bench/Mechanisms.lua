--!strict
-- Individual mechanical test fixtures (01-12).
local M = {}
local V = Vector3.new
local X, Y, Z = V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)
local BLUE = Color3.fromRGB(81, 157, 206)
local YELLOW = Color3.fromRGB(239, 192, 87)
local GREEN = Color3.fromRGB(85, 197, 161)
local GREY = Color3.fromRGB(112, 122, 136)

local function block(g, name, center, size, anchored, color)
	return g:part(name, center, size, anchored, color or BLUE)
end

local function support(g, center, size)
	return block(g, "Fixed support", center, size, true, GREY)
end

local function jointAt(g, kind, part0, part1, point0, point1, props)
	local a0 = g:attachment(part0, point0, X)
	local a1 = g:attachment(part1, point1, X)
	local c = Instance.new(kind)
	c.Name = kind
	c.Attachment0, c.Attachment1 = a0, a1
	for k, v in pairs(props or {}) do
		c[k] = v
	end
	c.Parent = g.container
	table.insert(g.joints, c)
	return c
end

local function drive(g, a, b, pos, axis)
	return g:joint("HingeConstraint", a, b, pos, axis, {
		ActuatorType = Enum.ActuatorType.Motor,
		AngularVelocity = 0,
		MotorMaxTorque = 20000 * g.factor ^ 5,
		MotorMaxAcceleration = 250,
	})
end

local function linearMotor(g, a, b, pos, axis, limit)
	local s = g.factor
	return g:joint("PrismaticConstraint", a, b, pos, axis, {
		ActuatorType = Enum.ActuatorType.Motor,
		Velocity = 0,
		MotorMaxForce = 12000 * s ^ 3,
		MotorMaxAcceleration = 250 * s,
		LimitsEnabled = true,
		LowerLimit = -limit * s,
		UpperLimit = limit * s,
	})
end

function M.build(index, g)
	local s = g.factor
	if index == 1 then
		local pivot = V(0, 8, 0)
		local endPoint = pivot + V(3, -5.196, 0)
		local frame = support(g, pivot, V(2, 1, 2))
		local arm = g:beam("Pendulum", pivot, endPoint, 0.65, false, BLUE)
		g:joint("HingeConstraint", frame, arm, pivot, Z, {
			LimitsEnabled = true, LowerAngle = -90, UpperAngle = 90,
		})
		g:ballast(arm, V(0, -1.7, 0))
	elseif index == 2 then
		local center = V(0, 5, 0)
		local frame = support(g, V(-3, 5, 0), V(1.6, 2.2, 2.2))
		local cf = CFrame.new(g:at(center)) * CFrame.Angles(0, 0, math.pi / 2)
		local wheel = g:part("Flywheel", center, V(4, 0.8, 4), false, YELLOW,
			Enum.PartType.Cylinder, cf)
		local shaft = g:part("Shaft", center, V(6, 0.5, 0.5), false, BLUE)
		g:weld(wheel, shaft)
		drive(g, frame, shaft, V(-3, 5, 0), X)
		g:ballast(wheel, V(0, 0, 1.4))
	elseif index == 3 then
		local frame = support(g, V(0, 3, 0), V(11, 0.75, 2))
		local carriage = block(g, "Carriage", V(0, 4, 0), V(2.5, 1, 1.5), false, GREEN)
		linearMotor(g, frame, carriage, V(0, 4, 0), X, 3)
		g:ballast(carriage, V(0.8, 1, 0))
	elseif index == 4 then
		local frame = support(g, V(0, 5, 0), V(2, 2, 2))
		local shaft = block(g, "Telescoping shaft", V(0, 5, 0), V(7, 0.6, 0.6), false, BLUE)
		g:joint("CylindricalConstraint", frame, shaft, V(0, 5, 0), X, {
			ActuatorType = Enum.ActuatorType.Motor,
			Velocity = 0,
			MotorMaxForce = 10000 * s ^ 3,
			MotorMaxAcceleration = 200 * s,
			LimitsEnabled = true,
			LowerLimit = -2 * s,
			UpperLimit = 2 * s,
			AngularActuatorType = Enum.ActuatorType.Motor,
			AngularVelocity = 0,
			MotorMaxTorque = 20000 * s ^ 5,
			MotorMaxAngularAcceleration = 250,
		})
		g:ballast(shaft, V(2.5, 0.6, 0))
	elseif index == 5 then
		local pivot = V(0, 8, 0)
		local frame = support(g, pivot, V(2, 1, 2))
		local arm = g:beam("Spherical joint arm", pivot, V(2.2, 3, 1.2), 0.65, false, BLUE)
		g:joint("BallSocketConstraint", frame, arm, pivot, Z, {
			LimitsEnabled = true, UpperAngle = 50,
			TwistLimitsEnabled = true, TwistLowerAngle = -35, TwistUpperAngle = 35,
		})
		g:ballast(arm, V(0, -1.2, 0.5))
	elseif index == 6 then
		local top = V(0, 8, 0)
		local platePos = V(0, 4, 0)
		local frame = support(g, top, V(4, 1, 4))
		local plate = block(g, "Spring platform", platePos, V(3, 0.7, 3), false, GREEN)
		g:joint("PrismaticConstraint", frame, plate, platePos, Y, {
			LimitsEnabled = true, LowerLimit = -2 * s, UpperLimit = 2 * s,
		})
		jointAt(g, "SpringConstraint", frame, plate, top, platePos, {
			FreeLength = 4 * s,
			Stiffness = 300 * s ^ 2,
			Damping = 28 * s ^ 2,
			MaxForce = 40000 * s ^ 3,
			MinLength = 1.2 * s,
			MaxLength = 6 * s,
			LimitsEnabled = true,
		})
		g:ballast(plate, V(1, -0.8, 0))
	elseif index == 7 then
		local pivot = V(0, 7, 0)
		local frame = support(g, pivot, V(2, 1, 2))
		local lever = g:beam("Spring-return lever", pivot, V(3, 3, 0), 0.65, false, BLUE)
		g:joint("HingeConstraint", frame, lever, pivot, Z, {
			LimitsEnabled = true, LowerAngle = -100, UpperAngle = 100,
		})
		g:joint("TorsionSpringConstraint", frame, lever, pivot, Z, {
			Stiffness = 320 * s ^ 5, Damping = 35 * s ^ 5,
			MaxTorque = 18000 * s ^ 5, LimitsEnabled = true, MaxAngle = 100,
		})
		g:ballast(lever, V(1.2, -0.7, 0))
	elseif index == 8 then
		local top = V(0, 9, 0)
		local cargoPos = V(0, 4, 0)
		local frame = support(g, top, V(3, 1, 3))
		local cargo = block(g, "Hanging cargo", cargoPos, V(2, 2, 2), false, YELLOW)
		jointAt(g, "RopeConstraint", frame, cargo, top, cargoPos, {
			Length = 6 * s, WinchEnabled = false,
			WinchTarget = 5 * s, WinchSpeed = 3 * s,
			WinchForce = 20000 * s ^ 3, WinchResponsiveness = 30,
			Thickness = 0.1 * s,
		})
		g:ballast(cargo, V(0.6, 0, 0))
	elseif index == 9 then
		local top = V(0, 9, 0)
		local middle = V(2, 5, 0)
		local last = V(4, 2, 0)
		local frame = support(g, top, V(2, 1, 2))
		local a = block(g, "First rod end", middle, V(1, 1, 1), false, GREEN)
		local b = block(g, "Second rod end", last, V(1.5, 1.5, 1.5), false, YELLOW)
		jointAt(g, "RodConstraint", frame, a, top, middle, { Length = (top - middle).Magnitude * s })
		jointAt(g, "RodConstraint", a, b, middle, last, { Length = (middle - last).Magnitude * s })
		g:ballast(b, V(0.8, 0, 0))
	elseif index == 10 then
		local previous = support(g, V(-4, 5, 0), V(1, 1, 1))
		for i = 1, 6 do
			local center = V(-4 + i, 5, 0)
			local piece = block(g, "Cantilever "..i, center, V(1, 1, 1), false, BLUE)
			g:joint("RigidConstraint", previous, piece, V(-4 + i - 0.5, 5, 0), X)
			previous = piece
		end
		g:ballast(previous, V(0.65, -0.65, 0))
	elseif index == 11 then
		local root = V(-4, 5, 0)
		local middle = V(0, 5, 0)
		local far = V(3.864, 6.035, 0)
		local frame = support(g, root, V(1, 2, 2))
		local finalSupport = support(g, far, V(1.5, 1.5, 1.5))
		local input = g:beam("Driven input shaft", root, middle, 0.7, false, BLUE)
		local output = g:beam("Angled output shaft", middle, far, 0.7, false, GREEN)
		drive(g, frame, input, root, X)
		g:joint("UniversalConstraint", input, output, middle, X, {
			LimitsEnabled = false,
		}, Y)
		g:joint("BallSocketConstraint", finalSupport, output, far, X)
		g:ballast(output, V(0.4, -0.8, 0))
	elseif index == 12 then
		local origin = V(0, 4, 0)
		local frame = support(g, V(0, 2, 0), V(9, 0.5, 9))
		local plate = block(g, "Planar free plate", origin, V(3.5, 0.5, 3.5), false, GREEN)
		g:joint("PlaneConstraint", frame, plate, origin, Y)
		g:ballast(plate, V(1.2, 0.5, 0))
	end
	return g:finish()
end

return M
