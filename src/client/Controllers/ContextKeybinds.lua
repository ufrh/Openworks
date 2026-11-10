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
    if player:GetAttribute("OPENWORKS_Simulating") == true then
        append(lines, "P", "Stop physics")
        append(lines, "M", "Motor on / off")
        append(lines, "N", "Reverse drive")
        append(lines, "[  ]", "Motor speed")
        append(lines, "O / U", "Pause / Reset physics")
        append(lines, "I", "Inspect joint telemetry")
        return lines
    end

    -- Only list actions possible IN THE CURRENT CONTEXT; submenus narrow
    -- rather than continuing to show the entire tool's shortcut catalog.
    if tool == "Build" then
        if c.ScaleMode then
            append(lines, "LMB hold", "Grab face")
            append(lines, "Move / Look", "Resize in 3D")
            append(lines, "Step", tostring(c.ScaleHandles.IncrementU) .. " U")
            append(lines, "Release", "Apply size")
            append(lines, "V / Esc", "Exit scale")
        elseif c.CatalogOpen then
            append(lines, "LMB", "Choose primitive")
            append(lines, "B / Esc", "Close catalog")
        else
            append(lines, "LMB", "Place / auto-attach")
            append(lines, "B / V", "Catalog / resize")
            if c.SmartMatch then
                append(lines, "Tab", "Next compatible target")
                if c.SmartMatch.kind=="Bore" then
                    append(lines, "Wheel / Q E", "Depth / shaft roll")
                    append(lines, "C", "Rigid / Bearing / Slider / Cylindrical")
                elseif c.SmartMatch.kind=="Hub" then
                    append(lines, "Hub", "Rigid gear-on-shaft mount")
                end
                append(lines, "Alt", "Temporarily bypass snap")
            else
                append(lines, "R T Y", "Rotate axes")
            end
        end
    elseif tool == "Edit" then
        if c.ScaleMode then
            append(lines, "LMB hold", "Grab face")
            append(lines, "Move / Look", "Resize in 3D")
            append(lines, "Step", tostring(c.ScaleHandles.IncrementU) .. " U")
            append(lines, "Release", "Apply size")
            append(lines, "V / Esc", "Exit scale")
        elseif c.Layered and c.Layered.Alignment then
            local align = c.Layered.Alignment
            if align.Stage == "PickTarget" then
                append(lines, "LMB", "Choose opening")
                append(lines, "Tab", "Cycle depth")
            elseif align.Stage == "Fit" then
                append(lines, "Wheel / [ ]", "Shaft fit ±0.05 U")
                append(lines, "Alt+wheel", "Change insertion depth")
                append(lines, "Q / E", "Rotate shaft in bore")
                append(lines, "LMB / Esc", "Finish fitting")
            else
                append(lines, "Wheel / [ ]", "Insertion depth")
                append(lines, "Q / E", "Live shaft roll")
                append(lines, "LMB", "Confirm when blue")
            end
            append(lines, "L / Esc", "Cancel alignment")
        elseif c.Pending then
            append(lines, "Look / Walk", "Position preview")
            append(lines, "Release / Click", "Move / auto-attach")
            if c.SmartMatch then
                append(lines, "Tab / Alt", "Change target / bypass")
                if c.SmartMatch.kind=="Bore" then
                    append(lines, "Wheel / Q E", "Depth / shaft roll")
                    append(lines, "C", "Rigid / Bearing / Slider / Cylindrical")
                elseif c.SmartMatch.kind=="Hub" then
                    append(lines, "Hub", "Rigid gear-on-shaft mount")
                end
            else
                append(lines, "R T Y", "World-axis rotation")
            end
            append(lines, "Esc", "Cancel")
        else
            append(lines, "LMB", "Select component")
            append(lines, "Double click", "Edit member inside component")
            append(lines, "Hold selected", "Drag to auto-align")
            append(lines, "Alt+LMB", "Cycle deeper layers")
            append(lines, "V / G", "Scale / Move")
            if c.Selected and type(c.Selected:GetAttribute("AlignedOpeningId"))=="string" then
                append(lines,"V","Resize aligned shaft length only")
            end
            append(lines, "R / T / Y", "World-axis rotation")
            append(lines, "L", "Align shaft")
            append(lines, "C / U", "Combine / Ungroup")
            append(lines, "E", "Edit group interior")
            append(lines, "F / Del", "Duplicate / Delete")
            append(lines, "Tab / X / I", "Depth / X-ray / Isolate")
        end
    elseif tool == "Assemble" then
        if a.Stage=="GearFirst" then
            append(lines,"LMB","Choose driving gear")
            append(lines,"K / Esc","Cancel gear mesh")
        elseif a.Stage=="GearSecond" then
            append(lines,"LMB","Choose mating gear")
            append(lines,"K / Esc","Cancel gear mesh")
        elseif a.Stage=="JointSettings" then
            append(lines,"U","Toggle motion limits")
            append(lines,"[  ]","Adjust limit range")
            append(lines,"Esc","Close joint settings")
        elseif a.Stage=="Preview" then
            append(lines,"Wheel / [ ]","Insertion depth")
            append(lines,"Q / E","Rotate shaft around bore")
            append(lines,"LMB","Create selected joint")
            append(lines,"Esc","Cancel")
        elseif a.Stage=="Fit" then
            append(lines,"Wheel / [ ]","Diameter ±0.05 U")
            append(lines,"Alt+wheel","Insertion depth")
            append(lines,"Q / E","Shaft rotation")
            append(lines,"LMB / Esc","Finish fitting")
        else
            append(lines,"LMB",if a.Stage=="Housing"
                then "Choose housing" else "Choose shaft/body")
            append(lines,"R","Bearing / Slider / Cylinder / Fixed")
            append(lines,"K","Connect a gear pair")
            append(lines,"G","Toggle body grounding")
            append(lines,"J","Edit existing joint")
            append(lines,"P / Shift+P","Simulate grounded / free")
            append(lines,"Del","Delete aimed relationship")
        end
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
