--!strict
-- UI v2 relationship indicators + grounded/movable bounds.
-- Drawing is local-only. The shared VisualFeedback service owns ALL boxes.
-- No helper Parts or persistent rigid/weld/gear adornments.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Config=require(construction:WaitForChild("BuildConfig"))
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local Grid=require(construction:WaitForChild("GridMath"))

local player=Players.LocalPlayer
local Visuals={}
Visuals.__index=Visuals

local BLUE=Color3.fromRGB(62,169,238)
local ORANGE=Color3.fromRGB(249,152,52)
local GREEN=Color3.fromRGB(76,222,124)
local MAX_BODIES=64

local function create(parent,class,name,color)
    local item=Instance.new(class)
    item.Name=name
    if item:IsA("HandleAdornment") then
        item.Color3=color or BLUE
        item.Transparency=0
        item.AlwaysOnTop=false
        item.Visible=false
    end
    item.Parent=parent
    return item
end

local function point(item,anchor,pos,radius,color)
    item.Adornee=anchor
    item.CFrame=anchor.CFrame:ToObjectSpace(CFrame.new(pos))
    item.Radius=radius
    item.Color3=color
    item.Visible=true
end

local function segment(item,anchor,a,b,color)
    local delta=b-a
    if delta.Magnitude<1e-5 then item.Visible=false return end
    item.Adornee=anchor
    item.CFrame=anchor.CFrame:ToObjectSpace(CFrame.lookAt(a,b))
    item.Length=delta.Magnitude
    item.Thickness=2
    item.Color3=color
    item.Visible=true
end

local function axisFor(target,source)
    local localAxis=Alignment.TargetAxis(target)
    if localAxis then
        local axis=target:GetPivot():VectorToWorldSpace(localAxis)
        if axis.Magnitude>1e-5 then return axis.Unit end
    end
    local diff=source:GetPivot().Position-target:GetPivot().Position
    return if diff.Magnitude>1e-5 then diff.Unit else Vector3.yAxis
end

function Visuals.new(feedback)
    local root=Instance.new("Folder")
    root.Name="OPENWORKS_JointVisualAdornments"
    root.Parent=workspace
    return setmetatable({
        Folder=root,Feedback=feedback,Joints={},GroundIds={},
        LastUpdate=0,Connections={},
    },Visuals)
end

function Visuals:JointCue(id)
    local folder=create(self.Folder,"Folder","Joint_"..id)
    local cue={Root=folder}
    cue.Origin=create(folder,"SphereHandleAdornment","FixedOrigin",GREEN)
    cue.Min=create(folder,"SphereHandleAdornment","TravelMin",GREEN)
    cue.Max=create(folder,"SphereHandleAdornment","TravelMax",GREEN)
    cue.Current=create(folder,"SphereHandleAdornment","Position",BLUE)
    cue.Rail=create(folder,"LineHandleAdornment","Travel",BLUE)
    cue.Arc={}
    for i=1,13 do
        cue.Arc[i]=create(folder,"LineHandleAdornment",
            "RotationArc_"..i,BLUE)
    end
    cue.Pow=create(folder,"BillboardGui","MotorLabel")
    cue.Pow.Size=UDim2.fromOffset(28,14)
    cue.Pow.AlwaysOnTop=false
    cue.Pow.Enabled=false
    local label=Instance.new("TextLabel")
    label.Name="POW"
    label.BackgroundTransparency=1
    label.Text="POW"
    label.TextSize=10
    label.Font=Enum.Font.GothamBold
    label.TextColor3=ORANGE
    label.Size=UDim2.fromScale(1,1)
    label.Parent=cue.Pow
    return cue
end

