--!strict
-- Pure world-space decorative language: understated satin finish,
-- ground collars and mechanical-axis guide marks. No screen GUI.
-- Never participates in raycasts, contact or simulation authority.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local constructor = ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Config = require(constructor:WaitForChild("BuildConfig"))
local Alignment = require(constructor:WaitForChild("AlignmentMath"))

local localPlayer = Players.LocalPlayer
local Visuals = {}
Visuals.__index = Visuals

local GROUNDED=Color3.fromRGB(57,212,127)
local MOVABLE=Color3.fromRGB(252,160,73)
local AXIS = Color3.fromRGB(92, 189, 228)
local GEAR = Color3.fromRGB(209, 180, 124)

local function accentPart(parent, size)
    local part = Instance.new("Part")
    part.Name = "OPENWORKS_GeometryGuide"
    part.Size = size
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Transparency = 0.18
    part.Color = AXIS
    part.Parent = parent
    return part
end

local function cylinderBetween(part, a, b, radius)
    local delta = b-a
    if delta.Magnitude < 0.001 then return end
    part.Size = Vector3.new(delta.Magnitude,radius,radius)
    part.CFrame = CFrame.lookAt((a+b)*0.5,b)
        * CFrame.Angles(0,math.pi/2,0)
end

function Visuals.new()
    local folder = Instance.new("Folder")
    folder.Name = "OPENWORKS_PhysicalGuides"
    folder.Parent = workspace
    return setmetatable({Folder=folder, Ground={}, Joints={},
        LastUpdate=0,Connections={}},Visuals)
end

function Visuals:GroundCue(key)
    local ring = Instance.new("Folder")
    ring.Name = "BodyStatus_"..key
    ring.Parent = self.Folder
    local bars = {}
    for i=1,4 do
        local p = accentPart(ring,Vector3.new(0.1,0.025,0.025))
        p.Color = GROUNDED
        p.Transparency = 0.17
        table.insert(bars,p)
    end
    return {root=ring,bars=bars}
end

function Visuals:JointCue(id)
    local parent = Instance.new("Folder")
    parent.Name = "Joint_"..id
    parent.Parent = self.Folder
    local shaft = accentPart(parent,Vector3.new(0.1,0.03,0.03))
    local collar = accentPart(parent,Vector3.new(0.045,0.11,0.11))
    collar.Shape = Enum.PartType.Cylinder
    return {root=parent,shaft=shaft,collar=collar}
end

