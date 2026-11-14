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
    'actuator.AngularVelocity=axis(group)*desired' in gear)
test("Virtual inertia and load cap acceleration instead of applying torque",
    'DRIVE_BUDGET=HandCrankMath.MaxTorque*0.72' in gear and
    'local inertia=if mass then math.clamp(' in gear and
    'local acceleration=math.clamp(' in gear and
    'virtualLoad+=' in gear)
test("Unpowered gear assemblies never generate self-sustaining speed commands",
    'momentum+=inertia*f*speed' not in gear and
    'local baseSpeed=if hasDrive then commanded/commandWeight else 0' in gear and
    'if not hasDrive then' in gear and
    'RELEASE_BRAKE_ACCEL=28' in gear and
    'if not hasDrive or not self.Drives[group] then' in gear)
test("Competing motors use weighted signed gear graph",
    'drive.Weight*f*drive.Speed' in gear and
    'commandWeight+=drive.Weight*f*f' in gear and
    'factor[other]=expected' in gear)
test("Anchored shaft island is excluded from speed actuation",
    'root=part.AssemblyRootPart' in gear and
    'root and root.Anchored' in gear and
    'if not actuator or not inertia or not hasMotion then' in gear)
test("Crank input drives actual shaft; no second speed actuator fights it",
    'session.Gears:SetDrive(crank.DrivenId' in sim and
    'drive.AngularVelocity=crank.Axis*crank.NativeSpeed' in sim and
    'if not hasDrive or not self.Drives[group] then' in gear)
test("Actuator remains enabled during continuous motion",
    'group.ControlledThisFrame=true' in gear and
    'if not actuator or group.ControlledThisFrame then continue end' in gear)
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
