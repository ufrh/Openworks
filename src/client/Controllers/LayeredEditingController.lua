--!strict
-- Phase 04: first-person depth picking, non-destructive X-ray/isolate,
-- and guided coaxial insertion previews. No mechanical constraints here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Config = require(construction:WaitForChild("BuildConfig"))
local Grid = require(construction:WaitForChild("GridMath"))
local AlignmentMath = require(construction:WaitForChild("AlignmentMath"))

local Layered = {}
Layered.__index = Layered
local MAX_DEPTH = 24

local function owned(model)
    return model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId
end

local function createdModel(hit, container)
    local node = hit
    while node and node.Parent ~= container do node = node.Parent end
    return if node and node:IsA("Model") then node else nil
end

function Layered.new(controller)
    return setmetatable({
        Parent = controller,
        XRay = false,
        Isolated = false,
        Alignment = nil,
        DepthIndex = 0,
        TargetDepthIndex = 0,
        Connections = {},
        TargetHighlight = nil,
        HoveredCandidate = nil,
        LastHoverRefresh = 0,
    }, Layered)
end

function Layered:Built()
    return workspace:FindFirstChild(Config.FolderName)
end

function Layered:SelectedSet()
    local result = {}
    for _, model in ipairs(self.Parent.SelectedParts) do result[model] = true end
    return result
end

function Layered:ClearVisuals()
    local folder = self:Built()
    if not folder then return end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then part.LocalTransparencyModifier = 0 end
            end
        end
    end
end

function Layered:RefreshVisuals()
    local folder = self:Built()
    if not folder then return end

    if self.Parent.Mode ~= "Edit" and self.Parent.Mode ~= "Inspect" then
        self:ClearVisuals()
        return
    end

    local selected = self:SelectedSet()
    local editingId = self.Parent.EditingComponentId
    local align = self.Alignment

    for _, model in ipairs(folder:GetChildren()) do
        if not model:IsA("Model") then continue end

        local amount = 0
        local isSelected = selected[model] == true
        if self.Isolated then
            amount = if isSelected then 0 else 1
        elseif self.XRay then
            amount = if isSelected then 0 else 0.65
        elseif editingId and model:GetAttribute("ComponentId") == editingId then
            amount = if isSelected then 0 else 0.38
        end

        -- Hide the moving source while ghost positioning is in progress.
        if align and align.Stage == "Preview" then
            for _, member in ipairs(align.Members) do
                if model == member then amount = 1 break end
            end
        end

        local pending = self.Parent.Pending
        if pending == "Move" and model == self.Parent.Selected then
            amount = 1
        elseif pending == "ComponentMove" and isSelected then
            amount = 1
        elseif self.Parent.ScaleMode and model == self.Parent.Selected then
            amount = 1
        end

        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = amount
            end
        end
    end
end

function Layered:DepthModels(exclude)
    local folder = self:Built()
    local camera = workspace.CurrentCamera
    if not folder or not camera then return {} end

    local origin = camera.CFrame.Position
    local direction = camera.CFrame.LookVector * Grid.MaxDistance
    local candidates = {}

    for _, model in ipairs(folder:GetChildren()) do
        if owned(model) and not (exclude and exclude[model]) then
            local visible = not self.Isolated or self:SelectedSet()[model]
            if visible then table.insert(candidates, model) end
        end
    end

    local layers = {}
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.IgnoreWater = true

    for _ = 1, MAX_DEPTH do
        if #candidates == 0 then break end
        params.FilterDescendantsInstances = candidates
        local result = workspace:Raycast(origin, direction, params)
        if not result then break end

        local model = createdModel(result.Instance, folder)
        if not model then break end
        table.insert(layers, model)

        local index = table.find(candidates, model)
        if not index then break end
        table.remove(candidates, index)
    end
    return layers
end

function Layered:Select(model)
    local parent = self.Parent
    if not model then parent:SetSelection(nil) return end

    local componentId = model:GetAttribute("ComponentId")
    if parent.EditingComponentId then
        if parent.EditingComponentId == componentId then
            parent:SetSelection(model)
        else
            parent:Message("Exit component editing to select other parts")
        end
    elseif componentId then
        parent:SetComponentSelection(componentId)
    elseif game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftShift)
        or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.RightShift) then
        parent:ToggleMultiSelection(model)
    else
        parent:SetSelection(model)
    end
    self:RefreshVisuals()
end

function Layered:PickCurrent()
    local layers = self:DepthModels(nil)
    self.DepthIndex = 0
    self:Select(layers[1])
end

