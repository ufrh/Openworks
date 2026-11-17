#!/usr/bin/env python3
"""Regression contracts for centered multi-hole fitting and one-shot Adjust Fit.

These tests verify active client/server source integration, not Studio physics.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(path): return (root/path).read_text(encoding="utf-8")
multifit=read("src/shared/Construction/MultiFitMath.lua")
smart=read("src/shared/Construction/SmartPlacement.lua")
insertion=read("src/shared/Construction/BoreInsertion.lua")
build=read("src/client/Controllers/ConstructionController.lua")
layered=read("src/client/Controllers/LayeredEditingController.lua")
menu=read("src/client/Controllers/ContextEditor.lua")
server=read("src/server/Runtime/MechanicalService.lua")
construct=read("src/server/Runtime/ConstructionService.lua")
alignment=read("src/shared/Construction/AlignmentMath.lua")
checks={
    "Single shaft center spans the extreme guide holes, not the first target":
        "function Fit.CenteredShaftOffset(" in multifit
        and "local midpointU=(minDepth+maxDepth)*0.5/Grid.Unit" in multifit
        and "table.insert(holes,hole)" in multifit,
    "Reverse alignment centers multiple moving holes on one fixed shaft":
        "function Fit.CenteredReverseOffset(" in multifit
        and "MultiFit.CenteredReverseOffset(" in smart
        and "MultiFit.CenteredReverseOffset(" in layered,
    "Other ungrouped guide candidates discovered before full fit":
        "local function candidateNear(candidate)" in multifit
        and "if near or Fit.Check(shaft,candidate,delta) then" in multifit
        and "local matched=candidateNear(candidate)" in multifit,
    "Auto shaft placement preserves exact geometric midpoint":
        "MultiFit.CenteredShaftOffset(" in smart
        and "cf=plan.delta*ghost:GetPivot()" in smart
        and "offset=centered" in smart
        and "return midpointU,count,holes" in multifit
        and "math.round(midpointU*2)" not in multifit,
    "Exact midpoint remains valid through plan and server offset checks":
        "function Alignment.IsOffsetValid(units)" in alignment
        and "math.abs(units)<=Alignment.MaxOffsetUnits" in alignment
        and "math.abs(units * 2 - math.round(units * 2))" not in alignment,
    "Insertion solver preserves true midpoint and rejects off-center fallback":
        "local centered=(requiredHoles and #requiredHoles>1)" in insertion
        and "local anchorU=if centered then preferredU else" in insertion
        and "if not found and not centered then" in insertion
        and "for _,otherHole in ipairs(requiredHoles)" in insertion
        and "for _,otherHole in ipairs(requiredMovingHoles)" in insertion
        and "MultiFit.Check(shaftModel,otherHole)" in insertion
        and "MultiFit.Check(otherHole,shaftModel)" in insertion,
    "Smart preview checks every required guide before allowing blue":
        "for _,id in ipairs(match.requiredFitTargets or {})" in build
        and "for _,id in ipairs(match.requiredMovingFitIds or {})" in build
        and "match.fitTargets=match.requiredFitTargets or names" in build,
    "Both Build and Edit carry required contacts to the server":
        "fitMovingIds=self.SmartMatch.fitMovingIds" in build
        and "fitMovingIds=match.fitMovingIds" in build
        and "fitMovingIds=mate.fitMovingIds" in construct
        and "if request.fitMovingIds~=nil then" in server
        and "confirmed[pair.movingId]=true" in server,
    "Manual alignment includes centered contacts in final transaction":
        "MultiFit.CenteredShaftOffset(" in layered
        and "fitTargets=selected.FitTargets" in layered
        and "fitMovingIds=selected.FitMovingIds" in layered,
    "Adjust Fit returns to choices without offering another Adjust":
        "self.FitAdjustRequested=true" in build
        and "self.FitAdjustRequested))" in build
        and "selected.AdjustRequested=true" in layered
        and "selected.AdjustRequested==true))" in layered
        and 'if option.id~="__Adjust" then' in menu,
    "Commit finishes the manual fit rather than entering a legacy loop":
        'parent:Message("Fit and relationship committed")' in layered
        and 'self:CancelAlignment()' in layered
        and 'selected.Stage="Fit"' not in layered[layered.index("function Layered:ConfirmAlignment()"):layered.index("function Layered:Click()")],
    "Manual preview retains the array of moving models":
        "local fixed,seenMoving={},{}" in layered
        and "if not seenMoving[id] then" in layered
        and "MultiFit.Completeness(\n            moving,targets,fitted,align.Reverse)" in layered,
    "After a failed relationship commit the same kind is retried, no modal":
        "selected.CommitKind=choice" in layered
        and "if selected.CommitKind then" in layered
        and "onChoice(selected.CommitKind)" in layered
        and "self.PendingFitRelationKind=kind" in build
        and "if self.PendingFitRelationKind then" in build,
    "Zero axial clearance creates a rotation-only multi-hole joint":
        "fittedTravel=0" in server
        and "fittedTravel<0.25" in server
        and "The fitted rods leave no sliding travel" not in server,
}
for title,okay in checks.items():
    print(("PASS" if okay else "FAIL")+": "+title)
if not all(checks.values()): raise SystemExit("Multi-hole/adjust-fit source contract failed")
print("PASS: All multi-hole/adjust-fit source contracts (Studio runtime verification still needed)")
