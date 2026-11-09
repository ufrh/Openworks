--!strict
-- A temporary external test-bench drive. It is not manufactured hardware.
-- Actuation never changes or invents any mechanical relationship.
local BenchDrive = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function BenchDrive.validate(relation: any, speed: any, effort: any): (boolean, string?)
	if not relation or not (relation.kind == "Cylindrical"
		or relation.kind == "Prismatic" or relation.kind == "Revolute") then
		return false, "Select a supported rotational or linear joint"
	end
	if not finite(speed) or not finite(effort) or effort < 0 or effort > 50000 then
		return false, "Drive effort must be between 0 and 50,000"
	end
	if relation.kind == "Prismatic" and math.abs(speed) > 4 then
		return false, "Linear drive speed cannot exceed 1,120 mm/s"
	end
	if relation.kind ~= "Prismatic" and math.abs(speed) > 20 then
		return false, "Rotary drive speed cannot exceed 20 rad/s"
	end
	return true, nil
end

function BenchDrive.apply(objects: { Instance }, relation: any, speed: number, effort: number)
	local enabled = effort > 0 and speed ~= 0
	for _, obj in ipairs(objects) do
		if relation.kind == "Prismatic" and obj:IsA("PrismaticConstraint") then
			obj.ActuatorType = if enabled then Enum.ActuatorType.Motor else Enum.ActuatorType.None
			obj.Velocity = if enabled then speed else 0
			obj.MotorMaxForce = if enabled then effort else 0
			obj.MotorMaxAcceleration = 100
		elseif relation.kind == "Cylindrical" and obj:IsA("CylindricalConstraint") then
			obj.AngularActuatorType = if enabled then Enum.ActuatorType.Motor else Enum.ActuatorType.None
			obj.AngularVelocity = if enabled then speed else 0
			obj.MotorMaxTorque = if enabled then effort else 0
			obj.MotorMaxAngularAcceleration = 100
		elseif relation.kind == "Revolute" and obj:IsA("HingeConstraint") then
			obj.ActuatorType = if enabled then Enum.ActuatorType.Motor else Enum.ActuatorType.None
			obj.AngularVelocity = if enabled then speed else 0
			obj.MotorMaxTorque = if enabled then effort else 0
			obj.MotorMaxAcceleration = 100
		end
	end
end

return BenchDrive
