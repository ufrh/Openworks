--!strict
-- Phase 02: first-person Build/Edit interactions, primitive catalog and ghost preview.
-- No runtime CSG; all authoritative edits are checked by ConstructionService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Registry = require(construction:WaitForChild("PrimitiveRegistry"))
local Grid = require(construction:WaitForChild("GridMath"))
local Config = require(construction:WaitForChild("BuildConfig"))
local ResizeGizmo = require(script.Parent:WaitForChild("ResizeGizmo"))

local BLUE = Color3.fromRGB(96, 174, 207)
local DARK = Color3.fromRGB(22, 29, 38)
local PANEL = Color3.fromRGB(32, 42, 55)
local TEXT = Color3.fromRGB(230, 239, 246)
local MUTED = Color3.fromRGB(167, 186, 199)

local Controller = {}
Controller.__index = Controller

local function create(className, fields, parent)
    local instance = Instance.new(className)
    for key, value in pairs(fields or {}) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function rounded(gui, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 7) }, gui)
    return gui
end

local function label(parent, text, size, position, fontSize, color)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Size = size,
        Position = position,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = color or TEXT,
        TextSize = fontSize or 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, parent)
end

local function button(parent, text, size, position)
    local b = rounded(create("TextButton", {
        Size = size,
        Position = position or UDim2.fromOffset(0, 0),
        BackgroundColor3 = PANEL,
        TextColor3 = TEXT,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        Text = text,
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }, parent))
    return b
end

local function stepsCopy(s)
    return { x = s.x, y = s.y, z = s.z }
end

local function attributesSteps(model)
    return {
        x = model:GetAttribute("RotX") or 0,
        y = model:GetAttribute("RotY") or 0,
        z = model:GetAttribute("RotZ") or 0,
    }
end

function Controller.new(tools)
    return setmetatable({
        Tools = tools,
        Mode = nil,
        CurrentId = nil,
        CurrentSize = nil,
        Steps = { x = 0, y = 0, z = 0 },
        Selected = nil,
        SelectedParts = {},
        SelectedComponentId = nil,
        EditingComponentId = nil,
        SelectionHighlights = {},
        GroupAnchor = nil,
        Pending = nil, -- "Move", "Copy", or nil
        Preview = nil,
        PreviewCF = nil,
        CatalogOpen = false,
        ScaleMode = false,
        ScaleGhost = nil,
        ScaleCF = nil,
        ScaleSize = nil,
        ScaleHandles = nil,
        Busy = false,
        Connections = {},
        Started = false,
        MessageUntil = 0,
        Remote = ReplicatedStorage:WaitForChild(Config.RequestName),
    }, Controller)
end

