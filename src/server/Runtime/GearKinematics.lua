--!strict
-- OPENWORKS automatic gear engagement / deterministic rotational kinematics.
-- Roblox physics is NOT used to rotate any rigid body containing a gear.
-- Meshes are discovered from actual gear spacing each simulation update,
-- NOT from an authored K/Gear relationship and NOT from tooth collisions.
-- This first version supports external spur gears on fixed-axis assemblies;
-- bearings remain authoring geometry, not competing physics solvers.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))

local Kinematics={}
Kinematics.__index=Kinematics
local MAX_GEARS=40
local MAX_RACKS=24
local SCAN_PERIOD=0.08
local ROTATION_PERIOD=1/60 -- smoother scripted motion, bounded server Heartbeat
local GRAVITY_SPEED_CAP=160
local CRANK_ACCEL_RESPONSE=9
local CRANK_RELEASE_RESPONSE=6
local CYCLE_TOLERANCE=0.002

local function identifier(model)
    return model:GetAttribute("InstanceId")
end

local function isGear(model)
    return GearMath.Kind(model)=="Spur"
        or GearMath.Kind(model)=="Bevel45"
end

local function isRack(model)
    return GearMath.Kind(model)=="Rack"
        and model.PrimaryPart~=nil
end

function Kinematics.new(graph,copies)
    local parent={}
    for _,model in ipairs(graph.models) do
        local id=identifier(model)
        if type(id)=="string" then parent[id]=id end
    end
    local function root(id)
        if type(id)~="string" or not parent[id] then return nil end
        local origin=id
        while parent[id]~=id do id=parent[id] end
        local result=id
        -- Path compression avoids quadratic traversals for long welded trains.
        id=origin
        while parent[id]~=id do
            local nextId=parent[id]
            parent[id]=result
            id=nextId
        end
        return result
    end
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Weld" or edge.kind=="Fixed" or edge.kind=="Bolt" then
            local a=root(identifier(edge.source))
            local b=root(identifier(edge.target))
            if a and b and a~=b then parent[a]=b end
        end
    end

    local groups={}
    local byId={}
    local gears={}
    local racks={}
    for _,original in ipairs(graph.models) do
        local id=identifier(original)
        local key=root(id)
        local clone=copies[id]
        if key and clone then
            local group=groups[key]
            if not group then
                group={Id=key,Models={},Gears={},Racks={},Axis=nil,
                    TravelAxis=nil,Center=nil,Grounded=false,Supported=false,
                    FallVelocity=0,Followers={},Links={}}
                groups[key]=group
            end
            table.insert(group.Models,clone)
            byId[id]=group
            if isGear(original) then
                local entry={Group=group,Model=clone,
                    Teeth=original:GetAttribute("GearTeeth")}
                table.insert(gears,entry)
                table.insert(group.Gears,entry)
                if #gears>MAX_GEARS then
                    error("Too many kinematic gears (maximum 40 per assembly)")
                end
            elseif isRack(original) then
                local entry={Group=group,Model=clone,
                    Pitch=original:GetAttribute("RackPitchStuds")}
                table.insert(racks,entry)
                table.insert(group.Racks,entry)
                if #racks>MAX_RACKS then
                    error("Too many kinematic racks (maximum 24 per assembly)")
                end
            end
        end
    end

    local kinematic={}
    for _,group in pairs(groups) do
        if #group.Gears>0 and #group.Racks>0 then
            error("Do not rigidly weld a sliding rack to a rotating gear")
        end
        if #group.Gears>0 then
            group.Center=group.Gears[1].Model:GetPivot().Position
            group.Axis=group.Gears[1].Model:GetPivot().RightVector.Unit
            for _,entry in ipairs(group.Gears) do
                -- Different gears on ONE rigid axle must be concentric.
                -- A welded off-axis gearbox cannot rotate as one body.
                local cf=entry.Model:GetPivot()
                if math.abs(group.Axis:Dot(cf.RightVector))<0.999 then
                    error("Rigidly attached gears must share a parallel axle")
                end
                local delta=cf.Position-group.Center
                if (delta-group.Axis*delta:Dot(group.Axis)).Magnitude>0.025 then
                    error("Rigidly attached gears must share a single axle")
                end
            end
            kinematic[group]=true
        elseif #group.Racks>0 then
            group.Center=group.Racks[1].Model:GetPivot().Position
            group.TravelAxis=group.Racks[1].Model:GetPivot().LookVector.Unit
            for _,entry in ipairs(group.Racks) do
                if math.abs(group.TravelAxis:Dot(
                    entry.Model:GetPivot().LookVector))<0.999 then
                    error("Rigidly grouped racks must have parallel slides")
                end
            end
            kinematic[group]=true
        end
        if kinematic[group] then
            for _,model in ipairs(group.Models) do
                model:SetAttribute("OPENWORKS_GearKinematic",true)
            end
        end
    end

    local self=setmetatable({
        Groups=groups,ById=byId,Gears=gears,Racks=racks,
        Kinematic=kinematic,
        ScanElapsed=SCAN_PERIOD,MotionElapsed=0,Contacts=0,
        CurrentSpeed=0,LastDrivenId=nil,LastAxis=nil,
        RayParams=nil,
    },Kinematics)
    self:Detect()
    return self
