--!strict
-- OPENWORKS shaft-centric gear transmission.
-- Gears are rigidly welded to shafts; mesh ratios drive physical shaft
-- AngularVelocity actuators, not native Torque forces or CFrame poses.
-- Acceleration and load are simulated using virtual shaft inertia.
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
local SCAN_INTERVAL=0.20
local STALL_REPORT_INTERVAL=2.0
local MAX_SPEED=35
local RELEASE_STOP_EPS=0.035 -- residual shaft spin must not linger forever
local DRIVE_BUDGET=HandCrankMath.MaxTorque*0.72
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

local function coaxial(a,b)
    local acf,bcf=a:GetPivot(),b:GetPivot()
    local delta=bcf.Position-acf.Position
    return math.abs(acf.RightVector:Dot(bcf.RightVector))>=0.998
        and (delta-acf.RightVector*delta:Dot(acf.RightVector)).Magnitude<=0.035
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
                group={Id=key,Models={},Gears={},ShaftCandidates={},Root=nil,
                    AxisSource=nil,VelocityActuator=nil,VirtualSpeed=0,
                    TargetSpeed=0,Grounded=false,Braking=false}
                groups[key]=group
            end
            table.insert(group.Models,clone)
            byId[id]=group
            -- A HandCrank also advertises PrimitiveFamily=Cylinder, but it
            -- is an actuator, not the rigid output shaft reference. Prefer
            -- the real cylinder shaft regardless of assembly iteration order.
            if Alignment.IsShaft(original)
                and original:GetAttribute("ActuatorKind")~="HandCrank" then
                table.insert(group.ShaftCandidates,clone)
                if not group.AxisSource then
                    group.AxisSource=clone
                    group.Root=clone.PrimaryPart
                end
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
            -- Rigid welding another cylinder or bearing-shaped structure
            -- onto a gear shaft does NOT change the gear's spin axis.
            -- The old solver chose the first random shaft encountered and
            -- threw an error when that unrelated rigid member was angled.
            local chosen,score=nil,-1
            for _,shaft in ipairs(group.ShaftCandidates) do
                local count=0
                for _,entry in ipairs(group.Gears) do
                    if coaxial(shaft,entry.Model) then count+=1 end
                end
                if count>score then chosen,score=shaft,count end
            end
            if chosen and score>0 then
                group.AxisSource=chosen
                group.Root=chosen.PrimaryPart
            else
                -- A gear-only rigid group remains legal and can spin.
                group.AxisSource=nil
                group.Root=group.Gears[1].Model.PrimaryPart
            end
            -- If a builder rigidly welds two gears at non-coaxial angles,
            -- they form ONE rigid physics body, NOT two separately driven
            -- shafts. Ignore the incompatible mesh contact rather than
            -- killing simulation of the rest of the machine.
            local reference=group.AxisSource or group.Gears[1].Model
            for _,entry in ipairs(group.Gears) do
                if not coaxial(reference,entry.Model) then
                    entry.Incompatible=true
                    warn("[OPENWORKS][GEARS] Ignoring non-coaxial gear "
                        ..tostring(entry.Model.Name)
                        .." rigidly attached to a different gear axis")
                end
            end
            local attachment=Instance.new("Attachment")
            attachment.Name="OPENWORKS_GearShaftAxis"
            attachment.Parent=group.Root
            local velocity=Instance.new("AngularVelocity")
            velocity.Name="OPENWORKS_GearShaftSpeed"
            velocity.Attachment0=attachment
            velocity.RelativeTo=Enum.ActuatorRelativeTo.World
            velocity.AngularVelocity=Vector3.zero
            velocity.MaxTorque=DRIVE_BUDGET
            velocity.Enabled=false
            velocity.Parent=runtime
            group.VelocityActuator=velocity
        end
    end

    local self=setmetatable({Groups=groups,ById=byId,Gears=gears,
        Links={},Contacts=0,Unmeshed={},Drives={},ScanElapsed=SCAN_INTERVAL},Transmission)
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
            if left.Incompatible or right.Incompatible then continue end
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
                LeftGear=left.Model,RightGear=right.Model,
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
        local worstPhase=0
        for _,link in ipairs(self.Links) do
            if link.A==group or link.B==group then
                total+=math.abs(link.Effort or 0)
                worstPhase=math.max(worstPhase,math.abs(link.PhaseError or 0))
            end
        end
        return string.format("%d shaft speed link(s) / %s / %s / virtual load %.1f / target %.2f rad/s / tooth error %.2f pitch / %s",count,
            if group.AxisSource then "shaft mounted" else "LOOSE GEAR: missing shaft weld",
            live,total,group.TargetSpeed or 0,worstPhase,
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

-- External motors enter as shaft-speed commands, never Torque objects.
function Transmission:ClearDrives()
    table.clear(self.Drives)
end

function Transmission:SetDrive(id,speed,budget,worldAxis)
    local group=self.ById[id]
    if not group or #group.Gears==0
        or type(speed)~="number" or speed~=speed then return end
    local signed=math.clamp(speed,-MAX_SPEED,MAX_SPEED)
    if worldAxis and typeof(worldAxis)=="Vector3" and worldAxis.Magnitude>0 then
        signed*=axis(group):Dot(worldAxis.Unit)
    end
    local commands=self.Drives[group]
    if not commands then
        commands={}
        self.Drives[group]=commands
    end
    table.insert(commands,{Speed=signed,
        Weight=math.clamp(budget or HandCrankMath.MaxTorque,1,100000)})
end

-- A single explicit input drives each connected gear train at its
-- exact tooth ratio. Output shafts NEVER become implicit input sources:
-- no backdrive feedback, virtual inertia blending, or tooth-phase servo.
-- The only permitted commands are SetDrive calls from actual crank/motor
-- controls. This eliminates self-chasing jitter after releasing a drive.
function Transmission:Step(dt)
    dt=math.clamp(dt,1/240,0.07)
    self.ScanElapsed+=dt
    if self.ScanElapsed>=SCAN_INTERVAL then
        self.ScanElapsed=0
        self:Detect()
    end
    local neighbors={}
    for _,link in ipairs(self.Links) do
        if link.A.Root.Parent and link.B.Root.Parent then
            neighbors[link.A]=neighbors[link.A] or {}
            neighbors[link.B]=neighbors[link.B] or {}
            table.insert(neighbors[link.A],{Group=link.B,Ratio=link.Ratio,Link=link})
            table.insert(neighbors[link.B],{Group=link.A,Ratio=1/link.Ratio,Link=link})
            link.Effort=0
            link.PhysicsBlocked=false
        end
    end
    local visited={}
    local commandedGroups={}
    local function unanchored(group)
        local part=group.Root
        local root=part and part.AssemblyRootPart
        return part and part.Parent and not part.Anchored
            and not (root and root.Anchored)
    end
    for first in pairs(neighbors) do
        if visited[first] then continue end
        local component={}
        local queue={first}
        visited[first]=true
        local i=1
        while i<=#queue do
            local current=queue[i]
            i+=1
            table.insert(component,current)
            for _,edge in ipairs(neighbors[current]) do
                if not visited[edge.Group] then
                    visited[edge.Group]=true
                    table.insert(queue,edge.Group)
                end
            end
        end
        -- Prefer the strongest explicitly driven shaft; break ties by
        -- stable group ID, not order of pairs() iteration or physics speed.
        local lead,drive=nil,nil
        for _,group in ipairs(component) do
            if unanchored(group) then
                for _,candidate in ipairs(self.Drives[group] or {}) do
                    if not drive or candidate.Weight>drive.Weight
                        or (candidate.Weight==drive.Weight
                            and tostring(group.Id)<tostring(lead.Id)) then
                        lead,drive=group,candidate
                    end
                end
            end
        end
        if lead and drive then
            -- Ratios are directional from the selected AUTHORIZED input.
            -- This is not physics backdrive: changing which motor is held
            -- changes the source, but passive output motion never can.
            local factor={[lead]=1}
            local bfs={lead}
            local k=1
            while k<=#bfs do
                local current=bfs[k]
                k+=1
                for _,edge in ipairs(neighbors[current]) do
                    local expected=factor[current]*edge.Ratio
                    if factor[edge.Group]==nil then
                        factor[edge.Group]=expected
                        table.insert(bfs,edge.Group)
                    elseif math.abs(factor[edge.Group]-expected)>
                        0.02*math.max(1,math.abs(expected)) then
                        edge.Link.Inconsistent=true
                    end
                end
            end
            for _,group in ipairs(component) do
                local commanded=(factor[group] or 0)*drive.Speed
                group.TargetSpeed=math.clamp(commanded,-MAX_SPEED,MAX_SPEED)
                group.VirtualSpeed=group.TargetSpeed
                group.Braking=true
                if group~=lead and unanchored(group) then
                    local actuator=group.VelocityActuator
                    if actuator then
                        actuator.MaxTorque=DRIVE_BUDGET
                        actuator.AngularVelocity=axis(group)*group.TargetSpeed
                        actuator.Enabled=true
                        commandedGroups[group]=true
                    end
                end
            end
            for _,link in ipairs(self.Links) do
                if factor[link.A]~=nil and factor[link.B]~=nil then
                    link.Effort=math.min(drive.Weight,DRIVE_BUDGET)
                    link.PhaseError=0
                end
            end
        end
    end
    -- Braking is a ZERO target, never a reverse-motion sample or a
    -- generated drive. After it settles we release the actuator entirely.
    for _,group in pairs(self.Groups) do
        local actuator=group.VelocityActuator
        if actuator and not commandedGroups[group] then
            local explicitlyDriven=self.Drives[group]~=nil
            if explicitlyDriven then
                -- Do not fight the native crank or bearing motor.
                actuator.AngularVelocity=Vector3.zero
                actuator.Enabled=false
            elseif group.Braking and unanchored(group) then
                local dir=axis(group)
                local speed=group.Root.AssemblyAngularVelocity:Dot(dir)
                if math.abs(speed)>RELEASE_STOP_EPS then
                    actuator.MaxTorque=DRIVE_BUDGET
                    actuator.AngularVelocity=Vector3.zero
                    actuator.Enabled=true
                else
                    group.Root.AssemblyAngularVelocity=
                        group.Root.AssemblyAngularVelocity-dir*speed
                    actuator.AngularVelocity=Vector3.zero
                    actuator.Enabled=false
                    group.Braking=false
                end
            else
                actuator.AngularVelocity=Vector3.zero
                actuator.Enabled=false
            end
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
                "output %.3f rad/s, virtual load %.1f, input/output rigidly anchored %s/%s, "
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
    self:ClearDrives()
    for _,group in pairs(self.Groups) do
        if group.VelocityActuator then
            group.VelocityActuator.AngularVelocity=Vector3.zero
            group.VelocityActuator.Enabled=false
        end
    end
end

return Transmission
