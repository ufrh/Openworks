local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Machine = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Machine'))
local Renderer = require(script:WaitForChild('FORMRenderer'))

local machine = Machine.new(FORM.box(Vector3.new(100, 50, 40)))
local part
local editable
local busy = false
local position = CFrame.new(0, 7, -12)

local player = Players.LocalPlayer
local gui = Instance.new('ScreenGui')
gui.Name = 'OpenworksMachining'
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild('PlayerGui')

local panel = Instance.new('Frame')
panel.Name = 'Tools'
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 24, 1, -24)
panel.Size = UDim2.fromOffset(300, 468)
panel.BackgroundColor3 = Color3.fromRGB(24, 28, 29)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
local round = Instance.new('UICorner')
round.CornerRadius = UDim.new(0, 10)
round.Parent = panel

local padding = Instance.new('UIPadding')
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = panel

local layout = Instance.new('UIListLayout')
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local function textLabel(name, value, height, size, color)
    local label = Instance.new('TextLabel')
    label.Name = name
    label.Size = UDim2.new(1, 0, 0, height)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Code
    label.TextSize = size
    label.TextColor3 = color
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = value
    label.Parent = panel
    return label
end

textLabel('Title', 'OPENWORKS  /  FORM', 27, 21, Color3.fromRGB(242, 231, 206))
local status = textLabel('Status', '', 50, 13, Color3.fromRGB(167, 192, 174))

local function button(name, label, callback)
    local control = Instance.new('TextButton')
    control.Name = name
    control.Size = UDim2.new(1, 0, 0, 32)
    control.BackgroundColor3 = Color3.fromRGB(45, 53, 52)
    control.BorderSizePixel = 0
    control.AutoButtonColor = true
    control.TextXAlignment = Enum.TextXAlignment.Left
    control.Text = '  ' .. label
    control.Font = Enum.Font.Code
    control.TextSize = 14
    control.TextColor3 = Color3.fromRGB(232, 229, 218)
    control.Parent = panel
    local corners = Instance.new('UICorner')
    corners.CornerRadius = UDim.new(0, 5)
    corners.Parent = control
    control.MouseButton1Click:Connect(callback)
    return control
end

local function releaseMesh()
    if part then part:Destroy() part = nil end
    if editable then
        pcall(function() editable:Destroy() end)
        editable = nil
    end
end

local function refresh(message)
    releaseMesh()
    local solid, reason, diagnostic
    local ok, err = pcall(function()
        solid, reason, diagnostic = machine:mesh()
    end)

    if not ok then warn('[FORM] Unified reconstruction error: ' .. tostring(err)) end
    if ok and not solid then warn('[FORM] Unified reconstruction rejected: ' .. tostring(reason)) end

    local success, result = pcall(function()
        local newPart, newEditable
        if ok and solid then
            newPart, newEditable = Renderer.create(solid, 0.04, 30)
        else
            newPart, newEditable = Renderer.createMany(machine:pieces(), 0.04, 30)
        end
        part, editable = newPart, newEditable
        part.Name = 'OPENWORKS Machined Workpiece'
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Metal
        part.Color = Color3.fromRGB(78, 156, 120)
        part.CFrame = position
        part.Parent = workspace
    end)
    if not success then warn('[FORM] Machining preview failed: ' .. tostring(result)) end

    local info = machine:status()
    local meshLabel = if ok and solid then 'UNIFIED' else 'FRAGMENT FALLBACK'
    status.Text = string.format('%s  |  %.1f mm^3 left\n%d operations  |  %d convex pieces\n%s',
        meshLabel, info.volume, info.operations, info.pieceCount, message or 'Ready')
    print(string.format('[FORM] %s: %d operations, %d convex pieces, %.4f mm^3 remaining',
        meshLabel, info.operations, info.pieceCount, info.volume))
end

local commands = {
    drill = function()
        return machine:apply({kind = 'drill', center = Vector3.new(18, 0, 8), radius = 4,
            height = 70, segments = 12})
    end,
    pocket = function()
        return machine:apply({kind = 'pocket', center = Vector3.new(22, 23, -7),
            size = Vector3.new(16, 16, 16)})
    end,
    slot = function()
        return machine:apply({kind = 'slot', from = Vector3.new(-32, 0, -10),
            to = Vector3.new(-17, 0, -10), radius = 3, height = 70, segments = 12})
    end,
    profile = function()
        return machine:apply({kind = 'profile',
            points = {
                Vector3.new(-29, 0, 12),
                Vector3.new(-13, 0, 12),
                Vector3.new(-13, 0, 1),
            },
            radius = 2.5, height = 70, segments = 12})
    end,
    chamfer = function()
        return machine:apply({kind = 'chamfer', axisA = 'X', signA = 1,
            axisB = 'Z', signB = 1, distance = 4})
    end,
    fillet = function()
        return machine:apply({kind = 'fillet', axisA = 'X', signA = -1,
            axisB = 'Z', signB = 1, radius = 4, segments = 6})
    end,
    saw = function()
        return machine:apply({kind = 'saw', point = Vector3.new(47, 0, 0), normal = Vector3.xAxis})
    end,
    undo = function() return machine:undo(), 0 end,
    redo = function() return machine:redo(), 0 end,
    reset = function() machine:reset() return true, 0 end,
}

local function run(name)
    if busy then return end
    busy = true
    status.Text = 'Machining: ' .. name .. '...'
    local success, applied, amount = pcall(commands[name])
    if not success then
        warn('[FORM] Machining ' .. name .. ' failed: ' .. tostring(applied))
        refresh('FAILED: ' .. name)
    elseif not applied then
        warn('[FORM] Machining ' .. name .. ' rejected: ' .. tostring(amount))
        refresh('REJECTED: ' .. name)
    else
        refresh(name .. string.format('  (-%.3f mm^3)', amount or 0))
    end
    busy = false
end

button('Drill', '[1]  Drill 8 mm through-hole', function() run('drill') end)
button('Pocket', '[2]  Mill a rectangular pocket', function() run('pocket') end)
button('Slot', '[3]  Cut a rounded through-slot', function() run('slot') end)
button('Profile', '[7]  Sweep elbow milling path', function() run('profile') end)
button('Chamfer', '[4]  Chamfer outer edge', function() run('chamfer') end)
button('Fillet', '[5]  Faceted outer fillet', function() run('fillet') end)
button('Saw', '[6]  Trim right edge', function() run('saw') end)
button('Undo', '[Z]  Undo    [Y]  Redo', function() run('undo') end)
button('Reset', '[R]  Reset workpiece', function() run('reset') end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.One then run('drill')
    elseif key == Enum.KeyCode.Two then run('pocket')
    elseif key == Enum.KeyCode.Three then run('slot')
    elseif key == Enum.KeyCode.Four then run('chamfer')
    elseif key == Enum.KeyCode.Five then run('fillet')
    elseif key == Enum.KeyCode.Six then run('saw')
    elseif key == Enum.KeyCode.Seven then run('profile')
    elseif key == Enum.KeyCode.Z then run('undo')
    elseif key == Enum.KeyCode.Y then run('redo')
    elseif key == Enum.KeyCode.R then run('reset')
    end
end)

local initial, initialReason = machine:apply({
    kind = 'drill',
    center = Vector3.zero,
    radius = 7,
    height = 70,
    segments = 12,
})
if not initial then warn('[FORM] Initial demonstration drill failed: ' .. tostring(initialReason)) end
refresh('Interactive machining ready')
