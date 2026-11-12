--!strict
-- OPENWORKS physical shaft-centric transmission.
-- Gear hubs are WeldConstraints; mesh contacts apply forces/torques to the
-- resulting Roblox rigid bodies. No gear or shaft is animated with PivotTo,
-- and no input/output/independent/dependent designation is ever necessary.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Alignment=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))

local Transmission={}
Transmission.__index=Transmission

local MAX_GEARS=40
local MAX_RACKS=24
local SCAN_INTERVAL=0.10
local COUPLING_RESPONSE=14
local PHASE_RECOVERY=6
local MAX_TOOTH_FORCE=80000
local MIN_INERTIA=0.001
local RACK_DRIVE_FORCE=4500

local function identifier(model)
    return model:GetAttribute("InstanceId")
end

local function isGear(model)
    local kind=GearMath.Kind(model)
    return kind=="Spur" or kind=="Bevel45" or kind=="Bevel90"
end

local function axis(group)
    if group.AxisSource then
        return group.AxisSource:GetPivot().RightVector.Unit
    end
    return group.Gears[1].Model:GetPivot().RightVector.Unit
end

local function rackAxis(group)
    return group.Racks[1].Model:GetPivot().LookVector.Unit
end

local function addForce(group,runtime)
    local attachment=Instance.new("Attachment")
    attachment.Name="OPENWORKS_TransmissionAxis"
    attachment.Parent=group.Root
    if #group.Gears>0 then
        local torque=Instance.new("Torque")
        torque.Name="OPENWORKS_GearMeshTorque"
        torque.Attachment0=attachment
        torque.RelativeTo=Enum.ActuatorRelativeTo.World
        torque.Torque=Vector3.zero
        torque.Parent=runtime
        group.Torque=torque
    else
        local force=Instance.new("VectorForce")
        force.Name="OPENWORKS_RackMeshForce"
        force.Attachment0=attachment
        force.RelativeTo=Enum.ActuatorRelativeTo.World
        force.ApplyAtCenterOfMass=true
        force.Force=Vector3.zero
        force.Parent=runtime
        group.Force=force
    end
end

function Transmission.new(graph,copies,runtime)
    local parent={}
    for _,model in ipairs(graph.models) do
        local id=identifier(model)
        if type(id)=="string" then parent[id]=id end
    end
    local function root(id)
        if type(id)~="string" or not parent[id] then return nil end
        local origin=id
        while parent[id]~=id do id=parent[id] end
        local final=id
        id=origin
        while parent[id]~=id do
            local nextId=parent[id]
            parent[id]=final
            id=nextId
        end
        return final
    end
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Weld" or edge.kind=="Fixed" or edge.kind=="Bolt" then
            local a=root(identifier(edge.source))
            local b=root(identifier(edge.target))
            if a and b and a~=b then parent[a]=b end
        end
    end

    local groups,byId,gears,racks={},{},{},{}
    for _,original in ipairs(graph.models) do
        local id=identifier(original)
        local key=root(id)
        local clone=copies[id]
        if key and clone then
            local group=groups[key]
            if not group then
                group={Models={},Gears={},Racks={},Root=nil,
                    AxisSource=nil,Torque=nil,Force=nil,Drive=nil,
                    Guide=nil,Grounded=false,Pending=Vector3.zero,
                    PendingForce=Vector3.zero,Id=key}
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
                if #gears>MAX_GEARS then
                    error("Too many gears (maximum 40 per assembly)")
                end
                if not group.Root then group.Root=clone.PrimaryPart end
            elseif GearMath.Kind(original)=="Rack" then
                local entry={Model=clone,Group=group}
                table.insert(group.Racks,entry)
                table.insert(racks,entry)
                if #racks>MAX_RACKS then
                    error("Too many racks (maximum 24 per assembly)")
                end
                if not group.Root then group.Root=clone.PrimaryPart end
            end
        end
    end

    for _,group in pairs(groups) do
        if #group.Gears>0 and #group.Racks>0 then
            error("A rack cannot be welded to a rotating gear shaft")
        end
        if #group.Gears>0 then
            -- Multiple gears sharing one physical shaft must have one axis.
            local base=group.AxisSource or group.Gears[1].Model
            local cf=base:GetPivot()
            for _,entry in ipairs(group.Gears) do
                local gcf=entry.Model:GetPivot()
                local delta=gcf.Position-cf.Position
                if math.abs(gcf.RightVector:Dot(cf.RightVector))<0.999
                    or (delta-cf.RightVector*delta:Dot(cf.RightVector)).Magnitude>0.025 then
                    error("All gears welded to one shaft must be coaxial")
                end
            end
            addForce(group,runtime)
        elseif #group.Racks>0 then
            for _,entry in ipairs(group.Racks) do
                if math.abs(rackAxis(group):Dot(entry.Model:GetPivot().LookVector))<0.999 then
                    error("Rigidly joined racks must slide on parallel axes")
                end
            end
            addForce(group,runtime)
        end
    end

    local self=setmetatable({
        Groups=groups,ById=byId,Gears=gears,Racks=racks,
        Links={},Contacts=0,Unmeshed={},
        ScanElapsed=SCAN_INTERVAL,
    },Transmission)
    self:Detect()
    return self
