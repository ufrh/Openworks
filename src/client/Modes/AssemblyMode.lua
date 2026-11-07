--!strict
-- Q1 establishes the mode and its independent lifecycle. Q3 adds the
-- feature alignment and physical relationship services.
local AssemblyMode={}
AssemblyMode.__index=AssemblyMode
function AssemblyMode.new(bridge:any)
	return setmetatable({bridge=bridge},AssemblyMode)
end
function AssemblyMode:Enter(_context:any)
	self.bridge.enterAssembly()
end
function AssemblyMode:Exit()
	self.bridge.leaveAssembly()
end
function AssemblyMode:Update(_dt:number) end
return AssemblyMode
