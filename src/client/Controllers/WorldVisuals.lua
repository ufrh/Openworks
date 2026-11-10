--!strict
-- Pure world-space decorative language: understated satin finish,
-- ground collars and mechanical-axis guide marks. No screen GUI.
-- Never participates in raycasts, contact or simulation authority.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local constructor = ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Config = require(constructor:WaitForChild("BuildConfig"))
local Alignment = require(constructor:WaitForChild("AlignmentMath"))
local SpringMath = require(constructor:WaitForChild("SpringMath"))
local Grid = require(constructor:WaitForChild("GridMath"))

local localPlayer = Players.LocalPlayer
local Visuals = {}
Visuals.__index = Visuals

local GROUNDED=Color3.fromRGB(57,212,127)
local MOVABLE=Color3.fromRGB(252,160,73)
local AXIS = Color3.fromRGB(92, 189, 228)
local GEAR = Color3.fromRGB(209, 180, 124)
local SLIDER = Color3.fromRGB(74, 196, 235)
local BEARING = Color3.fromRGB(177, 132, 248)
local SPRING = Color3.fromRGB(255, 153, 47)
local WELD = Color3.fromRGB(73, 223, 150)
local GUIDE = Color3.fromRGB(102, 220, 240)

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
    local parent=Instance.new("Folder")
    parent.Name="Joint_"..id
    parent.Parent=self.Folder
    local shaft=accentPart(parent,Vector3.new(0.1,0.025,0.025))
    shaft.Transparency=0.35
    local collar=accentPart(parent,Vector3.new(0.05,0.14,0.14))
    collar.Shape=Enum.PartType.Cylinder
    collar.Transparency=0.12
    local function orb()
        local part=accentPart(parent,Vector3.new(0.095,0.095,0.095))
        part.Shape=Enum.PartType.Ball
        part.Transparency=0.08
        return part
    end
    local mark0,mark1=orb(),orb()
    local stop0=accentPart(parent,Vector3.new(0.025,0.18,0.18))
    local stop1=accentPart(parent,Vector3.new(0.025,0.18,0.18))
    stop0.Shape=Enum.PartType.Cylinder
    stop1.Shape=Enum.PartType.Cylinder
    local tag=Instance.new("BillboardGui")
    tag.Name="OPENWORKS_RelationshipLabel"
    tag.Adornee=collar
    tag.Size=UDim2.fromOffset(158,26)
    tag.StudsOffsetWorldSpace=Vector3.new(0,0.35,0)
    tag.AlwaysOnTop=false
    tag.MaxDistance=42
    tag.LightInfluence=0
    tag.Parent=parent
    local text=Instance.new("TextLabel")
    text.Name="Label"
    text.Size=UDim2.fromScale(1,1)
    text.BackgroundColor3=Color3.fromRGB(19,28,36)
    text.BackgroundTransparency=0.16
    text.BorderSizePixel=0
    text.Font=Enum.Font.GothamBold
    text.TextSize=10
    text.TextColor3=Color3.fromRGB(234,243,249)
    text.TextStrokeTransparency=1
    text.Parent=tag
    local round=Instance.new("UICorner")
    round.CornerRadius=UDim.new(0,6)
    round.Parent=text
    local stroke=Instance.new("UIStroke")
    stroke.Thickness=1
    stroke.Transparency=0.38
    stroke.Parent=text
    return {root=parent,shaft=shaft,collar=collar,
        mark0=mark0,mark1=mark1,stop0=stop0,stop1=stop1,
        text=text,stroke=stroke,fitMarkers={},fitData={},fitJSON=nil}
end

local function oriented(center,axis)
    local dir=axis.Magnitude>0.0001 and axis.Unit or Vector3.xAxis
    local reference=if math.abs(dir.Y)<0.9 then Vector3.yAxis else Vector3.zAxis
    local up=(reference-dir*dir:Dot(reference)).Unit
    return CFrame.fromMatrix(center,dir,up,dir:Cross(up))
end

local function drawEnd(part,position)
    part.CFrame=CFrame.new(position)
end

