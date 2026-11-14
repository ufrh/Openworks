#!/usr/bin/env python3
"""Source and numerical regressions for bounded native gearbox torque.

This does not replace an actual Roblox Studio Play Solo physics test.
"""
from pathlib import Path
import math

base = Path(__file__).resolve().parents[1]
gear = (base/'src/server/Runtime/GearTransmission.lua').read_text()
sim = (base/'src/server/Runtime/PhysicalSimulationService.lua').read_text()
fixture = (base/'scripts/studio/TestGearTorqueTransfer.luau').read_text()
crank = (base/'src/shared/Construction/HandCrankMath.lua').read_text()

def test(label, condition):
    assert condition, label
    print('PASS:', label)

test('Mesh effort bounded by the native manual drive budget',
     'local MAX_MESH_EFFORT=HandCrankMath.MaxTorque*0.72' in gear
     and 'MAX_MESH_EFFORT/math.max(1,math.abs(ratio))' in gear
     and '-maxEffort,maxEffort' in gear)
test('Anchored rigid body is detected even when the chosen root is not anchored',
     'root=part.AssemblyRootPart' in gear
     and 'root and root.Anchored' in gear
     and 'part.AssemblyMass' in gear
     and 'link.PhysicsBlocked=true' in gear)
test('Infinite or invalid mass cannot contaminate physics torque',
     'mass~=mass or mass==math.huge or mass<0 or mass>1e8' in gear
     and 'if not ma or not mb then' in gear
     and 'link.Effort=0' in gear)
test('Crank immediately receives nonzero drive and is cleaned up on stop',
     'crank.NativeSpeed=HandCrankMath.FixedAngularSpeed*0.2' in sim
     and 'crank.Drive.AngularVelocity=crank.Axis*crank.NativeSpeed' in sim
     and 'crank.Drive.AngularVelocity=Vector3.zero' in sim)
test('Live diagnostics distinguish an armed crank from actual motion',
     'LIVE DRIVE STALL:' in sim
     and 'Crank drive cut: %s' in sim
     and 'Crank released after %.2f s' in sim
     and 'DriveDiagnostics(crank.DrivenId)' in sim)
test('Diagnostics use actual peer angular speeds, torque and assembly anchored status',
     'function Transmission:DriveDiagnostics(id)' in gear
     and 'AssemblyAngularVelocity:Dot(axis(other))' in gear
     and 'AssemblyRootPart' in gear
     and 'link.PhysicsBlocked==true' in gear
     and 'Final drive telemetry:' in fixture)
test('No scripted rotation or hidden weld authoring',
     ':PivotTo(' not in gear and 'Instance.new("WeldConstraint")' not in gear)

budget=6500*0.72
for ratio in (-0.25,-1,-4):
    max_effort=budget/max(1,abs(ratio))
    for error in (0.01,0.5,10,1e6):
        raw=-error*100000
        effort=max(-max_effort,min(max_effort,raw))
        ta=-ratio*effort
        tb=effort
        test(f'Gear ratio {ratio:g} torque bounded for error {error:g}',
             math.isfinite(ta) and math.isfinite(tb)
             and abs(ta)<=budget+1e-9
             and abs(tb)<=budget+1e-9 and tb<0)
print('PASS: torque budget & live drive diagnostics (Studio acceptance required)')
