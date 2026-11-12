--!strict
-- Physical, shaft-centric torque coupling for automatically meshed gears.
-- Every gear hub is a WeldConstraint. Shafts/gears remain UNANCHORED unless
-- the builder separately grounds the body. A mesh adds torques, never PivotTo.
-- There is no driver/follower designation: either shaft can backdrive the other.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Alignment=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))

local Transmission={}
Transmission.__index=Transmission

local SCAN_INTERVAL=0.10
local COUPLING_RESPONSE=14
local MAX_TOOTH_FORCE=80000
local MIN_INERTIA=0.001

local function identifier(model)
    return model:GetAttribute("InstanceId")
end

local function isGear(model)
    local kind=GearMath.Kind(model)
    return kind=="Spur" or kind=="Bevel45" or kind=="Bevel90"
end

function Transmission.new(graph,copies,runtime)
    local parent={}
    for _,model in ipairs(graph.models) do
        local id=identifier(model)
        if type(id)=="string" then parent[id]=id end
    end
    local function root(id)
        if type(id)~="string" or not parent[id] then return nil end
        while parent[id]~=id do
            parent[id]=parent[parent[id]]
            id=parent[id]
        end
        return id
    end
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Weld" or edge.kind=="Fixed" or edge.kind=="Bolt" then
            local a=root(identifier(edge.source))
            local b=root(identifier(edge.target))
            if a and b and a~=b then parent[a]=b end
        end
    end

    local groups,byId,gears={},{},{}
    for _,original in ipairs(graph.models) do
        local id=identifier(original)
        local key=root(id)
        local clone=copies[id]
        if key and clone then
            local group=groups[key]
            if not group then
                group={Models={},Gears={},Root=nil,AxisSource=nil,Torque=nil,
                    Pending=Vector3.zero,Id=key}
                groups[key]=group
            end
            table.insert(group.Models,clone)
            byId[id]=group
            if Alignment.IsShaft(original) and not group.AxisSource then
                group.AxisSource=clone
                group.Root=clone.PrimaryPart
            end
            if isGear(original) then
                local entry={Model=clone,Group=group,
                    Teeth=original:GetAttribute("GearTeeth")}
                table.insert(group.Gears,entry)
                table.insert(gears,entry)
                if not group.Root then group.Root=clone.PrimaryPart end
            end
        end
    end

    for _,group in pairs(groups) do
        if #group.Gears>0 then
            -- A compound shaft has multiple gears, all sharing its axis.
            local base=group.AxisSource or group.Gears[1].Model
            local cf=base:GetPivot()
            for _,entry in ipairs(group.Gears) do
                local gcf=entry.Model:GetPivot()
                local axial=gcf.Position-cf.Position
                if math.abs(gcf.RightVector:Dot(cf.RightVector))<0.999
                    or (axial-cf.RightVector*axial:Dot(cf.RightVector)).Magnitude>0.025 then
                    error("All gears welded to one shaft must be coaxial")
                end
            end
            local attachment=Instance.new("Attachment")
            attachment.Name="OPENWORKS_GearTorqueAxis"
            attachment.Parent=group.Root
            local torque=Instance.new("Torque")
            torque.Name="OPENWORKS_GearMeshTorque"
            torque.Attachment0=attachment
            torque.RelativeTo=Enum.ActuatorRelativeTo.World
            torque.Torque=Vector3.zero
            torque.Parent=runtime
            group.Torque=torque
        end
    end

    local self=setmetatable({
        Groups=groups,ById=byId,Gears=gears,
        Links={},Contacts=0,Unmeshed={},
        ScanElapsed=SCAN_INTERVAL,
    },Transmission)
    self:Detect()
    return self
end

local function axis(group)
    return (group.AxisSource or group.Gears[1].Model):GetPivot().RightVector.Unit
end

function Transmission:Detect()
    local links={}
    local contacted={}
    for i=1,#self.Gears-1 do
        local left=self.Gears[i]
        for j=i+1,#self.Gears do
            local right=self.Gears[j]
            if left.Group==right.Group or
                not GearMath.AutoMeshable(left.Model,right.Model) then
                continue
            end
            local a,b=left.Group,right.Group
            local ratio
            local kind=GearMath.Kind(left.Model)
            if kind=="Bevel45" or kind=="Bevel90" then
                local sa=if axis(a):Dot(left.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                local sb=if axis(b):Dot(right.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                ratio=-left.Teeth/right.Teeth*sa*sb
            else
                local orientation=axis(a):Dot(axis(b))
                if math.abs(orientation)<0.999 then continue end
                ratio=-left.Teeth/right.Teeth*orientation
            end
            table.insert(links,{A=a,B=b,Ratio=ratio,
                RadiusA=GearMath.PitchRadius(left.Model),
                RadiusB=GearMath.PitchRadius(right.Model)})
            contacted[left]=true
            contacted[right]=true
        end
    end
    self.Links=links
    self.Contacts=#links
    local unmeshed={}
    for _,entry in ipairs(self.Gears) do
        if contacted[entry] then continue end
        local nearest,best=nil,math.huge
        for _,other in ipairs(self.Gears) do
            if other.Group~=entry.Group then
                local _,why,distance=GearMath.AutoMeshStatus(entry.Model,other.Model)
                if distance<best then best=distance;nearest=why end
            end
        end
        table.insert(unmeshed,{Gear=entry.Model.Name,
            Reason=nearest or "No other meshing gear in assembly"})
    end
    self.Unmeshed=unmeshed
end

function Transmission:Step(dt)
    dt=math.clamp(dt,1/240,0.07)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_INTERVAL then
        self.ScanElapsed=0
        self:Detect()
    end
    for _,group in pairs(self.Groups) do
        if group.Torque then group.Pending=Vector3.zero end
    end
    -- An error in the gear ratio produces EQUAL AND OPPOSITE mesh work.
    -- Either shaft can supply the force. Compound meshes sum at their shaft.
    for _,link in ipairs(self.Links) do
        local a,b=link.A,link.B
        if not a.Root.Parent or not b.Root.Parent then continue end
        local aa,ab=axis(a),axis(b)
        local wa=a.Root.AssemblyAngularVelocity:Dot(aa)
        local wb=b.Root.AssemblyAngularVelocity:Dot(ab)
        local ratio=link.Ratio
        local errorSpeed=wb-ratio*wa
        local ma=math.max(0.001,a.Root.AssemblyMass)
        local mb=math.max(0.001,b.Root.AssemblyMass)
        local ia=math.max(MIN_INERTIA,0.5*ma*link.RadiusA^2)
        local ib=math.max(MIN_INERTIA,0.5*mb*link.RadiusB^2)
        local effective=1/(1/ib+ratio^2/ia)
        local correction=(1-math.exp(-COUPLING_RESPONSE*dt))/dt
        local torqueB=math.clamp(-errorSpeed*effective*correction,
            -MAX_TOOTH_FORCE*link.RadiusB,
            MAX_TOOTH_FORCE*link.RadiusB)
        -- Work balance: T_A*w_A + T_B*w_B = 0 when w_B=ratio*w_A.
        a.Pending+=aa*(-ratio*torqueB)
        b.Pending+=ab*torqueB
    end
    for _,group in pairs(self.Groups) do
        if group.Torque and group.Torque.Parent then
            group.Torque.Torque=group.Pending
        end
    end
end

function Transmission:StopMotion()
    for _,group in pairs(self.Groups) do
        if group.Torque then group.Torque.Torque=Vector3.zero end
    end
end

return Transmission
