--!strict
-- Client-only proportional Roblox character scale reference. The mannequin
-- is a visual measuring aid, not authored geometry, a weld, or a physics body.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local CameraAimRay=require(script.Parent:WaitForChild("CameraAimRay"))
local Config=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BuildConfig"))

local ScaleGhost={}
ScaleGhost.__index=ScaleGhost

local BODY=Color3.fromRGB(125,150,167)
local HEAD=Color3.fromRGB(166,187,199)
local HEIGHT=5.2 -- ordinary Roblox avatar approximation, in real studs

local function part(model,name,size,offset,color,shape)
    local p=Instance.new("Part")
    p.Name=name
    p.Size=size
    p.Shape=shape or Enum.PartType.Block
    p.Color=color
    p.Material=Enum.Material.SmoothPlastic
    p.Transparency=0.50
    p.Reflectance=0
    p.Anchored=true
    p.CanCollide=false
    p.CanTouch=false
    p.CanQuery=false
    p.CastShadow=false
    p.CFrame=CFrame.new(offset)
    p:SetAttribute("OPENWORKS_VisualOnly",true)
    p.Parent=model
    return p
end

function ScaleGhost.new()
    return setmetatable({
        Model=nil,Visible=false,Moving=false,
        LastPose=CFrame.identity,Connection=nil,
    },ScaleGhost)
end

function ScaleGhost:Make()
    if self.Model then return self.Model end
    local model=Instance.new("Model")
    model.Name="OPENWORKS_CharacterScaleGhost"
    model:SetAttribute("OPENWORKS_VisualOnly",true)
    -- Poses are relative to FEET on the floor, not the humanoid root.
    part(model,"Torso",Vector3.new(1.7,1.9,0.84),
        Vector3.new(0,3.30,0),BODY)
    part(model,"Head",Vector3.new(1.03,1.03,1.03),
        Vector3.new(0,4.68,0),HEAD,Enum.PartType.Ball)
    part(model,"LeftArm",Vector3.new(0.55,2.25,0.62),
        Vector3.new(-1.18,3.12,0),BODY)
    part(model,"RightArm",Vector3.new(0.55,2.25,0.62),
        Vector3.new(1.18,3.12,0),BODY)
    part(model,"LeftLeg",Vector3.new(0.72,2.35,0.77),
        Vector3.new(-0.43,1.18,0),BODY)
    part(model,"RightLeg",Vector3.new(0.72,2.35,0.77),
        Vector3.new(0.43,1.18,0),BODY)
    model.WorldPivot=CFrame.identity
    self.Model=model
    return model
end

function ScaleGhost:Show(value)
    self.Visible=value
    self.Moving=false
    if value then
        local model=self:Make()
        local initial=self.LastPose
        if initial==CFrame.identity then
            local player=game:GetService("Players").LocalPlayer
            local plot=player:GetAttribute("OPENWORKS_PlotOrigin")
            initial=CFrame.new(if typeof(plot)=="Vector3"
                then plot+Vector3.new(0,0.05,0) else Vector3.new(0,0.05,0))
            self.LastPose=initial
        end
        model.Parent=workspace
        model:PivotTo(initial)
    elseif self.Model then
        self.Model.Parent=nil
    end
end

function ScaleGhost:Toggle()
    self:Show(not self.Visible)
    return self.Visible
end

function ScaleGhost:BeginMove()
    if not self.Visible then self:Show(true) end
    self.Moving=true
end

function ScaleGhost:CancelMove()
    self.Moving=false
    if self.Model then self.Model:PivotTo(self.LastPose) end
end

function ScaleGhost:Place()
    if not self.Moving then return false end
    self.Moving=false
    if self.Model then self.LastPose=self.Model:GetPivot() end
    return true
end

function ScaleGhost:Update()
    if not self.Moving or not self.Model then return end
    local camera=workspace.CurrentCamera
    if not camera then return end
    local ray=CameraAimRay.Ray(camera)
    if not ray then return end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={self.Model,
        game:GetService("Players").LocalPlayer.Character}
    local result=workspace:Raycast(ray.Origin,ray.Direction,params)
    local location=result and result.Position
    if not location then
        local dir=ray.Direction.Unit
        if dir.Y< -0.001 then
            local dist=-ray.Origin.Y/dir.Y
            if dist>=0 and dist<=256 then
                location=ray.Origin+dir*dist
            end
        end
    end
    if location then
        -- Local ghost never enters construction selection or collision tests.
        self.Model:PivotTo(CFrame.new(location+Vector3.new(0,0.025,0)))
    end
end

function ScaleGhost:Start()
    if self.Connection then return end
    self.Connection=RunService.RenderStepped:Connect(function()
        self:Update()
    end)
end

function ScaleGhost:Destroy()
    if self.Connection then self.Connection:Disconnect() end
    self.Connection=nil
    if self.Model then self.Model:Destroy() end
    self.Model=nil
end

return ScaleGhost
