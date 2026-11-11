--!strict
-- Manual rotary actuator. No overlay, circle widget, unlocked cursor, or
-- fake relationship motor. Aim at crank, HOLD LMB, move mouse horizontally.
-- Roblox first-person cursor remains centered throughout.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Config=require(RS:WaitForChild("Openworks"):WaitForChild("Construction")
    :WaitForChild("BuildConfig"))
local Crank=require(RS.Openworks.Construction:WaitForChild("HandCrankMath"))
local player=Players.LocalPlayer

local Controller={}
Controller.__index=Controller
local SEND_STEP=0.05
local SENSITIVITY=0.009
local RESPONSE=13

function Controller.new(assembly)
    return setmetatable({
        Assembly=assembly,
        ActiveId=nil,
        Pressed=false,
        Starting=false,
        SmoothSpeed=0,
        Accumulator=0,
        DeltaSum=0,
        SessionToken=0,
        CameraTypeBefore=nil,
        Connections={},
    },Controller)
end

function Controller:Running()
    local folder=workspace:FindFirstChild("OPENWORKS_Simulated")
    return folder and folder:FindFirstChild("Simulation_"..tostring(player.UserId))
end

function Controller:CrankAtCenter()
    local folder=self:Running()
    local camera=workspace.CurrentCamera
    if not folder or not camera then return nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={folder}
    params.IgnoreWater=true
    local ray=camera:ViewportPointToRay(
        camera.ViewportSize.X*0.5,camera.ViewportSize.Y*0.5)
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Config.PlotSize,params)
    local member=hit and hit.Instance:FindFirstAncestorOfClass("Model")
    if member and Crank.IsCrank(member)
        and member:GetAttribute("OwnerUserId")==player.UserId then
        return member
    end
    return nil
end

function Controller:TryGrab()
    if self.ActiveId or self.Starting then return true end
    if self.Assembly.Mode~="Simulate"
        or not self.Assembly:IsSimulating()
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true then
        return false
    end
    local target=self:CrankAtCenter()
    if not target then return false end
    local id=target:GetAttribute("InstanceId")
    if type(id)~="string" then return false end
    self.Starting=true
    self.Pressed=true
    self.SessionToken+=1
    local token=self.SessionToken
    -- The server grants manual torque only for a real welded crank.
    task.spawn(function()
        local accepted=self.Assembly:Request({action="BeginCrank",crankId=id})
        if self.SessionToken~=token then
            if accepted then
                self.Remote:FireServer(id,0,false,true)
            end
            return
        end
        self.Starting=false
        if not accepted then
            self.Pressed=false
            if self.Assembly.Properties then
                self.Assembly.Properties:InspectAtCenter()
            end
            return
        end
        if not self.Pressed then
            self.Remote:FireServer(id,0,false,true)
            self.Assembly.Properties:InspectAtCenter()
            return
        end
        self.ActiveId=id
        self.SmoothSpeed=0
        self.Accumulator=0
        self.DeltaSum=0
        player:SetAttribute("OPENWORKS_CrankActive",true)
        -- Hold the existing view steady during input. Unlike a cursor
        -- circle, movement is unbounded, doesn't hit screen edges, and
        -- operates with MouseBehavior.LockCenter.
        local camera=workspace.CurrentCamera
        if camera then
            self.CameraTypeBefore=camera.CameraType
            camera.CameraType=Enum.CameraType.Scriptable
        end
        UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
        UIS.MouseIconEnabled=false
    end)
    return true
end

function Controller:Release()
    local id=self.ActiveId
    self.SessionToken+=1
    self.Starting=false
    self.ActiveId=nil
    self.Pressed=false
    self.SmoothSpeed=0
    self.Accumulator=0
    self.DeltaSum=0
    player:SetAttribute("OPENWORKS_CrankActive",false)
    local camera=workspace.CurrentCamera
    if camera and self.CameraTypeBefore~=nil then
        camera.CameraType=self.CameraTypeBefore
    end
    self.CameraTypeBefore=nil
    if id and self.Remote then
        self.Remote:FireServer(id,0,false,true)
    end
end

function Controller:Tick(dt)
    if not self.ActiveId then return end
    if self.Assembly.Mode~="Simulate"
        or not self.Assembly:IsSimulating()
        or not self.Pressed then
        self:Release()
        return
    end
    -- Relative pixel velocity, filtered for continuous hand control.
    -- Angular torque is still capped by the server, so a jam stalls.
    local delta=UIS:GetMouseDelta().X
    local frameSpeed=math.clamp(
        delta/math.max(dt,1/120)*SENSITIVITY,
        -Crank.MaxAngularSpeed,Crank.MaxAngularSpeed)
    local blend=1-math.exp(-RESPONSE*math.min(dt,0.1))
    self.SmoothSpeed+=(frameSpeed-self.SmoothSpeed)*blend
    self.Accumulator+=dt
    self.DeltaSum+=self.SmoothSpeed*dt
    if self.Accumulator>=SEND_STEP then
        local desired=self.DeltaSum/math.max(self.Accumulator,0.001)
        self.Remote:FireServer(self.ActiveId,desired,true,false)
        self.Accumulator=0
        self.DeltaSum=0
    end
end

function Controller:Start()
    self.Remote=RS:WaitForChild("OPENWORKS_CrankControl")
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        if self.ActiveId then
            self:Release()
        elseif self.Starting then
            self.Pressed=false
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
            if mode~="Simulate" then self:Release() end
        end))
end

function Controller:Destroy()
    self:Release()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
end

return Controller
