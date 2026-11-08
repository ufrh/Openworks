--!strict
local Compiler = {}
function Compiler.compileResolved(relation:any, parts:any, parent:Instance):({Instance}?, string?)
	if relation.kind ~= 'Cylindrical' or relation.model ~= 'BoreSupportV1' then
		return nil, 'No mechanically supported compiler for this relationship'
	end
	local a, b = parts[relation.bodyId], parts[relation.shaftId]
	if not a or not b then
		return nil, 'Missing simulation body'
	end
	local axis = relation.direction
	local y = axis:Cross(if math.abs(axis.Y)<.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local frame = CFrame.fromMatrix(relation.point, axis, y, axis:Cross(y))
	local attA, attB = Instance.new('Attachment'), Instance.new('Attachment')
	attA.Name = 'OW_BoreSupport'
	attB.Name = 'OW_ShaftSupport'
	attA.CFrame = a.CFrame:ToObjectSpace(frame)
	attB.CFrame = b.CFrame:ToObjectSpace(frame)
	attA.Parent = a
	attB.Parent = b
	local constraint = Instance.new('CylindricalConstraint')
	constraint.Name = 'OW_UnretainedBore'
	constraint.InclinationAngle = 0
	constraint.Attachment0 = attA
	constraint.Attachment1 = attB
	constraint.LimitsEnabled = false
	constraint.AngularLimitsEnabled = false
	constraint.ActuatorType = Enum.ActuatorType.None
	constraint.AngularActuatorType = Enum.ActuatorType.None
	constraint.Parent = parent
	return {constraint, attA, attB}, nil
end
function Compiler.compile(_record:any, _parts:any, _components:any, _features:any, _parent:Instance):({Instance}?, string?)
	return nil, 'Legacy joint compilation retired; resolve manufactured support first'
end
function Compiler.destroy(objects:{Instance}?)
	for _, obj in ipairs(objects or {}) do
		obj:Destroy()
	end
end
return Compiler
