--!strict
-- A HAND crank is a player-controlled physical torque source. It never
-- changes Bearing/Slider/Cylindrical ActuatorType. H enters grip mode;
-- hold LMB and trace circles with the free cursor to apply limited torque.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Grid=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))
local CrankMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("HandCrankMath"))
local player=Players.LocalPlayer

local Hand={}
Hand.__index=Hand
local STEP=0.07
local RING_RADIUS=116

local function make(kind,parent,properties)
    local item=Instance.new(kind)
    for key,value in pairs(properties) do item[key]=value end
    item.Parent=parent
    return item
end

function Hand.new(assembly)
    return setmetatable({
        Assembly=assembly,
        ActiveId=nil,
        Dragging=false,
        LastAngle=nil,
        AngleDelta=0,
        SendAccumulator=0,
        LastDesired=0,
        LastBodyUp=nil,
        Connections={},
    },Hand)
end

function Hand:SimFolder()
    local world=workspace:FindFirstChild("OPENWORKS_Simulated")
    return world and world:FindFirstChild("Simulation_"..player.UserId)
end

function Hand:Candidate()
    local running=self:SimFolder()
    if not running then return nil end
    -- Select a simulated crank directly when camera is pointed at its grip.
    local camera=workspace.CurrentCamera
    if camera then
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={running}
        local half=camera.ViewportSize*0.5
        local ray=camera:ViewportPointToRay(half.X,half.Y)
        local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
        local member=hit and hit.Instance:FindFirstAncestorOfClass("Model")
        if member and CrankMath.IsCrank(member) then return member end
    end
    -- Simulate Properties can select a crank through transparent layers.
    local selected=self.Assembly.Properties
        and self.Assembly.Properties.SelectedId
    if type(selected)=="string" then
        for _,member in ipairs(running:GetChildren()) do
            if member:IsA("Model")
                and member:GetAttribute("InstanceId")==selected
                and CrankMath.IsCrank(member) then return member end
        end
    end
    return nil
end

function Hand:FindCrank()
    if not self.ActiveId then return nil end
    local folder=self:SimFolder()
    if not folder then return nil end
    for _,member in ipairs(folder:GetChildren()) do
        if member:IsA("Model")
            and member:GetAttribute("InstanceId")==self.ActiveId
            and CrankMath.IsCrank(member) then return member end
    end
    return nil
end

function Hand:Draw()
    local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_ManualHandCrank",Enabled=false,
        IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=119,
    })
    self.Gui=gui
    local ring=make("Frame",gui,{
        Name="MouseCrankRing",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(RING_RADIUS*2,RING_RADIUS*2),
        BackgroundTransparency=0.97,
        BackgroundColor3=Color3.fromRGB(218,165,87),
        BorderSizePixel=0,
        Active=false,
    })
    make("UICorner",ring,{CornerRadius=UDim.new(1,0)})
    make("UIStroke",ring,{
        Thickness=3,Color=Color3.fromRGB(239,174,94),
        Transparency=0.14,
    })
    self.Ring=ring
    local center=make("Frame",ring,{
        Name="Axle",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(18,18),
        BackgroundColor3=Color3.fromRGB(221,157,88),
        BorderSizePixel=0,
    })
    make("UICorner",center,{CornerRadius=UDim.new(1,0)})
    local knob=make("Frame",ring,{
        Name="CrankMotionDot",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0),
        Size=UDim2.fromOffset(15,15),
        BackgroundColor3=Color3.fromRGB(248,218,169),
        BorderSizePixel=0,
    })
    make("UICorner",knob,{CornerRadius=UDim.new(1,0)})
    self.Knob=knob
    local title=make("TextLabel",gui,{
        Name="CrankInstructions",
        AnchorPoint=Vector2.new(0.5,1),
        Position=UDim2.new(0.5,0,0.5,-RING_RADIUS-24),
        Size=UDim2.fromOffset(460,70),
        BackgroundTransparency=1,TextColor3=Color3.fromRGB(241,228,208),
        Font=Enum.Font.GothamBold,TextSize=15,TextWrapped=true,
        Text="HAND CRANK  /  MANUAL TORQUE\nHold LMB and move the pointer around the circle",
    })
    self.Title=title
    local status=make("TextLabel",gui,{
        Name="CrankFeedback",
        AnchorPoint=Vector2.new(0.5,0),
        Position=UDim2.new(0.5,0,0.5,RING_RADIUS+18),
        Size=UDim2.fromOffset(420,54),
        BackgroundTransparency=1,TextColor3=Color3.fromRGB(191,209,221),
        Font=Enum.Font.GothamMedium,TextSize=12,TextWrapped=true,
        Text="H / Esc release  •  LMB hold and trace circles",
    })
    self.Status=status
end

function Hand:StartGrip()
    if self.ActiveId then self:Release() return end
    if self.Assembly.Mode~="Simulate" or not self.Assembly:IsSimulating() then
        self.Assembly:Message("Start simulation (P) before gripping the crank")
        return
    end
    local model=self:Candidate()
    if not model then
        self.Assembly:Message("Aim at a simulated crank grip or select it in Properties, then H")
        return
    end
    local id=model:GetAttribute("InstanceId")
    if type(id)~="string" then return end
    local ok,result=self.Assembly:Request({action="BeginCrank",crankId=id})
    if not ok then return end
    self.ActiveId=id
    self.Dragging=false
    self.LastAngle=nil
    self.AngleDelta=0
    self.SendAccumulator=0
    self.LastDesired=0
    self.LastBodyUp=nil
    -- The Properties GUI owns a modal full-screen mouse surface. Hide it
    -- temporarily while manually drawing the crank path, restore on release.
    if self.Assembly.Properties then
        self.Assembly.Properties:Show(false)
    end
    player:SetAttribute("OPENWORKS_CrankActive",true)
    self.Gui.Enabled=true
    UIS.MouseBehavior=Enum.MouseBehavior.Default
    UIS.MouseIconEnabled=true
    self.Status.Text=tostring(result and result.message
        or "Hold LMB and draw circles with your mouse")
