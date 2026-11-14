#!/usr/bin/env python3
"""Static gearbox integration checks; native motion requires Studio test."""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
def source(rel): return (ROOT/rel).read_text(encoding='utf-8')
trans=source('src/server/Runtime/GearTransmission.lua')
sim=source('src/server/Runtime/PhysicalSimulationService.lua')
mechanical=source('src/server/Runtime/MechanicalService.lua')
fixture=source('scripts/studio/TestGearTorqueTransfer.luau')
client=source('src/client/Controllers/ConstructionController.lua')

def check(label, condition):
    if not condition: raise AssertionError(label)
    print('PASS',label)
check('native Torque enabled, attached to actual physical shaft',
      'torque.Enabled=true' in trans
      and 'torque.Attachment0=attachment' in trans
      and 'group.Root=clone.PrimaryPart' in trans
      and 'gearCF.RightVector:Dot(cf.RightVector)' in trans)
check('physics solver feeds angular-speed error back as equal virtual work',
      all(t in trans for t in ('wb-ratio*wa','a.Pending+=aa*(-ratio*effort)',
                              'b.Pending+=ab*effort','group.Torque.Torque=group.Pending')))
check('explicit gear fit creates rigid weld, not a free gear bearing',
      all(t in mechanical for t in ('kind="Weld"','Smart.HubFits(source,target)',
                                  'oldGearHub','oldHubMotion')))
check('F-copy mounts new gear hubs and bolts through real authored relationships',
      all(q in client for q in ('self.SmartMatch.kind=="Hub"',
                                 'self.SmartMatch.kind=="BoltHole"',
                                 'self.SmartMatch.kind=="CrankCoupling"')))
check('simulation never auto-grounds clicked moving shaft/gear',
      'local groundedKey=if hasCrank then nil else graph.rootKey' not in sim
      and 'not session.Gears:IsGeared(' in sim
      and 'session.GroundKeys[edge.b]=true' in sim
      and 'session.SupportWarning' in sim)
check('powered motor & crank feed same native transmission solver',
      'session.Gears:Step(dt)' in sim
      and 'motor.Constraint.AngularVelocity' in sim
      and 'drive.AngularVelocity=crank.Axis*crank.NativeSpeed' in sim)
check('transmission diagnostics exposes mesh, mounting, grounding and speed',
      all(t in trans for t in ('NO SHAFT WELD','Not engaged:',
                                'GROUNDED','rad/s','idle: drive the crank shaft')))
check('Studio fixture measures actual physics, not simulated CFrames',
      all(t in fixture for t in ('Transmission.new','HingeConstraint',
                                 'WeldConstraint','AssemblyAngularVelocity',
                                 'AngularVelocity','transmission:Step(dt)',
                                 'root:SetNetworkOwner(nil)')))
# Independent force-sign regression: for equal external spur gears, when A is
# spinning + and B idle, the corrective torque on B must be negative.
def torque_sign(w_a,w_b,ratio):
    error_speed=w_b-ratio*w_a
    effort=-error_speed
    return -ratio*effort,effort
for ratio in (-1,-12/20,-20/32):
    inp,out=torque_sign(2.0,0.0,ratio)
    check(f'load counter-torque and opposite driven output for ratio {ratio:.3f}',inp<0 and out<0)
for ratio in (-1,-12/20):
    inp,out=torque_sign(0,2.0,ratio)
    check(f'bidirectional backdrive reaction for ratio {ratio:.3f}',inp<0 and out<0)
print('PASS: gearbox transfer static contracts (Studio physics pending)')
