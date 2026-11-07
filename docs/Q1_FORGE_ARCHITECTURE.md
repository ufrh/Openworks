# OPENWORKS — Q1 / FORGE 4.4.1 runtime

## Source of truth
FORGE is imported from `ufrh/Ruckus` `dev`:
`src/shared/ReplicatedStorage/FORGE`, version 4.4.1.
All Kernel core, API, networking, Engine UI and development modules are
the original FORGE source. FORGE's server networking bridge is imported
from `src/shared/ServerScriptService/FORGE/Kernel/Networking`.

The root FORGE module has a narrow OpenWorks compatibility change:
Ruckus-only VAULT and Matchmaking engines are optional on the server.
The framework does **not** have another Registry/Loader/Lifecycle underneath it.

## Current execution flow
1. `src/server/init.server.lua` starts FORGE's original ServerBridge.
2. `src/client/init.client.lua` invokes `FORGE.Start({Roots = {Controllers}})`.
3. The FORGE Loader requires `Controllers/OpenWorksController.lua`,
   which registers the `FORGE.Controller("OpenWorksRuntime")`.
4. FORGE handles dependencies, Init, Start, scopes and shutdown.
5. OpenWorksRuntime owns one Free / Edit / Assembly mode machine.
6. The existing FORM editing implementation is temporarily isolated under
   Modes/Edit/LegacyFabricationAdapter until the Q2 tool migration.

## Game-mode boundaries
- Free — normal Roblox character, world-space visual component projections.
- Edit — fixed 40x40x20-stud midnight-steel/cyan chamber at (0,200,0).
- Assembly — separate local stage/camera. Q3 builds actual contact/retention.
- Component workspace dimensions are user X/Z specification, not chamber size.
- World placement is stored separately from edit-space coordinate frames.
- Chamber geometry never shadows, collides or participates in ray queries.
- Tool availability is centrally registered in Tools/ToolRegistry, owned by
  the FORGE OpenWorksRuntime controller.

## Q1 limitations / acceptance criteria
- Existing FORM editor remains a *legacy adapter* (Modes/Edit/LegacyFabricationAdapter.lua). Geometry
  algorithms are preserved until Q2. It is not a server-authoritative document
  system yet, and visual clones are **not physical, replicated assemblies**.
- Edit geometry and preview are client-local until Q2 migration.
- FORGE.VAULT persistence is not enabled.
- Q3 handles feature matching and physical assembly interactions.
- Studio verification has **not been executed** by the GitHub-only workflow.
- Run `scripts/VERIFY_Q1_FORGE.lua` on CLIENT and
  `scripts/VERIFY_Q1_SERVER.lua` on SERVER.
- Acceptance: boot as Free, place grid, instant enter Edit, sketch first solid,
  exit to Free with component in original position, enter Assembly, return to
  Edit without leaked chamber parts, and verify all three with test scripts.

## Non-negotiable future migration rule
New infrastructure is built with `FORGE.Service`, `FORGE.Controller`,
`FORGE.Signal`, `FORGE.Scope` and `FORGE.UI` where appropriate.
No OpenWorks-specific replacement for FORGE Kernel primitives.

## Q1 organization update
- The client root now contains only `init.client.lua`.
- The FORGE-owned controller lives in `Controllers/OpenWorksController.lua`.
- Legacy fabrication execution is isolated in `Modes/Edit`.
- Camera/view widgets are in `Experience/Cameras`; construction visuals
  are in `Experience/Visuals`; placement is in `Experience/Placement`.
- Tool functions are grouped in `Tools/{Sketch,Inspection,Snapping,Transform,Visuals}`.
- Geometry picking/topology is in `Systems/Selection`; compiled preview
  rendering is in `Systems/Components`.
- World/Assembly projection copies are cached and detached on mode exit;
  their cached instances are rebuilt only when geometry revisions change.
- `FORGE.Test("OpenWorks.Q1.ModeRegistration")` is registered by the
  controller and can be run through `FORGE.Tests:Run("OpenWorks.Q1")`.
- `FORGE.Metric("OpenWorks.Mode.TransitionMs")` and
  `FORGE.Metric("OpenWorks.Mode.Failures")` expose runtime diagnostics.
