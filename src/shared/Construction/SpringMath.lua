--!strict
-- Shape-independent, native-physics springs. A spring connects two selected
-- primitives (which may belong to two larger manually joined components).
-- It does not require matching plates, centered faces or a particular shape.
-- A spring never creates a hidden slider, even between a shaft and a tube.
local Grid=require(script.Parent:WaitForChild("GridMath"))

local Spring={}
local EDGE_CLEARANCE=Grid.Unit*0.12

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

function Spring.Mode(_source,_target)
    return "General"
end

function Spring.Validate(source,target)
    if not source or not target or source==target
        or not source.PrimaryPart or not target.PrimaryPart then
        return nil,"Choose two different valid components"
    end
    return "General"
end

function Spring.Frames(source,target,mode)
    local sc,tc=source:GetPivot(),target:GetPivot()
    -- Free spring force has no geometry-specific guide.
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
    -- Size from full component bounds, independent of primitive type.
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
