local UIEvent = {} do
	UIEvent.__index = UIEvent

	function UIEvent.new(Name, Target, InputObject, Position)
		local self = setmetatable({}, UIEvent)
		self.Name = Name
		self.Target = Target
		self.CurrentTarget = Target
		self.InputObject = InputObject
		self.Position = Position
		self.Handled = false
		self.Stopped = false
		return self
	end

	function UIEvent:Handle()
		self.Handled = true
		return self
	end

	function UIEvent:StopPropagation()
		self.Stopped = true
		self.Handled = true
		return self
	end

	function UIEvent:IsHandled()
		return self.Handled
	end
end

return UIEvent;