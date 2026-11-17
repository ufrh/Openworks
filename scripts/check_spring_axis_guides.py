#!/usr/bin/env python3
"""Source-level regression checks for OPENWORKS single-axis springs.

Run: python scripts/check_spring_axis_guides.py
This does not replace a live Roblox Studio spring/suspension playtest.
"""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def source(path):
    return (ROOT/path).read_text(encoding="utf-8")

math=source("src/shared/Construction/SpringMath.lua")
authoring=source("src/server/Runtime/MechanicalService.lua")
physical=source("src/server/Runtime/PhysicalSimulationService.lua")
rack=source("src/server/Runtime/RackSimulationService.lua")
router=source("src/server/Runtime/UnifiedSimulationService.lua")

checks={
    "Active router uses the patched engines":
        "return if rack then self.Rack else self.Physical" in router,
    "Axes derived from attachment endpoint direction":
        "local delta=world1-world0" in math
        and "function Spring.AxisFrames(" in math
        and "CFrame.fromMatrix(world0,axis,up)" in math,
    "Authored springs have axis guide":
        'guide.Name="SpringAxisGuide"' in authoring,
    "Physical springs have axis guide":
        'guide.Name="SpringAxisGuide"' in physical,
    "Rack springs have axis guide":
        'guide.Name="SpringAxisGuide"' in rack,
    "Native prismatic constraints used in both runtimes":
        'local guide=Instance.new("PrismaticConstraint")' in physical
        and 'local guide=Instance.new("PrismaticConstraint")' in rack,
    "Guide allows only its one translational axis":
        all("guide.LimitsEnabled=false" in x
            and "guide.ActuatorType=Enum.ActuatorType.None" in x
            for x in (authoring,physical,rack)),
    "Shared spring and guide attachments":
        all("guide.Attachment0=s0" in x
            and "guide.Attachment1=s1" in x
            and "spring.Attachment0=s0" in x
            and "spring.Attachment1=s1" in x
            for x in (physical,rack)),
    "Both guides included in cleanup/session":
        all("table.insert(session.Constraints,guide)" in x
            for x in (physical,rack)),
    "Native spring stiffness and damping retained":
        all('spring=Instance.new("SpringConstraint")' in x
            and "SpringMath.ApplyPhysical(spring,p0,p1)" in x
            for x in (physical,rack)),
    "Live spring tuning still targets spring not guide":
        all('if kind=="Spring" and constraint:IsA("SpringConstraint")' in x
            for x in (physical,rack)),
}
for name,pass_ in checks.items():
    print(f"{'PASS' if pass_ else 'FAIL'}: {name}")
if not all(checks.values()):
    raise SystemExit("Spring single-axis regression")
print("All source-level spring checks passed.")
