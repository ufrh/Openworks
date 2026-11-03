local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORMMaterial = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORMMaterial'))

local player = Players.LocalPlayer
local Inspector = {}
Inspector.__index = Inspector

local function itemPosition(item)
    if not item or not item.Parent then return nil end
    if item:IsA('BasePart') then return item.Position end
    if item:IsA('Model') then return item:GetPivot().Position end
end

local function makeText(parent, text, height, size)
    local label = Instance.new('TextLabel')
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -16, 0, height)
    label.Text = text
    label.TextSize = size or 13
    label.TextWrapped = true
    label.TextColor3 = Color3.fromRGB(225, 231, 229)
    label.Font = Enum.Font.Code
    label.Parent = parent
    return label
end

local function makeButton(parent, text, callback)
    local button = Instance.new('TextButton')
    button.Size = UDim2.new(1, -14, 0, 34)
    button.BorderSizePixel = 0
    button.BackgroundColor3 = Color3.fromRGB(62, 95, 91)
    button.TextColor3 = Color3.fromRGB(244, 248, 243)
    button.Font = Enum.Font.Code
    button.TextSize = 13
    button.Text = text
    button.Parent = parent
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = button
    button.MouseButton1Click:Connect(callback)
    return button
end

function Inspector.new(onTool, onExit, onFileSettings, onMaterial, onMaterialFlip)
    local self = setmetatable({}, Inspector)
    self.onTool = onTool
    self.onExit = onExit
    self.onFileSettings = onFileSettings
    self.onMaterial = onMaterial
    self.onMaterialFlip = onMaterialFlip
    self.materials = {}
    self.fileShape = 'Round'
    self.fileRadius = 1.25
    self.fileMaxRadius = 100
    self.material = nil
    self.kind = nil
    self.focusOffset = Vector3.zero
    self.yaw = 0
    self.pitch = 0.3
    self.distance = 8
    self.exiting = false
    self.returnElapsed = 0
    self.returnFrame = nil
    self.returnFocus = nil
    self.returnFOV = 70
    self.rightHeld = false
    self.middleHeld = false
    self.previousMouseBehavior = nil
    self.connections = {}
    self.lastRefresh = 0
    self.tools = {}

    local gui = Instance.new('ScreenGui')
    gui.Name = 'OpenworksPrecision'
    gui.ResetOnSpawn = false
    gui.Enabled = false
    gui.Parent = player:WaitForChild('PlayerGui')
    self.gui = gui

    local panel = Instance.new('Frame')
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position = UDim2.new(1, -18, 0, 86)
    panel.Size = UDim2.fromOffset(260, 330)
    panel.BorderSizePixel = 0
    panel.BackgroundColor3 = Color3.fromRGB(24, 30, 31)
    panel.Parent = gui
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = panel
    local stack = Instance.new('UIListLayout')
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Padding = UDim.new(0, 5)
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Parent = panel
    self.title = makeText(panel, 'OPENWORKS / INSPECT', 33, 16)
    self.title.LayoutOrder = 0
    self.name = makeText(panel, '', 27, 13)
    self.name.LayoutOrder = 1
    self.instructions = makeText(panel, '', 72, 12)
    self.instructions.LayoutOrder = 2
    self.progress = makeText(panel, '', 24, 12)
    self.progress.LayoutOrder = 3

    local fileSettings = Instance.new('Frame')
    fileSettings.Name = 'FileSettings'
    fileSettings.BackgroundTransparency = 1
    fileSettings.Size = UDim2.new(1, -14, 0, 120)
    fileSettings.Visible = false
    fileSettings.LayoutOrder = 4
    fileSettings.Parent = panel
    self.fileSettings = fileSettings

    local fileLayout = Instance.new('UIListLayout')
    fileLayout.SortOrder = Enum.SortOrder.LayoutOrder
    fileLayout.Padding = UDim.new(0, 3)
    fileLayout.Parent = fileSettings

    local heading = makeText(fileSettings, 'FILE PROFILE', 19, 12)
    heading.LayoutOrder = 1

    local function updateFileSize()
        self.fileRadius = math.clamp(self.fileRadius, 0.5, self.fileMaxRadius)
        self.sizeEntry.Text = string.format('%.2f', self.fileRadius)
        self.fileSizeHelp.Text = string.format('Profile size %.2f–%.2f mm', 0.5, self.fileMaxRadius)
        if self.kind == 'File' and self.onFileSettings then
            self.onFileSettings(self.fileShape, self.fileRadius)
        end
    end

    local profile = makeButton(fileSettings, 'ROUND  /  SWITCH PROFILE', function()
        self.fileShape = if self.fileShape == 'Round' then 'Chamfer' else 'Round'
        self.profileButton.Text = string.upper(self.fileShape) .. '  /  SWITCH PROFILE'
        updateFileSize()
    end)
    profile.LayoutOrder = 2
    self.profileButton = profile

    local sizeRow = Instance.new('Frame')
    sizeRow.BackgroundTransparency = 1
    sizeRow.Size = UDim2.new(1, -14, 0, 32)
    sizeRow.LayoutOrder = 3
    sizeRow.Parent = fileSettings

    local minus = makeButton(sizeRow, '-', function()
        self.fileRadius -= 0.25
        updateFileSize()
    end)
    minus.Position = UDim2.fromOffset(0, 0)
    minus.Size = UDim2.fromOffset(42, 32)

    local plus = makeButton(sizeRow, '+', function()
        self.fileRadius += 0.25
        updateFileSize()
    end)
    plus.AnchorPoint = Vector2.new(1, 0)
    plus.Position = UDim2.fromScale(1, 0)
    plus.Size = UDim2.fromOffset(42, 32)

    local sizeEntry = Instance.new('TextBox')
    sizeEntry.Name = 'FileSizeMM'
    sizeEntry.AnchorPoint = Vector2.new(0.5, 0)
    sizeEntry.Position = UDim2.fromScale(0.5, 0)
    sizeEntry.Size = UDim2.new(1, -94, 0, 32)
    sizeEntry.BackgroundColor3 = Color3.fromRGB(45, 54, 55)
    sizeEntry.BorderSizePixel = 0
    sizeEntry.TextColor3 = Color3.fromRGB(244, 248, 243)
    sizeEntry.Font = Enum.Font.Code
    sizeEntry.TextSize = 14
    sizeEntry.Text = '1.25'
    sizeEntry.PlaceholderText = 'mm'
    sizeEntry.ClearTextOnFocus = false
    sizeEntry.Parent = sizeRow
    local inputCorner = Instance.new('UICorner')
    inputCorner.CornerRadius = UDim.new(0, 5)
    inputCorner.Parent = sizeEntry
    self.sizeEntry = sizeEntry

    sizeEntry.FocusLost:Connect(function()
        local number = tonumber(sizeEntry.Text)
        if number then self.fileRadius = number end
        updateFileSize()
    end)

    local sizeHelp = makeText(fileSettings, 'Profile size in mm', 19, 11)
    sizeHelp.LayoutOrder = 4
    self.fileSizeHelp = sizeHelp

    local choices = Instance.new('ScrollingFrame')
    choices.Size = UDim2.new(1, -14, 0, 118)
    choices.BackgroundTransparency = 1
    choices.BorderSizePixel = 0
    choices.ScrollBarThickness = 3
    choices.CanvasSize = UDim2.new()
    choices.AutomaticCanvasSize = Enum.AutomaticSize.Y
    choices.LayoutOrder = 5
    choices.Parent = panel
    self.choices = choices
    local choiceStack = Instance.new('UIListLayout')
    choiceStack.Padding = UDim.new(0, 5)
    choiceStack.Parent = choices

    local materialFlip = Instance.new('Frame')
    materialFlip.Name = 'FlipMaterial'
    materialFlip.Size = UDim2.new(1, -14, 0, 34)
    materialFlip.BackgroundTransparency = 1
    materialFlip.Visible = false
    materialFlip.LayoutOrder = 7
    materialFlip.Parent = panel
    self.materialFlip = materialFlip

    for index, axis in {'X', 'Z'} do
        local button = makeButton(materialFlip, 'FLIP MATERIAL ' .. axis, function()
            if self.kind and self.onMaterialFlip then self.onMaterialFlip(axis) end
        end)
        button.Size = UDim2.new(0.5, -4, 1, 0)
        button.Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, 0)
    end

    local close = makeButton(panel, 'EXIT  [ESC]', function()
        self.onExit()
    end)
    close.LayoutOrder = 8

    table.insert(self.connections, UserInputService.InputBegan:Connect(function(input)
        if not self.material then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.rightHeld = true
            self.previousMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            self.middleHeld = true
        end
    end))
    table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
        if not self.material then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.rightHeld = false
            UserInputService.MouseBehavior = self.previousMouseBehavior or Enum.MouseBehavior.Default
            self.previousMouseBehavior = nil
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            self.middleHeld = false
        end
    end))
    table.insert(self.connections, UserInputService.InputChanged:Connect(function(input, processed)
        if not self.material then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
            self.distance = math.clamp(self.distance * (if input.Position.Z > 0 then 0.87 else 1.15), 1.5, 28)
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Delta
            if self.rightHeld then
                self.yaw -= delta.X * 0.006
                self.pitch = math.clamp(self.pitch + delta.Y * 0.006, -1.35, 1.35)
            elseif self.middleHeld then
                local camera = workspace.CurrentCamera
                local scale = self.distance / 650
                self.focusOffset += (-camera.CFrame.RightVector * delta.X + camera.CFrame.UpVector * delta.Y) * scale
            end
        end
    end))
    RunService:BindToRenderStep('OpenworksInspectionCamera',
        Enum.RenderPriority.Camera.Value + 2, function(dt)
        local camera = workspace.CurrentCamera
        if not camera then return end

        if not self.material then
            if not self.exiting then return end

            self.returnElapsed += math.min(dt, 0.1)
            local t = math.clamp(self.returnElapsed / 0.65, 0, 1)
            local eased = t * t * (3 - 2 * t)
            local naturalFrame = camera.CFrame
            local naturalFocus = camera.Focus

            camera.CFrame = self.returnFrame:Lerp(naturalFrame, eased)
            camera.Focus = self.returnFocus:Lerp(naturalFocus, eased)
            camera.FieldOfView = self.returnFOV
                + ((self.savedFOV or 70) - self.returnFOV) * eased

            if t >= 1 then
                self.exiting = false
            end
            return
        end

        local origin = itemPosition(self.material)
        if not origin then self.onExit() return end

        local focus = origin + self.focusOffset
        local horizontal = math.cos(self.pitch) * self.distance
        local displacement = Vector3.new(
            math.sin(self.yaw) * horizontal,
            math.sin(self.pitch) * self.distance,
            math.cos(self.yaw) * horizontal
        )
        local goal = CFrame.lookAt(focus + displacement, focus)
        local alpha = 1 - math.exp(-11 * math.min(dt, 0.1))

        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = camera.CFrame:Lerp(goal, alpha)
        camera.Focus = camera.Focus:Lerp(CFrame.new(focus), alpha)
        camera.FieldOfView += (62 - camera.FieldOfView) * alpha
    end)

    return self
