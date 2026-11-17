#!/usr/bin/env python3
"""Check that OpenWorks does not reject large registered assemblies.

Run: python scripts/check_simulation_capacity.py
Source-level regression guard only. Real Roblox physics/performance still
depends on hardware, engine budgets, and the authored mechanism.
"""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def file(name):
    return (ROOT/name).read_text(encoding="utf-8")

physical=file("src/server/Runtime/PhysicalSimulationService.lua")
rack=file("src/server/Runtime/RackSimulationService.lua")
gears=file("src/server/Runtime/GearTransmission.lua")
kinematics=file("src/server/Runtime/GearKinematics.lua")
belts=file("src/server/Runtime/BeltTransmission.lua")
assembly=file("src/server/Runtime/AssemblyService.lua")
tool=file("src/client/Controllers/AssemblyToolController.lua")
mechanical=file("src/server/Runtime/MechanicalService.lua")
components=file("src/server/Runtime/ComponentService.lua")
construction=file("src/server/Runtime/ConstructionService.lua")
saves=file("src/server/Runtime/PlotPersistence.lua")
router=file("src/server/Runtime/UnifiedSimulationService.lua")

checks={
    "Normal and rack engines both routed": "return if rack then self.Rack else self.Physical" in router,
    "Physical engine has no 128-part / 64-joint limit": all(
        token not in physical for token in ("MAX_PARTS = 128","MAX_JOINTS = 64","simulation safety limits")),
    "Rack engine has no 128-part / 64-joint limit": all(
        token not in rack for token in ("MAX_PARTS = 128","MAX_JOINTS = 64","simulation safety limits")),
    "Physical engine has no collision exclusion limit": "MAX_COLLISION_PAIRS" not in physical
        and "collisionExclusions[lp]" in physical,
    "Rack engine has no collision exclusion limit": "MAX_COLLISION_PAIRS" not in rack
        and "collisionExclusions[lp]" in rack,
    "Physical gear count unrestricted": "MAX_GEARS" not in gears,
    "Rack kinematic gear/rack counts unrestricted": all(
        token not in kinematics for token in ("MAX_GEARS","MAX_RACKS")),
    "Simulated belt count unrestricted": "MAX_LOOPS" not in belts,
    "Assembly detection and registry unrestricted": "MAX_MEMBERS" not in assembly
        and "Mechanism exceeds 128 parts" not in assembly,
    "Assembly client selection unrestricted": "MAX_SELECTION" not in tool,
    "Mechanical relationship authoring unrestricted": "MAX_RELATIONSHIPS_PER_PLAYER" not in mechanical
        and "Component exceeds 128 members" not in mechanical,
    "Component grouping and multi-selection unrestricted": "MAX_GROUP" not in components
        and "#payload.ids>128" not in components,
    "Group nudges unrestricted": "#selected>128" not in construction
        and "#ids>128" not in construction,
    "Save/load no longer rejects >128 joints": "MAX_JOINTS" not in saves
        and "document.joints>MAX_JOINTS" not in saves,
    "Platform storage-size safeguard remains": "MAX_BYTES" in saves,
    "Ownership remains verified in assembly requests": "self.D.findOwned(player,id)" in assembly,
}
for name,passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if not all(checks.values()):
    raise SystemExit("OpenWorks simulation capacity regression")
print("All source-level assembly capacity checks passed.")