end

function Hand:Release()
    local id=self.ActiveId
    self.ActiveId=nil
    self.Dragging=false
    self.LastAngle=nil
    self.AngleDelta=0
    self.SendAccumulator=0
    self.LastDesired=0
    self.LastBodyUp=nil
    player:SetAttribute("OPENWORKS_CrankActive",false)
    self.Gui.Enabled=false
    if id and self.Remote then
        self.Remote:FireServer(id,0,false,true)
    end
    if self.Assembly.Mode=="Simulate" and self.Assembly.Properties then
        self.Assembly.Properties:Show(true)
    end
end

function Hand:MouseAngle()
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local center=camera.ViewportSize*0.5
    local offset=UIS:GetMouseLocation()-center
    if offset.Magnitude<29 then return nil end
    return math.atan2(offset.Y,offset.X)
end

function Hand:Tick(dt)
    if not self.ActiveId then return end
    if self.Assembly.Mode~="Simulate" or not self.Assembly:IsSimulating()
        or not self:FindCrank() then
        self:Release()
        return
    end
    if self.Dragging then
        local angle=self:MouseAngle()
        if angle then
            self.Knob.Position=UDim2.fromOffset(
                RING_RADIUS+math.cos(angle)*RING_RADIUS,
                RING_RADIUS+math.sin(angle)*RING_RADIUS)
            if self.LastAngle then
                local delta=math.atan2(math.sin(angle-self.LastAngle),
                    math.cos(angle-self.LastAngle))
                if math.abs(delta)<math.pi*0.7 then
                    self.AngleDelta+=delta
                end
            end
        end
        self.LastAngle=angle
    end
    self.SendAccumulator+=dt
    if self.SendAccumulator<STEP then return end
    local delta=math.max(self.SendAccumulator,0.015)
    self.SendAccumulator=0
    local desired=if self.Dragging
        then math.clamp(self.AngleDelta/delta,
            -CrankMath.MaxAngularSpeed,CrankMath.MaxAngularSpeed) else 0
    self.AngleDelta=0
    -- Screen clockwise/counterclockwise should match the apparent
    -- crank direction even when the player looks from the other side.
    local model=self:FindCrank()
    local root=model and model.PrimaryPart
    local camera=workspace.CurrentCamera
    if root and camera and root.CFrame.RightVector:Dot(
        camera.CFrame.LookVector)<0 then
        desired=-desired
    end
    self.LastDesired=desired
    if self.Remote then
        self.Remote:FireServer(self.ActiveId,desired,self.Dragging,false)
    end
    if root then
        -- AngularVelocity isn't guaranteed to replicate as a property.
        -- Measure visible rotational movement between world poses instead
        -- of reporting a misleading zero from client property reads.
        local up=root.CFrame.UpVector
        local actual=0
        if self.LastBodyUp then
            local axial=root.CFrame.RightVector.Unit
            actual=math.atan2(self.LastBodyUp:Cross(up):Dot(axial),
                self.LastBodyUp:Dot(up))/delta
        end
        self.LastBodyUp=up
        if self.Dragging then
            if math.abs(desired)>1.0 and math.abs(actual)<0.15 then
                self.Status.Text="HIGH RESISTANCE / STALLED  •  capped hand torque"
            else
                self.Status.Text=string.format(
                    "MANUAL INPUT %.1f rad/s  •  SHAFT %.1f rad/s",
                    desired,actual)
            end
        else
            self.Status.Text="H / Esc release  •  hold LMB and trace circles"
        end
    end
end

function Hand:Start()
    self:Draw()
    self.Remote=ReplicatedStorage:WaitForChild("OPENWORKS_CrankControl")
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if input.KeyCode==Enum.KeyCode.H then
            if processed or UIS:GetFocusedTextBox() then return end
            if self.Assembly.Mode=="Simulate" then self:StartGrip() end
            return
        end
        if not self.ActiveId then return end
        if input.KeyCode==Enum.KeyCode.Escape then
            self:Release()
        elseif input.UserInputType==Enum.UserInputType.MouseButton1 then
            self.Dragging=true
            self.LastAngle=self:MouseAngle()
            self.AngleDelta=0
        end
    end))
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        if self.ActiveId
            and input.UserInputType==Enum.UserInputType.MouseButton1 then
            self.Dragging=false
            self.LastAngle=nil
            self.AngleDelta=0
            self.Remote:FireServer(self.ActiveId,0,false,false)
        end
    end))
    table.insert(self.Connections,RunService.RenderStepped:Connect(function(dt)
        self:Tick(dt)
    end))
    table.insert(self.Connections,player:GetAttributeChangedSignal(
        "OPENWORKS_Simulating"):Connect(function()
        if self.ActiveId and not self.Assembly:IsSimulating() then
            self:Release()
        end
    end))
    table.insert(self.Connections,self.Assembly.Tools.Changed.Event:Connect(
        function(mode)
            if self.ActiveId and mode~="Simulate" then self:Release() end
        end))
end

function Hand:Destroy()
    if self.ActiveId then self:Release() end
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end

return Hand
