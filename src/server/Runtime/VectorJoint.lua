--!strict
-- OPENWORKS Vector Joint: a zero-span, two-shaft articulation and 1:1 drive.
-- No added axle, extension, telescoping geometry or physical elbow.
-- At a real adjoining shaft-end pivot, a BallSocketConstraint carries
-- translation and a balanced axial torque servo transmits spin in both
-- directions. A single cosmetic metal cap conceals the junction.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Alignment=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))

local VectorJoint={}
local CAP_COLOR=Color3.fromRGB(138,153,166)
local RIM_COLOR=Color3.fromRGB(73,86,101)

local function shaftEnd(model,toward)
    local part=model.PrimaryPart
    local axis=part.CFrame.RightVector
    local sign=if (toward-part.Position):Dot(axis)>=0 then 1 else -1
    return part.Position+axis*sign*part.Size.X*0.5,sign
end

-- Authored joint must occupy the actual adjoining end faces. No virtual
-- driveshaft spanning a gap is allowed, even when both shafts are angled.
function VectorJoint.Measure(a,b)
    if a==b or not Alignment.IsShaft(a) or not Alignment.IsShaft(b)
        or not a.PrimaryPart or not b.PrimaryPart then
        return nil,"Vector Joint requires two separate shaft primitives"
    end
    local first=a.PrimaryPart
    local second=b.PrimaryPart
    local p0,sign0=shaftEnd(a,second.Position)
    local p1,sign1=shaftEnd(b,first.Position)
    local dia=math.min(first.Size.Y,first.Size.Z,second.Size.Y,second.Size.Z)
    local radius=math.clamp(dia*0.64,0.025,0.38)
    local gap=(p1-p0).Magnitude
    local allowance=math.clamp(dia*0.32,0.018,0.12)
    if gap>allowance then
        return nil,string.format(
            "Bring the shaft END FACES together (gap %.3f, limit %.3f studs)",
            gap,allowance)
    end
    return {
        Point=(p0+p1)*0.5,Radius=radius,
        -- Constant throughout articulation: moving the elbow cannot
        -- reverse the spin sign or turn a 1:1 joint into a gearbox.
        SpinSign=-sign0*sign1,
    }
end

local function attachment(part,name,point)
    local a=Instance.new("Attachment")
    a.Name=name
    a.CFrame=part.CFrame:ToObjectSpace(CFrame.new(point))
    a.Parent=part
    return a
end

local function cap(parent,g,physical,sourcePart)
    local model=Instance.new("Folder")
    model.Name="VectorJointHardware"
    model.Parent=parent
    if physical then
        -- Simulated cover is a pure shaft-relative adornment, NOT a
        -- separate unanchored Part. It has zero mass and cannot fall off.
        local shell=Instance.new("SphereHandleAdornment")
        shell.Name="ElbowCover"
        shell.Adornee=sourcePart
        shell.CFrame=sourcePart.CFrame:ToObjectSpace(CFrame.new(g.Point))
        shell.Radius=g.Radius*1.2
        shell.Color3=CAP_COLOR
        shell.AlwaysOnTop=false
        shell.Transparency=0
        shell.Parent=model
        return shell
    end
    local shell=Instance.new("Part")
    shell.Name="ElbowCover"
    shell.Shape=Enum.PartType.Ball
    shell.Size=Vector3.one*g.Radius*2.4
    shell.Color=CAP_COLOR
    shell.Material=Enum.Material.Metal
    shell.CFrame=CFrame.new(g.Point)
    shell.Anchored=true
    shell.Massless=true
    shell.CanCollide=false
    shell.CanTouch=false
    shell.CanQuery=false
    shell.CastShadow=false
    shell:SetAttribute("OPENWORKS_VisualOnly",true)
    shell.Parent=model
    return shell
end

function VectorJoint.Hardware(parent,g,physical,sourcePart)
    return cap(parent,g,physical,sourcePart)
end

local function torque(runtime,attach,name,id)
    local device=Instance.new("Torque")
    device.Name=name
    device.Attachment0=attach
    device.RelativeTo=Enum.ActuatorRelativeTo.World
    -- Torque has no ReactionTorqueEnabled member. We apply opposing
    -- torque explicitly on each shaft in Step for bidirectional drive.
    device.Torque=Vector3.zero
    device:SetAttribute("AuthoredRelationId",id)
    device.Parent=runtime
    return device
end

