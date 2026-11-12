--!strict
-- Combined Edit mechanical-relationship authoring and Simulate UX bridge.
-- The dedicated AssemblyToolController owns named membership separately.
-- Rename/split the older combined controller only after in-Studio coverage
-- exists for its mechanical and simulation state transitions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CameraAimRay=require(script.Parent:WaitForChild("CameraAimRay"))

local player = Players.LocalPlayer
local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Config = require(construction:WaitForChild("BuildConfig"))
local Grid = require(construction:WaitForChild("GridMath"))
local Alignment = require(construction:WaitForChild("AlignmentMath"))
local PreviewFeedback = require(construction:WaitForChild("PreviewFeedback"))
local WorldMotion = require(script.Parent:WaitForChild("WorldMotion"))
local RelationshipProperties=require(script.Parent:WaitForChild("RelationshipProperties"))
local HandCrankController=require(script.Parent:WaitForChild("HandCrankController"))
local RackControlController=require(script.Parent:WaitForChild("RackControlController"))
local MotorControlController=require(script.Parent:WaitForChild("MotorControlController"))
local HandCrankMath=require(construction:WaitForChild("HandCrankMath"))
local Theme=require(script.Parent:WaitForChild("StudioTheme"))
local INSERTION_STEP_U = 0.5

-- No implicit Fixed joint. Rigid fabrication requires explicit Weld.
local TYPES = { "Cylindrical", "Slider", "Bearing" }
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
    panel.Name="AssemblyPanel"
    panel.Size = UDim2.fromOffset(380, 116)
    panel.Position = UDim2.new(1, -396, 0, 20)
    panel.BackgroundColor3 = Theme.Window
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.Parent = gui
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0, Theme.Radius)
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

    return gui, panel, label(7, 26, 15, Color3.fromRGB(234, 242, 249)),
        label(37, 31, 14, Color3.fromRGB(181, 214, 230)),
        label(72, 39, 12, Color3.fromRGB(169, 191, 204))
end

function Controller.new(tools)
    return setmetatable({
        Tools = tools,
        Active = false,
        Mode = nil,
        WeldFirst = nil,
        ManualActive = false,
        Stage = "Housing",
        KindIndex = 1,
        Housing = nil,
        Source = nil,
        Members = {},
        OffsetUnits = 0,
        RollDegrees = 0,
        GearFirst = nil,
        PairFirst = nil,
        PairKind = nil,
        Joint = nil,
        LastRollSend = 0,
        PreviewModel = nil,
        PreviewValid = true,
        LastMessage = nil,
        MessageUntil = 0,
        Connections = {},
        Busy = false,
    }, Controller)
end

function Controller:Kind()
    return TYPES[self.KindIndex]
end

function Controller:IsSimulating()
    return player:GetAttribute("OPENWORKS_Simulating") == true
end

function Controller:ToggleSimulation()
    if self.Busy then return end

    if self:IsSimulating() then
        if self:Request({ action = "StopSimulation" }) then self:Reset() end
        return
    end

    local seed = self:Pick()
    if not seed then
        self:Message("Aim at a registered assembly member, then press P")
        return
    end
    local id = seed:GetAttribute("InstanceId")
    if type(id) ~= "string" then
        self:Message("Select a constructed body you own")
        return
    end

    local assemblyId=seed:GetAttribute("AssemblyId")
    if type(assemblyId)~="string" or assemblyId=="" then
        self:Message("Create an assembly in the Assembly tool: N, name, select, Enter")
        return
    end

    -- Simulate the entire registered assembly, never an arbitrary connected
    -- mechanism selected via a seed. The server independently enforces
    -- membership and rejects incomplete connected registrations.
    self.SimAssemblyName=seed:GetAttribute("AssemblyName") or "Assembly"
    self:Reset()
    -- Simulation starts ungrounded regardless of Shift. Grounding
    -- is explicitly authored on supports when needed, not a camera mode.
    self.SimSeedId = id
    self:Request({ action = "StartSimulation", seedId = id,
        grounded = false })
end

function Controller:Message(message)
    self.LastMessage = message
    self.MessageUntil = os.clock() + 2.5
    self:RefreshHUD()
end

