local Signal = require(script.Parent.Parent.Parent.Kernel.Core.Signal)
local Enums = require(script.Parent.Enums)

local Widget = {} do
	Widget.__index = Widget
	Widget.ClassName = 'Widget'

	local SignalNames = {
		'OnInitialized', 'OnMounted', 'OnUnmounted', 'OnAddedToFocusPath', 'OnRemovedFromFocusPath',
		'OnVisibilityChanged', 'OnEnabledChanged', 'OnMouseEnter', 'OnMouseLeave', 'OnMouseMove',
		'OnPointerDown', 'OnPointerUp', 'OnClicked', 'OnKeyDown', 'OnKeyUp', 'OnDestroyed'
	}

	local function ApplyVisibility(self)
		if not self.Object then return end
		local Visibility = self.Visibility
		self.Object.Visible = self.InternalVisible ~= false and Visibility ~= Enums.Visibility.Hidden and Visibility ~= Enums.Visibility.Collapsed
		self.Object.Interactable = self.Enabled and Visibility ~= Enums.Visibility.HitTestInvisible and Visibility ~= Enums.Visibility.SelfHitTestInvisible
	end

	function Widget.new(Object)
		assert(typeof(Object) == 'Instance' and Object:IsA('GuiObject'), 'Widget requires a GuiObject.')

		local self = setmetatable({}, Widget)
		self.Object = Object
		self.Name = Object.Name
		self.Parent = nil
		self.Slot = nil
		self.Children = {}
		self.Visibility = Enums.Visibility.Visible
		self.Enabled = true
		self.RenderOpacity = 1
		self.Bindings = {}
		self.BindingConnections = {}
		self.Focusable = Object:IsA('GuiButton') or Object:IsA('TextBox')
		self.Animations = {}
		self.Navigation = {}
		self.EventHandlers = {}
		self.Connections = {}
		self.Manager = nil
		self.Initialized = false
		self.Mounted = false
		self.Destroyed = false
		self.InternalVisible = true

		for _, Name in ipairs(SignalNames) do self[Name] = Signal.new() end
		ApplyVisibility(self)
		self:Initialize()
		return self
	end

	function Widget:NativeOnInitialized()
	end

	function Widget:NativeOnMounted()
	end

	function Widget:NativeOnUnmounted()
	end

	function Widget:Initialize()
		if self.Initialized then return self end
		self.Initialized = true
		self:NativeOnInitialized()
		self.OnInitialized:Fire()
		return self
	end

	function Widget:SetName(Name)
		self.Name = Name
		self.Object.Name = Name
		return self
	end

	function Widget:GetObject()
		return self.Object
	end

	function Widget:GetParent()
		return self.Parent
	end

	function Widget:GetSlot()
		return self.Slot
	end

	function Widget:GetRootWidget()
		local Current = self
		while Current.Parent do Current = Current.Parent end
		return Current
	end

	function Widget:IsDescendantOf(Widget)
		local Current = self.Parent
		while Current do
			if Current == Widget then return true end
			Current = Current.Parent
		end
		return false
	end

	function Widget:SetVisibility(Visibility)
		assert(Enums.Visibility[Visibility], 'Invalid widget visibility.')
		if self.Visibility == Visibility then return self end
		self.Visibility = Visibility
		ApplyVisibility(self)
		if self.Parent and self.Parent.InvalidateLayout then self.Parent:InvalidateLayout() end
		self.OnVisibilityChanged:Fire(Visibility)
		if self.Manager then self.Manager:ValidateFocus(self) end
		return self
	end

	function Widget:IsVisible()
		if not self.InternalVisible or self.Visibility == Enums.Visibility.Hidden or self.Visibility == Enums.Visibility.Collapsed then return false end
		local Current = self.Parent
		while Current do
			if not Current.InternalVisible or Current.Visibility == Enums.Visibility.Hidden or Current.Visibility == Enums.Visibility.Collapsed then return false end
			Current = Current.Parent
		end
		return true
	end

	function Widget:_SetInternalVisible(Visible)
		self.InternalVisible = Visible ~= false
		ApplyVisibility(self)
		if self.Object then self.Object.Visible = self.InternalVisible and self.Visibility ~= Enums.Visibility.Hidden and self.Visibility ~= Enums.Visibility.Collapsed end
		if self.Manager then self.Manager:ValidateFocus(self) end
		return self
	end

	function Widget:IsHitTestVisible()
		if not self.Enabled or not self:IsVisible() then return false end
		if self.Visibility == Enums.Visibility.HitTestInvisible or self.Visibility == Enums.Visibility.SelfHitTestInvisible then return false end
		return self.Object.Interactable
	end

	function Widget:SetEnabled(Enabled)
		self.Enabled = Enabled == true
		ApplyVisibility(self)
		self.OnEnabledChanged:Fire(self.Enabled)
		if self.Manager then self.Manager:ValidateFocus(self) end
		return self
	end

	function Widget:SetRenderOpacity(Opacity)
		self.RenderOpacity = math.clamp(Opacity, 0, 1)
		if self.Object:IsA('CanvasGroup') then self.Object.GroupTransparency = 1 - self.RenderOpacity end
		return self
	end

	function Widget:SetZOrder(ZIndex)
		self.Object.ZIndex = ZIndex
		return self
	end

	function Widget:SetNavigation(Direction, Rule, Target)
		assert(Enums.NavigationDirection[Direction], 'Invalid navigation direction.')
		assert(Enums.NavigationRule[Rule], 'Invalid navigation rule.')
		self.Navigation[Direction] = {Rule = Rule, Target = Target}
		return self
	end

	function Widget:SetFocusable(Focusable)
		self.Focusable = Focusable == true
		self.Object.Selectable = self.Focusable
		if self.Manager then self.Manager:ValidateFocus(self) end
		return self
	end

	function Widget:IsFocusable()
		if not self.Focusable or not self.Enabled or not self:IsVisible() or self.Destroyed then return false end
		local Current = self.Parent
		while Current do
			if not Current.Enabled then return false end
			Current = Current.Parent
		end
		return true
	end

	function Widget:Navigate(Direction)
		if self.Manager then return self.Manager:Navigate(Direction, self) end
	end

	function Widget:SetKeyboardFocus()
		if self.Manager then self.Manager:SetFocusedWidget(self) end
		return self
	end

	function Widget:ClearKeyboardFocus()
		if self.Manager and self.Manager:GetFocusedWidget() == self then self.Manager:SetFocusedWidget(nil) end
		return self
	end

	function Widget:HasKeyboardFocus()
		return self.Manager and self.Manager:GetFocusedWidget() == self or false
	end

	function Widget:_ApplyBinding(Property)
		local Binding = self.Bindings[Property]
		if not Binding or not self.Object then return self end
		local Success, Value = pcall(Binding.Getter, self)
		if Success then self.Object[Property] = Binding.Transform and Binding.Transform(Value, self) or Value end
		return self
	end

	function Widget:Bind(Property, Source, Transform)
		assert(type(Property) == 'string', 'Widget binding property must be a string.')
		self:Unbind(Property)

		if type(Source) == 'function' then
			self.Bindings[Property] = {Getter = Source, Transform = Transform, Reactive = false}
		elseif type(Source) == 'table' and type(Source.Get) == 'function' and Source.Changed then
			self.Bindings[Property] = {
				Getter = function() return Source:Get() end,
				Transform = Transform,
				Reactive = true
			}
			self.BindingConnections[Property] = Source.Changed:Connect(function()
				self:_ApplyBinding(Property)
			end)
		else
			error('Widget binding requires a getter function or reactive State.')
		end

		self:_ApplyBinding(Property)
		if self.Manager and self.Manager.SetWidgetBindingActive then self.Manager:SetWidgetBindingActive(self, true) end
		return self
	end

	function Widget:BindState(Property, State, Transform)
		return self:Bind(Property, State, Transform)
	end

	function Widget:Unbind(Property)
		local Connection = self.BindingConnections[Property]
		if Connection then Connection:Disconnect() self.BindingConnections[Property] = nil end
		self.Bindings[Property] = nil
		if self.Manager and self.Manager.SetWidgetBindingActive then
			self.Manager:SetWidgetBindingActive(self, next(self.Bindings) ~= nil)
		end
		return self
	end

	function Widget:SynchronizeProperties()
		for Property, Binding in pairs(self.Bindings) do
			if not Binding.Reactive then self:_ApplyBinding(Property) end
		end
		return self
	end

	function Widget:On(EventName, Callback)
		assert(type(Callback) == 'function', 'Widget event callback must be a function.')
		self.EventHandlers[EventName] = self.EventHandlers[EventName] or {}
		table.insert(self.EventHandlers[EventName], Callback)
		return self
	end

	function Widget:HandleEvent(EventName, Event)
		local SignalObject = self['On' .. EventName]
		if SignalObject then SignalObject:Fire(Event) end
		for _, Callback in ipairs(self.EventHandlers[EventName] or {}) do
			if Callback(Event) == true then Event:Handle() end
			if Event.Stopped then break end
		end
		return Event.Handled
	end

	function Widget:AddAnimation(Name, Animation)
		self.Animations[Name] = Animation
		return Animation
	end

	function Widget:PlayAnimation(Name, ...)
		local Animation = self.Animations[Name]
		assert(Animation, string.format('Animation %q does not exist on %s.', Name, self.Name))
		return Animation:Play(self, ...)
	end

	function Widget:StopAnimation(Name)
		local Animation = self.Animations[Name]
		if Animation then Animation:Stop(self) end
		return self
	end

	function Widget:_SetManager(Manager)
		self.Manager = Manager
		return self
	end

	function Widget:_MountTree()
		if self.Mounted then return self end
		self.Mounted = true
		self:NativeOnMounted()
		self.OnMounted:Fire()
		for _, Child in ipairs(self.Children) do Child:_MountTree() end
		return self
	end

	function Widget:_UnmountTree()
		if not self.Mounted then return self end
		for Index = #self.Children, 1, -1 do self.Children[Index]:_UnmountTree() end
		self.Mounted = false
		self:NativeOnUnmounted()
		self.OnUnmounted:Fire()
		return self
	end

	function Widget:Mount(Parent)
		assert(not self.Destroyed, 'Cannot mount a destroyed Widget.')
		local Target = type(Parent) == 'table' and Parent.Object or Parent
		assert(typeof(Target) == 'Instance', 'Widget mount target must be an Instance or Widget.')
		self.Object.Parent = Target
		return self:_MountTree()
	end

	function Widget:Unmount()
		if not self.Mounted then return self end
		self:_UnmountTree()
		self.Object.Parent = nil
		return self
	end

	function Widget:RemoveFromParent()
		if self.Parent and self.Parent.RemoveChild then self.Parent:RemoveChild(self) else self:Unmount() end
		return self
	end

	function Widget:Destroy()
		if self.Destroyed then return end
		local Manager = self.Manager
		if not self.Parent and Manager and Manager.Widgets and Manager.Widgets[self] then
			Manager:RemoveFromViewport(self)
		end
		self.Destroyed = true
		if self.Parent and self.Parent.RemoveChild then self.Parent:RemoveChild(self) end
		for Index = #self.Children, 1, -1 do self.Children[Index]:Destroy() end
		for _, Animation in pairs(self.Animations) do if Animation.Destroy then Animation:Destroy() end end
		for _, Connection in ipairs(self.Connections) do Connection:Disconnect() end
		for _, Connection in pairs(self.BindingConnections) do Connection:Disconnect() end
		self.OnDestroyed:Fire()
		for _, Name in ipairs(SignalNames) do self[Name]:Destroy() end
		if self.Manager and self.Manager.SetWidgetBindingActive then self.Manager:SetWidgetBindingActive(self, false) end
		if self.Manager and self.Manager.InputRouter then self.Manager.InputRouter:Unregister(self) end
		if self.Object then self.Object:Destroy() end
		self.Object = nil
		self.Manager = nil
		table.clear(self.Children)
		table.clear(self.Bindings)
		table.clear(self.BindingConnections)
		table.clear(self.Animations)
		table.clear(self.EventHandlers)
	end
end

return Widget;