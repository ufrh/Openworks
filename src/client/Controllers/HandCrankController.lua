--!strict
-- Hold LMB on a physical HandCrank in Simulate to apply a constant-speed,
-- torque-limited drive. Releasing LMB or losing tool/simulation stops torque.
-- No drag gesture, mouse delta, camera freeze, or arbitrary client speed.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Grid=require(Construction:WaitForChild("GridMath"))
local Crank=require(Construction:WaitForChild("HandCrankMath"))
local player=Players.LocalPlayer

local PULSE_PERIOD=0.1
local Controller={}
Controller.__index=Controller

function Controller.new(assembly)
    return setmetatable({
        Assembly=assembly,
        Starting=false,
        Holding=false,
        ActiveId=nil,
        SessionToken=0,
        PulseTime=0,
        Connections={},
        Destroyed=false,
        Remote=RS:WaitForChild("OPENWORKS_CrankControl"),
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
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
    local node=hit and hit.Instance
    while node and node.Parent~=folder do
        node=node.Parent
    end
    if not node or not node:IsA("Model")
        or node:GetAttribute("OwnerUserId")~=player.UserId then
        return nil
    end
    if Crank.IsCrank(node) then return node end

    -- Aim at ANY part of your simulated mechanism when it contains exactly
    -- one hand crank. The long shaft, gear, or housing can obscure its
    -- small handle, making the original direct-hit-only control unusable.
    -- Do not guess a crank when multiple independent cranks are present.
    local only=nil
    for _,candidate in ipairs(folder:GetChildren()) do
        if candidate:IsA("Model") and Crank.IsCrank(candidate)
            and candidate:GetAttribute("OwnerUserId")==player.UserId then
            if only then return nil end
            only=candidate
        end
    end
    return only
end

function Controller:Release()
    self.Holding=false
    self.SessionToken+=1
    self.Starting=false
    local id=self.ActiveId
    self.ActiveId=nil
    self.PulseTime=0
    if id then
        -- Release is a one-way event; it is never blocked by the normal
        -- construction action cooldown or waiting for an InvokeServer reply.
        self.Remote:FireServer(id,0,false,true)
    end
end

function Controller:TryGrab()
    if self.Destroyed then return false end
    if self.Holding or self.Starting then return true end
    if self.Assembly.Mode~="Simulate"
        or not self.Assembly:IsSimulating()
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
        or player:GetAttribute("OPENWORKS_SimulationPaused")==true
        or not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        return false
    end
    local target=self:CrankAtCenter()
    if not target then return false end
    local id=target:GetAttribute("InstanceId")
    if type(id)~="string" then return false end

    self.Holding=true
    self.Starting=true
    self.SessionToken+=1
    self.ActiveId=id
    local token=self.SessionToken
    task.spawn(function()
        local ok=self.Assembly:Request({action="BeginCrank",crankId=id})
        if self.Destroyed then
            if ok then self.Remote:FireServer(id,0,false,true) end
            return
        end
        -- The user may release while the RemoteFunction is in flight. Never
        -- let the delayed server response leave the motor running afterward.
        if token~=self.SessionToken or not self.Holding
            or not UserInputService:IsMouseButtonPressed(
                Enum.UserInputType.MouseButton1) then
            if ok then self.Remote:FireServer(id,0,false,true) end
            return
        end
        self.Starting=false
        if not ok then
            self:Release()
            return
        end
        self.PulseTime=0
        self.Remote:FireServer(id,0,true,false)
    end)
    return true
end

function Controller:Start()
    -- Tool.Activated is retained as a fallback; InputBegan also handles
    -- first-person mouse clicks that Roblox consumes before Tool.Activated.
    table.insert(self.Connections,UserInputService.InputBegan:Connect(function(input,processed)
        if processed or input.UserInputType~=Enum.UserInputType.MouseButton1
            or UserInputService:GetFocusedTextBox() then return end
        self:TryGrab()
    end))
    table.insert(self.Connections,UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            self:Release()
        end
    end))
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        if not self.Holding then return end
        if self.Assembly.Mode~="Simulate"
            or not self.Assembly:IsSimulating()
            or player:GetAttribute("OPENWORKS_SimulationPaused")==true
            or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
            or not UserInputService:IsMouseButtonPressed(
                Enum.UserInputType.MouseButton1) then
            self:Release()
            return
        end
        if self.Starting or not self.ActiveId then return end
        self.PulseTime+=dt
        if self.PulseTime>=PULSE_PERIOD then
            self.PulseTime=0
            self.Remote:FireServer(self.ActiveId,0,true,false)
        end
    end))
end

function Controller:Destroy()
    self:Release()
    self.Destroyed=true
    for _,connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)
end

return Controller