function Visuals:Update()
    -- Live simulation replaces authored bodies with moving clones.
    -- Hide construction guides to avoid ghost axes at old edit positions.
    if localPlayer:GetAttribute("OPENWORKS_Simulating")==true then
        self.Folder.Parent=nil
        return
    end
    if not self.Folder.Parent then self.Folder.Parent=workspace end
    local built = workspace:FindFirstChild(Config.FolderName)
    if not built then return end
    local models={}
    local groups={}
    for _,model in ipairs(built:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==localPlayer.UserId then
            local id = model:GetAttribute("InstanceId")
            if type(id)=="string" then models[id]=model end
            local key=model:GetAttribute("ComponentId") or id
            if key then
                groups[key]=groups[key] or {models={},grounded=false}
                table.insert(groups[key].models,model)
                if model:GetAttribute("Grounded")==true then
                    groups[key].grounded=true
                end
            end
        end
    end
    for key,cue in pairs(self.Ground) do
        if not groups[key] then cue.root:Destroy() self.Ground[key]=nil end
    end
    for key,status in pairs(groups) do
        local cue=self.Ground[key]
        if not cue then
            cue=self:GroundCue(key)
            self.Ground[key]=cue
        end
        for _,bar in ipairs(cue.bars) do
            bar.Color=if status.grounded then GROUNDED else MOVABLE
        end
        local low=Vector3.new(math.huge,math.huge,math.huge)
        local high=Vector3.new(-math.huge,-math.huge,-math.huge)
        for _,model in ipairs(status.models) do
            for _,part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    local r=part.Size.Magnitude * 0.5
                    low=Vector3.new(math.min(low.X,part.Position.X-r),
                        math.min(low.Y,part.Position.Y-r),
                        math.min(low.Z,part.Position.Z-r))
                    high=Vector3.new(math.max(high.X,part.Position.X+r),
                        math.max(high.Y,part.Position.Y+r),
                        math.max(high.Z,part.Position.Z+r))
                end
            end
        end
        if low.X~=math.huge then
            local center=(low+high)*0.5
            local radius=math.max(high.X-low.X, high.Z-low.Z)*0.45+0.15
            local y=low.Y-0.045
            for i,bar in ipairs(cue.bars) do
                local a=(i-1)*math.pi/2
                local p=center+Vector3.new(math.cos(a)*radius,y-center.Y,math.sin(a)*radius)
                local tangent=Vector3.new(-math.sin(a),0,math.cos(a))
                cylinderBetween(bar,p-tangent*0.11,p+tangent*0.11,0.032)
            end
        end
    end

    local joints=workspace:FindFirstChild("OPENWORKS_Relationships")
    local active={}
    if joints then
        for _,folder in ipairs(joints:GetChildren()) do
            if folder:GetAttribute("OwnerUserId")~=localPlayer.UserId then continue end
            local id=folder:GetAttribute("RelationId")
            local target=models[folder:GetAttribute("TargetId")]
            local source=models[folder:GetAttribute("SourceId")]
            if type(id)~="string" or not source or not target then continue end
            active[id]=true
            local cue=self.Joints[id]
            if not cue then cue=self:JointCue(id) self.Joints[id]=cue end
            local kind=folder:GetAttribute("Kind")
            if kind=="Gear" then
                cue.shaft.Color=GEAR
                cue.collar.Color=GEAR
                cylinderBetween(cue.shaft,target:GetPivot().Position,
                    source:GetPivot().Position,0.035)
                cue.collar.CFrame=source:GetPivot()
            else
                local axis=Alignment.TargetAxis(target)
                if axis then
                    local accent=if kind=="Spring" then MOVABLE
                        elseif kind=="Bolt" then GEAR
                        elseif kind=="Weld" then GROUNDED else AXIS
                    cue.shaft.Color=accent
                    cue.collar.Color=accent
                    cue.shaft.Transparency=0.18
                    local point=target:GetPivot().Position
                    local vector=target:GetPivot():VectorToWorldSpace(axis)
                    local reach=math.min(1.5,math.max(0.3,source.PrimaryPart.Size.X*0.7))
                    cylinderBetween(cue.shaft,point-vector*reach,
                        point+vector*reach,0.024)
                    cue.collar.CFrame=CFrame.new(point)
                        * (target:GetPivot().Rotation)
                else
                    if kind=="Spring" or kind=="Weld" then
                        local accent=if kind=="Spring" then MOVABLE else GROUNDED
                        cue.shaft.Color=accent
                        cue.collar.Color=accent
                        cue.shaft.Transparency=0.16
                        cylinderBetween(cue.shaft,target:GetPivot().Position,
                            source:GetPivot().Position,0.028)
                        cue.collar.CFrame=source:GetPivot()
                    else
                        cue.shaft.Transparency=1
                    end
                end
            end
        end
    end
    for key,cue in pairs(self.Joints) do
        if not active[key] then cue.root:Destroy() self.Joints[key]=nil end
    end
end

function Visuals:Start()
    -- Studio-generated workshop already supplies its enclosing workspace.
    -- Apply light visual grading locally, rather than modifying physical
    -- collisions, global environment, or user camera optics.
    local grade=Lighting:FindFirstChild("OPENWORKS_IndustrialGrade")
    if not grade then
        grade=Instance.new("ColorCorrectionEffect")
        grade.Name="OPENWORKS_IndustrialGrade"
        grade.Brightness=0.012
        grade.Contrast=0.075
        grade.Saturation=-0.055
        grade.TintColor=Color3.fromRGB(230,238,246)
        grade.Parent=Lighting
    end
    self.Grade=grade
    table.insert(self.Connections,RunService.RenderStepped:Connect(function()
        if os.clock()-self.LastUpdate<0.12 then return end
        self.LastUpdate=os.clock()
        self:Update()
    end))
end

function Visuals:Destroy()
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    self.Folder:Destroy()
end

return Visuals
