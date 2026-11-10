--!strict
-- Shape-independent, native-physics springs. A spring connects two selected
-- primitives (which may belong to two larger manually joined components).
-- It does not require matching plates, centered faces or a particular shape.
-- Shaft-in-bore springs retain the optional physical prismatic guide.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local Bore=require(script.Parent:WaitForChild("BoreClearance"))
local Grid=require(script.Parent:WaitForChild("GridMath"))

local Spring={}
local EDGE_CLEARANCE=Grid.Unit*0.12

local function thinAxis(model)
    local s=model.PrimaryPart.Size
    if s.X<=s.Y and s.X<=s.Z then return "X" end
    if s.Y<=s.Z then return "Y" end
    return "Z"
end

local function plate(model)
    if not model or not model.PrimaryPart then return false end
    local name=string.lower(tostring(model:GetAttribute("TemplateId") or model.Name))
    if string.find(name,"gear",1,true) or string.find(name,"bolt",1,true)
        or string.find(name,"cylinder",1,true) or string.find(name,"tube",1,true)
        then return false end
    if string.find(name,"plate",1,true) then return true end
    local s=model.PrimaryPart.Size
    local axis=thinAxis(model)
    local thickness=if axis=="X" then s.X elseif axis=="Y" then s.Y else s.Z
    return thickness<=math.max(s.X,s.Y,s.Z)*0.45
end

local function groupEnvelope(model)
    -- Selection is through a model; if it's editor-grouped, show the
    -- spring across the WHOLE component envelope, not just one hole block.
    -- Group membership NEVER implies physical welding.
    local parent=model.Parent
    local group=model:GetAttribute("ComponentId")
    local owner=model:GetAttribute("OwnerUserId")
    local low=Vector3.new(math.huge,math.huge,math.huge)
    local high=-low
    local parts=0
    local function add(item)
        for _,part in ipairs(item:GetDescendants()) do
            if part:IsA("BasePart") and part:GetAttribute("GearPivotOnly")~=true then
                local cf=part.CFrame
                local size=part.Size*0.5
                local right,up,look=cf.RightVector,cf.UpVector,cf.LookVector
                local ext=Vector3.new(
                    math.abs(right.X)*size.X+math.abs(up.X)*size.Y+math.abs(look.X)*size.Z,
                    math.abs(right.Y)*size.X+math.abs(up.Y)*size.Y+math.abs(look.Y)*size.Z,
                    math.abs(right.Z)*size.X+math.abs(up.Z)*size.Y+math.abs(look.Z)*size.Z)
                low=Vector3.new(math.min(low.X,cf.Position.X-ext.X),
                    math.min(low.Y,cf.Position.Y-ext.Y),
                    math.min(low.Z,cf.Position.Z-ext.Z))
                high=Vector3.new(math.max(high.X,cf.Position.X+ext.X),
                    math.max(high.Y,cf.Position.Y+ext.Y),
                    math.max(high.Z,cf.Position.Z+ext.Z))
                parts+=1
            end
        end
    end
    if type(group)=="string" and group~=""
        and parent and parent.Name=="OPENWORKS_Constructed" then
        for _,candidate in ipairs(parent:GetChildren()) do
            if candidate:IsA("Model")
                and candidate:GetAttribute("OwnerUserId")==owner
                and candidate:GetAttribute("ComponentId")==group then
                add(candidate)
            end
        end
    else
        add(model)
    end
    if parts==0 then
        return model:GetPivot().Position,model.PrimaryPart.Size*0.5
    end
    return (low+high)*0.5,(high-low)*0.5
end

function Spring.Mode(source,target)
    -- Guided piston is a special case, never a prerequisite for a spring.
    if source and target and Alignment.IsShaft(source)
        and Alignment.TargetAxis(target) and Bore.ShaftFits(source,target) then
        return "Piston"
    end
    if plate(source) and plate(target) then return "Plates" end
    return "General"
end