function Visuals:UpdateJoint(cue,relation,source,target,models)
    local kind=relation:GetAttribute("Kind")
    local tint=if kind=="Spring" then SPRING
        elseif kind=="Weld" then WELD
        elseif kind=="Bolt" or kind=="Gear" then GEAR
        elseif kind=="Bearing" then BEARING
        elseif kind=="Slider" then SLIDER else AXIS
    local a,b=target:GetPivot().Position,source:GetPivot().Position
    local localAxis=Alignment.TargetAxis(target)
    local direction=if localAxis
        then target:GetPivot():VectorToWorldSpace(localAxis).Unit
        elseif (b-a).Magnitude>0.0001
        then (b-a).Unit else Vector3.yAxis
    if kind=="Spring" then
        a,b=SpringMath.Frames(source,target,"General")
        if (b-a).Magnitude>0.0001 then direction=(b-a).Unit end
    end
    local center=(a+b)*0.5
    local guideCount=relation:GetAttribute("FitPointCount") or 0
    local labels={Spring="SPRING",Weld="WELD",Bolt="BOLT",Gear="GEARS",
        Bearing="ROTATE",Slider="SLIDE",Cylindrical="SLIDE + ROTATE",
        Fixed="FIXED"}
    cue.text.Text=(labels[kind] or tostring(kind):upper())
        ..(if guideCount>1 then "  ·  "..guideCount.." FITS" else "")
    cue.stroke.Color=tint
    for _,part in ipairs({cue.shaft,cue.collar,cue.mark0,cue.mark1}) do
        part.Color=tint
    end
    drawEnd(cue.mark0,a)
    drawEnd(cue.mark1,b)
    cue.collar.CFrame=oriented(center,direction)
    if kind=="Slider" or kind=="Bearing" or kind=="Cylindrical" then
        local reach=math.min(1.8,math.max(0.3,
            math.min(source.PrimaryPart.Size.Magnitude,
                target.PrimaryPart.Size.Magnitude)*0.4))
        cylinderBetween(cue.shaft,center-direction*reach,
            center+direction*reach,0.024)
    else
        cylinderBetween(cue.shaft,a,b,if kind=="Spring" then 0.012 else 0.025)
    end
    local travel=relation:GetAttribute("FitTravelU")
    local hasStop=(kind=="Slider" or kind=="Cylindrical")
        and type(travel)=="number" and travel>0
    for index,stop in ipairs({cue.stop0,cue.stop1}) do
        stop.Color=tint
        stop.Transparency=if hasStop then 0.22 else 1
        if hasStop then
            local sign=if index==1 then -1 else 1
            stop.CFrame=oriented(center+direction*travel*Grid.Unit*sign,
                direction)
        end
    end
    local json=relation:GetAttribute("FitPointsJSON")
    if json~=cue.fitJSON then
        cue.fitJSON=json
        cue.fitData={}
        if type(json)=="string" and #json<12000 then
            local ok,result=pcall(function() return HttpService:JSONDecode(json) end)
            if ok and type(result)=="table" then cue.fitData=result end
        end
    end
    local n=0
    for _,entry in ipairs(cue.fitData) do
        if n>=32 then break end
        n+=1
        local dot=cue.fitMarkers[n]
        if not dot then
            dot=accentPart(cue.root,Vector3.new(0.12,0.12,0.12))
            dot.Shape=Enum.PartType.Ball
            dot.Color=GUIDE
            dot.Transparency=0.07
            cue.fitMarkers[n]=dot
        end
        local moving=models[entry.movingId]
        local stationary=models[entry.stationaryId]
        if moving and stationary then
            local bore=if Alignment.TargetAxis(moving) then moving
                elseif Alignment.TargetAxis(stationary) then stationary else nil
            dot.CFrame=bore and bore:GetPivot() or CFrame.new(stationary:GetPivot().Position)
            dot.Transparency=0.07
        else
            dot.Transparency=1
        end
    end
    for i=#cue.fitMarkers,n+1,-1 do
        cue.fitMarkers[i]:Destroy()
        table.remove(cue.fitMarkers,i)
    end
end

function Visuals:Update()
    -- Authored spring coils are construction-only visuals.
    local simulating=localPlayer:GetAttribute("OPENWORKS_Simulating")==true
    local authored=workspace:FindFirstChild("OPENWORKS_Relationships")
    if authored then
        for _,relation in ipairs(authored:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")==localPlayer.UserId
                and relation:GetAttribute("Kind")=="Spring" then
                local spring=relation:FindFirstChildOfClass("SpringConstraint")
                if spring then spring.Visible=not simulating end
            end
        end
    end
    -- Live simulation replaces authored bodies with moving clones.
    if simulating then
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
            self:UpdateJoint(cue,folder,source,target,models)
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
