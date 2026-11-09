--!strict
-- A manufactured pivot has two drilled members, a real pin and two end caps.
-- Retention and press-fit are idealized into constraints in Simulation;
-- geometric material clearance is audited independently by FORM.
local References = require(script.Parent.GeometryReferences)
local Geometry = require(script.Parent.SupportGeometry)

local Pivot = {}
local MM = 1 / 280
local MAX_RADIAL_ERROR = 1.5 * MM
local MAX_CAP_ERROR = 3 * MM

local function hasActiveOperations(component: any): boolean
	for _, operation in ipairs(component.operations or {}) do
		if operation.enabled ~= false then
			return true
		end
	end
	return false
end

local function checkBore(ref: any, component: any, pose: CFrame, shaft: any): (boolean, string?)
	if not ref or not ref.feature or not ref.feature.through then
		return false, "Both links need manufactured through-bores"
	end
	local clearance = ref.diameter - shaft.diameter
	if clearance < MM - 1e-6 or clearance > 4 * MM + 1e-6 then
		return false, "Pin requires 1–4 mm diametral clearance in each bore"
	end
	local world = References.world(ref, pose)
	local alignment = math.abs(world.direction:Dot(shaft.direction))
	if alignment < 0.9999 then
		return false, "Pin and bore axes must be concentric"
	end
	local difference = world.point - shaft.point
	local axial = difference:Dot(shaft.direction)
	local radial = (difference - shaft.direction * axial).Magnitude
	if radial > math.min(MAX_RADIAL_ERROR, clearance * 0.5 + 0.0001) then
		return false, "Pin is not inside the bore centerline clearance"
	end
	local localMin, localMax = Geometry.boreSpan(
		component.nodes[1],
		ref.point,
		ref.direction,
		ref.diameter * 0.5 + Geometry.Wall
	)
	if not localMin or not localMax then
		return false, "Pivot bore lacks a continuous surrounding wall"
	end
	local inner = world.point + world.direction * math.min((localMax - localMin) * 0.5, ref.feature.depth * 0.5)
	local innerAxial = (inner - shaft.point):Dot(shaft.direction)
	if math.abs(axial) > shaft.length * 0.5 - MM or math.abs(innerAxial) > shaft.length * 0.5 - MM then
		return false, "Pin must pass through both drilled links"
	end
	return true, nil
end

function Pivot.resolve(record: any, components: any, poses: any): (any?, string?)
	local body = components[record.bodyId]
	local mover = components[record.movingId]
	local pin = components[record.pinId]
	local caps = record.stopIds
	if not body or not mover or not pin or type(caps) ~= "table" or #caps ~= 2 then
		return nil, "Pivot needs two links, one manufactured pin and two end caps"
	end
	local seen = {}
	for _, id in ipairs({record.bodyId, record.movingId, record.pinId, caps[1], caps[2]}) do
		if type(id) ~= "number" or not components[id] or seen[id] then
			return nil, "Pivot hardware must use five distinct manufactured components"
		end
		seen[id] = true
	end
	if hasActiveOperations(pin) or pin.nodes[1].kind ~= "Cylinder" then
		return nil, "Pivot pin must be an uncut manufactured cylinder"
	end
	local pinPose = poses[tostring(pin.id)]
	local bodyPose = poses[tostring(body.id)]
	local moverPose = poses[tostring(mover.id)]
	if not pinPose or not bodyPose or not moverPose then
		return nil, "Position all pivot components first"
	end
	local shaftRef = References.get(pin, "shaft")
	if not shaftRef then
		return nil, "Pin axis is unavailable"
	end
	local shaft = References.world(shaftRef, pinPose)
	local a = References.get(body, record.featureId)
	local b = References.get(mover, record.movingFeatureId)
	local ok, why = checkBore(a, body, bodyPose, shaft)
	if not ok then
		return nil, why
	end
	ok, why = checkBore(b, mover, moverPose, shaft)
	if not ok then
		return nil, why
	end

	local ends = {}
	for _, capId in ipairs(caps) do
		local component = components[capId]
		local pose = poses[tostring(capId)]
		local size = Geometry.box(component)
		if not pose or not size or hasActiveOperations(component) then
			return nil, "End caps must be positioned uncut rectangular stock"
		end
		if math.abs(pose.YVector:Dot(shaft.direction)) < 0.9999 then
			return nil, "End cap faces must be square to the pin axis"
		end
		if math.min(size.X, size.Z) < shaft.diameter + 2 * MM then
			return nil, "End caps must cover the pin diameter"
		end
		local delta = pose.Position - shaft.point
		local distance = delta:Dot(shaft.direction)
		local radial = (delta - shaft.direction * distance).Magnitude
		if radial > MAX_CAP_ERROR then
			return nil, "End caps are not centered over the pin"
		end
		local endSign = if distance > 0 then 1 else -1
		if ends[endSign] then
			return nil, "Place one end cap on each end of the pin"
		end
		if math.abs(math.abs(distance) - (shaft.length * 0.5 + size.Y * 0.5)) > MAX_CAP_ERROR then
			return nil, "End caps must touch the pin ends without overlapping"
		end
		ends[endSign] = true
	end
	if not ends[-1] or not ends[1] then
		return nil, "Pivot pin needs retention on both ends"
	end

	return {
		kind = "Revolute",
		model = record.model,
		bodyId = body.id,
		movingId = mover.id,
		pinId = pin.id,
		stopIds = {caps[1], caps[2]},
		point = References.world(a, bodyPose).point,
		direction = shaft.direction,
		translation = 0,
		rotation = 1,
		retained = true,
	}, nil
end

return Pivot