function Spring.Validate(source,target)
    if not source or not target or source==target
        or not source.PrimaryPart or not target.PrimaryPart then
        return nil,"Choose two different valid components"
    end
    -- Any shapes, sizes, rotations and spacing are allowed. Limits on
    -- ownership, build range and relationship count live on the server.
    return Spring.Mode(source,target)
end

function Spring.Frames(source,target,mode)
    local sc,tc=source:GetPivot(),target:GetPivot()
    if mode=="Piston" then
        local localAxis=Alignment.TargetAxis(target)
        local axis=tc:VectorToWorldSpace(localAxis).Unit
        local toward=if (sc.Position-tc.Position):Dot(axis)>=0 then axis else -axis
        local s=target.PrimaryPart.Size
        local housingLength=math.abs(localAxis.X)*s.X+
            math.abs(localAxis.Y)*s.Y+math.abs(localAxis.Z)*s.Z
        local shaftLength=source.PrimaryPart.Size.X
        return tc.Position-toward*housingLength*0.27,
            sc.Position+toward*shaftLength*0.27
    end

    local sourceCenter,sourceHalf=groupEnvelope(source)
    local targetCenter,targetHalf=groupEnvelope(target)
    local delta=sourceCenter-targetCenter
    local distance=delta.Magnitude
    local direction=if distance>0.0001 then delta.Unit else tc.UpVector
    local function reach(half)
        return math.abs(direction.X)*half.X+
            math.abs(direction.Y)*half.Y+math.abs(direction.Z)*half.Z
    end
    -- Attach near the visible facing surfaces when there is room.
    -- For interpenetrating/enclosed geometry keep the anchor separation
    -- well-defined rather than crossing two spring endpoints.
    local cap=distance*0.45
    local fromTarget=math.min(reach(targetHalf),cap)
    local fromSource=math.min(reach(sourceHalf),cap)
    if distance<=0.0001 then
        return tc.Position-direction*Grid.Unit*0.1,
            sc.Position+direction*Grid.Unit*0.1
    end
    return targetCenter+direction*fromTarget,
        sourceCenter-direction*fromSource
end

function Spring.Radius(source,target,mode)
    if mode=="Piston" then
        local bore=Bore.OpeningDiameter(target)
        local shaft=source.PrimaryPart.Size
        return math.max(0.025,math.min(
            (bore or math.min(shaft.Y,shaft.Z))*0.5,
            math.min(shaft.Y,shaft.Z)*0.65)-EDGE_CLEARANCE*0.3)
    end
    local a,ah=groupEnvelope(source)
    local b,bh=groupEnvelope(target)
    local delta=a-b
    local axis=if delta.Magnitude>0.001 then delta.Unit
        else source:GetPivot().UpVector
    local reference=if math.abs(axis.Y)<0.9 then Vector3.yAxis else Vector3.xAxis
    local right=axis:Cross(reference).Unit
    local up=axis:Cross(right).Unit
    local function span(half,vector)
        -- Axis-aligned bounds projected onto the two tangential directions.
        return math.abs(vector.X)*half.X+
            math.abs(vector.Y)*half.Y+math.abs(vector.Z)*half.Z
    end
    local maxRadius=math.min(
        span(ah,right),span(ah,up),span(bh,right),span(bh,up))
    -- Never claim a rigid cross section wider than either component.
    -- Actual spring is a separate constraint, not solid generated geometry.
    return math.max(0.025,maxRadius-EDGE_CLEARANCE)
end

function Spring.Settings(request,length)
    local stiffness=request.stiffness or 120
    local damping=request.damping or 14
    local rest=if type(request.freeLength)=="number"
        then request.freeLength else math.max(0.05,length)
    if type(stiffness)~="number" or stiffness~=stiffness
        or stiffness<10 or stiffness>3000
        or type(damping)~="number" or damping~=damping
        or damping<0 or damping>300
        or type(rest)~="number" or rest~=rest
        or rest<0.05 or rest>Grid.MaxDistance*2 then
        return nil,"Spring stiffness 10–3000, damping 0–300, rest length must fit build range"
    end
    return {stiffness=stiffness,damping=damping,freeLength=rest}
end

return table.freeze(Spring)
