local PanelWidget = require(script.Parent.PanelWidget)

local ContentWidget = setmetatable({}, PanelWidget) do
	ContentWidget.__index = ContentWidget
	ContentWidget.ClassName = 'ContentWidget'

	function ContentWidget.new(Object)
		return setmetatable(PanelWidget.new(Object), ContentWidget)
	end

	function ContentWidget:SetContent(Content)
		self:ClearChildren()
		if Content then self:AddChild(Content) end
		return self
	end

	function ContentWidget:GetContent()
		return self.Children[1]
	end

	function ContentWidget:GetContentSlot()
		local Content = self:GetContent()
		return Content and Content.Slot or nil
	end

	function ContentWidget:AddChild(Content)
		assert(#self.Children == 0, self.ClassName .. ' can only contain one child.')
		return PanelWidget.AddChild(self, Content)
	end
end

return ContentWidget;