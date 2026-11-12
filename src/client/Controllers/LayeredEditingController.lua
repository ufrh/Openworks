--!strict
-- Phase 04: first-person depth picking, non-destructive X-ray/isolate,
-- and guided coaxial insertion previews. No mechanical constraints here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Config = require(construction:WaitForChild("BuildConfig"))
local Grid = require(construction:WaitForChild("GridMath"))
local AlignmentMath = require(construction:WaitForChild("AlignmentMath"))
local Bore = require(construction:WaitForChild("BoreClearance"))
local MultiFit = require(construction:WaitForChild("MultiFitMath"))
local PreviewFeedback = require(construction:WaitForChild("PreviewFeedback"))
local WorldMotion = require(script.Parent:WaitForChild("WorldMotion"))
local INSERTION_INCREMENT_U = 0.5

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
        LastClickedModel = nil,
        LastClickAt = 0,
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
    local selected = self:SelectedSet()

    for _, model in ipairs(folder:GetChildren()) do
        if owned(model) and not (exclude and exclude[model]) then
            local visible = not self.Isolated or selected[model]
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
    local layers=self:DepthModels(nil)
    if #layers==0 then
        self.LastClickedModel=nil
        self:Select(nil)
        return
    end
    local alt=game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftAlt)
        or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.RightAlt)
    local choice=layers[1]
    if alt then
        -- Alt+click still cycles through physical depth layers.
        local current=self.Parent.Selected or self.Parent.GroupAnchor
        local index=table.find(layers,current) or 0
        self.DepthIndex=index%#layers
        choice=layers[self.DepthIndex+1]
        self.LastClickedModel=nil
        self:Select(choice)
        self.Parent:Message("Selected layer "..(self.DepthIndex+1)
            .."/"..#layers)
        return
    end

    local now=os.clock()
    local id=choice:GetAttribute("ComponentId")
    local doubleClick=type(id)=="string"
        and self.LastClickedModel==choice
        and now-self.LastClickAt<=0.34
    self.DepthIndex=0
    if doubleClick then
        -- Single click selects the rigid component; a second deliberate
        -- click selects its actual primitive, with all group metadata intact.
        self.LastClickedModel=nil
        self.LastClickAt=0
        self.Parent.DirectDragCandidate=nil
        self.Parent.EditingComponentId=id
        self:Select(choice)
        self.Parent:Message("Editing a member of the component • E exits")
    else
        self.LastClickedModel=choice
        self.LastClickAt=now
        self:Select(choice)
    end
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

-- Raycasts miss the EMPTY center of a drilled opening. The centerline
-- fallback targets the nearest owned bore within a small aim radius,
-- even when the ray passes through a hinge lug into the background.
function Layered:AimedOpening(excluded)
    local folder=self:Built()
    local camera=workspace.CurrentCamera
    if not folder or not camera then return nil end
    local origin=camera.CFrame.Position
    local direction=camera.CFrame.LookVector.Unit
    local best,bestAlong=nil,math.huge
    for _,model in ipairs(folder:GetChildren()) do
        if not owned(model) or (excluded and excluded[model])
            or not AlignmentMath.TargetAxis(model) then continue end
        local diameter=Bore.OpeningDiameter(model)
        if not diameter then continue end
        local delta=model:GetPivot().Position-origin
        local along=delta:Dot(direction)
        if along<=0 or along>Grid.MaxDistance then continue end
        local distance=(delta-direction*along).Magnitude
        local radius=math.clamp(diameter*0.5+0.075,0.12,0.32)
        if distance<=radius and along<bestAlong then
            best,bestAlong=model,along
        end
    end
    return best
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
    if not target or not AlignmentMath.TargetAxis(target) then
        target=self:AimedOpening(excluded) or target
    end
    if target == self.HoveredCandidate then return end

    self.HoveredCandidate = target
    if self.TargetHighlight then self.TargetHighlight:Destroy() end
    self.TargetHighlight = nil
    if target then
        local highlight = Instance.new("Highlight")
        highlight.Adornee = target
        highlight.FillTransparency = 0.83
        highlight.OutlineTransparency = 1
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
            item.Transparency = if item:GetAttribute("GearPivotOnly")==true
                then 1 else 0.48
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
        align.Members, align.Shaft, align.Target, align.OffsetUnits,
        align.RollDegrees
    )
    if not plan then
        self.Parent:Message(tostring(reason))
        return
    end

    align.Plan = plan
    if align.Preview then
        local visual = align.VisualPose or align.Preview:GetPivot()
        local goal = plan.delta * align.StartGhostPivot
        align.Preview:PivotTo(goal)
        local ignore = {}
        for _, member in ipairs(align.Members) do ignore[member] = true end
        local all={}
        local folder=self:Built()
        if folder then
            for _,candidate in ipairs(folder:GetChildren()) do
                if owned(candidate) and not ignore[candidate] then
                    table.insert(all,candidate)
                end
            end
        end
        local moving={}
        for _,candidate in ipairs(align.Preview:GetChildren()) do
            if candidate:IsA("Model") then table.insert(moving,candidate) end
        end
        local targets=MultiFit.StationarySet(
            moving,align.Target,all,nil,ignore)
        local contacts,why=MultiFit.Find(moving,targets)
        local fitted=contacts and MultiFit.Unique(contacts,
            align.Shaft:GetAttribute("InstanceId"),
            align.Target:GetAttribute("InstanceId")) or {}
        align.FittedCount=#fitted
        local primary=MultiFit.Contains(fitted,
            align.Shaft:GetAttribute("InstanceId"),
            align.Target:GetAttribute("InstanceId"))
        local complete,reason=MultiFit.Completeness(
            moving,targets,fitted,false)
        if not primary then
            align.Valid=false
            align.ConflictReason=why
                or "Shaft is not coaxial, too short, or too wide for the opening"
        elseif not complete then
            align.Valid=false
            align.ConflictReason=reason
        else
            align.Valid,align.ConflictReason=PreviewFeedback.Check(
                align.Preview,ignore,nil,nil,MultiFit.AllowMap(fitted))
        end
        PreviewFeedback.Paint(align.Preview, align.Valid)
        align.TargetPose = goal
        align.VisualPose = visual
        align.Preview:PivotTo(visual)
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
        RollDegrees = 0,
        LastRollSend = 0,
        LastPreviewTime = 0,
    }
    self.TargetDepthIndex = 0
    self.HoveredCandidate = nil
    self.LastHoverRefresh = 0
    self:RefreshVisuals()
    parent:Message("Aim at a tube, drilled opening or gear bore, then click")
