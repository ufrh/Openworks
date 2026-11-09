--!strict
-- Joint graph integrity, shared by live registration and persisted restore.
-- A hardware piece cannot silently become a fastener in two different
-- relationships. Multiple distinct pivots on one linkage remain legal.
local Integrity = {}
local function isPivot(model: string): boolean
	return model == "RetainedPivotV1" or model == "DualPinRigidV1"
end

local function fasteners(record: any): {number}
	local ids = {}
	if record.pinId then table.insert(ids, record.pinId) end
	for _, id in ipairs(record.pinIds or {}) do table.insert(ids, id) end
	for _, id in ipairs(record.stopIds or {}) do table.insert(ids, id) end
	return ids
end

local function samePair(a: any, b: any): boolean
	return a.bodyId and b.bodyId
		and ((a.bodyId == b.bodyId and a.movingId == b.movingId)
			or (a.bodyId == b.movingId and a.movingId == b.bodyId))
end

function Integrity.canAdd(existing: {any}, candidate: any): (boolean, string?)
	if type(existing) ~= "table" or type(candidate) ~= "table"
		or type(candidate.model) ~= "string" or type(candidate.movingId) ~= "number" then
		return false, "Invalid mechanical relationship record"
	end
	local pivot = isPivot(candidate.model)
	local used = {}
	for _, id in ipairs(fasteners(candidate)) do
		if type(id) ~= "number" or used[id] then
			return false, "A fastener cannot be repeated within one mechanical joint"
		end
		used[id] = true
	end

	for _, prior in ipairs(existing) do
		local priorPivot = isPivot(prior.model)
		if pivot and priorPivot then
			if samePair(candidate, prior) then
				return false,
					"These bodies are already connected. Remove the earlier joint before changing its mechanical model"
			end
			for _, id in ipairs(fasteners(prior)) do
				if used[id] then
					return false, "A pin or retainer cannot secure two independent joints"
				end
			end
		elseif not pivot and not priorPivot and
			(prior.movingId or prior.shaftId) == candidate.movingId then
			return false, "This moving component already has a bearing or guide"
		end
	end
	return true, nil
end

return Integrity
