--!strict
-- Studio-style 3D feedback. NO helper Parts, BillboardGui or world text.
-- Mechanisms are shown with native HandleAdornments attached to existing
-- geometry; grounded/movable bodies use a literal fill-only Highlight.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Config=require(construction:WaitForChild("BuildConfig"))
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local SpringMath=require(construction:WaitForChild("SpringMath"))
local Grid=require(construction:WaitForChild("GridMath"))

local player=Players.LocalPlayer
local Visuals={}
Visuals.__index=Visuals

local GROUNDED=Color3.fromRGB(59,211,132)
local MOVABLE=Color3.fromRGB(248,151,61)
local COLORS={
    Spring=Color3.fromRGB(255,161,52),
    Weld=Color3.fromRGB(104,207,159),
    Fixed=Color3.fromRGB(104,207,159),
    Bolt=Color3.fromRGB(208,173,109),
    Gear=Color3.fromRGB(208,173,109),
    Bearing=Color3.fromRGB(158,146,229),
    Slider=Color3.fromRGB(96,185,238),
    Cylindrical=Color3.fromRGB(96,185,238),
}
local MAX_HIGHLIGHTS=180

local function newAdornment(parent,class,name)
    local item=Instance.new(class)
    item.Name=name
    item.Color3=Color3.fromRGB(173,187,201)
    item.Transparency=0.18
    item.AlwaysOnTop=false
    item.Visible=true
    item.Parent=parent
    return item
end

local function frameOnAxis(position,direction)
    local y=if direction.Magnitude>1e-5 then direction.Unit else Vector3.yAxis
    local hint=if math.abs(y:Dot(Vector3.yAxis))<0.9
        then Vector3.yAxis else Vector3.xAxis
    local x=hint:Cross(y).Unit
    return CFrame.fromMatrix(position,x,y,x:Cross(y))
end

local function put(adornment,part,frame)
    adornment.Adornee=part
    adornment.CFrame=part.CFrame:ToObjectSpace(frame)
end

local function cylinder(adornment,part,startPoint,endPoint,radius)
    local diff=endPoint-startPoint
    local distance=diff.Magnitude
    adornment.Visible=distance>1e-4
    if not adornment.Visible then return end
    adornment.Radius=radius
    adornment.Height=distance
    put(adornment,part,frameOnAxis((startPoint+endPoint)*0.5,diff))
end

local function dot(adornment,part,point,radius)
    adornment.Visible=true
    adornment.Radius=radius
    put(adornment,part,CFrame.new(point))
end

function Visuals.new()
    local root=Instance.new("Folder")
    root.Name="OPENWORKS_VisualAdornments"
    root.Parent=workspace
    return setmetatable({
        Folder=root,
        Ground={},
        Joints={},
        LastUpdate=0,
        Connections={},
    },Visuals)
end

function Visuals:GroundCue(model)
    local highlight=Instance.new("Highlight")
    highlight.Name="OPENWORKS_GroundStatus"
    highlight.Adornee=model
    highlight.DepthMode=Enum.HighlightDepthMode.Occluded
    highlight.FillTransparency=0.83
    highlight.OutlineTransparency=1
    highlight.Parent=self.Folder
    return highlight
end

function Visuals:JointCue(id)
    local root=Instance.new("Folder")
    root.Name="JointAdornment_"..id
    root.Parent=self.Folder
    local shaft=newAdornment(root,"CylinderHandleAdornment","Axis")
    shaft.Radius=0.012
    local collar=newAdornment(root,"CylinderHandleAdornment","Socket")
    collar.Radius=0.13
    collar.InnerRadius=0.109
    collar.Height=0.025
    local first=newAdornment(root,"SphereHandleAdornment","ContactA")
    local second=newAdornment(root,"SphereHandleAdornment","ContactB")
    local stopA=newAdornment(root,"CylinderHandleAdornment","TravelMin")
    local stopB=newAdornment(root,"CylinderHandleAdornment","TravelMax")
    for _,item in ipairs({stopA,stopB}) do
        item.Radius=0.18
        item.InnerRadius=0.15
        item.Height=0.024
        item.Visible=false
    end
    return {
        root=root,shaft=shaft,collar=collar,first=first,second=second,
        stopA=stopA,stopB=stopB,
        fitMarkers={},fitData={},fitJSON=nil,
    }
end

