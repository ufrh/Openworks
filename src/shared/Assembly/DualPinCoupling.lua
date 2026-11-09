--!strict
-- Two separated, retained through-pins mechanically lock the relative
-- pose of two rigid bodies. No fasteners, links, or weld geometry are
-- generated; the solver weld is a representation of this physical fit.
local References = require(script.Parent.GeometryReferences)
local Pivot = require(script.Parent.PinnedPivot)

local Coupling = {}
local MIN_SPACING = 0.08 -- 22.4 mm between independent parallel pin axes

local function checkPivot(
	record: any, components: any, poses: any,
	pinId: number, stopA: number, stopB: number,
	featureBody: string, featureMover: string
): (any?, string?)
	return Pivot.resolve({
		model = "RetainedPivotV1",
		bodyId = record.bodyId,
		movingId = record.movingId,
		featureId = featureBody,
		movingFeatureId = featureMover,
		pinId = pinId,
		stopIds = {stopA, stopB},
	}, components, poses)
end

function Coupling.resolve(record: any, components: any, poses: any): (any?, string?)
	if type(record.pinIds) ~= "table" or #record.pinIds ~= 2
		or type(record.stopIds) ~= "table" or #record.stopIds ~= 4 then
		return nil, "A rigid coupling requires two pins and four separate retainers"
	end
	local unique = {}
	for _, id in ipairs({
		record.bodyId, record.movingId,
		record.pinIds[1], record.pinIds[2],
		record.stopIds[1], record.stopIds[2],
		record.stopIds[3], record.stopIds[4],
	}) do
		if type(id) ~= "number" or unique[id] or not components[id] then
			return nil, "Both links and all six fasteners must be distinct manufactured parts"
		end
		unique[id] = true
	end
	local first, firstReason = checkPivot(
		record, components, poses,
		record.pinIds[1], record.stopIds[1], record.stopIds[2],
		record.featureId, record.movingFeatureId
	)
	if not first then return nil, "First pin: " .. tostring(firstReason) end
	local body = components[record.bodyId]
	local mover = components[record.movingId]
	local match = nil
	local matchCount = 0
	for _, featureBody in ipairs(References.list(body)) do
		if not featureBody.feature or featureBody.id == record.featureId then continue end
		for _, featureMover in ipairs(References.list(mover)) do
			if not featureMover.feature or featureMover.id == record.movingFeatureId then continue end
			local second = checkPivot(
				record, components, poses,
				record.pinIds[2], record.stopIds[3], record.stopIds[4],
				featureBody.id, featureMover.id
			)
			if second then
				local delta = second.point - first.point
				local lateral = (delta - first.direction * delta:Dot(first.direction)).Magnitude
				if lateral >= MIN_SPACING
					and math.abs(first.direction:Dot(second.direction)) > 0.9999 then
					matchCount += 1
					match = {body = featureBody.id, mover = featureMover.id}
				end
			end
		end
	end
	if matchCount == 0 then
		return nil, "Second pin needs a distinct pair of coaxial through-bores, 22 mm or more from the first"
	elseif matchCount > 1 then
		return nil, "Multiple secondary bore pairs fit; reposition the pins to identify one pair"
	end
	return {
		kind = "Rigid",
		model = record.model,
		bodyId = body.id,
		movingId = mover.id,
		pinIds = {record.pinIds[1], record.pinIds[2]},
		stopIds = table.clone(record.stopIds),
		secondary = match,
		point = first.point,
		direction = first.direction,
		translation = 0,
		rotation = 0,
		retained = true,
	}, nil
end

return Coupling
