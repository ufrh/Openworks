#!/usr/bin/env python3
"""Source integration contracts for automatic, connected mechanical assemblies.

Checks *wiring* across server detection, simulation engines and UI.
Full physics/hover behavior requires a Studio playtest.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def src(relative): return (root/relative).read_text(encoding="utf-8")
detector=src("src/server/Runtime/AssemblyService.lua")
physical=src("src/server/Runtime/PhysicalSimulationService.lua")
rack=src("src/server/Runtime/RackSimulationService.lua")
router=src("src/server/Runtime/UnifiedSimulationService.lua")
service=src("src/server/Runtime/ConstructionService.lua")
client=src("src/client/Controllers/AssemblyController.lua")
preview=src("src/client/Controllers/AssemblyToolController.lua")
editor=src("src/client/Controllers/ContextEditor.lua")
subtools=src("src/shared/Construction/SubtoolDefinitions.lua")
help_text=src("src/client/Controllers/ToolHelpDefinitions.lua")

detect_scope=detector[detector.index("function Service:DetectConnected("):
    detector.index("function Service:Requested(")]
checks={
    "Implicit detector traverses only owned mechanical links and valid gear meshes":
        'self.D.findOwned(player,payload.seedId)' in detect_scope
        and 'relation:GetAttribute("OwnerUserId")==player.UserId' in detect_scope
        and 'relation:GetAttribute("Kind")~="Gear"' in detect_scope
        and 'GearMath.AutoMeshable(toothed[i],toothed[j])' in detect_scope,
    "Neither old AssemblyId nor editor-only ComponentId defines connectivity":
        'GetAttribute("AssemblyId")' not in detect_scope
        and 'GetAttribute("ComponentId")' not in detect_scope
        and 'GetAttribute("InstanceId")' in detect_scope
        and 'table.sort(queue)' in detect_scope,
    "Simulation receives read-only detector and ignores persisted membership":
        'assemblies = assemblies,' in service
        and 'assemblies:DetectConnected(player,{' in physical
        and 'assemblies:DetectConnected(player,{' in rack
        and 'GetAttribute("AssemblyId")' not in physical[physical.index("function Simulation:Graph("):physical.index("function Simulation:Stop(")]
        and 'GetAttribute("AssemblyId")' not in rack[rack.index("function Simulation:Graph("):rack.index("function Simulation:Stop(")],
    "Both runtime graphs include exactly detected connected IDs":
        'for _,id in ipairs(ids) do' in physical
        and 'for _,id in ipairs(ids) do' in rack
        and 'local selected={}' in physical
        and 'local selected={}' in rack
        and 'assemblyName="Connected mechanism"' in physical
        and 'assemblyName="Connected mechanism"' in rack,
    "Router chooses engine from live connected graph rather than AssemblyId":
        'self.D.assemblies:DetectConnected(player,{' in router
        and 'memberIds[model:GetAttribute("InstanceId")]' in router
        and 'kind=="Rack" or kind=="RackGuide"' in router
        and 'GetAttribute("AssemblyId")' not in router,
    "Existing manual registration write requests disabled":
        'if action~="DetectConnectedAssembly" then' in service
        and 'Assemblies are automatic; connect parts to group them' in service,
    "Hover preview uses asynchronous server detection and purple group outline":
        'function Tool:RefreshConnectedPreview(seed)' in preview
        and 'action="DetectConnectedAssembly",seedId=id' in preview
        and 'task.spawn(function()' in preview
        and 'self:ShowVisuals(members,PURPLE)' in preview
        and 'self.Feedback:Set("assembly","outer",ordered,"assembly",true)' in preview,
    "Hover detection cannot throttle P or construction writes":
        'local lastDetection = {}' in service
        and 'if action=="DetectConnectedAssembly" then' in service
        and 'lastDetection[player]=now' in service,
    "Simulate starts from any aimed owned primitive, no saved registration":
        'self:StartRegisteredAssembly(seed)' in client
        and 'self:Pick() or (chosen and chosen.members' in client
        and 'SimAssemblyName="Connected mechanism"' in client
        and 'Select a registered assembly first' not in client,
    "Manual Assembly Editor is no longer an accessible subtool":
        'Default="Simulation"' in subtools
        and 'Id="AssemblyEditor"' not in subtools
        and 'Simulate aimed mechanism' in help_text,
    "Context menu supports auto-detected simulation from ordinary primitives":
        'Run connected mechanism' in editor
        and 'if running or not node then return false end' in editor
        and 'self:RenderSimulationControls(node)' in editor
        and 'Select a registered assembly' not in editor,
}
for label,passed in checks.items():
    print(("PASS" if passed else "FAIL")+": "+label)
if not all(checks.values()):
    raise SystemExit("Implicit assembly regression check failed")
print(f"PASS: {len(checks)} implicit assembly source contracts; Studio playtest required")
