--!strict
-- Physical hand crank: aim and click once to start a fixed-speed,
-- torque-limited drive. Click the same crank again to stop.
-- No mouse dragging, camera freezing, or per-frame input remote.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Grid=require(Construction:WaitForChild("GridMath"))
local Crank=require(Construction:WaitForChild("HandCrankMath"))
local player=Players.LocalPlayer

local Controller={}
Controller.__index=Controller

function Controller.new(assembly)
    return setmetatable({
        Assembly=assembly,
        Starting=false,
        SessionToken=0,
        Destroyed=false,
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
    local member=hit and hit.Instance:FindFirstAncestorOfClass("Model")
    if member and Crank.IsCrank(member)
        and member:GetAttribute("OwnerUserId")==player.UserId then
        return member
    end
    return nil
end

function Controller:TryGrab()
    if self.Destroyed then return false end
    if self.Starting then return true end
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
    self.SessionToken+=1
    local token=self.SessionToken
    task.spawn(function()
        -- BeginCrank is intentionally a server-authoritative TOGGLE.
        -- The server validates ownership, assembly, coupling and range.
        self.Assembly:Request({action="BeginCrank",crankId=id})
        if self.SessionToken==token and not self.Destroyed then
            self.Starting=false
        end
    end)
    return true
end

function Controller:Start()
    -- There is no held input state to bind or release.
end

function Controller:Destroy()
    self.Destroyed=true
    self.SessionToken+=1
    self.Starting=false
end

return Controller
