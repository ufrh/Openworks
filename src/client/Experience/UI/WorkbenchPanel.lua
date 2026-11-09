--!strict
local Players = game:GetService("Players")
local Panel = {}
Panel.__index = Panel

function Panel.label(parent: Instance, caption: string, height: number?): TextLabel
	local item = Instance.new("TextLabel")
	item.Size = UDim2.new(1, -16, 0, height or 30)
	item.BackgroundTransparency = 1
	item.TextColor3 = Color3.fromRGB(207, 224, 233)
	item.Font = Enum.Font.Gotham
	item.TextSize = 12
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Text = caption
	item.Parent = parent
	return item
end

function Panel.button(parent: Instance, caption: string, callback: () -> ()): TextButton
	local item = Instance.new("TextButton")
	item.Size = UDim2.new(1, -16, 0, 32)
	item.BackgroundColor3 = Color3.fromRGB(43, 65, 79)
	item.TextColor3 = Color3.fromRGB(233, 243, 248)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamMedium
	item.TextSize = 12
	item.TextWrapped = true
	item.Text = caption
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = item
	item.Activated:Connect(callback)
	return item
end

function Panel.input(parent: Instance, caption: string, value: string): TextBox
	Panel.label(parent, caption, 24)
	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, -16, 0, 32)
	input.BackgroundColor3 = Color3.fromRGB(18, 31, 42)
	input.TextColor3 = Color3.fromRGB(237, 244, 249)
	input.BorderSizePixel = 0
	input.Text = value
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Code
	input.TextSize = 13
	input.Parent = parent
	return input
end

function Panel.list(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

function Panel.clear(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Panel.new(name: string, pages: { string })
	local gui = Instance.new("ScreenGui")
	gui.Name = "OPENWORKS_" .. name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 82
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 66)
	panel.Size = UDim2.new(0, 330, 1, -82)
	panel.BackgroundColor3 = Color3.fromRGB(22, 35, 44)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local title = Panel.label(panel, name:upper(), 24)
	title.Position = UDim2.fromOffset(8, 4)
	local status = Panel.label(panel, "Ready", 64)
	status.Position = UDim2.fromOffset(8, 32)
	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(8, 100)
	tabs.Size = UDim2.new(1, -16, 0, 30)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel
	local self =
		setmetatable({ gui = gui, status = status, pages = {}, tabs = {}, current = nil }, Panel)
	for i, pageName in ipairs(pages) do
		local button = Panel.button(tabs, pageName, function()
			self:show(pageName)
		end)
		button.Position = UDim2.new((i - 1) / #pages, 0, 0, 0)
		button.Size = UDim2.new(1 / #pages, -4, 1, 0)
		local scroll = Instance.new("ScrollingFrame")
		scroll.Position = UDim2.fromOffset(0, 140)
		scroll.Size = UDim2.new(1, 0, 1, -148)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ScrollBarThickness = 4
		scroll.Visible = false
		scroll.Parent = panel
		self.pages[pageName] = Panel.list(scroll)
		self.tabs[pageName] = button
	end
	self:show(pages[1])
	return self
end

function Panel:show(name: string)
	if not self.pages[name] then
		return
	end
	self.current = name
	for key, frame in pairs(self.pages) do
		frame.Parent.Visible = key == name
		self.tabs[key].BackgroundColor3 = if key == name
			then Color3.fromRGB(27, 119, 135)
			else Color3.fromRGB(43, 65, 79)
	end
end
return Panel