end

function Inspector:refreshTools()
    if not self.material or self.kind then return end
    local available = {}
    for _, node in workspace:GetDescendants() do
        if (node:IsA('Model') or node:IsA('BasePart'))
            and node:GetAttribute('isTool') == true
            and (node:GetAttribute('OnWorkbench') == true
                or node == workspace:FindFirstChild('Scorer')) then
            table.insert(available, node)
        end
    end
    table.sort(available, function(a, b) return a.Name < b.Name end)
    if #available == #self.tools then
        local same = true
        for i, tool in available do
            if self.tools[i] ~= tool then same = false break end
        end
        if same then return end
    end
    self.tools = available
    for _, child in self.choices:GetChildren() do
        if child:IsA('TextButton') or child:IsA('TextLabel') then child:Destroy() end
    end
    if #available == 0 then
        makeText(self.choices, 'Place a saw, file, or scorer on the workbench', 54, 12)
    else
        for _, tool in available do
            makeButton(self.choices, tool.Name:upper(), function()
                self.onTool(tool)
            end)
        end
    end
end

function Inspector:refreshMaterials(force)
    if not self.material or not self.kind then return end

    local found = {}
    for _, node in workspace:GetDescendants() do
        if (node:IsA('BasePart') or node:IsA('Model'))
            and FORMMaterial.isMarked(node)
            and node:GetAttribute('OnWorkbench') == true then
            table.insert(found, node)
        end
    end

    table.sort(found, function(a, b)
        if a.Name ~= b.Name then return a.Name < b.Name end
        return a:GetFullName() < b:GetFullName()
    end)

    local changed = force == true or #found ~= #self.materials
    if not changed then
        for i, item in found do
            if self.materials[i] ~= item then
                changed = true
                break
            end
        end
    end
    self.materials = found
    if not changed then return end

    for _, child in self.choices:GetChildren() do
        if child:IsA('TextButton') or child:IsA('TextLabel') then
            child:Destroy()
        end
    end

    if #found == 0 then
        makeText(self.choices, 'No workpieces on the bench', 44, 12)
        return
    end

    for i, item in found do
        local current = item == self.material
        local text = tostring(i) .. '  ' .. item.Name
            .. (if current then '  [ACTIVE]' else '')
        local choice = makeButton(self.choices, text, function()
            if self.onMaterial then self.onMaterial(item) end
        end)
        choice.LayoutOrder = i
        if current then
            choice.BackgroundColor3 = Color3.fromRGB(91, 112, 81)
        end
    end
