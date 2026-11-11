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
  │    ├─ HandCrankController (hold LMB to drive; release stops; no mouse drag)
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
       │     grounding, controlled crank rotation, pause/reset/cleanup
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
- `ConstructionService` is the only dispatcher for `OPENWORKS_ConstructionRequest`. The hand crank uses a validated `BeginCrank` press through this request; `OPENWORKS_CrankControl` carries authenticated held-input heartbeats and release signals, never arbitrary speeds. The server applies a fixed angular-speed target with bounded physical torque and cancels it on release, heartbeat timeout, pause, range loss, or stop.
- Only `Assembly` may `CreateAssembly` / `UpdateAssembly`. Only `Simulate` may start/pause/reset and operate a manual crank. `Edit` authors mechanical joints; `Weld` creates explicit touching-solid welds.
- Naming an assembly sends the **exact** selected primitive IDs to the server; it never trusts selected client Instances or automatically traverses relationships.
- Geometry mutation is different from metadata-only mutation. The latter uses `commitMetadata` / `restoreMetadata` to undo/redo membership, grouping and grounding **in place**; do not route it through destructive geometry reconstruction.

## Constructed vs simulated world

Authoritative constructed models live under `Workspace.OPENWORKS_Constructed`. They remain anchored during Edit. Simulating a registered assembly makes temporary clones under `Workspace.OPENWORKS_Simulated.Simulation_<UserId>`; Stop/Reset destroys only those clones. **Automatic spur-gear engagement:** `GearKinematics` scans every built Transmission gear in the selected assembly for compatible tooth module, parallel axes, real pitch-circle center distance and overlapping faces. Neither K nor saved Gear relationship metadata is needed to transmit rotation. Independent gears engage/disengage when those geometric conditions change. Weld/Fixed/Bolt-connected primitives sharing an axle are grouped into one kinematic body, so gear, rigidly attached shaft and crank rotate together. **No native physical drive, bearing, spring, weld constraints or collisions act on any gear-containing rigid group**; its cloned parts are anchored, noncolliding and server-PivotTo rotated. Unrelated models retain native Roblox physics and native joints. A validated LMB-held crank powers one kinematic group; ratios propagate through geometry-detected gear meshes only. There is NO motor attached to the meshed gears. Separately placed bearings and housings remain visible and can stay grounded. The gear-to-shaft mount remains explicit (Rigid for power transfer or Rotation for a gear spinning independently on its shaft); component editor grouping never creates a physical weld. Existing legacy K Gear relationships remain readable but are ignored by the runtime mesh solver.

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
- A single-crank assembly may be driven by holding LMB on any simulated mechanism part (even when its small handle is obscured). Multiple cranks still require a direct hit. Held-input heartbeats and release use `OPENWORKS_CrankControl` and are validated server-side. The server updates kinematic gear rotations on Heartbeat; the active input is one constant-speed crank, not per-frame client speeds. Only standalone ungeared crank shafts retain native bounded AngularVelocity. Releasing LMB, pausing, stopping, leaving range or losing input heartbeats disables the drive.
- Every client controller should own and disconnect its signals, visual folders and render bindings on `:Destroy()`.
- Do not change tool action names or IDs, template IDs, saved schema fields or relationship kinds without a deliberate migration.
- Retire dead UI paths instead of leaving unreachable branches; keep current rules in this document and old experiments in the archive.

## Known limitations

- **Not Roblox Studio verified in this pass.** Static audits cannot guarantee every connection, CSG collision, animation, camera lock, highlight, physics constraint or DataStore operation.
- The first kinematic gear solver is deliberately **fixed-axis, external spur gear only**. It uses angular tooth-count ratios without Roblox contact forces, so gear teeth cannot jam or shake native bearings. Engagement rechecks physical geometry during simulation. Gear groups themselves are anchored and therefore **cannot translate or slide into mesh through native physics**; dynamically moving gear carriages require future kinematic translation support. It is not yet a force/torque solver: load-dependent stalling, conservation of torque, backlash, tooth phase, free backdriving and collision damage are future work. Contradictory gear loops are stalled instead of being overdriven.
- Physics constraints can become unstable at small scale/high mass ratios; verify springs, multi-point joints, bolts and hand crank using the regression checklist.
- The large `ConstructionController`, `MechanicalService`, and `SimulationService` are still monolithic and should be split by responsibility in controlled future changes with tests. Rewriting them all without runtime verification risks losing current working behavior.
- Historical phase documents and the archived README contain superseded controls/decisions. Follow the present README and this document.
