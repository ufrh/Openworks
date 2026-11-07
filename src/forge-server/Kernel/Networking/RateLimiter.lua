-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local RateLimiter = {} do
	RateLimiter.__index = RateLimiter
	RateLimiter.ClassName = 'RateLimiter'

	-- new -> RateLimiter
	-- Creates a token-bucket limiter keyed by arbitrary objects or strings.
	function RateLimiter.new()
		local this = setmetatable({}, RateLimiter)
		this._Buckets = {}
		return this;
	end

	-- Allow -> boolean
	-- Consumes one token from a bucket when enough capacity is available.
	-- @param Key, any -> Bucket identity.
	-- @param Capacity, number -> Maximum bucket size.
	-- @param Refill, number -> Tokens restored per second.
	-- @param Cost, number? -> Token cost of this request.
	function RateLimiter:Allow(Key, Capacity, Refill, Cost)
		Cost = Cost or 1
		local Now = time()
		local Bucket = self._Buckets[Key]

		if not Bucket then
			Bucket = {Tokens = Capacity; Updated = Now;}
			self._Buckets[Key] = Bucket
		end

		local Delta = math.max(Now - Bucket.Updated, 0)
		Bucket.Updated = Now
		Bucket.Tokens = math.min(Capacity, Bucket.Tokens + Delta * Refill)
		if Bucket.Tokens < Cost then return false end
		Bucket.Tokens -= Cost
		return true;
	end

	-- Clear -> nil
	-- Clears every bucket associated with one key prefix object.
	-- @param Key, any -> Exact bucket key to remove.
	function RateLimiter:Clear(Key)
		self._Buckets[Key] = nil
	end

	-- ClearPrefix -> nil
	-- Removes every string-keyed bucket beginning with one prefix.
	-- @param Prefix, string -> Bucket prefix to remove.
	function RateLimiter:ClearPrefix(Prefix)
		for Key in pairs(self._Buckets) do
			if type(Key) == 'string' and string.sub(Key, 1, #Prefix) == Prefix then self._Buckets[Key] = nil end
		end
	end

	-- Destroy -> nil
	-- Clears all limiter state.
	function RateLimiter:Destroy()
		table.clear(self._Buckets)
	end
end

return RateLimiter;