end

function Kinematics:IsKinematic(id)
    local group=self.ById[id]
    return group~=nil and self.Kinematic[group]==true
end

function Kinematics:IsGrounded(id)
    local group=self.ById[id]
    return group~=nil and group.Grounded==true
end

function Kinematics:MarkGrounding(groundKeys)
    for _,group in pairs(self.Groups) do
        group.Grounded=false
        group.Supported=false
    end
    for id,group in pairs(self.ById) do
        if groundKeys["p:"..tostring(id)] then
            group.Grounded=true
        end
    end
end

-- A kinematic gear still needs mechanical SUPPORT. Its authored
-- bearing/housing constrains position without a native hinge torque.
-- A free gear mounted on a FALLING shaft inherits shaft translation,
-- but retains independent rotation. No tooth physics is introduced.
function Kinematics:ConfigureSupport(graph,copies,groundKeys,sessionFolder,
    playerCharacter,constructedFolder)
    self:MarkGrounding(groundKeys)
    -- Exclude ONLY scripted gear groups, not the entire simulated
    -- assembly. Loose gears can settle on an authored, grounded table
    -- or other static housing, while meshing teeth exert no collision.
    local exclude={}
    for group in pairs(self.Kinematic) do
        for _,model in ipairs(group.Models) do
            table.insert(exclude,model)
        end
    end
    if playerCharacter then table.insert(exclude,playerCharacter) end
    if constructedFolder then table.insert(exclude,constructedFolder) end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances=exclude
    params.IgnoreWater=true
    self.RayParams=params
    for _,edge in ipairs(graph.edges) do
        if edge.kind~="Bearing" and edge.kind~="Slider"
            and edge.kind~="Cylindrical" then continue end
        local sourceId=identifier(edge.source)
        local targetId=identifier(edge.target)
        local sg=self.ById[sourceId]
        local tg=self.ById[targetId]
        if not sg or not tg or sg==tg then continue end
        local isS=self.Kinematic[sg]==true
        local isT=self.Kinematic[tg]==true
        if isS and groundKeys["p:"..tostring(targetId)] then
            sg.Supported=true
        end
        if isT and groundKeys["p:"..tostring(sourceId)] then
            tg.Supported=true
        end
        -- A free-hub bearing (shaft is source, gear is target) makes
        -- the gear translationally follow the shaft, not rotationally
        -- welded to it. The input shaft can be native or kinematic.
        if isT and edge.kind=="Bearing"
            and type(edge.target:GetAttribute("GearTeeth"))=="number" then
            local model=copies[sourceId]
            if model then
                table.insert(tg.Followers,{
                    Model=model,
                    AxialOffset=(tg.Center-model:GetPivot().Position)
                        :Dot(model:GetPivot().RightVector),
                    AxisSign=if tg.Axis:Dot(model:GetPivot().RightVector)>=0
                        then 1 else -1,
                })
            end
        end
    end
end

local function shiftGroup(group,delta)
    if delta.Magnitude<0.000001 then return end
    group.Center+=delta
    for _,model in ipairs(group.Models) do
        if model.Parent then model:PivotTo(model:GetPivot()+delta) end
    end
end

local function bottomOfGroup(group)
    local lowest=math.huge
    for _,model in ipairs(group.Models) do
        for _,part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart")
                and part:GetAttribute("GearPivotOnly")~=true then
                local cf=part.CFrame
                local size=part.Size*0.5
                local radius=math.abs(cf.RightVector.Y)*size.X
                    +math.abs(cf.UpVector.Y)*size.Y
                    +math.abs(cf.LookVector.Y)*size.Z
                lowest=math.min(lowest,part.Position.Y-radius)
            end
        end
    end
    return lowest
end

