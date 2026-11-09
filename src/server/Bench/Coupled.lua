--!strict
-- Coupled mechanical fixtures (13-17), including actual closed-loop linkages.
local M = {}
local V = Vector3.new
local X, Y, Z = V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)
local BLUE = Color3.fromRGB(81, 157, 206)
local GOLD = Color3.fromRGB(239, 192, 87)
local GREEN = Color3.fromRGB(85, 197, 161)
local GREY = Color3.fromRGB(112, 122, 136)

local function support(g, pos, size)
	return g:part("Stationary bearing / guide", pos, size or V(1.5, 1.5, 1.5), true, GREY)
end

local function motor(g, base, crank, at, axis)
	return g:joint("HingeConstraint", base, crank, at, axis, {
		ActuatorType = Enum.ActuatorType.Motor,
		AngularVelocity = 0,
		MotorMaxTorque = 24000 * g.factor ^ 5,
		MotorMaxAcceleration = 250,
	})
end

local function hinge(g, a, b, pos, axis)
	return g:joint("HingeConstraint", a, b, pos, axis)
end

local function circleIntersection(a, r0, b, r1)
	local v = b - a
	local dist = v.Magnitude
	assert(dist < r0 + r1 and dist > math.abs(r0 - r1), "Invalid four-bar configuration")
	local forward = v / dist
	local along = (r0 * r0 - r1 * r1 + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(0, r0 * r0 - along * along))
	local side = V(-forward.Y, forward.X, 0)
	local c1 = a + forward * along + side * h
	local c2 = a + forward * along - side * h
	return if c1.Y >= c2.Y then c1 else c2
end

local function makeSliderCrank(g, pivot, angleDeg, lane, commonCrank)
	local angle = math.rad(angleDeg)
	local r, rodLength = 2, 6
	local tip = pivot + V(r * math.cos(angle), r * math.sin(angle), 0)
	local yDiff = tip.Y - pivot.Y
	local sliderPos = V(tip.X + math.sqrt(rodLength ^ 2 - yDiff ^ 2), pivot.Y, lane)
	local crank
	if commonCrank then
		crank = g:beam("Crank on common shaft", pivot, tip, 0.7, false, GOLD)
		g:weld(commonCrank, crank)
	else
		local base = support(g, pivot)
		crank = g:beam("Motor crank", pivot, tip, 0.7, false, GOLD)
		motor(g, base, crank, pivot, Z)
	end
	local rod = g:beam("Connecting rod", tip, sliderPos, 0.55, false, BLUE)
	local guide = support(g, sliderPos, V(9, 0.7, 1.3))
	local slide = g:part("Linear piston", sliderPos, V(1.5, 1.2, 1.2), false, GREEN)
	g:joint("PrismaticConstraint", guide, slide, sliderPos, X, {
		LimitsEnabled = true, LowerLimit = -5 * g.factor, UpperLimit = 5 * g.factor,
	})
	hinge(g, crank, rod, tip, Z)
	hinge(g, rod, slide, sliderPos, Z)
	g:ballast(slide, V(0.7, 0.3, 0))
	return slide
end

function M.build(index, g)
	if index == 13 then
		local fixedA, fixedB = V(-3, 5, 0), V(3, 5, 0)
		local crankTip = fixedA + V(math.sqrt(2), math.sqrt(2), 0)
		local rockerTip = circleIntersection(crankTip, 5, fixedB, 4)
		local baseA, baseB = support(g, fixedA), support(g, fixedB)
		local crank = g:beam("Input crank", fixedA, crankTip, 0.65, false, GOLD)
		local rocker = g:beam("Output rocker", fixedB, rockerTip, 0.65, false, GREEN)
		local coupler = g:beam("Coupler", crankTip, rockerTip, 0.55, false, BLUE)
		motor(g, baseA, crank, fixedA, Z)
		hinge(g, crank, coupler, crankTip, Z)
		hinge(g, coupler, rocker, rockerTip, Z)
		hinge(g, baseB, rocker, fixedB, Z)
		g:ballast(rocker, V(0.6, 0.4, 0))
	elseif index == 14 then
		makeSliderCrank(g, V(-4, 5, 0), 45, 0, nil)
	elseif index == 15 then
		local framePos = V(0, 8, 0)
		local frame = support(g, framePos, V(5, 1, 3))
		local carrierPos = V(0, 4.5, 0)
		local carrier = g:part("Moving wheel carrier", carrierPos, V(2, 1.2, 1.5), false, GREEN)
		g:joint("PrismaticConstraint", frame, carrier, carrierPos, Y, {
			LimitsEnabled = true, LowerLimit = -2 * g.factor, UpperLimit = 2 * g.factor,
		})
		local a0 = g:attachment(frame, framePos, Y)
		local a1 = g:attachment(carrier, carrierPos, Y)
		local spring = Instance.new("SpringConstraint")
		spring.Attachment0, spring.Attachment1 = a0, a1
		spring.FreeLength = 3.5 * g.factor
		spring.Stiffness = 550 * g.factor ^ 2
		spring.Damping = 45 * g.factor ^ 2
		spring.MaxForce = 55000 * g.factor ^ 3
		spring.LimitsEnabled = true
		spring.MinLength = 1.2 * g.factor
		spring.MaxLength = 6 * g.factor
		spring.Parent = g.container
		table.insert(g.joints, spring)
		local wheelPos = V(0, 3, 0)
		local cf = CFrame.new(g:at(wheelPos)) * CFrame.Angles(math.pi / 2, 0, 0)
		local wheel = g:part("Suspended wheel", wheelPos, V(2, 0.7, 2), false, GOLD,
			Enum.PartType.Cylinder, cf)
		motor(g, carrier, wheel, wheelPos, Z)
		local floor = support(g, V(0, 1.2, 0), V(9, 0.4, 9))
		floor.Name = "Impact floor"
		floor.CanCollide = true
		wheel.CanCollide = true
		g:ballast(carrier, V(1, 0.6, 0))
	elseif index == 16 then
		local left, right = V(-4.5, 5, 0), V(4.5, 5, 0)
		local base0, base1 = support(g, left), support(g, right)
		local shaft = g:part("Two-bearing shaft", V(0, 5, 0), V(10.5, 0.65, 0.65), false, BLUE)
		motor(g, base0, shaft, left, X)
		hinge(g, base1, shaft, right, X)
		g:ballast(shaft, V(0, 1.1, 0))
	elseif index == 17 then
		-- Three crank-slider loops share ONE rigid drive shaft via welds.
		-- A constraint failure in any lane can disturb the entire mechanism.
		local a, b = V(0, 5, -4.5), V(0, 5, 4.5)
		local baseA, baseB = support(g, a), support(g, b)
		local shaft = g:beam("Shared triple crankshaft", a, b, 0.65, false, BLUE)
		motor(g, baseA, shaft, a, Z)
		hinge(g, baseB, shaft, b, Z)
		for i = 1, 3 do
			local z = (i - 2) * 3
			makeSliderCrank(g, V(0, 5, z), 25 + (i - 1) * 120, z, shaft)
		end
		g:ballast(shaft, V(0, 0, 0.5))
	end
	return g:finish()
end

return M