function Controller:RefreshHUD()
    if not self.Gui then return end
    self.Gui.Enabled = self.Active
        and (self.Mode=="Simulate" or self.WeldMode or self.ManualActive)
    self.HUDPanel.Visible=self.Mode=="Simulate"
        or self.WeldMode or self.ManualActive
    self.HUDPanel.AnchorPoint=Vector2.new(0,0)
    self.HUDPanel.Position=if self.Mode=="Simulate"
        then UDim2.fromOffset(16,64)
        else UDim2.new(1,-396,0,20)
    self.HUDPanel.Size=if self.Mode=="Simulate"
        then UDim2.fromOffset(312,116)
        else UDim2.fromOffset(380,116)
    if not self.Gui.Enabled then return end

    if self.Mode=="Mechanics" and self.WeldMode then
        self.Header.Text="OPENWORKS / WELD"
        self.Detail.Text=if self.WeldFirst
            then "Choose touching surfaces or an inserted shaft in a drilled block"
            else "Choose the first solid to weld"
        self.Help.Text="Click both solids • Esc cancels selection"
        if self.LastMessage and os.clock()<self.MessageUntil then
            self.Detail.Text=self.LastMessage
        end
        return
    end
    if self.Mode=="Simulate" then
        self.Header.Text="SIMULATE / MECHANICAL ASSEMBLY"
        if not self:IsSimulating() then
            local aimed=self:Pick()
            local name=aimed and aimed:GetAttribute("AssemblyName")
            self.Detail.Text=if type(name)=="string" and name~=""
                then name.."  /  REGISTERED"
                else "No registered assembly selected"
            self.Help.Text="P run ungrounded assembly • G configure grounding"
        else
            local paused=player:GetAttribute("OPENWORKS_SimulationPaused")==true
            local grounded=player:GetAttribute("OPENWORKS_Grounded")~=false
            self.Detail.Text=tostring(self.SimAssemblyName or "Assembly")
                ..(if paused then "  /  PAUSED" else "  /  RUNNING")
            self.Help.Text="Hold LMB crank • Q/E guided rack • P stop"
                ..(if grounded then " • green grounded" else " • free")
        end
        if self.LastMessage and os.clock()<self.MessageUntil then
            self.Detail.Text=self.LastMessage
        end
        return
    end

    self.Header.Text = "OPENWORKS / MECHANICS / " .. string.upper(self:Kind())
    if self.Stage == "GearFirst" then
        self.Header.Text = "OPENWORKS / GEAR TRANSMISSION"
        self.Detail.Text = "Choose the first gear"
        self.Help.Text = "Click first gear • K/Esc cancel"
    elseif self.Stage == "GearSecond" then
        self.Header.Text = "OPENWORKS / GEAR TRANSMISSION"
        self.Detail.Text = "Choose the mating gear"
        self.Help.Text = "Click second gear • tooth pitch / spacing validated"
    elseif self.Stage=="PairFirst" or self.Stage=="PairSecond" then
        self.Header.Text="OPENWORKS / "..string.upper(
            tostring(self.PairKind or "MECHANICAL"))
        self.Detail.Text=if self.Stage=="PairFirst"
            then "Choose first mechanical part" else "Choose second physical part"
        self.Help.Text=if self.PairKind=="CrankCoupling"
            then "Choose hand crank, then the shaft END • rigid coupling • Esc cancel"
            elseif self.PairKind=="Spring"
            then "Select any two components • spring force only • Esc cancel"
            elseif self.PairKind=="Bolt"
            then "Choose two aligned holes • physical bolt inserted"
            else "Choose two touching surfaces • permanent weld"
    elseif self.Stage == "JointSettings" then
        local kind = self.Joint and self.Joint:GetAttribute("Kind") or "Joint"
        local low = self.Joint and self.Joint:GetAttribute("LowerLimit") or -90
        local high = self.Joint and self.Joint:GetAttribute("UpperLimit") or 90
        self.Header.Text = "OPENWORKS / " .. string.upper(kind) .. " LIMITS"
        if kind=="Spring" then
            self.Detail.Text=string.format("Stiffness %.0f / damping %.0f / rest %.2f U",
                self.Joint:GetAttribute("Stiffness") or 120,
                self.Joint:GetAttribute("Damping") or 14,
                (self.Joint:GetAttribute("FreeLength") or 0.5)/Grid.Unit)
            self.Help.Text="[ ] strength • Shift+[ ] damping • -/= rest length • Esc"
        else
            self.Detail.Text = tostring(low) .. " — " .. tostring(high)
            self.Help.Text = "U toggle limits • [ ] adjust travel • Esc close"
        end
    elseif self.Stage == "Housing" then
        self.Detail.Text = "Choose the housing or opening"
        self.Help.Text = "Click opening • R relationship • Esc close"
    elseif self.Stage == "Source" then
        self.Detail.Text = "Choose the shaft or source component"
        self.Help.Text = "Click shaft/component • P simulate aimed mechanism • Esc reset"
    elseif self.Stage == "Fit" then
        local u = if self.Source and self.Source.PrimaryPart then
            self.Source.PrimaryPart.Size.Y / Grid.Unit else 0
        self.Detail.Text = string.format("SHAFT DIAMETER  /  %.2f U", u)
        self.Help.Text = "Wheel fit • Alt+wheel depth • Shift+wheel/Q/E rotate • click done"
    else
        self.Detail.Text = string.format("Insertion %.1f U  /  rotation %.0f°",
            self.OffsetUnits,self.RollDegrees)
        self.Help.Text = "Wheel depth • Q/E rotate • blue clear / red blocked • click create"
    end

    if self.Stage == "Preview" and self:Kind() ~= "Fixed" and not self.PreviewValid then
        self.Detail.Text = "INTERFERENCE / move insertion until blue"
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
    h.OutlineTransparency = 1
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = model
    return h
