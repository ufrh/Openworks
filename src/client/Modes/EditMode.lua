--!strict
local EditMode={}
EditMode.__index=EditMode
function EditMode.new(bridge:any,environment:any)
	return setmetatable({bridge=bridge,environment=environment,workspace=nil},EditMode)
end
function EditMode:Enter(context:any)
	assert(context and context.workspace,"Edit Mode requires component workspace")
	self.workspace=context.workspace
	self.environment:show()
	self.bridge.enterEditor(context.workspace)
end
function EditMode:Exit()
	self.bridge.leaveEditor()
	self.environment:hide()
	self.workspace=nil
end
function EditMode:CleanupFailedEnter()
	self.environment:hide()
end
function EditMode:Update(_dt:number) end
return EditMode
