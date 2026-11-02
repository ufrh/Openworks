local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local SawCut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('SawCut'))
local ToolVisual = require(script.Parent.ToolVisual)

local SawUI = {}

local function makeLabel(parent, value, height)
    local label = Instance.new('TextLabel')
    label.Size = UDim2.new(1, -16, 0, height)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(231, 231, 218)
    label.TextWrapped = true
    label.Font = Enum.Font.Code
    label.TextSize = 13
    label.Text = value
    label.Parent = parent
    return label
end

local function makeButton(parent, value, callback)
    local button = Instance.new('TextButton')
    button.Size = UDim2.new(1, -16, 0, 30)
    button.Text = value
    button.TextColor3 = Color3.fromRGB(241, 236, 219)
    button.Font = Enum.Font.Code
    button.TextSize = 13
    button.BackgroundColor3 = Color3.fromRGB(55, 65, 65)
    button.BorderSizePixel = 0
    button.Parent = parent
    button.MouseButton1Click:Connect(callback)
end

function SawUI.start(workpieces)
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local gui = Instance.new('ScreenGui')
    gui.Name = 'OpenworksSaw'
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild('PlayerGui')

    local panel = Instance.new('Frame')
    panel.Name = 'SawPanel'
    panel.AnchorPoint = Vector2.new(1, 0.5)
    panel.Position = UDim2.new(1, -14, 0.5, 0)
    panel.Size = UDim2.fromOffset(235, 196)
    panel.BorderSizePixel = 0
    panel.BackgroundColor3 = Color3.fromRGB(25, 31, 32)
    panel.BackgroundTransparency = 0.05
    panel.Parent = gui
    local stack = Instance.new('UIListLayout')
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Padding = UDim.new(0, 4)
    stack.Parent = panel

    makeLabel(panel, 'OPENWORKS / HACKSAW', 26)
    local hint = makeLabel(panel, 'Equip hacksaw to begin', 40)
    local bar = Instance.new('Frame')
    bar.Size = UDim2.new(1, -18, 0, 9)
    bar.BorderSizePixel = 0
    bar.BackgroundColor3 = Color3.fromRGB(63, 71, 68)
    bar.Parent = panel
    local fill = Instance.new('Frame')
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(225, 178, 96)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local currentTool
    local preview
    local cutting
    local turn = 0
    local orbit
    local lines = {}
    local activeToolConnection = {}
    local connections = {}

    local function clearLines()
        for _, line in lines do line:Destroy() end
        table.clear(lines)
    end

    local function drawRing(ring)
        local used = 0
        for i, a in ring do
            local b = ring[i % #ring + 1]
            local delta = b - a
            if delta.Magnitude < 0.008 then continue end
            used += 1
            local line = lines[used]
            if not line then
                line = Instance.new('Part')
                line.Name = 'Saw Cutting Preview'
                line.Material = Enum.Material.Neon
                line.Color = Color3.fromRGB(240, 179, 73)
                line.Anchored = true
                line.CanCollide = false
                line.CanTouch = false
                line.CanQuery = false
                line.Parent = workspace
                lines[used] = line
            end
            line.Transparency = 0.1
            line.Size = Vector3.new(0.035, 0.035, delta.Magnitude)
            line.CFrame = CFrame.lookAt((a + b) / 2, b)
        end
        for i = used + 1, #lines do lines[i].Transparency = 1 end
    end

    local function stopCut()
        if cutting and cutting.tool and cutting.tool.Parent then
            cutting.tool.Grip = cutting.grip
        end
        cutting = nil
        fill.Size = UDim2.fromScale(0, 1)
    end

    local function stopOrbit()
        if not orbit then return end
        local camera = workspace.CurrentCamera
        if camera then camera.CameraType = orbit.oldType end
        orbit = nil
    end

    local function equipped()
        return currentTool and player.Character and currentTool.Parent == player.Character
    end

    local function findTool()
        local backpack = player:FindFirstChildOfClass('Backpack')
        local character = player.Character
        local equippedTool = character and character:FindFirstChild('Hacksaw')
        if equippedTool and equippedTool:IsA('Tool') then return equippedTool end
        local owned = backpack and backpack:FindFirstChild('Hacksaw')
        if owned and owned:IsA('Tool') then return owned end

        if backpack then
            for _, source in ReplicatedStorage:GetDescendants() do
                if source:IsA('Tool') and source.Name == 'Hacksaw' then
                    local clone = source:Clone()
                    clone.Parent = backpack
                    return clone
                end
            end
        end
        return nil
    end

    local function connectTool(tool)
        if currentTool == tool then return end
        for _, connection in activeToolConnection do connection:Disconnect() end
        table.clear(activeToolConnection)
        stopCut()
        stopOrbit()
        clearLines()
        preview = nil
        currentTool = tool
        if not tool then return end
        ToolVisual.attach(tool)

        activeToolConnection[#activeToolConnection + 1] = tool.Activated:Connect(function()
            if not equipped() or cutting then return end
            if not preview or not preview.part or not preview.part.Parent then
                hint.Text = 'Aim at a secured workpiece'
                return
            end
            if not preview.part.Anchored then
                hint.Text = 'Secure the workpiece first'
                return
            end
            cutting = {
                part = preview.part,
                item = preview.item,
                point = preview.data.point,
                normal = preview.data.normal,
                tool = tool,
                grip = tool.Grip,
                elapsed = 0,
                required = if preview.item.material == 'Steel' then 3.8 else 2.6,
            }
            hint.Text = 'Sawing... keep holding'
        end)
        activeToolConnection[#activeToolConnection + 1] = tool.Deactivated:Connect(function()
            if cutting then
                stopCut()
                hint.Text = 'Cut interrupted'
            end
        end)
        activeToolConnection[#activeToolConnection + 1] = tool.Unequipped:Connect(function()
            if mouse.TargetFilter == player.Character then mouse.TargetFilter = nil end
            stopCut()
            stopOrbit()
            clearLines()
            preview = nil
            hint.Text = 'Equip hacksaw to begin'
        end)
        activeToolConnection[#activeToolConnection + 1] = tool.Equipped:Connect(function()
            mouse.TargetFilter = player.Character
            hint.Text = 'Aim at secured metal. Hold click to saw.'
        end)
    end

    makeButton(panel, 'EQUIP HACKSAW', function()
        local tool = findTool()
        if not tool then
            hint.Text = 'Need a Roblox Tool named Hacksaw in StarterPack or ReplicatedStorage'
            return
        end
        connectTool(tool)
        local humanoid = player.Character and player.Character:FindFirstChildOfClass('Humanoid')
        if not humanoid then hint.Text = 'Character is not ready' return end
        if not tool:FindFirstChild('Handle') and tool.RequiresHandle then
            hint.Text = 'Hacksaw Tool needs a direct Handle part (or RequiresHandle=false)'
            return
        end
        humanoid:EquipTool(tool)
    end)

    local function observe(character)
        for _, child in character:GetChildren() do
            if child:IsA('Tool') and child.Name == 'Hacksaw' then
                connectTool(child)
                mouse.TargetFilter = player.Character
            end
        end
        connections[#connections + 1] = character.ChildAdded:Connect(function(child)
            if child:IsA('Tool') and child.Name == 'Hacksaw' then
                connectTool(child)
                mouse.TargetFilter = player.Character
            end
        end)
    end
    if player.Character then observe(player.Character) end
    connections[#connections + 1] = player.CharacterAdded:Connect(observe)

    makeLabel(panel, 'V: orbit camera | T: top down | Q/E: rotate cut | RMB: orbit | wheel: zoom', 56)

    local function startOrbit()
        local focusPart = if preview then preview.part else workpieces.selected()
        if not focusPart then hint.Text = 'Select a workpiece to focus the camera' return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        orbit = {part = focusPart, oldType = camera.CameraType,
            distance = math.clamp((camera.CFrame.Position - focusPart.Position).Magnitude, 4, 26),
            yaw = math.rad(35), pitch = math.rad(40)}
        camera.CameraType = Enum.CameraType.Scriptable
    end

    connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or not equipped() then return end
        if input.KeyCode == Enum.KeyCode.V then
            if orbit then stopOrbit() else startOrbit() end
        elseif input.KeyCode == Enum.KeyCode.T then
            if not orbit then startOrbit() end
            if orbit then orbit.pitch = math.rad(87) end
        elseif input.KeyCode == Enum.KeyCode.Q then
            turn -= 15
        elseif input.KeyCode == Enum.KeyCode.E then
            turn += 15
        end
    end)
    connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input, processed)
        if processed or not orbit then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            orbit.distance = math.clamp(orbit.distance - input.Position.Z * 1.5, 3, 32)
        elseif input.UserInputType == Enum.UserInputType.MouseMovement
            and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            orbit.yaw -= input.Delta.X * 0.007
            orbit.pitch = math.clamp(orbit.pitch - input.Delta.Y * 0.007,
                math.rad(12), math.rad(88))
        end
    end)

    local clock = 0
    connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
        if orbit then
            if not orbit.part.Parent then
                stopOrbit()
            else
                local camera = workspace.CurrentCamera
                if camera then
                    local focus = orbit.part.Position
                    local offset = Vector3.new(
                        math.sin(orbit.yaw) * math.cos(orbit.pitch),
                        math.sin(orbit.pitch),
                        math.cos(orbit.yaw) * math.cos(orbit.pitch)) * orbit.distance
                    camera.CFrame = CFrame.lookAt(focus + offset, focus)
                end
            end
        end

        if cutting then
            local operation = cutting
            if not equipped() or not operation.part.Parent or not operation.part.Anchored then
                stopCut()
                clearLines()
                return
            end
            operation.elapsed += dt
            local progress = math.min(1, operation.elapsed / operation.required)
            fill.Size = UDim2.fromScale(progress, 1)
            operation.tool.Grip = operation.grip * CFrame.new(0, 0,
                math.sin(operation.elapsed * 25) * 0.18)
            if progress >= 1 then
                local success, solids, stats = pcall(SawCut.split, operation.item,
                    operation.point, operation.normal)
                stopCut()
                clearLines()
                preview = nil
                if not success or not solids then
                    hint.Text = 'Cut failed: ' .. tostring(if success then stats else solids)
                    return
                end
                local ok, committed, reason = pcall(workpieces.separate, operation.part, solids)
                if ok and committed then
                    hint.Text = string.format('Cut complete - kerf %.2f mm, %.1f mm³ removed',
                        SawCut.KERF_MM, stats.removed)
                else
                    hint.Text = 'Cut failed: ' .. tostring(if ok then reason else committed)
                end
            end
            return
        end

        clock += dt
        if clock < 0.10 then return end
        clock = 0
        if not equipped() then
            if preview then clearLines() preview = nil end
            return
        end

        local part = mouse.Target
        local item = workpieces.get(part)
        if not item or not part.Anchored then
            if preview then clearLines() preview = nil end
            return
        end

        local up = item.frame:VectorToWorldSpace(Vector3.yAxis)
        local attachment = currentTool:FindFirstChild('CutNormal', true)
        local baseAxis = if attachment and attachment:IsA('Attachment')
            then attachment.WorldAxis else item.frame:VectorToWorldSpace(Vector3.xAxis)
        local axis = CFrame.fromAxisAngle(up, math.rad(turn)):VectorToWorldSpace(baseAxis).Unit

        local candidate = SawCut.preview(item, mouse.Hit.Position, axis)
        if not candidate then
            if preview then clearLines() preview = nil end
            return
        end
        preview = {part = part, item = item, data = candidate}
        drawRing(candidate.ring)
        hint.Text = 'Cut ready - hold LMB to saw (' .. item.material .. ')'
    end)

    return gui
end

return SawUI
