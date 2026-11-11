# OPENWORKS — Current architecture

This document describes **current `dev` behavior**, not obsolete phase designs. Update it when module responsibilities, networking contracts, persistence or simulation semantics change.

## System boundaries

```text
Roblox native Tool (Build / Edit / Assembly / Simulate / Inspect / Weld)
  │
  ├─ client/Controllers  → input, presentation, ghosts, local-only 3D guides
  │    ├─ ToolController (tool equipped/activated state)
  │    ├─ ConstructionController (Build/Edit state and preview orchestration)
  │    ├─ LayeredEditingController, PhysicalHandles, ResizeGizmo (geometry editing)
  │    ├─ AssemblyToolController (named assembly drafts and purple preview)
  │    ├─ AssemblyController (Edit relationships + Simulate UX)
  │    ├─ HandCrankController (one-click start/stop; no mouse drag)
  │    ├─ RelationshipProperties (read/edit mechanical settings)
  │    ├─ WorldVisuals, ComponentOutline (adornments / grounded state)
  │    ├─ PlotSaveController (manual F6 Save/Load)
  │    └─ StudioTheme, ContextKeybinds (presentation)
  │
  ├─ shared/Construction → BuildConfig, ToolDefinitions, Registry,
  │    fit math, geometry math, axes, springs, gears, etc.
  │
  └─ ConstructionRequest / CrankControl (server)
       ├─ ConstructionService → authorization, ownership, tool/action dispatch,
       │     mutation history and construction-state validation
       ├─ ComponentService  → editor component group transforms + metadata
       ├─ AssemblyService   → exact named primitive membership
       ├─ MechanicalService → relation authoring, persistence specifications
       ├─ SimulationService → temporary physical clones, passive constraints,
       │     grounding, manual-crank torque, pause/reset/cleanup
       ├─ PlotService       → isolated per-player plot bounds
       └─ PlotPersistence   → validated explicit F6 persistence
```

FORGE/Reforge remains in `src/forge-shared` and `src/forge-server`; domain-specific modules are not imported into the framework kernel.

## Identity model

| Concept | Identity | What it DOES | What it DOES NOT do |
|---|---|---|---|
| Primitive | `InstanceId` and `TemplateId` | Template-based constructed object; one simulation body with welded **internal** prefab parts | Automatically weld to another primitive |
| Component | `ComponentId` + `ComponentAnchorId` | Editor selection/transform grouping of one or more primitives | Grant a hidden physical connection |
| Assembly | `AssemblyId` + `AssemblyName` on selected primitive models | Scope what `P` compiles; assign a human name | Discover connected neighbors or impose rigidity |
| Relationship | `RelationId`, kind, endpoints and limits | Define joints, fixed/weld, springs or gear mating | Generate energy |
| Actuator | Physical prefab with input/output metadata | Apply torque/force when a player or controller operates it | Reinterpret a passive relationship as an automatic motor |

**Invariant:** Components may be partially included in named assemblies; the physics graph must use **one body key per primitive**. A physical relationship crossing the assembly boundary invalidates simulation. A disconnected primitive can still belong to a named assembly. No membership action may secretly add joints or welds.

## Authority and requests

- Client state, ghost transforms, property panels and adornments are **advisory**.
- Server must verify **equipped native Tool**, owning player, individual IDs, valid data, plot, distance where appropriate, collisions and physical-fit limits before mutating.
- `ConstructionService` is the only dispatcher for `OPENWORKS_ConstructionRequest`. The hand crank uses a validated `BeginCrank` toggle through this request; the legacy `OPENWORKS_CrankControl` event is release-only and cannot inject speeds. The server applies a fixed angular-speed target with bounded physical torque and cancels it on pause/range loss/stop.
- Only `Assembly` may `CreateAssembly` / `UpdateAssembly`. Only `Simulate` may start/pause/reset and operate a manual crank. `Edit` authors mechanical joints; `Weld` creates explicit touching-solid welds.
- Naming an assembly sends the **exact** selected primitive IDs to the server; it never trusts selected client Instances or automatically traverses relationships.
- Geometry mutation is different from metadata-only mutation. The latter uses `commitMetadata` / `restoreMetadata` to undo/redo membership, grouping and grounding **in place**; do not route it through destructive geometry reconstruction.

