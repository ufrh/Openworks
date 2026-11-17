#!/usr/bin/env python3
"""Active-engine source regression: native servos and powered Vector Joint drive.

Static integration checks only; a free chassis and loaded shaft must still
be playtested in Roblox Studio.
"""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def src(path):
    return (ROOT/path).read_text(encoding="utf-8")

physical=src("src/server/Runtime/PhysicalSimulationService.lua")
rack=src("src/server/Runtime/RackSimulationService.lua")
vector=src("src/server/Runtime/VectorJoint.lua")
gears=src("src/server/Runtime/GearTransmission.lua")
router=src("src/server/Runtime/UnifiedSimulationService.lua")

checks={
    "Normal assemblies route through active physical runtime":
        'return if rack then self.Rack else self.Physical' in router,
    "Physical native Servo receives direct key-selected target angle":
        'hinge.TargetAngle=if motor.On then motor.TargetAngle else 0' in physical
        and 'hinge.AngularSpeed=math.abs(motor.Speed)' in physical
        and 'hinge.ServoMaxTorque=motor.Torque' in physical
        and 'hinge.AngularResponsiveness=45' in physical,
    "Physical servo has no custom controller or second world drive":
        'ServoVelocity' not in physical
        and 'ServoTarget' not in physical
        and 'motor.DriveType=="Servo" then' in physical
        and 'if motor.DriveType=="Servo" then\n                -- Direct native servo control' in physical
        and 'if motor.On then\n                markVectorSource(session,shaft,motor.Torque)' in physical,
    "Rack physical servo is native; kinematic rack servo fails explicitly":
        'hinge.TargetAngle=if motor.On then motor.TargetAngle else 0' in rack
        and 'hinge.ActuatorType=Enum.ActuatorType.Servo' in rack
        and 'if motor.Kinematic and motor.DriveType=="Servo" then' in rack
        and 'ServoVelocity' not in rack
        and 'ServoTarget' not in rack,
    "Vector Joint retains unrestrained ball pivot":
        'Instance.new("BallSocketConstraint")' in vector
        and 'ball.TwistLimitsEnabled=false' in vector
        and 'ball.LimitsEnabled=false' in vector,
    "Vector Joint creates independent one-way driven output actuators":
        'result.DriveA=angularRelay(' in vector
        and 'result.DriveB=angularRelay(' in vector
        and 'if driveA and not driveB and j.DriveB then' in vector
        and 'elseif driveB and not driveA and j.DriveA then' in vector
        and 'j.DriveA.Enabled=false' in vector
        and 'j.DriveB.Enabled=false' in vector,
    "Vector drive uses measured upstream speed and bounded output torque":
        'input.AssemblyAngularVelocity:Dot(axis)*sign' in vector
        and 'output.MaxTorque=math.clamp(source.Torque or 3000,10,100000)' in vector
        and 'output.AngularVelocity=outputPart.CFrame.RightVector.Unit*j.RelaySpeed' in vector,
    "Vector shaft backdrive retains passive torque when no active power":
        'local slip=math.clamp(omegaA-j.Sign*omegaB,-25,25)' in vector
        and 'j.TorqueA.Torque=-axisA*effort' in vector
        and 'j.TorqueB.Torque=axisB*(j.Sign*effort)' in vector,
    "Physical runtime feeds real continuous motor crank and gear sources":
        'if motor.On then\n                markVectorSource(session,shaft,motor.Torque)' in physical
        and 'markVectorSource(session,root,HandCrankMath.MaxTorque)' in physical
        and 'group.ActiveDrive and group.Root' in physical,
    "Gear relay cannot reuse old commanded speed after motor release":
        'group.ActiveDrive=false' in gears
        and 'group.ActiveDrive=true' in gears
        and 'group.DriveTorque=0' in gears,
    "Pause removes all Vector power and keeps servo controls inactive":
        'VectorJoint.Stop(joint)' in physical
        and 'if session.Paused then' in physical
        and 'motor.Constraint.ActuatorType=Enum.ActuatorType.None' in physical,
}

for label,ok in checks.items():
    print(("PASS" if ok else "FAIL")+": "+label)
if not all(checks.values()):
    raise SystemExit("Servo/Vector power source contract failed")
print(f"PASS: {len(checks)} source contracts (Studio physics test still needed)")