end

function Controller:ClearPreview()
    if self.PreviewModel then self.PreviewModel:Destroy() end
    self.PreviewModel = nil
    self.VisualPose = nil
    self.TargetPose = nil
    player:SetAttribute("OPENWORKS_Inserting", false)
end

function Controller:Reset()
    self:ClearPreview()
    self:ClearHighlights()
    self.Stage = "Housing"
    self.ManualActive = false
    self.Housing = nil
    self.Source = nil
    self.Members = {}
    self.OffsetUnits = 0
    self.RollDegrees = 0
    self.GearFirst = nil
    self.PairFirst = nil
    self.PairKind = nil
    self.Joint = nil
    self.WeldFirst=nil
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
    local ray=CameraAimRay.Ray(camera)
    local result = workspace:Raycast(ray.Origin,
        ray.Direction * Grid.MaxDistance, params)
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
                part.Transparency = if part:GetAttribute("GearPivotOnly")==true
                    then 1 else 0.45
                part.Color = Color3.fromRGB(91, 201, 187)
            end
        end
    end
    ghost.WorldPivot = self.Source:GetPivot()
    ghost.Parent = workspace
    self.PreviewModel = ghost
    self.GhostStart = ghost:GetPivot()
    self.VisualPose = self.GhostStart
    self.TargetPose = self.GhostStart
    player:SetAttribute("OPENWORKS_Inserting", true)
    self:UpdatePreview()
end

function Controller:UpdatePreview()
    if not self.Active or self.Stage ~= "Preview" or not self.Housing or not self.Source then
        return
    end
    if self:Kind() == "Fixed" then return end

    local plan, reason = Alignment.Plan(
        self.Members, self.Source, self.Housing, self.OffsetUnits,
        self.RollDegrees
    )
    if not plan then
        self:Message(tostring(reason))
        return
    end
    if self.PreviewModel then
        local goal = plan.delta * self.GhostStart
        local visual = self.VisualPose or self.PreviewModel:GetPivot()
        self.PreviewModel:PivotTo(goal)
        local ignore = {}
        for _, member in ipairs(self.Members) do ignore[member] = true end
        self.PreviewValid, self.PreviewReason = PreviewFeedback.Check(
            self.PreviewModel, ignore, self.Source:GetAttribute("InstanceId"),
            self.Housing
        )
        PreviewFeedback.Paint(self.PreviewModel, self.PreviewValid)
        self.TargetPose = goal
        self.VisualPose = visual
        self.PreviewModel:PivotTo(visual)
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
    return result.ok == true,result
