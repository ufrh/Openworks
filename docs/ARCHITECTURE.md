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
  │    ├─ PlotSaveController (F6 autosave status + manual Save/Load)
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
       └─ PlotPersistence   → dirty-only autosave + version-guarded manual F6
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

Authoritative constructed models live under `Workspace.OPENWORKS_Constructed`. They remain anchored during Edit. Simulating a registered assembly makes temporary clones under `Workspace.OPENWORKS_Simulated.Simulation_<UserId>`; Stop/Reset destroys only those clones. **Automatic spur-gear engagement:** `GearKinematics` scans every built Transmission gear in the selected assembly for compatible tooth module, parallel axes, real pitch-circle center distance and overlapping faces. Neither K nor saved Gear relationship metadata is needed to transmit rotation. Gear-to-gear drag placement recognizes actual tooth surfaces and the pitch circumference (separate from the tiny gear-to-shaft hub selection), moves the new gear into correct pitch/face engagement, and commits GEOMETRY ONLY through SmartMate; it never creates an implicit Gear relation or consumes joint slots. The server and client both validate the same AutoMeshStatus physical engagement criteria. Independent gears engage/disengage when those geometric conditions change. Weld/Fixed/Bolt-connected primitives sharing an axle are grouped into one kinematic body, so gear, rigidly attached shaft and crank translate and rotate cohesively. When placing a moving gear near TWO stationary gears, SmartPlacement can solve the geometric intersection of both pitch circles and favor the valid two-mesh position. The runtime graph supports multiple outputs from any gear and drives bidirectionally from whichever shaft carries the active crank; no particular stage count or branch arrangement is hardcoded. **No native physical drive, bearing, spring, weld constraints or collisions act on any gear-containing rigid group**; its cloned parts remain anchored/noncolliding and server-PivotTo animated. Separately, GearKinematics adds scripted gravity/translation to unsupported gear+shaft groups (including the crank), detects support from grounded authored bearing housings, and settles them against grounded/static world surfaces via downward raycasts. A free-spinning gear on a falling native shaft follows that shaft's position and axle tilt without inheriting its axial rotation. This translational approximation does NOT feed native bearing forces back into the gears. Unrelated models retain native Roblox physics and native joints. A validated LMB-held crank powers one kinematic group; ratios propagate through geometry-detected gear meshes only. There is NO motor attached to the meshed gears. Separately placed bearings and housings remain visible and can stay grounded. The gear-to-shaft mount remains explicit (Rigid for power transfer or Rotation for a gear spinning independently on its shaft); component editor grouping never creates a physical weld. Existing legacy K Gear relationships remain readable but are ignored by the runtime mesh solver.

Simulating must never overwrite player-authored original CFrames or delete saved membership. Stop/Reset destroys session clones and restores original transparency/collision/anchoring. The server owns simulation physics; the client may only view/operate it through validated controls.



### Transmission profiles: spur, bevel, and rack

`GearMath.Kind` and `GearMath.AutoMeshStatus` classify and validate physical contact, while `GearKinematics` discovers a procedural bidirectional motion graph. New Transmission catalog prefabs: matched `Bevel45_12T` and `Bevel45_20T` (equal-tooth, 22.5° pitch cones on shafts meeting at 45°); `Rack_4Stud` and `Rack_8Stud`; `RackGuide_8Stud` and `RackGuide_12Stud`. Unequal-tooth bevel pairs are deliberately rejected until their complementary pitch cones can be fabricated, rather than assuming a false 1:1 cone geometry.

Bevel placement computes an intersecting *pitch-cone apex* and appropriate 45° axle direction. The server revalidates the geometry before committing; there are no inferred welds or Gear relationships. A rack/pinion pair must have matching tooth module, parallel pinion/rack X axes, adequate tooth-face overlap, and correct pinion pitch-circle distance above the rack. Racks travel along their local Z axis; `v = ω × pitchRadius` is the graph edge, and its reciprocal backdrives the pinion. Stationary, explicitly grounded RackGuide geometry is separately validated and provides scripted support and bounded rail travel; hitting a rail end stalls the connected transmission. Holding **Q/E** over a supported rack (or its guide) applies server-controlled `±1.5 studs/s` linear input to the same solver; only signed input state and heartbeat are transmitted, never arbitrary client torque or CFrame. Holding LMB on the hand crank remains the rotational input; one source is active at a time.