end

function Transmission:IsGeared(id)
    local group=self.ById[id]
    return group~=nil and #group.Gears>0
end

function Transmission:IsGrounded(id)
    local group=self.ById[id]
    return group~=nil and group.Grounded==true
end

function Transmission:RackAxis(id)
    local group=self.ById[id]
    return group and #group.Racks>0 and rackAxis(group) or nil
end

function Transmission:RackModel(id)
    local group=self.ById[id]
    return group and group.Racks[1] and group.Racks[1].Model or nil
end

function Transmission:CanDriveRack(id)
    local group=self.ById[id]
    return group~=nil and #group.Racks>0 and group.Guide~=nil
        and not group.Grounded and group.Drive~=nil
end

function Transmission:ConfigureSupport(graph,copies,groundKeys,runtime)
    for id,group in pairs(self.ById) do
        if groundKeys["p:"..tostring(id)] then group.Grounded=true end
    end

    -- The rack guide is an ordinary explicitly grounded rigid body.
    -- A native prismatic limits rack travel; no scripted sliding poses.
    for _,original in ipairs(graph.models) do
        if GearMath.Kind(original)~="RackGuide" then continue end
        local guideId=identifier(original)
        if not groundKeys["p:"..tostring(guideId)] then continue end
        local guide=copies[guideId]
        if not guide or not guide.PrimaryPart then continue end

        for _,entry in ipairs(self.Racks) do
            local group=entry.Group
            if group.Guide or not GearMath.AutoGuideStatus(entry.Model,guide) then
                continue
            end
            local root=group.Root
            local cf=guide:GetPivot()
            local travelAxis=cf.LookVector.Unit
            local up=cf.UpVector.Unit
            local frame=CFrame.fromMatrix(entry.Model:GetPivot().Position,
                travelAxis,up,travelAxis:Cross(up))
            local a0=Instance.new("Attachment")
            a0.Name="OPENWORKS_RackGuideAnchor"
            a0.CFrame=guide.PrimaryPart.CFrame:ToObjectSpace(frame)
            a0.Parent=guide.PrimaryPart
            local a1=Instance.new("Attachment")
            a1.Name="OPENWORKS_RackSlideAnchor"
            a1.CFrame=root.CFrame:ToObjectSpace(frame)
            a1.Parent=root
            local slide=Instance.new("PrismaticConstraint")
            slide.Name="OPENWORKS_PhysicalRackGuide"
            slide.Attachment0=a0
            slide.Attachment1=a1
            slide.ActuatorType=Enum.ActuatorType.None
            local range=math.max(0,
                ((guide:GetAttribute("RackGuideLengthStuds") or 0)
                -(entry.Model:GetAttribute("RackLengthStuds") or 0))*0.5-0.02)
            local offset=(entry.Model:GetPivot().Position-cf.Position):Dot(travelAxis)
            slide.LimitsEnabled=true
            slide.LowerLimit=-range-offset
            slide.UpperLimit=range-offset
            slide.Parent=runtime

            -- Rack teeth may contact a gear through the transmission solver.
            -- Exclude the guide housing from physical rack collision jitter.
            for _,p0 in ipairs(entry.Model:GetDescendants()) do
                if not p0:IsA("BasePart") then continue end
                for _,p1 in ipairs(guide:GetDescendants()) do
                    if not p1:IsA("BasePart") then continue end
                    local excluded=Instance.new("NoCollisionConstraint")
                    excluded.Name="OPENWORKS_RackGuideNoCollision"
                    excluded.Part0=p0
                    excluded.Part1=p1
                    excluded.Parent=runtime
                end
            end

            local input=Instance.new("Attachment")
            input.Name="OPENWORKS_RackDriveAxis"
            input.Parent=root
            local drive=Instance.new("LinearVelocity")
            drive.Name="OPENWORKS_RackManualDrive"
            drive.Attachment0=input
            drive.RelativeTo=Enum.ActuatorRelativeTo.World
            drive.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
            drive.ForceLimitsEnabled=true
            drive.MaxForce=RACK_DRIVE_FORCE
            drive.VectorVelocity=Vector3.zero
            drive.Enabled=false
            drive.Parent=runtime
            group.Guide=slide
            group.Drive=drive
        end
    end
