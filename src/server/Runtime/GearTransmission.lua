--!strict
-- OPENWORKS shaft-centric gear transmission.
-- Gears are rigidly welded to shafts; meshing transfers torque between
-- Roblox physics assemblies, never scripted gear poses or hidden anchors.
-- The same mesh works in both directions with competing torque sources.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Alignment=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))
local HandCrankMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("HandCrankMath"))

local Transmission={}
Transmission.__index=Transmission

local MAX_GEARS=40
local SCAN_INTERVAL=0.10
local STALL_REPORT_INTERVAL=2.0
local COUPLING_RESPONSE=14
local PHASE_RECOVERY=6
local MAX_TOOTH_FORCE=80000
local MIN_INERTIA=0.001
-- The old per-tooth cap could be >100,000 while a manual crank could only
-- supply 6,500. That closed-loop brake can stall an otherwise valid gearbox.
-- A coupling MUST NOT consume more than the available drive torque just to
-- enforce a speed ratio. The input motor retains headroom to accelerate.
local MAX_MESH_EFFORT=HandCrankMath.MaxTorque*0.72
local MAX_INERTIA_ESTIMATE=2500
local function finiteAssemblyMass(part)
    local root=part.AssemblyRootPart
    if (root and root.Anchored) or part.Anchored then return nil end
    local mass=part.AssemblyMass
    if mass~=mass or mass==math.huge or mass<0 or mass>1e8 then return nil end
    return mass
end

local function identifier(model)
    return model:GetAttribute("InstanceId")
end

local function isGear(model)
    local kind=GearMath.Kind(model)
    return kind=="Spur" or kind=="Bevel45" or kind=="Bevel90"
end

local function axis(group)
    return (group.AxisSource or group.Gears[1].Model):GetPivot().RightVector.Unit
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

    local groups,byId,gears={},{},{}
    for _,original in ipairs(graph.models) do
        local id=identifier(original)
        local key=root(id)
        local clone=copies[id]
        if key and clone then
            local group=groups[key]
            if not group then
                group={Id=key,Models={},Gears={},Root=nil,
                    AxisSource=nil,Torque=nil,Pending=Vector3.zero,
                    Grounded=false}
                groups[key]=group
            end
            table.insert(group.Models,clone)
            byId[id]=group
            -- A HandCrank also advertises PrimitiveFamily=Cylinder, but it
            -- is an actuator, not the rigid output shaft reference. Prefer
            -- the real cylinder shaft regardless of assembly iteration order.
            if Alignment.IsShaft(original)
                and original:GetAttribute("ActuatorKind")~="HandCrank"
                and not group.AxisSource then
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
            end
        end
    end

    for _,group in pairs(groups) do
        if #group.Gears>0 then
            -- Compound trains: a single shaft may carry arbitrarily many
            -- distinct gears provided every mounted gear is concentric.
            local cf=(group.AxisSource or group.Gears[1].Model):GetPivot()
            for _,entry in ipairs(group.Gears) do
                local gearCF=entry.Model:GetPivot()
                local delta=gearCF.Position-cf.Position
                if math.abs(gearCF.RightVector:Dot(cf.RightVector))<0.999
                    or (delta-cf.RightVector*delta:Dot(cf.RightVector)).Magnitude>0.025 then
                    error("All gears welded to one shaft must be coaxial")
                end
            end
            local attachment=Instance.new("Attachment")
            attachment.Name="OPENWORKS_TransmissionAxis"
            attachment.Parent=group.Root
            local torque=Instance.new("Torque")
            torque.Name="OPENWORKS_GearMeshTorque"
            torque.Enabled=true
            torque.Attachment0=attachment
            torque.RelativeTo=Enum.ActuatorRelativeTo.World
            torque.Torque=Vector3.zero
            torque.Parent=runtime
            group.Torque=torque
        end
    end

    local self=setmetatable({Groups=groups,ById=byId,Gears=gears,
        Links={},Contacts=0,Unmeshed={},ScanElapsed=SCAN_INTERVAL},Transmission)
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

function Transmission:ConfigureSupport(_graph,_copies,groundKeys)
    for id,group in pairs(self.ById) do
        if groundKeys["p:"..tostring(id)] then group.Grounded=true end
    end
end

