#!/usr/bin/env python3
"""Source and geometric integration contracts for new OPENWORKS prefabs.

This is a deterministic static contract, not a substitute for Studio physics.
"""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[1]

def source(path):
    return (ROOT/path).read_text(encoding="utf-8")

def check(label,expression):
    assert expression,label
    print('PASS',label)

module=source('src/shared/Construction/ProceduralPrefabLibrary.lua')
policy=source('src/shared/Construction/PrefabCollision.lua')
construction=source('src/server/Runtime/ConstructionService.lua')
physical=source('src/server/Runtime/PhysicalSimulationService.lua')
rack=source('src/server/Runtime/RackSimulationService.lua')
mechanical=source('src/server/Runtime/MechanicalService.lua')
math_module=source('src/shared/Construction/GearMath.lua')
transmission=source('src/server/Runtime/GearTransmission.lua')
bolts=source('src/shared/Construction/BoltMath.lua')
command=source('scripts/studio/GeneratePrecisionPrefabs.luau')
bolt_command=source('scripts/studio/RegenerateSharpBolts.luau')

check('45 prefab stock families',all(s in module for s in ['COUNTS = {8, 12, 20, 32}', 'SCALES = {0.6, 0.8, 1.0, 1.2, 1.4}', 'BOLT_SCALES = {0.5, 0.75, 1.0, 1.25, 1.5}', '#pending == 45']))
check('Baked static meshes (no per-clone EditableMesh)',all(x in module for x in ['CreateDataModelContentAsync','CreateMeshPartAsync','source:Clone()']))
check('Visual and physical collision modes',all(x in policy for x in ['mode=="VisualOnly"','mode=="Proxy"','part.CanCollide=false','part.CanQuery=false','part.CanCollide=true']))
check('Construction never re-enables visual mesh collision', 'PrefabCollision.Configure(descendant)' in construction)
check('Physical simulation honors prefab collision', 'PrefabCollision.Configure(part)' in physical)
check('Rack simulation honors prefab collision', 'PrefabCollision.Configure(part)' in rack)
check('All meshes have separate collision proxies', all(x in module for x in ['ringCollision(model,scale,details.root,details.pitch,bevel)','RimCollider_%02d','OpenworksCollisionMode","Proxy"','head.Name="HeadCollider"']))
check('Bolt fits use cylinder centered on declared shank',all(x in module for x in ['pivot.Name = "Geometry"','pivot.Shape = Enum.PartType.Cylinder','model.PrimaryPart = pivot','model:SetAttribute("BoltDiameterU", diameterU)','model:SetAttribute("BoltLengthU", lengthU)']))
check('Game prefabs remain under the stable registry folders',all(x in module for x in ['OPENWORKS_PrimitiveLibrary_DRAFT','folder(library, "Transmission")','folder(library, "Fasteners")']))
check('Geometry version marks new profile without mislabeling old published meshes',
      all(x in module for x in [
          'model:SetAttribute("ProceduralPrefabVersion", VERSION)',
          'model:SetAttribute("GeometryVersion",if toothPhase==0.5 then 5 else 4)',
          'model:SetAttribute("GearToothPhaseFraction",toothPhase)',
          'model:SetAttribute("GeometryVersion", 5)']))
check('Bolt automatic selection searches the whole registry', 'for _,entry in ipairs(self.D.Registry.List()) do' in mechanical and 'bestNew=precision' in mechanical)
create_bolt=mechanical.split('function Mechanical:CreateBolt(player,request)',1)[1].split('function Mechanical:FastenBolt',1)[0]
check('Bolt source is physically generated bolt', 'sourceId=bolt:GetAttribute("InstanceId")' in create_bolt)
check('Old saved bolt relations migrate to physical bolt welds', all(part in mechanical for part in ['if spec.kind=="Bolt" and not BoltMath.IsBolt(source)', 'spec.secondTargetId=spec.targetId', 'spec.targetId=spec.sourceId', 'spec.sourceId=spec.boltId']))
check('Bolt reaches two pierced bodies by weld', 'targetId=first:GetAttribute("InstanceId")' in create_bolt and 'secondTargetId=second:GetAttribute("InstanceId")' in create_bolt)
check('Bolt head begins outside first face', 'cf0.Position-direction*(thickness0*0.5+0.005)' in create_bolt)
check('Bolts validated through both openings before commit', 'BoltMath.Fits(bolt,first) or not BoltMath.Fits(bolt,second)' in create_bolt)
check('Loaded bolts validate first and second hole geometry', 'spec.kind=="Bolt" and not BoltMath.Fits(source,target)' in mechanical and 'BoltMath.Fits(source,other)' in mechanical)
check('Direct bolt-to-hole placement still supported', 'function Mechanical:FastenBolt(player,request,newSource)' in mechanical and 'if not BoltMath.Fits(bolt,target)' in mechanical)
manual_gear=mechanical.split('function Mechanical:CreateGearMesh(player, request)',1)[1].split('function Mechanical:PoseShaft',1)[0]
check('Manual gear meshing uses shared bevel + spur math', 'GearMath.AutoMeshStatus(first,second)' in manual_gear)
check('Spur and 90-degree bevel detection remains shaft-centric',all(x in transmission for x in ['GearMath.AutoMeshStatus', 'GearShaftSpeed','ratio=-left.Teeth/right.Teeth','axis(a)']))
check('Bevel collision ring does not intrude into bore',all(x in module for x in ['rootRadius*scale*(1-FACE_WIDTH*BEVEL_SLOPE/(2*pitch))','inner=bore+0.018*scale']))
check('Standalone gallery script includes corrected gear/bolt physics',all(x in command for x in ['ringCollision(model,scale,details.root,details.pitch,bevel)','head.Name="HeadCollider"','OpenworksCollisionMode","VisualOnly"']))
check('Standalone bolt regenerator includes matching physics',all(x in bolt_command for x in ['pivot:SetAttribute("OpenworksCollisionMode","Proxy")','head.Name="HeadCollider"','visual:SetAttribute("OpenworksCollisionMode","VisualOnly")']))
check('No DataStore wipe in integration code',all(x not in construction+mechanical+module for x in [':RemoveAsync(', 'ClearAllChildren() -- DATASTORE']))

# The CAD parameter is pitch diameter per tooth. The runtime module stores
# circular pitch, and GearMath consistently converts it back to pitch radius.
for teeth in (8,12,20,32):
    pitch=teeth*.25/2
    root=pitch-1.25*.25
    for scale in (.6,.8,1.0,1.2,1.4):
        bore=.375*scale
        outer_spur=root*scale
        outer_bevel=root*scale*(1-.6/(2*pitch))
        inner=bore+.018*scale
        assert outer_spur>inner+.01*scale,(teeth,scale,'spur')
        assert outer_bevel>inner+.01*scale,(teeth,scale,'bevel')
        stored_module=math.pi*.25*scale
        calculated_pitch=teeth*stored_module/(2*math.pi)
        assert abs(calculated_pitch-pitch*scale)<1e-12
check('40 gear bores and pitch radii pass scalar bounds',True)

for scale in (.5,.75,1.,1.25,1.5):
    length=8*scale*.25
    thickness=.25
    separation=.65
    if length<separation+thickness+.025:continue
    first=0
    direction=1
    origin=first-(thickness*.5+.005)+length*.5
    head_end=origin-length*.5
    assert head_end<first-thickness*.5
    second=separation
    assert (second+thickness*.5-origin) <= length*.5
check('Automatic bolt offset keeps head outside entry face',True)
print('PASS: precision prefab integration static contracts')
