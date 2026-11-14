#!/usr/bin/env python3
"""Regression for observed video: right crank gear spins, left output gear does not.
No Roblox VM is available here; this checks the source paths, not live physics.
"""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
sim=(r/'src/server/Runtime/PhysicalSimulationService.lua').read_text()
solver=(r/'src/server/Runtime/GearTransmission.lua').read_text()
math=(r/'src/shared/Construction/GearMath.lua').read_text()
for label,check in [
 ("Recognize press-fit inserted gear bores with bounded tolerances", 'physicallyInsertedGearShaft(gear,shaft)' in sim and 'eccentricity>math.min(0.08,math.max(0.045,bore*0.20))' in sim and 'diameter>2*bore+0.035' in sim),
 ("Require an unambiguous shaft before inferring a weld", '#matches==1' in sim and '#matches>1' in sim),
 ("Preserve authored model and save data", 'table.insert(graph.edges,{' in sim and 'self.D.commitAssembly' not in sim.split('local function repairMissingGearHubs(graph)')[1].split('function Simulation.new(deps)')[0]),
 ("Native shaft speed is not skipped merely due to absent shaft mount", 'if not a.AxisSource or not b.AxisSource then' not in solver and 'actuator.AngularVelocity=axis(group)*desired' in solver),
 ("Use actual tooth envelope and module-dependent capture", 'toothEngagementTolerance(a,b,held)' in math and 'Gear tooth tips do not touch' in math),
 ("Never mesh different module sizes", 'if math.abs(m1-m2)>0.0001 then' in math),
 ("Warning for zero meshed contacts", 'session.Gears:NearestFailure()' in sim and 'ZERO engaging pairs' in sim),
 ("Crank body is not mistaken for shaft reference", 'original:GetAttribute("ActuatorKind")~="HandCrank"' in solver),
 ("No gear CFrame animation fake", ':PivotTo(' not in solver),
]:
    assert check,label
    print('PASS:',label)
print('PASS: video gearbox regression contracts (Studio physics acceptance needed)')
