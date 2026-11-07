local Signal = require(script.Parent.Parent.Kernel.Core.Signal)
local Replication = require(script.Parent.Parent.Engine.Replication)
local Permissions = require(script.Parent.Permissions)

local Event = {} do
	Event.__index = Event
	Event.ClassName = 'Event'

	local function options(Value)
		if type(Value) == 'table' and Value._FORGEContract and type(Value.ToOptions) == 'function' then
			return Value:ToOptions()
		end
		return type(Value) == 'table' and table.clone(Value) or {}
	end

	function Event.new(Options)
		local self = setmetatable({}, Event)
		self._FORGEEvent = true
		self._Options = Options
		self._Signal = Signal.new()
		self._Service = nil
		self._Name = nil
		self._Destroyed = false
		return self
	end

	function Event:_Attach(Service, Name)
		assert(not self._Destroyed, 'Cannot attach a destroyed Event.')
		assert(not self._Service, 'FORGE Event is already attached.')
		assert(Service and Service.Kind == 'Service', 'FORGE Event can only attach to a Service.')
		assert(type(Name) == 'string' and Name ~= '', 'FORGE Event requires a field name.')

		self._Service = Service
		self._Name = Name
		Service:CreateSignal(Name)

		Service.Client[Name] = function(Player, ...)
			self._Signal:Fire(Player, ...)
		end

		local Options = Permissions:Apply(options(self._Options))
		Options.Transport = 'Event'
		Service:ConfigureEndpoint(Name, Options)
		return self
	end

	function Event:Connect(Callback)
		return self._Signal:Connect(Callback)
	end

	function Event:Once(Callback)
		return self._Signal:Once(Callback)
	end

	function Event:Wait()
		return self._Signal:Wait()
	end

	function Event:Fire(Target, ...)
		assert(self._Service and self._Name, 'FORGE Event must be assigned to a Service before firing remotely.')
		assert(Target ~= nil, 'Event:Fire requires a Player or FORGE.To audience. Use :Broadcast(...) for everyone.')

		if typeof(Target) == 'Instance' and Target:IsA('Player') then
			self._Service:FireClient(Target, self._Name, ...)
			return
		end

		for _, Player in ipairs(Replication:Recipients(Target)) do
			self._Service:FireClient(Player, self._Name, ...)
		end
	end

	function Event:Broadcast(...)
		assert(self._Service and self._Name, 'FORGE Event must be assigned to a Service before broadcasting.')
		self._Service:FireAll(self._Name, ...)
	end

	Event.FireAll = Event.Broadcast

	function Event:Destroy()
		if self._Destroyed then return end
		self._Destroyed = true
		self._Signal:Destroy()
		self._Service = nil
		self._Name = nil
	end
end

return Event
