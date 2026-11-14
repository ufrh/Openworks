#!/usr/bin/env python3
"""Compact gear dimensions, Edit-copy smart fitting and idle shaft stop contracts.
Static/numerical checks are no substitute for Roblox Studio physics tests.
"""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
def get(name):return (ROOT/name).read_text(encoding="utf8")
p=get("src/shared/Construction/ProceduralPrefabLibrary.lua")
s=get("src/server/Runtime/ConstructionService.lua")
c=get("src/client/Controllers/ConstructionController.lua")
g=get("src/server/Runtime/GearTransmission.lua")
pl=get("scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua")
def check(name,ok):
    assert ok,name
    print("PASS",name)

check("Smaller 0.19 module, 0.40 face and untouched 0.375 shaft bore",
    all(x in p for x in ['local CAD_MODULE = 0.19','local FACE_WIDTH = 0.40',
                       'local BORE_RADIUS = 0.375',
                       'local SMALL_BEVEL_FACE_WIDTH = 0.20']))
check("40 gear prefabs preserve each historical bore dimension",
    'model:SetAttribute("BoreRadiusStuds", BORE_RADIUS * scale)' in p
    and 'model:SetAttribute("BoreDiameter", 2 * BORE_RADIUS * scale)' in p)
check("Smallest bevel uses actual reduced face for cone and collider",
    'local faceWidth=gearFaceWidth(teeth,bevel)' in p
    and '1-faceWidth*BEVEL_SLOPE/(2*pitch)' in p
    and 'ringCollision(model,scale,details.root,details.pitch,bevel,details.faceWidth)' in p)
check("Old live mesh metadata remains compatible during staged uploads",
    'details = publishedGearDetails(teeth,bevel,rev)' in p
    and 'local module=if modern then CAD_MODULE else 0.25' in p
    and 'local faceWidth=if modern then gearFaceWidth(teeth,bevel) else 0.60' in p)
check("Publisher stages v6 and retains original bolt version and saved data",
    'entry:SetAttribute("PendingProfileVersion",6)' in pl
    and 'manifest:SetAttribute("GearGeometryVersion",6)' in pl
    and 'manifest:SetAttribute("BoltGeometryVersion",5)' in pl
    and 'entry.Value=old.Id' in pl)
check("Copy preview recognizes smart fits and can choose Bore/Hub relationship",
    'if not alt and self.Pending~="ComponentCopy" then' in c
    and 'if self.SmartMatch' in c
    and 'self:OpenMateChoice("Build")' in c
    and 'or self.SmartMatch.kind=="Bore") then {' in c)
check("New Build and copied Edit primitives use one server-side fitted transaction",
    'local function finalizeNewPrimitive(player,model,payload)' in s
    and s.count('return finalizeNewPrimitive(player,model,payload)')==2
    and 'if payload.autoMate==nil and intersectsConstructed(model) then' in s)
check("Copy still verifies authoritative source and clears inherited relations",
    'local original=snapshot(source)' in s
    and 'duplicate.assemblyId=nil' in s
    and 'duplicate.alignedOpeningId=nil' in s
    and 'sourceId=model:GetAttribute("InstanceId")' in s)
check("Motor release sets zero angular speed instead of feeding back velocity",
    'local baseSpeed=if hasDrive then commanded/commandWeight else 0' in g
    and 'desired=0' in g and 'group.Braking=true' in g)
check("Formerly meshed isolated shafts continue braking until settled",
    'group.Braking and not self.Drives[group]' in g
    and 'actuator.AngularVelocity=Vector3.zero' in g
    and 'root.AssemblyAngularVelocity=root.AssemblyAngularVelocity-dir*spin' in g)
check("All native gear speed actuation remains attached to physical shaft body",
    'Instance.new("AngularVelocity")' in g
    and 'Instance.new("Torque")' not in g)

old=.25
new=.19
bore=.375
for teeth in (8,12,20,32):
    pitch=teeth*new/2
    root=pitch-1.25*new
    for bevel in (False,True):
        face=.20 if bevel and teeth==8 else .40
        smallroot=root*(1-face/(2*pitch)) if bevel else root
        check(f"{teeth}T {'Bevel90' if bevel else 'Spur'} retained bore and real rim",
              smallroot>bore+.04)
        originalTip=teeth*old/2+old
        compactTip=teeth*new/2+new
        check(f"{teeth}T {'Bevel90' if bevel else 'Spur'} outer tip radius reduced 24%",
              math.isclose(compactTip/originalTip,.76))
print("PASS: compact gear/edit-copy/idle braking contracts")