function Visuals:UpdateJoint(cue,relation,source,target)
    if not target.PrimaryPart or not source.PrimaryPart then return end
    local anchor=target.PrimaryPart
    local kind=relation:GetAttribute("Kind")
    local powered=kind=="Bearing" and relation:GetAttribute("MotorEnabled")==true
    local color=if powered then ORANGE else BLUE
    local center=target:GetPivot().Position
    local moving=source:GetPivot().Position
    local axis=axisFor(target,source)

    local rotational=kind=="Bearing" or kind=="Cylindrical"
    local linear=kind=="Slider" or kind=="Cylindrical"

    cue.Origin.Visible=rotational
    if rotational then point(cue.Origin,anchor,center,0.047,GREEN) end

    local travel=relation:GetAttribute("FitTravelU")
    local half=if type(travel)=="number" and travel>0
        then travel*Grid.Unit else 0
    -- A travel line shows the physical shaft-housing range. Authored limits
    -- narrow this range but do not extend beyond the underlying hardware.
    local lower=relation:GetAttribute("LowerLimit")
    local upper=relation:GetAttribute("UpperLimit")
    if relation:GetAttribute("LimitsEnabled")==true
        and type(lower)=="number" and type(upper)=="number"
        and lower<upper and half>0 then
        local lo=math.clamp(lower*Grid.Unit,-half,half)
        local hi=math.clamp(upper*Grid.Unit,-half,half)
        if hi>=lo then
            segment(cue.Rail,anchor,center+axis*lo,center+axis*hi,BLUE)
            point(cue.Min,anchor,center+axis*lo,0.055,GREEN)
            point(cue.Max,anchor,center+axis*hi,0.055,GREEN)
        else
            cue.Rail.Visible=false
            cue.Min.Visible=false
            cue.Max.Visible=false
        end
    elseif linear and half>0 then
        segment(cue.Rail,anchor,center-axis*half,center+axis*half,BLUE)
        point(cue.Min,anchor,center-axis*half,0.055,GREEN)
        point(cue.Max,anchor,center+axis*half,0.055,GREEN)
    else
        cue.Rail.Visible=false
        cue.Min.Visible=false
        cue.Max.Visible=false
    end
    cue.Current.Visible=linear
    if linear then
        local offset=(moving-center):Dot(axis)
        if half>0 then offset=math.clamp(offset,-half,half) end
        point(cue.Current,anchor,center+axis*offset,0.053,BLUE)
    end

    if rotational then
        local hint=if math.abs(axis:Dot(Vector3.yAxis))<0.9
            then Vector3.yAxis else Vector3.xAxis
        local u=axis:Cross(hint).Unit
        local v=axis:Cross(u).Unit
        local size=math.min(source.PrimaryPart.Size.Magnitude,
            target.PrimaryPart.Size.Magnitude)
        local radius=math.clamp(size*0.28,0.17,0.65)
        local function at(angle)
            return center+(u*math.cos(angle)+v*math.sin(angle))*radius
        end
        local steps=11
        local begin=-math.pi*0.5
        for i=1,steps do
            segment(cue.Arc[i],anchor,
                at(begin+math.pi*(i-1)/steps),
                at(begin+math.pi*i/steps),color)
        end
        local endPoint=at(math.pi*0.5)
        local tangent=-u
        local tail=endPoint-tangent*radius*0.23
        segment(cue.Arc[12],anchor,tail+axis*radius*0.14,endPoint,color)
        segment(cue.Arc[13],anchor,tail-axis*radius*0.14,endPoint,color)
        cue.Pow.Enabled=powered
        if powered then
            cue.Pow.Adornee=anchor
            cue.Pow.StudsOffsetWorldSpace=u*radius*0.72+v*radius*0.15
        end
    else
        for _,line in ipairs(cue.Arc) do line.Visible=false end
        cue.Pow.Enabled=false
    end
end

function Visuals:Update()
    local simulating=player:GetAttribute("OPENWORKS_Simulating")==true
    local authored=workspace:FindFirstChild("OPENWORKS_Relationships")
    if authored then
        for _,relation in ipairs(authored:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")==player.UserId
                and relation:GetAttribute("Kind")=="Spring" then
                local spring=relation:FindFirstChildOfClass("SpringConstraint")
                if spring then
                    spring.Visible=not simulating
                    pcall(function() spring.Color=BrickColor.new("Bright blue") end)
                end
            end
        end
    end
    local root=if simulating then
        (workspace:FindFirstChild("OPENWORKS_Simulated")
            and workspace.OPENWORKS_Simulated:FindFirstChild(
                "Simulation_"..tostring(player.UserId)))
        else workspace:FindFirstChild(Config.FolderName)

    local models={}
    if root then
        for _,model in ipairs(root:GetChildren()) do
            if model:IsA("Model")
                and model:GetAttribute("OwnerUserId")==player.UserId
                and model.PrimaryPart then
                local id=model:GetAttribute("InstanceId")
                if type(id)=="string" then models[id]=model end
            end
        end
    end

    -- A grounding visual is meaningful in assembly/simulation, not during
    -- ordinary Build painting or precision placement.
    local visibleGround=player:GetAttribute("OPENWORKS_PrimaryTool")
        =="AssemblySimulation"
    local nextIds={}
    local count=0
    if visibleGround and self.Feedback then
        for id,model in pairs(models) do
            if count>=MAX_BODIES then break end
            count+=1
            nextIds[id]=true
            local grounded=model:GetAttribute("Grounded")==true
            if simulating then
                local constructed=workspace:FindFirstChild(Config.FolderName)
                for _,original in ipairs(if constructed then constructed:GetChildren() else {}) do
                    if original:GetAttribute("InstanceId")==id then
                        grounded=original:GetAttribute("Grounded")==true
                        break
                    end
                end
            end
            self.Feedback:Set("ground",id,{model},
                if grounded then "grounded" else "free",false)
        end
    end
    if self.Feedback then
        for id in pairs(self.GroundIds) do
            if not nextIds[id] then self.Feedback:Remove("ground",id) end
        end
    end
    self.GroundIds=nextIds

    local active={}
    if not simulating and authored then
        for _,relation in ipairs(authored:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")~=player.UserId then continue end
            local kind=relation:GetAttribute("Kind")
            if kind~="Bearing" and kind~="Slider"
                and kind~="Cylindrical" then continue end
            local id=relation:GetAttribute("RelationId")
            local source=models[relation:GetAttribute("SourceId")]
            local target=models[relation:GetAttribute("TargetId")]
            if type(id)~="string" or not source or not target then continue end
            active[id]=true
            local cue=self.Joints[id]
            if not cue then cue=self:JointCue(id) self.Joints[id]=cue end
            self:UpdateJoint(cue,relation,source,target)
        end
    end
    for id,cue in pairs(self.Joints) do
        if not active[id] then
            cue.Root:Destroy()
            self.Joints[id]=nil
        end
    end
end

function Visuals:Start()
    table.insert(self.Connections,RunService.RenderStepped:Connect(function()
        if os.clock()-self.LastUpdate<0.14 then return end
        self.LastUpdate=os.clock()
        self:Update()
    end))
end

function Visuals:Destroy()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    if self.Feedback then self.Feedback:Clear("ground") end
    for _,cue in pairs(self.Joints) do cue.Root:Destroy() end
    self.Folder:Destroy()
end

return Visuals
