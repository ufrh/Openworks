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

function Placement.solve(
	shaftPose: CFrame, shaftAxis: any,
	housingPose: CFrame, boreAxis: any, offsetMM: number
): (CFrame?, string?)
	if typeof(shaftPose) ~= "CFrame" or typeof(housingPose) ~= "CFrame"
		or not shaftAxis or shaftAxis.kind ~= "Axis" or shaftAxis.id ~= "shaft"
		or not boreAxis or boreAxis.kind ~= "Axis" or not boreAxis.feature then
		return nil, "Select a manufactured housing bore and a shaft"
	end
	if type(offsetMM) ~= "number" or offsetMM ~= offsetMM
		or math.abs(offsetMM) > Placement.MaxOffsetMM then
		return nil, "Axial offset is outside the supported range"
	end
	local aPoint = shaftPose:PointToWorldSpace(shaftAxis.point)
	local aDirection = shaftPose:VectorToWorldSpace(shaftAxis.direction).Unit
	local bPoint = housingPose:PointToWorldSpace(boreAxis.point)
	local bDirection = housingPose:VectorToWorldSpace(boreAxis.direction).Unit
	-- Preserve the nearest orientation when axes are parallel but opposite.
	local target = if aDirection:Dot(bDirection) < 0 then -bDirection else bDirection
	local turn = axisRotation(aDirection, target)
	local rotated = CFrame.new(aPoint) * turn * CFrame.new(-aPoint) * shaftPose
	local alignedPoint = rotated:PointToWorldSpace(shaftAxis.point)
	local delta = bPoint - alignedPoint
	local radial = delta - bDirection * delta:Dot(bDirection)
	local axial = bDirection * (delta:Dot(bDirection) + offsetMM / 280)
	return rotated + radial + axial, nil
end

return Placement
