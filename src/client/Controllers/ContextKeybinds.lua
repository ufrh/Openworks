--!strict
-- Compact context-sensitive shortcuts: left of Assembly/Simulate HUD,
-- right of ordinary Build/Edit where they do not obscure the construction.
-- No buttons here: this only documents the controls that actually exist.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Theme=require(script.Parent:WaitForChild("StudioTheme"))

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
    if not tool then return { "Choose a tool: 1–5" } end
    if c.PendingMateChoice then
        if c.SmartMatch and c.SmartMatch.kind=="Hub" then
            append(lines,"CLICK","Gear mount: Rotation or Rigid")
        else
            append(lines,"CLICK","Choose rotation, slide, bearing or fit")
            append(lines,"ADJUST","Set shaft depth/roll before selecting")
        end
        append(lines,"ESC","Cancel • numeric hotbar disabled")
        return lines
    end
    if c.Numeric and c.Numeric.Active then
        append(lines,"X Y Z","Type dimensions in U")
        append(lines,"Enter","Apply precise size")
        append(lines,"Esc","Cancel")
        return lines
    end
    if tool=="Weld" then
        append(lines,"Click","Select first solid, then second to weld")
        append(lines,"Esc","Cancel weld selection")
        return lines
    end
    if tool=="Simulate" then
        local running=player:GetAttribute("OPENWORKS_Simulating")==true
        if player:GetAttribute("OPENWORKS_PropertiesOpen")==true then
            append(lines,"LMB","Pick relationship / edit settings")
            append(lines,"Esc","Close inspector and lock pointer")
            append(lines,"RMB hold","Look around while inspector open")
        elseif running then
            append(lines,"P","Stop registered assembly")
            append(lines,"O","Pause / resume physics")
            append(lines,"U","Reset assembly to authored pose")
            append(lines,"I","Inspect joint telemetry")
            append(lines,"Click","Inspect body / relationships")
            append(lines,"Hold LMB","Drive crank at fixed speed; release to stop")
        else
            append(lines,"P","Run registered assembly")
            append(lines,"Shift+P","Run assembly ungrounded")
            append(lines,"G","Toggle aimed body grounding")
            append(lines,"Click","Inspect body / relationships")
            append(lines,"Assembly tool","Create and choose assembly members")
        end
        append(lines,"Purple","Assembly P will simulate")
        append(lines,"Green / Orange","Grounded / movable body fills")
        append(lines,"Z / Shift+Z","Camera zoom in / out")
        return lines
    end
    if player:GetAttribute("OPENWORKS_Simulating")==true then
        -- Other tools have no simulation editing authority.
        append(lines,"Simulate tool","Stop or inspect running assembly")
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
            append(lines, "N", "Enter exact dimensions in U")
            append(lines, "V / Esc", "Exit scale")
        elseif c.CatalogOpen then
            append(lines, "LMB", "Choose primitive")
            append(lines, "B / Esc", "Close catalog")
        else
            append(lines, "LMB", "Place / multi-point fit")
            append(lines, "B / V / N", "Catalog / resize / exact U")
            if c.SmartMatch then
                append(lines, "Tab", "Next compatible target")
                if c.SmartMatch.kind=="Bore" then
                    if c.LockedAlignment then
                        append(lines,"Wheel / Q E","Depth / roll (after alignment)")
                        append(lines,"Click","Finalize / choose passive joint")
                        append(lines,"Esc","Re-align")
                    else
                        append(lines,"Click","Choose relationship popup")
                    end
                elseif c.SmartMatch.kind=="Hub" then
                    append(lines, "Click", "Choose Rotation / Rigid gear mount")
                elseif c.SmartMatch.kind=="BoltHole" then
                    append(lines, "Bolt", "Fasten holes reached by prefab")
                end
                append(lines, "Alt", "Temporarily bypass snap")
            else
                append(lines, "R T Y", "Rotate axes")
            end
        end
    elseif tool == "Edit" then
        if a.ManualActive then
            if a.Stage=="PairFirst" or a.Stage=="PairSecond" then
                append(lines,"LMB",if a.Stage=="PairFirst"
                    then "Select first part" else "Select second part")
                append(lines,"Mode",tostring(a.PairKind))
                if a.PairKind=="CrankCoupling" then
                    append(lines,"Valid","Coaxial crank output touching a shaft end")
                elseif a.PairKind=="Spring" then
                    append(lines,"Valid","Any two components; no size or shape requirement")
                elseif a.PairKind=="Bolt" then
                    append(lines,"Valid","Two matching coaxial holes")
                else
                    append(lines,"Valid","Touching solid faces")
                end
                append(lines,"Esc","Cancel")
            elseif a.Stage=="GearFirst" or a.Stage=="GearSecond" then
                append(lines,"Click","Choose gear to mesh")
                append(lines,"K / Esc","Cancel gear connection")
            elseif a.Stage=="JointSettings" then
                append(lines,"Simulate","Use the relationship properties panel")
            else
                append(lines,"Click","Housing then shaft")
                append(lines,"R","Change relationship")
                append(lines,"Wheel / Q E","Depth / rotation")
                append(lines,"Esc","Exit manual relationship")
            end
        elseif c.ScaleMode then
            append(lines, "LMB hold", "Grab face")
            append(lines, "Move / Look", "Resize in 3D")
            append(lines, "Step", tostring(c.ScaleHandles.IncrementU) .. " U")
            append(lines, "Release", "Apply size")
            append(lines, "N", "Enter exact dimensions in U")
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
                    if c.LockedAlignment then
                        append(lines,"Wheel / Q E","Depth / roll (after alignment)")
                        append(lines,"Click","Finalize / choose passive joint")
                        append(lines,"Esc","Re-align")
                    else
                        append(lines,"Click","Choose relationship popup")
                    end
                elseif c.SmartMatch.kind=="Hub" then
                    append(lines, "Click", "Choose Rotation / Rigid gear mount")
                elseif c.SmartMatch.kind=="BoltHole" then
                    append(lines, "Bolt", "Fasten holes reached by prefab")
                end
            else
                append(lines, "R T Y", "World-axis rotation")
            end
            append(lines, "Esc", "Cancel")
        else
            append(lines, "LMB", "Select editor group")
            append(lines, "Double click", "Edit member inside component")
            append(lines, "Hold selected", "Drag to auto-align")
            append(lines, "Alt+LMB", "Cycle deeper layers")
            append(lines, "V / N / G", "Scale / exact size / Move")
            if c.Selected and type(c.Selected:GetAttribute("AlignedOpeningId"))=="string" then
                append(lines,"V","Resize aligned shaft length only")
            end
            append(lines, "R / T / Y", "World-axis rotation")
            append(lines, "L", "Manual align")
            append(lines,"Auto gear mesh","Engages by tooth pitch and spacing in Simulate")
            append(lines,"H","Manual joint authoring")
            append(lines,"Shift+J","Spring between any two components")
            append(lines,"Shift+C","Couple crank output to shaft end")
            append(lines,"Weld tool","Manually join touching solids")
            append(lines,"Build > Fasteners","Drag prefab bolts into real holes")
            append(lines,"Assembly tool","Name and select assembly members")
            append(lines, "C / U", "Combine / Ungroup")
            append(lines, "E", "Edit group interior")
            append(lines, "F / Del", "Duplicate / Delete")
            append(lines, "Tab / X / I", "Depth / X-ray / Isolate")
        end
    elseif tool=="Assembly" then
        append(lines,"N","Create and name new assembly")
        append(lines,"Enter","Confirm selected members")
        append(lines,"LMB","Toggle entire component / primitive")
        append(lines,"Alt+LMB","Toggle only the aimed primitive")
        append(lines,"Click existing","Edit existing assembly")
        append(lines,"R","Rename selected assembly")
        append(lines,"Ctrl+Z / Ctrl+Y","Undo / redo membership")
        append(lines,"Esc","Cancel the draft")
    elseif tool == "Inspect" then
        append(lines, "LMB", "Inspect")
        append(lines, "Tab", "Cycle depth")
        append(lines, "X / I", "X-ray / Isolate")
    end
    append(lines,"Z / Shift+Z","Camera zoom in / out")
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
    panel.BackgroundColor3 = Theme.Window
    panel.BackgroundTransparency = 0.12
    panel.BorderSizePixel = 0
    panel.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.Radius)
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
    self.ChromeConnection=Theme.Attach(gui)
    self.Panel = panel
    self.Body = body
    self.Title = title
    self.Connection = RunService.RenderStepped:Connect(function()
        local now = os.clock()
        if now - self.LastUpdate < 0.15 then return end
        self.LastUpdate = now
        local mode = self.Tools.ActiveId
        self.Panel.Visible=mode~=nil
        if not mode then return end
        local sim=mode=="Simulate"
        local assembly=mode=="Assembly"
        self.Panel.AnchorPoint=if sim or assembly then Vector2.new(0,0)
            else Vector2.new(1,0)
        self.Panel.Position=if sim then UDim2.fromOffset(16,190)
            elseif assembly then UDim2.fromOffset(16,231)
            else UDim2.new(1,-16,0,145)
        self.Panel.Size=if sim then UDim2.fromOffset(312,318)
            elseif assembly then UDim2.fromOffset(328,281)
            else UDim2.fromOffset(244,247)
        self.Title.Text=if sim then "SIMULATION / CONTROLS"
            elseif assembly then "ASSEMBLY / CONTROLS"
            else "CONTROLS  /  "..string.upper(mode)
        local value = table.concat(self:Lines(), "\n")
        if self.LastText ~= value then
            self.Body.Text = value
            self.LastText = value
        end
    end)
end

function Context:Destroy()
    if self.Connection then self.Connection:Disconnect() end
    if self.ChromeConnection then self.ChromeConnection:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end

return Context