**Duplication invariant:** a single-primitive F copy always gets a fresh server GUID and remains mechanically independent. A duplicated multi-primitive component gets fresh GUIDs for *every primitive*, a fresh ComponentId and an internally remapped ComponentAnchorId. All **fully internal** authored relationships (weld, bearing, slider, cylinder, spring, bolt and shared fit sets) are independently recreated under new RelationIds, with their source/target/auxiliary IDs remapped to the copied primitives and tuning retained. Links to primitives outside the component are deliberately omitted to prevent reconnecting copies to originals. Internal AlignedOpeningId, offset and roll are preserved with mapped IDs; external alignment is cleared. Assembly membership and grounding are not inherited. Duplication and the new relationships form one undo/redo transaction. Gear/Rack/Guide engagement remains geometry-driven, not an authored relationship.

### Face-relative construction snapping

Build/Edit preview now chooses the face of the **actual targeted constructed part**. The moving shape's oriented minimum support is brought flush to the hit face; its two tangent coordinates snap in the target part's LOCAL frame using a 0.25-U fabrication lattice, with face center and edge alignment taking precedence within the capture range. This removes world-grid parity drift between differently sized parts and works for top, bottom and side faces without creating an automatic joint. Ground/plot-floor placements retain ordinary world-grid snapping; the server continues validating precise geometry and collision as before. Mechanical socket/gear alignment retains priority whenever a valid specialized snap is found.

### Hardware-first mechanical joints, shaft drive and material system

A physical shaft must fit inside a verified opening before authoring a **Bearing (Rotation Only)**, **Slider**, or **Cylindrical** relationship. Under the hood, native Roblox constraints enforce the allowed degrees of freedom. The arbitrary **Alt+J** AxisHinge / AxisBall / AxisUniversal / PoweredHinge editor and server creation paths are retired. Players must construct the geometry rather than connecting two unrelated solids with a hidden physics constraint. Existing plot saves load the physical bodies and supported joints; unsupported retired arbitrary-axis joints are skipped with an explicit warning.

An optional **Shaft Motor** is now configured on an authored *Bearing*, never on two floating parts. Equip **Simulate**, inspect a physical bearing in the Properties panel, enable Shaft Motor, choose a hold key, signed angular velocity (rad/s), torque and acceleration, then save. The Simulate client sends only held-key liveness and the server owns the saved motor settings. Motors stop on release/pause or after 0.45 seconds of missing input. Motor drive is currently a software-controlled native actuator on real shaft hardware, not yet a separate fabricated electric motor or an electrical circuit. Kinematic gears remain primarily hand-crank driven until power sources are integrated into GearKinematics.

`MaterialCatalog` defines Steel, Aluminum, Rubber, Plastic, Wood, and Concrete. **M** in Edit opens a native Roblox material picker for the selected primitive or full editor component. The material is represented by appearance, density, friction, elasticity, and weighted native `CustomPhysicalProperties`; choose Rubber for tire surfaces. The selected material is stored in the primitive snapshot, inherited by component duplication, and included in manual plot save/load. Presets alter physical contact and mass rather than bypassing Roblox's physics; tire slip, anisotropic tread, thermal behavior and wear are not yet modeled.

**Alt+arrows** in Edit and Assembly replace Alt+mousewheel. Up/Down always raise/lower on WORLD Y, Left/Right nudge along the camera's horizontal right direction; **Shift+Alt+any arrow** uses fine 0.05-stud steps, versus ordinary 0.25. The server chooses X, Y or Z, verifies ownership and all member moves against the plot/collision system, and commits a single undo record for the entire selected component or named assembly.

## Plot persistence and error handling

`PlotService` owns isolated 124×124 stud plots. `PlotPersistence` stores versioned records with primitive IDs, geometry state, component metadata, assembly metadata, grounding and mechanical relation specifications. On join the server attempts to **load the latest saved plot**. Failed/corrupt loads report **Error**, refuse autosave, and preserve the remote save; construction may continue temporarily in memory. Successful edits mark only the authored plot dirty. The server checks every 10 seconds, writes approximately every **120 seconds while changes are pending**, waits at least 10 seconds after first edit, and retries transient failures no faster than 45 seconds. **PlayerRemoving** and **BindToClose** attempt a final dirty-only save before tearing down models and relationships. Manual F6 Save/Load still works, and loading discards local unsaved edits only after confirmation. All writes use the original schema-v1 DataStore key with `DataStore:UpdateAsync` and a `writeId` compare-and-swap guard, preventing stale sessions from silently replacing newer data. Failed load does not generate an empty fallback write, and temporary simulation clones never enter persistence.

