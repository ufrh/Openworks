--!strict
local FreeMode={}
FreeMode.__index=FreeMode
function FreeMode.new(bridge:any)
	return setmetatable({bridge=bridge},FreeMode)
end
function FreeMode:Enter(_context:any)
	self.bridge.leaveEditor()
end
function FreeMode:Exit() end
function FreeMode:Update(_dt:number) end
return FreeMode