end

function Inspector:focusMaterial(material)
    if not material or not material.Parent or not self.material then return end

    self.material = material
    self.name.Text = material.Name
    self.focusOffset = Vector3.zero

    local size = if material:IsA('BasePart') then material.Size else material:GetExtentsSize()
    self.distance = math.clamp(math.max(size.X, size.Y, size.Z) * 3.5, 4, 15)

    if self.kind == 'File' then
        local dimension = if material:GetAttribute('FORMContourMode') == true
            then math.min(size.X, size.Z) else size.Y
        local limit = math.floor(dimension / 0.04 * 0.42 * 100) / 100
        self.fileMaxRadius = math.max(0.5, math.min(100, limit))
        self.fileRadius = math.clamp(self.fileRadius, 0.5, self.fileMaxRadius)
        self.sizeEntry.Text = string.format('%.2f', self.fileRadius)
        self.fileSizeHelp.Text = string.format('Profile size 0.50–%.2f mm', self.fileMaxRadius)
        if self.onFileSettings then
            self.onFileSettings(self.fileShape, self.fileRadius)
        end
    end

    self:refreshMaterials(true)
end

function Inspector:open(material)
    if not material or not material.Parent then return end

    local camera = workspace.CurrentCamera
    local wasInspecting = self.material ~= nil

    if not wasInspecting and not self.exiting then
        self.savedType = camera.CameraType
        self.savedSubject = camera.CameraSubject
        self.savedFOV = camera.FieldOfView
    end

    self.exiting = false

    if not wasInspecting then
        local center = itemPosition(material)
        local offset = camera.CFrame.Position - center
        if offset.Magnitude > 0.01 then
            self.yaw = math.atan2(offset.X, offset.Z)
            self.pitch = math.asin(math.clamp(offset.Y / offset.Magnitude, -0.95, 0.95))
        end
    end

    self.material = material
    local size = if material:IsA('BasePart') then material.Size else material:GetExtentsSize()
    self.distance = math.clamp(math.max(size.X, size.Y, size.Z) * 3.5, 4, 15)
    self.focusOffset = Vector3.zero
    camera.CameraType = Enum.CameraType.Scriptable

    ContextActionService:BindActionAtPriority('OpenworksInspectMovement',
        function()
            return Enum.ContextActionResult.Sink
        end, false, 4000, Enum.KeyCode.W, Enum.KeyCode.A,
        Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
        Enum.KeyCode.Up, Enum.KeyCode.Down,
        Enum.KeyCode.Left, Enum.KeyCode.Right)

    self.name.Text = material.Name
    self.gui.Enabled = true
    self:setTool(nil)
    self:refreshTools()
