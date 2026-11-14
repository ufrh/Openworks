#!/usr/bin/env python3
"""Crank -> shaft -> gear -> mesh -> output validation source contracts.
Checks authored wiring; Roblox Studio physics still requires live acceptance.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sim=(root/'src/server/Runtime/PhysicalSimulationService.lua').read_text()
solver=(root/'src/server/Runtime/GearTransmission.lua').read_text()
math=(root/'src/shared/Construction/GearMath.lua').read_text()
crank=(root/'src/shared/Construction/HandCrankMath.lua').read_text()
def check(label, ok):
    assert ok,label
    print('PASS:', label)
check('Crank end-face fit checks a real output and shaft end',
      'local function crankShaftEndFit(crank,shaft)' in sim and
      'HandCrankMath.NearestShaftEnd(shaft,output)' in sim and
      'math.abs(crankDiameter-shaftDiameter)>0.08' in sim)
check('Only unambiguous crank connections can be inferred',
      'local function repairMissingCrankCouplings(graph)' in sim and
      'if #matches==1 then' in sim and 'elseif #matches>1 then' in sim and
      'inferredCrank=true' in sim)
check('All inferred welds inserted before gear grouping and native physics',
      sim.index('session.RepairedHubs,session.AmbiguousHubs=repairMissingGearHubs(graph)')
      < sim.index('session.RepairedCranks,session.AmbiguousCranks=repairMissingCrankCouplings(graph)')
      < sim.index('session.Gears=GearTransmission.new(graph,copies,runtime)'))
check('No inferred crank weld mutates permanent construction or saves',
      'self.D.commitAssembly' not in sim.split('local function repairMissingCrankCouplings(graph)')[1].split('function Simulation.new(deps)')[0]
      and 'table.insert(graph.edges,{' in sim)
check('Crank may directly drive physically inserted gear on its own output spindle',
      'physicallyInsertedGearShaft(other,original)' in sim and
      'coupledShaft=other' in sim)
check('Crank must be rigidly connected to a gear group before running',
      'session.Gears:IsGeared(crank.DrivenId)' in sim and
      'shaft with NO gear mounted' in sim)
check('Silent zero-contact gearboxes are rejected at crank activation',
      'session.Gears.Contacts==0' in sim and
      'The gearbox has ZERO recognized gear contacts:' in sim and
      'session.Gears:NearestFailure()' in sim)
check('Mismatched tooth modules are not faked as meshed',
      'if math.abs(m1-m2)>0.0001 then' in math and
      'Different tooth pitches' in math)
check('Actual welded shaft assemblies receive bidirectional angular-speed commands',
      'Instance.new("Torque")' not in solver and
      'actuator.AngularVelocity=axis(group)*desired' in solver and
      'Ratio=1/link.Ratio' in solver and
      'session.Gears:SetDrive(crank.DrivenId' in sim)
check('Live stall watchdog reports measured shaft speed and anchored roots',
      'LIVE DRIVE STALL:' in sim and
      'DriveDiagnostics(crank.DrivenId)' in sim and
      'AssemblyAngularVelocity:Dot(axis(other))' in solver and
      'AssemblyRootPart' in solver)
check('No visual rotation fakes',
      ':PivotTo(' not in solver and ':PivotTo(' not in sim)
print('PASS: hand-crank gearbox chain contracts')
