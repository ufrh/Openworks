local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local GuiService = game:GetService('GuiService')
local InputRouter = require(script.Parent.InputRouter)
local Enums = require(script.Parent.Enums)

local UIManager = {} do
	UIManager.__index = UIManager

	local SpatialDirections = {Up = true, Down = true, Left = true, Right = true}

	function UIManager.new()
		local self = setmetatable({}, UIManager)
		self.Screen = nil
		self.Viewport = nil
		self.Widgets = {}
		self.Layers = {}
		self.BindingWidgets = setmetatable({}, {__mode = 'k'})
		self.BindingConnection = nil
		self.BindingCount = 0
		self.InputMode = 'GameAndUI'
		self.FocusedWidget = nil
		self.InputRouter = InputRouter.new(self)
		return self
	end

	function UIManager:Initialize(ScreenGui)
		assert(RunService:IsClient(), 'FORGE.UI viewport is client-only.')
		if self.Screen then return self.Screen end

		local Screen = ScreenGui or Instance.new('ScreenGui')
		Screen.Name = 'FORGE_UI'
		Screen.IgnoreGuiInset = true
		Screen.ResetOnSpawn = false
		Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		Screen.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')

		local Viewport = Instance.new('Frame')
		Viewport.Name = 'Viewport'
		Viewport.BackgroundTransparency = 1
		Viewport.Size = UDim2.fromScale(1, 1)
		Viewport.Parent = Screen

		self.Screen = Screen
		self.Viewport = Viewport
		self.InputRouter:Enable()
		return Screen
	end

	function UIManager:SetWidgetBindingActive(Widget, Active)
		if not Widget then return self end
		local Current = self.BindingWidgets[Widget] == true

		if Active and not Current then
			self.BindingWidgets[Widget] = true
			self.BindingCount += 1

			if not self.BindingConnection then
				self.BindingConnection = RunService.RenderStepped:Connect(function()
					for CurrentWidget in pairs(self.BindingWidgets) do
						if CurrentWidget.Destroyed or not CurrentWidget.Object then
							self.BindingWidgets[CurrentWidget] = nil
							self.BindingCount = math.max(self.BindingCount - 1, 0)
						else
							CurrentWidget:SynchronizeProperties()
						end
					end

					if self.BindingCount <= 0 and self.BindingConnection then
						self.BindingConnection:Disconnect()
						self.BindingConnection = nil
					end
				end)
			end
		elseif not Active and Current then
			self.BindingWidgets[Widget] = nil
			self.BindingCount = math.max(self.BindingCount - 1, 0)
			if self.BindingCount <= 0 and self.BindingConnection then
				self.BindingConnection:Disconnect()
				self.BindingConnection = nil
			end
		end

		return self
	end

	function UIManager:RegisterWidgetTree(Widget)
		Widget:_SetManager(self)
		self.InputRouter:Register(Widget)
		self:SetWidgetBindingActive(Widget, next(Widget.Bindings or {}) ~= nil)
		for _, Child in ipairs(Widget.Children or {}) do self:RegisterWidgetTree(Child) end
		return Widget
	end

	function UIManager:UnregisterWidgetTree(Widget)
		for _, Child in ipairs(Widget.Children or {}) do self:UnregisterWidgetTree(Child) end
		self:SetWidgetBindingActive(Widget, false)
		self.InputRouter:Unregister(Widget)
		if self.FocusedWidget == Widget then self:SetFocusedWidget(nil) end
		Widget:_SetManager(nil)
		return Widget
	end

	function UIManager:GetLayer(Name, ZIndex)
		self:Initialize()
		if self.Layers[Name] then return self.Layers[Name] end

		local Layer = Instance.new('Frame')
		Layer.Name = Name
		Layer.BackgroundTransparency = 1
		Layer.Size = UDim2.fromScale(1, 1)
		Layer.ZIndex = ZIndex or 1
		Layer.Parent = self.Viewport
		self.Layers[Name] = Layer
		return Layer
	end

	function UIManager:AddToViewport(Widget, ZOrder, LayerName)
		self:Initialize()
		if self.Widgets[Widget] then return Widget end
		if Widget.Parent then Widget:RemoveFromParent() end
		local Layer = self:GetLayer(LayerName or 'Game', ZOrder or 1)
		Widget.Object.ZIndex = ZOrder or 1
		self:RegisterWidgetTree(Widget)
		Widget:Mount(Layer)
		if Widget.Construct then Widget:Construct() end
		self.Widgets[Widget] = true
		return Widget
	end

	function UIManager:RemoveFromViewport(Widget)
		if not self.Widgets[Widget] then return false end
		if Widget.Destruct then Widget:Destruct() end
		if self.FocusedWidget and (self.FocusedWidget == Widget or self.FocusedWidget:IsDescendantOf(Widget)) then self:SetFocusedWidget(nil) end
		Widget:Unmount()
		self:UnregisterWidgetTree(Widget)
		self.Widgets[Widget] = nil
		return true
	end

	function UIManager:GetFocusPath(Widget)
		local Path = {}
		local Current = Widget
		while Current do
			table.insert(Path, 1, Current)
			Current = Current.Parent
		end
		return Path
	end

	function UIManager:SetFocusedWidget(Widget)
		if Widget and (Widget.Manager ~= self or not Widget:IsFocusable()) then return self end
		if Widget == self.FocusedWidget then return self end

		local Previous = self.FocusedWidget
		local OldPath = Previous and self:GetFocusPath(Previous) or {}
		local NewPath = Widget and self:GetFocusPath(Widget) or {}
		local Shared = 0
		while OldPath[Shared + 1] and OldPath[Shared + 1] == NewPath[Shared + 1] do Shared += 1 end

		self.FocusedWidget = Widget
		for Index = #OldPath, Shared + 1, -1 do OldPath[Index].OnRemovedFromFocusPath:Fire(Previous, Widget) end
		for Index = Shared + 1, #NewPath do NewPath[Index].OnAddedToFocusPath:Fire(Widget, Previous) end
		return self
	end

	function UIManager:GetFocusedWidget()
		return self.FocusedWidget
	end

	function UIManager:ValidateFocus(ChangedRoot)
		local Focused = self.FocusedWidget
		if not Focused then return self end
		if ChangedRoot and Focused ~= ChangedRoot and not Focused:IsDescendantOf(ChangedRoot) then return self end
		if Focused.Manager ~= self or not Focused:IsFocusable() then self:SetFocusedWidget(nil) end
		return self
	end

	function UIManager:GetFocusableWidgets(Root)
		local Result = {}
		local function Visit(Widget)
			if Widget ~= Root and Widget:IsFocusable() then table.insert(Result, Widget) end
			for _, Child in ipairs(Widget.Children or {}) do Visit(Child) end
		end
		if Root then Visit(Root) else
			for Widget in pairs(self.Widgets) do Visit(Widget) end
		end
		return Result
	end

	function UIManager:FindSpatialTarget(Current, Direction)
		local Origin = Current.Object.AbsolutePosition + Current.Object.AbsoluteSize / 2
		local Best, BestScore

		for _, Candidate in ipairs(self:GetFocusableWidgets(Current:GetRootWidget())) do
			if Candidate ~= Current then
				local Center = Candidate.Object.AbsolutePosition + Candidate.Object.AbsoluteSize / 2
				local Delta = Center - Origin
				local Primary, Secondary

				if Direction == 'Up' then Primary, Secondary = -Delta.Y, math.abs(Delta.X)
				elseif Direction == 'Down' then Primary, Secondary = Delta.Y, math.abs(Delta.X)
				elseif Direction == 'Left' then Primary, Secondary = -Delta.X, math.abs(Delta.Y)
				elseif Direction == 'Right' then Primary, Secondary = Delta.X, math.abs(Delta.Y) end

				if Primary and Primary > 0 then
					local Score = Primary + Secondary * 2
					if not BestScore or Score < BestScore then Best, BestScore = Candidate, Score end
				end
			end
		end
		return Best
	end

	function UIManager:Navigate(Direction, From)
		assert(Enums.NavigationDirection[Direction], 'Invalid navigation direction.')
		local Current = From or self.FocusedWidget
		if not Current then
			local Widgets = self:GetFocusableWidgets()
			if Widgets[1] then self:SetFocusedWidget(Widgets[1]) end
			return Widgets[1]
		end

		local Config = Current.Navigation[Direction]
		if Config then
			if Config.Rule == 'Stop' then return Current end
			if Config.Rule == 'Explicit' then
				local Target = type(Config.Target) == 'function' and Config.Target(Current) or Config.Target
				if Target and Target:IsFocusable() then self:SetFocusedWidget(Target) return Target end
				return Current
			end
			if Config.Rule == 'Escape' then self:SetFocusedWidget(nil) return nil end
		end

		local Widgets = self:GetFocusableWidgets(Current:GetRootWidget())
		if Direction == 'Next' or Direction == 'Previous' then
			local Index = table.find(Widgets, Current) or 1
			local Step = Direction == 'Next' and 1 or -1
			local NextIndex = Index + Step
			local Wrap = Config and Config.Rule == 'Wrap'
			if Wrap then NextIndex = ((NextIndex - 1) % #Widgets) + 1 end
			local Target = Widgets[NextIndex]
			if Target then self:SetFocusedWidget(Target) return Target end
			return Current
		end

		if SpatialDirections[Direction] then
			local Target = self:FindSpatialTarget(Current, Direction)
			if not Target and Config and Config.Rule == 'Wrap' then
				local Best, BestDistance
				local Origin = Current.Object.AbsolutePosition + Current.Object.AbsoluteSize / 2
				for _, Candidate in ipairs(Widgets) do
					if Candidate ~= Current then
						local Center = Candidate.Object.AbsolutePosition + Candidate.Object.AbsoluteSize / 2
						local Distance = (Center - Origin).Magnitude
						if not BestDistance or Distance > BestDistance then Best, BestDistance = Candidate, Distance end
					end
				end
				Target = Best
			end
			if Target then self:SetFocusedWidget(Target) return Target end
		end

		return Current
	end

	function UIManager:SetInputMode(Mode)
		assert(Mode == 'GameOnly' or Mode == 'UIOnly' or Mode == 'GameAndUI', 'Invalid input mode.')
		self.InputMode = Mode
		if Mode == 'GameOnly' then self:SetFocusedWidget(nil) end
		return self
	end

	function UIManager:Destroy()
		self:SetFocusedWidget(nil)
		for Widget in pairs(self.Widgets) do
			if Widget.Destruct then Widget:Destruct() end
			Widget:Unmount()
			self:UnregisterWidgetTree(Widget)
		end
		self.InputRouter:Destroy()
		if self.BindingConnection then self.BindingConnection:Disconnect(); self.BindingConnection = nil end
		self.BindingCount = 0
		table.clear(self.BindingWidgets)
		table.clear(self.Widgets)
		table.clear(self.Layers)
		if self.Screen then self.Screen:Destroy() end
		self.Screen = nil
		self.Viewport = nil
	end
end

return UIManager;