end

function Transmission:Detect()
    local old={}
    for _,link in ipairs(self.Links) do old[link.Key]=link end
    local links={}
    local contacted={}
    for i=1,#self.Gears-1 do
        local left=self.Gears[i]
        for j=i+1,#self.Gears do
            local right=self.Gears[j]
            if left.Group==right.Group
                or not GearMath.AutoMeshable(left.Model,right.Model) then
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
            local key=tostring(identifier(left.Model))..":"..tostring(identifier(right.Model))
            table.insert(links,{A=a,B=b,Ratio=ratio,
                RadiusA=GearMath.PitchRadius(left.Model),
                RadiusB=GearMath.PitchRadius(right.Model),
                Key=key,Kind="Gear",
                Error=if old[key] then old[key].Error else 0})
            contacted[left]=true
            contacted[right]=true
        end
    end

    for _,pinion in ipairs(self.Gears) do
        if GearMath.Kind(pinion.Model)~="Spur" then continue end
        for _,rack in ipairs(self.Racks) do
            if pinion.Group==rack.Group
                or not GearMath.AutoMeshable(pinion.Model,rack.Model) then
                continue
            end
            local a,b=pinion.Group,rack.Group
            local sign=axis(a):Cross(-rack.Model:GetPivot().UpVector)
                :Dot(rackAxis(b))
            if math.abs(sign)<0.999 then continue end
            local key=tostring(identifier(pinion.Model))..":"..tostring(identifier(rack.Model))
            table.insert(links,{A=a,B=b,Ratio=GearMath.PitchRadius(pinion.Model)*sign,
                RadiusA=GearMath.PitchRadius(pinion.Model),
                Key=key,Kind="Rack",
                Error=if old[key] then old[key].Error else 0})
            contacted[pinion]=true
            contacted[rack]=true
        end
    end

    self.Links=links
    self.Contacts=#links
    local unmeshed={}
    local all={}
    for _,entry in ipairs(self.Gears) do table.insert(all,entry) end
    for _,entry in ipairs(self.Racks) do table.insert(all,entry) end
    for _,entry in ipairs(all) do
        if contacted[entry] then continue end
        local reason,best=nil,math.huge
        for _,other in ipairs(all) do
            if other~=entry and other.Group~=entry.Group then
                local _,why,distance=GearMath.AutoMeshStatus(entry.Model,other.Model)
                if distance<best then best=distance;reason=why end
            end
        end
        table.insert(unmeshed,{Gear=entry.Model.Name,
            Reason=reason or "No other meshing gear in the assembly",
            Id=identifier(entry.Model)})
    end
    self.Unmeshed=unmeshed
