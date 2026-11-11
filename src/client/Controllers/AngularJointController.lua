--!strict
-- Arbitrary joint editor. Alt+J opens an ordinary Roblox UI picker;
-- face-click selects an anchor. X/Y/Z choose local axis, Q/E and U/O
-- rotate that axis in 5-degree steps, Alt+arrows tweak anchor precision.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
local Aim=require(script.Parent:WaitForChild("CameraAimRay"))
local Frames=require(RS:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("JointFrameMath"))
local Config=require(RS:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BuildConfig"))
local KINDS={"AxisHinge","AxisBall","AxisUniversal","PoweredHinge"}
local UI_COLOR=Color3.fromRGB(31,39,50)
local Angular={}
Angular.__index=Angular

local function box(parent,class,props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local function pickFace()
    local camera=workspace.CurrentCamera
    local folder=workspace:FindFirstChild(Config.FolderName)
    if not camera or not folder then return nil,nil end
    local ray=Aim.Ray(camera)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={folder}
    local hit=workspace:Raycast(ray.Origin,ray.Direction*100,params)
    if not hit then return nil,nil end
    local model=hit.Instance
    while model and model.Parent~=folder do model=model.Parent end
    if model and model:IsA("Model")
        and model:GetAttribute("OwnerUserId")==player.UserId then
        return model,hit.Position
    end
    return nil,nil
end
function Angular.new(parent)
    return setmetatable({
        Parent=parent,Active=false,Stage="None",Kind="AxisHinge",
        First=nil,Anchor=nil,AxisLetter="X",Yaw=0,Pitch=0,
        Connections={},Visuals={},
    },Angular)
end
function Angular:ClearVisuals()
    for _,visual in ipairs(self.Visuals) do visual:Destroy() end
    table.clear(self.Visuals)
end
function Angular:Frame()
    if not self.First or not self.Anchor then return nil end
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local basis=self.First.PrimaryPart.CFrame
    local a=if self.AxisLetter=="X" then basis.RightVector
        elseif self.AxisLetter=="Y" then basis.UpVector else basis.LookVector
    local yaw=CFrame.fromAxisAngle(Vector3.yAxis,math.rad(self.Yaw))
    local pitch=CFrame.fromAxisAngle(camera.CFrame.RightVector,math.rad(self.Pitch))
    local axis=(pitch*yaw):VectorToWorldSpace(a).Unit
    local up=if math.abs(axis:Dot(Vector3.yAxis))<0.94
        then Vector3.yAxis else Vector3.zAxis
    up=(up-axis*axis:Dot(up)).Unit
    return CFrame.fromMatrix(self.Anchor,axis,up,axis:Cross(up))
end
function Angular:DrawAnchor()
    self:ClearVisuals()
    local frame=self:Frame()
    if not frame or not self.First or not self.First.PrimaryPart then return end
    local part=self.First.PrimaryPart
    local dot=Instance.new("SphereHandleAdornment")
    dot.Name="OPENWORKS_AngularJointAnchor"
    dot.Adornee=part
    dot.CFrame=part.CFrame:ToObjectSpace(CFrame.new(self.Anchor))
    dot.Radius=0.11
    dot.AlwaysOnTop=true
    dot.ZIndex=5
    dot.Color3=Color3.fromRGB(235,175,90)
    dot.Transparency=0
    dot.Parent=workspace
    table.insert(self.Visuals,dot)
    local axis=Instance.new("CylinderHandleAdornment")
    axis.Name="OPENWORKS_AngularJointAxis"
    axis.Adornee=part
    axis.CFrame=part.CFrame:ToObjectSpace(
        frame*CFrame.new(0.35,0,0)*CFrame.Angles(0,0,math.rad(90)))
    axis.Radius=0.026
    axis.Height=0.70
    axis.AlwaysOnTop=true
    axis.ZIndex=5
    axis.Color3=Color3.fromRGB(76,213,229)
    axis.Parent=workspace
    table.insert(self.Visuals,axis)
end
function Angular:ShowPicker(visible)
    self.Gui.Enabled=visible
    player:SetAttribute("OPENWORKS_CursorUIOpen",visible)
end
function Angular:Cancel()
    self.Active=false
    self.Stage="None"
    self.First=nil
    self.Anchor=nil
    self:ClearVisuals()
    if self.Gui then self:ShowPicker(false) end
    self.Parent:RefreshHUD()
end
function Angular:Begin()
    if self.Parent.Mode~="Edit" then return end
    self:Cancel()
    self.Active=true
    self.Stage="Choose"
    self:ShowPicker(true)
    self.Parent:Message("Choose joint type; motor speed/torque/key below")
end
function Angular:Choose(kind)
    self.Kind=kind
    self.Stage="First"
    self:ShowPicker(false)
    self.Parent:Message("Aim at the FIRST joint anchor and click")
    self.Parent:RefreshHUD()
end
function Angular:Click()
    if not self.Active or self.Stage=="Choose" then return true end
    if self.Stage=="First" then
        local model,pos=pickFace()
        if not model then self.Parent:Message("Aim at the first solid face") return true end
        self.First=model
        self.Anchor=pos
        self.Yaw=0
        self.Pitch=0
        self.AxisLetter="X"
        self.Stage="Second"
        self:DrawAnchor()
        self.Parent:Message("Axis X/Y/Z • Q/E yaw • U/O tilt • click second part")
        self.Parent:RefreshHUD()
        return true
    end
    if self.Stage=="Second" then
        local other=pickFace()
        if not other or other==self.First then
            self.Parent:Message("Aim at the OTHER component near orange anchor")
            return true
        end
        local frame=self:Frame()
        if not frame then return true end
        local a,b=Frames.LocalPair(self.First.PrimaryPart,
            other.PrimaryPart,frame,self.Kind)
        local payload={
            action="CreateAxisJoint",kind=self.Kind,
            targetId=self.First:GetAttribute("InstanceId"),
            sourceId=other:GetAttribute("InstanceId"),
            frameA=a,frameB=b,
            motorSpeed=tonumber(self.SpeedBox.Text) or 3,
            motorTorque=tonumber(self.TorqueBox.Text) or 3000,
            motorAcceleration=tonumber(self.AccelBox.Text) or 40,
            motorKey=self.KeyBox.Text,
        }
        local ok=self.Parent:Request(payload)
        if ok then self:Cancel() end
        return true
    end
    return true
end
function Angular:HandleKey(input,processed)
    local key=input.KeyCode
    if self.Parent.Mode~="Edit" then return end
    if (UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UIS:IsKeyDown(Enum.KeyCode.RightAlt))
        and key==Enum.KeyCode.J and not processed
        and not UIS:GetFocusedTextBox() then
        if self.Active then self:Cancel() else self:Begin() end
        return
    end
    if not self.Active or self.Stage=="Choose"
        or processed or UIS:GetFocusedTextBox() then return end
    if key==Enum.KeyCode.Escape then self:Cancel() return end
    if self.Stage~="Second" then return end
    if key==Enum.KeyCode.X then self.AxisLetter="X"
    elseif key==Enum.KeyCode.Y then self.AxisLetter="Y"
    elseif key==Enum.KeyCode.Z then self.AxisLetter="Z"
    elseif key==Enum.KeyCode.Q then self.Yaw-=5
    elseif key==Enum.KeyCode.E then self.Yaw+=5
    elseif key==Enum.KeyCode.U then self.Pitch-=5
    elseif key==Enum.KeyCode.O then self.Pitch+=5
    elseif UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UIS:IsKeyDown(Enum.KeyCode.RightAlt) then
        local cam=workspace.CurrentCamera
        if not cam then return end
        local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift)
            or UIS:IsKeyDown(Enum.KeyCode.RightShift)
        if shift and (key==Enum.KeyCode.Up or key==Enum.KeyCode.Down) then
            self.Anchor+=Vector3.yAxis*(if key==Enum.KeyCode.Up then 0.05 else -0.05)
        elseif key==Enum.KeyCode.Up or key==Enum.KeyCode.Down
            or key==Enum.KeyCode.Left or key==Enum.KeyCode.Right then
            local v=if key==Enum.KeyCode.Up or key==Enum.KeyCode.Down
                then cam.CFrame.LookVector else cam.CFrame.RightVector
            v=Vector3.new(v.X,0,v.Z)
            if v.Magnitude>0.01 then
                self.Anchor+=v.Unit*0.05*(if key==Enum.KeyCode.Up
                    or key==Enum.KeyCode.Right then 1 else -1)
            end
        end
    end
    self:DrawAnchor()
end
function Angular:Start()
    local gui=box(player:WaitForChild("PlayerGui"),"ScreenGui",{
        Name="OPENWORKS_JointPicker",ResetOnSpawn=false,
        IgnoreGuiInset=true,Enabled=false,DisplayOrder=110,
    })
    self.Gui=gui
    local panel=box(gui,"Frame",{
        Size=UDim2.fromOffset(318,360),
        Position=UDim2.new(1,-332,0,72),
        BackgroundColor3=UI_COLOR,BorderSizePixel=0,
    })
    box(panel,"UICorner",{CornerRadius=UDim.new(0,8)})
    box(panel,"TextLabel",{
        Position=UDim2.fromOffset(12,7),Size=UDim2.fromOffset(292,31),
        BackgroundTransparency=1,Text="JOINT  /  SELECT TYPE",
        TextColor3=Color3.fromRGB(231,239,248),
        Font=Enum.Font.GothamBold,TextSize=15,
    })
    for i,kind in ipairs(KINDS) do
        local button=box(panel,"TextButton",{
            Position=UDim2.fromOffset(12,43+(i-1)*43),
            Size=UDim2.fromOffset(294,36),Text=kind,
            TextColor3=Color3.fromRGB(233,241,250),
            BackgroundColor3=Color3.fromRGB(53,65,81),
            Font=Enum.Font.GothamMedium,TextSize=13,
        })
        box(button,"UICorner",{CornerRadius=UDim.new(0,5)})
        table.insert(self.Connections,button.Activated:Connect(function()
            self:Choose(kind)
        end))
    end
    local function input(y,label,default)
        box(panel,"TextLabel",{
            Position=UDim2.fromOffset(12,y),Size=UDim2.fromOffset(145,24),
            BackgroundTransparency=1,Text=label,
            TextColor3=Color3.fromRGB(196,213,233),
            TextSize=12,Font=Enum.Font.Gotham,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
        return box(panel,"TextBox",{
            Position=UDim2.fromOffset(163,y),Size=UDim2.fromOffset(141,23),
            BackgroundColor3=Color3.fromRGB(64,77,92),
            TextColor3=Color3.new(1,1,1),
            Font=Enum.Font.Gotham,TextSize=12,
            Text=default,ClearTextOnFocus=false,
        })
    end
    self.SpeedBox=input(221,"Motor speed (rad/s)","3")
    self.TorqueBox=input(250,"Motor torque","3000")
    self.AccelBox=input(279,"Motor acceleration","40")
    self.KeyBox=input(308,"Hold-to-run key","F")
    table.insert(self.Connections,UIS.InputBegan:Connect(function(i,p)
        self:HandleKey(i,p)
    end))
end
function Angular:Destroy()
    self:Cancel()
    for _,con in ipairs(self.Connections) do con:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end
return Angular
