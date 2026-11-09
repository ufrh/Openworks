--!strict
-- Structural sanity check for a source-authored bore. Allows independent
-- mounting and pivot holes, but rejects merged bore paths before Simulation.
-- This is not a finite-element stress calculation or a substitute for CSG.
local References = require(script.Parent.GeometryReferences)
local Geometry = require(script.Parent.SupportGeometry)

local Integrity = {}
Integrity.MinimumWeb = Geometry.Wall

local function closestSegmentDistance(a0: Vector3, a1: Vector3,
	b0: Vector3, b1: Vector3): number
	local u, v = a1 - a0, b1 - b0
	local w = a0 - b0
	local aa, bb, cc = u:Dot(u), u:Dot(v), v:Dot(v)
	local dd, ee = u:Dot(w), v:Dot(w)
	local denominator = aa * cc - bb * bb
	local s, t
	if aa < 1e-10 or cc < 1e-10 then
		return (a0 - b0).Magnitude
	end
	if denominator < 1e-10 then
		s = 0
		t = math.clamp(ee / cc, 0, 1)
	else
		s = math.clamp((bb * ee - cc * dd) / denominator, 0, 1)
		t = math.clamp((aa * ee - bb * dd) / denominator, 0, 1)
	end
	-- Clamping one segment endpoint changes the best point on the other.
	s = math.clamp((bb * t - dd) / aa, 0, 1)
	t = math.clamp((bb * s + ee) / cc, 0, 1)
	s = math.clamp((bb * t - dd) / aa, 0, 1)
	return (w + u * s - v * t).Magnitude
end

function Integrity.check(component: any, reference: any): (boolean, string?)
	if not component or not reference or not reference.feature
		or not reference.feature.through then
		return false, "Select a manufactured through-bore"
	end
	local low, high = Geometry.boreSpan(
		component.nodes[1],
		reference.point,
		reference.direction,
		reference.diameter * 0.5 + Integrity.MinimumWeb
	)
	if not low or not high then
		return false, "Bore lacks a continuous surrounding wall"
	end
	local startA = reference.point
	local endA = startA + reference.direction.Unit * reference.feature.depth
	for _, other in ipairs(References.list(component)) do
		if other.id == reference.id or not other.feature then continue end
		local startB = other.point
		local endB = startB + other.direction.Unit * other.feature.depth
		local distance = closestSegmentDistance(startA, endA, startB, endB)
		if distance + 1e-5 <
			(reference.diameter + other.diameter) * 0.5 + Integrity.MinimumWeb then
			return false,
				"Bore intersects another machined opening or leaves less than 1 mm of material"
		end
	end
	return true, nil
end

return Integrity
