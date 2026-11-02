local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

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

function Inspector.new(onTool, onExit)
    local self = setmetatable({}, Inspector)
    self.onTool = onTool
    self.onExit = onExit
    self.material = nil
    self.kind = nil
    self.focusOffset = Vector3.zero
    self.yaw = 0
    self.pitch = 0.3
    self.distance = 8
    self.rightHeld = false
    self.middleHeld = false
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

    local choices = Instance.new('ScrollingFrame')
    choices.Size = UDim2.new(1, -14, 0, 118)
    choices.BackgroundTransparency = 1
    choices.BorderSizePixel = 0
    choices.ScrollBarThickness = 3
    choices.CanvasSize = UDim2.new()
    choices.AutomaticCanvasSize = Enum.AutomaticSize.Y
    choices.LayoutOrder = 4
    choices.Parent = panel
    self.choices = choices
    local choiceStack = Instance.new('UIListLayout')
    choiceStack.Padding = UDim.new(0, 5)
    choiceStack.Parent = choices

    local close = makeButton(panel, 'EXIT  [ESC]', function()
        self.onExit()
    end)
    close.LayoutOrder = 5

    table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not self.material or processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then self.rightHeld = true end
        if input.UserInputType == Enum.UserInputType.MouseButton3 then self.middleHeld = true end
    end))
    table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then self.rightHeld = false end
        if input.UserInputType == Enum.UserInputType.MouseButton3 then self.middleHeld = false end
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
    table.insert(self.connections, RunService.RenderStepped:Connect(function()
        if not self.material then return end
        local origin = itemPosition(self.material)
        if not origin then self.onExit() return end

        local camera = workspace.CurrentCamera
        local focus = origin + self.focusOffset
        local horizontal = math.cos(self.pitch) * self.distance
        local displacement = Vector3.new(
            math.sin(self.yaw) * horizontal,
            math.sin(self.pitch) * self.distance,
            math.cos(self.yaw) * horizontal
        )
        camera.CFrame = CFrame.lookAt(focus + displacement, focus)
    end))

    return self
end

function Inspector:refreshTools()
    if not self.material or self.kind then return end
    local available = {}
    for _, node in workspace:GetDescendants() do
        if (node:IsA('Model') or node:IsA('BasePart'))
            and node:GetAttribute('isTool') == true
            and node:GetAttribute('OnWorkbench') == true then
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
        makeText(self.choices, 'Place a saw or file on the workbench', 54, 12)
    else
        for _, tool in available do
            makeButton(self.choices, tool.Name:upper(), function()
                self.onTool(tool)
            end)
        end
    end
end

function Inspector:open(material)
    self:close()
    self.material = material
    local camera = workspace.CurrentCamera
    self.savedType = camera.CameraType
    self.savedSubject = camera.CameraSubject
    self.savedFOV = camera.FieldOfView

    local size = if material:IsA('BasePart') then material.Size else material:GetExtentsSize()
    self.distance = math.clamp(math.max(size.X, size.Y, size.Z) * 3.5, 4, 15)
    local center = itemPosition(material)
    local offset = camera.CFrame.Position - center
    if offset.Magnitude > 0.01 then
        self.yaw = math.atan2(offset.X, offset.Z)
        self.pitch = math.asin(math.clamp(offset.Y / offset.Magnitude, -0.95, 0.95))
    end
    self.focusOffset = Vector3.zero
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 62

    local ok, controls = pcall(function()
        return require(player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule')):GetControls()
    end)
    if ok then self.controls = controls controls:Disable() end

    self.name.Text = material.Name
    self.gui.Enabled = true
    self:setTool(nil)
    self:refreshTools()
end

function Inspector:setTool(kind)
    self.kind = kind
    self.progress.Text = ''
    self.title.Text = if kind then 'OPENWORKS / ' .. string.upper(kind) else 'OPENWORKS / INSPECT'
    self.instructions.Text = if kind then
        'LMB + move mouse sideways: manual strokes\nSHIFT + move mouse: position cut\nQ: change cut axis | RMB: orbit | ESC: exit'
        else 'RMB: orbit | MMB: pan | wheel: zoom\nChoose a physical tool resting on the table.'
    self.choices.Visible = kind == nil
    if not kind then self.tools = {} self:refreshTools() end
end

function Inspector:status(message)
    self.progress.Text = message
end

function Inspector:close()
    if not self.material then return end
    self.material = nil
    self.kind = nil
    self.gui.Enabled = false
    self.rightHeld = false
    self.middleHeld = false
    if self.controls then self.controls:Enable() self.controls = nil end
    local camera = workspace.CurrentCamera
    camera.CameraType = self.savedType or Enum.CameraType.Custom
    if self.savedSubject then camera.CameraSubject = self.savedSubject end
    if self.savedFOV then camera.FieldOfView = self.savedFOV end
end

return Inspector
