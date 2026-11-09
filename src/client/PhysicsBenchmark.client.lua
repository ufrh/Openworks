--!strict
-- Controls and copyable results for the server-owned physics laboratory.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("OWPhysicsBenchmarkRemote", 15)
if not remote then return end

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "OWPhysicsBenchmarkUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function panel(parent, name, size, pos)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size, f.Position = size, pos
	f.BackgroundColor3 = Color3.fromRGB(23, 30, 41)
	f.BorderSizePixel = 0
	f.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f
	return f
end

local function label(parent, text, height, size)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -20, 0, height)
	t.Text = text
	t.Font = Enum.Font.Gotham
	t.TextColor3 = Color3.fromRGB(233, 241, 249)
	t.TextSize = size or 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Parent = parent
	return t
end

local root = panel(gui, "Controls", UDim2.fromOffset(430, 290), UDim2.fromOffset(15, 70))
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 12), UDim.new(0, 10)
pad.Parent = root
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.Parent = root

local heading = label(root, "OPENWORKS  /  PHYSICS LAB", 24, 17)
heading.Font = Enum.Font.GothamBold
local current = label(root, "Loading test...", 38, 14)
local status = label(root, "Waiting for server", 42, 13)
status.TextColor3 = Color3.fromRGB(150, 192, 211)

local function button(parent, title, action, width)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 34)
	b.Text = title
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = Color3.fromRGB(242, 249, 253)
	b.BackgroundColor3 = Color3.fromRGB(49, 75, 92)
	b.BorderSizePixel = 0
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	if action then
		b.Activated:Connect(function()
			remote:FireServer(action)
		end)
	end
	return b
end

local row1 = Instance.new("Frame")
row1.Size, row1.BackgroundTransparency = UDim2.new(1, -18, 0, 34), 1
row1.Parent = root
local line1 = Instance.new("UIListLayout")
line1.FillDirection = Enum.FillDirection.Horizontal
line1.Padding = UDim.new(0, 5)
line1.Parent = row1
button(row1, "◀ Previous", "prev", 93)
button(row1, "Next ▶", "next", 79)
button(row1, "Run Test", "run", 79)
button(row1, "Run All 17", "all", 108)

local row2 = Instance.new("Frame")
row2.Size, row2.BackgroundTransparency = UDim2.new(1, -18, 0, 34), 1
row2.Parent = root
local line2 = Instance.new("UIListLayout")
line2.FillDirection, line2.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 5)
line2.Parent = row2
button(row2, "Stop", "stop", 77)
button(row2, "Export CSV", "export", 116)
local focusAll = button(row2, "Focus All", nil, 110)
focusAll.Activated:Connect(function()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 110, 160), Vector3.new(0, 6, 0))
end)

local cameras = Instance.new("Frame")
cameras.Size, cameras.BackgroundTransparency = UDim2.new(1, -18, 0, 34), 1
cameras.Parent = root
local line3 = Instance.new("UIListLayout")
line3.FillDirection, line3.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 5)
line3.Parent = cameras
for i, value in ipairs({ "0.375", "0.5", "0.75", "1.0", "1.5" }) do
	local b = button(cameras, value, nil, 70)
	b.Activated:Connect(function()
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local target = Vector3.new((i - 3) * 38, 6, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(16, 16, 25), target)
	end)
end
local footer = label(root, "5 scales • 4 phases • 3 trials • all native constraints", 26, 12)
footer.TextColor3 = Color3.fromRGB(157, 169, 184)

local csvWindow = panel(gui, "CSVWindow", UDim2.new(0.72, 0, 0.62, 0), UDim2.new(0.14, 0, 0.19, 0))
csvWindow.Visible = false
local top = Instance.new("Frame")
top.BackgroundTransparency = 1
top.Position = UDim2.fromOffset(12, 10)
top.Size = UDim2.new(1, -24, 0, 36)
top.Parent = csvWindow
local bar = Instance.new("UIListLayout")
bar.FillDirection = Enum.FillDirection.Horizontal
bar.Padding = UDim.new(0, 9)
bar.Parent = top
button(top, "Close CSV", nil, 105).Activated:Connect(function() csvWindow.Visible = false end)
local hint = label(top, "Click text, Ctrl+A, Ctrl+C to copy (before stopping Play)", 34, 13)
hint.Size = UDim2.new(1, -125, 0, 34)

local csvBox = Instance.new("TextBox")
csvBox.Name = "Results"
csvBox.Position = UDim2.fromOffset(12, 56)
csvBox.Size = UDim2.new(1, -24, 1, -68)
csvBox.BackgroundColor3 = Color3.fromRGB(14, 20, 28)
csvBox.TextColor3 = Color3.fromRGB(222, 231, 240)
csvBox.Font = Enum.Font.Code
csvBox.TextSize = 13
csvBox.TextXAlignment = Enum.TextXAlignment.Left
csvBox.TextYAlignment = Enum.TextYAlignment.Top
csvBox.ClearTextOnFocus = false
csvBox.MultiLine = true
csvBox.TextEditable = true
csvBox.TextWrapped = false
csvBox.Text = ""
csvBox.Parent = csvWindow

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "status" and typeof(payload) == "table" then
		current.Text = string.format("%s  |  %d results  |  %s stepping",
			tostring(payload.test), tonumber(payload.totalRows) or 0, tostring(payload.stepping))
		status.Text = tostring(payload.text)
	elseif kind == "csv" and typeof(payload) == "string" then
		csvBox.Text = payload
		csvWindow.Visible = true
	end
end)
remote:FireServer("status")
