local Widget = require(script.Parent.Widget)
local PanelSlot = require(script.Parent.PanelSlot)

local PanelWidget = setmetatable({}, Widget) do
	PanelWidget.__index = PanelWidget
	PanelWidget.ClassName = 'PanelWidget'

	function PanelWidget.new(Object)
		return setmetatable(Widget.new(Object), PanelWidget)
	end

	function PanelWidget:CreateSlot(Content)
		return PanelSlot.new(self, Content)
	end

	function PanelWidget:AddChild(Content)
		assert(type(Content) == 'table' and Content.Object, 'PanelWidget child must be a Widget.')
		assert(not Content.Destroyed, 'Cannot add a destroyed Widget.')
		if Content.Parent then
			Content:RemoveFromParent()
		elseif Content.Manager and Content.Manager.Widgets and Content.Manager.Widgets[Content] then
			Content.Manager:RemoveFromViewport(Content)
		elseif Content.Mounted then
			Content:Unmount()
		end

		local Slot = self:CreateSlot(Content)
		Content.Parent = self
		Content.Slot = Slot
		Content.Object.Parent = self.Object
		table.insert(self.Children, Content)

		if self.Manager then self.Manager:RegisterWidgetTree(Content) end
		if self.Mounted then Content:_MountTree() end
		self:InvalidateLayout()
		return Slot
	end

	function PanelWidget:RemoveChild(Content)
		for Index, Child in ipairs(self.Children) do
			if Child == Content then
				if Child.Mounted then Child:_UnmountTree() end
				if self.Manager then self.Manager:UnregisterWidgetTree(Child) end
				table.remove(self.Children, Index)
				Child.Parent = nil
				Child.Slot = nil
				Child.Object.Parent = nil
				self:InvalidateLayout()
				return true
			end
		end
		return false
	end

	function PanelWidget:ClearChildren()
		for Index = #self.Children, 1, -1 do self:RemoveChild(self.Children[Index]) end
		return self
	end

	function PanelWidget:DestroyChildren()
		for Index = #self.Children, 1, -1 do self.Children[Index]:Destroy() end
		return self
	end

	function PanelWidget:GetChildren()
		return table.clone(self.Children)
	end

	function PanelWidget:GetChildAt(Index)
		return self.Children[Index]
	end

	function PanelWidget:GetChildrenCount()
		return #self.Children
	end

	function PanelWidget:GetChildIndex(Content)
		for Index, Child in ipairs(self.Children) do
			if Child == Content then return Index end
		end
		return 0
	end

	function PanelWidget:InvalidateLayout()
		for _, Child in ipairs(self.Children) do
			if Child.Slot then Child.Slot:Apply() end
		end
		return self
	end
end

return PanelWidget;