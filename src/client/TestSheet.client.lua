local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

if not RunService:IsStudio() then
    return
end

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('SpawnTestSheet')

local gui = Instance.new('ScreenGui')
gui.Name = 'OpenworksMaterialTest'
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild('PlayerGui')

local panel = Instance.new('Frame')
panel.Name = 'TestPanel'
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -20, 1, -20)
panel.Size = UDim2.fromOffset(224, 92)
panel.BackgroundColor3 = Color3.fromRGB(26, 32, 34)
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new('UICorner')
corner.CornerRadius = UDim.new(0, 7)
corner.Parent = panel

local count = Instance.new('TextLabel')
count.BackgroundTransparency = 1
count.Position = UDim2.fromOffset(10, 7)
count.Size = UDim2.new(1, -20, 0, 22)
count.TextColor3 = Color3.fromRGB(218, 225, 226)
count.Font = Enum.Font.Code
count.TextSize = 13
count.TextXAlignment = Enum.TextXAlignment.Left
count.Parent = panel

local button = Instance.new('TextButton')
button.Name = 'SpawnTestSheet'
button.Position = UDim2.fromOffset(10, 34)
button.Size = UDim2.new(1, -20, 0, 32)
button.BackgroundColor3 = Color3.fromRGB(66, 110, 111)
button.TextColor3 = Color3.fromRGB(245, 249, 247)
button.Font = Enum.Font.Code
button.TextSize = 13
button.Text = 'SPAWN TEST SHEET'
button.BorderSizePixel = 0
button.Parent = panel

local buttonCorner = Instance.new('UICorner')
buttonCorner.CornerRadius = UDim.new(0, 5)
buttonCorner.Parent = button

local status = Instance.new('TextLabel')
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(10, 68)
status.Size = UDim2.new(1, -20, 0, 17)
status.TextColor3 = Color3.fromRGB(166, 177, 178)
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = 'Studio-only detection test'
status.Parent = panel

local bench = workspace:WaitForChild('Workbench', 10)

local function updateCount()
    count.Text = 'MATERIALS ON BENCH: ' .. tostring(bench and bench:GetAttribute('MaterialCount') or 0)
end

updateCount()
if bench then
    bench:GetAttributeChangedSignal('MaterialCount'):Connect(updateCount)
else
    status.Text = 'Workbench not found'
end

button.MouseButton1Click:Connect(function()
    status.Text = 'Requesting sheet from server...'
    status.TextColor3 = Color3.fromRGB(204, 212, 214)
    remote:FireServer()
end)

remote.OnClientEvent:Connect(function(success, message)
    status.Text = message
    status.TextColor3 = if success then Color3.fromRGB(164, 213, 174)
        else Color3.fromRGB(238, 164, 160)
end)
