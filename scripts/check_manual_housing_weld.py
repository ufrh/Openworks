#!/usr/bin/env python3
"""Rigid exterior-face weld regression (source contract, not Studio physics)."""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
mechanics=(root/"src/server/Runtime/MechanicalService.lua").read_text()
ui=(root/"src/client/Controllers/ConnectionCatalog.lua").read_text()
panel=(root/"src/client/Controllers/AssemblyController.lua").read_text()

start=mechanics.index("local function weldPairValid(")
end=mechanics.index("function Mechanical:CreateWeld(",start)
validator=mechanics[start:end]
checks={
    "Manual rigid weld does not require coaxial shaft-in-hole fitting":
        "Bore.ShaftFits(" not in validator
        and "Alignment.Plan(" not in validator,
    "Flush CSG and cylinder seams get a bounded two-way contact tolerance":
        "stillTouching(source,target,0.03)" in validator
        and "nearOnAxes(left,right) and nearOnAxes(right,left)" in mechanics
        and "local epsilon=tolerance or 0.012" in mechanics,
    "Distant pairs and duplicate/motion constraints remain rejected":
        "if not close then" in validator
        and "Rigid weld requires adjoining surfaces" in validator
        and "Remove the existing relationship before rigid welding" in validator,
    "Motion joints still require real bore geometry":
        "Bore.ShaftFits(source,target)" in mechanics
        and "Powered Motor requires a Cylinder shaft and drilled hole block" in mechanics,
    "Gear-to-shaft weld still validates physical hub fitting":
        'if spec.kind=="Weld" and' in mechanics
        and "Smart.HubFits(source,target)" in mechanics,
    "Both normal Connect and weld tool use the explicit CreateWeld action":
        'action="CreateWeld"' in panel
        and 'add("Weld")' in ui,
}
for name,okay in checks.items():
    print(("PASS" if okay else "FAIL")+": "+name)
if not all(checks.values()):
    raise SystemExit("Manual housing weld source regression")
print("PASS: Rigid housing face weld contracts")
