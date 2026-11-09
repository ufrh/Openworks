--!strict
-- Position two manufactured links, a separate pin, and two retainers.
-- The resulting poses are proposed only; domain fit and final-solid CSG
-- must validate the entire group before installation is committed.
local References = require(script.Parent.GeometryReferences)
local FitPlacement = require(script.Parent.FitPlacement)
local Geometry = require(script.Parent.SupportGeometry)

local PivotPlacement = {}
PivotPlacement.MaxOffsetMM = 35840

function PivotPlacement.propose(
	components: any, poses: any,
	bodyId: number, bodyFeature: string,
	movingId: number, movingFeature: string,
	pinId: number, capA: number, capB: number,
	offsetMM: number, phaseDegrees: number
): (any?, any?, string?)
	local ids = {bodyId, movingId, pinId, capA, capB}
	local seen = {}
	for _, id in ipairs(ids) do
		if type(id) ~= "number" or seen[id] or not components[id]
			or not poses[tostring(id)] then
			return nil, nil, "Select five separate, positioned manufactured components"
		end
		seen[id] = true
	end
	if type(offsetMM) ~= "number" or offsetMM ~= offsetMM
		or math.abs(offsetMM) > PivotPlacement.MaxOffsetMM
		or type(phaseDegrees) ~= "number" or phaseDegrees ~= phaseDegrees
		or math.abs(phaseDegrees) > 360 then
		return nil, nil, "Enter a finite axial spacing and rotation angle"
	end
	local body, mover, pin = components[bodyId], components[movingId], components[pinId]
	local bodyBore = References.get(body, bodyFeature)
	local movingBore = References.get(mover, movingFeature)
	local shaft = References.get(pin, "shaft")
	if not bodyBore or not movingBore or not bodyBore.feature
		or not movingBore.feature or not bodyBore.feature.through
		or not movingBore.feature.through then
		return nil, nil, "Both links need manufactured through-bore references"
	end
	if not shaft or pin.nodes[1].kind ~= "Cylinder" then
		return nil, nil, "Choose a separate manufactured cylindrical pin"
	end
	local bodyPose, movingPose = poses[tostring(bodyId)], poses[tostring(movingId)]
	local candidate, reason = FitPlacement.alignAxes(
		movingPose, movingBore, bodyPose, bodyBore, offsetMM
	)
	if not candidate then return nil, nil, reason end
	local bodyWorld = References.world(bodyBore, bodyPose)
	local movingCenter = candidate:PointToWorldSpace(movingBore.point)
	candidate = CFrame.new(movingCenter)
		* CFrame.fromAxisAngle(bodyWorld.direction, math.rad(phaseDegrees))
		* CFrame.new(-movingCenter) * candidate
	local pinPose, pinReason = FitPlacement.solve(
		poses[tostring(pinId)], shaft, bodyPose, bodyBore, offsetMM * 0.5
	)
	if not pinPose then return nil, nil, pinReason end
	local pinWorld = References.world(shaft, pinPose)
	local capABox, capBBox = Geometry.box(components[capA]), Geometry.box(components[capB])
	if not capABox or not capBBox then
		return nil, nil, "Retaining caps must be uncut rectangular stock"
	end
	local center = pinWorld.point
	local axis = pinWorld.direction
	local pinLength = shaft.length
	local capBasis = Geometry.axisFrame(Vector3.zero, axis)
	local alignedCap = CFrame.fromMatrix(
		Vector3.zero, capBasis.XVector, capBasis.YVector, capBasis.ZVector
	)
	local proposed = table.clone(poses)
	proposed[tostring(movingId)] = candidate
	proposed[tostring(pinId)] = pinPose
	proposed[tostring(capA)] = CFrame.new(
		center - axis * (pinLength * 0.5 + capABox.Y * 0.5)
	) * alignedCap
	proposed[tostring(capB)] = CFrame.new(
		center + axis * (pinLength * 0.5 + capBBox.Y * 0.5)
	) * alignedCap
	local record = {
		model = "RetainedPivotV1",
		bodyId = bodyId,
		movingId = movingId,
		featureId = bodyFeature,
		movingFeatureId = movingFeature,
		pinId = pinId,
		stopIds = {capA, capB},
	}
	return proposed, record, nil
end

return PivotPlacement
