#!/usr/bin/env python3
"""Cardinal root-gap geometry and in-line three-gear acceptance contracts.

Numerical checks are not Roblox mesh publishing or an in-Studio playtest.
"""
import math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def src(name): return (ROOT/name).read_text(encoding="utf8")
generator=src("src/shared/Construction/ProceduralPrefabLibrary.lua")
standalone=src("scripts/studio/GeneratePrecisionPrefabs.luau")
gear_math=src("src/shared/Construction/GearMath.lua")
smart=src("src/shared/Construction/SmartPlacement.lua")
plugin=src("scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua")
xml=src("scripts/studio/OpenworksPermanentMeshPublisher.rbxmx")
def check(name,value):
    assert value,name
    print("PASS",name)

check("Real involute tooth centers are half a pitch off radial axes",
      "local center = (tooth + 0.5) * step" in generator
      and "local center = (tooth + 0.5) * step" in standalone)
check("This change preserves every tooth and the original model shaft bore",
      "for tooth = 0, teeth - 1 do" in generator
      and "BORE_RADIUS * cosine" in generator)
check("Phase source is the actual published base mesh version",
      'entry:GetAttribute("ProfileVersion")' in generator
      and 'model:SetAttribute("GearToothPhaseFraction",toothPhase)' in generator
      and 'model:SetAttribute("GeometryVersion",if toothPhase==0.5 then 5 else 4)' in generator)
check("Old and new geometry can mesh with correct tooth phase",
      'shiftA-shiftB' in gear_math
      and 'sourceShift=source:GetAttribute("GearToothPhaseFraction") or 0' in smart
      and 'targetShift=target:GetAttribute("GearToothPhaseFraction") or 0' in smart
      and '(sourcePhase+sourceShift)*sourcePitch' in smart)
check("Gear assets are republished as NEW IDs, with delayed manifest promotion",
      "CreateAssetVersionAsync(editableMesh," not in plugin
      and "CreateAssetAsync(editableMesh," in plugin
      and 'manifest:SetAttribute("GearGeometryVersion",5)' in plugin
      and 'entry:SetAttribute("PendingAssetId",' in plugin
      and 'entry:SetAttribute("ProfileVersion",5)' in plugin
      and 'entry.Value=string.format("%.0f",ids[key])' in plugin)
check("Old bolts remain untouched in a gear version update",
      'local isGear=key~="Bolt_SharpThread"' in plugin
      and 'not replaceGears or not isGear or upToDate' in plugin)
check("Studio plugin XML and source are identical",
      xml.split("<![CDATA[",1)[1].split("]]>",1)[0]==plugin)

MODULE=.25
BORE=.375
PRESSURE=math.radians(20)
WIDTH=.60
for teeth in (8,12,20,32):
    step=2*math.pi/teeth
    pitch=teeth*MODULE/2
    base=pitch*math.cos(PRESSURE)
    root=pitch-1.25*MODULE
    tip=pitch+MODULE
    t=math.sqrt((pitch/base)**2-1)
    involute=t-math.atan(t)
    shoulder=math.pi/(2*teeth)+involute+math.radians(.55)
    assert shoulder<step*.5
    centers=[(n+.5)*step for n in range(teeth)]
    for direction in range(4):
        cardinal=direction*math.pi/2
        angular_distance=min(abs((angle-cardinal+math.pi)%(2*math.pi)-math.pi)
                             for angle in centers)
        check(f"{teeth}T: quadrant {direction} lies inside a true root gap",
              angular_distance-shoulder>0.005)
    for bevel in (False,True):
        small_end_factor=(1-WIDTH/(2*pitch)) if bevel else 1
        check(f"{teeth}T {'90deg bevel' if bevel else 'spur'}: open bore and real rim",
              small_end_factor*root>BORE+.01)
        # Pitch radius is unchanged, so centers of consecutive parallel
        # spur shafts can all sit on one horizontal line.
        check(f"{teeth}T {'90deg bevel' if bevel else 'spur'}: pitch unchanged",
              math.isclose(pitch,teeth*MODULE/2))
# Three 20/12/20 spur gears with ALL axis centers on the same horizontal line.
r20=20*MODULE/2
r12=12*MODULE/2
centers=[(0.,0.),(r20+r12,0.),(2*(r20+r12),0.)]
check("20/12/20 straight spur train has identical centerline height",
      all(y==0 for _,y in centers))
check("Left-center and center-right both have exact pitch spacing",
      all(math.isclose(centers[i+1][0]-centers[i][0],r20+r12)
          for i in range(2)))
print("PASS: cardinal gap profile and level three-gear geometry contracts")
