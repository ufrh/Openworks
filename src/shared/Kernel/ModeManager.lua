--!strict
-- One mode per player. Enter/Exit are synchronous and may not yield.
-- Failed entry attempts restore the prior mode; no recursive transitions.
local ModeManager={}
ModeManager.__index=ModeManager
function ModeManager.new(context:any)
	return setmetatable({
		context=context,modes={},current=nil,currentName=nil,
		busy=false,changed=nil,
	},ModeManager)
end
function ModeManager:register(name:string,mode:any)
	assert(self.modes[name]==nil,"Duplicate mode: "..name)
	assert(type(mode.Enter)=="function" and type(mode.Exit)=="function",
		"Mode must implement Enter and Exit: "..name)
	self.modes[name]=mode
end
function ModeManager:switch(name:string,context:any?):(boolean,string?)
	local nextMode=self.modes[name]
	if not nextMode then return false,"Unknown mode: "..name end
	if self.busy then return false,"Mode transition already in progress" end
	if self.current==nextMode then return true,nil end
	self.busy=true
	local oldMode=self.current
	local oldName=self.currentName
	local oldContext=self.context
	if oldMode then
		local ok,err=pcall(function()oldMode:Exit()end)
		if not ok then
			self.busy=false
			return false,"Exit "..tostring(oldName).." failed: "..tostring(err)
		end
	end
	local args=context or self.context
	local ok,err=pcall(function()nextMode:Enter(args)end)
	if not ok then
		warn("[OPENWORKS] Enter "..name.." failed: "..tostring(err))
		if nextMode.CleanupFailedEnter then
			pcall(function()nextMode:CleanupFailedEnter()end)
		end
		if oldMode then
			local restored,restoreError=pcall(function()oldMode:Enter(oldContext)end)
			self.current=if restored then oldMode else nil
			self.currentName=if restored then oldName else nil
			if not restored then warn("[OPENWORKS] Failed to restore prior mode: "..tostring(restoreError)) end
		else
			self.current=nil
			self.currentName=nil
		end
		self.busy=false
		return false,tostring(err)
	end
	self.current=nextMode
	self.currentName=name
	self.context=args
	self.busy=false
	if self.changed then self.changed:Fire(name,oldName) end
	return true,nil
end
function ModeManager:update(dt:number)
	if not self.busy and self.current and self.current.Update then
		self.current:Update(dt)
	end
end
function ModeManager:destroy()
	if self.current then pcall(function()self.current:Exit()end) end
	self.current=nil
	self.currentName=nil
	for _,mode in pairs(self.modes) do
		if mode.Destroy then pcall(function()mode:Destroy()end) end
	end
	if self.changed then self.changed:Destroy() end
	table.clear(self.modes)
end
return ModeManager
