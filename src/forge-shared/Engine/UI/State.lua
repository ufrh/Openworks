local Signal = require(script.Parent.Parent.Parent.Kernel.Core.Signal)

local State = {} do
	State.__index = State

	function State.new(Value)
		local self = setmetatable({}, State)
		self.Value = Value
		self.Changed = Signal.new()
		self.Destroyed = false
		return self
	end

	function State:Get()
		return self.Value
	end

	function State:Set(Value)
		assert(not self.Destroyed, 'Cannot set a destroyed UI State.')
		if self.Value == Value then return false end
		local Previous = self.Value
		self.Value = Value
		self.Changed:Fire(Value, Previous)
		return true
	end

	function State:Update(Callback)
		assert(type(Callback) == 'function', 'State update requires a function.')
		self:Set(Callback(self.Value))
		return self.Value
	end

	function State:Subscribe(Callback, Immediate)
		assert(type(Callback) == 'function', 'State subscription requires a function.')
		local Connection = self.Changed:Connect(Callback)
		if Immediate ~= false then Callback(self.Value, nil) end
		return Connection
	end

	function State:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		self.Changed:Destroy()
	end
end

return State;