--!strict

-- Owns the assembly editing lifecycle; simulation has a separate mode.
local AssemblyMode = {}
AssemblyMode.__index = AssemblyMode

function AssemblyMode.new(bridge: any, assembly: any)
	return setmetatable({bridge = bridge, assembly = assembly}, AssemblyMode)
end

function AssemblyMode:Enter(_context: any)
	self.assembly:Enter()
end

function AssemblyMode:Exit()
	self.assembly:Exit()
end

function AssemblyMode:CleanupFailedEnter()
	self.assembly:Exit()
end

function AssemblyMode:Update(dt: number)
	self.assembly:Update(dt)
end

return AssemblyMode
