--!strict
-- First-person Build/Edit interaction orchestrator: selection, catalog,
-- transformation, snapping and ghost preview. The server validates all edits.
-- No runtime CSG; all authoritative edits are checked by ConstructionService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService=game:GetService("ContextActionService")
local CameraAimRay=require(script.Parent:WaitForChild("CameraAimRay"))
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Registry = require(construction:WaitForChild("PrimitiveRegistry"))
local CatalogMetadata=require(construction:WaitForChild("PrimitiveCatalogMetadata"))
local Grid = require(construction:WaitForChild("GridMath"))
local Config = require(construction:WaitForChild("BuildConfig"))
local ComponentGeometry = require(construction:WaitForChild("ComponentGeometry"))
local SurfacePlacement = require(construction:WaitForChild("SurfacePlacement"))
local BoltMath = require(construction:WaitForChild("BoltMath"))
local PreviewFeedback = require(construction:WaitForChild("PreviewFeedback"))
local ResizeGizmo = require(script.Parent:WaitForChild("ResizeGizmo"))
local LayeredEditingController = require(script.Parent:WaitForChild("LayeredEditingController"))
local WorldMotion = require(script.Parent:WaitForChild("WorldMotion"))
local ComponentBankPreview=require(script.Parent:WaitForChild("ComponentBankPreview"))
local FitOrigin=require(construction:WaitForChild("FitOrigin"))
local FitSolver=require(construction:WaitForChild("FitSolver"))
local FitPivotSnap=require(script.Parent:WaitForChild("FitPivotSnap"))
local FitPivotHandle=require(script.Parent:WaitForChild("FitPivotHandle"))
local RotationMath = require(construction:WaitForChild("RotationMath"))
local SmartPlacement = require(construction:WaitForChild("SmartPlacement"))
local MultiFit = require(construction:WaitForChild("MultiFitMath"))
local AlignmentMath = require(construction:WaitForChild("AlignmentMath"))
local BoreClearance = require(construction:WaitForChild("BoreClearance"))
local NumericSizePanel = require(script.Parent:WaitForChild("NumericSizePanel"))
local Theme = require(script.Parent:WaitForChild("StudioTheme"))

local BLUE = Theme.Accent
local DARK = Theme.Window
local PANEL = Theme.Raised
local TEXT = Theme.Text
local MUTED = Theme.Muted

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
    create("UICorner", { CornerRadius = UDim.new(0, Theme.Radius) }, gui)
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
        PreviewVisualPose = nil,
        PreviewTime = 0,
        SmartMatch = nil,
        SmartMatches = {},
        SmartPreferred = nil,
        SmartHighlight = nil,
        SmartOffsetDeltaU = 0,
        SmartRollDelta = 0,
        SmartBoreKind = "Cylindrical",
        SmartLastScan = 0,
        CatalogOpen = false,
        CurrentBank=nil,
        BankModal=nil,
        BankEntries={},
        BankConfirmRemove=nil,
        PivotSetting=false,
        PivotModeIndex=1,
        FitPivotHandle=nil,
        CatalogCollapsed={},
        CurrentDisplayName=nil,
        ScaleMode = false,
        NumericPrecision = false,
        Numeric = nil,
        PendingMateChoice = nil,
        LockedAlignment = nil,
        Assembly = nil,
        ScaleStepU = Grid.DefaultSizeStepU,
        PreviewValid = true,
        LastPreviewCheck = 0,
        ScaleGhost = nil,
        ScaleCF = nil,
        ScaleSize = nil,
        ScaleVisualCF = nil,
        ScaleVisualSize = nil,
        ScaleHandles = nil,
        DirectDragCandidate = nil,
        DirectDragActive = false,
        MoveShadowStates=nil,
        VerticalHeld=nil,VerticalElapsed=0,
        Layered = nil,
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
        Name="ConstructionStatus",
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.03,
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
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-22,0.5,0),
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.025,
        BorderSizePixel = 0,
        Visible = false,
    }, gui), 10)

    label(catalog, "BUILD LIBRARY", UDim2.fromOffset(220, 30), UDim2.fromOffset(13, 9), 17)
    local close = button(catalog, "×  CLOSE", UDim2.fromOffset(90, 29), UDim2.fromOffset(226, 10))
    close.Activated:Connect(function() self:ShowCatalog(false) end)

    label(catalog, "Place primitives or reusable saved components", UDim2.fromOffset(300, 24),
        UDim2.fromOffset(13, 40), 12, MUTED)

    local search=create("TextBox",{
        Name="Search",Text="",PlaceholderText="Search primitives or saved components…",
        ClearTextOnFocus=false,BackgroundColor3=PANEL,
        TextColor3=TEXT,PlaceholderColor3=MUTED,
        Font=Enum.Font.GothamMedium,TextSize=13,
        TextXAlignment=Enum.TextXAlignment.Left,
        Position=UDim2.fromOffset(12,72),
        Size=UDim2.new(1,-24,0,34),BorderSizePixel=0,
    },catalog)
    rounded(search,7)
    create("UIPadding",{
        PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),
    },search)
    local list = create("ScrollingFrame", {
        Name = "Items",
        Position = UDim2.fromOffset(12,116),
        Size = UDim2.new(1, -24, 1, -175),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, catalog)
    create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

    -- Register an authored component from the same Build library as stock
    -- primitives; avoid a separate native Edit/Bank tool.
    local registerButton=button(catalog,"SAVE SELECTED COMPONENT",
        UDim2.new(1,-24,0,31),UDim2.new(0,12,1,-40))
    registerButton.Activated:Connect(function() self:OpenBankSave() end)

    local modal=rounded(create("Frame",{
        Name="OPENWORKS_BankSave",Visible=false,ZIndex=42,
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.43),Size=UDim2.fromOffset(370,172),
        BackgroundColor3=DARK,BorderSizePixel=0,
    },gui),10)
    local modalTitle=label(modal,"SAVE COMPONENT TO LIBRARY",
        UDim2.fromOffset(342,24),UDim2.fromOffset(15,11),16)
    modalTitle.ZIndex=43
    local bankInput=create("TextBox",{
        Name="ComponentName",ZIndex=43,Text="",PlaceholderText="Component name",
        ClearTextOnFocus=false,Size=UDim2.fromOffset(340,39),
        Position=UDim2.fromOffset(15,45),BackgroundColor3=PANEL,
        TextColor3=TEXT,PlaceholderColor3=MUTED,
        TextSize=14,Font=Enum.Font.GothamMedium,BorderSizePixel=0,
    },modal)
    rounded(bankInput,7)
    local save=button(modal,"SAVE COMPONENT",
        UDim2.fromOffset(164,37),UDim2.fromOffset(15,105))
    local cancel=button(modal,"CANCEL",
        UDim2.fromOffset(164,37),UDim2.fromOffset(191,105))
    save.ZIndex=43
    cancel.ZIndex=43
    save.Activated:Connect(function() self:ConfirmBankSave() end)
    cancel.Activated:Connect(function() self:CloseBankSave() end)
    bankInput.FocusLost:Connect(function(enter)
        if enter and modal.Visible then self:ConfirmBankSave() end
    end)

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
    self.StatusFrame=status
    self.TitleLabel = title
    self.DetailLabel = details
    self.HelpLabel = help
    self.Catalog = catalog
    self.List = list
    self.CatalogSearch=search
    self.BankModal=modal
    self.BankNameInput=bankInput
    self.BankRegisterButton=registerButton
    search:GetPropertyChangedSignal("Text"):Connect(function()
        if self.CatalogOpen then self:RefreshCatalog() end
    end)
    self.Unlock = unlock
    self.Crosshair = crosshair
    self.Numeric = NumericSizePanel.new(gui)
    self.FitPivotHandle=FitPivotHandle.new()
    self.ScaleHandles = ResizeGizmo.new(gui, function(cf, size)
        self:UpdateScalePreview(cf, size)
    end, function(cf, size, oldCF, oldSize)
        return self:CommitScale(cf, size, oldCF, oldSize)
    end, function(axis, sign)
        self:Message("Resizing " .. ({ "X", "Y", "Z" })[axis]
            .. (if sign > 0 then "+" else "-") .. " — drag to change size")
    end)
end

function Controller:BankRequest(payload)
    local ok,result=pcall(function() return self.Remote:InvokeServer(payload) end)
    if not ok or type(result)~="table" or not result.ok then
        self:Message(if ok and type(result)=="table"
            then tostring(result.message) else "Component bank unavailable")
        return nil
    end
    return result.data,result
end

function Controller:RefreshBankEntries()
    local data=self:BankRequest({action="ListComponentBank"})
    self.BankEntries=if data and type(data.entries)=="table"
        then data.entries else {}
    self.BankLoaded=true
end

