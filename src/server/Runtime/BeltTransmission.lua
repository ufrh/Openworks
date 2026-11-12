--!strict
-- Two-pulley open friction belt transmission. Shaft groups are real authored
-- Weld/Bolt links; belts apply opposing native torques, not scripted rotation.
-- Grip is limited by actual tension and contact wrap. Either shaft may drive.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Alignment=require(Shared:WaitForChild("AlignmentMath"))
local BeltMath=require(Shared:WaitForChild("BeltMath"))
local BeltVisual=require(script.Parent:WaitForChild("BeltVisual"))

local Transmission={}
Transmission.__index=Transmission
local STIFFNESS=8500 -- reference N/stud for a short, relatively stiff flat belt
local FRICTION=0.8
local RESPONSE=12
local MIN_INERTIA=0.001
local MAX_FORCE=55000
local MAX_LOOPS=24
local VISUAL_INTERVAL=0.08

local function id(model)
    return model:GetAttribute("InstanceId")
end

function Transmission.new(graph,copies,runtime)
    local parents={}
    for _,model in ipairs(graph.models) do
        local k=id(model)
        if type(k)=="string" then parents[k]=k end
    end
    local function root(k)
        if type(k)~="string" or not parents[k] then return nil end
        while parents[k]~=k do
            parents[k]=parents[parents[k]]
            k=parents[k]
        end
        return k
    end
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Weld" or edge.kind=="Fixed" or edge.kind=="Bolt" then
            local a,b=root(id(edge.source)),root(id(edge.target))
            if a and b and a~=b then parents[a]=b end
        end
    end
    local groups,byId={},{}
    for _,original in ipairs(graph.models) do
        local key=root(id(original))
        local copy=copies[id(original)]
        if key and copy then
            local group=groups[key]
            if not group then
                group={Root=nil,AxisSource=nil,Torque=nil,Pending=Vector3.zero}
                groups[key]=group
            end
            byId[id(original)]=group
            if Alignment.IsShaft(original) then
                group.AxisSource=group.AxisSource or copy
                group.Root=group.Root or copy.PrimaryPart
            end
        end
    end
    local loops={}
    for _,edge in ipairs(graph.edges) do
        if edge.kind~="Belt" then continue end
        local ida,idb=id(edge.source),id(edge.target)
        local a,b=copies[ida],copies[idb]
        local ga,gb=byId[ida],byId[idb]
        if not a or not b or not ga or not gb or ga==gb then
            error("Belt requires two separate physical pulley shafts")
        end
        if not ga.Root or not gb.Root then
            error("Both belt pulleys must be rigidly mounted on shafts")
        end
        local path,reason=BeltMath.Path(a,b)
        if not path then error("Belt routing is invalid: "..tostring(reason)) end
        local rest=edge.relation:GetAttribute("BeltRestLength")
        if type(rest)~="number" or rest<=0 or rest>300 then
            error("Saved belt length is invalid")
        end
        local visual=BeltVisual.new(runtime)
        visual:Update(path)
        table.insert(loops,{A=a,B=b,GroupA=ga,GroupB=gb,
            RestLength=rest,Visual=visual,VisibleElapsed=0})
        if #loops>MAX_LOOPS then error("Maximum 24 belts per assembly") end
    end
    for _,loop in ipairs(loops) do
        for _,group in ipairs({loop.GroupA,loop.GroupB}) do
            if group.Torque then continue end
            local att=Instance.new("Attachment")
            att.Name="OPENWORKS_BeltShaftAxis"
            att.Parent=group.Root
            local torque=Instance.new("Torque")
            torque.Name="OPENWORKS_FrictionBeltTorque"
            torque.Attachment0=att
            torque.RelativeTo=Enum.ActuatorRelativeTo.World
            torque.Torque=Vector3.zero
            torque.Parent=runtime
            group.Torque=torque
        end
    end
    return setmetatable({Groups=groups,Loops=loops},Transmission)
end

function Transmission:Step(dt)
    dt=math.clamp(dt,1/240,0.07)
    local response=(1-math.exp(-RESPONSE*dt))/dt
    for _,group in pairs(self.Groups) do group.Pending=Vector3.zero end
    for _,loop in ipairs(self.Loops) do
        local a,b=loop.GroupA,loop.GroupB
        if not a.Root.Parent or not b.Root.Parent then continue end
        local path=BeltMath.Path(loop.A,loop.B)
        loop.VisibleElapsed+=dt
        if loop.VisibleElapsed>=VISUAL_INTERVAL then
            loop.Visual:Update(path)
            loop.VisibleElapsed=0
        end
        if not path then continue end
        local tension=math.max(0,(path.Length-loop.RestLength)*STIFFNESS)
        -- Capstan limit: allowable tight/slack difference under wrap friction.
        -- At zero stretch no normal load and no transmitted drive torque.
        local capstan=math.tanh(FRICTION*math.min(path.WrapA,path.WrapB)*0.5)
        local forceLimit=math.min(MAX_FORCE,2*tension*capstan)
        if forceLimit<0.0001 then continue end
        local axisA,axisB=path.AxisA,path.AxisB
        local ratio=path.RadiusA/path.RadiusB
            *(if axisA:Dot(axisB)>=0 then 1 else -1)
        local wa=a.Root.AssemblyAngularVelocity:Dot(axisA)
        local wb=b.Root.AssemblyAngularVelocity:Dot(axisB)
        local velocityError=wb-ratio*wa
        local ia=math.max(MIN_INERTIA,
            0.5*a.Root.AssemblyMass*path.RadiusA^2)
        local ib=math.max(MIN_INERTIA,
            0.5*b.Root.AssemblyMass*path.RadiusB^2)
        local effective=1/(1/ib+ratio^2/ia)
        local required=-velocityError*effective*response
        local transmitted=math.clamp(required,
            -forceLimit*path.RadiusB,forceLimit*path.RadiusB)
        a.Pending+=axisA*(-ratio*transmitted)
        b.Pending+=axisB*transmitted
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