end

function Transmission:Explain(id)
    local group=self.ById[id]
    if not group or (#group.Gears==0 and #group.Racks==0) then
        return "Not part of a shaft transmission"
    end
    local count=0
    for _,link in ipairs(self.Links) do
        if link.A==group or link.B==group then count+=1 end
    end
    if count>0 then return tostring(count).." physical torque mesh(es)" end
    for _,problem in ipairs(self.Unmeshed) do
        if self.ById[problem.Id]==group then
            return "Not engaged: "..problem.Reason
        end
    end
    return "No meshing teeth in this assembly"
end

-- A soft, reciprocal velocity-and-phase coupling approximates gear contact
-- using native Torque/VectorForce. A mesh applies no positional teleport,
-- no invisible motor, and cannot override a grounded or limited shaft joint.
function Transmission:Step(dt,manualRackId,manualSpeed)
    dt=math.clamp(dt,1/240,0.07)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_INTERVAL then
        self.ScanElapsed=0
        self:Detect()
    end
    for _,group in pairs(self.Groups) do
        group.Pending=Vector3.zero
        group.PendingForce=Vector3.zero
        if group.Drive then
            local active=manualRackId~=nil
                and self.ById[manualRackId]==group
                and not group.Grounded
                and manualSpeed~=0
            group.Drive.Enabled=active
            group.Drive.VectorVelocity=if active
                then rackAxis(group)*manualSpeed else Vector3.zero
        end
    end
    local correction=(1-math.exp(-COUPLING_RESPONSE*dt))/dt
    for _,link in ipairs(self.Links) do
        local a,b=link.A,link.B
        if not a.Root.Parent or not b.Root.Parent then continue end
        local aa=axis(a)
        local wa=a.Root.AssemblyAngularVelocity:Dot(aa)
        local wb=if link.Kind=="Rack"
            then b.Root.AssemblyLinearVelocity:Dot(rackAxis(b))
            else b.Root.AssemblyAngularVelocity:Dot(axis(b))
        local ratio=link.Ratio
        local errorSpeed=wb-ratio*wa
        link.Error=math.clamp(link.Error+errorSpeed*dt,-0.35,0.35)
        local ia=math.max(MIN_INERTIA,0.5*a.Root.AssemblyMass*link.RadiusA^2)
        local ib=if link.Kind=="Rack"
            then math.max(0.001,b.Root.AssemblyMass)
            else math.max(MIN_INERTIA,0.5*b.Root.AssemblyMass*link.RadiusB^2)
        local effective=1/(1/ib+ratio^2/ia)
        local effort=math.clamp(
            -(errorSpeed+PHASE_RECOVERY*link.Error)*effective*correction,
            -MAX_TOOTH_FORCE*(if link.Kind=="Rack" then 1 else link.RadiusB),
            MAX_TOOTH_FORCE*(if link.Kind=="Rack" then 1 else link.RadiusB))
        -- Virtual-work identity: torque A = -ratio * effort B.
        -- Force on a rack and torque on a driven gear are fully reciprocal.
        a.Pending+=aa*(-ratio*effort)
        if link.Kind=="Rack" then
            b.PendingForce+=rackAxis(b)*effort
        else
            b.Pending+=axis(b)*effort
        end
    end
    for _,group in pairs(self.Groups) do
        if group.Torque and group.Torque.Parent then
            group.Torque.Torque=group.Pending
        end
        if group.Force and group.Force.Parent then
            group.Force.Force=group.PendingForce
        end
    end
end

function Transmission:StopMotion()
    for _,group in pairs(self.Groups) do
        if group.Torque then group.Torque.Torque=Vector3.zero end
        if group.Force then group.Force.Force=Vector3.zero end
        if group.Drive then
            group.Drive.VectorVelocity=Vector3.zero
            group.Drive.Enabled=false
        end
    end
end

return Transmission
