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

local Transmission={}
Transmission.__index=Transmission

local MAX_GEARS=40
local SCAN_INTERVAL=0.10
local STALL_REPORT_INTERVAL=2.0
local COUPLING_RESPONSE=14
local PHASE_RECOVERY=6
local MAX_TOOTH_FORCE=80000
local MIN_INERTIA=0.001

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
            if not a.AxisSource or not b.AxisSource then
                continue -- a visually meshed loose gear is not a shaft gearbox
            end
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
                Key=key,Error=if previous[key] then previous[key].Error else 0})
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
        return string.format("%d torque mesh(es) / shaft mounted / %s / effort %.1f / %s",count,
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
        local ia=math.max(MIN_INERTIA,0.5*a.Root.AssemblyMass*link.RadiusA^2)
        local ib=math.max(MIN_INERTIA,0.5*b.Root.AssemblyMass*link.RadiusB^2)
        local effective=1/(1/ib+ratio^2/ia)
        local effort=math.clamp(
            -(errorSpeed+PHASE_RECOVERY*link.Error)*effective*correction,
            -MAX_TOOTH_FORCE*link.RadiusB,
            MAX_TOOTH_FORCE*link.RadiusB)
        -- Equal virtual work; reversing shaft torques reverses the power flow.
        link.Effort=effort
        a.Pending+=aa*(-ratio*effort)
        b.Pending+=ab*effort
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
