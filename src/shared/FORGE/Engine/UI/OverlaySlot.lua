local PanelSlot = require(script.Parent.PanelSlot)

local OverlaySlot = setmetatable({}, PanelSlot) do
	OverlaySlot.__index = OverlaySlot
	OverlaySlot.ClassName = 'OverlaySlot'

	function OverlaySlot.new(Parent, Content)
		local self = setmetatable(PanelSlot.new(Parent, Content), OverlaySlot)
		self.ZOrder = 1
		return self
	end

	function OverlaySlot:SetZOrder(ZOrder)
		self.ZOrder = ZOrder
		self:Apply()
		return self
	end

	function OverlaySlot:Apply()
		PanelSlot.Apply(self)
		if self.Content and self.Content.Object then self.Content.Object.ZIndex = self.ZOrder end
		return self
	end
end

return OverlaySlot;