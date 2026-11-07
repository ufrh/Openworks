local Slot = require(script.Parent.Slot)
local Enums = require(script.Parent.Enums)

local PanelSlot = setmetatable({}, Slot) do
	PanelSlot.__index = PanelSlot
	PanelSlot.ClassName = 'PanelSlot'

	function PanelSlot.new(Parent, Content)
		return setmetatable(Slot.new(Parent, Content), PanelSlot)
	end

	function PanelSlot:Apply()
		local Object = self.Content and self.Content.Object
		if not Object then return self end

		local Left, Top, Right, Bottom = self:GetPadding()
		local Horizontal, Vertical = self.HorizontalAlignment, self.VerticalAlignment

		if Horizontal == Enums.HorizontalAlignment.Fill then
			Object.AnchorPoint = Vector2.new(0, Object.AnchorPoint.Y)
			Object.Position = UDim2.new(0, Left, Object.Position.Y.Scale, Object.Position.Y.Offset)
			Object.Size = UDim2.new(1, -(Left + Right), Object.Size.Y.Scale, Object.Size.Y.Offset)
		elseif Horizontal == Enums.HorizontalAlignment.Left then
			Object.AnchorPoint = Vector2.new(0, Object.AnchorPoint.Y)
			Object.Position = UDim2.new(0, Left, Object.Position.Y.Scale, Object.Position.Y.Offset)
		elseif Horizontal == Enums.HorizontalAlignment.Center then
			Object.AnchorPoint = Vector2.new(.5, Object.AnchorPoint.Y)
			Object.Position = UDim2.new(.5, math.floor((Left - Right) / 2), Object.Position.Y.Scale, Object.Position.Y.Offset)
		else
			Object.AnchorPoint = Vector2.new(1, Object.AnchorPoint.Y)
			Object.Position = UDim2.new(1, -Right, Object.Position.Y.Scale, Object.Position.Y.Offset)
		end

		if Vertical == Enums.VerticalAlignment.Fill then
			Object.AnchorPoint = Vector2.new(Object.AnchorPoint.X, 0)
			Object.Position = UDim2.new(Object.Position.X.Scale, Object.Position.X.Offset, 0, Top)
			Object.Size = UDim2.new(Object.Size.X.Scale, Object.Size.X.Offset, 1, -(Top + Bottom))
		elseif Vertical == Enums.VerticalAlignment.Top then
			Object.AnchorPoint = Vector2.new(Object.AnchorPoint.X, 0)
			Object.Position = UDim2.new(Object.Position.X.Scale, Object.Position.X.Offset, 0, Top)
		elseif Vertical == Enums.VerticalAlignment.Center then
			Object.AnchorPoint = Vector2.new(Object.AnchorPoint.X, .5)
			Object.Position = UDim2.new(Object.Position.X.Scale, Object.Position.X.Offset, .5, math.floor((Top - Bottom) / 2))
		else
			Object.AnchorPoint = Vector2.new(Object.AnchorPoint.X, 1)
			Object.Position = UDim2.new(Object.Position.X.Scale, Object.Position.X.Offset, 1, -Bottom)
		end

		return self
	end
end

return PanelSlot;