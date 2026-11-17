--!strict
-- A single saved mechanical Rope connects two existing parts. It is a
-- tension-only physical link; never welds, anchors, or pushes the endpoints.
-- 1 U = Grid.Unit studs. Rope lengths are stored in studs; the winch
-- speed is authored in U/second and converted exactly once here.
local Grid=require(script.Parent:WaitForChild("GridMath"))
local Spring=require(script.Parent:WaitForChild("SpringMath"))

local Rope={}
Rope.DefaultInKey="Z"
Rope.DefaultOutKey="X"
Rope.DefaultSpeedU=4
Rope.DefaultForce=15000

local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function allowedKey(key)
    -- Steering ropes may use A/D even though drivetrain motor bindings
    -- intentionally avoid character-movement keys.
    return type(key)=="string" and (
        key:match("^[A-Z]$")~=nil
        or key=="One" or key=="Two"
        or key=="Three" or key=="Four")
end

function Rope.Frames(source,target)
    -- The authored opening-facing mount points are the same as general
    -- springs; they remain on their respective rigid parts after rotation.
    return Spring.Frames(source,target,"General")
end

function Rope.Settings(request,initialDistance)
    if not finite(initialDistance) or initialDistance<0 then
        return nil,"Rope endpoints are invalid"
    end
    local initial=if request.ropeLength~=nil then request.ropeLength
        else math.max(Grid.Unit*Grid.MinSizeStepU,
            initialDistance+Grid.Unit*0.5)
    local minimum=if request.ropeMinLength~=nil then request.ropeMinLength
        else Grid.Unit*Grid.MinSizeStepU
    local maximum=if request.ropeMaxLength~=nil then request.ropeMaxLength
        else initial+Grid.Unit*Grid.MaxUnits
    local speedU=if request.ropeSpeedU~=nil then request.ropeSpeedU
        else Rope.DefaultSpeedU
    local force=if request.ropeForce~=nil then request.ropeForce
        else Rope.DefaultForce
    local inKey=request.ropeInKey or Rope.DefaultInKey
    local outKey=request.ropeOutKey or Rope.DefaultOutKey
    -- Finite, positive physical measurements are essential. These are
    -- validity checks, not per-assembly part/constraint safety limits.
    if not finite(initial) or not finite(minimum) or not finite(maximum)
        or minimum<Grid.Unit*Grid.MinSizeStepU-1e-5
        or maximum>4096 or minimum>initial or initial>maximum then
        return nil,"Rope length must stay between the minimum and maximum"
    end
    if not finite(speedU) or speedU<0.25 or speedU>64 then
        return nil,"Rope speed must be 0.25–64 U/s"
    end
    if not finite(force) or force<10 or force>1000000 then
        return nil,"Rope winch force must be 10–1,000,000"
    end
    if not allowedKey(inKey) or not allowedKey(outKey) or inKey==outKey then
        return nil,"Choose two different supported rope control keys"
    end
    return {
        ropeLength=initial,ropeMinLength=minimum,ropeMaxLength=maximum,
        ropeSpeedU=speedU,ropeForce=force,
        ropeInKey=inKey,ropeOutKey=outKey,
    }
end

function Rope.Attributes(relation)
    return {
        ropeLength=relation:GetAttribute("RopeLength"),
        ropeMinLength=relation:GetAttribute("RopeMinLength"),
        ropeMaxLength=relation:GetAttribute("RopeMaxLength"),
        ropeSpeedU=relation:GetAttribute("RopeSpeedU"),
        ropeForce=relation:GetAttribute("RopeForce"),
        ropeInKey=relation:GetAttribute("RopeInKey"),
        ropeOutKey=relation:GetAttribute("RopeOutKey"),
    }
end

function Rope.Write(relation,settings)
    relation:SetAttribute("RopeLength",settings.ropeLength)
    relation:SetAttribute("RopeMinLength",settings.ropeMinLength)
    relation:SetAttribute("RopeMaxLength",settings.ropeMaxLength)
    relation:SetAttribute("RopeSpeedU",settings.ropeSpeedU)
    relation:SetAttribute("RopeForce",settings.ropeForce)
    relation:SetAttribute("RopeInKey",settings.ropeInKey)
    relation:SetAttribute("RopeOutKey",settings.ropeOutKey)
end

function Rope.Compile(source,target,part0,part1,parent,settings,id,authored)
    local point0,point1=Rope.Frames(source,target)
    local att0=Instance.new("Attachment")
    att0.Name="RopeMount0"
    att0.CFrame=part0.CFrame:ToObjectSpace(CFrame.new(point0))
    att0.Parent=part0
    local att1=Instance.new("Attachment")
    att1.Name="RopeMount1"
    att1.CFrame=part1.CFrame:ToObjectSpace(CFrame.new(point1))
    att1.Parent=part1
    if authored then
        for _,att in ipairs({att0,att1}) do
            local ref=Instance.new("ObjectValue")
            ref.Name="ManagedAttachment"
            ref.Value=att
            ref.Parent=parent
        end
    end
    local rope=Instance.new("RopeConstraint")
    rope.Name="Rope"
    rope.Attachment0=att0
    rope.Attachment1=att1
    rope.Length=settings.ropeLength
    rope.Visible=true
    rope.Thickness=math.max(0.012,Grid.Unit*0.10)
    rope.Restitution=0
    rope.WinchEnabled=false
    rope.WinchTarget=settings.ropeLength
    rope.WinchSpeed=settings.ropeSpeedU*Grid.Unit
    rope.WinchForce=settings.ropeForce
    rope.WinchResponsiveness=30
    rope:SetAttribute("AuthoredRelationId",id)
    rope.Parent=parent
    return rope
