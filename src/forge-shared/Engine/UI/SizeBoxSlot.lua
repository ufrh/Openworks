local PanelSlot = require(script.Parent.PanelSlot)

local SizeBoxSlot = setmetatable({}, PanelSlot) do
	SizeBoxSlot.__index = SizeBoxSlot
	SizeBoxSlot.ClassName = 'SizeBoxSlot'

	function SizeBoxSlot.new(Parent, Content)
		return setmetatable(PanelSlot.new(Parent, Content), SizeBoxSlot)
	end
end

return SizeBoxSlot;