function Transmission:Detect()
    local previous={}
    for _,link in ipairs(self.Links) do previous[link.Key]=link end
    local links,contacted={},{}
    for i=1,#self.Gears-1 do
        local left=self.Gears[i]
        for j=i+1,#self.Gears do
            local right=self.Gears[j]
            local key=tostring(identifier(left.Model))..":"..tostring(identifier(right.Model))
            -- A tiny amount of bearing/physics drift must not turn off
            -- torque transmission every tenth of a second. New contacts
            -- use strict validation; existing contacts retain a small
            -- bounded hysteresis region (same gear module and axis).
            local engaged=GearMath.AutoMeshStatus(left.Model,right.Model,
                previous[key]~=nil)
            if left.Group==right.Group or not engaged then
                continue
            end
            local a,b=left.Group,right.Group
            -- Apply native torque even to a gear whose shaft mount is
            -- missing: a visibly engaging *free* gear should still receive
            -- force. A mounted gear remains part of its welded shaft body.
            -- The diagnostic names missing Hub welds rather than silently
            -- turning a valid visual contact into zero transmission.
            local ratio
            local kind=GearMath.Kind(left.Model)
            if kind=="Bevel45" or kind=="Bevel90" then
                local signA=if axis(a):Dot(left.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                local signB=if axis(b):Dot(right.Model:GetPivot().RightVector)>=0
                    then 1 else -1
                ratio=-left.Teeth/right.Teeth*signA*signB
            else
                local orientation=axis(a):Dot(axis(b))
                if math.abs(orientation)<0.999 then continue end
                ratio=-left.Teeth/right.Teeth*orientation
            end
            table.insert(links,{A=a,B=b,Ratio=ratio,
                RadiusA=GearMath.PitchRadius(left.Model),
                RadiusB=GearMath.PitchRadius(right.Model),
                Key=key,Error=if previous[key] then previous[key].Error else 0,
                StallElapsed=if previous[key] then previous[key].StallElapsed else 0})
            contacted[left]=true
            contacted[right]=true
        end
    end
    self.Links=links
    self.Contacts=#links

    local unmeshed={}
    for _,entry in ipairs(self.Gears) do
        if contacted[entry] then continue end
        local reason,best=nil,math.huge
        if not entry.Group.AxisSource then
            reason="Gear has no rigidly welded shaft; use a Hub fit first"
        else
            for _,other in ipairs(self.Gears) do
                if other~=entry then
                    if other.Group==entry.Group then
                        reason=reason or "Gears are welded to the same shaft (no relative motion)"
                    else
                        local _,why,distance=GearMath.AutoMeshStatus(entry.Model,other.Model)
                        if distance<best then best=distance;reason=why end
                    end
                end
            end
        end
        table.insert(unmeshed,{Gear=entry.Model.Name,
            Reason=reason or "No other meshing gear in assembly",
            Id=identifier(entry.Model)})
    end
    self.Unmeshed=unmeshed
end

function Transmission:NearestFailure()
    if #self.Gears<2 then return "Assembly must register at least two gears." end
    local closestReason="No matching gears"
    local closest=math.huge
    for i=1,#self.Gears-1 do
        for j=i+1,#self.Gears do
            local left,right=self.Gears[i],self.Gears[j]
            local a,b=left.Model,right.Model
            local good,why,distance=GearMath.AutoMeshStatus(a,b)
            if left.Group==right.Group then
                why="Both gears belong to ONE rigid welded shaft"
                good=false
                distance=0
            end
            if not good and type(distance)=="number"
                and (distance<closest or closest==math.huge) then
                closest=distance
                closestReason=string.format("%s vs %s: %s",
                    a.Name,b.Name,tostring(why))
            end
        end
    end
    return closestReason
end

function Transmission:Explain(id)
    local group=self.ById[id]
    if not group or #group.Gears==0 then
        return "Not part of a shaft transmission"
    end
    local count=0
    for _,link in ipairs(self.Links) do
        if link.A==group or link.B==group then count+=1 end
    end
    local root=group.Root
    local speed=if root and root.Parent then
        root.AssemblyAngularVelocity:Dot(axis(group)) else 0
    local live=string.format("%s / %.2f rad/s",if group.Grounded then
        "GROUNDED" else "FREE",speed)
    if count>0 then
        local total=0
        for _,link in ipairs(self.Links) do
            if link.A==group or link.B==group then
                total+=math.abs(link.Effort or 0)
            end
        end
        return string.format("%d torque mesh(es) / %s / %s / effort %.1f / %s",count,
            if group.AxisSource then "shaft mounted" else "LOOSE GEAR: missing shaft weld",
            live,total,
            if root and root.Anchored then "ERROR: SHAFT ANCHORED"
                elseif group.Grounded then "GROUNDED"
                elseif math.abs(speed)<0.035 then "idle: drive the crank shaft"
                else "rotation active")
    end
    if not group.AxisSource then
        return "NO SHAFT WELD • fit the gear hub onto a cylinder shaft / "..live
    end
    for _,info in ipairs(self.Unmeshed) do
        if self.ById[info.Id]==group then
            return "Not engaged: "..info.Reason.." / "..live
        end
    end
    return "No meshing teeth in this assembly / "..live
end

function Transmission:Step(dt)
    dt=math.clamp(dt,1/240,0.07)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_INTERVAL then
        self.ScanElapsed=0
        self:Detect()
    end
    for _,group in pairs(self.Groups) do
        group.Pending=Vector3.zero
    end
    local correction=(1-math.exp(-COUPLING_RESPONSE*dt))/dt
    for _,link in ipairs(self.Links) do
        local a,b=link.A,link.B
        if not a.Root.Parent or not b.Root.Parent then continue end
        local aa,ab=axis(a),axis(b)
        local wa=a.Root.AssemblyAngularVelocity:Dot(aa)
        local wb=b.Root.AssemblyAngularVelocity:Dot(ab)
        local ratio=link.Ratio
        local errorSpeed=wb-ratio*wa
        link.Error=math.clamp(link.Error+errorSpeed*dt,-0.35,0.35)
        -- An anchored member makes the ENTIRE rigid physics island immobile,
        -- even if our chosen root Part.Anchored is false. Roblox reports an
        -- infinite AssemblyMass in that case; never feed INF/NaN to Torque.
        local ma,mb=finiteAssemblyMass(a.Root),finiteAssemblyMass(b.Root)
        if not ma or not mb then
            link.Effort=0
            link.Error=0
            link.PhysicsBlocked=true
            continue
        end
        link.PhysicsBlocked=false
        local ia=math.clamp(0.5*ma*link.RadiusA^2,
            MIN_INERTIA,MAX_INERTIA_ESTIMATE)
        local ib=math.clamp(0.5*mb*link.RadiusB^2,
            MIN_INERTIA,MAX_INERTIA_ESTIMATE)
        local effective=1/(1/ib+ratio^2/ia)
        -- A gear ratio multiplies the reaction torque at the input. Bound
        -- both sides of the coupling; don't let the feedback solver overpower
        -- the hand-crank motor and freeze the driving gear at startup.
        local maxEffort=math.min(MAX_TOOTH_FORCE*link.RadiusB,
            MAX_MESH_EFFORT/math.max(1,math.abs(ratio)))
        local effort=math.clamp(
            -(errorSpeed+PHASE_RECOVERY*link.Error)*effective*correction,
            -maxEffort,maxEffort)
        -- Equal virtual work; reversing shaft torques reverses the power flow.
        link.Effort=effort
        a.Pending+=aa*(-ratio*effort)
        b.Pending+=ab*effort
        -- Under load, a missing bearing, anchored output or disconnected
        -- shaft can leave one side stationary despite a confirmed torque
        -- mesh. Report the *real* state so the issue is actionable.
        if math.max(math.abs(wa),math.abs(wb))>0.25
            and math.min(math.abs(wa),math.abs(wb))<0.03
            and math.abs(effort)>0.5 then
            link.StallElapsed=(link.StallElapsed or 0)+dt
            if link.StallElapsed>=STALL_REPORT_INTERVAL then
                link.StallElapsed=0
                warn(string.format("[OPENWORKS][GEARS] STALLED mesh %s: "
                    .."input=%.2f output=%.2f rad/s; effort=%.1f; "
                    .."roots anchored=%s/%s; mounted shafts=%s/%s. "
                    .."Verify grounded HOUSINGS and actual Hub welds.",
                    link.Key,wa,wb,effort,tostring(a.Root.Anchored),
                    tostring(b.Root.Anchored),tostring(a.AxisSource~=nil),
                    tostring(b.AxisSource~=nil)))
            end
        else
            link.StallElapsed=0
        end
    end
    for _,group in pairs(self.Groups) do
        if group.Torque and group.Torque.Parent then
            group.Torque.Torque=group.Pending
        end
    end
end

function Transmission:DriveDiagnostics(id)
    local group=self.ById[id]
    if not group or #group.Gears==0 then
        return false,"input shaft is NOT part of a recognized mounted gear"
    end
    local root=group.Root
    if not root or not root.Parent then
        return false,"input physics root is missing"
    end
    local physicalRoot=root.AssemblyRootPart
    local anchored=physicalRoot and physicalRoot.Anchored or root.Anchored
    local w=root.AssemblyAngularVelocity:Dot(axis(group))
    local links={}
    local outputTurning=false
    for _,link in ipairs(self.Links) do
        local other=if link.A==group then link.B
            elseif link.B==group then link.A else nil
        if other then
            local peerRoot=other.Root
            local peerPhysical=peerRoot and peerRoot.AssemblyRootPart
            local blocked=peerPhysical and peerPhysical.Anchored
                or peerRoot and peerRoot.Anchored
            local speed=if peerRoot and peerRoot.Parent then
                peerRoot.AssemblyAngularVelocity:Dot(axis(other)) else 0
            if math.abs(speed)>0.08 then outputTurning=true end
            table.insert(links,string.format(
                "output %.3f rad/s, torque %.1f, input/output rigidly anchored %s/%s, "
                .."output shaft mount %s, blocked %s",
                speed,math.abs(link.Effort or 0),tostring(anchored),
                tostring(blocked),tostring(other.AxisSource~=nil),
                tostring(link.PhysicsBlocked==true)))
        end
    end
    local detail=string.format("input %.3f rad/s, mass %.1f, rigidly anchored %s, %d mesh(es)",
        w,root.AssemblyMass,tostring(anchored),#links)
    if #links==0 then return false,detail.."; no gear contact currently" end
    return math.abs(w)>0.08 and outputTurning,
        detail.."; "..table.concat(links,"; ")
end

function Transmission:StopMotion()
    for _,group in pairs(self.Groups) do
        if group.Torque then group.Torque.Torque=Vector3.zero end
    end
end

return Transmission
