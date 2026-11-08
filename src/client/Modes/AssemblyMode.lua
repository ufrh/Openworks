--!strict
-- Q1 establishes the mode and its independent lifecycle. Q3 adds the
-- feature alignment and physical relationship services.
local AssemblyMode={}
AssemblyMode.__index=AssemblyMode
function AssemblyMode.new(bridge:any,assembly:any)
 return setmetatable({bridge=bridge,assembly=assembly},AssemblyMode)
end
function AssemblyMode:Enter(_context:any)
 self.assembly:Enter()
end
function AssemblyMode:Exit()
 self.assembly:Exit()
end
function AssemblyMode:CleanupFailedEnter() self.assembly:Exit() end
function AssemblyMode:Update(dt:number)
 self.assembly:Update(dt)
end
return AssemblyMode