end

function Controller:AdjustFit(direction)
    if self.Stage ~= "Fit" or not self.Source or not self.Housing then
        return
    end
    self:Request({
        action = "FitShaft",
        sourceId = self.Source:GetAttribute("InstanceId"),
        targetId = self.Housing:GetAttribute("InstanceId"),
        step = direction,
    })
    self:RefreshHUD()
end

function Controller:PoseConnected(offset,roll)
    if self.Stage~="Fit" or not self.Source or not self.Housing then return end
    local stop=WorldMotion.AnimateShaftPose(self.Members,self.Source,
        self.Housing,offset,roll)
    local ok=self:Request({
        action="PoseShaft",
        sourceId=self.Source:GetAttribute("InstanceId"),
        targetId=self.Housing:GetAttribute("InstanceId"),
        offsetUnits=offset,
        rollDegrees=roll,
    })
    if ok then
        self.OffsetUnits=offset
        self.RollDegrees=roll
    else
        stop()
    end
end

function Controller:ChangeRoll(delta)
    local degrees=math.clamp(math.round(self.RollDegrees+delta),-360,360)
    if self.Stage=="Preview" then
        self.RollDegrees=degrees
        self:UpdatePreview()
    elseif self.Stage=="Fit" then
        self:PoseConnected(self.OffsetUnits,degrees)
    end
end

function Controller:ToggleGearMode()
    -- No manual K pairing. Contact, axle direction, tooth count and
    -- physical pitch spacing now determine engagement automatically.
    -- Existing saved Gear relationships remain readable as legacy data.
    self:Reset()
    self:Message("Gears auto-mesh in simulation • no K pairing required")
    self:RefreshHUD()
end

-- Distinct authoring actions remain in Edit, but no extra native tool
-- is required. A two-click pair is only needed for explicit springs,
-- structural welds and physical bolt holes.
function Controller:StartPair(kind)
    self:Reset()
    self.ManualActive=true
    self.PairKind=kind
    self.Stage="PairFirst"
    self:RefreshHUD()
end

function Controller:WeldClick()
    if self:IsSimulating() then
        self:Message("Stop simulation before welding")
        return
    end
    local picked=self:Pick()
    if not picked then self:Message("Aim at a solid to weld") return end
    if not self.WeldFirst then
        self.WeldFirst=picked
        self:RefreshHUD()
        return
    end
    if self.WeldFirst==picked then
        self:Message("Select a different touching solid")
        return
    end
    local success=self:Request({
        action="CreateWeld",
        sourceId=self.WeldFirst:GetAttribute("InstanceId"),
        targetId=picked:GetAttribute("InstanceId"),
    })
    if success then self.WeldFirst=nil end
    self:RefreshHUD()
end

function Controller:StartManualJoint()
    self:Reset()
    self.ManualActive=true
    self.Stage="Housing"
    self:RefreshHUD()
end

function Controller:HandleEditClick()
    if self.Mode ~= "Mechanics" or not self.ManualActive then
        return false
    end
    self:Activate()
    return true
end

function Controller:IsEditingJoint()
    return self.Mode=="Mechanics" and self.ManualActive
end

function Controller:ToggleGround()
    local target=self:Pick()
    if not target then self:Message("Aim at a body to toggle grounding") return end
    self:Request({action="SetGrounded",
        instanceId=target:GetAttribute("InstanceId")})
end

function Controller:OpenJointSettings()
    local target=self:Pick()
    if not target then self:Message("Aim at a connected body") return end
    local id=target:GetAttribute("InstanceId")
    local folder=workspace:FindFirstChild("OPENWORKS_Relationships")
    if not folder then return end
    -- Prefer springs when multiple constraints share one shaft,
    -- otherwise a J press would always pick the older bearing.
    local ordered=folder:GetChildren()
    table.sort(ordered,function(a,b)
        return (if a:GetAttribute("Kind")=="Spring" then 0 else 1)
            <(if b:GetAttribute("Kind")=="Spring" then 0 else 1)
    end)
    for _,joint in ipairs(ordered) do
        if joint:GetAttribute("OwnerUserId")==player.UserId
            and (joint:GetAttribute("SourceId")==id
                or joint:GetAttribute("TargetId")==id)
            and (joint:GetAttribute("Kind")=="Bearing"
                or joint:GetAttribute("Kind")=="Slider"
                or joint:GetAttribute("Kind")=="Cylindrical"
                or joint:GetAttribute("Kind")=="Spring") then
            self:Reset()
            self.ManualActive=true
            self.Joint=joint
            self.Stage="JointSettings"
            self:RefreshHUD()
            return
        end
    end
    self:Message("No adjustable bearing or slider under the crosshair")
