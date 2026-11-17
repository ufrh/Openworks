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
        -- The moving cap is real METAL geometry welded to the first
        -- simulated shaft. It has no collision or weight of its own.
        local weld=Instance.new("WeldConstraint")
        weld.Name="VectorElbowCoverFollow"
        weld.Part0=sourcePart
        weld.Part1=shell
        weld.Parent=model
    end
    return shell
end

function VectorJoint.Hardware(parent,g,physical,sourcePart)
    return cap(parent,g,physical,sourcePart)
end

function VectorJoint.RefreshHardware(relation,source,target)
    local hardware=relation:FindFirstChild("VectorJointHardware")
    local shell=hardware and hardware:FindFirstChild("ElbowCover")
    if not shell or not shell:IsA("BasePart") then return end
    local g=VectorJoint.Measure(source,target)
    if not g then return end
    shell.Size=Vector3.one*g.Radius*2.4
    shell.CFrame=CFrame.new(g.Point)
    shell.Material=Enum.Material.Metal
    shell.Color=CAP_COLOR
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

-- An explicitly driven upstream shaft can power the opposite side
-- without relying on a tiny passive slip torque. Drive only the output:
-- each relay is inactive until the real source shaft is commanded.
local function angularRelay(runtime,attach,name,id)
    local drive=Instance.new("AngularVelocity")
    drive.Name=name
    drive.Attachment0=attach
    drive.RelativeTo=Enum.ActuatorRelativeTo.World
    drive.ReactionTorqueEnabled=false
    drive.MaxTorque=3000
    drive.AngularVelocity=Vector3.zero
    drive.Enabled=false
    drive:SetAttribute("AuthoredRelationId",id)
    drive.Parent=runtime
    return drive
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
    cap(runtime,g,true,p0)

    local result={
        PartA=p0,PartB=p1,Sign=g.SpinSign,
        KinematicA=kinematicA,KinematicB=kinematicB,
        IdA=a:GetAttribute("InstanceId"),
        IdB=b:GetAttribute("InstanceId"),
        Constraint=ball,
        Attachment0=at0,Attachment1=at1,
        ReportedDrift=false,
    }
    local id=relation:GetAttribute("RelationId")
    if not kinematicA and not kinematicB then
        result.TorqueA=torque(runtime,at0,"VectorDriveReaction",id)
        result.TorqueB=torque(runtime,at1,"VectorDriveOutput",id)
        result.DriveA=angularRelay(runtime,at0,"VectorDriveShaftA",id)
        result.DriveB=angularRelay(runtime,at1,"VectorDriveShaftB",id)
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
    if j.Motor then
        j.Motor.AngularVelocity=Vector3.zero
        j.Motor.Enabled=false
    end
    if j.DriveA then
        j.DriveA.AngularVelocity=Vector3.zero
        j.DriveA.Enabled=false
    end
    if j.DriveB then
        j.DriveB.AngularVelocity=Vector3.zero
        j.DriveB.Enabled=false
    end
    j.RelaySide=nil
    j.RelaySpeed=0
end

-- A live motor, crank or gear train is an authoritative drive source.
-- The Vector Joint never runs two opposing speed actuators at once.
-- In the absence of a driven source it is a bidirectional passive
-- torque coupling, preserving coast and backdrive.
local function relay(j,dt,input,output,source,sign,side)
    if j.RelaySide~=side then
        j.RelaySide=side
        j.RelaySpeed=0
    end
    local axis=input.CFrame.RightVector.Unit
    local target=input.AssemblyAngularVelocity:Dot(axis)*sign
    local dtSafe=math.clamp(dt,0,0.07)
    -- Smooth the measured input so one physics solver tick cannot kick
    -- the entire downstream wheel or gear assembly sideways.
    local filtered=j.RelaySpeed+(target-j.RelaySpeed)
        *(1-math.exp(-16*dtSafe))
    local maxChange=math.max(3,math.abs(target)*4)*dtSafe
    j.RelaySpeed+=math.clamp(filtered-j.RelaySpeed,
        -maxChange,maxChange)
    local active=math.abs(j.RelaySpeed)>0.02
    output.MaxTorque=math.clamp(source.Torque or 3000,10,100000)
    local outputPart=if side=="A" then j.PartB else j.PartA
    output.AngularVelocity=outputPart.CFrame.RightVector.Unit*j.RelaySpeed
    output.Enabled=active
    if j.TorqueA then j.TorqueA.Torque=Vector3.zero end
    if j.TorqueB then j.TorqueB.Torque=Vector3.zero end
