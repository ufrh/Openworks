local Enums = require(script.Parent.Enums)

local Slot = {} do
	Slot.__index = Slot
	Slot.ClassName = 'Slot'

	local function NormalizePadding(Left, Top, Right, Bottom)
		if type(Left) == 'table' then
			return {Left[1] or Left.Left or 0, Left[2] or Left.Top or 0, Left[3] or Left.Right or 0, Left[4] or Left.Bottom or 0}
		end

		Left = Left or 0
		return {Left, Top or Left, Right or Left, Bottom or Top or Left}
	end

	function Slot.new(Parent, Content)
		local self = setmetatable({}, Slot)
		self.Parent = Parent
		self.Content = Content
		self.Padding = {0, 0, 0, 0}
		self.HorizontalAlignment = Enums.HorizontalAlignment.Fill
		self.VerticalAlignment = Enums.VerticalAlignment.Fill
		return self
	end

	function Slot:SetPadding(Left, Top, Right, Bottom)
		self.Padding = NormalizePadding(Left, Top, Right, Bottom)
		self:Apply()
		return self
	end

	function Slot:SetHorizontalAlignment(Alignment)
		assert(Enums.HorizontalAlignment[Alignment], 'Invalid horizontal alignment.')
		self.HorizontalAlignment = Alignment
		self:Apply()
		return self
	end

	function Slot:SetVerticalAlignment(Alignment)
		assert(Enums.VerticalAlignment[Alignment], 'Invalid vertical alignment.')
		self.VerticalAlignment = Alignment
		self:Apply()
		return self
	end

	function Slot:GetPadding()
		return table.unpack(self.Padding)
	end

	function Slot:Apply()
		return self
	end
end

return Slot;