end

function Controller:UpdateJoint(delta,toggle,changeRest)
    local joint=self.Joint
    if not joint or not joint.Parent then self:Reset() return end
    local kind=joint:GetAttribute("Kind")
    if kind=="Spring" then
        local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        local stiffness=joint:GetAttribute("Stiffness") or 120
        local damping=joint:GetAttribute("Damping") or 14
        local rest=joint:GetAttribute("FreeLength") or 0.5
        if changeRest then
            rest=math.clamp(rest+(delta or 0)*Grid.Unit*0.25,
                Grid.Unit*0.2,Grid.Unit*32)
        elseif shift then
            damping=math.clamp(damping+(delta or 0)*5,0,300)
        else
            stiffness=math.clamp(stiffness+(delta or 0)*25,10,3000)
        end
        self:Request({
            action="TuneSpring",relationId=joint:GetAttribute("RelationId"),
            stiffness=stiffness,damping=damping,freeLength=rest,
        })
        self:RefreshHUD()
        return
    end
    local isHinge=kind=="Bearing"
    local limit=if isHinge then 180 else 32
    local previous=math.max(
        math.abs(joint:GetAttribute("LowerLimit") or (if isHinge then -90 else -4)),
        math.abs(joint:GetAttribute("UpperLimit") or (if isHinge then 90 else 4))
    )
    local half=math.clamp(previous+(delta or 0)*(if isHinge then 15 else 0.5),
        if isHinge then 15 else 0.5,limit)
    local on=joint:GetAttribute("LimitsEnabled")==true
    if toggle then on=not on end
    self:Request({
        action="AdjustJoint",
        relationId=joint:GetAttribute("RelationId"),
        lowerLimit=-half,
        upperLimit=half,
        limitsEnabled=on,
    })
    self:RefreshHUD()
end

function Controller:Activate()
    if not self.Active or self.Busy or self:IsSimulating() then return end
    if self.Stage=="PairFirst" then
        local first=self:Pick()
        if not first then self:Message("Aim at a construction you own") return end
        if self.PairKind=="CrankCoupling"
            and not HandCrankMath.IsCrank(first) then
            self:Message("Select the HandCrank first, then its output shaft")
            return
        end
        self.PairFirst=first
        self.Stage="PairSecond"
        self:RefreshHUD()
        return
    elseif self.Stage=="PairSecond" then
        local second=self:Pick({[self.PairFirst]=true})
        if not second then
            self:Message("Select another part of the mechanical connection")
            return
        end
        local first=self.PairFirst
        local request={
            action=if self.PairKind=="CrankCoupling"
                then "CoupleHandCrank" else "Create"..self.PairKind,
            sourceId=first:GetAttribute("InstanceId"),
            targetId=second:GetAttribute("InstanceId"),
        }
        if self.PairKind=="Spring" then
            -- Piston source MUST be the shaft and target the opening.
            if Alignment.IsShaft(second) and Alignment.TargetAxis(first) then
                request.sourceId=second:GetAttribute("InstanceId")
                request.targetId=first:GetAttribute("InstanceId")
            end
        end
        if self:Request(request) then self:Reset() end
        return
    end
    if self.Stage=="GearFirst" then
        local candidate=self:Pick()
        if not candidate or not candidate:GetAttribute("GearTeeth") then
            self:Message("Select a toothed Transmission gear") return
        end
        self.GearFirst=candidate
        self.Stage="GearSecond"
        self:RefreshHUD()
        return
    elseif self.Stage=="GearSecond" then
        local candidate=self:Pick({[self.GearFirst]=true})
        if not candidate or not candidate:GetAttribute("GearTeeth") then
            self:Message("Aim at a second Transmission gear") return
        end
        if self:Request({action="CreateGearMesh",
            sourceId=self.GearFirst:GetAttribute("InstanceId"),
            targetId=candidate:GetAttribute("InstanceId")}) then
            self:Reset()
        end
        return
    elseif self.Stage=="JointSettings" then
        return
    elseif self.Stage == "Housing" then
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
        self.RollDegrees = 0
        self.Stage = "Preview"
        self:MakePreview()
    elseif self.Stage == "Fit" then
        self:Reset()
        return
    else
        if not self.Housing or not self.Source then self:Reset() return end
        if self:Kind() ~= "Fixed" and not self.PreviewValid then
            self:Message(self.PreviewReason or "Red preview: geometry overlaps")
            return
        end
        if self:Request({
            action = "CreateRelation",
            kind = self:Kind(),
            targetId = self.Housing:GetAttribute("InstanceId"),
            sourceId = self.Source:GetAttribute("InstanceId"),
            offsetUnits = self.OffsetUnits,
            rollDegrees = self.RollDegrees,
        }) then
            if self:Kind() ~= "Fixed" then
                self:ClearPreview()
                self.Stage = "Fit"
                player:SetAttribute("OPENWORKS_Inserting", true)
                self:Message("Connected • wheel fits shaft diameter by 0.05 U")
            else
                self:Reset()
            end
        end
    end
    self:RefreshHUD()
