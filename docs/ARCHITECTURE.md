# OpenWorks 2.0 — Roblox Engineering Architecture

**Status:** Locked engineering baseline, November 21, 2026. Current implementation: first Block vertical slice only.

## Design invariants

1. FORGE 3.2.0 owns lifecycle, service/controller registry, dependency graph, and remote transport. Application logic is organized into folders and internal ModuleScripts, not one giant root module.
2. Server-owned versioned documents are authoritative. Roblox Instances and physics objects are generated representations only.
3. All mutations travel through validated, revisioned commands. The server owns IDs, permissions, accepted revisions, and per-document undo/redo.
4. Clients may predict previews; they cannot directly mutate construction source.
5. Exactly five eventual primitive types: Block, Cylinder, Sphere, Wedge, Rounded Wedge.
6. Exactly three eventual geometric editing tool families: Drill/Cut, Pattern, Fillet/Chamfer. Source and modifier history remain nondestructive.
7. Mechanical features have stable IDs. SmartFit aligns features but does not imply a specific joint. Contact policy Auto / Never / Force compiles rigid groups; moving joints take precedence.
8. Machines have independent Stabilized/Active lifecycle; grounding is separate. Authored build poses never vanish into runtime physics state.
9. Harmonics stays independent and deferred until geometry and mechanics work.
10. Performance optimization follows profiling; only modified source subgraphs should be recompiled in later releases.

## Actual FORGE integration

The FORGE runtime here is based on the **Ruckus FORGE 3.2.0 core**. The service registry and network bridges are the real FORGE source, not a new homegrown service framework. `FORGE/init.lua` is an intentionally slim OpenWorks entry point: its only changes are dropping Ruckus-only subsystem imports/lifecycle calls.

FORGE 3.2's loader scans all descendant ModuleScripts beneath its registered roots. Therefore:
- Registered service entries live in `ServerScriptService.Services` only; private algorithm modules go elsewhere.
- Registered controller entries live in `PlayerScripts.Controllers` only.
- Pure shared modules never register themselves as FORGE components.
- Service dependencies are declared through `Dependencies` and accessed through `:GetDependency()`, rejecting cycles.
- Remote methods live under `Service.Client`, with endpoint `:Secure(...)` policies and server validation.

## Data contract

One authored OpenWorks unit = 1000 integer ticks. One unit currently maps to 0.25 Roblox studs for presentation. Logical standalone convention is 1u = 0.10m; physics scale/gravity will be calibrated separately. The authoritative document stores IDs, integer translations and dimensions rather than instance CFrames.

The first slice's schema is purposely a **minimal subset**:
```lua
{
  version = 1,
  revision = 0,
  blocks = {
    { id = "server-guid", x = 0, y = 2000, z = 0,
      sx = 4000, sy = 4000, sz = 4000 }
  }
}
```
Future versions add component hierarchy, modifier history, feature IDs, materials, transformations, machine graphs, and build poses through explicit migrations.

## Ownership

- `ConstructionService`: documents, validated operations, revisions, undo/redo.
- `GeometryService`: translates source to render/collider Parts. Never reads workspace to reconstruct saves.
- `PersistenceService`: DataStore serialization. Volatile mode on unavailable load.
- `BuildController`: first-person input, visual previews, selection, RPC requests.
- `Shared/Units` and `Shared/BlockDocument`: pure utilities/definitions, safe to require on either side.

## Slice boundaries

Slice 01 supports fixed-axis Blocks, uniform resize, relocation, delete, undo, redo and save/load. It deliberately does not pretend to have functioning CSG, precise fabricated holes, full rotation tools, rigid group compilation, network ownership management, physics state transitions or future Harmonics.

This limited slice gives us a testable end-to-end document lifecycle. Those deferred systems follow only once actual Roblox Studio testing confirms the current foundation.