end

function VectorJoint.Step(j,dt,gears,backdriven,driveA,driveB)
    if not j.PartA.Parent or not j.PartB.Parent then
        VectorJoint.Stop(j)
        return
    end
    local axisA=j.PartA.CFrame.RightVector.Unit
    local axisB=j.PartB.CFrame.RightVector.Unit
    -- A vector joint cannot connect two already welded shafts: that is
    -- one rigid body with no relative rotational degree of freedom.
    local rootA=j.PartA.AssemblyRootPart
    local rootB=j.PartB.AssemblyRootPart
    if rootA and rootB and rootA==rootB then
        if not j.WarnedRigid then
            warn("[OPENWORKS][VECTOR] Shaft ends belong to the same "
                .."rigid body; remove the redundant weld")
            j.WarnedRigid=true
        end
        VectorJoint.Stop(j)
        return
    end
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
        local driven=backdriven==j.GearId
        j.Motor.Enabled=not driven and math.abs(speed)>0.02
        j.Motor.AngularVelocity=nativeAxis*(speed*j.Sign)
        return
    end
    if not j.TorqueA or not j.TorqueB then return end
    local omegaA=j.PartA.AssemblyAngularVelocity:Dot(axisA)
    local omegaB=j.PartB.AssemblyAngularVelocity:Dot(axisB)
    if not (omegaA==omegaA and omegaB==omegaB) then
        VectorJoint.Stop(j)
        return
    end

    -- The active input stays controlled by its actual motor/gear drive.
    -- Only the other shaft is velocity-driven: no competing motors and
    -- no PI windup. This is the crucial loaded-output torque path.
    if driveA and not driveB and j.DriveB then
        j.DriveA.Enabled=false
        relay(j,dt,j.PartA,j.DriveB,driveA,j.Sign,"A")
        return
    elseif driveB and not driveA and j.DriveA then
        j.DriveB.Enabled=false
        relay(j,dt,j.PartB,j.DriveA,driveB,j.Sign,"B")
        return
    end

    if j.DriveA then
        j.DriveA.Enabled=false
        j.DriveA.AngularVelocity=Vector3.zero
    end
    if j.DriveB then
        j.DriveB.Enabled=false
        j.DriveB.AngularVelocity=Vector3.zero
    end
    j.RelaySide=nil
    j.RelaySpeed=0

    -- Passive bidirectional coupling for unpowered motion. Do not
    -- regulate elbow tilt: only the two shaft-local spin components.
    -- The old controller used the REDUCED INERTIA of a tiny input rod,
    -- reducing efforts to effectively zero for a large wheel. Use a
    -- bounded assembly-aware inertial scale instead.
    local radiusA=math.max(0.10,
        math.min(j.PartA.Size.Y,j.PartA.Size.Z)*0.5)
    local radiusB=math.max(0.10,
        math.min(j.PartB.Size.Y,j.PartB.Size.Z)*0.5)
    local inertiaA=0.5*math.max(j.PartA.AssemblyMass,0.01)*radiusA^2
    local inertiaB=0.5*math.max(j.PartB.AssemblyMass,0.01)*radiusB^2
    local inertia=math.max(0.1,inertiaA,inertiaB)
    local slip=math.clamp(omegaA-j.Sign*omegaB,-25,25)
    local effort=math.clamp(slip*inertia*10,
        -math.min(2000,inertia*60),math.min(2000,inertia*60))
    j.TorqueA.Torque=-axisA*effort
    j.TorqueB.Torque=axisB*(j.Sign*effort)
end

return VectorJoint
