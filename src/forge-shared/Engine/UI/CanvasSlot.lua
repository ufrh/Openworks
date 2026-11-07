local PanelSlot = require(script.Parent.PanelSlot)

local CanvasSlot = setmetatable({}, PanelSlot) do
	CanvasSlot.__index = CanvasSlot
	CanvasSlot.ClassName = 'CanvasSlot'

	local function NormalizeUDim2(Value, Name)
		if typeof(Value) == 'Vector2' then return UDim2.fromOffset(Value.X, Value.Y) end
		assert(typeof(Value) == 'UDim2', Name .. ' must be a UDim2 or Vector2.')
		return Value
	end

	function CanvasSlot.new(Parent, Content)
		local self = setmetatable(PanelSlot.new(Parent, Content), CanvasSlot)
		self.Position = UDim2.fromOffset(0, 0)
		self.Size = UDim2.fromOffset(100, 100)
		self.Anchors = Vector2.zero
		self.Alignment = Vector2.zero
		self.AutoSize = false
		self.ZOrder = 1
		return self
	end

	function CanvasSlot:SetPosition(Position)
		self.Position = NormalizeUDim2(Position, 'CanvasSlot position')
		self:Apply()
		return self
	end

	function CanvasSlot:SetSize(Size)
		self.Size = NormalizeUDim2(Size, 'CanvasSlot size')
		self:Apply()
		return self
	end

	function CanvasSlot:SetAnchors(Anchors)
		assert(typeof(Anchors) == 'Vector2', 'CanvasSlot anchors must be a Vector2.')
		self.Anchors = Anchors
		self:Apply()
		return self
	end

	function CanvasSlot:SetAlignment(Alignment)
		assert(typeof(Alignment) == 'Vector2', 'CanvasSlot alignment must be a Vector2.')
		self.Alignment = Alignment
		self:Apply()
		return self
	end

	function CanvasSlot:SetAutoSize(AutoSize)
		self.AutoSize = AutoSize == true
		self:Apply()
		return self
	end

	function CanvasSlot:SetZOrder(ZOrder)
		self.ZOrder = math.floor(ZOrder or 1)
		self:Apply()
		return self
	end

	function CanvasSlot:Apply()
		local Object = self.Content and self.Content.Object
		if not Object then return self end

		Object.AnchorPoint = self.Alignment
		Object.Position = UDim2.new(
			self.Anchors.X + self.Position.X.Scale,
			self.Position.X.Offset,
			self.Anchors.Y + self.Position.Y.Scale,
			self.Position.Y.Offset
		)
		Object.Size = self.Size
		Object.AutomaticSize = self.AutoSize and Enum.AutomaticSize.XY or Enum.AutomaticSize.None
		Object.ZIndex = self.ZOrder
		return self
	end
end

return CanvasSlot;
