--!strict
-- Phase 05: direct first-person mechanical relationship authoring.
-- Housing -> shaft/component -> axial offset -> create Bearing/Slider/Fixed.
-- No mouse unlock or custom Tool/hotbar. Native physics constraints are
-- authored while parts remain anchored in the construction phase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Config = require(construction:WaitForChild("BuildConfig"))
local Grid = require(construction:WaitForChild("GridMath"))
local Alignment = require(construction:WaitForChild("AlignmentMath"))

local TYPES = { "Bearing", "Slider", "Fixed" }
local Controller = {}
Controller.__index = Controller

local function constructedFolder()
    return workspace:FindFirstChild(Config.FolderName)
end

local function createGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "OPENWORKS_AssemblyHUD"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 41
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    -- The Build/Edit crosshair is inside a ScreenGui that is disabled
    -- while Assemble is equipped. Give Assemble the same aim reference,
    -- centered on the exact camera ray used by Pick().
    local crosshair = Instance.new("TextLabel")
    crosshair.Name = "AssemblyCrosshair"
    crosshair.BackgroundTransparency = 1
    crosshair.BorderSizePixel = 0
    crosshair.Size = UDim2.fromOffset(20, 20)
    crosshair.Position = UDim2.fromScale(0.5, 0.5)
    crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
    crosshair.Text = "+"
    crosshair.TextSize = 21
    crosshair.Font = Enum.Font.GothamMedium
    crosshair.TextColor3 = Color3.fromRGB(229, 238, 245)
    crosshair.TextXAlignment = Enum.TextXAlignment.Center
    crosshair.TextYAlignment = Enum.TextYAlignment.Center
    crosshair.ZIndex = 50
    crosshair.Parent = gui

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(380, 116)
    panel.Position = UDim2.new(1, -396, 0, 20)
    panel.BackgroundColor3 = Color3.fromRGB(22, 29, 38)
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.Parent = gui
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0, 9)
    round.Parent = panel

    local function label(y, height, fontSize, color)
        local object = Instance.new("TextLabel")
        object.BackgroundTransparency = 1
        object.Position = UDim2.fromOffset(12, y)
        object.Size = UDim2.new(1, -24, 0, height)
        object.TextXAlignment = Enum.TextXAlignment.Left
        object.TextYAlignment = Enum.TextYAlignment.Center
        object.TextWrapped = true
        object.Font = Enum.Font.GothamMedium
        object.TextSize = fontSize
        object.TextColor3 = color
        object.Parent = panel
        return object
    end

    return gui, label(7, 26, 15, Color3.fromRGB(234, 242, 249)),
        label(37, 31, 14, Color3.fromRGB(181, 214, 230)),
        label(72, 39, 12, Color3.fromRGB(169, 191, 204))
end

function Controller.new(tools)
    return setmetatable({
        Tools = tools,
        Active = false,
        Stage = "Housing",
        KindIndex = 1,
        Housing = nil,
        Source = nil,
        Members = {},
        OffsetUnits = 0,
        PreviewModel = nil,
        LastMessage = nil,
        MessageUntil = 0,
        Connections = {},
        Busy = false,
    }, Controller)
end

function Controller:Kind()
    return TYPES[self.KindIndex]
end

function Controller:Message(message)
    self.LastMessage = message
    self.MessageUntil = os.clock() + 2.5
    self:RefreshHUD()
end

function Controller:RefreshHUD()
    if not self.Gui then return end
    self.Gui.Enabled = self.Active
    if not self.Active then return end

    self.Header.Text = "OPENWORKS / ASSEMBLE / " .. string.upper(self:Kind())
    if self.Stage == "Housing" then
        self.Detail.Text = "Choose the housing or opening"
        self.Help.Text = "Click an opening  •  R change relation  •  Esc reset"
    elseif self.Stage == "Source" then
        self.Detail.Text = "Choose the shaft or source component"
        self.Help.Text = "Click a source  •  R change relation  •  Esc reset"
    else
        self.Detail.Text = "Insertion offset: " .. tostring(self.OffsetUnits) .. " U"
        self.Help.Text = "Wheel adjusts depth  •  click finalize  •  R change type  •  Esc cancel"
    end

    if self.LastMessage and os.clock() < self.MessageUntil then
        self.Detail.Text = self.LastMessage
    end
