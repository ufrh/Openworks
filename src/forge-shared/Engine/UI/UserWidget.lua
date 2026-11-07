local RunService = game:GetService('RunService')
local Widget = require(script.Parent.Widget)
local WidgetTree = require(script.Parent.WidgetTree)
local Signal = require(script.Parent.Parent.Parent.Kernel.Core.Signal)

local UserWidget = setmetatable({}, Widget) do
	UserWidget.__index = UserWidget
	UserWidget.ClassName = 'UserWidget'

	function UserWidget.new(Name)
		local Object = Instance.new('Frame')
		Object.Name = Name or 'UserWidget'
		Object.BackgroundTransparency = 1
		Object.BorderSizePixel = 0
		Object.Size = UDim2.fromScale(1, 1)

		local self = setmetatable(Widget.new(Object), UserWidget)
		self.ClassName = 'UserWidget'
		self.WidgetTree = WidgetTree.new()
		self.Constructed = false
		self.ViewportConnection = nil
		self.OnConstructed = Signal.new()
		self.OnDestructed = Signal.new()
		return self
	end

	function UserWidget:NativePreConstruct()
	end

	function UserWidget:NativeConstruct()
	end

	function UserWidget:NativeTick(DeltaTime)
	end

	function UserWidget:NativeDestruct()
	end

	function UserWidget:SetRootWidget(RootWidget)
		local Previous = self.WidgetTree:GetRootWidget()
		if Previous == RootWidget then return RootWidget end

		if Previous then
			if Previous.Mounted then Previous:_UnmountTree() end
			if self.Manager then self.Manager:UnregisterWidgetTree(Previous) end
			Previous.Parent = nil
			Previous.Object.Parent = nil
		end

		table.clear(self.Children)
		self.WidgetTree:SetRootWidget(RootWidget)

		if RootWidget then
			if RootWidget.Parent then
				RootWidget:RemoveFromParent()
			elseif RootWidget.Manager and RootWidget.Manager.Widgets and RootWidget.Manager.Widgets[RootWidget] then
				RootWidget.Manager:RemoveFromViewport(RootWidget)
			elseif RootWidget.Mounted then
				RootWidget:Unmount()
			end
			RootWidget.Parent = self
			RootWidget.Object.Parent = self.Object
			RootWidget.Object.Size = UDim2.fromScale(1, 1)
			table.insert(self.Children, RootWidget)
			if self.Manager then self.Manager:RegisterWidgetTree(RootWidget) end
			if self.Mounted then RootWidget:_MountTree() end
		end
		return RootWidget
	end

	function UserWidget:GetWidgetFromName(Name)
		return self.WidgetTree:FindWidget(Name)
	end

	function UserWidget:Construct()
		if self.Constructed then return self end
		self:NativePreConstruct()
		self:NativeConstruct()
		self.Constructed = true
		self.OnConstructed:Fire()

		if RunService:IsClient() and self.NativeTick ~= UserWidget.NativeTick then
			self.ViewportConnection = RunService.RenderStepped:Connect(function(DeltaTime)
				self:NativeTick(DeltaTime)
			end)
		end
		return self
	end

	function UserWidget:Destruct()
		if not self.Constructed then return self end
		if self.ViewportConnection then self.ViewportConnection:Disconnect() self.ViewportConnection = nil end
		self:NativeDestruct()
		self.Constructed = false
		self.OnDestructed:Fire()
		return self
	end

	function UserWidget:Destroy()
		self:Destruct()
		self.OnConstructed:Destroy()
		self.OnDestructed:Destroy()
		Widget.Destroy(self)
	end
end

return UserWidget;