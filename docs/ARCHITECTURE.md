# OPENWORKS — Current architecture

This document describes the **feature-branch architecture** proposed for `dev`; it does not imply the draft PR has been merged or physically validated in Roblox Studio. Update it when module responsibilities, networking contracts, persistence or simulation semantics change.

## System boundaries

```text
Roblox native Tool (Build / Assembly / Simulate / Inspect / Weld / Belt)
  │
  ├─ client/Controllers  → input, presentation, ghosts, local-only 3D guides
  │    ├─ ToolController (tool equipped/activated state)
  │    ├─ ConstructionController (one native Build tool; contextual select/place state)
  │    ├─ LayeredEditingController, PhysicalHandles, ResizeGizmo (geometry editing)
  │    ├─ AssemblyToolController (named assembly drafts and purple preview)
  │    ├─ AssemblyController (Build relationships + Simulate UX)
  │    ├─ HandCrankController (hold LMB to drive; release stops; no mouse drag)
  │    ├─ RelationshipProperties (read/edit mechanical settings)
  │    ├─ WorldVisuals, ComponentOutline (adornments / grounded state)
  │    ├─ PlotSaveController (F6 autosave status + manual Save/Load)
  │    └─ StudioTheme, ContextKeybinds (presentation)
  │
  ├─ shared/Construction → BuildConfig, ToolDefinitions, Registry,
  │    fit math, geometry math, axes, springs, gears, pulleys, belts
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
- Only `Assembly` may `CreateAssembly` / `UpdateAssembly`. Only `Simulate` may start/pause/reset and operate a manual crank. `Edit` authors mechanical joints; `Weld` creates explicit touching-solid welds. Only `Belt` may author a two-pulley friction belt, and neither belt nor pulley creates a motor.
- Naming an assembly sends the **exact** selected primitive IDs to the server; it never trusts selected client Instances or automatically traverses relationships.
- Geometry mutation is different from metadata-only mutation. The latter uses `commitMetadata` / `restoreMetadata` to undo/redo membership, grouping and grounding **in place**; do not route it through destructive geometry reconstruction.

## Constructed vs simulated world

Authoritative constructed models live under `Workspace.OPENWORKS_Constructed`. During Edit, authored geometry is stationary. Simulating a registered assembly creates temporary physics clones under `Workspace.OPENWORKS_Simulated.Simulation_<UserId>`; Stop/Reset returns to authored geometry. **Automatic gear engagement:** `GearTransmission` detects compatible spur and bevel gear tooth geometry (module, pitch circle, face overlap and verified pitch-cone apexes). Each gear fitted to a shaft is ALWAYS rigidly connected with a `WeldConstraint`, including multiple gears on the same shaft. A welded shaft/gear group is an ordinary Roblox physics assembly: its real bearings remain active, its gear teeth are excluded from tooth collision jitter, and the transmission solver applies reciprocal, torque-limited gear mesh forces to the actual shafts rather than changing gear CFrames. Power is bidirectional: an opposing motor or load may stall or backdrive the input if sufficient torque is available. Compound gear trains work by sharing welded shafts, with all mounted gears contributing torque through that shaft. There are no independent/dependent gear modes. Gear-to-gear smart placement is geometry only and does not create implicit gear-edge relationships. Legacy K/Gear metadata remains ignorable. Existing explicit assemblies remain the only simulation scope.

Simulating must never overwrite player-authored original CFrames or delete saved membership. Stop/Reset destroys session clones and restores original transparency/collision/anchoring. The server owns simulation physics; the client may only view/operate it through validated controls.



### Transmission profiles: spur and bevel

`GearMath.Kind` and `GearMath.AutoMeshStatus` classify and validate compatible spur and bevel contacts; `GearTransmission` handles physical, bidirectional shaft torque. The gear catalog includes spur gears and matching `Bevel45_12T`, `Bevel45_20T`, `Bevel90_12T`, and `Bevel90_20T` tapered solids. The 45° and 90° bevel sets currently require matching tooth counts and pitch-cone geometry. Rack-and-pinion and rack-guide templates are deliberately **not available**: players must fabricate their own linear-motion mechanisms using ordinary components, bearings, sliders, cylinders, springs, cams or linkages.

Bevel placement computes intersecting *pitch-cone apexes* and the appropriate shaft angle. The server revalidates the geometry before committing; gears only become part of a rotating shaft when the builder fits them coaxially into a shaft hub, at which point the weld is automatic. Simulate uses native constraints and the welded shaft's current angular velocity to calculate reciprocal torque. A grounded housing supports a shaft through its authored physical bearing, not through scripted support or invisible anchoring. Dedicated guided-rack and Q/E rack-drive shortcuts have been removed.

**Duplication invariant:** a single-primitive F copy always gets a fresh server GUID and remains mechanically independent. A duplicated multi-primitive component gets fresh GUIDs for *every primitive*, a fresh ComponentId and an internally remapped ComponentAnchorId. All **fully internal** authored relationships (weld, bearing, slider, cylinder, spring, belt, bolt and shared fit sets) are independently recreated under new RelationIds, with their source/target/auxiliary IDs remapped to the copied primitives and tuning retained. Links to primitives outside the component are deliberately omitted to prevent reconnecting copies to originals. Internal AlignedOpeningId, offset and roll are preserved with mapped IDs; external alignment is cleared. Assembly membership and grounding are not inherited. Duplication and the new relationships form one undo/redo transaction. Gear meshing remains geometry-driven, not an authored relationship.

### Friction belt transmission (two-pulley phase)

`PulleyLibrary` registers fixed-size open-bore `Pulley_5U`, `Pulley_8U` and `Pulley_12U` under Transmission. Each has an actual faceted annular rim and an invisible noncolliding pivot. Both insertion directions use `SmartPlacement.HubPose` + `BoreClearance.ShaftFits`; valid hub fitting **automatically authors a Weld** to the physical cylinder shaft. Bearing supports are independent constructions, not part of the pulley prefab.

Equip **Belt**, click two distinct, shaft-welded pulleys, and the server checks ownership, range, mount welds, separate shafts, parallel axes, coplanarity, diameter and nonintersection. A single `Belt` relationship records pulley endpoint IDs plus `BeltRestLength`. Use **[** / **]** while holding the Belt tool to select 0–8% preload in 0.5% increments (default 1.5%), then click the second pulley to fit. To remove one specific belt without detaching a shaft weld, select the first pulley and **Shift+click** the second. The continuous open-belt path is computed by `BeltMath`; `BeltVisual` renders 32 connected, noncolliding beam spans around both pulley circumferences. There are no hidden welds between the two shafts, no automatic drives and no ready-made linear actuator.

When the registered assembly simulates, `BeltTransmission` groups authored fixed/weld/bolt-connected primitives by shaft, rebuilds the exact belt path from the cloned moving pulley positions, and applies reciprocal native `Torque` constraints to the actual shaft assemblies. Belt tension scales with positive stretch beyond the saved rest length; the wrap-angle friction limit caps transferred torque. Torque is reciprocal and supports backdrive; insufficient grip produces **slip**, not perfect synchronization. Editing pulley separation recalculates the displayed belt path and keeps the relation while the route is valid. The original authoring beams hide while simulating and return on Stop. The relationship persists through plot autosave, undo/redo and component duplication when both endpoints are included.

**Current scope:** open friction belts, two pulleys per loop, one plane, editable initial rest length/preload. No crossed routing, idlers/multi-pulley loops, spring tensioner model, toothed timing engagement, belt segment collisions, wear, tooth jump, or explicit radial bearing load from belt tension yet. The native torque model is a bounded approximation requiring Studio playtests under load; architecture contracts only verify source invariants.

### Unified feature fitting and universal alignment origins

`FitFeatureRegistry` defines the same **Shaft / Bore / Hub / Gear** semantic compatibility for unified Build placement/selection and server `SmartMate`. `SmartPlacement` continues to delegate actual diametric clearance, penetration, multi-hole constraints, gear pitch and rollback to the existing specialized geometry solvers rather than weakening their precision. It caches feature descriptors once per scanned model. `FitSolver` adds geometric **Pivot** candidates only when the player aims near an explicitly authored origin; this is a **FitOnly** placement, never a hidden weld or motor.

Every authored primitive may store a **`FitPivotLocal`** Vector3 relative to its model pivot. A grouped component stores **`ComponentFitPivotLocal`** on its canonical, previously recorded `ComponentAnchorId` primitive, so choosing another member or changing geometric center cannot shift the origin. Both primitive and component origins are nonphysical metadata and leave `PrimaryPart`, collision, relationship frames, and native physics untouched. The shared `FitOrigin` module handles reference-frame conversion, selected-component anchors and preview-world placement.

**Edit origin:** select any primitive or a whole component, press **O**, aim at a solid face of the selected geometry, and click. Use **Q/E** to cycle **Cursor (exact hit)**, **Face (center)**, **Edge (nearest midpoint)**, and **Corner (nearest bounding-box corner)**; the latter three use the selected part's oriented bounds and may define logical origins in otherwise empty CSG areas. The server validates ownership, plot bounds and that the chosen world point lies inside the hit solid's allowed oriented bounds, then saves the local-space offset with metadata-only undo. **Shift+O** resets the selected scope to its default origin, even during origin selection; **Esc** cancels selection. The cyan origin handle (identical for primitives and components, reserving purple for assembly simulation scope) only appears while editing an origin or after an origin has been set. A customized grab origin is shown on moving previews.

**Use:** when dragging an authored primitive or component, its origin can be positioned directly against the selected surface point; when aiming close to another explicitly set primitive/component origin, the preview snaps origin-to-origin. R/T/Y world quarter-turns likewise rotate around the custom origin. Existing noncustomized objects retain default center/face snapping and default centered rotation. The normal blue/red collision preview still decides whether the placement can commit. Pivot matching remains **geometric only**, whereas physical shaft/hole/hub fitting still requires separate geometry checks and the appropriate authored relationship. No shortcut can connect two mechanically incompatible parts.

All offsets persist through snapshot/restore, undo/redo, save/load (backward-compatible optional fields), primitive F copy and component duplication. The component's fixed anchor identity is preserved across ordinary transforms. An anchor deleted from a component cannot preserve its old pivot until migrated by an explicit future re-anchoring operation. This version supports cursor-based and face/edge/corner origins; numeric XYZ offset editing, pivot-axis orientation, and user-authored multi-feature fitting constraints are not yet provided. Studio interaction and rigid-body playtests remain required.

### Face-relative construction snapping

Unified Build placement preview now chooses the face of the **actual targeted constructed part**. The moving shape's oriented minimum support is brought flush to the hit face; its two tangent coordinates snap in the target part's LOCAL frame using a 0.25-U fabrication lattice, with face center and edge alignment taking precedence within the capture range. This removes world-grid parity drift between differently sized parts and works for top, bottom and side faces without creating an automatic joint. Ground/plot-floor placements retain ordinary world-grid snapping; the server continues validating precise geometry and collision as before. Mechanical socket/gear alignment retains priority whenever a valid specialized snap is found.

### Hardware-first mechanical joints, shaft drive and material system

A physical shaft must fit inside a verified opening before authoring a **Bearing (Rotation Only)**, **Slider**, or **Cylindrical** relationship. Under the hood, native Roblox constraints enforce the allowed degrees of freedom. The arbitrary **Alt+J** AxisHinge / AxisBall / AxisUniversal / PoweredHinge editor and server creation paths are retired. Players must construct the geometry rather than connecting two unrelated solids with a hidden physics constraint. Existing plot saves load the physical bodies and supported joints; unsupported retired arbitrary-axis joints are skipped with an explicit warning.

An optional **Shaft Motor** is configured on an authored *Bearing*, never on two floating parts. Equip **Simulate**, inspect a physical bearing in the Properties panel, enable Shaft Motor, choose a hold key, signed angular velocity (rad/s), torque and acceleration, then save. The Simulate client sends only held-key liveness and the server owns the saved motor settings. Motors stop on release/pause or after 0.45 seconds of missing input. Motor torque can now act on welded compound shafts and pass through the transmission solver in either direction.

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
- A single-crank assembly may be driven by holding LMB on a simulated mechanism part (even when its small handle is obscured). Multiple cranks still require a direct hit. Held-input heartbeats and release use `OPENWORKS_CrankControl` and are validated server-side. The crank uses a native capped `AngularVelocity` actuator on the physical shaft, whether the shaft has gears or not. Shaft/gear motion is handled by Roblox physics and the torque-coupled meshing solver; no gear object is scripted with `PivotTo`. Releasing LMB, pausing, stopping, leaving range, or losing input heartbeats disables drive input.
- Every client controller should own and disconnect its signals, visual folders and render bindings on `:Destroy()`.
- Do not change tool action names or IDs, template IDs, saved schema fields or relationship kinds without a deliberate migration.
- Retire dead UI paths instead of leaving unreachable branches; keep current rules in this document and old experiments in the archive.

## Known limitations

- **Not Roblox Studio verified in this pass.** Static audits cannot guarantee every connection, CSG collision, animation, camera lock, highlight, physics constraint or DataStore operation.
- The physical transmission supports external spur gears and matching equal-tooth 45°/90° bevel pairs on welded shafts. Reciprocal signed tooth-count ratios approximate torque transfer, including multiple outputs and backdriving under competing motors or external loads. This is a torque-based coupling approximation rather than full tooth-contact simulation; real-world friction, backlash, wear, tooth compliance, and high-load stability require Studio stress testing. Racks, pinions engaging racks, rack guides and the dedicated rack controller are removed. Ordinary slider/cylindrical/bearing constraints remain to enable user-designed linear mechanisms.
- Physics constraints can become unstable at small scale/high mass ratios; verify springs, multi-point joints, bolts and hand crank using the regression checklist.
- The large `ConstructionController`, `MechanicalService`, and `SimulationService` are still monolithic and should be split by responsibility in controlled future changes with tests. Rewriting them all without runtime verification risks losing current working behavior.
- Historical phase documents and the archived README contain superseded controls/decisions. Follow the present README and this document.


### Compact drilled block
`CompactHoleLibrary.Ensure()` runs a single GeometryService subtraction at server startup to provision the optional `DrilledBlock_1U_D098` template, and never during construction, snapping or simulation. It produces a 1 U cube with a true Y-axis 0.98 U circular bore and explicit `HoleDiameterU` metadata consumed by the shared BoreClearance math. It is separate from all existing authored drilled blocks. If CSG fails, no misleading solid-block substitute is installed. Its 0.01 U walls are exceptionally thin and require in-Studio verification; this is a deliberate compact-sized exception to the generally prebaked template policy.

### 90-degree bevel gears
`GearLibrary` provides matching `Bevel90_12T` and `Bevel90_20T` gear templates with 45° pitch-cone half angles, allowing shafts to intersect at a right angle. The same verified axle/apex/pitch predicate is shared between smart snapping and physical torque-mesh detection; mixed 45°/90° pairs are not accepted. Equal teeth give 1:1 speed transfer. The bevel solids have physical through-bores and weld to shafts when fitted.

### Key-bound motor on physical bearing
The retired PoweredHinge shortcut does not remove power: an existing, physically fitted shaft/bore Rotation Only relationship can be configured with **Simulate > Properties > Bearing > HOLD-KEY MOTOR**. The native hinge uses configured angular velocity, max torque and acceleration. Shaft motors and cranks can drive or resist gear trains through the physical torque coupler, rather than directly commanding gear CFrames. Validation in Studio is still required, particularly for multi-shaft high-load and backdriving behavior.

### Paint, surface finishes, and physical materials
Paint is independent of engineering material. **M** in Edit opens Paint Studio with a Paint & Finish tab and a Physical Material tab. You can color an owned primitive or a selected component using 18 quick swatches or any `#RRGGBB` hex, select Original, Matte, Satin, High Gloss, Metallic, Chrome, Brushed Metal or Pearlescent and apply/reset the finish. Server authorization, component targeting, history, duplication, and manual save/load use model-level `PaintFinish` and `PaintColorHex` attributes. `MaterialCatalog` sets density, grip, restitution and native physical properties; `PaintCatalog` touches only visual material, color, and reflectance so chrome bodywork does not magically change suspension density or tire traction. The Roblox standard BasePart material/reflectance approximation is NOT physically based real-world automotive clearcoat, anisotropic brushed metal or environmental mirror reflection; true mirror/PBR coatings would require supported textures/shader assets and a separate renderer workflow. Whole-primitive/component painting is in scope, per-face painting/decal livery is not in this first release.