**Busy flag invariant:** every load/save error path must clear `persistence.Busy[player]`. Loader apply and save encode are guarded; failure must not leave the UI saying Loading forever. Autosave failures keep edits dirty and retry; a detected cloud revision conflict disables writing until a deliberate reload. Successful writes alone clear dirty flags. Save failures must not intentionally overwrite the last known good document. Undo is volatile and clears upon loading; undo is not a save. Ctrl+Z/Ctrl+Y are also available while Assembly is equipped.

## World visuals and UI

3D Highlights/HandleAdornments are local-only Workspace children, grouped by owning controller so tool switches, deletion, simulation, undo and shutdown can clean them up. No construction helper Parts should be created for relationship guidance. Purple applies to the **entire aimed named assembly** before Simulate P; green/orange are fill-only physical grounded/moving states, blue is ordinary selection. To respect Roblox's client Highlight budget (255 total), world grounding cues are capped while up to 128 purple member highlights may be visible.

The shared Studio-style UI design lives in `StudioTheme.lua`. Normal Simulate remains locked first-person; the properties panel unlocks the mouse only while open; the assembly naming modal also temporarily unlocks it. All temporary UI/modal states must restore cursor ownership when they close.

## Code organization rules

- Only `ConstructionService` should dispatch authoritative construction requests and own construction history.
- Domain services should receive explicit dependencies through `.new(deps)`; do not write to arbitrary client state or DataStores.
- Add physical geometry algorithms to `src/shared/Construction` when reusable by both client preview and server validation.
- A single-crank assembly may be driven by holding LMB on any simulated mechanism part (even when its small handle is obscured). Multiple cranks still require a direct hit. Held-input heartbeats and release use `OPENWORKS_CrankControl` and are validated server-side. The server updates gear rotation/translation on Heartbeat, eased toward the crank's fixed target speed. The solver runs its scripted rotation at up to 60 Hz and decelerates briefly after release to avoid visually abrupt stops. Only standalone ungeared crank shafts retain native bounded AngularVelocity, now with a smoother speed ramp. Releasing LMB, pausing, stopping, leaving range or losing input heartbeats disables new drive input; Stop/Pause also ends the simulation's motion.
- Every client controller should own and disconnect its signals, visual folders and render bindings on `:Destroy()`.
- Do not change tool action names or IDs, template IDs, saved schema fields or relationship kinds without a deliberate migration.
- Retire dead UI paths instead of leaving unreachable branches; keep current rules in this document and old experiments in the archive.

## Known limitations

- **Not Roblox Studio verified in this pass.** Static audits cannot guarantee every connection, CSG collision, animation, camera lock, highlight, physics constraint or DataStore operation.
- The kinematic transmission solver currently supports fixed-axis external spur gears, **matched equal-tooth 45° bevel pairs**, and guided straight racks, with rotation restricted to authored axle directions. It uses signed tooth-count ratios without Roblox contact forces, so gear teeth cannot jam native bearings; the motion graph branches and can propagate backward from any crank-driven stage. Gear+shaft groups can drop under scripted gravity and follow bearing-mounted shafts, but this is an approximate vertical/tilt support model, NOT rigid-body collision physics. Dynamic guided carriages beyond the straight rack template, true load-bearing tooth contacts, torque-conserving backdrive, backlash, tooth phase, collision damage, unequal-ratio bevel cones and curved/helical gear profiles are future work. Guided rack support is scripted (not native contact forces), and the Q/E rack push is an explicit kinematic test actuator. Contradictory closed loops are halted instead of overdriven.
- Physics constraints can become unstable at small scale/high mass ratios; verify springs, multi-point joints, bolts and hand crank using the regression checklist.
- The large `ConstructionController`, `MechanicalService`, and `SimulationService` are still monolithic and should be split by responsibility in controlled future changes with tests. Rewriting them all without runtime verification risks losing current working behavior.
- Historical phase documents and the archived README contain superseded controls/decisions. Follow the present README and this document.


