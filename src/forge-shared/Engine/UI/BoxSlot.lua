local Slot = require(script.Parent.Slot)

local BoxSlot = setmetatable({}, Slot) do
	BoxSlot.__index = BoxSlot
	BoxSlot.ClassName = 'BoxSlot'

	function BoxSlot.new(Parent, Content)
		local self = setmetatable(Slot.new(Parent, Content), BoxSlot)
		self.Size = nil
		self.Fill = 0
		self.Auto = false
		return self
	end

	function BoxSlot:SetSize(Size)
		assert(typeof(Size) == 'UDim2', 'BoxSlot size must be a UDim2.')
		self.Size = Size
		self.Fill = 0
		self.Auto = false
		self:Apply()
		return self
	end

	function BoxSlot:SetAuto()
		self.Size = nil
		self.Fill = 0
		self.Auto = true
		self:Apply()
		return self
	end

	function BoxSlot:SetFill(Weight)
		self.Size = nil
		self.Fill = math.max(tonumber(Weight) or 1, 0)
		self.Auto = false
		self:Apply()
		return self
	end

	function BoxSlot:Apply()
		local Object, Parent = self.Content and self.Content.Object, self.Parent
		if not Object or not Parent then return self end

		Object.LayoutOrder = Parent:GetChildIndex(self.Content)
		if self.Size then Object.Size = self.Size end
		if Parent.ApplyLayout then Parent:ApplyLayout() end
		return self
	end
end

return BoxSlot;