function Kinematics:Translate(dt)
    local maxStep=math.clamp(dt,0,1/30)
    -- Resolve shaft followers before loose gear gravity. If the shaft
    -- drops one stud the freely spinning gear follows by exactly one.
    for group in pairs(self.Kinematic) do
        if group.Grounded then
            group.FallVelocity=0
        elseif #group.Followers>0 then
            local follower=group.Followers[1]
            if follower.Model.Parent then
                local shaft=follower.Model:GetPivot()
                local desiredAxis=shaft.RightVector.Unit*follower.AxisSign
                local center=shaft.Position
                    +shaft.RightVector*follower.AxialOffset
                shiftGroup(group,center-group.Center)
                -- The shaft may TILT while falling under native physics.
                -- Follow its axle direction but strip axial shaft roll:
                -- a Rotation-mounted gear must remain free to spin
                -- independently rather than being welded to the shaft.
                local dot=math.clamp(group.Axis:Dot(desiredAxis),-1,1)
                if dot<0.99999 then
                    local cross=group.Axis:Cross(desiredAxis)
                    local axis=if cross.Magnitude>0.00001 then cross.Unit
                        else shaft.UpVector
                    local rotation=CFrame.new(group.Center)
                        *CFrame.fromAxisAngle(axis,math.acos(dot))
                        *CFrame.new(-group.Center)
                    for _,model in ipairs(group.Models) do
                        if model.Parent then
                            model:PivotTo(rotation*model:GetPivot())
                        end
                    end
                    group.Axis=desiredAxis
                end
            end
            group.FallVelocity=0
        elseif group.Supported then
            group.FallVelocity=0
        else
            local v=math.max(-GRAVITY_SPEED_CAP,
                group.FallVelocity-workspace.Gravity*maxStep)
            local falling=math.max(0,-(v+group.FallVelocity)*0.5*maxStep)
            local bottom=bottomOfGroup(group)
            local offset=-falling
            if self.RayParams and bottom<math.huge then
                local origin=Vector3.new(group.Center.X,bottom+0.12,
                    group.Center.Z)
                local hit=workspace:Raycast(origin,
                    Vector3.new(0,-(falling+0.15),0),self.RayParams)
                if hit and hit.Normal.Y>0.55 and hit.Instance.CanCollide
                    and hit.Instance.Anchored then
                    offset=math.min(0,hit.Position.Y+0.015-bottom)
                    v=0
                end
            end
            shiftGroup(group,Vector3.new(0,offset,0))
            group.FallVelocity=v
        end
    end
end