end

function Layered:ChooseTarget()
    local align = self.Alignment
    if not align or align.Stage ~= "PickTarget" then return end

    local excluded = {}
    for _, member in ipairs(align.Members) do excluded[member] = true end
    local layers = self:DepthModels(excluded)
    local target = layers[(self.TargetDepthIndex % math.max(1, #layers)) + 1]
    if not target or not AlignmentMath.TargetAxis(target) then
        target=self:AimedOpening(excluded) or target
    end

    if not target then
        self.Parent:Message("Aim at a constructed opening")
        return
    end
    if not AlignmentMath.TargetAxis(target) then
        self.Parent:Message("Choose a tube, DrilledBlock or gear center opening")
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
    align.RollDegrees = 0
    player:SetAttribute("OPENWORKS_Inserting", true)
    self:CreatePreview()
    self.Parent:Message("Scroll to adjust insertion depth, click to confirm")
end

function Layered:AdjustOffset(wheel)
    local align = self.Alignment
    if not align or (align.Stage ~= "Preview" and align.Stage ~= "Fit") then
        return false
    end
    local amount = if wheel > 0 then 1 elseif wheel < 0 then -1 else 0
    if amount == 0 then return true end

    local alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
    local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    if shift then
        self:AdjustRoll(amount * 5)
        return true
    end
    if align.Stage == "Fit" and alt then
        self:AdjustInsertion(amount * INSERTION_INCREMENT_U)
        return true
    end

    if align.Stage == "Fit" then
        self.Parent:Request({
            action = "FitShaft",
            sourceId = align.Shaft:GetAttribute("InstanceId"),
            targetId = align.Target:GetAttribute("InstanceId"),
            step = amount,
        })
        return true
    end

    align.OffsetUnits = math.clamp(
        align.OffsetUnits + amount * INSERTION_INCREMENT_U,
        -AlignmentMath.MaxOffsetUnits,
        AlignmentMath.MaxOffsetUnits
    )
    self:UpdateAlignPreview()
    self.Parent:Message("Insertion offset: " .. tostring(align.OffsetUnits) .. " U")
    return true
end

function Layered:CommitPose(nextOffset,nextRoll)
    local align=self.Alignment
    if not align or not align.Target then return end
    local stop=WorldMotion.AnimateShaftPose(align.Members,align.Shaft,
        align.Target,nextOffset,nextRoll)
    local ok=self.Parent:Request({
        action="PoseShaft",
        sourceId=align.Shaft:GetAttribute("InstanceId"),
        targetId=align.Target:GetAttribute("InstanceId"),
        offsetUnits=nextOffset,
        rollDegrees=nextRoll,
    })
    if ok then
        align.OffsetUnits=nextOffset
        align.RollDegrees=nextRoll
        self.Parent:RefreshHUD()
    else
        stop()
    end
end

function Layered:AdjustInsertion(delta)
    local align=self.Alignment
    if not align then return end
    local offset=math.clamp(align.OffsetUnits+delta,
        -AlignmentMath.MaxOffsetUnits,AlignmentMath.MaxOffsetUnits)
    if align.Stage=="Fit" then
        self:CommitPose(offset,align.RollDegrees)
    elseif align.Stage=="Preview" then
        align.OffsetUnits=offset
        self:UpdateAlignPreview()
    end
end

function Layered:AdjustRoll(deltaDegrees)
    local align=self.Alignment
    if not align or (align.Stage~="Preview" and align.Stage~="Fit") then return end
    local degrees=math.clamp(math.round(align.RollDegrees+deltaDegrees),-360,360)
    if degrees==align.RollDegrees then return end
    if align.Stage=="Fit" then
        self:CommitPose(align.OffsetUnits,degrees)
    else
        align.RollDegrees=degrees
        self:UpdateAlignPreview()
    end
end

function Layered:ConfirmAlignment()
    local align=self.Alignment
    local parent=self.Parent
    if not align or align.Stage~="Preview" or parent.PendingMateChoice then return end
    if align.Valid==false then
        parent:Message(align.ConflictReason or "Red preview: solid interference")
        return
    end

    -- Manual shaft/hole alignment keeps its joint picker. Gear bores are
    -- different: they ALWAYS weld to the shaft without extra prompts.
    local selected=align
    local sourceId=align.Shaft:GetAttribute("InstanceId")
    local targetId=align.Target:GetAttribute("InstanceId")
    local componentId=align.ComponentId
    local offset=align.OffsetUnits
    local roll=align.RollDegrees
    local isGear=type(align.Target:GetAttribute("GearTeeth"))=="number"
    parent.PendingMateChoice="ManualAlign"
    local function applyChoice(choice)
        parent.PendingMateChoice=nil
        parent.IgnoreClickUntil=os.clock()+0.22
        if self.Alignment~=selected or selected.Stage~="Preview" then
            parent:RefreshPointer()
            return
        end
        -- Adjust (or dismiss the picker) returns to the live positioning
        -- preview; the user can scroll depth/roll then click to choose again.
        if not choice or choice=="__Adjust" then
            parent:RefreshPointer()
            parent:RefreshHUD()
            return
        end
        -- Gear hubs create the same validated Weld as ordinary drag fitting.
        local approach=selected.Target:GetPivot().Position
            +selected.Target:GetPivot().RightVector*offset*Grid.Unit
        -- All manual shaft/bores now go through the same atomic,
        -- server-verified multi-opening transaction as drag fitting.
        -- The old CreateRelation/Align path moved only one shaft/hole.
        local exact=selected.Plan.delta*selected.Shaft:GetPivot()
        local ok=parent:Request(if isGear then {
            action="SmartMate",
            mateKind="Hub",
            relationKind=choice,
            sourceId=sourceId,
            targetId=targetId,
            approach=approach,
        } else {
            action="SmartMate",
            mateKind="Bore",
            relationKind=choice,
            sourceId=sourceId,
            targetId=targetId,
            offsetUnits=offset,
            rollDegrees=roll,
            position=exact.Position,
            orientation=exact.Rotation,
        })
        if ok then
            if selected.Preview then selected.Preview:Destroy() end
            selected.Preview=nil
            selected.Stage="Fit"
            self:RefreshVisuals()
            player:SetAttribute("OPENWORKS_Inserting",true)
            parent:Message("Aligned • scroll to fine-fit shaft • click/Enter to finish")
        end
        parent:RefreshPointer()
        parent:RefreshHUD()
    end
    if isGear then
        applyChoice("Weld")
    else
        parent.MateChoice:Show(applyChoice,selected.FittedCount or 1,false)
    end
end

function Layered:Click()
    local align = self.Alignment
    if align then
        if align.Stage == "PickTarget" then self:ChooseTarget()
        elseif align.Stage == "Preview" then self:ConfirmAlignment()
        elseif align.Stage == "Fit" then
            self:CancelAlignment()
            self.Parent:RefreshHUD()
        end
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
    if key == Enum.KeyCode.Return and self.Alignment then
        self:CancelAlignment()
        parent:RefreshHUD()
        return true
    end
    if processed then return false end

    if self.Alignment and (self.Alignment.Stage == "Preview"
        or self.Alignment.Stage == "Fit") then
        if key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.Minus then
            self:AdjustOffset(-1)
        elseif key == Enum.KeyCode.RightBracket or key == Enum.KeyCode.Equals then
            self:AdjustOffset(1)
        elseif key == Enum.KeyCode.Q then
            self:AdjustRoll(-5)
        elseif key == Enum.KeyCode.E then
            self:AdjustRoll(5)
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
    elseif key == Enum.KeyCode.L and parent.Mode == "Edit" then
        if self.Alignment then self:CancelAlignment() else self:StartAlignment() end
        return true
    end
    -- Selecting an opening is an exclusive mode; block Edit keyboard
    -- transforms until alignment is finished or cancelled.
    return self.Alignment ~= nil
end

function Layered:Start()
    -- Roblox's stock leaderboard also consumes Tab. Capture it in the
    -- construction tools before the default player-list shortcut.
    ContextActionService:BindActionAtPriority(
        "OPENWORKS_DepthSelect",
        function(_, inputState)
            local mode = self.Parent.Mode
            if mode ~= "Edit" and mode ~= "Inspect" then
                return Enum.ContextActionResult.Pass
            end
            if inputState == Enum.UserInputState.Begin
                and not UserInputService:GetFocusedTextBox() then
                local reverse = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
                self:CycleDepth(reverse)
            end
            return Enum.ContextActionResult.Sink
        end,
        false,
        3000,
        Enum.KeyCode.Tab
    )

    table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
        self:RefreshTargetCue()
        local align=self.Alignment
        if align and align.Stage=="Preview"
            and align.Preview and align.TargetPose then
            align.VisualPose=WorldMotion.Step(
                align.VisualPose,align.TargetPose,dt,
                WorldMotion.Profile.Placement)
            align.Preview:PivotTo(align.VisualPose)
        end
        if align and (align.Stage=="Preview" or align.Stage=="Fit") then
            local turn=if UserInputService:IsKeyDown(Enum.KeyCode.Q) then -1
                elseif UserInputService:IsKeyDown(Enum.KeyCode.E) then 1 else 0
            if turn~=0 then
                local now=os.clock()
                if align.Stage=="Preview" then
                    align.RotationAccumulator=(align.RotationAccumulator or 0)+dt*95*turn
                    local step=(if align.RotationAccumulator>=0 then math.floor(align.RotationAccumulator) else math.ceil(align.RotationAccumulator))
                    if step~=0 then
                        align.RotationAccumulator-=step
                        self:AdjustRoll(step)
                    end
                elseif now-(align.LastRollSend or 0)>0.11 then
                    align.LastRollSend=now
                    self:AdjustRoll(turn*5)
                end
            end
        end
    end))
end

function Layered:Destroy()
    ContextActionService:UnbindAction("OPENWORKS_DepthSelect")
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    self:CancelAlignment()
    self:ClearVisuals()
end

return Layered