end

function Controller:ClearHighlights()
    if self.HousingHighlight then self.HousingHighlight:Destroy() end
    if self.SourceHighlight then self.SourceHighlight:Destroy() end
    self.HousingHighlight = nil
    self.SourceHighlight = nil
end

local function highlight(model, color)
    local h = Instance.new("Highlight")
    h.Adornee = model
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = 0.8
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = model
    return h
end

function Controller:ClearPreview()
    if self.PreviewModel then self.PreviewModel:Destroy() end
    self.PreviewModel = nil
    player:SetAttribute("OPENWORKS_Inserting", false)
end

function Controller:Reset()
    self:ClearPreview()
    self:ClearHighlights()
    self.Stage = "Housing"
    self.Housing = nil
    self.Source = nil
    self.Members = {}
    self.OffsetUnits = 0
    self:RefreshHUD()
end

function Controller:Pick(exclude)
    local folder = constructedFolder()
    local camera = workspace.CurrentCamera
    if not folder or not camera then return nil end

    local candidates = {}
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId") == player.UserId
            and not (exclude and exclude[model]) then
            table.insert(candidates, model)
        end
    end
    if #candidates == 0 then return nil end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = candidates
    params.IgnoreWater = true
    local result = workspace:Raycast(camera.CFrame.Position,
        camera.CFrame.LookVector * Grid.MaxDistance, params)
    if not result then return nil end

    local current = result.Instance
    while current and current.Parent ~= folder do current = current.Parent end
    if current and current:IsA("Model") then return current end
    return nil
end

function Controller:SourceMembers(source)
    local componentId = source:GetAttribute("ComponentId")
    if not componentId then return { source } end
    local folder = constructedFolder()
    local members = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("ComponentId") == componentId
                and model:GetAttribute("OwnerUserId") == player.UserId then
                table.insert(members, model)
            end
        end
    end
    return members
end

function Controller:MakePreview()
    self:ClearPreview()
    if not self.Source or not self.Housing then return end
    if self:Kind() == "Fixed" then
        self:RefreshHUD()
        return
    end

    local ghost = Instance.new("Model")
    ghost.Name = "OPENWORKS_MechanicalPreview"
    for _, member in ipairs(self.Members) do
        local model = member:Clone()
        model.Parent = ghost
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.CastShadow = false
                part.LocalTransparencyModifier = 0
                part.Transparency = 0.45
                part.Color = Color3.fromRGB(91, 201, 187)
            end
        end
    end
    ghost.WorldPivot = self.Source:GetPivot()
    ghost.Parent = workspace
    self.PreviewModel = ghost
    self.GhostStart = ghost:GetPivot()
    player:SetAttribute("OPENWORKS_Inserting", true)
    self:UpdatePreview()
end

function Controller:UpdatePreview()
    if not self.Active or self.Stage ~= "Preview" or not self.Housing or not self.Source then
        return
    end
    if self:Kind() == "Fixed" then return end

    local plan, reason = Alignment.Plan(
        self.Members, self.Source, self.Housing, self.OffsetUnits
    )
    if not plan then
        self:Message(tostring(reason))
        return
    end
    if self.PreviewModel then
        self.PreviewModel:PivotTo(plan.delta * self.GhostStart)
    end
    self:RefreshHUD()
end

function Controller:Request(payload)
    if self.Busy then return false end
    self.Busy = true
    local ok, result = pcall(function()
        return self.Remote:InvokeServer(payload)
    end)
    self.Busy = false
    if not ok or type(result) ~= "table" then
        self:Message("Assembly request failed; check Studio Output")
        return false
    end
    self:Message(result.message or "")
    return result.ok == true
end