function Controller:MakeUI()
    local gui = create("ScreenGui", {
        Name = "OPENWORKS_ConstructionHUD",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 40,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player:WaitForChild("PlayerGui"))

    local status = rounded(create("Frame", {
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.07,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 20),
        Size = UDim2.fromOffset(370, 108),
    }, gui), 9)
    local title = label(status, "OPENWORKS  /  BUILD", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 8), 15)
    local details = label(status, "", UDim2.new(1, -24, 0, 28), UDim2.fromOffset(12, 38), 13, MUTED)
    local help = label(status, "", UDim2.new(1, -24, 0, 33), UDim2.fromOffset(12, 71), 12, MUTED)

    local crosshair = label(gui, "+", UDim2.fromOffset(20, 20),
        UDim2.new(0.5, -10, 0.5, -10), 21, Color3.fromRGB(229, 238, 245))
    crosshair.TextXAlignment = Enum.TextXAlignment.Center
    crosshair.TextYAlignment = Enum.TextYAlignment.Center

    local catalog = rounded(create("Frame", {
        Name = "PrimitiveCatalog",
        ZIndex = 10,
        Size = UDim2.fromOffset(330, 470),
        Position = UDim2.fromOffset(18, 70),
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.025,
        BorderSizePixel = 0,
        Visible = false,
    }, gui), 10)

    label(catalog, "PRIMITIVES", UDim2.fromOffset(220, 30), UDim2.fromOffset(13, 9), 17)
    local close = button(catalog, "×  CLOSE", UDim2.fromOffset(90, 29), UDim2.fromOffset(226, 10))
    close.Activated:Connect(function() self:ShowCatalog(false) end)

    label(catalog, "Select a Studio-precompiled primitive", UDim2.fromOffset(300, 24),
        UDim2.fromOffset(13, 40), 12, MUTED)

    local list = create("ScrollingFrame", {
        Name = "Items",
        Position = UDim2.fromOffset(12, 71),
        Size = UDim2.new(1, -24, 1, -84),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, catalog)
    create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

    -- The primitive catalog alone unlocks the mouse. Resizing always uses
    -- the center crosshair with a locked first-person pointer.
    local unlock = create("TextButton", {
        Name = "MouseReleaseSurface",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        Active = true,
        Modal = true,
        ZIndex = 1,
        Visible = false,
    }, gui)

    self.Gui = gui
    self.TitleLabel = title
    self.DetailLabel = details
    self.HelpLabel = help
    self.Catalog = catalog
    self.List = list
    self.Unlock = unlock
    self.Crosshair = crosshair
    self.ScaleHandles = ResizeGizmo.new(gui, function(cf, size)
        self:UpdateScalePreview(cf, size)
    end, function(cf, size, oldCF, oldSize)
        return self:CommitScale(cf, size, oldCF, oldSize)
    end)
end

function Controller:RefreshCatalog()
    for _, child in ipairs(self.List:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local entries = Registry.List()
    if #entries == 0 then
        local missing = label(self.List, "No primitives found. Run the Studio generator and save the place.",
            UDim2.new(1, -8, 0, 75), UDim2.fromOffset(0, 0), 13, MUTED)
        missing.LayoutOrder = 1
        return
    end

    for index, entry in ipairs(entries) do
        local b = button(self.List, entry.Id, UDim2.new(1, -7, 0, 32))
        b.LayoutOrder = index
        b.BackgroundColor3 = if entry.Id == self.CurrentId then Color3.fromRGB(44, 89, 99) else PANEL
        b.Activated:Connect(function()
            self:SelectPrimitive(entry.Id)
            self:ShowCatalog(false)
        end)
    end
end

function Controller:RefreshPointer()
    -- Only the library needs the free cursor. Scale mode stays LockCenter,
    -- and the ResizeGizmo uses relative MouseMovement + crosshair aiming.
    local unlocked = self.CatalogOpen
    self.Unlock.Visible = unlocked
    self.Crosshair.Visible = not unlocked
    UserInputService.MouseIconEnabled = unlocked

    if unlocked then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end
end

function Controller:ShowCatalog(visible)
    if visible and self.ScaleMode then self:EndScale() end
    local wasOpen = self.CatalogOpen
    self.CatalogOpen = visible and self.Mode == "Build"
    if wasOpen and not self.CatalogOpen then
        self.IgnoreClickUntil = os.clock() + 0.2
    end
    self.Catalog.Visible = self.CatalogOpen
    self:RefreshPointer()

    if self.CatalogOpen then
        self:RefreshCatalog()
    end
    self:RefreshHUD()
end

function Controller:Message(text)
    self.StatusMessage = text
    self.MessageUntil = os.clock() + 3.5
    self:RefreshHUD()
end

function Controller:RefreshHUD()
    if not self.Gui then return end
    self.Gui.Enabled = self.Mode == "Build" or self.Mode == "Edit"
    if not self.Gui.Enabled then return end

    local mode = self.Mode
    local current = self.CurrentId or "Choose a primitive"
    local size = self.CurrentSize

    self.TitleLabel.Text = "OPENWORKS  /  " .. string.upper(mode)
    if self.ScaleMode then
        self.DetailLabel.Text = current .. (if self.ScaleSize then
            "  •  " .. string.format("%.2g × %.2g × %.2g U",
                self.ScaleSize.X / Grid.Unit, self.ScaleSize.Y / Grid.Unit, self.ScaleSize.Z / Grid.Unit)
            else "")
        self.HelpLabel.Text = "Aim at X/Y/Z grip • hold click + drag • V/Esc finish"
    elseif mode == "Build" then
        self.DetailLabel.Text = current .. (if size then "  •  " .. string.format("%.2g × %.2g × %.2g U",
            size.X / Grid.Unit, size.Y / Grid.Unit, size.Z / Grid.Unit) else "")
        self.HelpLabel.Text = if self.CatalogOpen then "Choose a primitive • B/Esc close"
            else "B catalog  •  R/T/Y rotate  •  V drag resize"
    elseif self.Pending == "Move" then
        self.DetailLabel.Text = "MOVE  /  " .. (self.Selected and self.Selected.Name or "")
        self.HelpLabel.Text = "Click to place  •  R/T/Y rotate  •  Esc cancel"
    elseif self.Pending == "Copy" then
        self.DetailLabel.Text = "DUPLICATE  /  " .. current
        self.HelpLabel.Text = "Click to place copy  •  R/T/Y rotate  •  Esc cancel"
    elseif self.SelectedComponentId then
        self.DetailLabel.Text = (if self.Pending == "ComponentMove" then "MOVING COMPONENT"
            elseif self.Pending == "ComponentCopy" then "COPYING COMPONENT"
            else "Rigid component") .. "  /  " .. tostring(#self.SelectedParts) .. " primitives"
        self.HelpLabel.Text = if self.Pending then
            "Aim and click to confirm  •  R/T/Y rotate  •  Esc cancel"
            else "G move  •  F duplicate  •  E edit inside  •  U ungroup  •  Del"
    elseif #self.SelectedParts > 1 then
        self.DetailLabel.Text = tostring(#self.SelectedParts) .. " primitives selected"
        self.HelpLabel.Text = "C combine  •  Shift+click to change selection"
    elseif self.EditingComponentId then
        self.DetailLabel.Text = (self.Selected and self.Selected.Name or "Editing component")
            .. "  /  component interior"
        self.HelpLabel.Text = "Click primitive • V scale • G move • E exit component"
    else
        local target = self.Selected
        self.DetailLabel.Text = if target then target.Name .. "  /  drag scale with V" else "Click a constructed piece"
        self.HelpLabel.Text = "Shift+click multi-select • C combine • V scale • G move"
    end

    if self.StatusMessage and os.clock() < self.MessageUntil then
        self.DetailLabel.Text = self.StatusMessage
    end
end

function Controller:SelectPrimitive(id)
    local entry = Registry.Get(id)
    if not entry then return end

    self.CurrentId = id
    self.CurrentSize = entry.Model.PrimaryPart.Size
    self.Steps = { x = 0, y = 0, z = 0 }
    self.Pending = nil
    self:RebuildPreview()
    self:RefreshHUD()
end

function Controller:ClearPreview()
    if self.Preview then self.Preview:Destroy() end
    self.Preview = nil
    self.PreviewCF = nil
end

function Controller:RebuildPreview()
    self:ClearPreview()

    local source
    if (self.Pending == "ComponentMove" or self.Pending == "ComponentCopy") and self.GroupAnchor then
        local combined = Instance.new("Model")
        combined.Name = "OPENWORKS_ComponentGhost"
        for _, model in ipairs(self.SelectedParts) do
            if model and model.Parent then model:Clone().Parent = combined end
        end
        combined.WorldPivot = self.GroupAnchor:GetPivot()
        source = combined
    elseif self.Pending == "Move" and self.Selected then
        source = self.Selected
    elseif self.Pending == "Copy" and self.Selected then
        source = self.Selected
    elseif self.Mode == "Build" and self.CurrentId then
        local entry = Registry.Get(self.CurrentId)
        source = entry and entry.Model
    end
    if not source then return end

    local ghost = if source.Name == "OPENWORKS_ComponentGhost" then source else source:Clone()
    ghost.Name = "OPENWORKS_Ghost"
    for _, part in ipairs(ghost:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanQuery = false
            part.CanCollide = false
            part.CanTouch = false
            part.CastShadow = false
            part.Transparency = 0.58
            part.LocalTransparencyModifier = 0 -- cloned move previews must remain visible
            part.Color = BLUE
            if self.CurrentSize and part == ghost.PrimaryPart then
                part.Size = self.CurrentSize
            end
        end
    end

    create("Highlight", {
        Adornee = ghost,
        FillColor = Color3.fromRGB(98, 219, 168),
        FillTransparency = 0.72,
        OutlineColor = Color3.fromRGB(181, 249, 213),
        OutlineTransparency = 0.08,
        DepthMode = Enum.HighlightDepthMode.Occluded,
    }, ghost)

    ghost.Parent = workspace
    self.Preview = ghost
end

function Controller:RefreshSelectionHighlights()
    if self.SelectionHighlight then
        self.SelectionHighlight:Destroy()
        self.SelectionHighlight = nil
    end
    for _, highlight in ipairs(self.SelectionHighlights) do highlight:Destroy() end
    table.clear(self.SelectionHighlights)

    for _, model in ipairs(self.SelectedParts) do
        if model and model.Parent then
            local h = create("Highlight", {
                Adornee = model,
                FillColor = BLUE,
                FillTransparency = 0.78,
                OutlineColor = Color3.fromRGB(151, 214, 245),
                OutlineTransparency = 0,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
            }, self.Gui)
            table.insert(self.SelectionHighlights, h)
        end
    end
end

function Controller:SetSelection(model)
    if self.Selected == model and not self.SelectedComponentId and #self.SelectedParts <= 1 then return end
    self:CancelPending()
    self.Selected = model
    self.SelectedComponentId = nil
    self.GroupAnchor = nil
    self.SelectedParts = if model then { model } else {}
    if model and model.PrimaryPart then
        self.CurrentId = model:GetAttribute("TemplateId")
        self.CurrentSize = model.PrimaryPart.Size
        self.Steps = attributesSteps(model)
    end
    self:RefreshSelectionHighlights()
    self:RefreshHUD()
end

function Controller:ComponentMembers(componentId)
    local built = workspace:FindFirstChild(Config.FolderName)
    local members = {}
    if built then
        for _, model in ipairs(built:GetChildren()) do
            if model:IsA("Model")
                and model:GetAttribute("OwnerUserId") == player.UserId
                and model:GetAttribute("ComponentId") == componentId then
                table.insert(members, model)
            end
        end
    end
    return members
end

function Controller:SetComponentSelection(componentId, membersOverride)
    self:CancelPending()
    self.Selected = nil
    self.SelectedComponentId = componentId
    self.SelectedParts = membersOverride or self:ComponentMembers(componentId)
    if #self.SelectedParts == 0 then
        self.SelectedComponentId = nil
    else
        local anchorId = self.SelectedParts[1]:GetAttribute("ComponentAnchorId")
        self.GroupAnchor = nil
        for _, model in ipairs(self.SelectedParts) do
            if model:GetAttribute("InstanceId") == anchorId then self.GroupAnchor = model end
        end
        self.GroupAnchor = self.GroupAnchor or self.SelectedParts[1]
        self.CurrentId = self.GroupAnchor:GetAttribute("TemplateId")
        self.CurrentSize = self.GroupAnchor.PrimaryPart.Size
        self.Steps = attributesSteps(self.GroupAnchor)
    end
    self:RefreshSelectionHighlights()
    self:RefreshHUD()
end

function Controller:ToggleMultiSelection(model)
    if model:GetAttribute("ComponentId") then return end
    self:CancelPending()
    -- Starting multi-selection after selecting a component begins a fresh
    -- selection; grouped primitives cannot be mixed into a new component.
    local members = if self.SelectedComponentId then {} else table.clone(self.SelectedParts)
    local index = table.find(members, model)
    if index then
        table.remove(members, index)
    else
        table.insert(members, model)
    end
    self.SelectedParts = members
    self.SelectedComponentId = nil
    self.GroupAnchor = nil
    self.Selected = if #members == 1 then members[1] else nil
    if self.Selected then
        self.CurrentId = self.Selected:GetAttribute("TemplateId")
        self.CurrentSize = self.Selected.PrimaryPart.Size
        self.Steps = attributesSteps(self.Selected)
    end
    self:RefreshSelectionHighlights()
    self:RefreshHUD()
end

function Controller:CancelPending()
    if self.Pending then
        if self.Selected and self.Selected.PrimaryPart then
            self.Selected.PrimaryPart.LocalTransparencyModifier = 0
        end
        for _, model in ipairs(self.SelectedParts) do
            if model and model.PrimaryPart then
                model.PrimaryPart.LocalTransparencyModifier = 0
            end
        end
        self.Pending = nil
        self:ClearPreview()
    end
end

function Controller:OnModeChanged(mode)
    self:EndScale()
    self:CancelPending()
    self.Mode = mode
    self:ShowCatalog(false)
    self:ClearPreview()
    if mode ~= "Edit" then
        self.EditingComponentId = nil
        self:SetSelection(nil)
    end
    if mode == "Build" then
        if not self.CurrentId or not Registry.Get(self.CurrentId) then
            local entries = Registry.List()
            if #entries > 0 then self:SelectPrimitive(entries[1].Id) end
        else
            self:RebuildPreview()
        end
    end
    self:RefreshHUD()
end

function Controller:CastCenter(excludeSelected)
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local ray = camera:ViewportPointToRay(
        camera.ViewportSize.X / 2,
        camera.ViewportSize.Y / 2
    )

    local ignored = {}
    if player.Character then table.insert(ignored, player.Character) end
    if self.Preview then table.insert(ignored, self.Preview) end
    if excludeSelected then
        if self.Selected then table.insert(ignored, self.Selected) end
        if self.SelectedComponentId then
            for _, model in ipairs(self.SelectedParts) do table.insert(ignored, model) end
        end
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignored
    params.IgnoreWater = true

    local hit = workspace:Raycast(ray.Origin, ray.Direction * Grid.MaxDistance, params)
    if hit then
        return { Position = hit.Position, Normal = hit.Normal, Instance = hit.Instance }
    end

    -- Empty test places can build on the y=0 construction plane.
    if ray.Direction.Y < -0.001 then
        local distance = -ray.Origin.Y / ray.Direction.Y
        if distance > 0 and distance <= Grid.MaxDistance then
            return {
                Position = ray.Origin + ray.Direction * distance,
                Normal = Vector3.yAxis,
                Instance = nil,
            }
        end
    end
    return nil
end

function Controller:UpdatePreview()
    if self.ScaleMode then return end
    if not self.Preview or self.CatalogOpen then
        self.PreviewCF = nil
        if self.Preview then self.Preview.Parent = nil end
        return
    end

    local hit = self:CastCenter(self.Pending == "Move" or self.Pending == "ComponentMove")
    if not hit or not self.CurrentSize then
        self.PreviewCF = nil
        self.Preview.Parent = nil
        return
    end

    local rotation = Grid.Rotation(self.Steps)
    local cf = Grid.FromSurface(hit.Position, hit.Normal, self.CurrentSize, rotation)
    self.PreviewCF = cf

    if not self.Preview.Parent then self.Preview.Parent = workspace end
    self.Preview:PivotTo(cf)
end

function Controller:Request(payload)
    if self.Busy then return false end
    self.Busy = true

    local ok, result = pcall(function()
        return self.Remote:InvokeServer(payload)
    end)
    self.Busy = false

    if not ok or type(result) ~= "table" then
        self:Message("Server request failed; check Output")
        return false
    end

    if not result.ok then
        self:Message(tostring(result.message))
        return false
    end
    self:Message(tostring(result.message ~= "" and result.message or "Updated"))
    return true, result
end

function Controller:Place()
    if not self.PreviewCF or not self.CurrentId or not self.CurrentSize then return end
    local success = self:Request({
        action = "Place",
        templateId = self.CurrentId,
        position = self.PreviewCF.Position,
        steps = stepsCopy(self.Steps),
        size = self.CurrentSize,
    })
    if success and self.Pending == "Copy" then
        self:CancelPending()
        self:RefreshHUD()
    end
end

function Controller:Pick()
    local hit = self:CastCenter(false)
    if not hit or not hit.Instance then
        self:SetSelection(nil)
        return
    end

    local built = workspace:FindFirstChild(Config.FolderName)
    if not built then return end
    local node = hit.Instance
    while node and node.Parent ~= built do node = node.Parent end

    if not node or not node:IsA("Model")
        or node:GetAttribute("OwnerUserId") ~= player.UserId then
        self:SetSelection(nil)
        return
    end

    local cid = node:GetAttribute("ComponentId")
    if self.EditingComponentId then
        if cid == self.EditingComponentId then
            self:SetSelection(node)
        else
            self:SetSelection(nil)
        end
        return
    end

    if cid then
        self:SetComponentSelection(cid)
    elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
        self:ToggleMultiSelection(node)
    else
        self:SetSelection(node)
    end
end

function Controller:CreateComponent()
    if self.Mode ~= "Edit" or self.Pending or #self.SelectedParts < 2
        or self.SelectedComponentId or self.EditingComponentId then return end
    local ids = {}
    for _, part in ipairs(self.SelectedParts) do
        if not part or not part.Parent or part:GetAttribute("ComponentId") then
            self:Message("Select ungrouped primitives")
            return
        end
        table.insert(ids, part:GetAttribute("InstanceId"))
    end

    local ok, response = self:Request({ action = "Group", ids = ids })
    if ok and response and response.componentId then
        self:SetComponentSelection(response.componentId, table.clone(self.SelectedParts))
    end
end

function Controller:UngroupComponent()
    if not self.SelectedComponentId then return end
    local ok = self:Request({
        action = "Ungroup", componentId = self.SelectedComponentId,
    })
    if ok then
        self.EditingComponentId = nil
        self:SetSelection(nil)
    end
end

function Controller:ToggleComponentEdit()
    if self.EditingComponentId then
        local id = self.EditingComponentId
        self.EditingComponentId = nil
        self:SetComponentSelection(id)
    elseif self.SelectedComponentId then
        self.EditingComponentId = self.SelectedComponentId
        self:SetSelection(nil)
    end
end

function Controller:ConfirmMove()
    if not self.Selected or not self.PreviewCF then return end
    local success = self:Request({
        action = "Update",
        instanceId = self.Selected:GetAttribute("InstanceId"),
        position = self.PreviewCF.Position,
        steps = stepsCopy(self.Steps),
        size = self.CurrentSize,
    })
    if success then
        self:CancelPending()
        self:RefreshHUD()
    end
end

function Controller:ConfirmComponentPlacement()
    if not self.SelectedComponentId or not self.GroupAnchor or not self.PreviewCF then return end
    local isCopy = self.Pending == "ComponentCopy"
    local ok = self:Request({
        action = if isCopy then "DuplicateComponent" else "TransformComponent",
        componentId = self.SelectedComponentId,
        anchorId = self.GroupAnchor:GetAttribute("InstanceId"),
        position = self.PreviewCF.Position,
        steps = stepsCopy(self.Steps),
    })

    if ok then
        self:CancelPending()
        if not isCopy then
            -- Replication of new primitive transforms can lag the response.
            self:Message("Component moved")
        else
            self:Message("Component duplicated")
        end
        self:RefreshHUD()
    end
end

function Controller:Activate(mode)
    if self.CatalogOpen or self.ScaleMode or self.Busy
        or os.clock() < (self.IgnoreClickUntil or 0) then return end

    if mode == "Build" then
        self:Place()
    elseif mode == "Edit" then
        if self.Pending == "ComponentMove" or self.Pending == "ComponentCopy" then
            self:ConfirmComponentPlacement()
        elseif self.Pending == "Move" then
            self:ConfirmMove()
        elseif self.Pending == "Copy" then
            self:Place()
        else
            self:Pick()
        end
    end
end

function Controller:StartMove(copy)
    if self.Mode ~= "Edit" or self.Pending then return end
    if self.SelectedComponentId and self.GroupAnchor then
        self.Pending = if copy then "ComponentCopy" else "ComponentMove"
        self.CurrentId = self.GroupAnchor:GetAttribute("TemplateId")
        self.CurrentSize = self.GroupAnchor.PrimaryPart.Size
        self.Steps = attributesSteps(self.GroupAnchor)
        if not copy then
            for _, part in ipairs(self.SelectedParts) do
                if part.PrimaryPart then part.PrimaryPart.LocalTransparencyModifier = 1 end
            end
        end
    elseif self.Selected then
        self.Pending = if copy then "Copy" else "Move"
        self.CurrentId = self.Selected:GetAttribute("TemplateId")
        self.CurrentSize = self.Selected.PrimaryPart.Size
        self.Steps = attributesSteps(self.Selected)
        if not copy then
            self.Selected.PrimaryPart.LocalTransparencyModifier = 1
        end
    else
        return
    end
    self:RebuildPreview()
    self:RefreshHUD()
end

function Controller:ModifySelected(position, steps, size)
    if not self.Selected or not self.Selected.Parent then return end
    local ok = self:Request({
        action = "Update",
        instanceId = self.Selected:GetAttribute("InstanceId"),
        position = position,
        steps = stepsCopy(steps),
        size = size,
    })
    if ok then
        -- The response can arrive before property replication.
        -- Keep the acknowledged values rather than reading stale part state.
        self.CurrentSize = size
        self.Steps = stepsCopy(steps)
    else
        self.CurrentSize = self.Selected.PrimaryPart.Size
        self.Steps = attributesSteps(self.Selected)
    end
    self:RefreshHUD()
end

function Controller:Rotate(axis)
    local oldSteps = stepsCopy(self.Steps)
    self.Steps[axis] = (self.Steps[axis] + 1) % 4

    if self.Mode == "Edit" and self.SelectedComponentId and self.GroupAnchor and not self.Pending then
        local rotation = Grid.Rotation(self.Steps)
        local position = Grid.SnapCenter(self.GroupAnchor:GetPivot().Position,
            self.GroupAnchor.PrimaryPart.Size, rotation)
        local ok = self:Request({
            action = "TransformComponent",
            componentId = self.SelectedComponentId,
            anchorId = self.GroupAnchor:GetAttribute("InstanceId"),
            position = position,
            steps = stepsCopy(self.Steps),
        })
        if not ok then self.Steps = oldSteps end
    elseif self.Mode == "Edit" and self.Selected and not self.Pending then
        local rotation = Grid.Rotation(self.Steps)
        local position = Grid.SnapCenter(self.Selected:GetPivot().Position, self.CurrentSize, rotation)
        self:ModifySelected(position, self.Steps, self.CurrentSize)
    end
    self:RefreshHUD()
end

-- Face drag scaling stays entirely within the native first-person
-- locked mouse. V shows the grips; aim the crosshair at one, then drag.
function Controller:BeginScale()
    if self.ScaleMode or self.CatalogOpen or self.Pending then return end
    local model = if self.Mode == "Edit" then self.Selected else self.Preview
    if not model or not model.PrimaryPart then
        self:Message("Aim at a surface or select a piece first")
        return
    end

    local id = if self.Mode == "Edit" then model:GetAttribute("TemplateId") else self.CurrentId
    local entry = id and Registry.Get(id)
    if not entry or entry.ResizeMode == "None" then
        self:Message("This module has fixed dimensions")
        return
    end

    local cf = if self.Mode == "Edit" then model:GetPivot() else self.PreviewCF
    if not cf then
        self:Message("Aim at a surface before resizing")
        return
    end

    self.ScaleMode = true
    self.ScaleCF = cf
    self.ScaleSize = self.CurrentSize

    if self.Mode == "Edit" then
        local ghost = model:Clone()
        ghost.Name = "OPENWORKS_ResizePreview"
        for _, part in ipairs(ghost:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.LocalTransparencyModifier = 0
                part.Transparency = 0.45
                part.Color = BLUE
            end
        end
        ghost.Parent = workspace
        self.ScaleGhost = ghost
        model.PrimaryPart.LocalTransparencyModifier = 1
    end

    self.ScaleHandles:Open(cf, self.ScaleSize, entry.ResizeMode, entry.Model.PrimaryPart.Size)
    self:RefreshPointer()
    self:RefreshHUD()
end

function Controller:UpdateScalePreview(cf, size)
    if not self.ScaleMode then return end

    self.ScaleCF = cf
    self.ScaleSize = size
    self.CurrentSize = size

    local ghost = if self.Mode == "Edit" then self.ScaleGhost else self.Preview
    if ghost and ghost.PrimaryPart then
        ghost.PrimaryPart.Size = size
        ghost:PivotTo(cf)
        if not ghost.Parent then ghost.Parent = workspace end
    end
    self:RefreshHUD()
end

function Controller:CommitScale(cf, size, oldCF, oldSize)
    if not self.ScaleMode then return false end
    if self.Mode == "Build" then
        return true -- Build only updates its ghost; placement is a later click.
    end
    if not self.Selected or not self.Selected.Parent then return false end

    -- A full drag is one history entry; no per-frame server calls.
    local ok = self:Request({
        action = "Update",
        instanceId = self.Selected:GetAttribute("InstanceId"),
        position = cf.Position,
        steps = stepsCopy(self.Steps),
        size = size,
    })
    if ok then
        self.CurrentSize = size
    else
        self.CurrentSize = oldSize
    end
    return ok
end

function Controller:EndScale()
    if not self.ScaleMode then return end

    -- Escape/V during an unfinished mouse drag cancels the tentative
    -- dimensions rather than leaving the HUD showing an uncommitted size.
    local drag = self.ScaleHandles and self.ScaleHandles.Drag
    if drag then
        self:UpdateScalePreview(drag.StartCF, drag.StartSize)
    end

    self.ScaleMode = false
    self.ScaleHandles:Close()

    if self.ScaleGhost then
        self.ScaleGhost:Destroy()
        self.ScaleGhost = nil
    end
    if self.Selected and self.Selected.PrimaryPart then
        self.Selected.PrimaryPart.LocalTransparencyModifier = 0
    end

    self.ScaleCF = nil
    self.ScaleSize = nil
    self.IgnoreClickUntil = os.clock() + 0.2
    self:RefreshPointer()
    self:RefreshHUD()
end

function Controller:Delete()
    if self.Pending then return end
    local payload
    if self.SelectedComponentId then
        payload = { action = "DeleteComponent", componentId = self.SelectedComponentId }
    elseif self.Selected then
        payload = {
            action = "Delete",
            instanceId = self.Selected:GetAttribute("InstanceId"),
        }
    else
        return
    end
    if self:Request(payload) then self:SetSelection(nil) end
end

function Controller:History(redo)
    if self.Mode ~= "Build" and self.Mode ~= "Edit" then return end
    local success = self:Request({ action = if redo then "Redo" else "Undo" })
    if success then
        self.EditingComponentId = nil
        self:SetSelection(nil)
    end
end

function Controller:OnInput(input, processed)
    local key = input.KeyCode
    if UserInputService:GetFocusedTextBox() then return end
    if self.Mode ~= "Build" and self.Mode ~= "Edit" then return end

    if key == Enum.KeyCode.Escape then
        if self.ScaleMode then self:EndScale() end
        if self.CatalogOpen then self:ShowCatalog(false) end
        if self.Pending then self:CancelPending() self:RefreshHUD() end
        return
    end
    if key == Enum.KeyCode.V and not processed then
        if self.ScaleMode then self:EndScale() else self:BeginScale() end
        return
    end
    if self.ScaleMode then return end
    if processed then return end

    local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if ctrl then
        if key == Enum.KeyCode.Z then self:History(false) end
        if key == Enum.KeyCode.Y then self:History(true) end
        if key == Enum.KeyCode.D and self.Mode == "Edit" then self:StartMove(true) end
        return
    end

    if key == Enum.KeyCode.B and self.Mode == "Build" then
        self:ShowCatalog(not self.CatalogOpen)
        return
    end
    if self.CatalogOpen then return end

    if self.Mode == "Edit" and key == Enum.KeyCode.C then
        self:CreateComponent()
    elseif self.Mode == "Edit" and key == Enum.KeyCode.E then
        self:ToggleComponentEdit()
    elseif self.Mode == "Edit" and key == Enum.KeyCode.U then
        self:UngroupComponent()
    elseif key == Enum.KeyCode.R then
        self:Rotate("y")
    elseif key == Enum.KeyCode.T then
        self:Rotate("x")
    elseif key == Enum.KeyCode.Y then
        self:Rotate("z")
    elseif self.Mode == "Edit" and key == Enum.KeyCode.G then
        self:StartMove(false)
    elseif self.Mode == "Edit" and key == Enum.KeyCode.F then
        self:StartMove(true)
    elseif self.Mode == "Edit" and (key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace) then
        self:Delete()
    end
end

function Controller:Start()
    if self.Started then return end
    self.Started = true
    self:MakeUI()

    table.insert(self.Connections, self.Tools.Changed.Event:Connect(function(mode)
        self:OnModeChanged(mode)
    end))
    table.insert(self.Connections, self.Tools.Activated.Event:Connect(function(mode)
        self:Activate(mode)
    end))
    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        self:OnInput(input, processed)
    end))
    RunService:BindToRenderStep("OPENWORKS_CursorUnlock",
        Enum.RenderPriority.Camera.Value + 2, function()
            if self.CatalogOpen then
                -- Native first-person camera can re-lock the cursor per-frame.
                -- Keep the catalog interactive without modifying the toolbar.
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                UserInputService.MouseIconEnabled = true
            elseif self.ScaleMode then
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                UserInputService.MouseIconEnabled = false
            end
        end)

    table.insert(self.Connections, RunService.RenderStepped:Connect(function()
        if self.Mode == "Build" or (self.Mode == "Edit" and self.Pending) then
            self:UpdatePreview()
        end
        if self.StatusMessage and os.clock() >= self.MessageUntil then
            self.StatusMessage = nil
            self:RefreshHUD()
        end
    end))

    self:OnModeChanged(self.Tools.ActiveId)
    print("[OPENWORKS] Build/Edit controller ready; catalog = B")
end

function Controller:Destroy()
    self:EndScale()
    RunService:UnbindFromRenderStep("OPENWORKS_CursorUnlock")
    if self.ScaleHandles then self.ScaleHandles:Destroy() end
    self:CancelPending()
    self:ClearPreview()
    if self.SelectionHighlight then self.SelectionHighlight:Destroy() end
    for _, h in ipairs(self.SelectionHighlights) do h:Destroy() end
    table.clear(self.SelectionHighlights)
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    if self.Gui then self.Gui:Destroy() end
end

return Controller