-- Always attach at the same mathematical pivot on BOTH existing shafts.
-- The ball socket carries position, not axial spin; the paired Torques
-- carry equal/opposite axial efforts without locking steering articulation.
function VectorJoint.Compile(relation,a,b,runtime,kinematicA,kinematicB)
    local g,why=VectorJoint.Measure(a,b)
    if not g then error(why or "Vector Joint ends are separated") end
    local p0,p1=a.PrimaryPart,b.PrimaryPart
    local at0=attachment(p0,"VectorJointA",g.Point)
    local at1=attachment(p1,"VectorJointB",g.Point)
    local ball=Instance.new("BallSocketConstraint")
    ball.Name="VectorJointPivot"
    ball.Attachment0=at0
    ball.Attachment1=at1
    -- This is a real 3-axis pivot. No cone limit or elbow bushing:
    -- grounding ONE shaft supports the other via this constraint.
    ball.LimitsEnabled=false
    ball.TwistLimitsEnabled=false
    ball.MaxFrictionTorque=0
    ball.Radius=g.Radius
    ball.Enabled=true
    ball:SetAttribute("AuthoredRelationId",relation:GetAttribute("RelationId"))
    ball.Parent=runtime
    -- A position-only coincidence servo backs up the native socket under
    -- gravity/large mass ratios. It does NOT align shaft orientations or
    -- restrict spin, so the output is free to swing around the pivot.
    local lock=Instance.new("AlignPosition")
    lock.Name="VectorJointPinLock"
    lock.Mode=Enum.PositionAlignmentMode.TwoAttachment
    lock.Attachment0=at0
    lock.Attachment1=at1
    lock.RigidityEnabled=true
    lock.ReactionForceEnabled=true
    lock.ApplyAtCenterOfMass=false
    lock.Enabled=true
    lock:SetAttribute("AuthoredRelationId",relation:GetAttribute("RelationId"))
    lock.Parent=runtime
    cap(runtime,g,true,p0)

    local result={
        PartA=p0,PartB=p1,Sign=g.SpinSign,
        KinematicA=kinematicA,KinematicB=kinematicB,
        IdA=a:GetAttribute("InstanceId"),
        IdB=b:GetAttribute("InstanceId"),
        PhaseError=0,MaxSlip=0.40,
        Constraint=ball,PositionLock=lock,
        Attachment0=at0,Attachment1=at1,
        ReportedDrift=false,
    }
    local id=relation:GetAttribute("RelationId")
    if not kinematicA and not kinematicB then
        result.TorqueA=torque(runtime,at0,"VectorDriveReaction",id)
        result.TorqueB=torque(runtime,at1,"VectorDriveOutput",id)
    elseif kinematicA~=kinematicB then
        -- The existing kinematic gear engine cannot receive physical
        -- torque. Native shaft receives a bounded speed actuator while
        -- GearKinematics is driven backwards by measured native rotation.
        local nativeAt=if kinematicA then at1 else at0
        local motor=Instance.new("AngularVelocity")
        motor.Name="VectorKinematicBridge"
        motor.Attachment0=nativeAt
        motor.RelativeTo=Enum.ActuatorRelativeTo.World
        motor.ReactionTorqueEnabled=false
        motor.MaxTorque=math.clamp(
            (if kinematicA then p1 else p0).AssemblyMass*350,30,10000)
        motor.AngularVelocity=Vector3.zero
        motor.Enabled=false
        motor:SetAttribute("AuthoredRelationId",id)
        motor.Parent=runtime
        result.Motor=motor
        result.NativePart=if kinematicA then p1 else p0
        result.GearId=if kinematicA then result.IdA else result.IdB
    end
    return result
end

function VectorJoint.Stop(j)
    if j.TorqueA then j.TorqueA.Torque=Vector3.zero end
    if j.TorqueB then j.TorqueB.Torque=Vector3.zero end
    if j.Motor then j.Motor.Enabled=false end
    j.PhaseError=0
end

function VectorJoint.Step(j,dt,gears,backdriven)
    if not j.PartA.Parent or not j.PartB.Parent then
        VectorJoint.Stop(j)
        return
    end
    local axisA=j.PartA.CFrame.RightVector
    local axisB=j.PartB.CFrame.RightVector
    -- A diagnostic only: socket separation is never hidden by teleporting
    -- either shaft. The pin and position-lock constraints own translation.
    local gap=(j.Attachment0.WorldPosition-j.Attachment1.WorldPosition).Magnitude
    if gap>math.max(0.11,j.PartA.Size.Y*0.5) then
        if not j.ReportedDrift then
            warn(string.format("[OPENWORKS][VECTOR] Joint pivot drift: %.3f studs",gap))
            j.ReportedDrift=true
        end
    else
        j.ReportedDrift=false
    end
    if j.Motor then
        local gearPart=if j.KinematicA then j.PartA else j.PartB
        local speed=gears and gears:AngularSpeedFor(j.GearId,
            gearPart.CFrame.RightVector) or 0
        local native=j.NativePart
        local nativeAxis=native.CFrame.RightVector
        local sign=j.Sign
        -- Native->gear input must remain free of a competing motor.
        local driven=backdriven==j.GearId
        j.Motor.Enabled=not driven and math.abs(speed)>0.02
        j.Motor.AngularVelocity=nativeAxis*(speed*sign)
        return
    end
    if not j.TorqueA or not j.TorqueB then return end
    local omegaA=j.PartA.AssemblyAngularVelocity:Dot(axisA)
    local omegaB=j.PartB.AssemblyAngularVelocity:Dot(axisB)
    if not (omegaA==omegaA and omegaB==omegaB) then
        VectorJoint.Stop(j)
        return
    end
    local slip=math.clamp(omegaA-j.Sign*omegaB,-80,80)
    j.PhaseError=math.clamp(
        j.PhaseError+slip*math.clamp(dt,0,0.05),
        -j.MaxSlip,j.MaxSlip)
    local mass=math.clamp(math.min(j.PartA.AssemblyMass,
        j.PartB.AssemblyMass),0.18,40)
    local effort=math.clamp((slip*22+j.PhaseError*75)*mass,
        -400*mass,400*mass)
    -- Identical axial torque with opposite reactions: either side can
    -- backdrive the other. No motor, driver direction or external spin
    -- is invented when both shafts are at rest.
    j.TorqueA.Torque=-axisA*effort
    j.TorqueB.Torque=axisB*(j.Sign*effort)
end

return VectorJoint