function Kinematics:Detect()
    for group in pairs(self.Kinematic) do
        table.clear(group.Links)
    end
    local count=0
    local contacted={}
    for i=1,#self.Gears-1 do
        local left=self.Gears[i]
        for j=i+1,#self.Gears do
            local right=self.Gears[j]
            if left.Group==right.Group then continue end
            -- The shared predicate uses ACTUAL current orientation,
            -- pitch radius, center distance and face overlap.
            if not GearMath.AutoMeshable(left.Model,right.Model) then
                continue
            end
            local a,b=left.Group,right.Group
            local kind=GearMath.Kind(left.Model)
            local ratio
            if kind=="Bevel45" then
                -- Each group measures speed about its OWN local axle,
                -- which need not be parallel for an angled bevel mesh.
                local signA=if a.Axis:Dot(left.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                local signB=if b.Axis:Dot(right.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                ratio=-left.Teeth/right.Teeth*signA*signB
            else
                local orientation=a.Axis:Dot(b.Axis)
                if math.abs(orientation)<0.999 then continue end
                ratio=-left.Teeth/right.Teeth*orientation
            end
            table.insert(a.Links,{Group=b,Ratio=ratio})
            table.insert(b.Links,{Group=a,Ratio=1/ratio})
            contacted[left]=true
            contacted[right]=true
            count+=1
        end
    end

    -- Pinion angular speed (rad/s) converts to rack linear speed
    -- (studs/s) at the PITCH radius. Every edge has its inverse;
    -- the exact same graph supports multiple racks and backdriving.
    for _,pinion in ipairs(self.Gears) do
        if GearMath.Kind(pinion.Model)~="Spur" then continue end
        for _,rack in ipairs(self.Racks) do
            if pinion.Group==rack.Group
                or not GearMath.AutoMeshable(pinion.Model,rack.Model) then
                continue
            end
            local a,b=pinion.Group,rack.Group
            local rackUp=rack.Model:GetPivot().UpVector
            local signed=a.Axis:Cross(-rackUp):Dot(b.TravelAxis)
            if math.abs(signed)<0.999 then continue end
            local ratio=GearMath.PitchRadius(pinion.Model)*signed
            if math.abs(ratio)<0.0001 then continue end
            table.insert(a.Links,{Group=b,Ratio=ratio})
            table.insert(b.Links,{Group=a,Ratio=1/ratio})
            contacted[pinion]=true
            contacted[rack]=true
            count+=1
        end
    end
    self.Contacts=count
    self.Unmeshed={}
    -- Expose WHY a gear is stationary. A visually nearby gear may have
    -- correct tooth spacing but sit slightly outside the face plane.
    local allEntries={}
    for _,entry in ipairs(self.Gears) do
        table.insert(allEntries,entry)
    end
    for _,entry in ipairs(self.Racks) do
        table.insert(allEntries,entry)
    end
    for _,entry in ipairs(allEntries) do
        if contacted[entry] then continue end
        local nearest,reason,best=nil,nil,math.huge
        for _,other in ipairs(allEntries) do
            if other~=entry and other.Group~=entry.Group then
                local _,why,proximity=GearMath.AutoMeshStatus(
                    entry.Model,other.Model)
                if proximity<best then
                    best=proximity
                    reason=why
                    nearest=other
                end
            end
        end
        table.insert(self.Unmeshed,{
            Gear=entry.Model.Name,
            Reason=reason or "No other gear in the assembly",
            Nearest=nearest and nearest.Model.Name or nil,
            Id=entry.Model:GetAttribute("InstanceId"),
        })
    end
end

function Kinematics:Explain(id)
    local group=self.ById[id]
    if not group or not self.Kinematic[group] then
        return "Not a gear-driven rigid body"
    end
    if #group.Links>0 then
        return string.format("%d automatic gear mesh(es)",#group.Links)
    end
    for _,info in ipairs(self.Unmeshed or {}) do
        if self.ById[info.Id]==group then
            return "Not engaged: "..info.Reason
        end
    end
    return "Gear has no current mesh"
end

function Kinematics:StopMotion()
    self.CurrentSpeed=0
    self.MotionElapsed=0
    self.LastDrivenId=nil
    self.LastAxis=nil
end

-- Every gear group gets the same gravity/support and angular graph
-- regardless of where the single crank is attached. Drive can start at
-- ANY gear in a network, so transmission is inherently reversible and
-- supports branched one-to-many gear meshes without special cases.
function Kinematics:Step(dt,drivenId,shaftAxis,inputSpeed)
    dt=math.clamp(dt,0,0.07)
    self:Translate(dt)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_PERIOD then
        self.ScanElapsed=0
        self:Detect()
    end

    -- Inertia-like crank easing without a native physics actuator.
    -- Release stops injecting energy; a brief scripted coast smooths
    -- the gear train to a stop instead of snapping immediately.
    local active=drivenId~=nil and shaftAxis~=nil and inputSpeed~=0
    local target=if active then inputSpeed else 0
    local response=if active then CRANK_ACCEL_RESPONSE
        else CRANK_RELEASE_RESPONSE
    local alpha=1-math.exp(-response*dt)
    self.CurrentSpeed+=(target-self.CurrentSpeed)*alpha
    if not active and math.abs(self.CurrentSpeed)<0.015 then
        self.CurrentSpeed=0
    end
    if active then
        self.LastDrivenId=drivenId
        self.LastAxis=shaftAxis
    end
    local sourceId=if active then drivenId else self.LastDrivenId
    local inputAxis=if active then shaftAxis else self.LastAxis
    if not sourceId or not inputAxis or self.CurrentSpeed==0 then
        return
    end

    self.MotionElapsed+=dt
    if self.MotionElapsed<ROTATION_PERIOD then return end
    local step=math.clamp(self.MotionElapsed,0,0.07)
    self.MotionElapsed=0
    local source=self.ById[sourceId]
    if not source or not self.Kinematic[source] then return end

    local speed={[source]=self.CurrentSpeed*source.Axis:Dot(inputAxis)}
    local queue={source}
    local index=1
    local stalled=false
    while index<=#queue do
        local group=queue[index]
        index+=1
        if group.Grounded then stalled=true end
        for _,edge in ipairs(group.Links) do
            local nextGroup=edge.Group
            local calculated=speed[group]*edge.Ratio
            if speed[nextGroup]==nil then
                speed[nextGroup]=calculated
                table.insert(queue,nextGroup)
            elseif math.abs(speed[nextGroup]-calculated)>CYCLE_TOLERANCE then
                stalled=true
            end
        end
    end
    if stalled then
        self.CurrentSpeed=0
        return
    end

    -- One-to-many branching is automatic: EVERY reachable group is
    -- rotated once around its own axle. Rotating any output-side crank
    -- traverses the same edges backward without injecting extra motors.
    for group,velocity in pairs(speed) do
        if math.abs(velocity)>0.00001 then
            if group.TravelAxis then
                -- Rack DOF is translation only. No native prismatic
                -- motor or collision force may push the pinion.
                shiftGroup(group,group.TravelAxis*velocity*step)
            else
                local center=group.Center
                local delta=CFrame.new(center)
                    *CFrame.fromAxisAngle(group.Axis,velocity*step)
                    *CFrame.new(-center)
                for _,model in ipairs(group.Models) do
                    if model.Parent then
                        model:PivotTo(delta*model:GetPivot())
                    end
                end
            end
        end
    end
end

return Kinematics