When Roblox reports a DataStore error, the backend may already have written that attempted revision. `PlotPersistence.UncertainWriteIds` tracks only this server's failed request IDs and allows a subsequent `UpdateAsync` to adopt its own previously committed write, while still rejecting any unrelated concurrent session's newer revision. This prevents a transient unknown-outcome error from permanently locking an otherwise safe autosave lineage.

### Through-shaft multi-opening hinges and accurate bore targeting
A shaft no longer needs its midpoint inside the housing for **Rotation Only**. The shared `AlignmentMath.InsertionBounds` validates positive physical overlap of the complete shaft segment and each coaxial bore, so a single long pin can pass through **two or more independently placed drilled blocks/tubes**. `MultiFitMath.StationarySet` merges the clicked target's rigid/editor scope with separately built, owned bore models that are geometrically engaged by that shaft (without automatically adding unrelated gear hubs). `MultiFit.Unique` keeps normal maximum 1:1 matching for multi-shaft patterns, then adds verified additional bore contacts along the same shaft. Every accepted contact becomes an explicit shaft-hole relationship during a single atomic SmartMate operation, is persisted, and is collision-exempted only after actual geometry clearance checks. Client Build/Edit preview and manual **Edit > L > Align** call the same multi-contact validators, including ray-to-bore-center picking through genuinely empty CSG holes. A pin with several different moving bodies may create multiple native bearings; for long separated hinge pins choose **Rotation Only**. Slider/Cylindrical constraints still use the stricter housing-center tube-face travel bounds and reject center-outside placements. Resizing/posing a shaft rechecks the other openings; coupled gear hubs still require the explicit Hub choice. These are source-level changes requiring a real Studio physical joint/plot test.

