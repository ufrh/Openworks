local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local FileShape = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FileShape'))
local ToolVisual = require(script.Parent.ToolVisual)

local FileUI = {}

function FileUI.start(workpieces)
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local gui = Instance.new('ScreenGui')
    gui.Name = 'OpenworksFiling'
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild('PlayerGui')

    local panel = Instance.new('Frame')
    panel.Name = 'FilingPanel'
    panel.Size = UDim2.fromOffset(235, 160)
    panel.AnchorPoint = Vector2.new(1, 0.5)
    panel.Position = UDim2.new(1, -14, 0.5, 0)
    panel.BackgroundColor3 = Color3.fromRGB(25, 31, 32)
    panel.BorderSizePixel = 0
    panel.BackgroundTransparency = 0.05
    panel.Visible = false
    panel.Parent = gui

    local stack = Instance.new('UIListLayout')
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Padding = UDim.new(0, 5)
    stack.Parent = panel

    local function label(text, height)
        local object = Instance.new('TextLabel')
        object.Size = UDim2.new(1, -16, 0, height)
        object.Text = text
        object.TextWrapped = true
        object.Font = Enum.Font.Code
        object.TextSize = 13
        object.TextColor3 = Color3.fromRGB(235, 233, 220)
        object.BackgroundTransparency = 1
        object.Parent = panel
        return object
    end

    label('OPENWORKS / METAL FILE', 26)
    local status = label('Aim near a secured outer edge', 38)

    local fillBase = Instance.new('Frame')
    fillBase.Size = UDim2.new(1, -16, 0, 9)
    fillBase.BackgroundColor3 = Color3.fromRGB(60, 68, 64)
    fillBase.BorderSizePixel = 0
    fillBase.Parent = panel
    local fill = Instance.new('Frame')
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(223, 179, 101)
    fill.BorderSizePixel = 0
    fill.Parent = fillBase

    local radius = FileShape.DEFAULT_RADIUS
    local controls = Instance.new('Frame')
    controls.Size = UDim2.new(1, -16, 0, 30)
    controls.BackgroundTransparency = 1
    controls.Parent = panel
    local horizontal = Instance.new('UIListLayout')
    horizontal.FillDirection = Enum.FillDirection.Horizontal
    horizontal.Padding = UDim.new(0, 4)
    horizontal.Parent = controls

    local preview
    local filing
    local currentTool
    local lines = {}
    local toolConnections = {}
    local clock = 0

    local function equipped()
        return currentTool and player.Character and currentTool.Parent == player.Character
    end

    local function clearLines()
        for _, part in lines do part:Destroy() end
        table.clear(lines)
    end

    local function segment(a, b, index)
        local difference = b - a
        if difference.Magnitude < 0.008 then return index end
        index += 1
        local part = lines[index]
        if not part then
            part = Instance.new('Part')
            part.Name = 'Filing Curve Guide'
            part.Anchored = true
            part.CanQuery = false
            part.CanCollide = false
            part.CanTouch = false
            part.Material = Enum.Material.Neon
            part.Color = Color3.fromRGB(236, 183, 98)
            part.Parent = workspace
            lines[index] = part
        end
        part.Transparency = 0.08
        part.Size = Vector3.new(0.036, 0.036, difference.Magnitude)
        part.CFrame = CFrame.lookAt((a + b) / 2, b)
        return index
    end

    local function draw(spec)
        local used = 0
        for _, strip in spec.strips do
            for i = 1, #strip - 1 do
                used = segment(strip[i], strip[i + 1], used)
            end
        end
        for _, i in {1, math.ceil((#spec.strips[1]) / 2), #spec.strips[1]} do
            used = segment(spec.strips[1][i], spec.strips[2][i], used)
        end
        for i = used + 1, #lines do lines[i].Transparency = 1 end
    end

    local function stop()
        if filing and filing.tool and filing.tool.Parent then
            filing.tool.Grip = filing.grip
        end
        filing = nil
        fill.Size = UDim2.fromScale(0, 1)
    end

    local function connect(tool)
        if currentTool == tool then return end
        for _, connection in toolConnections do connection:Disconnect() end
        table.clear(toolConnections)
        stop()
        clearLines()
        preview = nil
        currentTool = tool
        if not tool then return end
        ToolVisual.attach(tool)

        toolConnections[#toolConnections + 1] = tool.Activated:Connect(function()
            if not equipped() or filing then return end
            if not preview or not preview.part.Parent or not preview.part.Anchored then
                status.Text = 'Secure a workpiece and aim near an outer edge'
                return
            end
            filing = {
                part = preview.part, item = preview.item,
                spec = preview.spec, tool = tool, grip = tool.Grip,
                elapsed = 0,
                duration = if preview.item.material == 'Steel' then 3.2 else 2.1,
            }
            status.Text = 'Filing edge... hold mouse'
        end)
        toolConnections[#toolConnections + 1] = tool.Deactivated:Connect(function()
            if filing then
                stop()
                status.Text = 'Filing interrupted'
            end
        end)
        toolConnections[#toolConnections + 1] = tool.Unequipped:Connect(function()
            stop()
            clearLines()
            preview = nil
            panel.Visible = false
            if mouse.TargetFilter == player.Character then mouse.TargetFilter = nil end
        end)
        toolConnections[#toolConnections + 1] = tool.Equipped:Connect(function()
            mouse.TargetFilter = player.Character
            panel.Visible = true
            status.Text = 'Hover near an edge; hold LMB to round'
        end)
    end

    for _, value in {1, 3, 6} do
        local button = Instance.new('TextButton')
        button.Size = UDim2.new(1 / 3, -3, 1, 0)
        button.Text = tostring(value) .. ' mm'
        button.TextSize = 13
        button.Font = Enum.Font.Code
        button.TextColor3 = Color3.fromRGB(240, 236, 218)
        button.BackgroundColor3 = Color3.fromRGB(55, 64, 62)
        button.BorderSizePixel = 0
        button.Parent = controls
        button.MouseButton1Click:Connect(function()
            if filing then return end
            radius = value
            preview = nil
            clearLines()
            status.Text = 'Rounding radius: ' .. value .. ' mm'
        end)
    end

    local function watchCharacter(character)
        for _, child in character:GetChildren() do
            if child:IsA('Tool') and child.Name == 'Metal File' then
                connect(child)
                panel.Visible = true
                mouse.TargetFilter = character
            end
        end
        character.ChildAdded:Connect(function(child)
            if child:IsA('Tool') and child.Name == 'Metal File' then
                connect(child)
                panel.Visible = true
                mouse.TargetFilter = character
            end
        end)
    end
    if player.Character then watchCharacter(player.Character) end
    player.CharacterAdded:Connect(watchCharacter)

    RunService.RenderStepped:Connect(function(dt)
        if not equipped() then
            panel.Visible = false
            if preview then preview = nil clearLines() end
            return
        end
        panel.Visible = true

        if filing then
            local task = filing
            if not task.part.Parent or not task.part.Anchored or workpieces.get(task.part) ~= task.item then
                stop()
                clearLines()
                status.Text = 'Workpiece changed; filing cancelled'
                return
            end
            task.elapsed += dt
            local fraction = math.min(1, task.elapsed / task.duration)
            fill.Size = UDim2.fromScale(fraction, 1)
            task.tool.Grip = task.grip * CFrame.new(0, 0, math.sin(task.elapsed * 32) * 0.13)
            if fraction >= 1 then
                local success, solid, stats = pcall(FileShape.apply, task.item, task.spec)
                stop()
                preview = nil
                clearLines()
                if not success or not solid then
                    status.Text = 'Filing failed: ' .. tostring(if success then stats else solid)
                    return
                end
                local ok, committed, reason = pcall(workpieces.refine, task.part, solid)
                if ok and committed then
                    status.Text = string.format('Rounded edge: %.1f mm³ removed', stats.removed)
                else
                    status.Text = 'Filing failed: ' .. tostring(if ok then reason else committed)
                end
            end
            return
        end

        clock += dt
        if clock < 0.12 then return end
        clock = 0

        local part = mouse.Target
        local item = workpieces.get(part)
        if not item or not part.Anchored then
            if preview then preview = nil clearLines() end
            return
        end

        local result, reason = FileShape.preview(item, mouse.Hit.Position, radius)
        if not result then
            if preview then preview = nil clearLines() end
            status.Text = tostring(reason or 'Aim near an outer edge')
            return
        end
        preview = {part = part, item = item, spec = result}
        draw(result)
        status.Text = 'Edge ready - hold LMB (' .. tostring(radius) .. ' mm)'
    end)

    return gui
end

return FileUI
