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
local SCAN_PERIOD=0.08
local ROTATION_PERIOD=1/30 -- avoid 60 Hz * 40 gears * dozens of teeth replication
local CYCLE_TOLERANCE=0.002

local function identifier(model)
    return model:GetAttribute("InstanceId")
end

local function isGear(model)
    return type(model:GetAttribute("GearTeeth"))=="number"
        and type(model:GetAttribute("GearModuleStuds"))=="number"
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
    for _,original in ipairs(graph.models) do
        local id=identifier(original)
        local key=root(id)
        local clone=copies[id]
        if key and clone then
            local group=groups[key]
            if not group then
                group={Id=key,Models={},Gears={},Axis=nil,
                    Center=nil,Grounded=false,Links={}}
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
            end
        end
    end

    local kinematic={}
    for _,group in pairs(groups) do
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
            for _,model in ipairs(group.Models) do
                model:SetAttribute("OPENWORKS_GearKinematic",true)
            end
        end
    end

    local self=setmetatable({
        Groups=groups,ById=byId,Gears=gears,Kinematic=kinematic,
        ScanElapsed=SCAN_PERIOD,MotionElapsed=0,Contacts=0,
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
    end
    for id,group in pairs(self.ById) do
        if groundKeys["p:"..tostring(id)] then
            group.Grounded=true
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
            local orientation=a.Axis:Dot(b.Axis)
            if math.abs(orientation)<0.999 then continue end
            local ratio=-left.Teeth/right.Teeth*orientation
            table.insert(a.Links,{Group=b,Ratio=ratio})
            table.insert(b.Links,{Group=a,Ratio=1/ratio})
            contacted[left]=true
            contacted[right]=true
            count+=1
        end
    end
    self.Contacts=count
    self.Unmeshed={}
    -- Expose WHY a gear is stationary. A visually nearby gear may have
    -- correct tooth spacing but sit slightly outside the face plane.
    for _,entry in ipairs(self.Gears) do
        if contacted[entry] then continue end
        local nearest,reason,best=nil,nil,math.huge
        for _,other in ipairs(self.Gears) do
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

-- All motion is a fixed-axis rigid transform of authored gear/shaft/crank
-- clones. No angular velocity, native hinge actuator, force or part physics
-- can influence these bodies. Only an active crank can inject rotation.
function Kinematics:Step(dt,drivenId,shaftAxis,inputSpeed)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_PERIOD then
        self.ScanElapsed=0
        self:Detect()
    end
    if not drivenId or not shaftAxis or inputSpeed==0 then
        self.MotionElapsed=0
        return
    end
    self.MotionElapsed+=dt
    if self.MotionElapsed<ROTATION_PERIOD then return end
    local step=math.clamp(self.MotionElapsed,0,0.08)
    self.MotionElapsed=0
    local source=self.ById[drivenId]
    if not source or not self.Kinematic[source] then return end

    local speed={ [source]=inputSpeed*source.Axis:Dot(shaftAxis) }
    local queue={source}
    local index=1
    local stalled=false
    while index<=#queue do
        local group=queue[index]
        index+=1
        if group.Grounded then stalled=true end
        for _,edge in ipairs(group.Links) do
            local nextGroup=edge.Group
            local target=speed[group]*edge.Ratio
            if speed[nextGroup]==nil then
                speed[nextGroup]=target
                table.insert(queue,nextGroup)
            elseif math.abs(speed[nextGroup]-target)>CYCLE_TOLERANCE then
                -- Conflicting closed loops are mechanically locked. No
                -- infinite or contradictory motor output may be generated.
                stalled=true
            end
        end
    end
    if stalled then return end
    for group,omega in pairs(speed) do
        if math.abs(omega)>0.00001 then
            local center=group.Center
            local delta=CFrame.new(center)
                *CFrame.fromAxisAngle(group.Axis,omega*step)
                *CFrame.new(-center)
            for _,model in ipairs(group.Models) do
                if model.Parent then
                    model:PivotTo(delta*model:GetPivot())
                end
            end
        end
    end
end

return Kinematics
