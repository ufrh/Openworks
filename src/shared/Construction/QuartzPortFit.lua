--!strict
-- OPENWORKS | Shared quartz socket fitting.
-- Port geometry is authored as invisible Attachments on any component.
-- Connections are recognized from physical port alignment, not magical wires.
local Fit = {}

Fit.CaptureDistance = 0.22 -- studs: compact quartz fittings
Fit.ConnectionTolerance = 0.035
Fit.DirectionTolerance = -0.995

function Fit.Ports(model)
    local ports = {}
    if not model or not model:IsA("Model") or not model.PrimaryPart then
        return ports
    end
    for _,descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Attachment")
            and descendant:GetAttribute("QuartzPort") == true
            and descendant.Parent and descendant.Parent:IsA("BasePart") then
            table.insert(ports,descendant)
        end
    end
    table.sort(ports,function(a,b) return a.Name<b.Name end)
    return ports
end

function Fit.HasPorts(model)
    return #Fit.Ports(model)>0
end

function Fit.IsTube(model)
    return model~=nil and model:IsA("Model")
        and model:GetAttribute("QuartzTube")==true
        and model.PrimaryPart~=nil
end

local function compatible(a,b)
    local d1,d2=a:GetAttribute("DiameterU"),b:GetAttribute("DiameterU")
    if type(d1)~="number" or type(d2)~="number"
        or math.abs(d1-d2)>0.001 then
        return false
    end
    local m1=a:GetAttribute("Medium")
    local m2=b:GetAttribute("Medium")
    if type(m1)=="string" and type(m2)=="string"
        and m1~="Universal" and m2~="Universal" and m1~=m2 then
        return false
    end
    return true
end

function Fit.AreConnected(a,b,sourcePortName,targetPortName)
    if not a or not b or a==b then return false end
    for _,portA in ipairs(Fit.Ports(a)) do
        if sourcePortName==nil or portA.Name==sourcePortName then
            for _,portB in ipairs(Fit.Ports(b)) do
                if (targetPortName==nil or portB.Name==targetPortName)
                    and compatible(portA,portB)
                    and (portA.WorldPosition-portB.WorldPosition).Magnitude
                        <= Fit.ConnectionTolerance
                    and portA.WorldCFrame.LookVector:Dot(
                        portB.WorldCFrame.LookVector
                    ) <= Fit.DirectionTolerance then
                    return true
                end
            end
        end
    end
    return false
end

function Fit.Find(ghost,targets,ignored,preferred)
    local sources=Fit.Ports(ghost)
    if #sources==0 then return nil end
    local best,bestScore=nil,math.huge
    for _,target in ipairs(targets) do
        if not target or target==ghost or not target.Parent
            or (ignored and ignored[target])
            or not target.PrimaryPart then continue end
        local sourceGroup=ghost:GetAttribute("ComponentId")
        if type(sourceGroup)=="string" and sourceGroup~=""
            and target:GetAttribute("ComponentId")==sourceGroup then
            continue
        end
        for _,sourcePort in ipairs(sources) do
            for _,targetPort in ipairs(Fit.Ports(target)) do
                if not compatible(sourcePort,targetPort) then continue end
                local distance=(sourcePort.WorldPosition
                    -targetPort.WorldPosition).Magnitude
                if distance>Fit.CaptureDistance then continue end
                -- Oppose the socket outward directions and align their centers.
                local desiredPort=targetPort.WorldCFrame
                    *CFrame.Angles(0,math.pi,0)
                local delta=desiredPort*sourcePort.WorldCFrame:Inverse()
                local pose=delta*ghost:GetPivot()
                local score=distance-(if target==preferred then 0.025 else 0)
                if score<bestScore then
                    bestScore=score
                    best={
                        kind="Quartz",
                        relationKind="FitOnly",
                        target=target,
                        source=ghost,
                        cf=pose,
                        score=score,
                        approach=targetPort.WorldPosition,
                        sourcePortName=sourcePort.Name,
                        targetPortName=targetPort.Name,
                        offsetUnits=0,
                        rollDegrees=0,
                    }
                end
            end
        end
    end
    return best
end

-- Query connectivity on demand; does not create mechanical constraints.
function Fit.Networks(folder,ownerUserId)
    if not folder then return {} end
    local nodes={}
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and Fit.HasPorts(model)
            and (ownerUserId==nil
                or model:GetAttribute("OwnerUserId")==ownerUserId) then
            table.insert(nodes,model)
        end
    end
    local networks,seen={},{}
    for _,start in ipairs(nodes) do
        if seen[start] then continue end
        local queue={start}
        local head=1
        local connected={}
        seen[start]=true
        while head<=#queue do
            local current=queue[head]
            head+=1
            table.insert(connected,current)
            for _,candidate in ipairs(nodes) do
                if not seen[candidate] and Fit.AreConnected(current,candidate) then
                    seen[candidate]=true
                    table.insert(queue,candidate)
                end
            end
        end
        table.insert(networks,connected)
    end
    return networks
end

return table.freeze(Fit)
