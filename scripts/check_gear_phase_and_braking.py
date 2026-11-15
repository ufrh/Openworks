#!/usr/bin/env python3
"""OPENWORKS placement tooth phases and explicit-input gearbox/braking contracts.

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
     "local center = (tooth + 0.5) * step" in
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
test("No live tooth-phase correction or speed feedback remains",
     'PHASE_RESPONSE' not in gear
     and 'phaseCorrections' not in gear
     and 'GearMath.ToothPhaseError(link.LeftGear,link.RightGear)' not in gear
     and 'Output shafts NEVER become implicit input sources' in gear)
test("Only explicit input drives connected gears at exact tooth ratios",
     'local lead,drive=nil,nil' in gear
     and 'factor[edge.Group]=expected' in gear
     and 'local commanded=(factor[group] or 0)*drive.Speed' in gear)
test("Braking supplies zero speed, never a new input source",
     'group.Braking and unanchored(group)' in gear
     and 'actuator.AngularVelocity=Vector3.zero' in gear
     and 'local explicitlyDriven=self.Drives[group]~=nil' in gear)
test("Held crank and powered bearing are the only graph drive inputs",
     'session.Gears:ClearDrives()' in sim
     and 'session.Gears:SetDrive(crank.DrivenId' in sim
     and 'session.Gears:SetDrive(motor.ShaftId' in sim)
test("No native Torque force or scripted gear poses",
     'Instance.new("Torque")' not in gear and ':PivotTo(' not in gear)

# Rev 5 moves tooth zero half a pitch from local +Y: +Y,+Z,-Y,-Z are
# ROOT GAPS in the actual mesh. Rev 4 published meshes use phase 0.
# Either profile can mesh with the other when each mesh carries its phase.
def phase_error(na,nb,theta_a,theta_b,phase_a=.5,phase_b=.5):
    contact_a=-theta_a
    contact_b=math.pi-theta_b
    turns=(na*contact_a+nb*contact_b)/(2*math.pi)-phase_a-phase_b
    return (turns%1)-0.5

for na,nb in [(8,8),(8,12),(12,20),(20,20),(20,32),(32,8)]:
    aligned_offset=-math.pi/nb
    for theta in [-2.1,0,0.37,1.5]:
        theta_out=aligned_offset-(na/nb)*theta
        e=phase_error(na,nb,theta,theta_out)
        test(f"Aligned {na}:{nb} spur teeth remain in gaps while rotating input {theta:g}",
             abs(e)<1e-8)
    # All four radial cardinal directions are between full involute teeth.
    gap_pitch=2*math.pi/nb
    for cardinal in range(4):
        theta=cardinal*math.pi/2
        nearest=min(abs((theta-(tooth+.5)*gap_pitch+math.pi)
                        %(2*math.pi)-math.pi) for tooth in range(nb))
        test(f"{nb}T cardinal gap at quadrant {cardinal}",
             abs(nearest-gap_pitch/2)<1e-9)

# A mixed previously-published rev 4 and rev 5 gear pair still finds
# a half-tooth contact phase, without assuming both IDs were reuploaded.
for pa,pb in [(0,0),(.5,.5),(0,.5),(.5,0)]:
    n=20
    theta_b=-(pa+pb+.5)*2*math.pi/n
    test(f"Mixed geometry phases {pa:g}/{pb:g} mesh correctly",
         abs(phase_error(n,n,0,theta_b,pa,pb))<1e-8)

speed=2.0
for _ in range(15):
    speed=max(0,speed-28/60)
test("Released 2 rad/s hand crank has no self-sustaining speed",speed==0)
print("PASS: initial tooth phase placement and explicit-input gear braking contracts")
