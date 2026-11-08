--!strict

-- Navigation emits intent; the FORGE controller owns active mode state.
local ModeBar = {}
ModeBar.__index = ModeBar

function ModeBar.new(gui: PlayerGui, onSwitch: (string) -> ())
	local screen = Instance.new("ScreenGui")
	screen.Name = "OPENWORKS_Modes"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 75
	screen.Parent = gui

	local root = Instance.new("Frame")
	root.Name = "ModeBar"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 12)
	root.Size = UDim2.fromOffset(445, 42)
	root.BackgroundColor3 = Color3.fromRGB(18, 27, 34)
	root.BorderSizePixel = 0
	root.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = root

	local buttons = {}
	for i, name in ipairs({"Free", "Edit", "Assembly", "Simulation"}) do
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.new(1 / 4, -8, 1, -8)
		button.Position = UDim2.new((i - 1) / 4, 4, 0, 4)
		button.BackgroundColor3 = Color3.fromRGB(44, 60, 69)
		button.TextColor3 = Color3.fromRGB(226, 239, 243)
		button.TextSize = 13
		button.Font = Enum.Font.GothamMedium
		button.Text = name
		button.BorderSizePixel = 0
		button.Parent = root

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 5)
		round.Parent = button

		button.Activated:Connect(function()
			onSwitch(name)
		end)
		buttons[name] = button
	end

	local self = setmetatable({gui = screen, buttons = buttons}, ModeBar)
	self:setActive("Free")
	return self
end

function ModeBar:setActive(name: string)
	for id, button in pairs(self.buttons) do
		button.BackgroundColor3 = if id == name
			then Color3.fromRGB(27, 119, 135)
			else Color3.fromRGB(44, 60, 69)
	end
end

function ModeBar:destroy()
	self.gui:Destroy()
end

return ModeBar
