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
local DEFAULT_ANGLE=125

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
    local outward0=first.CFrame.RightVector*sign0
    local outward1=second.CFrame.RightVector*sign1
    local angle=math.deg(math.acos(math.clamp(
        -outward0:Dot(outward1),-1,1)))
    if angle>DEFAULT_ANGLE then
        return nil,"Joint elbow exceeds the 125-degree articulation limit"
    end
    return {
        Point=(p0+p1)*0.5,Radius=radius,Angle=DEFAULT_ANGLE,
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
    local shell=Instance.new("Part")
    shell.Name="ElbowCover"
    shell.Shape=Enum.PartType.Ball
    shell.Size=Vector3.one*g.Radius*2.4
    shell.Color=CAP_COLOR
    shell.Material=Enum.Material.Metal
    shell.CFrame=CFrame.new(g.Point)
    shell.Anchored=not physical
    shell.Massless=true
    shell.CanCollide=false
    shell.CanTouch=false
    shell.CanQuery=false
    shell.CastShadow=false
    shell:SetAttribute("OPENWORKS_VisualOnly",true)
    shell.Parent=model
    if physical then
        local w=Instance.new("WeldConstraint")
        w.Name="VectorCoverFollow"
        w.Part0=sourcePart
        w.Part1=shell
        w.Parent=model
    end
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
    device.ReactionTorqueEnabled=false
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
    ball.LimitsEnabled=true
    ball.UpperAngle=g.Angle
    ball.TwistLimitsEnabled=false
    -- Do not use native angular friction: it also resists shaft roll.
    -- A custom perpendicular-axis bushing stabilizes only the elbow.
    ball.MaxFrictionTorque=0
    ball.Radius=g.Radius
    ball:SetAttribute("AuthoredRelationId",relation:GetAttribute("RelationId"))
    ball.Parent=runtime
    cap(runtime,g,true,p0)

    local result={
        PartA=p0,PartB=p1,Sign=g.SpinSign,
        KinematicA=kinematicA,KinematicB=kinematicB,
        IdA=a:GetAttribute("InstanceId"),
        IdB=b:GetAttribute("InstanceId"),
        PhaseError=0,MaxSlip=0.40,
        Constraint=ball,
    }
    local id=relation:GetAttribute("RelationId")
    -- An ordinary free ball socket lets the wheel-side shaft hang down
    -- under gravity. Add a limited, damped angular bushing that restores
    -- its AUTHORED elbow angle while leaving axial rotation completely free.
    -- Gear-authored bodies are CFrame-driven and must not receive native
    -- torque; apply only to the non-kinematic side in mixed graphs.
    if not (kinematicA and kinematicB) then
        local reference=if kinematicB then p1 else p0
        local moving=if kinematicB then p0 else p1
        local movingAttachment=if kinematicB then at0 else at1
        result.TiltReference=reference
        result.TiltPart=moving
        result.TiltRestReferenceAxis=reference.CFrame.RightVector
        result.TiltRestAxis=moving.CFrame.RightVector
        result.TiltDrive=torque(runtime,movingAttachment,
            "VectorElbowTiltSupport",id)
        if not kinematicA and not kinematicB then
            result.TiltReaction=torque(runtime,at0,
                "VectorElbowSupportReaction",id)
        end
    end
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
    if j.TiltDrive then j.TiltDrive.Torque=Vector3.zero end
    if j.TiltReaction then j.TiltReaction.Torque=Vector3.zero end
    if j.TorqueB then j.TorqueB.Torque=Vector3.zero end
    if j.Motor then j.Motor.Enabled=false end
    j.PhaseError=0
end

-- Minimum rotation from the rest reference axis to the current one,
-- explicitly ignoring shaft roll. Otherwise each drivetrain revolution
-- would rotate the elbow's rest orientation and fight wheel steering.
local function referenceSwing(oldAxis,newAxis)
    local dot=math.clamp(oldAxis:Dot(newAxis),-1,1)
    if dot>0.999999 then return CFrame.identity end
    local cross=oldAxis:Cross(newAxis)
    if cross.Magnitude<1e-5 then
        local side=if math.abs(oldAxis:Dot(Vector3.yAxis))<0.9
            then Vector3.yAxis else Vector3.xAxis
        return CFrame.fromAxisAngle(oldAxis:Cross(side).Unit,math.pi)
    end
    return CFrame.fromAxisAngle(cross.Unit,math.acos(dot))
end

-- A compliant angular bushing, not a rigid AlignOrientation. Only the
-- TWO tilt degrees of freedom are stabilized; shaft roll (the driven DOF)
-- receives no restoring torque. Actual suspension/steering forces can
-- still articulate the joint against this bounded resistance.
local function stabilizeElbow(j)
    local moving=j.TiltPart
    local reference=j.TiltReference
    if not moving or not reference then return end
    local rotation=referenceSwing(j.TiltRestReferenceAxis,
        reference.CFrame.RightVector)
    local desired=rotation:VectorToWorldSpace(j.TiltRestAxis)
    local current=moving.CFrame.RightVector
    local tiltError=current:Cross(desired)
    local angularVelocity=moving.AssemblyAngularVelocity
    local lateralVelocity=angularVelocity-current*angularVelocity:Dot(current)
    local mass=math.clamp(moving.AssemblyMass,0.1,35)
    local strength=math.clamp(
        mass*workspace.Gravity*math.clamp(moving.Size.X*0.5,0.2,1.4),
        7,3500)
    local correction=tiltError*(strength*3.5)
        -lateralVelocity*(strength*0.55)
    local maxTorque=strength*1.5
    if correction.Magnitude>maxTorque then
        correction=correction.Unit*maxTorque
    end
    -- Axial projection is removed explicitly, including any damping.
    correction-=current*correction:Dot(current)
    j.TiltDrive.Torque=correction
    if j.TiltReaction then
        j.TiltReaction.Torque=-correction
    end
end

function VectorJoint.Step(j,dt,gears,backdriven)
    if not j.PartA.Parent or not j.PartB.Parent then
        VectorJoint.Stop(j)
        return
    end
    local axisA=j.PartA.CFrame.RightVector
    local axisB=j.PartB.CFrame.RightVector
    if j.TiltDrive then stabilizeElbow(j) end
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
