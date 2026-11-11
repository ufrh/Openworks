--!strict
-- Hold Q/E while aiming at a grounded rack guide or its rack to push
-- linearly. Authenticated server input is only direction/liveness.
-- The kinematic graph converts rack translation back into pinion RPM.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))

local Controller={}
Controller.__index=Controller
local HEARTBEAT_INTERVAL=0.1

function Controller.new(assembly)
    return setmetatable({
        Assembly=assembly,
        Remote=ReplicatedStorage:WaitForChild("OPENWORKS_RackControl"),
        Id=nil,Direction=0,KeyCode=nil,Holding=false,Starting=false,
        Token=0,Elapsed=0,Connections={},Destroyed=false,
    },Controller)
end

function Controller:FindAim()
    local folder=workspace:FindFirstChild("OPENWORKS_Simulated")
    local simulation=folder
        and folder:FindFirstChild("Simulation_"..tostring(player.UserId))
    local camera=workspace.CurrentCamera
    if not simulation or not camera then return nil end
    local ray=camera:ViewportPointToRay(
        camera.ViewportSize.X*0.5,camera.ViewportSize.Y*0.5)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={simulation}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction*70,params)
    local node=hit and hit.Instance
    while node and node.Parent~=simulation do
        node=node.Parent
    end
    if not node or not node:IsA("Model")
        or node:GetAttribute("OwnerUserId")~=player.UserId then
        return nil
    end
    if GearMath.Kind(node)=="Rack" then return node end
    if GearMath.Kind(node)~="RackGuide" then return nil end
    local found=nil
    for _,candidate in ipairs(simulation:GetChildren()) do
        if candidate:IsA("Model")
            and candidate:GetAttribute("OwnerUserId")==player.UserId
            and GearMath.Kind(candidate)=="Rack"
            and GearMath.AutoGuideStatus(candidate,node) then
            if found then return nil end
            found=candidate
        end
    end
    return found
end

function Controller:Release()
    self.Token+=1
    local id=self.Id
    local dir=self.Direction
    self.Id=nil
    self.KeyCode=nil
    self.Direction=0
    self.Holding=false
    self.Starting=false
    self.Elapsed=0
    if id then self.Remote:FireServer(id,dir,false,true) end
end

function Controller:TryPush(key)
    if self.Destroyed or self.Assembly.Mode~="Simulate"
        or not self.Assembly:IsSimulating()
        or player:GetAttribute("OPENWORKS_SimulationPaused")==true
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
        or UserInputService:GetFocusedTextBox() then return false end
    local dir=if key==Enum.KeyCode.Q then -1
        elseif key==Enum.KeyCode.E then 1 else 0
    if dir==0 or not UserInputService:IsKeyDown(key) then return false end
    if self.Holding then
        if self.KeyCode==key then return true end
        self:Release()
    end
    local model=self:FindAim()
    if not model then return false end
    local id=model:GetAttribute("InstanceId")
    if type(id)~="string" then return false end
    self.Id=id
    self.KeyCode=key
    self.Direction=dir
    self.Holding=true
    self.Starting=true
    self.Token+=1
    local token=self.Token
    task.spawn(function()
        local ok=self.Assembly:Request({
            action="BeginRack",rackId=id,direction=dir,
        })
        if self.Destroyed or token~=self.Token
            or not self.Holding or not UserInputService:IsKeyDown(key) then
            if ok then self.Remote:FireServer(id,dir,false,true) end
            return
        end
        self.Starting=false
        if not ok then self:Release() return end
        self.Elapsed=0
        self.Remote:FireServer(id,dir,true,false)
    end)
    return true
end

function Controller:Start()
    table.insert(self.Connections,UserInputService.InputBegan:Connect(
        function(input,processed)
            if processed then return end
            if input.KeyCode==Enum.KeyCode.Q
                or input.KeyCode==Enum.KeyCode.E then
                self:TryPush(input.KeyCode)
            end
        end))
    table.insert(self.Connections,UserInputService.InputEnded:Connect(
        function(input)
            if input.KeyCode==self.KeyCode then self:Release() end
        end))
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        if not self.Holding then return end
        if self.Assembly.Mode~="Simulate"
            or not self.Assembly:IsSimulating()
            or player:GetAttribute("OPENWORKS_SimulationPaused")==true
            or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
            or not self.KeyCode
            or not UserInputService:IsKeyDown(self.KeyCode) then
            self:Release()
            return
        end
        if self.Starting or not self.Id then return end
        self.Elapsed+=dt
        if self.Elapsed>=HEARTBEAT_INTERVAL then
            self.Elapsed=0
            self.Remote:FireServer(self.Id,self.Direction,true,false)
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