end

function Controller:DeleteRelationship()
    -- Delete an authored relationship by aiming at either connected body.
    -- Construction itself is never deleted by the Assemble tool.
    local candidate = self:Pick()
    if not candidate then candidate = self.Source or self.Housing end
    if not candidate then
        self:Message("Aim at a connected part to delete its relationship")
        return
    end
    local id = candidate:GetAttribute("InstanceId")
    local relationships = workspace:FindFirstChild("OPENWORKS_Relationships")
    if not relationships then
        self:Message("No mechanical relationships to delete")
        return
    end
    local chosen
    for _, relation in ipairs(relationships:GetChildren()) do
        if relation:GetAttribute("OwnerUserId") == player.UserId
            and (relation:GetAttribute("SourceId") == id
                or relation:GetAttribute("TargetId") == id) then
            chosen = relation
            break
        end
    end
    if not chosen then
        self:Message("This part has no mechanical relationship")
        return
    end

    if self:Request({
        action = "RemoveRelation",
        relationId = chosen:GetAttribute("RelationId"),
    }) then
        self:Reset()
    end
end

function Controller:CycleType()
    if self.Stage == "Fit" then self:Reset() end
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
    if self.Mode~=mode then self:Reset() end
    self.Mode=mode
    self.Active=mode=="Mechanics" or mode=="Simulate"
    self.WeldMode=false
    if self.Properties then self.Properties:Show(false) end
    if mode=="Mechanics" and self.Tools.SubtoolId=="Connect" then
        self:StartManualJoint()
    end
    self:RefreshHUD()
end

function Controller:OnSubtoolChanged(primary,subtool,_previous)
    if primary~="Mechanics" then return end
    self:Reset()
    self.WeldMode=false
    if self.Properties then self.Properties:Show(false) end
    if subtool=="Connect" then self:StartManualJoint() end
    self:RefreshHUD()
end

