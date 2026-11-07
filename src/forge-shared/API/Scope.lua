local Janitor = require(script.Parent.Parent.Kernel.Core.Janitor)

local Scope = {} do
	Scope.__index = Scope
	Scope.ClassName = 'Scope'

	local function cancel(Thread)
		pcall(task.cancel, Thread)
	end

	function Scope.new()
		local self = setmetatable({}, Scope)
		self._Janitor = Janitor.new()
		self._Destroyed = false
		return self
	end

	function Scope:Add(Object, Method)
		assert(not self._Destroyed, 'Cannot add to a destroyed Scope.')
		return self._Janitor:Add(Object, Method)
	end

	Scope.Track = Scope.Add

	function Scope:Connect(Signal, Callback)
		assert(Signal and type(Signal.Connect) == 'function', 'Scope:Connect requires a connectable signal.')
		return self:Add(Signal:Connect(Callback))
	end

	function Scope:After(Delay, Callback)
		assert(type(Delay) == 'number' and Delay >= 0, 'Scope:After requires a non-negative delay.')
		assert(type(Callback) == 'function', 'Scope:After requires a callback.')

		local Active = true
		local Thread
		Thread = task.delay(Delay, function()
			if not Active or self._Destroyed then return end
			Active = false
			Callback()
		end)

		self:Add(function()
			if not Active then return end
			Active = false
			cancel(Thread)
		end)

		return Thread
	end

	function Scope:Every(Interval, Callback, Immediate)
		assert(type(Interval) == 'number' and Interval > 0, 'Scope:Every requires a positive interval.')
		assert(type(Callback) == 'function', 'Scope:Every requires a callback.')

		local Active = true
		local Thread = task.spawn(function()
			if Immediate == true and Active and not self._Destroyed then Callback() end
			while Active and not self._Destroyed do
				task.wait(Interval)
				if Active and not self._Destroyed then Callback() end
			end
		end)

		self:Add(function()
			if not Active then return end
			Active = false
			cancel(Thread)
		end)

		return Thread
	end

	function Scope:Spawn(Callback, ...)
		assert(type(Callback) == 'function', 'Scope:Spawn requires a callback.')
		local Arguments = table.pack(...)
		local Thread = task.spawn(function()
			if self._Destroyed then return end
			Callback(table.unpack(Arguments, 1, Arguments.n))
		end)
		self:Add(function() cancel(Thread) end)
		return Thread
	end

	function Scope:Child()
		local Child = Scope.new()
		self:Add(Child)
		return Child
	end

	function Scope:Cleanup()
		if self._Destroyed then return end
		self._Janitor:Cleanup()
	end

	function Scope:Destroy()
		if self._Destroyed then return end
		self._Destroyed = true
		self._Janitor:Destroy()
	end
end

return Scope
