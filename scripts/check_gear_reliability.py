#!/usr/bin/env python3
"""Regressions for physical gearbox reliability. Studio physics acceptance remains necessary."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def src(p): return (root / p).read_text(encoding="utf-8")
sim=src("src/server/Runtime/PhysicalSimulationService.lua")
solver=src("src/server/Runtime/GearTransmission.lua")
math=src("src/shared/Construction/GearMath.lua")
crank=src("src/shared/Construction/HandCrankMath.lua")
mechanical=src("src/server/Runtime/MechanicalService.lua")
test=src("scripts/studio/TestGearTorqueTransfer.luau")
def testit(name, ok):
    assert ok, name
    print("PASS", name)
testit("Editor components do not prevent gear/shaft Weld when already fitted",
    'ComponentId is ONLY an editor selection group, not a rigid joint' in mechanical
    and 'if mode~="Hub" then' in mechanical
    and 'Smart.HubFits(source,target)' in mechanical
    and 'd.commitAssembly(player,{},{},spec)' in mechanical)
testit("Infer only validated concentric gear/shaft Hub pairs inside registered assembly",
    all(x in sim for x in ['local function repairMissingGearHubs(graph)',
      'Smart.HubFits(gear,shaft)', 'if #matches==1 then', 'elseif #matches>1 then',
      'inferredHub=true', 'session.RepairedHubs,session.AmbiguousHubs=repairMissingGearHubs(graph)']))
testit("No saved model, DataStore, or fabricated user-authorized relationship mutated",
    'table.insert(graph.edges,{' in sim and 'kind="Weld", source=shaft,target=gear' in sim
    and 'self.D.commitAssembly' not in sim.split('local function repairMissingGearHubs(graph)')[1].split('function Simulation.new(deps)')[0])
testit("Run inference after recording authored relation IDs and before physics build",
    sim.index('session.ActiveRelations[edge.relation:GetAttribute')
      < sim.index('session.RepairedHubs,session.AmbiguousHubs=repairMissingGearHubs(graph)')
      < sim.index('session.Gears=GearTransmission.new(graph,copies,runtime)'))
testit("Crank recognizes already-authorized welded shafts, even with legacy saved dimensions",
    'HandCrankMath.Fits(original,other)' not in sim
    and 'if math.abs(crankCF.RightVector:Dot(axis))>=0.995' in sim
    and 'crank.Drive.AngularVelocity=Vector3.zero' in sim)
testit("Bounded native crank effort supports loaded gears and stays held-input controlled",
    'Crank.MaxTorque=6500' in crank and 'drive.MaxTorque=HandCrankMath.MaxTorque' in sim
    and 'drive.AngularVelocity=crank.Axis*crank.NativeSpeed' in sim
    and 'CRANK_HOLD_TIMEOUT = 0.5' in sim)
testit("Detect actively meshed shafts only, not loose gear contact",
    'if not a.AxisSource or not b.AxisSource then' in solver
    and 'GearMath.AutoMeshStatus(left.Model,right.Model,' in solver)
testit("Strict first contact; bounded holding margin prevents 0.1s physics disconnect flicker",
    'previous[key]~=nil' in solver
    and 'if axial>=faceLimit+(if held then 0.025 else 0) then' in math
    and 'MESH_PITCH_TOLERANCE+0.075' in math
    and 'if held then BEVEL_APEX_TOLERANCE*1.5' in math)
testit("Native torque unchanged, bidirectional; no scripted gear CFrame motion",
    'local errorSpeed=wb-ratio*wa' in solver
    and 'a.Pending+=aa*(-ratio*effort)' in solver
    and 'b.Pending+=ab*effort' in solver
    and 'group.Torque.Torque=group.Pending' in solver
    and ':PivotTo(' not in solver)
testit("Runtime inspection surfaces crank drive, link count, torque effort, and mount repair",
    all(x in sim+solver for x in ['NO GEAR TORQUE MESH','crank SHAFT COUPLED',
       'crank NOT COUPLED','effort %.1f','hub weld(s) repaired in sim']))
testit("Real precision mesh Studio fixture with actual native hinge/motor/torque",
    all(x in test for x in ['REQUIRES a real published GearMesh_20T_S03',
       'HingeConstraint','WeldConstraint','AngularVelocity','transmission:Step(dt)'])
    and 'fallback mock gear' not in test)
print("PASS: 11 robust gearbox source contracts (runtime physics still requires Studio)")