### Unified bevel-gear geometry (v3)
The earlier `Bevel45_12T/20T` and `Bevel90_12T/20T` templates consisted of **three planar rim layers plus two separate tooth layers**, which looked like stacked spur gears. `GearLibrary.bevelTemplate` now creates slanted radial conical-body ribs and one continuous inclined tooth per pitch position, with a shared `tan(BevelConeDeg)` slope. At *server startup only*, `GeometryService:UnionAsync` combines those connected shapes into **one visible/collidable CSG part**; `SubtractAsync` opens the shaft bore along local X. `SplitApart=false` and output checks require exactly one final solid; a generation failure warns rather than substituting a fake filled or multi-part gear. The invisible non-colliding `GearPivotOnly` part is retained as a transform anchor, not visible bodywork. The resulting model has `GeometryVersion=3` and `UnifiedBevelSolid=true`; older templates replace atomically only after a successful CSG build. Tooth positions approximate straight bevel geometry; the kinematic GearMath/GearKinematics solver still provides meshing, not contact-based involute tooth forces. New CSG on server startup has a cost; none is performed per drag or placement. This upgrade needs Roblox Studio inspection for meshing, shade quality, hole clearance, convex collision fidelity and startup CSG reliability.

### Smoothed permanent construction freecam
`CameraController` keeps the original scriptable, always-look locked-center movement system and adds four lightweight inverse-second exponential response rates: acceleration 15, braking 27, yaw/pitch look 26, and FOV 17. Raw mouse deltas integrate into separate target yaw/pitch; shortest-angle interpolation prevents 360° discontinuities. A separately smoothed camera velocity follows normalized WASD + Space/Ctrl movement at the existing 22/44 stud/s speeds, with stronger deceleration and a hard zero at near-rest. When the camera touches a plot bound, the clipped velocity component resets rather than accumulating at the wall. Opening cursor UI, properties, crank controls or menus zeros camera velocity and discards pending look lag immediately, and plot reassignment resets both actual/target orientation without a spawn spring. Frame step is capped at 0.06 seconds to avoid extreme jumps after stalls. FOV still changes with Z / Shift+Z, now interpolating towards the target. No new hotkeys, RMB requirements or server remotes.