function Controller:Start()
    self.Gui, self.HUDPanel, self.Header, self.Detail, self.Help = createGui()
    table.insert(self.Connections,Theme.Attach(self.Gui))
    self.Properties=RelationshipProperties.new(self)
    self.Properties:Start()
    self.Remote = ReplicatedStorage:WaitForChild(Config.RequestName)
    self.HandCrank=HandCrankController.new(self)
    self.HandCrank:Start()
    self.RackControl=RackControlController.new(self)
    self.RackControl:Start()
    self.MotorControl=MotorControlController.new(self)
    self.MotorControl:Start()
    table.insert(self.Connections,self.Tools.Changed.Event:Connect(function(mode)
        self:OnModeChanged(mode)
    end))
    table.insert(self.Connections,self.Tools.SubtoolChanged.Event:Connect(
        function(primary,subtool,previous)
            self:OnSubtoolChanged(primary,subtool,previous)
        end))
    table.insert(self.Connections,self.Tools.Activated.Event:Connect(function(mode)
        if mode=="Simulate"
            and not player:GetAttribute("OPENWORKS_PropertiesOpen") then
            -- Hold LMB on the mechanism to drive a physically coupled crank;
            -- release stops it. Other clicks inspect the aimed body.
            if self.HandCrank and self.HandCrank:TryGrab() then return end
            self.Properties:InspectAtCenter()
        elseif mode=="Mechanics" then
            if self.Tools.SubtoolId=="Configure" then
                self.Properties:InspectAtCenter()
            elseif self.WeldMode then
                self:WeldClick()
            elseif self.ManualActive then
                self:Activate()
            end
        end
    end))
    table.insert(self.Connections,UserInputService.InputBegan:Connect(function(input,processed)
        if not self.Active or UserInputService:GetFocusedTextBox()
            or self.Tools:WasConsumed(input) then return end
        local key=input.KeyCode
        if self.Mode=="Mechanics" and self.WeldMode then
            if key==Enum.KeyCode.Escape or key==Enum.KeyCode.F then
                self.WeldFirst=nil
                self.WeldMode=false
                self:StartManualJoint()
            end
            return
        end
        if self.Construction and
            (self.Construction.PendingMateChoice
                or (self.Construction.Numeric and self.Construction.Numeric.Active)) then
            return
        end
        if self.Mode=="Simulate" then
            if processed then return end
            if key==Enum.KeyCode.P then self:ToggleSimulation()
            elseif key==Enum.KeyCode.G then
                if not self:IsSimulating() then self:ToggleGround() end
            elseif self:IsSimulating() then
                if key==Enum.KeyCode.O then
                    self:Request({action="PauseSimulation"})
                elseif key==Enum.KeyCode.U then
                    self:Request({action="ResetSimulation"})
                elseif key==Enum.KeyCode.I then
                    self:Request({action="GetMechanismInfo",seedId=self.SimSeedId})
                end
            end
            return
        end

        -- Mechanics / Connect owns mechanical authoring; Build/Edit owns
        -- world selection and geometry manipulation.
        if self.Mode~="Mechanics"
            or self.Tools.SubtoolId~="Connect" or processed then return end
        local control=UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        if control and (key==Enum.KeyCode.Z or key==Enum.KeyCode.Y) then
            self:Request({action=if key==Enum.KeyCode.Z then "Undo" else "Redo"})
            self:Reset()
            if self.Tools.SubtoolId=="Connect" then self:StartManualJoint() end
            return
        end
        -- F enters the legacy validated two-solid weld workflow. W remains
        -- the universal freecam forward key, so it cannot be a weld shortcut.
        if key==Enum.KeyCode.F and not control then
            self:Reset()
            self.WeldMode=true
            self:RefreshHUD()
            return
        end
        -- Shift+J creates a real spring between authored components.
        if key==Enum.KeyCode.J and shift then
            self:StartPair("Spring")
            return
        end
        if key==Enum.KeyCode.C and shift then
            self:StartPair("CrankCoupling")
            return
        end
        if key==Enum.KeyCode.K then self:ToggleGearMode() return end
        -- Tune joints only with the mouse-driven Simulate properties GUI.
        if key==Enum.KeyCode.H then self:StartManualJoint() return end
        if shift and (key==Enum.KeyCode.Delete
            or key==Enum.KeyCode.Backspace) then
            self:DeleteRelationship()
            return
        end
        if not self.ManualActive then return end

        if key==Enum.KeyCode.Escape then self:Reset()
        elseif key==Enum.KeyCode.R and self.Stage~="JointSettings" then
            self:CycleType()
        elseif key==Enum.KeyCode.LeftBracket or key==Enum.KeyCode.RightBracket then
            local delta=if key==Enum.KeyCode.RightBracket then 1 else -1
            if self.Stage=="Fit" then
                self:AdjustFit(delta)
            elseif self.Stage=="Preview" then
                self.OffsetUnits=math.clamp(
                    self.OffsetUnits+delta*INSERTION_STEP_U,
                    -Alignment.MaxOffsetUnits,Alignment.MaxOffsetUnits)
                self:UpdatePreview()
            end
        elseif (self.Stage=="Preview" or self.Stage=="Fit")
            and (key==Enum.KeyCode.Q or key==Enum.KeyCode.E) then
            self:ChangeRoll(if key==Enum.KeyCode.E then 5 else -5)
        end
    end))
    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if self.Mode~="Mechanics" or not self.ManualActive
            or (self.Stage ~= "Preview" and self.Stage ~= "Fit")
            or self:Kind() == "Fixed" then return end
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        local direction=if input.Position.Z>0 then 1 else -1
        local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        local alt=UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
        if shift then
            self:ChangeRoll(direction*5)
            return
        end
        if alt and self.Stage=="Fit" then
            local offset=math.clamp(self.OffsetUnits+direction*INSERTION_STEP_U,
                -Alignment.MaxOffsetUnits,Alignment.MaxOffsetUnits)
            self:PoseConnected(offset,self.RollDegrees)
            return
        end
        if self.Stage == "Fit" then
            self:AdjustFit(if input.Position.Z > 0 then 1 else -1)
            return
        end
        self.OffsetUnits = math.clamp(
            self.OffsetUnits + (if input.Position.Z > 0
                then INSERTION_STEP_U else -INSERTION_STEP_U),
            -Alignment.MaxOffsetUnits, Alignment.MaxOffsetUnits
        )
        self:UpdatePreview()
    end))
    table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
        if self.Mode=="Simulate" and not self:IsSimulating() then
            local now=os.clock()
            if now-(self.LastSimHUDPoll or 0)>0.25 then
                self.LastSimHUDPoll=now
                self:RefreshHUD()
            end
        end
        if self.Mode~="Mechanics" or not self.ManualActive
            or self:IsSimulating() then return end
        if self.Stage=="Preview" and self.PreviewModel and self.TargetPose then
            self.VisualPose=WorldMotion.Step(
                self.VisualPose,self.TargetPose,dt,
                WorldMotion.Profile.Placement)
            self.PreviewModel:PivotTo(self.VisualPose)
        end
        if self.Stage=="Preview" or self.Stage=="Fit" then
            local direction=if UserInputService:IsKeyDown(Enum.KeyCode.Q) then -1
                elseif UserInputService:IsKeyDown(Enum.KeyCode.E) then 1 else 0
            if direction~=0 then
                local now=os.clock()
                if self.Stage=="Preview" then
                    self.RollAccumulator=(self.RollAccumulator or 0)
                        + dt*95*direction
                    local step=(if self.RollAccumulator>=0 then math.floor(self.RollAccumulator) else math.ceil(self.RollAccumulator))
                    if step~=0 then
                        self.RollAccumulator-=step
                        self:ChangeRoll(step)
                    end
                elseif now-(self.LastRollSend or 0)>0.115 then
                    self.LastRollSend=now
                    self:ChangeRoll(direction*5)
                end
            end
        end
    end))
    table.insert(self.Connections, player:GetAttributeChangedSignal(
        "OPENWORKS_Simulating"):Connect(function()
            self:RefreshHUD()
        end))
    table.insert(self.Connections,player:GetAttributeChangedSignal(
        "OPENWORKS_SimulationPaused"):Connect(function()
            self:RefreshHUD()
        end))
    for _, name in ipairs({ "OPENWORKS_Grounded" }) do
        table.insert(self.Connections, player:GetAttributeChangedSignal(
            name):Connect(function() self:RefreshHUD() end))
    end
    -- Use the state of the already-equipped native tool on client startup.
    self:OnModeChanged(self.Tools.ActiveId)
    self:OnSubtoolChanged(self.Tools.PrimaryId,self.Tools.SubtoolId,nil)
end

function Controller:Destroy()
    if self.HandCrank then self.HandCrank:Destroy() end
    if self.RackControl then self.RackControl:Destroy() end
    if self.MotorControl then self.MotorControl:Destroy() end
    self:Reset()
    for _, conn in ipairs(self.Connections) do conn:Disconnect() end
    table.clear(self.Connections)
    if self.Properties then self.Properties:Destroy() end
    if self.Gui then self.Gui:Destroy() end
end

return Controller
