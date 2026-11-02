local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local SawCut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('SawCut'))
local FabricationVisual = require(script.Parent.FabricationVisual)
local FabricationTool = require(script.Parent.FabricationTool)
local Motion = require(script.Parent.FabricationMotion)

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
    local working
    local groove
    local turn = 0
    local orbit
    local lines = {}
    local activeToolConnection = {}
    local connections = {}
    local sawRotation = 0
    local startOrbit

    local function clearLines()
        for _, line in lines do line:Destroy() end
        table.clear(lines)
    end

    local function drawRing(rings)
        local used = 0
        for _, ring in rings do
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
        end
        for i = used + 1, #lines do lines[i].Transparency = 1 end
    end

    local function clearGroove()
        if groove then groove:Destroy() groove = nil end
    end

    local function stopCut()
        cutting = nil
        if currentTool then FabricationTool.restore(currentTool) end
        if working then working:hide() end
        clearGroove()
        fill.Size = UDim2.fromScale(0, 1)
    end

    local function closeWorking()
        if working then working:destroy() working = nil end
    end

    local function stopOrbit()
        if not orbit then return end
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = orbit.oldType
            if orbit.oldSubject and orbit.oldSubject.Parent then
                camera.CameraSubject = orbit.oldSubject
            end
        end
        orbit = nil
    end

    local function equipped()
        return currentTool and player.Character and currentTool.Parent == player.Character
    end

    local function findTool()
        return FabricationTool.find(player, 'Hacksaw')
    end

    local function showModel()
        if working then return true end
        local object, reason = FabricationVisual.new('Hacksaw', 'BladeEdge')
        if not object then
            hint.Text = tostring(reason)
            return false
        end
        working = object
        return true
    end

    local function connectTool(tool)
        if currentTool == tool then return end
        for _, connection in activeToolConnection do connection:Disconnect() end
        table.clear(activeToolConnection)
        if currentTool then FabricationTool.restore(currentTool) end
        stopCut()
        stopOrbit()
        closeWorking()
        clearLines()
        preview = nil
        currentTool = tool
        if not tool then return end
        FabricationTool.ensureCosmetic(tool)

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
            if not preview.motion or not showModel() then
                hint.Text = 'No valid saw movement for this cut'
                return
            end
            FabricationTool.hideEquipped(tool)
            local plan = preview.motion
            local depth = plan.travel
            cutting = {
                part = preview.part,
                item = preview.item,
                point = preview.data.point,
                normal = preview.data.normal,
                plan = plan,
                advanced = 0,
                travel = depth,
                rate = depth / (if preview.item.material == 'Steel' then 3.8 else 2.6),
                phase = 0,
            }
            groove = Instance.new('Part')
            groove.Name = 'Saw Kerf Progress'
            groove.Transparency = 1
            groove.Size = Vector3.new(0.02, 0.02, 0.02)
            groove.Anchored = true
            groove.CanCollide = false
            groove.CanTouch = false
            groove.CanQuery = false
            groove.CastShadow = false
            groove.Material = Enum.Material.SmoothPlastic
            groove.Color = Color3.fromRGB(30, 33, 35)
            groove.Transparency = 1
            groove.Parent = workspace
            hint.Text = 'Blade engaged - hold to saw through the metal'
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
            closeWorking()
            clearLines()
            preview = nil
            hint.Text = 'Equip hacksaw to begin'
        end)
        activeToolConnection[#activeToolConnection + 1] = tool.Equipped:Connect(function()
            mouse.TargetFilter = player.Character
            if startOrbit then startOrbit() end
            hint.Text = 'Aim at secured metal. Hold click to drive the working saw along the cut.'
        end)
        if equipped() and startOrbit then startOrbit() end
    end

    makeButton(panel, 'EQUIP HACKSAW', function()
        local tool, reason = findTool()
        if not tool then
            hint.Text = tostring(reason)
            return
        end
        connectTool(tool)
        local humanoid = player.Character and player.Character:FindFirstChildOfClass('Humanoid')
        if not humanoid then hint.Text = 'Character is not ready' return end
        if not tool:FindFirstChild('Handle') and tool.RequiresHandle then
            tool.RequiresHandle = false
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
    makeLabel(panel, 'Auto orbit: metal | V: toggle | T: top down | Q/E: cut | R: rotate saw | RMB: orbit', 56)

    startOrbit = function(focusPart)
        local target = focusPart or workpieces.selected()
        if not target or not target.Parent then
            hint.Text = 'Select a metal workpiece to focus the camera'
            return
        end
        local camera = workspace.CurrentCamera
        if not camera then return end
        if orbit then
            orbit.part = target
            return
        end
        local offset = camera.CFrame.Position - target.Position
        local distance = math.clamp(offset.Magnitude, 4, 26)
        local yaw = math.atan2(offset.X, offset.Z)
        local pitch = math.asin(math.clamp(offset.Y / math.max(offset.Magnitude, 0.001), -1, 1))
        orbit = {
            part = target, oldType = camera.CameraType,
            oldSubject = camera.CameraSubject,
            distance = distance,
            yaw = yaw,
            pitch = math.clamp(pitch, math.rad(18), math.rad(85)),
        }
        camera.CameraSubject = target
        camera.CameraType = Enum.CameraType.Scriptable
    end

    if player.Character then observe(player.Character) end
    connections[#connections + 1] = player.CharacterAdded:Connect(observe)

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
        elseif input.KeyCode == Enum.KeyCode.R and not cutting then
            sawRotation = (sawRotation + 90) % 360
            hint.Text = 'Working blade alignment: ' .. sawRotation .. ' degrees'
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
        panel.Visible = not (player.Character and player.Character:FindFirstChild('Metal File'))
        if orbit then
            local desired = if cutting then cutting.part else workpieces.selected()
            if desired and desired.Parent then
                if orbit.part ~= desired then
                    orbit.part = desired
                    local camera = workspace.CurrentCamera
                    if camera then camera.CameraSubject = desired end
                end
            elseif not orbit.part.Parent then
                stopOrbit()
            end
            if orbit then
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
            if not equipped() or not operation.part.Parent or not operation.part.Anchored
                or workpieces.get(operation.part) ~= operation.item then
                stopCut()
                clearLines()
                if working then working:hide() end
                return
            end

            operation.advanced = math.min(operation.travel, operation.advanced + dt * operation.rate)
            operation.phase += dt * 23
            local progress = operation.advanced / operation.travel
            fill.Size = UDim2.fromScale(progress, 1)
            if working then
                working:pose(Motion.sawPose(operation.plan, progress, operation.phase)
                    * CFrame.Angles(0, 0, math.rad(sawRotation)))
            end
            if groove then
                local plan = operation.plan
                local advanceAlong = plan.across * progress
                local visibleLength = math.max(0.006, advanceAlong)
                groove.Transparency = 0.28
                groove.Size = Vector3.new(visibleLength, 0.018,
                    SawCut.KERF_MM * 0.04 + 0.012)
                local surface = plan.center
                    + plan.forward * (plan.alongStart + visibleLength / 2)
                    + plan.outward * (plan.start + 0.012)
                groove.CFrame = FabricationVisual.contactFrame(
                    surface, plan.forward, plan.outward)
            end

            if progress >= 1 then
                local success, solids, stats = pcall(SawCut.split, operation.item,
                    operation.point, operation.normal)
                stopCut()
                clearLines()
                preview = nil
                if working then working:hide() end
                if not success or not solids then
                    hint.Text = 'Cut failed: ' .. tostring(if success then stats else solids)
                    return
                end
                local ok, committed, reason = pcall(workpieces.separate,
                    operation.part, solids, stats)
                if ok and committed then
                    hint.Text = string.format('Metal separated - %.1f mm³ kerf removed', stats.removed)
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
            if working then working:hide() end
            return
        end

        local part = mouse.Target
        local item = workpieces.get(part)
        if not item or not part.Anchored then
            if preview then clearLines() preview = nil end
            if working then working:hide() end
            return
        end

        local tube = item.shape == 'Tube' or item.tubeProfile ~= nil
        local up = item.frame:VectorToWorldSpace(
            if tube then Vector3.xAxis else Vector3.yAxis)
        local attachment = currentTool:FindFirstChild('CutNormal', true)
        local baseAxis = if attachment and attachment:IsA('Attachment')
            then attachment.WorldAxis else item.frame:VectorToWorldSpace(
                if tube then Vector3.yAxis else Vector3.xAxis)
        local axis = CFrame.fromAxisAngle(up, math.rad(turn)):VectorToWorldSpace(baseAxis).Unit

        local candidate, reason = SawCut.preview(item, mouse.Hit.Position, axis)
        if not candidate then
            if preview then clearLines() preview = nil end
            if working then working:hide() end
            hint.Text = tostring(reason or 'No valid cut at this position')
            return
        end
        local camera = workspace.CurrentCamera
        local ray = camera and camera:ViewportPointToRay(mouse.X, mouse.Y)
        local surfaceNormal = if ray then Motion.surfaceNormal(part, ray) else nil
        local plan, planReason = Motion.sawPlan(candidate, mouse.Hit.Position,
            surfaceNormal or item.frame.UpVector)
        if not plan then
            if working then working:hide() end
            if preview then clearLines() preview = nil end
            hint.Text = tostring(planReason)
            return
        end
        preview = {part = part, item = item, data = candidate, motion = plan}
        drawRing(candidate.rings or {candidate.ring})
        if working then working:hide() end
        hint.Text = 'Saw ready - hold LMB to follow cut (' .. item.material .. ')'
    end)

    return gui
end

return SawUI