## Constructed vs simulated world

Authoritative constructed models live under `Workspace.OPENWORKS_Constructed`. They remain anchored while editing. Registered assemblies are simulated by making temporary clones under `Workspace.OPENWORKS_Simulated.Simulation_<UserId>`. The compiler installs native passive joints on the cloned primary parts, internal prefab welds, explicit authored rigid relationships, and actual spring constraints. Only the hand-crank prefab may install native Torque input, toggled by a player click at a fixed requested angular speed. No relationship itself receives motor energy. Hand cranks resize their physical output diameter and radial subparts when explicitly coupled to a cylindrical shaft; the primary-part size is persisted and reconstructed by undo/redo and plot load. A gear hub mount must be explicitly authored as Rotation (unpowered Hinge/Bearing) or Rigid (Weld), never an editor-only component merge. A drilled block may be rigidly welded to a truly inserted, clearance-fitted shaft without metal-to-metal surface contact; arbitrary remote or floating welds remain rejected.

Simulating must never overwrite player-authored original CFrames or delete saved membership. Stop/Reset destroys session clones and restores original transparency/collision/anchoring. The server owns simulation physics; the client may only view/operate it through validated controls.

## Plot persistence and error handling

`PlotService` owns isolated 124×124 stud plots. `PlotPersistence` stores versioned records with primitive IDs, geometry state, component metadata, assembly metadata, grounding and mechanical relation specifications. On join the server attempts to **load the last manual save**. If Studio API access fails, the plot reports **Error** and saving is refused; *constructing may continue in the assigned in-memory plot*. Only the explicit `SavePlot` action invokes `DataStore:SetAsync`. Do not add autosaving on close, spawn, timer, pause or simulation.

**Busy flag invariant:** every load/save error path must clear `persistence.Busy[player]`. Loader apply and save encode are guarded; failure must not leave the UI saying Loading forever. Save failures must not overwrite the last known good document intentionally. Undo is volatile and clears upon loading; undo is not a save. Ctrl+Z/Ctrl+Y are also available while Assembly is equipped.

## World visuals and UI

3D Highlights/HandleAdornments are local-only Workspace children, grouped by owning controller so tool switches, deletion, simulation, undo and shutdown can clean them up. No construction helper Parts should be created for relationship guidance. Purple applies to the **entire aimed named assembly** before Simulate P; green/orange are fill-only physical grounded/moving states, blue is ordinary selection. To respect Roblox's client Highlight budget (255 total), world grounding cues are capped while up to 128 purple member highlights may be visible.

The shared Studio-style UI design lives in `StudioTheme.lua`. Normal Simulate remains locked first-person; the properties panel unlocks the mouse only while open; the assembly naming modal also temporarily unlocks it. All temporary UI/modal states must restore cursor ownership when they close.

## Code organization rules

- Only `ConstructionService` should dispatch authoritative construction requests and own construction history.
- Domain services should receive explicit dependencies through `.new(deps)`; do not write to arbitrary client state or DataStores.
- Add physical geometry algorithms to `src/shared/Construction` when reusable by both client preview and server validation.
- Avoid per-frame remote invocations. Hand-crank activation is a one-shot validated construction request; torque is integrated on server Heartbeat and the legacy crank event can only release.
- Every client controller should own and disconnect its signals, visual folders and render bindings on `:Destroy()`.
- Do not change tool action names or IDs, template IDs, saved schema fields or relationship kinds without a deliberate migration.
- Retire dead UI paths instead of leaving unreachable branches; keep current rules in this document and old experiments in the archive.

## Known limitations

- **Not Roblox Studio verified in this pass.** Static audits cannot guarantee every connection, CSG collision, animation, camera lock, highlight, physics constraint or DataStore operation.
- Gears currently rely on passive physical collision; precise torque transmission/contact stability and realistic gear trains need separate work.
- Physics constraints can become unstable at small scale/high mass ratios; verify springs, multi-point joints, bolts and hand crank using the regression checklist.
- The large `ConstructionController`, `MechanicalService`, and `SimulationService` are still monolithic and should be split by responsibility in controlled future changes with tests. Rewriting them all without runtime verification risks losing current working behavior.
- Historical phase documents and the archived README contain superseded controls/decisions. Follow the present README and this document.