function Visuals:UpdateJoint(cue,relation,source,target,models)
    local part=target.PrimaryPart
    if not part or not source.PrimaryPart then return end
    local kind=relation:GetAttribute("Kind")
    local color=COLORS[kind] or COLORS.Cylindrical
    for _,adorn in ipairs({cue.shaft,cue.collar,cue.first,cue.second,
        cue.stopA,cue.stopB}) do
        adorn.Color3=color
        adorn.Adornee=part
    end
    local a,b=target:GetPivot().Position,source:GetPivot().Position
    local axisLocal=Alignment.TargetAxis(target)
    local axis=if axisLocal then
        target:GetPivot():VectorToWorldSpace(axisLocal).Unit
        elseif (b-a).Magnitude>1e-4 then (b-a).Unit else Vector3.yAxis
    if kind=="Spring" then
        a,b=SpringMath.Frames(source,target,"General")
        if (b-a).Magnitude>1e-4 then axis=(b-a).Unit end
    end
    local center=(a+b)*0.5
    dot(cue.first,part,a,0.058)
    dot(cue.second,part,b,0.058)
    put(cue.collar,part,frameOnAxis(center,axis))
    cue.collar.Visible=true
    if kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        local distance=math.min(1.8,math.max(0.35,
            math.min(source.PrimaryPart.Size.Magnitude,
                target.PrimaryPart.Size.Magnitude)*0.45))
        cylinder(cue.shaft,part,center-axis*distance,center+axis*distance,0.012)
    elseif kind=="Spring" then
        -- The native SpringConstraint already draws the coil.
        cue.shaft.Visible=false
        cue.collar.Visible=false
    else
        cylinder(cue.shaft,part,a,b,0.014)
    end

    local travel=relation:GetAttribute("FitTravelU")
    local hasStops=(kind=="Slider" or kind=="Cylindrical")
        and type(travel)=="number" and travel>0
    cue.stopA.Visible=hasStops
    cue.stopB.Visible=hasStops
    if hasStops then
        put(cue.stopA,part,frameOnAxis(center-axis*travel*Grid.Unit,axis))
        put(cue.stopB,part,frameOnAxis(center+axis*travel*Grid.Unit,axis))
    end

    local json=relation:GetAttribute("FitPointsJSON")
    if json~=cue.fitJSON then
        cue.fitJSON=json
        cue.fitData={}
        if type(json)=="string" and #json<12000 then
            local ok,result=pcall(function()return HttpService:JSONDecode(json)end)
            if ok and type(result)=="table" then cue.fitData=result end
        end
    end
    local count=0
    for _,entry in ipairs(cue.fitData) do
        if count>=32 then break end
        count+=1
        local mark=cue.fitMarkers[count]
        if not mark then
            mark=newAdornment(cue.root,"SphereHandleAdornment",
                "FitContact_"..count)
            mark.Color3=Color3.fromRGB(130,211,227)
            mark.Transparency=0.08
            cue.fitMarkers[count]=mark
        end
        local moving=models[entry.movingId]
        local stationary=models[entry.stationaryId]
        local bore=moving and Alignment.TargetAxis(moving) and moving
            or (stationary and Alignment.TargetAxis(stationary) and stationary)
        if bore then
            dot(mark,part,bore:GetPivot().Position,0.066)
        else
            mark.Visible=false
        end
    end
    for i=#cue.fitMarkers,count+1,-1 do
        cue.fitMarkers[i]:Destroy()
        table.remove(cue.fitMarkers,i)
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
                if spring then spring.Visible=not simulating end
            end
        end
    end

    local root=if simulating then
        (workspace:FindFirstChild("OPENWORKS_Simulated")
            and workspace.OPENWORKS_Simulated:FindFirstChild(
                "Simulation_"..tostring(player.UserId)))
        else workspace:FindFirstChild(Config.FolderName)

    local models,allowed={},{}
    local amount=0
    if root then
        for _,model in ipairs(root:GetChildren()) do
            if not model:IsA("Model")
                or model:GetAttribute("OwnerUserId")~=player.UserId
                or not model.PrimaryPart then continue end
            local id=model:GetAttribute("InstanceId")
            if type(id)=="string" then models[id]=model end
            if amount<MAX_HIGHLIGHTS then
                allowed[model]=true
                amount+=1
            end
        end
    end

    -- Keep one fill-only Highlight per visible body, never a second set
    -- of floating Part-based green/orange grounding bars.
    for model,highlight in pairs(self.Ground) do
        if not allowed[model] or not model.Parent then
            highlight:Destroy()
            self.Ground[model]=nil
        end
    end
    for model in pairs(allowed) do
        local cue=self.Ground[model]
        if not cue then
            cue=self:GroundCue(model)
            self.Ground[model]=cue
        end
        -- ComponentId is only an editor grouping, not a rigid joint.
        -- Never color an ungrounded component member green because another
        -- editor-grouped member is grounded.
        local grounded=if simulating then model.PrimaryPart.Anchored
            else model:GetAttribute("Grounded")==true
        cue.FillColor=if grounded then GROUNDED else MOVABLE
        cue.OutlineTransparency=1
        cue.FillTransparency=0.84
    end

    -- Relationship guides are construction adornments, not active phantom
    -- mechanisms. The moving simulation shows only real geometry and the
    -- native spring coils; no helper text, guides or bars.
    local active={}
    if not simulating and authored then
        for _,relation in ipairs(authored:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")~=player.UserId then continue end
            local id=relation:GetAttribute("RelationId")
            local source=models[relation:GetAttribute("SourceId")]
            local target=models[relation:GetAttribute("TargetId")]
            if type(id)~="string" or not source or not target then continue end
            active[id]=true
            local cue=self.Joints[id]
            if not cue then
                cue=self:JointCue(id)
                self.Joints[id]=cue
            end
            self:UpdateJoint(cue,relation,source,target,models)
        end
    end
    for id,cue in pairs(self.Joints) do
        if not active[id] then
            cue.root:Destroy()
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
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    for _,cue in pairs(self.Ground) do cue:Destroy() end
    for _,cue in pairs(self.Joints) do cue.root:Destroy() end
    self.Folder:Destroy()
end

return Visuals
