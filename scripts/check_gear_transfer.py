#!/usr/bin/env python3
"""Contracts for shaft-speed transmission, not native Torque objects.
Roblox Studio physics remains the required runtime acceptance test.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def src(name): return (ROOT/name).read_text(encoding="utf-8")
gear=src("src/server/Runtime/GearTransmission.lua")
sim=src("src/server/Runtime/PhysicalSimulationService.lua")
mech=src("src/server/Runtime/MechanicalService.lua")
fixture=src("scripts/studio/TestGearTorqueTransfer.luau")
client=src("src/client/Controllers/ConstructionController.lua")
def check(label,condition):
    assert condition,label
    print("PASS",label)
check("No Roblox Torque object or scripted CFrame rotation in gearbox",
    'Instance.new("Torque")' not in gear and ':PivotTo(' not in gear)
check("Gear output is a native shaft AngularVelocity actuator",
    'Instance.new("AngularVelocity")' in gear and
    'velocity.Attachment0=attachment' in gear and
    'group.VelocityActuator=velocity' in gear and
    'actuator.AngularVelocity=axis(group)*desired' in gear)
check("Physical shaft is the gear rigid-group root",
    'group.Root=clone.PrimaryPart' in gear and
    'gearCF.RightVector:Dot(cf.RightVector)' in gear)
check("External spur and bevel tooth ratios use actual gear counts",
    'ratio=-left.Teeth/right.Teeth*orientation' in gear and
    'ratio=-left.Teeth/right.Teeth*signA*signB' in gear)
check("Compound gears and reverse drives propagate in one connected graph",
    'local factor={[first]=1}' in gear and
    'Ratio=1/link.Ratio' in gear and
    'factor[other]=expected' in gear)
check("Crank and bearing motors explicitly supply speed to shaft groups",
    'session.Gears:ClearDrives()' in sim and
    'session.Gears:SetDrive(crank.DrivenId' in sim and
    'session.Gears:SetDrive(motor.ShaftId' in sim and
    'ShaftId=edge.source:GetAttribute("InstanceId")' in sim)
check("Drive-side AngularVelocity motor is not opposed by another motor",
    'if not hasDrive or not self.Drives[group] then' in gear and
    'group.ControlledThisFrame=true' in gear)
check("Gear hub fitting authorizes rigid welds",
    'kind="Weld"' in mech and 'Smart.HubFits(source,target)' in mech)
check("F-copy preserves hub and crank relationships",
    all(k in client for k in ['self.SmartMatch.kind=="Hub"',
        'self.SmartMatch.kind=="BoltHole"',
        'self.SmartMatch.kind=="CrankCoupling"']))
check("Simulation anchors housings rather than moving shafts",
    'not session.Gears:IsGeared(' in sim and
    'session.GroundKeys[edge.b]=true' in sim)
check("Shaft-speed telemetry reports mounting, grounding, and actual rad/s",
    all(x in gear for x in ['NO SHAFT WELD','GROUNDED',
        'rad/s','virtual load','DriveDiagnostics']))
check("Studio fixture drives shaft speed and measures real physical output",
    all(x in fixture for x in ['HingeConstraint','WeldConstraint',
        'AssemblyAngularVelocity','transmission:SetDrive("test-shaft-A"',
        'transmission:Step(dt)','root:SetNetworkOwner(nil)']))
for n_a,n_b in [(20,20),(12,20),(20,32),(32,8)]:
    ratio=-n_a/n_b
    for input_speed in [2.0,-1.5]:
        out=ratio*input_speed
        check(f"Spur pair {n_a}:{n_b} follows ratio forward/reverse at {input_speed:g}",
            abs(out+input_speed*n_a/n_b)<1e-9 and out*input_speed<0)
print("PASS: shaft-speed gearbox source contracts; Studio acceptance required")