### Unified authoring motion profile (all tools)
`WorldMotion.lua` owns **one** authoring-only visual profile: a 30/s exponential placement response shared by unified Build preview, manual L alignment and mechanical relationship previews; 34/s for size, center and neon grips; 0.2-second fast-out exact quarter turns; and 0.14-second fast-out nudge presentations for primitives, components and saved assemblies. Previews are rendered each frame while expensive snap collision scans remain bounded to 30 Hz. The resize gizmo keeps exact `CFrame` and `Size` for drag mathematics and the server, and separate `VisualCF`/`VisualSize` for rendering. On a successful Edit move/SmartDrop, a temporary cloned ghost bridges the last few pixels to the server-authored pose in ~0.10 sec; it cannot collide or be queried. Rejected requests discard the visual transition, and overlapping animations cancel/restore original part visibility. Large models (over 260 BaseParts or 48 models) bypass extra cloning, while movement jumps over 12 studs snap immediately to avoid obnoxious long-distance trailing. **No real geometry, physical constraints, server save states or simulation dynamics are interpolated.** Actual committed dimensions, snapped rotation and positions remain precise. The system shares the existing camera responsiveness philosophy, but exposes only visual presentation and does not add new input latency or remote calls.

Shaft **Fit mode** depth/roll adjustments now also use the shared visual presentation: `WorldMotion.AnimateShaftPose` computes the identical housing-axis displacement and roll as server `MechanicalService:PoseShaft`, animating the full explicitly moving shaft component with the 0.14-second nudge duration. Both the manual Edit > L fitter and the mechanical relationship editor call this helper. It is always canceled if the server rejects the mechanical stop, collision or insertion validity.

### Shaft-position-aware reverse fitting
For **moving hole / fixed shaft** snapping, the local center aim ray is projected analytically onto the finite physical shaft segment using the closest-points solution. The selected point is clamped to the shaft's actual two end faces, so dragging a drilled hole towards one end places its center near that end rather than at the shaft midpoint. An exactly axial look resolves to the visible near end; an off-target ray cannot override normal proximity snapping. The resulting insertion remains on the existing 0.5U depth lattice and inside `Alignment.InsertionBounds`, and the server rechecks exact shaft/hole clearance, other multi-fit contacts and all real collision geometry before committing. The same rule now applies to **gear-on-shaft hubs**. A deliberate crosshair hit takes priority over a previously preferred nearby shaft; ordinary shaft-into-hole fitting is unchanged. This changes the client placement intent only, not authoritative saved geometry, motor or physics behavior.