end

function Inspector:setTool(kind)
    self.kind = kind
    self.fileSettings.Visible = kind == 'File'
    self.materialFlip.Visible = kind ~= nil
    self.gui.Enabled = self.material ~= nil
    local panel = self.title.Parent
    panel.Size = UDim2.fromOffset(260, if kind == 'File' then 540
        elseif kind == 'Saw' or kind == 'Scorer' then 440 else 350)

    if kind == 'File' and self.material then
        local thickness = if self.material:IsA('BasePart') then self.material.Size.Y
            else self.material:GetExtentsSize().Y
        local dimension = if self.material:GetAttribute('FORMContourMode') == true
            then (if self.material:IsA('BasePart')
                then math.min(self.material.Size.X, self.material.Size.Z)
                else math.min(self.material:GetExtentsSize().X, self.material:GetExtentsSize().Z))
            else thickness
        self.fileMaxRadius = math.max(0.5, math.min(100,
            math.floor(dimension / 0.04 * 0.42 * 100) / 100))
        self.fileRadius = math.clamp(self.fileRadius, 0.5, self.fileMaxRadius)
        self.sizeEntry.Text = string.format('%.2f', self.fileRadius)
        self.fileSizeHelp.Text = string.format('Profile size 0.50–%.2f mm', self.fileMaxRadius)
        self.profileButton.Text = string.upper(self.fileShape) .. '  /  SWITCH PROFILE'
    end
    self.progress.Text = ''
    self.title.Text = if kind then 'OPENWORKS / ' .. string.upper(kind) else 'OPENWORKS / INSPECT'
    self.instructions.Text = if kind == 'Saw' then
        'Click a score: automatically follow and cut\nUnmarked metal: hold LMB and stroke manually\nQ: freehand axis | Esc: cancel / exit'
        elseif kind == 'File' then
        'Hover edge: green guide snaps onto contour\nHold LMB: lock edge and file along it\nP: move | R: roll file | Esc: exit'
        elseif kind == 'Scorer' then
        'LMB + drag: score exposed surface\nRelease: save permanent score path\nP: move metal | X/Z: flip | Esc: exit'
        else 'RMB: orbit | MMB: pan | wheel: zoom\nChoose a physical tool resting on the table.'
    self.choices.Visible = true
    if kind then
        self:refreshMaterials(true)
    else
        self.materials = {}
        self.tools = {}
        self:refreshTools()
    end
end

function Inspector:status(message)
    self.progress.Text = message
end

function Inspector:close()
    if not self.material then return end

    local camera = workspace.CurrentCamera
    self.returnFrame = camera.CFrame
    self.returnFocus = camera.Focus
    self.returnFOV = camera.FieldOfView
    self.returnElapsed = 0

    self.material = nil
    self.kind = nil
    self.materials = {}
    self.gui.Enabled = false
    self.exiting = true

    local wasRightHeld = self.rightHeld
    self.rightHeld = false
    self.middleHeld = false
    ContextActionService:UnbindAction('OpenworksInspectMovement')
    if wasRightHeld or self.previousMouseBehavior then
        UserInputService.MouseBehavior = self.previousMouseBehavior or Enum.MouseBehavior.Default
        self.previousMouseBehavior = nil
    end

    camera.CameraType = self.savedType or Enum.CameraType.Custom
    if self.savedSubject then camera.CameraSubject = self.savedSubject end
end

return Inspector
