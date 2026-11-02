# Decisions

- Name: OPENWORKS.
- Single Roblox place.
- `src/` is authoritative for Rojo-owned game code.
- Rojo serve port: 34872.
- Branches: `main` stable, `dev` active integration.
- Workflow based on RUCKUS START/STOP/PUSH, simplified to one place.
- Simulation: hybrid native physics and mathematical modeling with adaptive fidelity.
- Interactions: physical dragging, accurate fixtures and player-operated fabrication tools; the previous UI/equipping prototype has been removed for a fresh implementation.
- Geometry: editable render meshes backed by a canonical solid representation.
- Design: manuals for teaching, knowledge not gated by XP.
- Economy: manufacturing contracts fund invention; no compulsory crafting recipe trees.
- Electronics: prebuilt and player-fabricated paths supported.

## New fabrication direction

- Universal player-built entities are **assemblies**, not predefined machines.
- Optional components include 2D/3D Workspaces, material input/output ports, and toolheads.
- Initial `Workspace.Workbench` is authored directly in Studio. Parts named `surface` define its usable surface regions; collision/detection proxies will be generated from them at runtime.
- Starter tools: one rigid saw assembly and one rigid file assembly, both ordinary physical world objects, not Roblox Tool instances.
- Fabrication tools should be usable through a workbench when physically resting on it, with a future dedicated precision camera and mouse-driven strokes.
- Workbench surface detection now generates invisible runtime proxies from the parts named `surface` inside `Workspace.Workbench`.
- Tool assemblies are Model/BasePart instances with Boolean attribute `isTool = true`.
- Physical FORM materials carry the `FORMMaterial` CollectionService tag and `isMaterial = true` attribute, applied by the renderer (or `FORMMaterial.mark(instance)` for server-created materials).
- Workbench presence is exposed via `OnWorkbench` on detected objects, and `ToolCount` / `MaterialCount` on the workbench; no interaction or fabrication controls have been restored.

## Not decided

Detailed workspace support verification; assembly registration API; geometry persistence encoding; multiplayer property model; released machine limits.
