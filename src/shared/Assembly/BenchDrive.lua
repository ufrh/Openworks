--!strict
-- External test-bench motor or position servo. No manufactured actuator is
-- created: the solver receives only commands for an existing accepted joint.
local BenchDrive = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function BenchDrive.validate(
	relation: any,
	speed: any,
	effort: any,
	mode: string?,
	target: number?
): (boolean, string?)
	if not relation or not (relation.kind == "Cylindrical"
		or relation.kind == "Prismatic" or relation.kind == "Revolute") then
		return false, "Select a supported revolute, cylindrical, or prismatic joint"
	end
	if not finite(speed) or not finite(effort) or effort < 0 or effort > 50000 then
		return false, "Drive effort must be between 0 and 50,000"
	end
	local kind = mode or "Motor"
	if kind ~= "Motor" and kind ~= "Servo" then
		return false, "Drive mode must be Motor or Servo"
	end
	if relation.kind == "Prismatic" and math.abs(speed) > 4 then
		return false, "Linear speed cannot exceed 1,120 mm/s"
	end
	if relation.kind ~= "Prismatic" and math.abs(speed) > 20 then
		return false, "Angular speed cannot exceed 20 rad/s"
	end
	if kind == "Servo" then
		if not finite(target) or speed <= 0 then
			return false, "Servo requires a finite target and positive speed"
		end
		if relation.kind == "Prismatic" and math.abs(target) > 4 then
			return false, "Servo position exceeds ±1,120 mm"
		elseif relation.kind ~= "Prismatic" and math.abs(target) > 360 then
			return false, "Servo angle exceeds ±360°"
		end
	end
	return true, nil
end

function BenchDrive.apply(
	objects: { Instance },
	relation: any,
	speed: number,
	effort: number,
	mode: string?,
	target: number?
)
	local servo = mode == "Servo"
	local enabled = effort > 0 and (servo or speed ~= 0)
	for _, obj in ipairs(objects) do
		if relation.kind == "Prismatic" and obj:IsA("PrismaticConstraint") then
			obj.ActuatorType = if not enabled then Enum.ActuatorType.None
				elseif servo then Enum.ActuatorType.Servo else Enum.ActuatorType.Motor
			if servo then
				obj.TargetPosition = target or 0
				obj.Speed = math.abs(speed)
				obj.ServoMaxForce = effort
			else
				obj.Velocity = if enabled then speed else 0
				obj.MotorMaxForce = if enabled then effort else 0
				obj.MotorMaxAcceleration = math.clamp(math.abs(speed) * 6, 1, 25)
			end
		elseif relation.kind == "Cylindrical" and obj:IsA("CylindricalConstraint") then
			obj.AngularActuatorType = if not enabled then Enum.ActuatorType.None
				elseif servo then Enum.ActuatorType.Servo else Enum.ActuatorType.Motor
			if servo then
				obj.TargetAngle = target or 0
				obj.AngularSpeed = math.abs(speed)
				obj.ServoMaxTorque = effort
			else
				obj.AngularVelocity = if enabled then speed else 0
				obj.MotorMaxTorque = if enabled then effort else 0
				obj.MotorMaxAngularAcceleration = math.clamp(math.abs(speed) * 6, 1, 25)
			end
		elseif relation.kind == "Revolute" and obj:IsA("HingeConstraint") then
			obj.ActuatorType = if not enabled then Enum.ActuatorType.None
				elseif servo then Enum.ActuatorType.Servo else Enum.ActuatorType.Motor
			if servo then
				obj.TargetAngle = target or 0
				obj.AngularSpeed = math.abs(speed)
				obj.ServoMaxTorque = effort
			else
				obj.AngularVelocity = if enabled then speed else 0
				obj.MotorMaxTorque = if enabled then effort else 0
				obj.MotorMaxAcceleration = 100
			end
		end
	end
end

return BenchDrive