end

function Rope.NewRuntime(rope,relation)
    local settings=Rope.Attributes(relation)
    return {
        Constraint=rope,
        RelationId=relation:GetAttribute("RelationId"),
        SeatId=relation:GetAttribute("SeatId"),
        InKey=settings.ropeInKey or Rope.DefaultInKey,
        OutKey=settings.ropeOutKey or Rope.DefaultOutKey,
        SpeedU=settings.ropeSpeedU or Rope.DefaultSpeedU,
        Force=settings.ropeForce or Rope.DefaultForce,
        Min=settings.ropeMinLength or Grid.Unit*Grid.MinSizeStepU,
        Max=settings.ropeMaxLength or rope.Length,
        Target=rope.Length,
        InHeld=false,OutHeld=false,LastIn=0,LastOut=0,
    }
end

function Rope.Stop(runtime)
    runtime.InHeld=false
    runtime.OutHeld=false
    runtime.LastIn=0
    runtime.LastOut=0
    local rope=runtime.Constraint
    if not rope or not rope.Parent then return end
    -- Idle rope is a limit, never a powered rod. Do not instantly shorten
    -- through the current separation if the winch is still under load.
    local current=rope.CurrentDistance
    runtime.Target=math.clamp(math.max(runtime.Target,current),
        runtime.Min,runtime.Max)
    rope.WinchEnabled=false
    rope.Length=runtime.Target
    rope.WinchTarget=runtime.Target
end

function Rope.Input(runtime,key,holding,now)
    if key==runtime.InKey then
        runtime.InHeld=holding
        runtime.LastIn=if holding then now else 0
    elseif key==runtime.OutKey then
        runtime.OutHeld=holding
        runtime.LastOut=if holding then now else 0
    end
end

function Rope.Step(runtime,dt,now)
    local rope=runtime.Constraint
    if not rope or not rope.Parent then return end
    if runtime.InHeld and now-runtime.LastIn>0.4 then runtime.InHeld=false end
    if runtime.OutHeld and now-runtime.LastOut>0.4 then runtime.OutHeld=false end
    local direction=(if runtime.InHeld then -1 else 0)
        +(if runtime.OutHeld then 1 else 0)
    if direction==0 then
        if rope.WinchEnabled then Rope.Stop(runtime) end
        return
    end
    local change=math.max(0,math.min(dt,0.1))*runtime.SpeedU*Grid.Unit
    if direction>0 then
        -- Paying out cannot push. Increasing the maximum separation
        -- simply gives the two bodies slack to separate naturally.
        if rope.WinchEnabled then Rope.Stop(runtime) end
        runtime.Target=math.min(runtime.Max,runtime.Target+change)
        rope.WinchEnabled=false
        rope.Length=runtime.Target
        rope.WinchTarget=runtime.Target
    else
        -- Only retraction needs active force. Positive WinchSpeed is
        -- mandated by Roblox; the direction is expressed in WinchTarget.
        runtime.Target=math.max(runtime.Min,runtime.Target-change)
        rope.WinchTarget=runtime.Target
        rope.WinchSpeed=runtime.SpeedU*Grid.Unit
        rope.WinchForce=runtime.Force
        -- A Roblox winch is a separation servo: if activated while the
        -- rope is slack it could PUSH the anchors toward a longer target.
        -- Only enable it when the actual separation EXCEEDS target length.
        -- Otherwise shorten the passive maximum without applying force.
        if rope.CurrentDistance>runtime.Target+Grid.Unit*0.01 then
            rope.Length=math.max(rope.Length,rope.CurrentDistance)
            rope.WinchEnabled=true
        else
            rope.WinchEnabled=false
            rope.Length=runtime.Target
        end
    end
end

function Rope.ApplyTuning(runtime,relation)
    local settings=Rope.Attributes(relation)
    runtime.InKey=settings.ropeInKey or Rope.DefaultInKey
    runtime.OutKey=settings.ropeOutKey or Rope.DefaultOutKey
    runtime.SpeedU=settings.ropeSpeedU or Rope.DefaultSpeedU
    runtime.Force=settings.ropeForce or Rope.DefaultForce
    runtime.Min=settings.ropeMinLength or runtime.Min
    runtime.Max=settings.ropeMaxLength or runtime.Max
    runtime.Target=math.clamp(settings.ropeLength or runtime.Target,
        runtime.Min,runtime.Max)
    local rope=runtime.Constraint
    rope.WinchEnabled=false
    rope.Length=math.max(runtime.Target,rope.CurrentDistance)
    rope.WinchTarget=runtime.Target
    rope.WinchSpeed=runtime.SpeedU*Grid.Unit
    rope.WinchForce=runtime.Force
    runtime.InHeld=false
    runtime.OutHeld=false
end

return table.freeze(Rope)
