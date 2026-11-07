--!strict
-- Explicit disposable event bus. Event listeners cannot cross-mode leak.
local Signal={}
Signal.__index=Signal
function Signal.new()
	return setmetatable({listeners={},destroyed=false},Signal)
end
function Signal:Connect(callback:(...any)->())
	assert(not self.destroyed,"Signal destroyed")
	local listeners=self.listeners
	local listener={callback=callback,connected=true}
	table.insert(listeners,listener)
	return {Disconnect=function()
		listener.connected=false
	end}
end
function Signal:Fire(...:any)
	if self.destroyed then return end
	for _,listener in ipairs(self.listeners) do
		if listener.connected then listener.callback(...) end
	end
end
function Signal:Destroy()
	self.destroyed=true
	table.clear(self.listeners)
end
return Signal
