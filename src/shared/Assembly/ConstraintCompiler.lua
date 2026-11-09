--!strict
local Compiler = {}
local function retainedPivot(relation: any, parts: any, parent: Instance): ({ Instance }?, string?)
	local body = parts[relation.bodyId]
	local mover = parts[relation.movingId]
	local pin = parts[relation.pinId]
	local caps = relation.stopIds
	if not body or not mover or not pin or not caps or not parts[caps[1]] or not parts[caps[2]] then
		return nil, "Pivot bodies, pin, or manufactured retainers are missing"
	end
	local axis = relation.direction.Unit
	local up = axis:Cross(if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local joint = CFrame.fromMatrix(relation.point, axis, up, axis:Cross(up))
	local attachmentA = Instance.new("Attachment")
	attachmentA.Name = "OW_Pivot_Body"
	attachmentA.CFrame = body.CFrame:ToObjectSpace(joint)
	attachmentA.Parent = body
	local attachmentB = Instance.new("Attachment")
	attachmentB.Name = "OW_Pivot_Link"
	attachmentB.CFrame = mover.CFrame:ToObjectSpace(joint)
	attachmentB.Parent = mover
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "OW_RetainedPivot"
	hinge.Attachment0 = attachmentA
	hinge.Attachment1 = attachmentB
	hinge.LimitsEnabled = false
	hinge.ActuatorType = Enum.ActuatorType.None
	hinge.Parent = parent
	local objects = {attachmentA, attachmentB, hinge}
	local function keep(piece: BasePart, name: string)
		local weld = Instance.new("WeldConstraint")
		weld.Name = name
		weld.Part0 = mover
		weld.Part1 = piece
		weld.Parent = parent
		table.insert(objects, weld)
	end
	keep(pin, "OW_PivotPin")
	for index, id in ipairs(caps) do
		keep(parts[id], "OW_PinRetainer_" .. index)
	end
	return objects, nil
end

function Compiler.compileResolved(
	relation: any,
	parts: any,
	parent: Instance
): ({ Instance }?, string?)
	if relation.kind == "Revolute" and relation.model == "RetainedPivotV1" then
		return retainedPivot(relation, parts, parent)
	end
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
