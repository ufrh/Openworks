#!/usr/bin/env python3
"""OPENWORKS source-level rope, collision-resize, and Units regression checks.

Run from repository root: python scripts/check_rope_resize_units.py
These checks verify code integration, NOT live Roblox Studio physics.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def src(path):
    return (ROOT/path).read_text(encoding="utf-8")

rope=src("src/shared/Construction/RopeMath.lua")
mechanical=src("src/server/Runtime/MechanicalService.lua")
construction=src("src/server/Runtime/ConstructionService.lua")
unified=src("src/server/Runtime/UnifiedSimulationService.lua")
physical=src("src/server/Runtime/PhysicalSimulationService.lua")
rack=src("src/server/Runtime/RackSimulationService.lua")
rope_client=src("src/client/Controllers/RopeControlController.lua")
assembly=src("src/client/Controllers/AssemblyController.lua")
catalog=src("src/client/Controllers/ConnectionCatalog.lua")
context=src("src/client/Controllers/ContextEditor.lua")
index=src("src/client/Controllers/AuthoredIndex.lua")
grid=src("src/shared/Construction/GridMath.lua")
scale=src("src/client/Controllers/ResizeGizmo.lua")
build=src("src/client/Controllers/ConstructionController.lua")
numeric=src("src/client/Controllers/NumericSizePanel.lua")
surface=src("src/shared/Construction/SurfacePlacement.lua")

checks={
    "Rope exists as authored relationship":
        'or kind=="Rope"' in mechanical
        and "function Mechanical:CreateRope" in mechanical
        and "function Mechanical:TuneRope" in mechanical,
    "Rope is tension-only, never anchored/welded":
        'Instance.new("RopeConstraint")' in rope
        and "if rope.CurrentDistance>runtime.Target+Grid.Unit*0.01 then" in rope
        and 'rope.WinchEnabled=false' in rope
        and 'rope.Anchored' not in rope,
    "Rope settings persist and undo":
        "ropeMaxLength=relation:GetAttribute" in mechanical
        and 'if spec.kind=="Rope" then' in mechanical
        and 'self.D.commitJointEdit(player,before,self:Snapshot(relation))' in mechanical,
    "Rope is visible in mechanical connection picker":
        'add("Rope")' in catalog and 'elseif kind=="Rope" then' in assembly,
    "Rope properties expose two keys and length in U":
        'action="TuneRope"' in context
        and "ropeLength=length*Grid.Unit" in context
        and 'self:KeyPicker("Retract key"' in context
        and 'self:KeyPicker("Pay out key"' in context,
    "Server owns rope physical commands":
        "OPENWORKS_RopeControl" in construction
        and "simulation:InputRope(player,key,holding)" in construction
        and 'hasEquippedTool(player,"AssemblySimulation")' in construction,
    "Router forwards only to active simulation engine":
        "function Unified:InputRope(player,key,holding)" in unified,
    "Physical and rack graph retain ropes":
        'or kind == "Rope")' in physical
        and 'or kind == "Rope")' in rack,
    "Physical and rack compile actual rope constraints":
        all('elseif edge.kind=="Rope" then' in x
            and "RopeMath.NewRuntime" in x for x in (physical,rack)),
    "Winches step, pause and tune in both live engines":
        all("RopeMath.Step(rope,dt,now)" in x
            and "RopeMath.Stop(rope)" in x
            and "RopeMath.ApplyTuning(rope,relation)" in x
            for x in (physical,rack)),
    "Ropes never disable collisions between tethered bodies":
        all('if edge.kind~="Rope" then' in x for x in (physical,rack)),
    "Client input has heartbeat liveness and release":
        "OPENWORKS_RopeControl" in rope_client
        and "self:Release()" in rope_client
        and 'RopeControlController.new(self)' in assembly,
    "Rope setting changes re-render":
        "RopeMaxLength" in index and "RopeInKey" in index,
    "All player-facing dimensions share a single U scale":
        "local UNIT = 0.25" in grid
        and "MinSizeStepU = 0.25" in grid
        and "FitDiameterStepU=0.05" in grid
        and "NumericSizeStepU=0.01" in grid,
    "Face lattice matches resize increment":
        "Grid.Unit*Grid.MinSizeStepU" in surface,
    "Mechanical shaft and belt conversions use Grid.Unit":
        "/d.Grid.Unit" in mechanical
        and "path.Length/self.D.Grid.Unit" in mechanical,
    "Resize is clamped locally before submitting":
        "self.OnResolve(drag,requestedSteps,candidate)" in scale
        and "function Controller:ClampScaleSteps" in build,
    "Numerical sizes clamp in U increments":
        "function Controller:ClampNumericScale" in build
        and "Grid.QuantizeSize" in build
        and "Grid.NumericSizeStepU" in numeric,
    "Server rechecks actual geometry and constraints":
        "local function maximumClearResize" in construction
        and "mechanical:ValidateResize(player,before.instanceId)" in construction
        and "intersectsConstructed(model,ignore," in construction,
    "Grip respects current-operation precision":
        "payload.numericPrecision==true)" in construction
        and "local stepU=if numericOperation" in construction,
    "Server communicates accepted dimension to UI":
        "clamped=resizeClamped" in construction
        and 'or action=="DetectConnectedAssembly" or action=="Update"' in construction
        and "local acceptedSize=if data" in build,
    "Build and Resize show two-decimal U":
        "%.2f × %.2f × %.2f U" in build,
}
for name,passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if not all(checks.values()):
    raise SystemExit("Rope/resize/Units regression")
print(f"All {len(checks)} rope/resize/Units source checks passed.")