function Layered:CycleDepth(backward)
    local align = self.Alignment
    if align and align.Stage == "PickTarget" then
        local excluded = {}
        for _, member in ipairs(align.Members) do excluded[member] = true end
        local layers = self:DepthModels(excluded)
        if #layers == 0 then
            self.Parent:Message("No construction under the crosshair")
            return
        end
        self.TargetDepthIndex = (self.TargetDepthIndex + (if backward then -1 else 1)) % #layers
        local current = layers[self.TargetDepthIndex + 1]
        self.LastHoverRefresh = 0
        self:RefreshTargetCue()
        self.Parent:Message("Opening candidate " .. tostring(self.TargetDepthIndex + 1)
            .. "/" .. tostring(#layers) .. ": " .. current.Name)
        return
    end

    local layers = self:DepthModels(nil)
    if #layers == 0 then
        self.Parent:Message("No construction under the crosshair")
        return
    end

    -- First Tab goes behind the currently selected model, if any.
    local selected = self.Parent.Selected
        or self.Parent.GroupAnchor
    local at = if selected then table.find(layers, selected) else nil
    local index = if at then at - 1 else self.DepthIndex
    self.DepthIndex = (index + (if backward then -1 else 1)) % #layers
    local target = layers[self.DepthIndex + 1]
    self:Select(target)
    self.Parent:Message("Depth " .. tostring(self.DepthIndex + 1) .. "/" .. tostring(#layers))
end

function Layered:RefreshTargetCue()
    local align = self.Alignment
    if not align or align.Stage ~= "PickTarget" then return end
    local now = os.clock()
    if now - self.LastHoverRefresh < 0.12 then return end
    self.LastHoverRefresh = now

    local excluded = {}
    for _, member in ipairs(align.Members) do excluded[member] = true end
    local layers = self:DepthModels(excluded)
    local target = layers[(self.TargetDepthIndex % math.max(1, #layers)) + 1]
    if target == self.HoveredCandidate then return end

    self.HoveredCandidate = target
    if self.TargetHighlight then self.TargetHighlight:Destroy() end
    self.TargetHighlight = nil
    if target then
        local highlight = Instance.new("Highlight")
        highlight.Adornee = target
        highlight.FillTransparency = 0.83
        highlight.OutlineTransparency = 0.05
        highlight.FillColor = if AlignmentMath.TargetAxis(target)
            then Color3.fromRGB(88, 209, 158)
            else Color3.fromRGB(228, 170, 98)
        highlight.OutlineColor = highlight.FillColor
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = self.Parent.Gui
        self.TargetHighlight = highlight
    end
end

function Layered:ToggleXRay()
    self.XRay = not self.XRay
    if self.XRay then self.Isolated = false end
    self:RefreshVisuals()
    self.Parent:Message(if self.XRay then "X-ray on" else "X-ray off")
end

function Layered:ToggleIsolate()
    if #self.Parent.SelectedParts == 0 then
        self.Parent:Message("Select something to isolate")
        return
    end
    self.Isolated = not self.Isolated
    if self.Isolated then self.XRay = false end
    self:RefreshVisuals()
    self.Parent:Message(if self.Isolated then "Selection isolated" else "All constructions visible")
end

function Layered:CreatePreview()
    local align = self.Alignment
    if not align then return end

    local ghost = Instance.new("Model")
    ghost.Name = "OPENWORKS_AxialGhost"
    for _, source in ipairs(align.Members) do
        local cloned = source:Clone()
        cloned.Parent = ghost
    end

    for _, item in ipairs(ghost:GetDescendants()) do
        if item:IsA("BasePart") then
            item.CanCollide = false
            item.CanTouch = false
            item.CanQuery = false
            item.Anchored = true
            item.Transparency = 0.48
            item.LocalTransparencyModifier = 0
            item.Color = Color3.fromRGB(86, 188, 210)
            item.CastShadow = false
        end
    end

    ghost.WorldPivot = align.Shaft:GetPivot()
    ghost.Parent = workspace
    align.Preview = ghost
    align.StartGhostPivot = ghost:GetPivot()
    self:UpdateAlignPreview()
end

function Layered:UpdateAlignPreview()
    local align = self.Alignment
    if not align or align.Stage ~= "Preview" then return end

    if not align.Target.Parent or not align.Shaft.Parent then
        self:CancelAlignment()
        self.Parent:Message("Alignment source or target no longer exists")
        return
    end

    local plan, reason = AlignmentMath.Plan(
        align.Members, align.Shaft, align.Target, align.OffsetUnits
    )
    if not plan then
        self.Parent:Message(tostring(reason))
        return
    end

    align.Plan = plan
    if align.Preview then
        align.Preview:PivotTo(plan.delta * align.StartGhostPivot)
    end
    self:RefreshVisuals()
    self.Parent:RefreshHUD()
end

function Layered:StartAlignment()
    local parent = self.Parent
    if parent.Mode ~= "Edit" or parent.Pending or parent.ScaleMode then return end

    local members = if parent.SelectedComponentId then
        table.clone(parent.SelectedParts)
        elseif parent.Selected then { parent.Selected } else {}
    local shaft = AlignmentMath.ShaftIn(members)

    if not shaft then
        parent:Message("Select a Cylinder shaft or a component containing one")
        return
    end

    self:CancelAlignment()
    self.Isolated = false
    self.Alignment = {
        Stage = "PickTarget",
        Shaft = shaft,
        Members = members,
        ComponentId = parent.SelectedComponentId,
        OffsetUnits = 0,
    }
    self.TargetDepthIndex = 0
    self.HoveredCandidate = nil
    self.LastHoverRefresh = 0
    self:RefreshVisuals()
    parent:Message("Aim at a tube or drilled opening, then click")
end

function Layered:ChooseTarget()
    local align = self.Alignment
    if not align or align.Stage ~= "PickTarget" then return end

    local excluded = {}
    for _, member in ipairs(align.Members) do excluded[member] = true end
    local layers = self:DepthModels(excluded)
    local target = layers[(self.TargetDepthIndex % math.max(1, #layers)) + 1]

    if not target then
        self.Parent:Message("Aim at a constructed opening")
        return
    end
    if not AlignmentMath.TargetAxis(target) then
        self.Parent:Message("Choose a CircularTube, SquareTube, or DrilledBlock")
        return
    end

    align.Target = target
    align.Stage = "Preview"
    if self.TargetHighlight then
        self.TargetHighlight:Destroy()
        self.TargetHighlight = nil
    end
    self.HoveredCandidate = nil
    align.OffsetUnits = 0
    player:SetAttribute("OPENWORKS_Inserting", true)
    self:CreatePreview()
    self.Parent:Message("Scroll to adjust insertion depth, click to confirm")
end

function Layered:AdjustOffset(wheel)
    local align = self.Alignment
    if not align or align.Stage ~= "Preview" then return false end
    local amount = if wheel > 0 then 1 elseif wheel < 0 then -1 else 0
    if amount == 0 then return true end

    align.OffsetUnits = math.clamp(
        align.OffsetUnits + amount,
        -AlignmentMath.MaxOffsetUnits,
        AlignmentMath.MaxOffsetUnits
    )
    self:UpdateAlignPreview()
    self.Parent:Message("Insertion offset: " .. tostring(align.OffsetUnits) .. " U")
    return true
end

function Layered:ConfirmAlignment()
    local align = self.Alignment
    if not align or align.Stage ~= "Preview" then return end

    local ok = self.Parent:Request({
        action = "Align",
        sourceId = align.Shaft:GetAttribute("InstanceId"),
        componentId = align.ComponentId,
        targetId = align.Target:GetAttribute("InstanceId"),
        offsetUnits = align.OffsetUnits,
    })
    if ok then
        self:CancelAlignment()
        self.Parent:RefreshHUD()
    end
end

function Layered:Click()
    local align = self.Alignment
    if align then
        if align.Stage == "PickTarget" then self:ChooseTarget()
        elseif align.Stage == "Preview" then self:ConfirmAlignment() end
        return true
    end

    if self.Parent.Mode == "Inspect" then
        self:PickCurrent()
        return true
    end
    return false
end

function Layered:CancelAlignment()
    local align = self.Alignment
    if align and align.Preview then align.Preview:Destroy() end
    self.Alignment = nil
    if self.TargetHighlight then self.TargetHighlight:Destroy() end
    self.TargetHighlight = nil
    self.HoveredCandidate = nil
    self.TargetDepthIndex = 0
    player:SetAttribute("OPENWORKS_Inserting", false)
    self:RefreshVisuals()
end

function Layered:OnModeChanged(mode)
    self:CancelAlignment()
    if mode ~= "Edit" and mode ~= "Inspect" then
        self.XRay = false
        self.Isolated = false
    end
    self:RefreshVisuals()
end

function Layered:OnInput(input, processed)
    local parent = self.Parent
    if parent.Mode ~= "Edit" and parent.Mode ~= "Inspect" then return false end
    local key = input.KeyCode
    if key == Enum.KeyCode.Escape and self.Alignment then
        self:CancelAlignment()
        parent:RefreshHUD()
        return true
    end
    if processed then return false end

    if self.Alignment and self.Alignment.Stage == "Preview" then
        if key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.Minus then
            self:AdjustOffset(-1)
        elseif key == Enum.KeyCode.RightBracket or key == Enum.KeyCode.Equals then
            self:AdjustOffset(1)
        end
        return true
    end

    if key == Enum.KeyCode.Tab then
        local reverse = game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftShift)
            or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.RightShift)
        self:CycleDepth(reverse)
        return true
    elseif key == Enum.KeyCode.X then
        self:ToggleXRay()
        return true
    elseif key == Enum.KeyCode.I then
        self:ToggleIsolate()
        return true
    elseif key == Enum.KeyCode.A and parent.Mode == "Edit" then
        if self.Alignment then self:CancelAlignment() else self:StartAlignment() end
        return true
    end
    -- Selecting an opening is an exclusive mode; block Edit keyboard
    -- transforms until alignment is finished or cancelled.
    return self.Alignment ~= nil
end

function Layered:Start()
    table.insert(self.Connections, RunService.RenderStepped:Connect(function()
        self:RefreshTargetCue()
    end))
end

function Layered:Destroy()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    self:CancelAlignment()
    self:ClearVisuals()
end

return Layered
