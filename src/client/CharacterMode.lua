--!strict
-- Normal Roblox player controls are the default. Entering component
-- workspace explicitly suspends walking and gives control to the CAD camera.
local CharacterMode={}
CharacterMode.__index=CharacterMode

function CharacterMode.new(player:Player)
	return setmetatable({player=player,editing=false,controls=nil},CharacterMode)
end

function CharacterMode:setEditing(editing:boolean)
	if self.editing==editing then return end
	self.editing=editing
	local player=self.player
	local ok,controls=pcall(function()
		local module=player.PlayerScripts:WaitForChild("PlayerModule",5)
		if not module then return nil end
		return require(module):GetControls()
	end)
	if ok and controls then
		self.controls=controls
		if editing then
			controls:Disable()
		else
			controls:Enable()
		end
	end
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
