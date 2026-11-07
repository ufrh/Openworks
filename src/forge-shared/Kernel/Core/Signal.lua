-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:27 PM CDT

local Signal = {} do
	Signal.__index = Signal
	Signal.ClassName = 'Signal'

	local Connection = {} do
		Connection.__index = Connection
		Connection.ClassName = 'SignalConnection'

		-- new -> SignalConnection
		-- Creates one lightweight local signal subscription.
		-- @param Owner, Signal -> Signal owning the subscription.
		-- @param Callback, function -> Listener callback.
		function Connection.new(Owner, Callback)
			local this = setmetatable({}, Connection)

			this.Connected = true
			this._Owner = Owner
			this._Callback = Callback

			return this;
		end

		-- Disconnect -> nil
		-- Removes this subscription without affecting other listeners.
		function Connection:Disconnect()
			if not self.Connected then return end

			self.Connected = false

			local Owner = self._Owner

			self._Owner = nil
			self._Callback = nil

			if Owner then
				Owner._Connections[self] = nil
			end
		end

		Connection.Destroy = Connection.Disconnect
	end

	-- new -> Signal
	-- Creates a local pure-Luau signal that can transport arbitrary runtime objects.
	function Signal.new()
		local this = setmetatable({}, Signal)

		this._Connections = {}
		this._Destroyed = false

		return this;
	end

	-- Connect -> SignalConnection
	-- Subscribes a callback to this signal.
	-- @param Callback, function -> Listener function.
	function Signal:Connect(Callback)
		assert(not self._Destroyed, 'Cannot connect to a destroyed Signal.')
		assert(type(Callback) == 'function', 'Signal:Connect expects a function.')

		local Subscription = Connection.new(self, Callback)

		self._Connections[Subscription] = true

		return Subscription;
	end

	-- Once -> SignalConnection
	-- Subscribes a callback that executes only on the first emission.
	-- @param Callback, function -> Listener function.
	function Signal:Once(Callback)
		assert(not self._Destroyed, 'Cannot connect to a destroyed Signal.')
		assert(type(Callback) == 'function', 'Signal:Once expects a function.')

		local Subscription
		local Fired = false

		Subscription = self:Connect(function(...)
			if Fired then return end

			Fired = true
			Subscription:Disconnect()
			Callback(...)
		end)

		return Subscription;
	end

	-- Wait -> ...any
	-- Yields the current thread until the next signal emission.
	function Signal:Wait()
		assert(not self._Destroyed, 'Cannot wait on a destroyed Signal.')

		local Thread = coroutine.running()
		local Subscription
		local Resumed = false

		Subscription = self:Connect(function(...)
			if Resumed then return end

			Resumed = true
			Subscription:Disconnect()

			task.spawn(Thread, ...)
		end)

		return coroutine.yield();
	end

	-- Fire -> nil
	-- Fires the signal to every current listener without Roblox value serialization.
	-- @param ..., any -> Values forwarded by reference to listeners.
	function Signal:Fire(...)
		if self._Destroyed or next(self._Connections) == nil then return end

		local Arguments = table.pack(...)
		local Snapshot = {}

		for Subscription in pairs(self._Connections) do
			if Subscription.Connected and Subscription._Callback then
				table.insert(Snapshot, Subscription)
			end
		end

		for _, Subscription in ipairs(Snapshot) do
			if not Subscription.Connected or not Subscription._Callback then
				continue
			end

			local Callback = Subscription._Callback

			task.spawn(function()
				Callback(table.unpack(Arguments, 1, Arguments.n))
			end)
		end
	end

	-- Destroy -> nil
	-- Disconnects every listener and prevents future subscriptions or emissions.
	function Signal:Destroy()
		if self._Destroyed then return end

		self._Destroyed = true

		local Snapshot = {}

		for Subscription in pairs(self._Connections) do
			table.insert(Snapshot, Subscription)
		end

		for _, Subscription in ipairs(Snapshot) do
			Subscription:Disconnect()
		end

		table.clear(self._Connections)
	end
end

return Signal;