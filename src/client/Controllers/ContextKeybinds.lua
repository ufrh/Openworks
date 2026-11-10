--!strict
-- Compact context-sensitive shortcut list, right side under the active HUD.
-- No buttons here: this only documents the controls that actually exist.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Context = {}
Context.__index = Context

local function append(lines, key, action)
    table.insert(lines, key .. "   " .. action)
end

function Context.new(tools, construction, assembly)
    return setmetatable({
        Tools = tools,
        Construction = construction,
        Assembly = assembly,
        LastText = nil,
        LastUpdate = 0,
    }, Context)
end

function Context:Lines()
    local tool = self.Tools.ActiveId
    local c = self.Construction
    local a = self.Assembly
    local lines = {}
    if not tool then return { "Choose a tool: 1–4" } end

    -- Only list actions possible IN THE CURRENT CONTEXT; submenus narrow
    -- rather than continuing to show the entire tool's shortcut catalog.
    if tool == "Build" then
        if c.ScaleMode then
            append(lines, "LMB hold", "Grab face")
            append(lines, "Move / Look", "Resize in 3D")
            append(lines, "[  ]", "Step: " .. tostring(c.ScaleStepU) .. " U")
            append(lines, "Release", "Apply size")
            append(lines, "V / Esc", "Exit scale")
        elseif c.CatalogOpen then
            append(lines, "LMB", "Choose primitive")
            append(lines, "B / Esc", "Close catalog")
        else
            append(lines, "LMB", "Place when blue")
            append(lines, "B", "Choose primitive")
            append(lines, "V", "Resize")
            append(lines, "R / T / Y", "Rotate axes")
        end
    elseif tool == "Edit" then
        if c.ScaleMode then
            append(lines, "LMB hold", "Grab face")
            append(lines, "Move / Look", "Resize in 3D")
            append(lines, "[  ]", "Step: " .. tostring(c.ScaleStepU) .. " U")
            append(lines, "Release", "Apply size")
            append(lines, "V / Esc", "Exit scale")
        elseif c.Layered and c.Layered.Alignment then
            local align = c.Layered.Alignment
            if align.Stage == "PickTarget" then
                append(lines, "LMB", "Choose opening")
                append(lines, "Tab", "Cycle depth")
            else
                append(lines, "Wheel / [ ]", "Insertion depth")
                append(lines, "LMB", "Confirm when blue")
            end
            append(lines, "L / Esc", "Cancel alignment")
        elseif c.RotateHandles and c.RotateHandles.Drag then
            append(lines, "Hold LMB", "Rotate around ring")
            append(lines, "Move / Look", "World-space rotation")
            append(lines, "Release", "Confirm quarter turn")
        elseif c.MoveHandles and c.MoveHandles.Drag then
            append(lines, "Hold LMB", "Move along axis")
            append(lines, "Move / Look", "World-space drag")
            append(lines, "Release", "Confirm")
        elseif c.Pending then
            append(lines, "Look / Walk", "Position preview")
            append(lines, "LMB", "Place when blue")
            append(lines, "R / T / Y", "Rotate")
            append(lines, "Esc", "Cancel")
        else
            append(lines, "LMB", "Select; hold to drag")
            append(lines, "Arrows / Rings", "Move / Rotate handles")
            append(lines, "V / G", "Scale / Move")
            append(lines, "R / T / Y", "Rotate")
            append(lines, "L", "Align shaft")
            append(lines, "C / U", "Combine / Ungroup")
            append(lines, "E", "Edit group interior")
            append(lines, "F / Del", "Duplicate / Delete")
            append(lines, "Tab / X / I", "Depth / X-ray / Isolate")
        end
    elseif tool == "Assemble" then
        if a.Stage == "Housing" then
            append(lines, "LMB", "Choose housing")
            append(lines, "R", "Change relationship")
        elseif a.Stage == "Source" then
            append(lines, "LMB", "Choose shaft/body")
            append(lines, "R", "Change relationship")
        else
            append(lines, "Wheel / [ ]", "Insertion depth")
            append(lines, "LMB", "Finalize when blue")
            append(lines, "R", "Change relationship")
        end
        append(lines, "Del", "Remove aimed joint")
        append(lines, "Esc", "Reset")
    elseif tool == "Inspect" then
        append(lines, "LMB", "Inspect")
        append(lines, "Tab", "Cycle depth")
        append(lines, "X / I", "X-ray / Isolate")
    end
    return lines
end

function Context:Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "OPENWORKS_ContextKeybinds"
    gui.DisplayOrder = 39
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")

    local panel = Instance.new("Frame")
    panel.Name = "BindsPanel"
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position = UDim2.new(1, -16, 0, 145)
    panel.Size = UDim2.fromOffset(244, 247)
    panel.BackgroundColor3 = Color3.fromRGB(22, 29, 38)
    panel.BackgroundTransparency = 0.12
    panel.BorderSizePixel = 0
    panel.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -20, 0, 27)
    title.Position = UDim2.fromOffset(10, 5)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(221, 235, 245)
    title.Text = "CONTROLS / ACTIVE TOOL"
    title.Parent = panel

    local list = Instance.new("ScrollingFrame")
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.Position = UDim2.fromOffset(10, 39)
    list.Size = UDim2.new(1, -20, 1, -47)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.ScrollBarThickness = 3
    list.Parent = panel

    local body = Instance.new("TextLabel")
    body.Name = "Shortcuts"
    body.BackgroundTransparency = 1
    body.Position = UDim2.fromOffset(0, 0)
    body.Size = UDim2.new(1, -6, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.Font = Enum.Font.GothamMedium
    body.TextSize = 12
    body.LineHeight = 1.55
    body.TextColor3 = Color3.fromRGB(182, 208, 224)
    body.Parent = list

    self.Gui = gui
    self.Panel = panel
    self.Body = body
    self.Title = title
    self.Connection = RunService.RenderStepped:Connect(function()
        local now = os.clock()
        if now - self.LastUpdate < 0.15 then return end
        self.LastUpdate = now
        local mode = self.Tools.ActiveId
        self.Panel.Visible = mode ~= nil
        if not mode then return end
        self.Title.Text = "CONTROLS  /  " .. string.upper(mode)
        local value = table.concat(self:Lines(), "\n")
        if self.LastText ~= value then
            self.Body.Text = value
            self.LastText = value
        end
    end)
end

function Context:Destroy()
    if self.Connection then self.Connection:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end

return Context
