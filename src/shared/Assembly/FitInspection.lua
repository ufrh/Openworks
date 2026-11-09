--!strict
-- Reference measurements are geometric observations, never constraints.
-- Use authored FORM datums; mesh triangle topology is not stable under CSG.
local FitInspection = {}
local MM_PER_STUD = 280

local function degreesBetween(a: Vector3, b: Vector3): number
	local cosine = math.clamp(math.abs(a.Unit:Dot(b.Unit)), 0, 1)
	return math.deg(math.acos(cosine))
end

function FitInspection.measure(referenceA: any, referenceB: any): (any?, string?)
	if not referenceA or not referenceB
		or typeof(referenceA.point) ~= "Vector3"
		or typeof(referenceB.point) ~= "Vector3"
		or typeof(referenceA.direction) ~= "Vector3"
		or typeof(referenceB.direction) ~= "Vector3"
		or referenceA.direction.Magnitude < 0.9
		or referenceB.direction.Magnitude < 0.9 then
		return nil, "Select two valid source references"
	end

	local a = referenceA.direction.Unit
	local b = referenceB.direction.Unit
	local delta = referenceB.point - referenceA.point
	local angle = degreesBetween(a, b)
	local signed = delta:Dot(a) * MM_PER_STUD

	if referenceA.kind == "Axis" and referenceB.kind == "Axis" then
		local radial = (delta - a * delta:Dot(a)).Magnitude * MM_PER_STUD
		local result = {
			kind = "Axes",
			angle = angle,
			radial = radial,
			axial = signed,
		}
		if type(referenceA.diameter) == "number" then
			result.diameterA = referenceA.diameter * MM_PER_STUD
		end
		if type(referenceB.diameter) == "number" then
			result.diameterB = referenceB.diameter * MM_PER_STUD
		end
		if result.diameterA and result.diameterB then
			result.diametralDifference = result.diameterB - result.diameterA
		end
		return result, nil
	end

	if referenceA.kind == "Plane" and referenceB.kind == "Plane" then
		return { kind = "Planes", angle = angle, separation = signed }, nil
	end

	return nil, "Select two axes or two planar faces"
end

function FitInspection.describe(measurement: any): string
	if not measurement then return "No measurement" end
	if measurement.kind == "Axes" then
		local text = string.format(
			"Axis angle %.3f° · radial offset %.2f mm · axial offset %+.2f mm",
			measurement.angle, measurement.radial, measurement.axial
		)
		if measurement.diametralDifference then
			text ..= string.format(
				"\nØ A %.2f mm · Ø B %.2f mm · B − A %+.2f mm",
				measurement.diameterA, measurement.diameterB,
				measurement.diametralDifference
			)
		end
		return text
	end
	return string.format(
		"Plane angle %.3f° · signed separation %+.2f mm",
		measurement.angle, measurement.separation
	)
end

return FitInspection
