--!strict
-- The CAD / character handoff must NEVER yield: PlayerModule may take
-- several seconds to appear on slower first spawns. Resolve controls
-- ahead of time and apply the desired state when they become available.
local CharacterMode={}
CharacterMode.__index=CharacterMode

function CharacterMode.new(player:Player)
	local self=setmetatable({
		player=player,editing=false,controls=nil,
	},CharacterMode)
	local function acquire()
		local scripts=player:FindFirstChild("PlayerScripts")
		if not scripts then return nil end
		local module=scripts:FindFirstChild("PlayerModule")
		if not module then return nil end
		local ok,controls=pcall(function()
			return require(module):GetControls()
		end)
		return if ok then controls else nil
	end
	-- Fast path: when PlayerModule is already loaded, no task scheduling.
	self.controls=acquire()
	if not self.controls then
		-- Prewarm asynchronously at startup; never WaitForChild in an
		-- interaction callback or while the character camera is changing.
		task.spawn(function()
			local scripts=player:WaitForChild("PlayerScripts")
			local module=scripts:WaitForChild("PlayerModule")
			local ok,controls=pcall(function()
				return require(module):GetControls()
			end)
			if not ok or not controls then return end
			self.controls=controls
			if self.editing then controls:Disable() end
		end)
	end
	return self
end

function CharacterMode:setEditing(editing:boolean)
	if self.editing==editing then return end
	self.editing=editing
	if self.controls then
		if editing then self.controls:Disable() else self.controls:Enable() end
	end
	local player=self.player
	if editing then
		local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid:Move(Vector3.zero,false) end
	else
		local camera=workspace.CurrentCamera
		if camera then
			camera.CameraType=Enum.CameraType.Custom
			local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then camera.CameraSubject=humanoid end
		end
	end
end

return CharacterMode
