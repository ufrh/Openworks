--!strict
-- Position an authored shaft axis inside a selected manufactured bore.
-- This module only computes an exact CAD pose; it does not register a joint,
-- infer fastening, or replace final-solid interference validation.
local Placement = {}
Placement.MaxOffsetMM = 35840

local function axisRotation(from: Vector3, to: Vector3): CFrame
	local dot = math.clamp(from.Unit:Dot(to.Unit), -1, 1)
	if dot > 1 - 1e-9 then return CFrame.identity end
	local cross = from:Cross(to)
	if cross.Magnitude < 1e-8 then
		cross = from:Cross(if math.abs(from.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
	end
	return CFrame.fromAxisAngle(cross.Unit, math.acos(dot))
end

function Placement.alignAxes(
	moverPose: CFrame, moverAxis: any,
	targetPose: CFrame, targetAxis: any, offsetMM: number
): (CFrame?, string?)
	if typeof(moverPose) ~= "CFrame" or typeof(targetPose) ~= "CFrame"
		or not moverAxis or moverAxis.kind ~= "Axis"
		or not targetAxis or targetAxis.kind ~= "Axis" then
		return nil, "Select two manufactured cylindrical references"
	end
	if type(offsetMM) ~= "number" or offsetMM ~= offsetMM
		or math.abs(offsetMM) > Placement.MaxOffsetMM then
		return nil, "Axial offset is outside the supported range"
	end
	local aPoint = moverPose:PointToWorldSpace(moverAxis.point)
	local aDirection = moverPose:VectorToWorldSpace(moverAxis.direction).Unit
	local bPoint = targetPose:PointToWorldSpace(targetAxis.point)
	local bDirection = targetPose:VectorToWorldSpace(targetAxis.direction).Unit
	-- Preserve the nearest orientation when axes are parallel but opposite.
	local target = if aDirection:Dot(bDirection) < 0 then -bDirection else bDirection
	local turn = axisRotation(aDirection, target)
	local rotated = CFrame.new(aPoint) * turn * CFrame.new(-aPoint) * moverPose
	local alignedPoint = rotated:PointToWorldSpace(moverAxis.point)
	local delta = bPoint - alignedPoint
	local radial = delta - bDirection * delta:Dot(bDirection)
	local axial = bDirection * (delta:Dot(bDirection) + offsetMM / 280)
	return rotated + radial + axial, nil
end

-- Shaft-specific selection guard. All mechanical installations share the
-- same axis/offset math; the domain decides which datums are compatible.
function Placement.solve(shaftPose: CFrame, shaftAxis: any,
	housingPose: CFrame, boreAxis: any, offsetMM: number): (CFrame?, string?)
	if not shaftAxis or shaftAxis.id ~= "shaft"
		or not boreAxis or not boreAxis.feature then
		return nil, "Select a manufactured housing bore and shaft"
	end
	return Placement.alignAxes(
		shaftPose, shaftAxis, housingPose, boreAxis, offsetMM
	)
end

return Placement