### Compact drilled block
`CompactHoleLibrary.Ensure()` runs a single GeometryService subtraction at server startup to provision the optional `DrilledBlock_1U_D098` template, and never during construction, snapping or simulation. It produces a 1 U cube with a true Y-axis 0.98 U circular bore and explicit `HoleDiameterU` metadata consumed by the shared BoreClearance math. It is separate from all existing authored drilled blocks. If CSG fails, no misleading solid-block substitute is installed. Its 0.01 U walls are exceptionally thin and require in-Studio verification; this is a deliberate compact-sized exception to the generally prebaked template policy.

### 90-degree bevel gears
`GearLibrary` includes matching `Bevel90_12T` and `Bevel90_20T` gear templates whose pitch cones have 45° half angles, so fitted shafts may intersect at a right angle. The same verified axle/apex/pitch predicate is shared between smart snapping and kinematic simulation; mixed 45°/90° pairs are not accepted. Equal tooth counts provide 1:1 speed transfer and explicitly modeled toothed annuli with a physical shaft bore. Gear transmission is currently the deterministic simulation kinematics system, not native tooth contact physics.

### Key-bound motor on physical bearing
The retired PoweredHinge shortcut does not remove power: an existing, physically fitted shaft/bore Rotation Only relationship can be configured with **Simulate > Properties > the Bearing relationship > HOLD-KEY MOTOR**. This sets an optional motor on the native hinge constraint using a hold-to-run key, angular velocity, max torque and acceleration. Unlike arbitrary axis creation, it does not manufacture a magical pivot. Server ownership and saved relationship settings are authoritative; motor inputs stop on release or missing heartbeats. Validation in Studio is still required, particularly when the gear kinematic solver owns the driven shaft.

### Paint, surface finishes, and physical materials
Paint is independent of engineering material. **M** in Edit opens Paint Studio with a Paint & Finish tab and a Physical Material tab. You can color an owned primitive or a selected component using 18 quick swatches or any `#RRGGBB` hex, select Original, Matte, Satin, High Gloss, Metallic, Chrome, Brushed Metal or Pearlescent and apply/reset the finish. Server authorization, component targeting, history, duplication, and manual save/load use model-level `PaintFinish` and `PaintColorHex` attributes. `MaterialCatalog` sets density, grip, restitution and native physical properties; `PaintCatalog` touches only visual material, color, and reflectance so chrome bodywork does not magically change suspension density or tire traction. The Roblox standard BasePart material/reflectance approximation is NOT physically based real-world automotive clearcoat, anisotropic brushed metal or environmental mirror reflection; true mirror/PBR coatings would require supported textures/shader assets and a separate renderer workflow. Whole-primitive/component painting is in scope, per-face painting/decal livery is not in this first release.

When Roblox reports a DataStore error, the backend may already have written that attempted revision. `PlotPersistence.UncertainWriteIds` tracks only this server's failed request IDs and allows a subsequent `UpdateAsync` to adopt its own previously committed write, while still rejecting any unrelated concurrent session's newer revision. This prevents a transient unknown-outcome error from permanently locking an otherwise safe autosave lineage.

### Through-shaft multi-opening hinges and accurate bore targeting
A shaft no longer needs its midpoint inside the housing for **Rotation Only**. The shared `AlignmentMath.InsertionBounds` validates positive physical overlap of the complete shaft segment and each coaxial bore, so a single long pin can pass through **two or more independently placed drilled blocks/tubes**. `MultiFitMath.StationarySet` merges the clicked target's rigid/editor scope with separately built, owned bore models that are geometrically engaged by that shaft (without automatically adding unrelated gear hubs). `MultiFit.Unique` keeps normal maximum 1:1 matching for multi-shaft patterns, then adds verified additional bore contacts along the same shaft. Every accepted contact becomes an explicit shaft-hole relationship during a single atomic SmartMate operation, is persisted, and is collision-exempted only after actual geometry clearance checks. Client Build/Edit preview and manual **Edit > L > Align** call the same multi-contact validators, including ray-to-bore-center picking through genuinely empty CSG holes. A pin with several different moving bodies may create multiple native bearings; for long separated hinge pins choose **Rotation Only**. Slider/Cylindrical constraints still use the stricter housing-center tube-face travel bounds and reject center-outside placements. Resizing/posing a shaft rechecks the other openings; coupled gear hubs still require the explicit Hub choice. These are source-level changes requiring a real Studio physical joint/plot test.