function Controller:RefreshCatalog()
    if not self.List then return end
    for _,child in ipairs(self.List:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel")
            or child:IsA("Frame") then child:Destroy() end
    end

    local search=if self.CatalogSearch
        then self.CatalogSearch.Text:lower():match("^%s*(.-)%s*$")
        else ""
    local searching=search~=""
    local order=0
    local matches=0
    local function advance()
        order+=1
        return order
    end
    local function header(name,count)
        local collapsed=self.CatalogCollapsed[name]==true
        local h=button(self.List,
            (if collapsed and not searching then "▸  " else "▾  ")
                ..name:upper().."    "..tostring(count),
            UDim2.new(1,-7,0,29))
        h.LayoutOrder=advance()
        h.TextColor3=Theme.Accent
        h.TextXAlignment=Enum.TextXAlignment.Left
        h.Activated:Connect(function()
            if not searching then
                self.CatalogCollapsed[name]=not collapsed
                self:RefreshCatalog()
            end
        end)
        return not collapsed or searching
    end

    local bank={}
    for _,entry in ipairs(self.BankEntries) do
        if not searching or (entry.name.." saved component bank")
            :lower():find(search,1,true) then
            table.insert(bank,entry)
        end
    end
    if #bank>0 or not searching then
        if header("My Components",#bank) then
            if #bank==0 then
                local empty=label(self.List,
                    "Nothing saved yet  ·  Select a component, Shift+B",
                    UDim2.new(1,-8,0,36),UDim2.fromOffset(0,0),12,MUTED)
                empty.LayoutOrder=advance()
            end
            for _,entry in ipairs(bank) do
                matches+=1
                local row=create("Frame",{
                    Size=UDim2.new(1,-7,0,38),
                    BackgroundTransparency=1,BorderSizePixel=0,
                    LayoutOrder=advance(),
                },self.List)
                local use=button(row,entry.name.."  ·  "..tostring(entry.parts).." parts",
                    UDim2.new(1,-44,1,0),UDim2.fromOffset(0,0))
                use.TextXAlignment=Enum.TextXAlignment.Left
                use.Activated:Connect(function()
                    self:SelectBank(entry.id)
                    self:ShowCatalog(false)
                end)
                local remove=button(row,
                    if self.BankConfirmRemove==entry.id then "?" else "×",
                    UDim2.fromOffset(38,38),UDim2.new(1,-38,0,0))
                remove.Activated:Connect(function()
                    if self.BankConfirmRemove~=entry.id then
                        self.BankConfirmRemove=entry.id
                        self:Message("Click ? again to remove "..entry.name.." from the bank")
                        self:RefreshCatalog()
                        return
                    end
                    self.BankConfirmRemove=nil
                    local _,result=self:BankRequest({
                        action="RemoveComponentBank",bankId=entry.id,
                    })
                    if result then
                        self:RefreshBankEntries()
                        self:RefreshCatalog()
                    end
                end)
            end
        end
    end
    local grouped={}
    local entries=Registry.List()
    for _,entry in ipairs(entries) do
        if not searching or entry.SearchText:find(search,1,true) then
            local group=entry.Category
            if not grouped[group] then grouped[group]={} end
            table.insert(grouped[group],entry)
            matches+=1
        end
    end
    for _,category in ipairs(CatalogMetadata.Categories) do
        local group=grouped[category]
        if group and #group>0 and header(category,#group) then
            for _,entry in ipairs(group) do
                local b=button(self.List,entry.DisplayName,
                    UDim2.new(1,-7,0,34))
                b.LayoutOrder=advance()
                b.TextXAlignment=Enum.TextXAlignment.Left
                b.BackgroundColor3=if entry.Id==self.CurrentId
                    then Theme.Active else PANEL
                b.Activated:Connect(function()
                    self:SelectPrimitive(entry.Id)
                    self:ShowCatalog(false)
                end)
            end
        end
    end
    if #entries==0 then
        local missing=label(self.List,
            "No primitives found. Generate and save the Studio library.",
            UDim2.new(1,-8,0,54),UDim2.fromOffset(0,0),13,MUTED)
        missing.LayoutOrder=advance()
    elseif searching and matches==0 then
        local empty=label(self.List,"No parts match “"..search.."”",
            UDim2.new(1,-8,0,42),UDim2.fromOffset(0,0),13,MUTED)
        empty.LayoutOrder=advance()
    end
end

function Controller:CloseBankSave()
    if self.BankModal then self.BankModal.Visible=false end
    self:RefreshPointer()
end

function Controller:OpenBankSave()
    if self.Tools.PrimaryId~="Edit" or self.Mode~="Edit"
        or not self.SelectedComponentId or self.Pending or self.PivotSetting then
        self:Message("Select a completed component in Edit before registering")
        return
    end
    self:ShowCatalog(false)
    self.BankNameInput.Text=""
    self.BankModal.Visible=true
    self.BankNameInput:CaptureFocus()
    self:RefreshPointer()
end

function Controller:ConfirmBankSave()
    if not self.BankModal or not self.BankModal.Visible then return end
    local name=self.BankNameInput.Text:match("^%s*(.-)%s*$")
    if #name==0 then self:Message("Enter a component name") return end
    local _,result=self:BankRequest({
        action="RegisterComponentBank",
        componentId=self.SelectedComponentId,name=name,
    })
    if not result then return end
    self:CloseBankSave()
    self:RefreshBankEntries()
    self:Message(result.message)
end

function Controller:SelectBank(id)
    if self.Tools.PrimaryId~="Build" then return end
    local data=self:BankRequest({action="GetComponentBank",bankId=id})
    if not data or type(data.parts)~="table" then return end
    local test,anchor=ComponentBankPreview.Create(data)
    if not test then
        self:Message(tostring(anchor or "Blueprint geometry is unavailable"))
        return
    end
    local anchorSize=anchor.PrimaryPart.Size
    test:Destroy()
    if self.Assembly then self.Assembly:Reset() end
    self:CancelPending()
    self:SetSelection(nil)
    self:BeginPlacement()
    self.CurrentBank=data
    self.CurrentDisplayName=data.name
    self.CurrentId=nil
    self.CurrentSize=anchorSize
    self.Steps={x=0,y=0,z=0}
    self.NumericPrecision=false
    self:RebuildPreview()
    self:RefreshHUD()
end

function Controller:RefreshPointer()
    -- Locked-mouse freecam uses center aiming unless a GUI explicitly
    -- needs cursor interaction. Scale and construction share center aim.
    local unlocked=self.CatalogOpen or (self.BankModal and self.BankModal.Visible)
        or self.PendingMateChoice~=nil
        or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
    -- The click-only relationship picker owns its own full-screen modal
    -- surface; never show the catalog's invisible hitbox over the dialog.
    self.Unlock.Visible = self.CatalogOpen or (self.BankModal and self.BankModal.Visible)
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
    self.CatalogOpen = visible and self.Tools.PrimaryId=="Build"
        and (self.Mode=="Build" or self.Mode=="Edit")
    if wasOpen and not self.CatalogOpen then
        self.IgnoreClickUntil = os.clock() + 0.2
    end
    self.Catalog.Visible = self.CatalogOpen
    self:RefreshPointer()

    if self.CatalogOpen then
        self:RefreshBankEntries()
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
    if self.StatusFrame then
        self.StatusFrame.Visible=self.UnifiedExplorer==nil
    end
    self.Gui.Enabled = self.Mode == "Build" or self.Mode == "Edit" or self.Mode == "Inspect"
    if not self.Gui.Enabled then return end

    local mode = self.Mode
    local current = self.CurrentDisplayName or self.CurrentId or "Choose a primitive"
    local size = self.CurrentSize

    self.TitleLabel.Text = "OPENWORKS / BUILD"
    if self.PivotSetting then
        self.DetailLabel.Text="ALIGNMENT ORIGIN / "..FitPivotSnap.Modes[self.PivotModeIndex]
        self.HelpLabel.Text="Aim at selected surface • Q/E point mode • click set • Enter exit • Shift+O reset"
        return
    end
    if self.SmartMatch and not (self.Layered and self.Layered.Alignment)
        and (self.Mode == "Build" or self.Pending) then
        local match=self.SmartMatch
        self.DetailLabel.Text=string.upper(match.relationKind)
            .. " / "..tostring(match.target.Name)
            .. (if match.kind=="Bore" and (match.fittedCount or 0)>1
                then "  •  "..tostring(match.fittedCount).." points" else "")
        self.HelpLabel.Text=if match.kind=="Bore"
            then (if self.LockedAlignment
                then "POSITION • wheel depth • Q/E roll • click for relationships"
                else "Align shaft and hole • click to choose relationship")
            elseif match.kind=="CrankCoupling"
            then "Click to couple hand crank to shaft end • physical weld, not motor"
            elseif match.kind=="Gear"
            then (if self.Mode=="Build" then "Click to place meshed gear" else "Release to position gear")
                .. " • automatic engagement in Simulate • Tab target • Alt free"
            elseif match.kind=="Hub"
            then "Click to rigidly weld gear/pulley hub onto shaft"
                .. " • wheel insertion depth"
            elseif match.kind=="BoltHole" then
                (if self.Mode=="Build" then "Click to place bolt"
                    else "Release to fasten bolt")
                .. " • shaft connects all pierced aligned holes"
            else (if self.Mode=="Build" then "Click to place" else "Release to place")
                .. " • touching is NOT welded • Alt free"
    elseif self.Layered and self.Layered.Alignment then
        local alignment = self.Layered.Alignment
        if alignment.Stage == "PickTarget" then
            self.DetailLabel.Text = "ALIGN SHAFT  /  choose an opening"
            self.HelpLabel.Text = "Aim at tube or drilled hole • click • Tab behind • Esc cancel"
        elseif alignment.Stage == "Fit" then
            local shaft = alignment.Shaft
            local diameter = if shaft and shaft.PrimaryPart
                then shaft.PrimaryPart.Size.Y / Grid.Unit else 0
            self.DetailLabel.Text = string.format(
                "SHAFT FIT  /  %.2f U diameter", diameter)
            self.HelpLabel.Text =
                "Scroll 0.05 U to snug fit • click / Esc to finish"
        else
            self.DetailLabel.Text = "INSERTION OFFSET  /  "
                .. tostring(alignment.OffsetUnits) .. " U"
            self.HelpLabel.Text = "Mouse wheel changes depth • click confirm • Esc cancel"
        end
    elseif self.Mode == "Inspect" then
        local target = self.Selected
        local dimensions = nil
        if self.SelectedComponentId then
            local _, size = ComponentGeometry.Bounds(self.SelectedParts)
            dimensions = size
        elseif target and target.PrimaryPart then
            dimensions = target.PrimaryPart.Size
        end
        self.DetailLabel.Text = (if self.SelectedComponentId then
            "Component / " .. tostring(#self.SelectedParts) .. " parts"
            elseif target then target.Name else "Aim and click to inspect")
            .. (if dimensions then string.format("  /  %.1f × %.1f × %.1f U",
                dimensions.X / Grid.Unit, dimensions.Y / Grid.Unit,
                dimensions.Z / Grid.Unit) else "")
        self.HelpLabel.Text = "Tab depth • Shift+Tab reverse • X X-ray • I isolate"
    elseif self.ScaleMode then
        self.DetailLabel.Text = current .. (if self.ScaleSize then
            "  •  " .. string.format("%.2g × %.2g × %.2g U",
                self.ScaleSize.X / Grid.Unit, self.ScaleSize.Y / Grid.Unit, self.ScaleSize.Z / Grid.Unit)
            else "")
        local aligned=self.Mode=="Edit" and self.Selected
            and type(self.Selected:GetAttribute("AlignedOpeningId"))=="string"
        self.HelpLabel.Text = (if aligned
            then "Aligned shaft • length-only grips • "
            else "Scale: ")
            .. tostring(self.ScaleHandles.IncrementU)
            .. " U • sphere drag • N enter exact U size • V exit"
    elseif mode == "Build" then
        self.DetailLabel.Text = current .. (if size then "  •  " .. string.format("%.2g × %.2g × %.2g U",
            size.X / Grid.Unit, size.Y / Grid.Unit, size.Z / Grid.Unit) else "")
        self.HelpLabel.Text = if self.CatalogOpen then "Search library • B/Enter close"
            elseif self.CurrentBank then "Click stamp component • Enter select • B library"
            else "B library • R/T/Y rotate • V grips • Enter select"
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
            else "Double-click member to edit • G move • E interior • U ungroup"
    elseif #self.SelectedParts > 1 then
        self.DetailLabel.Text = tostring(#self.SelectedParts) .. " primitives selected"
        self.HelpLabel.Text = "C combine  •  Shift+click to change selection"
    elseif self.EditingComponentId then
        self.DetailLabel.Text = (self.Selected and self.Selected.Name or "Editing component")
            .. "  /  component interior"
        self.HelpLabel.Text = "Click other members • V scale • E select whole component"
    else
        local target = self.Selected
        self.DetailLabel.Text = if target then target.Name .. " / V grips • N exact U" else "Click a constructed piece"
        self.HelpLabel.Text = "B library • O alignment origin • Alt+arrows nudge • V scale"
    end

    if self.Layered and self.Layered.Alignment
        and self.Layered.Alignment.Stage == "Preview"
        and self.Layered.Alignment.Valid == false then
        self.DetailLabel.Text = "RED / " .. tostring(
            self.Layered.Alignment.ConflictReason or "Geometry interference")
    elseif self.Preview and self.PreviewValid == false then
        self.DetailLabel.Text = "RED / " .. tostring(
            self.PreviewReason or "Geometry interference")
    end

    if self.StatusMessage and os.clock() < self.MessageUntil then
        self.DetailLabel.Text = self.StatusMessage
    end
end

-- Build and Edit are separate native tools. Keep legacy Mode strings for
-- the placement, layered editing and fitting controllers.
function Controller:BeginPlacement()
    if self.Tools.PrimaryId~="Build" then return end
    if self.Mode~="Build" then
        self:EndScale()
        self:CancelPending()
        self:ClearSmartMatch()
        self:SetSelection(nil)
        self.EditingComponentId=nil
        self.Mode="Build"
        if self.Layered then self.Layered:OnModeChanged("Build") end
    end
    self:RefreshHUD()
end

function Controller:SelectPrimitive(id)
    self.NumericPrecision=false
    self.CurrentBank=nil
    local entry = Registry.Get(id)
    if not entry then return end
    self:BeginPlacement()

    self.CurrentId = id
    self.CurrentDisplayName=entry.DisplayName
    self.CurrentSize = entry.Model.PrimaryPart.Size
    self.Steps = { x = 0, y = 0, z = 0 }
    self.Pending = nil
    self:RebuildPreview()
    self:RefreshHUD()
end

function Controller:StopPlacement()
    if self.Mode~="Build" or self.Tools.PrimaryId~="Build" then return end
    self:ClearSmartMatch()
    self:ClearPreview()
    self.CurrentBank=nil
    self.CurrentDisplayName=nil
    -- Return to idle Build, NOT to Edit. Equip hotbar 2 to manipulate.
    self.CurrentId=nil
    self.CurrentSize=nil
    self.Mode="Build"
    if self.Layered then self.Layered:OnModeChanged("Build") end
    self:RefreshHUD()
end

function Controller:ClearPreview()
    if self.Feedback then self.Feedback:SetGhost(nil,true) end
    if self.Preview then self.Preview:Destroy() end
    if self.FitIndicatorRoot then self.FitIndicatorRoot:Destroy() end
    self.FitIndicatorRoot=nil
    self.FitIndicatorDots=nil
    self.Preview = nil
    self.PreviewCF = nil
    -- A rebuilt ghost must be solved immediately, not inherit the previous
    -- preview's 30 Hz calculation window.
    self.PreviewComputeTime = 0
    self.PreviewTime = 0
end

function Controller:ClearSmartMatch()
    self.SmartMatch=nil
    self.SmartMatches={}
    self.SmartPreferred=nil
    self.SmartOffsetDeltaU=0
    self.SmartRollDelta=0
    self.SmartBoreKind="Cylindrical"
    self.LockedAlignment=nil
    self.SmartLastScan=0
    if self.Feedback then
        self.Feedback:Clear("snap")
        self.Feedback:SetGhostPending(false)
    end
end

function Controller:HighlightSmartTarget(match)
    if not self.Feedback then return end
    local target=match and match.target
    if not target or not target.Parent then
        self.Feedback:Clear("snap")
        self.Feedback:SetGhostPending(false)
        return
    end
    local mechanical=match.kind=="Bore" or match.kind=="Hub"
        or match.kind=="BoltHole" or match.kind=="CrankCoupling"
    self.Feedback:SetGhostPending(mechanical)
    local group=target:GetAttribute("ComponentId")
    local models={target}
    if type(group)=="string" and group~="" then
        local built=workspace:FindFirstChild(Config.FolderName)
        if built then
            for _,model in ipairs(built:GetChildren()) do
                if model:IsA("Model") and model~=target
                    and model:GetAttribute("OwnerUserId")==player.UserId
                    and model:GetAttribute("ComponentId")==group then
                    table.insert(models,model)
                end
            end
        end
    end
    -- Smart-fit target cues use the ghost's pending/collision color only.
    -- No target selection rectangle is created on passive acquisition.
    self.Feedback:Clear("snap")
end

function Controller:UpdateFitIndicators(match)
    local desired={}
    if match and match.kind=="Bore" then
        local approved={}
        for _,pair in ipairs(match.fitDetails or {}) do
            local moving=pair.moving
            local stationary=pair.stationary
            local bore=if AlignmentMath.TargetAxis(moving)
                then moving else stationary
            table.insert(desired,{
                cf=bore:GetPivot(),color=Color3.fromRGB(82,225,201)
            })
            approved[moving]=true
        end
        -- Invalid members are marked red, so a 3-of-4 fit is visible.
        for _,member in ipairs(SmartPlacement.Members(self.Preview)) do
            local fitPrimitive=if match.reverse
                then AlignmentMath.TargetAxis(member)~=nil
                else AlignmentMath.IsShaft(member)
            if fitPrimitive and not approved[member] then
                table.insert(desired,{
                    cf=member:GetPivot(),color=Color3.fromRGB(239,91,105)
                })
            end
        end
    end
    if #desired==0 then
        if self.FitIndicatorRoot then self.FitIndicatorRoot:Destroy() end
        self.FitIndicatorRoot=nil
        self.FitIndicatorDots=nil
        return
    end
    if not self.FitIndicatorRoot then
        local root=Instance.new("Folder")
        root.Name="OPENWORKS_MultiFitIndicators"
        root.Parent=workspace
        self.FitIndicatorRoot=root
        self.FitIndicatorDots={}
    end
    for i,item in ipairs(desired) do
        local dot=self.FitIndicatorDots[i]
        if not dot then
            dot=Instance.new("SphereHandleAdornment")
            dot.Name="FitPoint_"..i
            dot.Radius=0.068
            dot.AlwaysOnTop=false
            dot.Parent=self.FitIndicatorRoot
            self.FitIndicatorDots[i]=dot
        end
        local subject=if match and match.target and match.target.PrimaryPart
            then match.target.PrimaryPart else self.Preview.PrimaryPart
        if subject then
            dot.Adornee=subject
            dot.CFrame=subject.CFrame:ToObjectSpace(item.cf)
            dot.Visible=true
        else
            dot.Visible=false
        end
        dot.Color3=item.color
        dot.Transparency=0.08
    end
    for i=#self.FitIndicatorDots,#desired+1,-1 do
        self.FitIndicatorDots[i]:Destroy()
        table.remove(self.FitIndicatorDots,i)
    end
end

function Controller:CycleSmartTarget(reverse)
    if #self.SmartMatches<2 or not self.SmartMatch then return false end
    local at=1
    for i,candidate in ipairs(self.SmartMatches) do
        if candidate.target==self.SmartMatch.target then at=i break end
    end
    local nextIndex=(at-1+(if reverse then -1 else 1))%#self.SmartMatches+1
    self.SmartPreferred=self.SmartMatches[nextIndex].target
    self.SmartOffsetDeltaU=0
    self.SmartRollDelta=0
    self.LastPreviewCheck=0
    return true
end

function Controller:BeginAlignmentPositioning()
    local match=self.SmartMatch
    if not match or match.kind~="Bore" or not self.PreviewCF
        or not self.PreviewValid then
        self:Message(self.PreviewReason or "Align a valid shaft and opening first")
        return false
    end
    if self.LockedAlignment then return true end
    -- Capture source-to-group offset at the EXACT solved pose, not the
    -- easing/damped visual ghost from a previous RenderStepped frame.
    self.Preview:PivotTo(self.PreviewCF)
    local localSource=self.Preview:GetPivot():ToObjectSpace(match.source:GetPivot())
    self.LockedAlignment={
        cf=self.PreviewCF,
        localSource=localSource,
        offset=match.offsetUnits,
        roll=match.rollDegrees,
        match=match,
    }
    self.SmartOffsetDeltaU=0
    self.SmartRollDelta=0
    self.LastPreviewCheck=0
    self:RefreshHUD()
    return true
end

function Controller:OpenMateChoice(mode)
    local match=self.SmartMatch
    if not match or (match.kind~="Bore" and match.kind~="Hub")
        or self.PendingMateChoice then
        return false
    end
    -- One click on a valid hole/shaft or gear/shaft fit opens a mouse
    -- picker. Bore users can still choose "Adjust depth / roll first",
    -- then click once more to reopen this picker after adjustments.
    if match.kind=="Bore" and not self.LockedAlignment then
        if not self:BeginAlignmentPositioning() then return false end
    end
    self.PendingMateChoice=mode
    self.DirectDragCandidate=nil
    self.DirectDragActive=false
    -- Freeze the exact pair and solved pose while the mouse is unlocked.
    -- Never let camera movement or a different hovered part change the
    -- relationship that the user approves in the popup.
    local chosenMatch=table.clone(match)
    local chosenPose=self.PreviewCF
    local chosenValid=self.PreviewValid
    local function onChoice(kind)
        local requestMode=self.PendingMateChoice
        self.PendingMateChoice=nil
        -- A UI click must not also activate the equipped Roblox build tool
        -- and create a second placement on the same mouse release.
        self.IgnoreClickUntil=os.clock()+0.22
        if kind then
            self.SmartMatch=chosenMatch
            self.PreviewCF=chosenPose
            self.PreviewValid=chosenValid
        end
        if kind=="__Adjust" then
            -- Continue with the pre-existing depth/roll adjustment stage.
            -- No construction or relationship has been created yet.
            self:RefreshPointer()
            self:RefreshHUD()
            return
        elseif kind and requestMode=="Build" then
            self:Place(kind)
        elseif kind and requestMode=="Edit" then
            self:SmartDrop(kind)
        elseif requestMode=="Edit" then
            self:CancelPending()
        end
        self:RefreshPointer()
        self:RefreshHUD()
    end
    if not (self.UnifiedExplorer and self.UnifiedExplorer:ChooseFit(
        match.kind,onChoice,match.fittedCount or 1)) then
        -- No second hidden menu owner; this cancels safely if the shared
        -- chooser is temporarily unavailable during initialization.
        onChoice(nil)
    end
    return true
end

-- Capture the last visible ghost for a short, one-way presentation handoff.
-- The edit still commits the precise (non-smoothed) PreviewCF to the server.
function Controller:CapturePendingHandoff()
    if not self.Preview or not self.PreviewCF
        or (self.Pending~="Move" and self.Pending~="ComponentMove") then
        return nil
    end
    local models=if self.Pending=="ComponentMove"
        then table.clone(self.SelectedParts)
        else if self.Selected then {self.Selected} else {}
    if #models==0 or #models>48
        or not WorldMotion.NeedsHandoff(self.Preview,self.PreviewCF) then
        return nil
    end
    return self.Preview:Clone(),self.PreviewCF,models
end

function Controller:FinishPendingHandoff(snapshot,goal,models,succeeded)
    if succeeded and snapshot and goal then
        WorldMotion.SettlePreview(snapshot,goal,models)
    elseif snapshot then
        snapshot:Destroy()
    end
end

function Controller:SmartDrop(chosenKind)
    local match=self.SmartMatch
    if not match or not match.target.Parent
        or self.Pending=="Copy" or self.Pending=="ComponentCopy" then
        return false
    end
    if not self.PreviewValid then
        self:Message(self.PreviewReason or "Red snap: physical interference")
        return true
    end
    -- A custom alignment origin affects pose only; it never authors a joint.
    -- Continue through normal Update/TransformComponent validators.
    if match.kind=="Pivot" then return false end
    if (match.kind=="Bore" or match.kind=="Hub") and not chosenKind then
        return self:OpenMateChoice("Edit")
    end
    -- A multi-primitive ghost pivots at its central anchor, but the
    -- mechanical source may be a different member. Convert its LOCAL
    -- offset to the exact target pose (not the visually eased pose).
    local sourceOffset=self.Preview:GetPivot():ToObjectSpace(
        match.source:GetPivot()
    )
    local exactSourceCF=self.PreviewCF*sourceOffset
    local exactSourcePosition=exactSourceCF.Position
    local handoff,goal,models=self:CapturePendingHandoff()
    local ok=self:Request({
        action=if match.kind=="BoltHole" then "FastenBolt"
            elseif match.kind=="CrankCoupling" then "CoupleHandCrank"
            else "SmartMate",
        boltId=if match.kind=="BoltHole" then match.source:GetAttribute("InstanceId") else nil,
        sourceId=match.source:GetAttribute("InstanceId"),
        targetId=match.target:GetAttribute("InstanceId"),
        mateKind=match.kind,
        relationKind=chosenKind or match.relationKind,
        offsetUnits=match.offsetUnits,
        rollDegrees=match.rollDegrees,
        reverse=match.reverse==true,
        fitTargets=match.fitTargets,
        approach=match.approach or exactSourcePosition,
        position=exactSourcePosition,
        orientation=exactSourceCF.Rotation,
        -- The ghost was pivoted around its WHOLE component anchor; sending
        -- that exact pivot avoids re-deriving the transform from a corner.
        groupPivot=if self.Pending=="ComponentMove" then self.PreviewCF else nil,
    })
    if ok then
        if self.Feedback and (match.kind=="Bore" or match.kind=="Hub"
            or match.kind=="BoltHole" or match.kind=="CrankCoupling") then
            local participants={match.target}
            if self.Pending=="ComponentMove" then
                for _,member in ipairs(self.SelectedParts) do
                    table.insert(participants,member)
                end
            elseif self.Selected then
                table.insert(participants,self.Selected)
            end
            self.Feedback:FlashSuccess(participants)
        end
        self:CancelPending()
        self:RefreshHUD()
    end
    self:FinishPendingHandoff(handoff,goal,models,ok)
    return true
end

local function topBuiltModel(part, folder)
    local model=part
    while model and model.Parent~=folder do model=model.Parent end
    return if model and model:IsA("Model") then model else nil
end

function Controller:RecognizeAttachment(raw,hit)
    local preview=self.Preview
    local folder=workspace:FindFirstChild(Config.FolderName)
    local camera=workspace.CurrentCamera
    if not preview or not folder or not camera then return nil end
    -- A placed Bolt prefab snaps shaft-first through the nearest fitting
    -- drilled hole. Its head stays outside the entrance face.
    if BoltMath.IsBolt(preview) then
        local ignored={}
        if self.Selected and self.Pending=="Move" then
            ignored[self.Selected]=true
        end
        local aim=CameraAimRay.Ray(camera)
        local targets=SmartPlacement.NearbyTargets(
            folder,player.UserId,raw.Position,ignored,aim)
        local best,bestDistance=nil,math.huge
        local diameter=preview:GetAttribute("BoltDiameterU")*Grid.Unit
        for _,candidate in ipairs(targets) do
            local holeAxis=AlignmentMath.TargetAxis(candidate)
            local opening=BoreClearance.OpeningDiameter(candidate)
            if holeAxis and opening and opening>diameter+0.002 then
                local distance=(candidate:GetPivot().Position-raw.Position).Magnitude
                if distance<bestDistance then best=candidate bestDistance=distance end
            end
        end
        if best then
            local localAxis=AlignmentMath.TargetAxis(best)
            local axis=best:GetPivot():VectorToWorldSpace(localAxis).Unit
            if (camera.CFrame.Position-best:GetPivot().Position):Dot(axis)>0 then
                axis=-axis
            end
            local basis=if math.abs(axis:Dot(Vector3.yAxis))<0.9
                then Vector3.yAxis else Vector3.zAxis
            local up=(basis-axis*axis:Dot(basis)).Unit
            local size=best.PrimaryPart.Size
            local wall=math.abs(localAxis.X)*size.X+
                math.abs(localAxis.Y)*size.Y+math.abs(localAxis.Z)*size.Z
            local length=preview:GetAttribute("BoltLengthU")*Grid.Unit
            local point=best:GetPivot().Position+
                axis*(length*0.5-wall*0.5-0.005)
            return {kind="BoltHole",relationKind="Bolt",target=best,
                source=preview,cf=CFrame.fromMatrix(
                    point,axis,up,axis:Cross(up)),
                offsetUnits=0,rollDegrees=0}
        end
    end
    local ignore={}
    if self.Selected and self.Pending=="Move" then ignore[self.Selected]=true end
    if self.Pending=="ComponentMove" then
        for _,member in ipairs(self.SelectedParts) do ignore[member]=true end
    end
    local ray=CameraAimRay.Ray(camera)
    local aimedModel=if hit and hit.Instance
        then topBuiltModel(hit.Instance,folder) else nil
    local movingGear=false
    for _,member in ipairs(SmartPlacement.Members(preview)) do
        if type(member:GetAttribute("GearTeeth"))=="number" then
            movingGear=true
            break
        end
    end
    -- Do not keep the previous gear for another 65 ms when the crosshair
    -- directly moves onto a different gear's solid teeth.
    local switchedGear=movingGear and aimedModel
        and type(aimedModel:GetAttribute("GearTeeth"))=="number"
        and aimedModel~=(self.SmartMatch and self.SmartMatch.target)
    local fullScan=switchedGear
        or os.clock()-self.SmartLastScan>=0.065
    local targets
    if fullScan then
        self.SmartLastScan=os.clock()
        local span=0
        if self.Pending=="ComponentMove" then
            local pivot=preview:GetPivot().Position
            for _,member in ipairs(SmartPlacement.Members(preview)) do
                span=math.max(span,(member:GetPivot().Position-pivot).Magnitude)
            end
        end
        targets=SmartPlacement.NearbyTargets(
            folder,player.UserId,raw.Position,ignore,ray,span,
            preview,hit and hit.Instance
        )
    else
        targets=if self.SmartMatch and self.SmartMatch.target.Parent
            then {self.SmartMatch.target} else {}
    end
    local allTargets={}
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model.PrimaryPart
            and model:GetAttribute("OwnerUserId")==player.UserId
            and not ignore[model] then
            table.insert(allTargets,model)
        end
    end
    local match,list=SmartPlacement.Find(preview,targets,ignore,
        self.SmartPreferred or (self.SmartMatch and self.SmartMatch.target),
        ray,allTargets,aimedModel)
    if match then
        if fullScan then self.SmartMatches=list end
        if match.kind=="Hub" and self.SmartOffsetDeltaU~=0 then
            local shaft=if AlignmentMath.IsShaft(match.source)
                then match.source else match.target
            local axis=shaft:GetPivot().RightVector
            local near=(match.approach or match.source:GetPivot().Position)
                +axis*(self.SmartOffsetDeltaU*Grid.Unit)
            -- Use the SAME depth/shaft-end limits as the server, rather
            -- than moving the display ghost outside the shaft length.
            local posed,_,offset=SmartPlacement.HubPose(
                match.source,match.target,near
            )
            if posed then
                match.cf=(posed*match.source:GetPivot():Inverse())
                    *preview:GetPivot()
                match.approach=posed.Position
                match.offsetUnits=offset
            end
        end
        if match.kind=="Bore" then
            -- Before click-to-lock, alignment is geometric only. Do not
            -- carry an insertion offset from earlier hub fitting.
            if not self.LockedAlignment then
                self.SmartOffsetDeltaU=0
                self.SmartRollDelta=0
            end
            match.relationKind=self.SmartBoreKind
            local shaft=if match.reverse then match.target else match.source
            local hole=if match.reverse then match.source else match.target
            local lower,upper=AlignmentMath.InsertionBounds(shaft,hole)
            if not lower then return nil end
            local offset=math.clamp(
                match.offsetUnits+self.SmartOffsetDeltaU,lower,upper)
            local roll=math.clamp(match.rollDegrees+self.SmartRollDelta,-360,360)
            -- SmartPlacement already solved the WHOLE hole pattern. The
            -- old code unconditionally re-ran a SINGLE-hole plan here and
            -- threw away multi-point roll and corrected centering every
            -- frame. Preserve the exact multi-fit result unless the user
            -- explicitly changes depth or roll.
            if (match.fittedCount or 0)>1 then
                local axialDelta=(offset-match.offsetUnits)*Grid.Unit
                local rollDelta=roll-match.rollDegrees
                if math.abs(axialDelta)>0.00001
                    or math.abs(rollDelta)>0.00001 then
                    local pivot=preview:GetPivot()
                    local aligned=match.cf*pivot:Inverse()
                        *match.source:GetPivot()
                    local axis=if match.reverse then
                        match.target:GetPivot().RightVector.Unit
                        else match.target:GetPivot():VectorToWorldSpace(
                            AlignmentMath.TargetAxis(match.target)).Unit
                    local toward=if match.reverse then
                        aligned:VectorToWorldSpace(
                            AlignmentMath.TargetAxis(match.source)).Unit
                        else axis
                    local translation=if match.reverse then
                        -toward*axialDelta else toward*axialDelta
                    match.cf=CFrame.new(translation)*match.cf
                    if math.abs(rollDelta)>0.00001 then
                        local center=aligned.Position+translation
                        local rotation=CFrame.new(center)
                            *CFrame.fromAxisAngle(toward,
                                math.rad(rollDelta))
                            *CFrame.new(-center)
                        match.cf=rotation*match.cf
                    end
                end
                match.offsetUnits=offset
                match.rollDegrees=roll
            else
                local moving=SmartPlacement.Members(preview)
                local plan=if match.reverse then
                    AlignmentMath.ReversePlan(moving,match.source,match.target,
                        offset,roll)
                    else AlignmentMath.Plan(moving,match.source,match.target,
                        offset,roll)
                if plan then
                    match.cf=plan.delta*preview:GetPivot()
                    match.offsetUnits=offset
                    match.rollDegrees=roll
                end
            end
        end
        return match
    end
    if fullScan then self.SmartMatches={} end
    -- Contact is placement only. Welding requires a deliberate Weld-tool click.
    return nil
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
    elseif self.Mode=="Build" and self.CurrentBank then
        source=ComponentBankPreview.Create(self.CurrentBank)
    elseif self.Mode == "Build" and self.CurrentId then
        local entry = Registry.Get(self.CurrentId)
        source = entry and entry.Model
    end
    if not source then return end

    local ghost = if source.Name == "OPENWORKS_ComponentGhost" then source else source:Clone()
    ghost.Name = "OPENWORKS_Ghost"
    local combined=source.Name=="OPENWORKS_ComponentGhost"
    ghost:SetAttribute("FitPivotScope",if combined then "Component" else "Primitive")
    if source~=ghost and self.CurrentBank and self.Mode=="Build" then
        source:Destroy() -- source was a standalone, unparented bank preview
    end
    -- A component ghost is ONE presentation. Per-member transparent parts
    -- multiply shadow/shading through overlaps, so make their color solid
    -- and use one top-level Highlight for the complete assembled shape.
    -- This is only visual; preflight collision uses the actual cloned CSG.
    for _,item in ipairs(ghost:GetDescendants()) do
        if item:IsA("Highlight") or item:IsA("SelectionBox")
            or item:IsA("BillboardGui") or item:IsA("Decal")
            or item:IsA("Texture") then
            item:Destroy()
        elseif item:IsA("BasePart") then
            item.Anchored=true
            item.CanQuery=false
            item.CanCollide=false
            item.CanTouch=false
            item.CastShadow=false
            item.Reflectance=0
            item.Material=Enum.Material.SmoothPlastic
            item.Transparency=if item:GetAttribute("GearPivotOnly")==true
                then 1 else 0.65
            item.LocalTransparencyModifier=0
            item.Color=BLUE
            if item:IsA("PartOperation") then item.UsePartColor=true end
            if not combined and self.CurrentSize and item==ghost.PrimaryPart then
                item.Size=self.CurrentSize
            end
        end
    end


    if self.Mode=="Build" and self.CurrentId then
        ghost:SetAttribute("TemplateId",self.CurrentId)
        ghost:SetAttribute("InstanceId","OPENWORKS_Preflight")
    end
    ghost.Parent = workspace
    self.Preview = ghost
    if self.Feedback then self.Feedback:SetGhost(ghost,true) end
    self.PreviewValid = true
    self.LastPreviewCheck = 0
    self.PreviewVisualPose = nil
    self:ClearSmartMatch()
end

function Controller:UpdateHover()
    if not self.Feedback then return end
    -- Hover is intentionally visual-free. An outline denotes an explicit
    -- selection, not simply an object passing under the crosshair.
    self.Feedback:Clear("hover")
    return
end


function Controller:RefreshSelectionHighlights()
    if not self.Feedback then return end
    self.Feedback:Clear("selection")
    if self.Mode~="Edit" and self.Mode~="Inspect" then return end
    if self.SelectedComponentId and #self.SelectedParts>0 then
        -- Orient component bounds from the actual editor group anchor.
        local ordered={}
        if self.GroupAnchor then table.insert(ordered,self.GroupAnchor) end
        for _,member in ipairs(self.SelectedParts) do
            if member~=self.GroupAnchor then table.insert(ordered,member) end
        end
        self.Feedback:Set("selection","component",ordered,"selection",true)
    else
        -- Separate boxes for independent multi-selection.
        for i,model in ipairs(self.SelectedParts) do
            self.Feedback:Set("selection",tostring(i),{model},"selection",false)
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
    if self.Layered then self.Layered:RefreshVisuals() end
    self:RefreshHUD()
    if self.UnifiedExplorer then self.UnifiedExplorer:OnConstructionSelection() end
    if model and self.Tools.PrimaryId == "Edit"
        and self.Tools.SubtoolId == "Resize"
        and not self.ScaleMode then
        task.defer(function()
            if self.Started and self.Selected == model
                and self.Tools.PrimaryId == "Edit"
                and self.Tools.SubtoolId == "Resize"
                and not self.ScaleMode then
                self:BeginScale()
            end
        end)
    end
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
        self.GroupAnchor = nil
    else
        -- Always grab the primitive nearest the component's geometric
        -- center, even when selection order or authored dimensions change.
        self.GroupAnchor = ComponentGeometry.CentralPrimitive(self.SelectedParts)
        self.CurrentId = self.GroupAnchor:GetAttribute("TemplateId")
        self.CurrentSize = self.GroupAnchor.PrimaryPart.Size
        self.Steps = attributesSteps(self.GroupAnchor)
    end
    self:RefreshSelectionHighlights()
    if self.Layered then self.Layered:RefreshVisuals() end
    self:RefreshHUD()
    if self.UnifiedExplorer then self.UnifiedExplorer:OnConstructionSelection() end
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
    if self.Layered then self.Layered:RefreshVisuals() end
    self:RefreshHUD()
    if self.UnifiedExplorer then self.UnifiedExplorer:OnConstructionSelection() end
end

function Controller:CancelPending()
    if self.MoveShadowStates then
        for part,original in pairs(self.MoveShadowStates) do
            if part and part.Parent then part.CastShadow=original end
        end
        self.MoveShadowStates=nil
    end
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
        if self.Layered then self.Layered:RefreshVisuals() end
    end
end

function Controller:OnModeChanged(mode)
    if self.Feedback then self.Feedback:Clear("hover") end
    self.DirectDragCandidate = nil
    self.DirectDragActive = false
    self:EndScale()
    self:CancelPending()
    self.Mode = mode
    self.PendingMateChoice=nil
    if self.BankModal then self:CloseBankSave() end
    if self.Numeric then self.Numeric:Hide() end
    self:ShowCatalog(false)
    self:ClearPreview()
    if mode ~= "Edit" and mode ~= "Inspect" then
        self.EditingComponentId = nil
        self:SetSelection(nil)
    elseif mode == "Edit" then
        self:RefreshSelectionHighlights()
    end
    if self.Layered then self.Layered:OnModeChanged(mode) end
    if player:GetAttribute("OPENWORKS_Simulating") == true then
        self:ClearPreview()
        self:RefreshHUD()
        return
    end
    if mode == "Build" then
        if self.CurrentBank then
            self:RebuildPreview()
        elseif not self.CurrentId or not Registry.Get(self.CurrentId) then
            local entries = Registry.List()
            if #entries > 0 then self:SelectPrimitive(entries[1].Id) end
        else
            self:RebuildPreview()
        end
    end
    self:RefreshHUD()
end

-- Subtool-only changes do not change which native tool is equipped.
-- Apply the subtool lifecycle without reinitializing construction geometry.
function Controller:OnSubtoolChanged(primary,subtool,_previous)
    if primary~="Build" then return end
    if subtool~="Resize" and self.ScaleMode then self:EndScale() end
    -- V manages resize in Edit or the Build placement preview.
    self:RefreshHUD()
end

function Controller:CastCenter(excludeSelected)
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local ray = CameraAimRay.Ray(camera)

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
    if player:GetAttribute("OPENWORKS_Simulating") == true then
        self.PreviewCF = nil
        if self.Preview then self.Preview.Parent = nil end
        return
    end
    if self.ScaleMode then return end
    if not self.Preview or self.CatalogOpen then
        self.PreviewCF = nil
        self:ClearSmartMatch()
        if self.Preview then self.Preview.Parent = nil end
        return
    end

    -- Geometry scans and multi-fit solving are expensive with large plots.
    -- Solve at up to 30 Hz; keep the ghost interpolating on every render
    -- frame so movement stays visually smooth on high-refresh displays.
    -- Explicit placement/fit changes set LastPreviewCheck=0 to bypass the
    -- budget and calculate on the next rendered frame.
    local visualNow=os.clock()
    if self.PreviewCF and self.Preview.Parent
        and self.LastPreviewCheck~=0
        and visualNow-(self.PreviewComputeTime or 0)<1/30 then
        local dt=if self.PreviewTime>0 then visualNow-self.PreviewTime else 0
        self.PreviewTime=visualNow
        self.PreviewVisualPose=WorldMotion.Step(
            self.PreviewVisualPose,self.PreviewCF,dt,
            WorldMotion.Profile.Placement)
        self.Preview:PivotTo(self.PreviewVisualPose)
        return
    end
    self.PreviewComputeTime=visualNow

    local locked=self.LockedAlignment
    local cf,match
    local old=self.SmartMatch
    if locked then
        -- Positioning is frozen onto the already recognized fit. Camera
        -- movement cannot retarget it to another shaft while adjusting.
        if not self.Preview.Parent then self.Preview.Parent=workspace end
        match=locked.match
        if not match.target or not match.target.Parent then
            self:ClearSmartMatch()
            return
        end
        local shaft=if match.reverse then match.target else match.source
        local hole=if match.reverse then match.source else match.target
        local lower,upper=AlignmentMath.InsertionBounds(shaft,hole)
        if not lower then self:ClearSmartMatch() return end
        local offset=math.clamp(locked.offset+self.SmartOffsetDeltaU,lower,upper)
        local roll=math.clamp(locked.roll+self.SmartRollDelta,-360,360)
        -- Once a mechanical stop is reached, reverse wheel motion should
        -- move immediately rather than unwinding an overflowing delta.
        self.SmartOffsetDeltaU=offset-locked.offset
        self.SmartRollDelta=roll-locked.roll
        local alignedSource=locked.cf*locked.localSource
        local rollAxis=if match.reverse then
            alignedSource:VectorToWorldSpace(
                AlignmentMath.TargetAxis(match.source)).Unit
            else alignedSource.RightVector.Unit
        local travelAxis=if match.reverse then -rollAxis
            else match.target:GetPivot():VectorToWorldSpace(
                AlignmentMath.TargetAxis(match.target)).Unit
        local translation=travelAxis*((offset-locked.offset)*Grid.Unit)
        cf=CFrame.new(translation)*locked.cf
        if math.abs(roll-locked.roll)>0.00001 then
            local center=alignedSource.Position+translation
            cf=CFrame.new(center)*CFrame.fromAxisAngle(rollAxis,
                math.rad(roll-locked.roll))*CFrame.new(-center)*cf
        end
        match.offsetUnits=offset
        match.rollDegrees=roll
        match.cf=cf
        self.Preview:PivotTo(cf)
    else
        local hit = self:CastCenter(self.Pending == "Move"
            or self.Pending == "ComponentMove" or self.Pending == "ComponentCopy"
            or self.Pending == "Copy")
        if not hit or not self.CurrentSize then
            self.PreviewCF = nil
            if self.SmartMatch then self:ClearSmartMatch() self:RefreshHUD() end
            self.Preview.Parent = nil
            return
        end
        local rotation = Grid.Rotation(self.Steps)
        if self.GroupAnchor and
            (self.Pending=="ComponentMove" or self.Pending=="ComponentCopy") then
            local base=Grid.Rotation(attributesSteps(self.GroupAnchor))
            rotation=rotation*base:Inverse()*self.GroupAnchor:GetPivot().Rotation
        end
        local target=hit.Instance and topBuiltModel(
            hit.Instance,workspace:FindFirstChild(Config.FolderName))
        local proposed=if target then
            -- Neighbor placement stays in the target's local face frame;
            -- world-zero grid parity can offset different sized primitives.
            CFrame.new(hit.Position)*rotation
            else Grid.FromSurface(hit.Position,hit.Normal,
                self.CurrentSize,rotation)
        if not self.Preview.Parent then self.Preview.Parent=workspace end
        cf=if target then SurfacePlacement.SnapToNearbyFace(
            self.Preview,proposed,hit.Position,hit.Normal,hit.Instance)
            else SurfacePlacement.SnapToSurface(self.Preview,proposed,
                hit.Position,hit.Normal)
        local alt=UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
        local originPose=if not alt then FitSolver.SurfacePose(
            self.Preview,cf.Rotation,hit.Position) else nil
        if originPose then cf=originPose end
        self.Preview:PivotTo(cf)
        if not alt and self.Pending~="ComponentCopy" then
            match=self:RecognizeAttachment(cf,hit)
            -- Reusable blueprints preserve their own internal joints. Do not
            -- silently authorize new external joints on a bank placement.
            if self.CurrentBank and match and match.kind~="Pivot" then
                match=nil
            end
        end
    end
    self.SmartMatch=match
    if match then
        cf=match.cf
        self.Preview:PivotTo(cf)
    end
    self:HighlightSmartTarget(match)
    if (old and old.target)~=(match and match.target)
        or (old and old.kind)~=(match and match.kind) then
        self.LastPreviewCheck=0
        self:RefreshHUD()
    end
    self.PreviewCF=cf

    if os.clock() - self.LastPreviewCheck > 0.12 then
        self.LastPreviewCheck = os.clock()
        local previousValid,previousReason=self.PreviewValid,self.PreviewReason
        self.PreviewValid = true
        self.PreviewReason = nil
        local ignore = {}
        if self.Pending == "Move" and self.Selected then
            ignore[self.Selected] = true
        elseif self.Pending == "ComponentMove" then
            for _, member in ipairs(self.SelectedParts) do ignore[member] = true end
        end
        local approved=nil
        if match and match.kind=="Bore" then
            local allTargets={}
            local folder=workspace:FindFirstChild(Config.FolderName)
            if folder then
                for _,model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model")
                        and model:GetAttribute("OwnerUserId")==player.UserId
                        and not ignore[model] then
                        table.insert(allTargets,model)
                    end
                end
            end
            local moving=SmartPlacement.Members(self.Preview)
            local stationary=MultiFit.StationarySet(moving,match.target,
                allTargets,nil,ignore)
            local candidates,why=MultiFit.Find(moving,stationary)
            local matches=candidates and MultiFit.Unique(candidates,
                match.source:GetAttribute("InstanceId"),
                match.target:GetAttribute("InstanceId"))
            match.fitDetails=matches or {}
            if matches then
                approved=MultiFit.AllowMap(matches)
                match.fittedCount=#matches
                local complete,reason=MultiFit.Completeness(
                    moving,stationary,matches,match.reverse==true)
                if not complete then
                    self.PreviewValid=false
                    self.PreviewReason=reason
                end
                local names={}
                for _,pair in ipairs(matches) do
                    table.insert(names,pair.stationaryId)
                end
                table.sort(names)
                match.fitTargets=names
                local primary=false
                for _,pair in ipairs(matches) do
                    if pair.moving==match.source
                        and pair.stationary==match.target then
                        primary=true break
                    end
                end
                if not primary then
                    self.PreviewValid=false
                    self.PreviewReason="Shaft/hole fit is not coaxial or lacks clearance"
                end
            else
                self.PreviewValid=false
                self.PreviewReason=why
            end
        end
        local clear,obstruction=PreviewFeedback.Check(
            self.Preview,ignore,nil,nil,approved)
        if self.PreviewValid==false then
            -- Keep the more specific fitting error.
        else
            self.PreviewValid,self.PreviewReason=clear,obstruction
        end
        if match and match.kind=="BoltHole" and self.PreviewValid
            and not BoltMath.Fits(self.Preview,match.target) then
            self.PreviewValid=false
            self.PreviewReason="Bolt must pass through the selected hole"
        end
        if match and match.kind=="Bore" and
            (not self.LastFitCount or self.LastFitCount~=match.fittedCount) then
            self.LastFitCount=match.fittedCount
            self:RefreshHUD()
        end
        PreviewFeedback.Paint(self.Preview,self.PreviewValid)
        if self.Feedback then self.Feedback:SetGhostValid(self.PreviewValid) end
        if previousValid~=self.PreviewValid
            or previousReason~=self.PreviewReason then
            self:RefreshHUD()
        end
    end

    -- Presentation is damped independently of the exact hit/validation CF.
    local now = os.clock()
    local dt = if self.PreviewTime > 0 then now - self.PreviewTime else 0
    self.PreviewTime = now
    self.PreviewVisualPose=WorldMotion.Step(
        self.PreviewVisualPose,cf,dt,WorldMotion.Profile.Placement
    )
    self.Preview:PivotTo(self.PreviewVisualPose)
    self:UpdateFitIndicators(match)
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

function Controller:PlaceSavedComponent()
    if not self.CurrentBank or not self.PreviewCF or not self.PreviewValid then
        self:Message(self.PreviewReason or "Move the saved component to a blue valid placement")
        return
    end
    local _,result=self:BankRequest({
        action="PlaceComponentBank",
        bankId=self.CurrentBank.id,
        origin=self.PreviewCF,
    })
    if result then
        -- Keep the bank ghost active to stamp as many independent copies
        -- as desired. Enter returns to selection with no tool switch.
        self:ClearSmartMatch()
        self.PreviewVisualPose=nil
        self.LastPreviewCheck=0
        self:Message(result.message)
    end
end

function Controller:Place(chosenKind)
    if self.Mode=="Build" and self.CurrentBank then
        self:PlaceSavedComponent()
        return
    end
    if not self.PreviewCF or not self.CurrentId or not self.CurrentSize then return end
    if not self.PreviewValid then
        self:Message(self.PreviewReason
            or "Red preview: construction intersects existing geometry")
        return
    end
    -- F-copy never inherits old joints, but may authorize a NEW real
    -- attachment against the selected target, just like fresh Build.
    if self.SmartMatch
        and (self.SmartMatch.kind=="Bore" or self.SmartMatch.kind=="Hub")
        and not chosenKind then
        self:OpenMateChoice("Build")
        return
    end
    local placedMate=self.SmartMatch
    local success,reply = self:Request({
        action = if self.Pending=="Copy" then "DuplicatePrimitive" else "Place",
        sourceId=if self.Pending=="Copy" and self.Selected
            then self.Selected:GetAttribute("InstanceId") else nil,
        templateId = self.CurrentId,
        materialId=if self.Pending=="Copy" and self.Selected
            then self.Selected:GetAttribute("ConstructionMaterial") else nil,
        paintFinish=if self.Pending=="Copy" and self.Selected
            then self.Selected:GetAttribute("PaintFinish") else nil,
        paintColorHex=if self.Pending=="Copy" and self.Selected
            then self.Selected:GetAttribute("PaintColorHex") else nil,
        position = self.PreviewCF.Position,
        steps = stepsCopy(self.Steps),
        size = self.CurrentSize,
        fitPivotLocal=if self.Pending=="Copy" and self.Selected
            then self.Selected:GetAttribute("FitPivotLocal") else nil,
        numericPrecision=self.NumericPrecision==true,
        orientation=if self.Pending=="Copy" then self.PreviewCF.Rotation
            elseif self.SmartMatch
            and (self.SmartMatch.kind=="BoltHole"
                or self.SmartMatch.kind=="Bore"
                or self.SmartMatch.kind=="CrankCoupling"
                or self.SmartMatch.kind=="Hub"
                or self.SmartMatch.kind=="Pivot")
            then self.PreviewCF.Rotation else nil,
        autoMate=if self.SmartMatch and self.SmartMatch.kind~="Pivot"
            and (self.Pending~="Copy"
                or self.SmartMatch.kind=="Gear"
                or self.SmartMatch.kind=="Rack"
                or self.SmartMatch.kind=="Guide"
                or self.SmartMatch.kind=="Hub"
                or self.SmartMatch.kind=="BoltHole"
                or self.SmartMatch.kind=="CrankCoupling"
                or self.SmartMatch.kind=="Bore") then {
            -- A copied gear/bolt/crank fitted to a shaft or opening is
            -- still an actual mount. Only ambiguous Bore fits refrain
            -- from authoring mechanical relationships during F-copy.
            kind=self.SmartMatch.kind,
            targetId=self.SmartMatch.target:GetAttribute("InstanceId"),
            relationKind=chosenKind or self.SmartMatch.relationKind,
            offsetUnits=self.SmartMatch.offsetUnits,
            rollDegrees=self.SmartMatch.rollDegrees,
            reverse=self.SmartMatch.reverse==true,
            fitTargets=self.SmartMatch.fitTargets,
        } else nil,
    })
    if success then
        if self.Feedback and placedMate and self.Pending~="Copy"
            and (placedMate.kind=="Bore" or placedMate.kind=="Hub"
                or placedMate.kind=="BoltHole"
                or placedMate.kind=="CrankCoupling") then
            local target=placedMate.target
            local newId=reply and reply.instanceId
            local feedback=self.Feedback
            -- The server can acknowledge before its authored Model replicates.
            -- Only flash once the real new object exists, never a recycled ghost.
            task.spawn(function()
                local created
                if type(newId)=="string" then
                    for _=1,8 do
                        local built=workspace:FindFirstChild(Config.FolderName)
                        if built then
                            for _,model in ipairs(built:GetChildren()) do
                                if model:IsA("Model")
                                    and model:GetAttribute("InstanceId")==newId then
                                    created=model
                                    break
                                end
                            end
                        end
                        if created then break end
                        task.wait(0.05)
                    end
                end
                local participants={}
                if target and target.Parent then table.insert(participants,target) end
                if created then table.insert(participants,created) end
                if #participants>0 and feedback then
                    feedback:FlashSuccess(participants)
                end
            end)
        end
        if self.Pending=="Copy" then
            self:CancelPending()
        else
            -- Successful Build placement ends the alignment transaction.
            -- Do NOT leave the following new build ghost locked to the
            -- previously chosen rod/hole.
            self:ClearSmartMatch()
            self.PreviewVisualPose=nil
            self.LastPreviewCheck=0
        end
        self:RefreshHUD()
    end
end

function Controller:Pick()
    if self.Layered then
        self.Layered:PickCurrent()
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
    if self.SmartMatch and self:SmartDrop() then return end
    if not self.PreviewValid then
        self:Message("Red preview: movement intersects existing geometry")
        return
    end
    local handoff,goal,models=self:CapturePendingHandoff()
    local success=self:Request({
        action="Update",
        instanceId=self.Selected:GetAttribute("InstanceId"),
        position=self.PreviewCF.Position,
        steps=stepsCopy(self.Steps),
        size=self.CurrentSize,
        freePosition=true,
    })
    if success then
        self:CancelPending()
        self:RefreshHUD()
    end
    self:FinishPendingHandoff(handoff,goal,models,success)
end

function Controller:ConfirmComponentPlacement()
    if not self.SelectedComponentId or not self.GroupAnchor or not self.PreviewCF then return end
    if self.Pending=="ComponentMove" and self.SmartMatch
        and self:SmartDrop() then return end
    if not self.PreviewValid then
        self:Message(self.PreviewReason
            or "Red preview: component overlaps another construction")
        return
    end
    local isCopy=self.Pending=="ComponentCopy"
    local handoff,goal,models=self:CapturePendingHandoff()
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
    self:FinishPendingHandoff(handoff,goal,models,ok)
end

function Controller:EditFitPivot(reset)
    local anchor=if self.SelectedComponentId then self.GroupAnchor else self.Selected
    if not anchor or not anchor.Parent then
        self:Message("Select a primitive or component first")
        return
    end
    if reset then
        self.PivotSetting=false
        self:Request({
            action="SetFitPivot",reset=true,
            scope=if self.SelectedComponentId then "Component" else "Primitive",
            id=if self.SelectedComponentId then self.SelectedComponentId
                else anchor:GetAttribute("InstanceId"),
        })
        self:RefreshHUD()
        return
    end
    self.PivotSetting=true
    self.PivotModeIndex=1
    self:Message("Choose the alignment origin • aim at a selected surface and click")
end

function Controller:PivotHit()
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local members=if self.SelectedComponentId then self.SelectedParts
        else (if self.Selected then {self.Selected} else {})
    if #members==0 then return nil end
    local ray=CameraAimRay.Ray(camera)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances=members
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
    if not hit then return nil end
    local selected=topBuiltModel(hit.Instance,
        workspace:FindFirstChild(Config.FolderName))
    if not selected or not table.find(members,selected) then return nil end
    return selected,FitPivotSnap.Point(hit.Instance,hit.Position,
        FitPivotSnap.Modes[self.PivotModeIndex])
end

function Controller:CommitFitPivot()
    if not self.PivotSetting or self.Busy then return end
    local selected,position=self:PivotHit()
    if not selected then
        self:Message("Aim at a surface belonging to the selected construction")
        return
    end
    local anchor=if self.SelectedComponentId then self.GroupAnchor else self.Selected
    local succeeded=self:Request({
        action="SetFitPivot",
        scope=if self.SelectedComponentId then "Component" else "Primitive",
        id=if self.SelectedComponentId then self.SelectedComponentId
            else anchor:GetAttribute("InstanceId"),
        hitId=selected:GetAttribute("InstanceId"),
        position=position,
    })
    if succeeded then
        self.PivotSetting=false
        self:RefreshHUD()
    end
end

function Controller:Activate(mode)
    if self.Mode=="Edit" and self.PivotSetting then
        self:CommitFitPivot()
        return
    end
    -- The same equipped Build tool handles both placement and selection.
    -- Resolve against our local interaction context, not the Tool's legacy ID.
    mode=self.Mode
    if mode~="Build" and mode~="Edit" and mode~="Inspect" then return end
    if self.PendingMateChoice or (self.Numeric and self.Numeric.Active) then return end
    if mode=="Edit" and self.Assembly
        and self.Assembly:HandleEditClick() then return end
    if player:GetAttribute("OPENWORKS_Simulating") == true then
        self:Message("Stop simulation in Simulate (P) before editing")
        return
    end
    if self.DirectDragActive then return end
    if self.ScaleMode then
        -- Redundant native-Tool activation path: some Roblox input flows
        -- consume MouseButton1 before UserInputService.InputBegan sees it.
        if self.ScaleHandles then self.ScaleHandles:BeginDrag() end
        return
    end
    if self.CatalogOpen or (self.BankModal and self.BankModal.Visible)
        or self.Busy or os.clock() < (self.IgnoreClickUntil or 0) then return end

    if self.Layered and self.Layered:Click() then return end

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
    if not copy then
        -- Make the actual selected component fully shadowless while its
        -- cohesive ghost is displayed, restoring exact source settings on
        -- commit/cancel/mode switch. Preview clones also cast no shadows.
        self.MoveShadowStates={}
        for _,model in ipairs(self.SelectedParts) do
            if model and model.Parent then
                for _,part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        self.MoveShadowStates[part]=part.CastShadow
                        part.CastShadow=false
                    end
                end
            end
        end
    end
    self:RebuildPreview()
    if self.Layered then self.Layered:RefreshVisuals() end
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
    local axisName = string.upper(axis)
    local current = Grid.Rotation(self.Steps)
    local direction = RotationMath.Axis(axisName)
    if not direction then return end

    -- Quarter turns are in WORLD axes, rather than accumulating
    -- unintuitive Euler rotations around the component's local frame.
    local nextRotation = CFrame.fromAxisAngle(direction, math.pi/2) * current
    local nextSteps = RotationMath.MatchSteps(nextRotation)
    if not nextSteps then return end

    if self.Mode == "Edit" and not self.Pending
        and self.SelectedComponentId and #self.SelectedParts > 0 then
        local center = ComponentGeometry.Bounds(self.SelectedParts)
        local delta = center and RotationMath.Delta(axisName,1,center)
        if not delta then return end
        local stop=WorldMotion.AnimateTurn(
            self.SelectedParts,delta,WorldMotion.Profile.TurnSeconds)
        local ok = self:Request({
            action="RotateComponent",
            componentId=self.SelectedComponentId,
            axis=axisName,
            direction=1,
        })
        if not ok then stop() end
        if ok then self.Steps=nextSteps end
    elseif self.Mode == "Edit" and not self.Pending and self.Selected then
        local origin = self.Selected:GetPivot()
        local delta = RotationMath.Delta(axisName,1,origin.Position)
        local stop=WorldMotion.AnimateTurn(
            {self.Selected},delta,WorldMotion.Profile.TurnSeconds)
        local ok=self:Request({
            action="RotatePrimitiveWorld",
            instanceId=self.Selected:GetAttribute("InstanceId"),
            axis=axisName,
            direction=1,
        })
        if not ok then
            stop()
            self.Steps=attributesSteps(self.Selected)
        else
            self.Steps=nextSteps
        end
    else
        self.Steps=nextSteps
    end
    self:RefreshHUD()
end

-- Face drag scaling stays entirely within the native first-person
-- locked mouse. V shows the grips; aim the crosshair at one, then drag.
-- Direct numeric construction: arbitrary axis values in U at 0.01-U
-- precision, server-validated against the original primitive geometry.
-- Normal shaft grips stay length-only, but entering an exact diameter
-- remains possible in the panel if the shaft can physically fit its bore.
function Controller:OpenNumericSize()
    if self.CatalogOpen or self.PendingMateChoice
        or (self.Assembly and self.Assembly:IsEditingJoint()) then return end
    if not self.ScaleMode then self:BeginScale() end
    if not self.ScaleMode or not self.ScaleSize then return end
    if self.Numeric.Active then return end
    local id=if self.Mode=="Edit" and self.Selected then
        self.Selected:GetAttribute("TemplateId") else self.CurrentId
    local entry=id and Registry.Get(id)
    if not entry then return end
    local original=entry.Model.PrimaryPart.Size
    local sizeMode=entry.ResizeMode
    self.Numeric:Show(self.ScaleSize,sizeMode,function(newSize)
        if not Grid.ValidSize(original,newSize,sizeMode,true,true) then
            return false,"Invalid size for this primitive • 0.25–64 U"
        end
        local current=self.ScaleSize
        local cf=self.ScaleCF
        if not cf then return false,"Select a valid construction first" end
        if self.Mode=="Build" then
            self.NumericPrecision=true
            self:UpdateScalePreview(cf,newSize)
            self:EndScale()
            return true
        end
        if not self.Selected then return false,"Select a primitive first" end
        local ok=self:CommitScale(cf,newSize,cf,current)
        if not ok then return false,"Size rejected: check bore and collisions" end
        self:EndScale()
        return true
    end)
    self:Message("Enter exact X/Y/Z dimensions in U; press Enter to apply")
end

function Controller:BeginScale()
    if self.ScaleMode or self.CatalogOpen or self.Pending then return end

    -- Scale is a primitive operation, not a destructive component-wide scale.
    -- When V is pressed on a selected rigid component, enter its interior and
    -- choose the member under the crosshair (or the central member).
    if self.Mode == "Edit" and self.SelectedComponentId then
        local componentId = self.SelectedComponentId
        local target = self.GroupAnchor
        local hit = self:CastCenter(false)
        local built = workspace:FindFirstChild(Config.FolderName)
        local node = hit and hit.Instance
        while node and node.Parent ~= built do node = node.Parent end
        if node and node:IsA("Model")
            and node:GetAttribute("ComponentId") == componentId
            and node:GetAttribute("OwnerUserId") == player.UserId then
            target = node
        end
        if target then
            self.EditingComponentId = componentId
            self:SetSelection(target)
        end
    end

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
    player:SetAttribute("OPENWORKS_ScaleActive",true)
    self.ScaleCF=cf
    self.ScaleSize=self.CurrentSize
    self.ScaleVisualCF=cf
    self.ScaleVisualSize=self.CurrentSize
    -- Scale preview and neon grips share one visual-motion profile.
    -- The size and pivot sent to the server remain exact, unsmoothed.
    if self.Mode=="Build" and self.Preview and self.Preview.PrimaryPart then
        self.Preview.PrimaryPart.Size=self.CurrentSize
        self.Preview:PivotTo(cf)
    end

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
                part.Transparency = 0.65
                part.Color = BLUE
            end
        end
        ghost.Parent = workspace
        self.ScaleGhost = ghost
        if self.Feedback then
            self.Feedback:SetGhost(ghost,true)
            self.Feedback:Clear("selection")
            self.Feedback:Set("selection","resize",{ghost},"selection",false)
        end
        model.PrimaryPart.LocalTransparencyModifier = 1
    end

    local templateName = string.lower(tostring(id))
    local cylinder = string.find(templateName, "cylinder", 1, true)
        and not string.find(templateName, "halfcylinder", 1, true)
    local step = if cylinder then 0.25 else Grid.DefaultSizeStepU
    -- Once inside a hole, the fitted diameter is locked for ordinary
    -- resizing. Only the cylinder's X-axis end grips are offered.
    local aligned = self.Mode=="Edit" and cylinder
        and type(model:GetAttribute("AlignedOpeningId"))=="string"
    local mode=if aligned then "LengthOnly_1U" else entry.ResizeMode
    self.ScaleHandles:Open(
        cf, self.ScaleSize, mode, entry.Model.PrimaryPart.Size,
        step, model:GetAttribute("FitPrecision") == true,
        self.NumericPrecision==true
            or model:GetAttribute("NumericPrecision")==true
    )
    if self.Layered then self.Layered:RefreshVisuals() end
    self:RefreshPointer()
    self:RefreshHUD()
end

function Controller:UpdateScalePreview(cf, size)
    if not self.ScaleMode then return end

    self.ScaleCF = cf
    self.ScaleSize = size
    self.CurrentSize = size

    -- A cursor drag updates the EXACT target instantly. Only its visible
    -- geometry eases toward it; this is never used for collision or saving.
    local ghost=if self.Mode=="Edit" then self.ScaleGhost else self.Preview
    if ghost and not ghost.Parent then ghost.Parent=workspace end
    self:RefreshHUD()
end

function Controller:AdvanceScalePreview(dt)
    if not self.ScaleMode or not self.ScaleCF or not self.ScaleSize then
        return
    end
    local ghost=if self.Mode=="Edit" then self.ScaleGhost else self.Preview
    if not ghost or not ghost.PrimaryPart then return end
    -- Resize preview matches the actual handle values immediately. The
    -- selection box is re-evaluated from this precise size every frame.
    self.ScaleVisualCF=self.ScaleCF
    self.ScaleVisualSize=self.ScaleSize
    ghost.PrimaryPart.Size=self.ScaleSize
    ghost:PivotTo(self.ScaleVisualCF)
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
        resizePrecision = true,
        numericPrecision=self.Numeric and self.Numeric.Active,
    })
    if ok then
        self.CurrentSize = size
    else
        self.CurrentSize = oldSize
    end
    return ok
end

function Controller:EndScale()
    if self.Numeric and self.Numeric.Active then self.Numeric:Hide() end
    if not self.ScaleMode then return end

    -- Escape/V during an unfinished mouse drag cancels the tentative
    -- dimensions rather than leaving the HUD showing an uncommitted size.
    local drag = self.ScaleHandles and self.ScaleHandles.Drag
    if drag then
        self:UpdateScalePreview(drag.StartCF, drag.StartSize)
    end

    self.ScaleMode = false
    player:SetAttribute("OPENWORKS_ScaleActive",false)
    self.ScaleHandles:Close()

    if self.ScaleGhost then
        if self.Feedback then self.Feedback:SetGhost(nil,true) end
        self.ScaleGhost:Destroy()
        self.ScaleGhost = nil
    elseif self.Mode=="Build" and self.Preview and self.Preview.PrimaryPart
        and self.ScaleCF and self.ScaleSize then
        -- Complete the visual edit before returning to Build placement.
        -- Stale eased geometry must never be submitted to the server.
        self.Preview.PrimaryPart.Size=self.ScaleSize
        self.Preview:PivotTo(self.ScaleCF)
        self.PreviewCF=self.ScaleCF
        self.PreviewVisualPose=self.ScaleCF
        self.LastPreviewCheck=0
    end
    if self.Selected and self.Selected.PrimaryPart then
        self.Selected.PrimaryPart.LocalTransparencyModifier = 0
    end

    if self.Feedback then self:RefreshSelectionHighlights() end
    self.ScaleCF=nil
    self.ScaleSize=nil
    self.ScaleVisualCF=nil
    self.ScaleVisualSize=nil
    self.IgnoreClickUntil = os.clock() + 0.2
    if self.Layered then self.Layered:RefreshVisuals() end
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

-- Direct world-space pickup of any owned primitive or component.
-- A normal click still selects. Holding LMB and moving the camera or player
-- beyond a small world-space threshold starts the existing temporary G move.
function Controller:BeginDirectDrag()
    if self.PendingMateChoice
        or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
        or (self.Assembly and self.Assembly:IsEditingJoint())
        or self.Tools.PrimaryId ~= "Edit" or self.Tools.SubtoolId ~= "Edit"
        or self.Mode ~= "Edit" or self.Pending
        or self.ScaleMode or self.CatalogOpen then return end
    local hit = self:CastCenter(false)
    if not hit then return end
    local folder = workspace:FindFirstChild(Config.FolderName)
    local node = hit.Instance
    while node and node.Parent ~= folder do node = node.Parent end
    if not node or not node:IsA("Model")
        or node:GetAttribute("OwnerUserId") ~= player.UserId then return end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
    -- A first click just SELECTS. Only a second, deliberate hold on the
    -- already selected piece can become a move. Prevents accidental pickup
    -- when looking around during selection.
    local alreadySelected = if self.SelectedComponentId
        then node:GetAttribute("ComponentId") == self.SelectedComponentId
        else self.Selected == node
    if not alreadySelected then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    self.DirectDragCandidate = {
        Model = node,
        StartedAt = os.clock(),
        Camera = camera.CFrame,
    }
end

function Controller:UpdateDirectDrag()
    if self.PendingMateChoice then return end
    local held = self.DirectDragCandidate
    if not held or self.DirectDragActive then return end
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        self.DirectDragCandidate = nil
        return
    end
    if os.clock() - held.StartedAt < 0.16 then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local displacement = (camera.CFrame.Position - held.Camera.Position).Magnitude
    local angular = math.acos(math.clamp(
        camera.CFrame.LookVector:Dot(held.Camera.LookVector), -1, 1))
    if displacement < 0.20 and angular < math.rad(3) then return end

    if self.SelectedComponentId then
        if held.Model:GetAttribute("ComponentId") ~= self.SelectedComponentId then return end
    elseif self.Selected ~= held.Model then
        return
    end
    self.DirectDragActive = true
    self:StartMove(false)
    if not self.Pending then self.DirectDragActive = false end
end

function Controller:FinishDirectDrag()
    self.DirectDragCandidate = nil
    if not self.DirectDragActive then return end
    self.DirectDragActive = false
    if not self.PreviewValid or not self.PreviewCF then
        if not self.PreviewValid then
            self:Message(self.PreviewReason or "Red preview: placement blocked")
        end
        self:CancelPending()
    elseif self.Pending == "ComponentMove" then
        self:ConfirmComponentPlacement()
    elseif self.Pending == "Move" then
        self:ConfirmMove()
    end
end

-- Alt+Up/Down always moves on world Y. Alt+Left/Right follows the
-- camera's dominant horizontal right direction. Shift makes either
-- direction fine-grained. Server validates and commits atomically.
function Controller:CanNudge()
    local alt=UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
    return alt and self.Tools.PrimaryId=="Edit" and self.Mode=="Edit"
        and not self.Busy and not self.Pending and not self.ScaleMode
        and not self.CatalogOpen and not self.PendingMateChoice
        and player:GetAttribute("OPENWORKS_CursorUIOpen")~=true
        and player:GetAttribute("OPENWORKS_ExplorerOpen")~=true
        and player:GetAttribute("OPENWORKS_PropertiesOpen")~=true
        and player:GetAttribute("OPENWORKS_PlotMenuOpen")~=true
        and not self.PivotSetting and not self.DirectDragActive
        and not self.LockedAlignment
        and not (self.BankModal and self.BankModal.Visible)
        and not (self.Numeric and self.Numeric.Active)
        and not (self.MaterialPicker and self.MaterialPicker.Visible)
        and not (self.Layered and self.Layered.Alignment)
        and not (self.Assembly and self.Assembly:IsEditingJoint())
        and not UserInputService:GetFocusedTextBox()
        and player:GetAttribute("OPENWORKS_Simulating")~=true
        and (self.SelectedComponentId~=nil or self.Selected~=nil
            or #self.SelectedParts>1)
end

-- Alt+Up/Down moves on world Y; Alt+Left/Right tracks camera horizontal.
-- Shift provides fine increments; server owns collision and history.
function Controller:VerticalNudge(key)
    if not self:CanNudge() then return false end
    local axis,direction
    if key==Enum.KeyCode.Up or key==Enum.KeyCode.Down then
        -- Height never depends on camera orientation, even without Shift.
        axis,direction="Y",(if key==Enum.KeyCode.Up then 1 else -1)
    else
        local camera=workspace.CurrentCamera
        if not camera then return false end
        local v=camera.CFrame.RightVector
        if math.abs(v.X)>=math.abs(v.Z) then
            axis,direction="X",(if v.X>=0 then 1 else -1)
        else
            axis,direction="Z",(if v.Z>=0 then 1 else -1)
        end
        if key==Enum.KeyCode.Left then direction=-direction end
    end
    local scope,id,ids
    local selected=self.SelectedParts
    if self.SelectedComponentId then
        scope,id="Component",self.SelectedComponentId
    elseif #selected>1 then
        -- Shift-selected independent primitives are moved together, without
        -- silently grouping them or moving any unselected construction.
        scope,ids="Primitives",{}
        for _,model in ipairs(selected) do
            if not model or not model.Parent or model:GetAttribute("ComponentId") then
                self:Message("Multi-nudge only supports independent primitives")
                return false
            end
            table.insert(ids,model:GetAttribute("InstanceId"))
        end
    elseif self.Selected then
        -- Deep-selected members keep their ComponentId, but move alone.
        scope,id="Primitive",self.Selected:GetAttribute("InstanceId")
    end
    if not scope or (scope~="Primitives" and not id) then
        self:Message("Select a primitive or component to nudge")
        return false
    end
    local fine=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    local affected=if scope=="Component" or scope=="Primitives"
        then selected else {self.Selected}
    local amount=(if fine then 0.05 else 0.25)*direction
    local displacement=if axis=="X" then Vector3.new(amount,0,0)
        elseif axis=="Y" then Vector3.new(0,amount,0)
        else Vector3.new(0,0,amount)
    local stop=WorldMotion.AnimateMove(affected,displacement)
    local succeeded=self:Request({
        action="VerticalMove",scope=scope,id=id,ids=ids,
        axis=axis,direction=direction,fine=fine,
    })
    if not succeeded then stop() end
    self:RefreshHUD()
    return true
end

function Controller:OnInput(input, processed)
    if self.Tools:WasConsumed(input) then return end
    if self.BankModal and self.BankModal.Visible then return end
    if player:GetAttribute("OPENWORKS_ExplorerOpen")==true then return end
    if self.PendingMateChoice then return end
    if self.Numeric and self.Numeric.Active then
        if input.KeyCode==Enum.KeyCode.Escape then
            self.Numeric:Hide()
            self:EndScale()
        end
        return
    end
    if player:GetAttribute("OPENWORKS_Simulating") == true then return end
    local key = input.KeyCode
    if UserInputService:GetFocusedTextBox() then return end
    if self.Assembly and self.Assembly:IsEditingJoint() then return end
    local shiftHeld=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    if self.PivotSetting then
        if not processed and self.Mode=="Edit" and shiftHeld
            and key==Enum.KeyCode.O then
            self:EditFitPivot(true)
        elseif key==Enum.KeyCode.Return or key==Enum.KeyCode.KeypadEnter then
            self.PivotSetting=false
            self:RefreshHUD()
        elseif not processed and (key==Enum.KeyCode.Q or key==Enum.KeyCode.E) then
            local delta=if key==Enum.KeyCode.E then 1 else -1
            self.PivotModeIndex=(self.PivotModeIndex-1+delta
                +#FitPivotSnap.Modes)%#FitPivotSnap.Modes+1
            self:RefreshHUD()
        end
        return
    end
    if self.Mode=="Edit" and not processed and key==Enum.KeyCode.O
        and not self.Pending and not self.ScaleMode then
        self:EditFitPivot(shiftHeld)
        return
    end
    if self.Mode=="Edit" and shiftHeld
        and (key==Enum.KeyCode.Delete or key==Enum.KeyCode.Backspace) then
        -- Shift+Delete removes only the aimed relationship, handled by
        -- the integrated mechanical editor, never primitive geometry.
        return
    end
    if not processed and self.SmartMatch and not self.LockedAlignment
        and (self.Mode=="Build" or self.Pending)
        and key==Enum.KeyCode.Tab then
        local reverse=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        if self:CycleSmartTarget(reverse) then return end
    end
    if not processed and self.LockedAlignment
        and self.SmartMatch and self.SmartMatch.kind=="Bore"
        and (key==Enum.KeyCode.Q or key==Enum.KeyCode.E) then
        self.SmartRollDelta=math.clamp(
            self.SmartRollDelta+(if key==Enum.KeyCode.E then 5 else -5),
            -360,360)
        self.LastPreviewCheck=0
        return
    end
    if self.LockedAlignment and key~=Enum.KeyCode.Escape then
        -- During the positioning stage, only wheel/Q/E, zoom and click
        -- can affect the fit. Don't mutate the component or open sizing.
        return
    end
    if self.Mode ~= "Build" and self.Mode ~= "Edit"
        and self.Mode ~= "Inspect" then return end

    if self.Layered and self.Layered:OnInput(input, processed) then return end

    if key==Enum.KeyCode.Return or key==Enum.KeyCode.KeypadEnter then
        if self.LockedAlignment then
            self:ClearSmartMatch()
            self.LastPreviewCheck=0
        elseif self.ScaleMode then
            self:EndScale()
        elseif self.CatalogOpen then
            self:ShowCatalog(false)
        elseif self.Pending then
            self:CancelPending()
        elseif self.Mode=="Build" then
            self:StopPlacement()
        end
        self:RefreshHUD()
        return
    end
    if key == Enum.KeyCode.Escape then
        if self.LockedAlignment then
            self:ClearSmartMatch()
            self.LastPreviewCheck=0
            self:RefreshHUD()
            return
        end
        if self.CatalogOpen then
            self:ShowCatalog(false)
            return -- Close the library without ending an active placement.
        end
        if self.ScaleMode then
            self:EndScale()
            return
        end
        if self.Pending then
            self:CancelPending()
            self:RefreshHUD()
        elseif self.Mode=="Build" then
            self:StopPlacement()
        end
        return
    end
    if key==Enum.KeyCode.M and self.Mode=="Edit" and not processed then
        if self.UnifiedExplorer then
            self.UnifiedExplorer:OpenSelectedContext()
        end
        return
    end
    if key == Enum.KeyCode.V and not processed then
        if self.ScaleMode then self:EndScale() else self:BeginScale() end
        return
    end
    if key==Enum.KeyCode.N and not processed
        and (self.Mode=="Edit" or self.Mode=="Build") then
        self:OpenNumericSize()
        return
    end
    if self.ScaleMode or self.Mode == "Inspect" then return end
    if processed then return end

    local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if ctrl then
        if key == Enum.KeyCode.Z then self:History(false) end
        if key == Enum.KeyCode.Y then self:History(true) end
        if key == Enum.KeyCode.D and self.Mode == "Edit" then self:StartMove(true) end
        return
    end

    -- High-priority ContextActionService capture owns Alt+arrow nudging.
    -- Ordinary Roblox arrows still pass through without Build selection.

    if key==Enum.KeyCode.B and shiftHeld and self.Tools.PrimaryId=="Edit" then
        self:OpenBankSave()
        return
    end
    if key == Enum.KeyCode.B and self.Mode=="Build" then
        self:ShowCatalog(not self.CatalogOpen)
        return
    end
    if self.CatalogOpen then return end

    if self.Mode=="Edit" and key==Enum.KeyCode.C and shiftHeld then
        -- Shift+C is exclusively the hand-crank coupling workflow.
        return
    end
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
    table.insert(self.Connections,Theme.Attach(self.Gui))
    self.Layered = LayeredEditingController.new(self)
    self.Layered:Start()

    table.insert(self.Connections, self.Tools.Changed.Event:Connect(function(mode)
        self:OnModeChanged(mode)
    end))
    table.insert(self.Connections, self.Tools.SubtoolChanged.Event:Connect(
        function(primary,subtool,previous)
            self:OnSubtoolChanged(primary,subtool,previous)
        end))
    table.insert(self.Connections, player:GetAttributeChangedSignal(
        "OPENWORKS_Simulating"):Connect(function()
            self:OnModeChanged(self.Tools.ActiveId)
        end))
    table.insert(self.Connections, self.Tools.Activated.Event:Connect(function(_mode)
        if self.Tools.PrimaryId=="Build" or self.Tools.PrimaryId=="Edit" then
            self:Activate(self.Mode)
        end
    end))
    -- Capture Alt+arrows before Roblox's camera consumes them, but return
    -- immediately: all server validation runs in a spawned request.
    ContextActionService:BindActionAtPriority(
        "OPENWORKS_BuildNudge",
        function(_,state,input)
            local key=input.KeyCode
            if state==Enum.UserInputState.End
                or state==Enum.UserInputState.Cancel then
                if self.VerticalHeld==key then self.VerticalHeld=nil end
                return Enum.ContextActionResult.Pass
            end
            if state~=Enum.UserInputState.Begin then
                return Enum.ContextActionResult.Pass
            end
            if self:CanNudge() then
                self.VerticalHeld=key
                self.VerticalElapsed=0
                task.spawn(function() self:VerticalNudge(key) end)
                return Enum.ContextActionResult.Sink
            end
            return Enum.ContextActionResult.Pass
        end,
        false,
        Enum.ContextActionPriority.High.Value+150,
        Enum.KeyCode.Up,Enum.KeyCode.Down,
        Enum.KeyCode.Left,Enum.KeyCode.Right
    )
    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:BeginDirectDrag()
        end
        self:OnInput(input, processed)
    end))
    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:FinishDirectDrag()
        elseif input.KeyCode==self.VerticalHeld then
            self.VerticalHeld=nil
        end
    end))
    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseWheel
            and not self.PendingMateChoice then
            if self.SmartMatch
                and ((self.SmartMatch.kind=="Bore" and self.LockedAlignment)
                    or self.SmartMatch.kind=="Hub")
                and (self.Mode=="Build" or self.Pending) then
                self.SmartOffsetDeltaU=math.clamp(
                    self.SmartOffsetDeltaU+
                        (if input.Position.Z>0 then 0.5 else -0.5),
                    -64,64)
                self.LastPreviewCheck=0
            elseif self.Layered then
                self.Layered:AdjustOffset(input.Position.Z)
            end
        end
    end))
    RunService:BindToRenderStep("OPENWORKS_CursorUnlock",
        Enum.RenderPriority.Camera.Value + 2, function()
            local fitWheel=not self.PendingMateChoice
                and self.SmartMatch~=nil
                and (self.SmartMatch.kind=="Hub"
                    or (self.SmartMatch.kind=="Bore"
                        and self.LockedAlignment~=nil))
                and (self.Mode=="Build" or self.Pending~=nil)
            if player:GetAttribute("OPENWORKS_FitWheelActive")~=fitWheel then
                player:SetAttribute("OPENWORKS_FitWheelActive",fitWheel)
            end
            local open=self.CatalogOpen or (self.BankModal and self.BankModal.Visible)
                or self.PendingMateChoice~=nil
                or (self.Numeric and self.Numeric.Active)

            if player:GetAttribute("OPENWORKS_CursorUIOpen")~=open then
                player:SetAttribute("OPENWORKS_CursorUIOpen",open)
            end
            if player:GetAttribute("OPENWORKS_CrankActive")==true then
                UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter
                UserInputService.MouseIconEnabled=false
            elseif player:GetAttribute("OPENWORKS_PropertiesLooking")==true then
                UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter
                UserInputService.MouseIconEnabled=false
            elseif player:GetAttribute("OPENWORKS_PlotMenuOpen")==true
                or player:GetAttribute("OPENWORKS_AssemblyNaming")==true
                or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
                or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
                or (self.Numeric and self.Numeric.Active)
                or self.PendingMateChoice or (self.BankModal and self.BankModal.Visible) then
                UserInputService.MouseBehavior=Enum.MouseBehavior.Default
                UserInputService.MouseIconEnabled=true
            elseif self.CatalogOpen then
                -- Native first-person camera can re-lock the cursor per-frame.
                -- Keep the catalog interactive without modifying the toolbar.
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                UserInputService.MouseIconEnabled = true
            elseif self.ScaleMode then
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                UserInputService.MouseIconEnabled = false
            else
                UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter
                UserInputService.MouseIconEnabled=false
            end
        end)

    -- Repeat while held, but never issue a flood of RemoteFunction calls.
    -- The initial key press nudges once; hold repeats after a small delay.
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        local key=self.VerticalHeld
        if not key then return end
        if self.Mode~="Edit" or self.Pending or self.ScaleMode
            or UserInputService:GetFocusedTextBox()
            or not (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt))
            or not UserInputService:IsKeyDown(key) then
            self.VerticalHeld=nil
            return
        end
        self.VerticalElapsed+=dt
        if self.VerticalElapsed<0.24 then return end
        self.VerticalElapsed=0.09
        task.spawn(function()
            self:VerticalNudge(key)
        end)
    end))

    table.insert(self.Connections,RunService.RenderStepped:Connect(function(dt)
        self:AdvanceScalePreview(dt)
        -- Suppress the original selection box during a moving ghost.
        local previewing=self.Pending~=nil or (self.Layered
            and self.Layered.Alignment
            and self.Layered.Alignment.Stage=="Preview")
        -- Bounds() walks every descendant of each selected primitive.
        -- Selection geometry is stationary outside an explicit transform;
        -- recalculate at 10 Hz, but hide instantly when a ghost begins.
        if self.Feedback then
            if previewing then self.Feedback:Clear("selection")
            elseif self.LastPreviewing then self:RefreshSelectionHighlights() end
        end
        self.LastPreviewing=previewing
        -- Replicated deletion, undo/redo or plot reload may destroy selected
        -- models without calling SetSelection. Never leave orphan outlines.
        local stale=false
        for _,part in ipairs(self.SelectedParts) do
            if not part or not part.Parent then stale=true break end
        end
        if stale then self:SetSelection(nil) end
        self:UpdateDirectDrag()
        self:UpdateHover()
        if self.FitPivotHandle then
            local anchor=if self.SelectedComponentId then self.GroupAnchor
                else self.Selected
            if self.PivotSetting then
                local _,point=self:PivotHit()
                if point then
                    self.FitPivotHandle:UpdateCandidate(anchor,point,
                        if self.SelectedComponentId then "Component" else "Primitive")
                else
                    self.FitPivotHandle:Update(anchor,
                        if self.SelectedComponentId then "Component" else "Primitive",true)
                end
            elseif self.Pending and self.Preview then
                self.FitPivotHandle:UpdatePreview(self.Preview)
            else
                self.FitPivotHandle:Update(anchor,
                    if self.SelectedComponentId then "Component" else "Primitive",
                    self.Mode=="Edit" and not self.ScaleMode
                        and anchor~=nil
                        and (if self.SelectedComponentId
                            then FitOrigin.HasComponent(anchor)
                            else FitOrigin.HasPrimitive(anchor)))
            end
        end
        if not self.PendingMateChoice
            and (self.Mode == "Build" or
                (self.Mode == "Edit" and self.Pending)) then
            self:UpdatePreview()
        end
        if self.StatusMessage and os.clock() >= self.MessageUntil then
            self.StatusMessage = nil
            self:RefreshHUD()
        end
    end))

    self:OnModeChanged(self.Tools.ActiveId)
    self:OnSubtoolChanged(self.Tools.PrimaryId,self.Tools.SubtoolId,nil)
    print("[OPENWORKS] Build (1) places; Edit (2) reshapes, fits and paints")
end

function Controller:Destroy()
    if self.FitPivotHandle then self.FitPivotHandle:Destroy() end
    if self.Numeric then self.Numeric:Destroy() end
    self:EndScale()
    if self.Layered then self.Layered:Destroy() end
    RunService:UnbindFromRenderStep("OPENWORKS_CursorUnlock")
    ContextActionService:UnbindAction("OPENWORKS_BuildNudge")
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