function Controller:Activate()
    if not self.Active or self.Busy then return end
    if self.Stage == "Housing" then
        local candidate = self:Pick()
        if not candidate then
            self:Message("Aim at a constructed housing/opening")
            return
        end
        if self:Kind() ~= "Fixed" and not Alignment.TargetAxis(candidate) then
            self:Message("Select CircularTube, SquareTube, or DrilledBlock")
            return
        end
        self.Housing = candidate
        self.HousingHighlight = highlight(candidate, Color3.fromRGB(94, 207, 157))
        self.Stage = "Source"
    elseif self.Stage == "Source" then
        local housing = self.Housing
        if not housing or not housing.Parent then self:Reset() return end
        local candidate = self:Pick({ [housing] = true })
        if not candidate or candidate == housing then
            self:Message("Aim at a different shaft or component")
            return
        end
        if self:Kind() ~= "Fixed" and not Alignment.IsShaft(candidate) then
            self:Message("Choose a full Cylinder shaft for Bearing/Slider")
            return
        end
        local members = self:SourceMembers(candidate)
        for _, member in ipairs(members) do
            if member == housing then
                self:Message("Housing and source must be separate bodies")
                return
            end
        end
        self.Source = candidate
        self.Members = members
        self.SourceHighlight = highlight(candidate, Color3.fromRGB(236, 174, 102))
        self.OffsetUnits = 0
        self.Stage = "Preview"
        self:MakePreview()
    else
        if not self.Housing or not self.Source then self:Reset() return end
        if self:Request({
            action = "CreateRelation",
            kind = self:Kind(),
            targetId = self.Housing:GetAttribute("InstanceId"),
            sourceId = self.Source:GetAttribute("InstanceId"),
            offsetUnits = self.OffsetUnits,
        }) then
            self:Reset()
        end
    end
    self:RefreshHUD()
end

function Controller:CycleType()
    self.KindIndex = self.KindIndex % #TYPES + 1
    if self.Stage == "Preview" then
        if self:Kind() ~= "Fixed" and (not Alignment.IsShaft(self.Source)
            or not Alignment.TargetAxis(self.Housing)) then
            self.Stage = "Source"
            self.Source = nil
            self.Members = {}
            if self.SourceHighlight then self.SourceHighlight:Destroy() end
            self.SourceHighlight = nil
            self:ClearPreview()
        else
            self:MakePreview()
        end
    elseif self.Stage == "Source" and self:Kind() ~= "Fixed"
        and not Alignment.TargetAxis(self.Housing) then
        self:Reset()
    end
    self:RefreshHUD()
end

function Controller:OnModeChanged(mode)
    if mode ~= "Assemble" and self.Active then self:Reset() end
    self.Active = mode == "Assemble"
    if self.Active then self:Reset() end
    self:RefreshHUD()
end

function Controller:Start()
    self.Gui, self.Header, self.Detail, self.Help = createGui()
    self.Remote = ReplicatedStorage:WaitForChild(Config.RequestName)
    table.insert(self.Connections, self.Tools.Changed.Event:Connect(function(mode)
        self:OnModeChanged(mode)
    end))
    table.insert(self.Connections, self.Tools.Activated.Event:Connect(function(mode)
        if mode == "Assemble" then self:Activate() end
    end))
    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not self.Active or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.Escape then
            self:Reset()
        elseif processed then
            return
        elseif input.KeyCode == Enum.KeyCode.R then
            self:CycleType()
        elseif input.KeyCode == Enum.KeyCode.Z and
            (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
            self:Request({ action = "Undo" })
            self:Reset()
        elseif input.KeyCode == Enum.KeyCode.Y and
            (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
            self:Request({ action = "Redo" })
            self:Reset()
        elseif self.Stage == "Preview" and
            (input.KeyCode == Enum.KeyCode.LeftBracket or
            input.KeyCode == Enum.KeyCode.RightBracket) then
            self.OffsetUnits = math.clamp(
                self.OffsetUnits + (if input.KeyCode == Enum.KeyCode.RightBracket then 1 else -1),
                -Alignment.MaxOffsetUnits, Alignment.MaxOffsetUnits
            )
            self:UpdatePreview()
        end
    end))
    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if not self.Active or self.Stage ~= "Preview" or self:Kind() == "Fixed" then return end
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        self.OffsetUnits = math.clamp(
            self.OffsetUnits + (if input.Position.Z > 0 then 1 else -1),
            -Alignment.MaxOffsetUnits, Alignment.MaxOffsetUnits
        )
        self:UpdatePreview()
    end))
    -- Use the state of the already-equipped native tool on client startup.
    self:OnModeChanged(self.Tools.ActiveId)
end

function Controller:Destroy()
    self:Reset()
    for _, conn in ipairs(self.Connections) do conn:Disconnect() end
    table.clear(self.Connections)
    if self.Gui then self.Gui:Destroy() end
end

return Controller
