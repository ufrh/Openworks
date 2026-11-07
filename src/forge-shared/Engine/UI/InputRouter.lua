local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')

local UIEvent = require(script.Parent.UIEvent)

local InputRouter = {}
InputRouter.__index = InputRouter

local function DisconnectAll(Connections)
	for _, Connection in ipairs(Connections) do
		Connection:Disconnect()
	end
	table.clear(Connections)
end

function InputRouter.new(Manager)
	local self = setmetatable({}, InputRouter)
	self.Manager = Manager
	self.Registry = {}
	self.Hovered = {}
	self.Captured = {}
	self.PointerCapture = nil
	self.Connections = {}
	self.Enabled = false
	self.Destroyed = false
	return self
end

function InputRouter:Register(Widget)
	if self.Destroyed or not Widget or not Widget.Object then return self end
	self.Registry[Widget.Object] = Widget
	return self
end

function InputRouter:Unregister(Widget)
	if not Widget then return self end

	local Object = Widget.Object
	if Object then self.Registry[Object] = nil end
	self.Hovered[Widget] = nil

	for Input, Captured in pairs(self.Captured) do
		if Captured == Widget then self.Captured[Input] = nil end
	end
	if self.PointerCapture == Widget then self.PointerCapture = nil end
	return self
end

function InputRouter:GetWidget(Object)
	while Object do
		local Widget = self.Registry[Object]
		if Widget then return Widget end
		Object = Object.Parent
	end
end

function InputRouter:GetTargetAt(Position)
	local Player = Players.LocalPlayer
	local PlayerGui = Player and Player:FindFirstChildOfClass('PlayerGui')
	if not PlayerGui then return nil end

	for _, Object in ipairs(PlayerGui:GetGuiObjectsAtPosition(Position.X, Position.Y)) do
		local Widget = self:GetWidget(Object)
		if Widget and Widget:IsHitTestVisible() then return Widget end
	end
end

function InputRouter:GetFocusableTarget(Target)
	local Current = Target
	while Current do
		if Current:IsFocusable() then return Current end
		Current = Current.Parent
	end
end

function InputRouter:Route(Name, Target, InputObject, Position)
	if not Target then return nil end

	local Event = UIEvent.new(Name, Target, InputObject, Position)
	local Current = Target
	while Current do
		Event.CurrentTarget = Current
		Current:HandleEvent(Name, Event)
		if Event.Stopped then break end
		Current = Current.Parent
	end
	return Event
end

function InputRouter:UpdateHover(Position, Target)
	if Target == nil then Target = self:GetTargetAt(Position) end

	for Widget in pairs(self.Hovered) do
		if Widget ~= Target then
			self.Hovered[Widget] = nil
			self:Route('MouseLeave', Widget, nil, Position)
		end
	end

	if Target and not self.Hovered[Target] then
		self.Hovered[Target] = true
		self:Route('MouseEnter', Target, nil, Position)
	end
	return Target
end

function InputRouter:Enable()
	if self.Destroyed or self.Enabled then return self end
	self.Enabled = true

	table.insert(self.Connections, UserInputService.InputChanged:Connect(function(Input)
		if self.Manager.InputMode == 'GameOnly' then return end
		if Input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

		local Hit = self.PointerCapture or self:GetTargetAt(Input.Position)
		self:UpdateHover(Input.Position, Hit)
		if Hit then self:Route('MouseMove', Hit, Input, Input.Position) end
	end))

	table.insert(self.Connections, UserInputService.InputBegan:Connect(function(Input, Processed)
		if self.Manager.InputMode == 'GameOnly' then return end

		local Pointer = Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		if Processed and not Pointer and self.Manager.InputMode ~= 'UIOnly' then return end

		local Target = Pointer and self:GetTargetAt(Input.Position) or self.Manager:GetFocusedWidget()
		if Pointer and not Target then
			self.Manager:SetFocusedWidget(nil)
			self.PointerCapture = nil
			return
		end
		if not Target then return end

		if Pointer then
			local FocusTarget = self:GetFocusableTarget(Target)
			self.Manager:SetFocusedWidget(FocusTarget)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.PointerCapture = Target
			else
				self.Captured[Input] = Target
			end
			self:Route('PointerDown', Target, Input, Input.Position)
			return
		end

		local Key = Input.KeyCode
		local ShiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local Direction = Key == Enum.KeyCode.Up and 'Up'
			or Key == Enum.KeyCode.Down and 'Down'
			or Key == Enum.KeyCode.Left and 'Left'
			or Key == Enum.KeyCode.Right and 'Right'
			or Key == Enum.KeyCode.Tab and ShiftDown and 'Previous'
			or Key == Enum.KeyCode.Tab and 'Next'

		if Direction then
			self.Manager:Navigate(Direction)
		else
			self:Route('KeyDown', Target, Input, Input.Position)
		end
	end))

	table.insert(self.Connections, UserInputService.InputEnded:Connect(function(Input)
		if self.Manager.InputMode == 'GameOnly' then return end

		local Pointer = Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		local Target

		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			Target = self.PointerCapture
			self.PointerCapture = nil
		elseif Input.UserInputType == Enum.UserInputType.Touch then
			Target = self.Captured[Input]
			self.Captured[Input] = nil
		end

		if Pointer and Target then
			self:Route('PointerUp', Target, Input, Input.Position)
			local Hovered = self:GetTargetAt(Input.Position)
			if Hovered and (Hovered == Target or Hovered:IsDescendantOf(Target) or Target:IsDescendantOf(Hovered)) then
				self:Route('Clicked', Target, Input, Input.Position)
			end
		elseif not Pointer then
			Target = self.Manager:GetFocusedWidget()
			if Target then self:Route('KeyUp', Target, Input, Input.Position) end
		end
	end))

	return self
end

function InputRouter:Disable()
	if not self.Enabled then return self end
	self.Enabled = false
	DisconnectAll(self.Connections)
	table.clear(self.Hovered)
	table.clear(self.Captured)
	self.PointerCapture = nil
	return self
end

function InputRouter:Destroy()
	if self.Destroyed then return end
	self:Disable()
	self.Destroyed = true
	table.clear(self.Registry)
	self.Manager = nil
end

return InputRouter
