local Slot = require(script.Parent.Slot)

local GridSlot = setmetatable({}, Slot) do
	GridSlot.__index = GridSlot
	GridSlot.ClassName = 'GridSlot'

	function GridSlot.new(Parent, Content)
		local self = setmetatable(Slot.new(Parent, Content), GridSlot)
		self.Row = 0
		self.Column = 0
		return self
	end

	function GridSlot:SetRow(Row)
		self.Row = math.max(math.floor(Row or 0), 0)
		self:Apply()
		return self
	end

	function GridSlot:SetColumn(Column)
		self.Column = math.max(math.floor(Column or 0), 0)
		self:Apply()
		return self
	end

	function GridSlot:SetRowColumn(Row, Column)
		self.Row = math.max(math.floor(Row or 0), 0)
		self.Column = math.max(math.floor(Column or 0), 0)
		self:Apply()
		return self
	end

	function GridSlot:Apply()
		local Object, Parent = self.Content and self.Content.Object, self.Parent
		if not Object or not Parent then return self end
		Object.LayoutOrder = self.Row * Parent.MaxColumns + self.Column
		return self
	end
end

return GridSlot;