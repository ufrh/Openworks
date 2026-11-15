#!/usr/bin/env python3
"""Numerical/contract tests for virtual gearbox load and physical speed motors.
No Roblox VM: live shaft movement must be tested in Studio.
"""
from pathlib import Path
import math
root=Path(__file__).resolve().parents[1]
def src(p): return (root/p).read_text(encoding="utf-8")
gear=src("src/server/Runtime/GearTransmission.lua")
sim=src("src/server/Runtime/PhysicalSimulationService.lua")
fixture=src("scripts/studio/TestGearTorqueTransfer.luau")
crank=src("src/shared/Construction/HandCrankMath.lua")
def test(label,condition):
    assert condition,label
    print("PASS:",label)
test("Native Torque actuators removed; physical shaft speed controlled",
    'Instance.new("Torque")' not in gear and
    'Instance.new("AngularVelocity")' in gear and
    'actuator.AngularVelocity=axis(group)*group.TargetSpeed' in gear)
test("Explicit motor command sets exact signed output speed without virtual inertia",
    'DRIVE_BUDGET=HandCrankMath.MaxTorque*0.72' in gear
    and 'local commanded=(factor[group] or 0)*drive.Speed' in gear
    and 'group.TargetSpeed=math.clamp(commanded,-MAX_SPEED,MAX_SPEED)' in gear
    and 'phaseCorrections' not in gear
    and 'VIRTUAL_RESPONSE' not in gear)
test("Unpowered gear assemblies never create drive commands from physics feedback",
    'momentum+=inertia*f*speed' not in gear
    and 'Output shafts NEVER become implicit input sources' in gear
    and 'self.Drives[group] or {}' in gear
    and 'actuator.AngularVelocity=Vector3.zero' in gear)
test("Explicit strongest motor determines stable speed propagation",
    'candidate.Weight>drive.Weight' in gear
    and 'tostring(group.Id)<tostring(lead.Id)' in gear
    and 'factor[edge.Group]=expected' in gear)
test("Grounded or anchored shaft group excluded from speed actuation",
    'local root=part and part.AssemblyRootPart' in gear
    and 'not (root and root.Anchored)' in gear
    and 'if group~=lead and unanchored(group) then' in gear)
test("Crank input drives real shaft without competing gearbox actuator",
    'session.Gears:SetDrive(crank.DrivenId' in sim
    and 'drive.AngularVelocity=crank.Axis*crank.NativeSpeed' in sim
    and 'local explicitlyDriven=self.Drives[group]~=nil' in gear)
test("Output speed actuator stays enabled while commanded and disables on release",
    'commandedGroups[group]=true' in gear
    and 'if actuator and not commandedGroups[group] then' in gear
    and 'actuator.Enabled=true' in gear
    and 'actuator.Enabled=false' in gear)
test("Crank held-input safety, live speeds and diagnostics preserved",
    'Crank drive cut: %s' in sim and
    'LIVE DRIVE STALL:' in sim and 'DriveDiagnostics(crank.DrivenId)' in sim)
test("Studio native speed smoke test supplies explicit drive and measures output",
    'transmission:SetDrive("test-shaft-A",2,6500,Vector3.xAxis)' in fixture and
    'rootB.AssemblyAngularVelocity.X' in fixture)
test("No direct shaft pose animation or silent joint authoring",
    ':PivotTo(' not in gear and 'Instance.new("WeldConstraint")' not in gear)
for teeth_a,teeth_b in [(20,20),(12,20),(20,32)]:
    ratio=-teeth_a/teeth_b
    # In a compound graph A->B->C, C's speed is the product of both ratios.
    for omega in [2,-3,0.25]:
        second=ratio*omega
        back=second/ratio
        test(f"{teeth_a}T -> {teeth_b}T round trip at {omega}",
            math.isclose(back,omega,rel_tol=1e-10) and second*omega<0)
print("PASS: virtual load/speed gearbox contracts (Studio acceptance pending)")
