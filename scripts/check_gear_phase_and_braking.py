#!/usr/bin/env python3
"""OPENWORKS phase-locked gear mesh and no-input braking source/numerical contracts.

Roblox Studio physics is not emulated here; this checks authored math and invariants.
"""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[1]
def src(p): return (ROOT/p).read_text(encoding="utf-8")
gear=src("src/server/Runtime/GearTransmission.lua")
math_source=src("src/shared/Construction/GearMath.lua")
smart=src("src/shared/Construction/SmartPlacement.lua")
sim=src("src/server/Runtime/PhysicalSimulationService.lua")
def test(name, ok):
    assert ok,name
    print("PASS",name)

test("Actual generated tooth geometry uses local +Y and +Z angular basis",
     "local center = tooth * step" in
     src("src/shared/Construction/ProceduralPrefabLibrary.lua")
     and "math.cos(v.a), math.sin(v.a)" in
     src("src/shared/Construction/ProceduralPrefabLibrary.lua"))
test("Contact-phase computation measures correct Roblox local +Z direction",
     "function GearMath.ToothPhaseError(a:Model,b:Model,poseA:CFrame?)" in math_source
     and "VectorToWorldSpace(Vector3.zAxis)" in math_source
     and "return (toothTurns%1)-0.5" in math_source)
test("Spur and bevel contacts select valid pitch-contact directions",
     'if kindA=="Spur" then' in math_source
     and 'kindA=="Bevel90" or kindA=="Bevel45"' in math_source
     and 'local generator=axa+axb' in math_source)
test("Bevel placement snaps tooth to opposite gap before simulation",
     'GearMath.ToothPhaseError(source,target,pose)' in smart
     and 'phaseError*2*math.pi/teeth' in smart
     and 'pose=CFrame.new(center)*corrected' in smart)
test("Spur placement maintains half-tooth interlock",
     'local sourcePhase=(0.5-targetPhase)%1' in smart)
test("Each detected gear link retains its actual contacting gear models",
     'LeftGear=left.Model,RightGear=right.Model' in gear)
test("Follower phase correction is active only while a real motor is held",
     'if hasDrive then' in gear and
     'GearMath.ToothPhaseError(link.LeftGear,link.RightGear)' in gear
     and 'phaseCorrections[follower]' in gear
     and 'PHASE_RESPONSE=7' in gear)
test("Corrections avoid motor-driven input shafts",
     'if aDepth==nil or bDepth==nil or aDepth==bDepth then continue end' in gear
     and 'local follower=if aDepth>bDepth then link.A else link.B' in gear
     and 'if not hasDrive or not self.Drives[group] then' in gear)
test("No-input phase correction cannot feed itself",
     'local baseSpeed=if hasDrive then commanded/commandWeight else 0' in gear
     and 'momentum+=inertia*f*speed' not in gear
     and 'local phaseCorrections,phaseCounts={},{}' in gear)
test("No-input physical shafts actively brake, with no new drive source",
     'RELEASE_BRAKE_ACCEL=28' in gear
     and 'math.max(0,math.abs(speed)-RELEASE_BRAKE_ACCEL*dt)' in gear
     and 'if not hasDrive then' in gear
     and 'group.ControlledThisFrame=true' in gear)
test("Held crank and powered bearing are the only graph drive inputs",
     'session.Gears:ClearDrives()' in sim
     and 'session.Gears:SetDrive(crank.DrivenId' in sim
     and 'session.Gears:SetDrive(motor.ShaftId' in sim)
test("No native Torque force or scripted gear poses",
     'Instance.new("Torque")' not in gear and ':PivotTo(' not in gear)

# Tooth zero is at local +Y and each successive tooth moves toward local +Z.
# For equal/unequal even tooth counts, the two facing teeth would collide
# unless the second gear has an additional half-pitch angular displacement.
def phase_error(na,nb,theta_a,theta_b):
    contact_a=-theta_a
    contact_b=math.pi-theta_b
    return ((na*contact_a+nb*contact_b)/(2*math.pi)%1)-0.5

for na,nb in [(8,8),(8,12),(12,20),(20,20),(20,32),(32,8)]:
    aligned_offset=-math.pi/nb
    for theta in [-2.1,0,0.37,1.5]:
        theta_out=aligned_offset-(na/nb)*theta
        e=phase_error(na,nb,theta,theta_out)
        test(f"Aligned {na}:{nb} spur teeth remain in gaps while rotating input {theta:g}",
             abs(e)<1e-8)
    # A half-tooth correction should resolve an initial tip-to-tip contact.
    theta_b=0.0
    for _ in range(240):
        err=phase_error(na,nb,0,theta_b)
        command=max(-1.2,min(1.2,err*(2*math.pi/nb)*7))
        theta_b+=command/60
    test(f"{na}:{nb} follower converges to tooth gap",
         abs(phase_error(na,nb,0,theta_b))<0.012)

speed=2.0
for _ in range(15):
    speed=max(0,speed-28/60)
test("Released 2 rad/s hand crank has no self-sustaining speed",speed==0)
print("PASS: tooth contact phase and no-input braking source contracts")
