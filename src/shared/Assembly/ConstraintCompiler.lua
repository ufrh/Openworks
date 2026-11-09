--!strict
local Compiler = {}
function Compiler.compileResolved(
	relation: any,
	parts: any,
	parent: Instance
): ({ Instance }?, string?)
	if relation.kind ~= "Cylindrical" and relation.kind ~= "Prismatic" then
		return nil, "No mechanically supported compiler for this relationship"
	end
	local a, b = parts[relation.bodyId], parts[relation.movingId or relation.shaftId]
	if not a or not b then
		return nil, "Missing simulation body"
	end
	local axis = relation.direction
	local y = axis:Cross(if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local frame = CFrame.fromMatrix(relation.point, axis, y, axis:Cross(y))
	local attA, attB = Instance.new("Attachment"), Instance.new("Attachment")
	attA.Name = "OW_BoreSupport"
	attB.Name = "OW_ShaftSupport"
	attA.CFrame = a.CFrame:ToObjectSpace(frame)
	attB.CFrame = b.CFrame:ToObjectSpace(frame)
	attA.Parent = a
	attB.Parent = b
	local constraint = Instance.new(
		if relation.kind == "Prismatic" then "PrismaticConstraint" else "CylindricalConstraint"
	)
	constraint.Name = "OW_" .. relation.model
	constraint.Attachment0 = attA
	constraint.Attachment1 = attB
	constraint.ActuatorType = Enum.ActuatorType.None
	constraint.LimitsEnabled = relation.limits ~= nil
	if relation.limits then
		constraint.LowerLimit = relation.limits.min
		constraint.UpperLimit = relation.limits.max
	end
	if constraint:IsA("CylindricalConstraint") then
		constraint.InclinationAngle = 0
		constraint.AngularLimitsEnabled = false
		constraint.AngularActuatorType = Enum.ActuatorType.None
	end
	constraint.Parent = parent
	return { constraint, attA, attB }, nil
end
function Compiler.compile(
	_record: any,
	_parts: any,
	_components: any,
	_features: any,
	_parent: Instance
): ({ Instance }?, string?)
	return nil, "Legacy joint compilation retired; resolve manufactured support first"
end
function Compiler.destroy(objects: { Instance }?)
	for _, obj in ipairs(objects or {}) do
		obj:Destroy()
	end
end
return Compiler
