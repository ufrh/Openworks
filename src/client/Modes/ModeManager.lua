--!strict
-- Game-specific mode state. FORGE owns lifecycle/DI of its controller;
-- this class only coordinates the active player interaction mode.
local FORGE = require(game:GetService("ReplicatedStorage"):WaitForChild("FORGE"))
local ModeManager = {}
ModeManager.__index = ModeManager
function ModeManager.new()
	return setmetatable({
		modes = {},
		current = nil,
		currentName = nil,
		busy = false,
		changed = FORGE.Signal(),
		lastContext = nil,
	}, ModeManager)
end
function ModeManager:register(name: string, mode: any)
	assert(not self.modes[name], "Duplicate mode: " .. name)
	assert(
		type(mode.Enter) == "function" and type(mode.Exit) == "function",
		"Mode requires Enter/Exit"
	)
	self.modes[name] = mode
end
function ModeManager:switch(name: string, context: any?): (boolean, string?)
	local nextMode = self.modes[name]
	if not nextMode then
		return false, "Unknown mode: " .. name
	end
	if self.busy then
		return false, "Mode switch already active"
	end
	if self.current == nextMode then
		return true, nil
	end
	self.busy = true
	local old, oldName, oldContext = self.current, self.currentName, self.lastContext
	if old then
		local ok, err = pcall(function()
			old:Exit()
		end)
		if not ok then
			self.busy = false
			return false, tostring(err)
		end
	end
	local ok, err = pcall(function()
		nextMode:Enter(context)
	end)
	if not ok then
		if nextMode.CleanupFailedEnter then
			pcall(function()
				nextMode:CleanupFailedEnter()
			end)
		end
		if old then
			local restored, problem = pcall(function()
				old:Enter(oldContext)
			end)
			self.current = if restored then old else nil
			self.currentName = if restored then oldName else nil
			if not restored then
				warn("[OPENWORKS] Mode rollback failed: " .. tostring(problem))
				if old.CleanupFailedEnter then
					pcall(function()
						old:CleanupFailedEnter()
					end)
				end
			end
		else
			self.current = nil
			self.currentName = nil
		end
		if not self.current and self.modes.Free then
			local free = self.modes.Free
			local recovered = pcall(function()
				free:Enter()
			end)
			if recovered then
				self.current, self.currentName, self.lastContext = free, "Free", nil
				self.changed:Fire("Free", oldName)
			elseif free.CleanupFailedEnter then
				pcall(function()
					free:CleanupFailedEnter()
				end)
			end
		end
		self.busy = false
		return false, tostring(err)
	end
	self.current = nextMode
	self.currentName = name
	self.lastContext = context
	self.busy = false
	self.changed:Fire(name, oldName)
	return true, nil
end
function ModeManager:update(dt: number)
	if self.current and not self.busy and self.current.Update then
		self.current:Update(dt)
	end
end
function ModeManager:destroy()
	if self.current then
		pcall(function()
			self.current:Exit()
		end)
	end
	for _, mode in pairs(self.modes) do
		if mode.Destroy then
			pcall(function()
				mode:Destroy()
			end)
		end
	end
	self.changed:Destroy()
	table.clear(self.modes)
	self.current = nil
	self.currentName = nil
	self.lastContext = nil
end
return ModeManager
