#!/usr/bin/env python3
"""Regression checks for Edit-mode F / Ctrl+D primitive and component duplication.

These source invariants guard the server-authorized copy path that used to
send Build-only Place while Edit was equipped. Live mouse/physics still needs Studio.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
def src(path): return (root/path).read_text(encoding="utf-8")
server=src("src/server/Runtime/ConstructionService.lua")
client=src("src/client/Controllers/ConstructionController.lua")
component=src("src/server/Runtime/ComponentService.lua")

def check(label,ok):
    assert ok,label
    print("PASS",label)

check("Build Place remains restricted to Build",
    'return if action=="Place" then hasEquippedTool(player,"Build")' in server)
check("Edit copy is a distinct server-whitelisted action",
    'and action ~= "DuplicatePrimitive"' in server
    and 'if action == "DuplicatePrimitive" then return duplicatePrimitive(player,payload) end' in server
    and 'then "Equip Edit (2) to duplicate an existing primitive"' in server)
check("Edit F/Ctrl+D routes copied single primitive to dedicated action",
    'self.Pending = if copy then "Copy" else "Move"' in client
    and 'if self.Pending=="Copy" then "DuplicatePrimitive" else "Place"' in client
    and 'sourceId=if self.Pending=="Copy" and self.Selected' in client)
check("Edit copy uses exact unsmoothed preview pose and retains error feedback",
    'orientation=if self.Pending=="Copy" then self.PreviewCF.Rotation' in client
    and 'if self.Pending=="Copy" then' in client
    and 'self:CancelPending()' in client)
check("Server source is owned and may not be client-fabricated",
    'local source=findOwned(player,payload.sourceId)' in server
    and 'local original=snapshot(source)' in server
    and 'local entry=Registry.Get(original.templateId)' in server
    and 'createFromTemplate(player,original.templateId)' in server)
check("Appearance, prefab size and fit origin come from server snapshot",
    'local duplicate=table.clone(original)' in server
    and 'duplicate.position=payload.position' in server
    and 'duplicate.steps=payload.steps' in server
    and 'applyState(model,duplicate)' in server
    and 'duplicate.fitPivotLocal=' not in server)
check("Duplicate is independent: no inherited assembly, component or grounding",
    all(x in server for x in ('duplicate.componentId=nil',
        'duplicate.componentAnchorId=nil','duplicate.assemblyId=nil',
        'duplicate.assemblyName=nil','duplicate.grounded=false',
        'duplicate.alignedOpeningId=nil')))
check("Server checks plot bounds, shape and collision before committing",
    'local valid,reason=validState(player,entry,duplicate)' in server
    and 'if payload.autoMate==nil and intersectsConstructed(model) then' in server
    and 'return finalizeNewPrimitive(player,model,payload)' in server
    and 'return false,"Duplicate intersects existing geometry"' in server)
check("Copy is an undoable authored edit, returning its new instance ID",
    'commitRecord(player, nil, after)' in server
    and 'local function finalizeNewPrimitive(player,model,payload)' in server
    and 'if result and action == "DuplicatePrimitive" then message = "Duplicated" end' in server
    and 'if result and (action == "Place" or action == "DuplicatePrimitive")' in server)
check("Component copy retains its separate Edit-authorized path",
    'action = if isCopy then "DuplicateComponent" else "TransformComponent"' in client
    and 'if componentAction and not hasEquippedTool(player,"Edit") then' in server
    and 'function ComponentService:Duplicate(player, payload)' in component)
check("Component copy remaps internal joint IDs and does not inherit assemblies",
    all(x in component for x in ('spec.sourceId=idMap[original.sourceId]',
        'spec.targetId=idMap[original.targetId]',
        'newState.assemblyId = nil','newState.assemblyName = nil',
        'newState.grounded = false')))
print("PASS: Edit mode duplication source contracts (Studio acceptance pending)")
