local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local FileShape = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FileShape'))
local FabricationVisual = require(script.Parent.FabricationVisual)
local FabricationTool = require(script.Parent.FabricationTool)
local Motion = require(script.Parent.FabricationMotion)

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
    local working
    local lines = {}
    local toolConnections = {}
    local clock = 0
    local feedbackUntil = 0

    local function feedback(message, seconds)
        status.Text = message
        feedbackUntil = os.clock() + (seconds or 2.5)
    end

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
        filing = nil
        fill.Size = UDim2.fromScale(0, 1)
    end

    local function closeWorking()
        if working then working:destroy() working = nil end
    end

    local function showModel()
        if working then return true end
        local object, reason = FabricationVisual.new('Metal File', 'FileFace')
        if not object then
            feedback(tostring(reason), 5)
            return false
        end
        working = object
        return true
    end

    local function findTool()
        return FabricationTool.find(player, 'Metal File')
    end

    local function connect(tool)
        if currentTool == tool then return end
        for _, connection in toolConnections do connection:Disconnect() end
        table.clear(toolConnections)
        if currentTool then FabricationTool.restore(currentTool) end
        stop()
        closeWorking()
        clearLines()
        preview = nil
        currentTool = tool
        if not tool then return end

        toolConnections[#toolConnections + 1] = tool.Activated:Connect(function()
            if not equipped() or filing then return end
            if not preview or not preview.part.Parent or not preview.part.Anchored then
                feedback('Secure a workpiece and aim at an outside edge')
                return
            end
            local valid, solid, stats = pcall(FileShape.apply, preview.item, preview.spec)
            if not valid or not solid then
                feedback('Cannot file this edge: ' .. tostring(if valid then stats else solid), 5)
                warn('[FILE] Filing geometry rejected: ' .. status.Text)
                return
            end
            if not preview.motion or not showModel() then
                feedback('File model or filing movement is unavailable')
                return
            end
            filing = {
                part = preview.part, item = preview.item,
                spec = preview.spec,
                result = solid, stats = stats, elapsed = 0,
                duration = if preview.item.material == 'Steel' then 3.2 else 2.1,
                phase = 0, plan = preview.motion,
            }
            status.Text = 'Metal file engaged - hold to shape the edge'
        end)
        toolConnections[#toolConnections + 1] = tool.Deactivated:Connect(function()
            if filing then
                stop()
                status.Text = 'Filing interrupted'
            end
        end)
        toolConnections[#toolConnections + 1] = tool.Unequipped:Connect(function()
            stop()
            closeWorking()
            FabricationTool.restore(tool)
            clearLines()
            preview = nil
            panel.Visible = false
            if mouse.TargetFilter == player.Character then mouse.TargetFilter = nil end
        end)
        toolConnections[#toolConnections + 1] = tool.Equipped:Connect(function()
            mouse.TargetFilter = player.Character
            FabricationTool.hideEquipped(tool)
            showModel()
            panel.Visible = true
            status.Text = 'Aim at the edge; the working file follows the surface'
        end)
        if equipped() then
            FabricationTool.hideEquipped(tool)
            showModel()
        end
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

    local equipButton = Instance.new('TextButton')
    equipButton.Name = 'EquipMetalFile'
    equipButton.AnchorPoint = Vector2.new(1, 0)
    equipButton.Position = UDim2.new(1, -14, 0, 14)
    equipButton.Size = UDim2.fromOffset(194, 30)
    equipButton.Font = Enum.Font.Code
    equipButton.TextSize = 13
    equipButton.TextColor3 = Color3.fromRGB(240, 236, 218)
    equipButton.BackgroundColor3 = Color3.fromRGB(55, 64, 62)
    equipButton.BorderSizePixel = 0
    equipButton.Text = 'EQUIP METAL FILE'
    equipButton.Parent = gui
    equipButton.MouseButton1Click:Connect(function()
        local tool, reason = findTool()
        if not tool then
            feedback(tostring(reason), 5)
            equipButton.Text = 'MISSING METAL FILE'
            warn('[FILE] ' .. tostring(reason))
            return
        end
        connect(tool)
        local humanoid = player.Character and player.Character:FindFirstChildOfClass('Humanoid')
        if not humanoid then
            status.Text = 'Character is not ready'
            equipButton.Text = 'CHARACTER NOT READY'
            return
        end
        if tool.RequiresHandle and not tool:FindFirstChild('Handle') then
            tool.RequiresHandle = false
        end
        humanoid:EquipTool(tool)
    end)

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
        equipButton.Visible = not equipped()
        if not equipped() then
            panel.Visible = false
            if preview then preview = nil clearLines() end
            if working then working:hide() end
            return
        end
        panel.Visible = true

        if filing then
            local task = filing
            if not task.part.Parent or not task.part.Anchored
                or workpieces.get(task.part) ~= task.item then
                stop()
                clearLines()
                if working then working:hide() end
                feedback('Workpiece changed; filing cancelled')
                return
            end
            task.elapsed += dt
            task.phase += dt * 25
            local fraction = math.min(1, task.elapsed / task.duration)
            fill.Size = UDim2.fromScale(fraction, 1)
            if working then
                working:pose(Motion.filePose(task.plan, fraction, task.phase))
            end
            if fraction >= 1 then
                stop()
                preview = nil
                clearLines()
                local ok, committed, reason = pcall(workpieces.refine, task.part, task.result)
                if ok and committed then
                    feedback(string.format('Rounded edge: %.1f mm³ removed', task.stats.removed), 3)
                else
                    feedback('Filing failed: ' .. tostring(if ok then reason else committed), 6)
                    warn('[FILE] Workpiece update failed: ' .. status.Text)
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
            if working then working:hide() end
            if os.clock() >= feedbackUntil then
                status.Text = if item and not part.Anchored then 'Secure the metal first'
                    else 'Aim at a stock face to select an outer edge'
            end
            return
        end

        local result, reason = FileShape.preview(item, mouse.Hit.Position, radius)
        if not result then
            if preview then preview = nil clearLines() end
            if working then working:hide() end
            if os.clock() >= feedbackUntil then
                status.Text = tostring(reason or 'Aim at another outer edge')
            end
            return
        end
        local plan = Motion.filePlan(item, result)
        preview = {part = part, item = item, spec = result, motion = plan}
        draw(result)
        if showModel() then working:pose(Motion.filePose(plan, 0, 0)) end
        if os.clock() >= feedbackUntil then
            status.Text = 'Edge ready - hold LMB (' .. tostring(radius) .. ' mm)'
        end
    end)

    return gui
end

return FileUI
