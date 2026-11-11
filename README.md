# OPENWORKS

A Roblox mechanical construction and engineering sandbox. The active `dev` branch is currently on **Phase 18: physically coupled hand cranks, mouse-controlled torque, and passive joints**. Earlier milestones included Phase 05 mechanical relationship authoring: first-person native Roblox Tools, primitive catalog, drag resizing, placement/editing, undo/redo, multi-selection, editable rigid component groups, dark gray Metal primitives, layered depth selection, X-ray/isolation, and guided coaxial alignment (L in Edit), first-person Assemble tool authoring Bearing/Slider/Fixed constraints, and fixed 0.5-U sizing and movement increments. The pre-redesign editor is preserved in an archive branch.

## Direction

**GearBlocks is the main experience and interaction reference** for placing, snapping, aligning, connecting, and operating mechanical parts. OPENWORKS should expand that concept without making the editor harder to use.

Current guiding decisions (details will be finalized in the new design document):
- GearBlocks-like scale; no microscopic voxel resolution for its own sake.
- Modular building with adjustable sizing increments, but no mandatory position-grid validation; curved shapes and prefabs such as gears and shafts.
- Custom rigid parts built from modular/voxel material, then optimized into finished components.
- No reliance on destructive CSG modeling or arbitrarily scaling finished components.
- Functional mechanical relationships and intuitive assembly, with room to expand transmissions, flexible elements, and electronics.
- Design and document the experience before implementing the new game systems.

## Framework preserved

- `src/forge-shared/` — original FORGE/Reforge 4.4.1 shared Kernel, API, Engine, UI.
- `src/forge-server/` — FORGE server networking.
- `default.project.json` — existing Rojo mappings, place ID, and port 34872.
- Local scripts and Roblox toolchain configuration.

Game-specific code lives in `src/client/`, `src/server/`, and `src/shared/Construction/`. The primitive library comes from the Studio generator and must be saved in the place. Phase 05 usability fixes need a Studio playtest; see `docs/PHASE_05_USABILITY_TEST.md`. Components are logical rigid groups in anchored construction mode; mechanical relationships are stored as real server-owned Roblox Hinge/Prismatic/Weld constraints, but construction stays anchored until shipping/simulation in a later phase.

## Run

On the `dev` branch run `START_OPENWORKS.bat`, connect the Rojo plugin to `localhost:34872`, and press Play. Client and server should log the framework version. Construction and layered editing are wired, but gameplay behavior must be verified with the in-Studio smoke test.

If you already have OPENWORKS open in Studio, restart the play session and clear any stale game-specific instances that may survive Rojo synchronization; the existing project uses `$ignoreUnknownInstances`.

## Archive

The full pre-redesign implementation (FORM, editor, assemblies, simulation, verification scripts, docs) is preserved in:

`archive/pre-gearblocks-redesign-2026-11-08`

Previous archive `archive/pre-foundation-reset-2026-11-03` and the `main` branch remain untouched.

See `docs/REBUILD_NOTES.md` for the reset boundary and next design step.


## Current usability changes
- Alignment uses the actual hole/shaft world-space axis and offset without a grid-based position rejection. 0.5-U insertion nudges are the interface default.
- Moving a component onto a surface calculates the whole assembly's lowest geometry point, rather than burying its outer pieces below the floor.
- Placement and shaft insertion previews are blue when collision-free and red for intersections. Red previews cannot be finalized; the server remains the final authority.
- Resizing defaults to 0.5 U, with [ / ] selecting 0.25, 0.5, 1, or 2 U.
- A contextual shortcuts list appears on the right for the equipped Tool and current operation.
- Edit supports Delete for pieces/components; Assemble supports Delete for an authored relationship on the aimed part.


## Cohesion and interaction pass — 2026.11.09.PHASE05.PHYSICAL-CONTEXT
- In Edit, a click selects; **hold and move/look to drag** a selected primitive/component. Release positions it through the same temporary G-move workflow. **G** remains a separate placement mode.
- Physical scale controls use six smooth colored sphere grips, with no Neon bloom. There are no move-arrow or rotation-ring controls.
- Whole components use one continuously updated selection bounds outline, not a separate Highlight outline per member.
- The right controls panel lists only relevant keybinds for the active Tool's current substate (catalog, normal edit, scale, alignment, move, assemble selection/placement).
- Live red/blue feedback describes the actual interfering model. Selecting a hollow bore permits the intended *cylindrical shaft* to overlap its collision representation ONLY after a metadata-derived radial clearance test. The rest of the moving assembly still undergoes full collision tests.
- Exact bore metadata is read from Studio Generator v4 (`HoleDiameterU`, `InnerDiameterU`, `InnerWidthU`, `InnerHeightU`, `WallU`), including tube cross-section resizing.
- World position is not subject to a mandatory grid test. Size increments stay quantized; surface support and range/collision/ownership rules remain authoritative.
- Rotation rings are removed: dragging never rotates geometry. Existing R/T/Y discrete rotation shortcuts remain unchanged.


## Move-only drag and half-Unit cleanup
- **Single click selects** the same way as before. It never starts a move. A second deliberate hold-and-drag on the already selected primitive/component begins a temporary move and releases to place; the `G` move shortcut remains available.
- **No rotation-on-drag**. No rotation rings or ring capture; R/T/Y are still the only rotation inputs.
- **Fixed 0.5 U** increments for new size changes, drag-move displacement, insertion-depth nudges, and ordinary placement snapping. No [ / ] step-size adjustment. Older geometry with 0.25-U dimensions remains readable/valid; the server does not reject world positions for missing a grid.
- Scale grips are **colored smooth non-blooming spheres**. Their SmoothPlastic material and fill-only Highlights mimic vivid neon hues without Neon-material bloom; no cube borders.
- Component/single-part selection highlighting is preserved.


## Direct drag only (2026-11-10)
- Removed the move-arrow gizmo and all its input bindings. Edit selection continues to work with one click; holding and moving a previously selected object or component starts the existing temporary move, with surface-aware placement and red/blue collision feedback.
- The G move shortcut remains available, but no physical axis-move handles are displayed. R/T/Y rotation and V spherical scaling are unchanged.


## Phase 06 — Simulation / physics compilation (2026.11.10.PHASE06.SIMULATION)

- Equip **Assemble (3)**, aim at the **housing / body to hold stationary**, press **P** to simulate the connected mechanism. The server traverses all Bearing, Slider and Fixed relationships plus their rigid component memberships; only the chosen connected graph is compiled, not your entire workshop.
- The selected body is grounded (anchored) for this prototype. Other bodies use native Roblox rigid-body physics. Rigid component members are welded together in a dedicated simulated copy; HingeConstraint, PrismaticConstraint and WeldConstraint relationships are reconstructed on those physical copies.
- The original authored construction stays anchored and intact. It is temporarily hidden and made noncollidable during simulation. The simulation copies occupy `Workspace.OPENWORKS_Simulated`.
- Press **M** during simulation to start/stop simple hinge and linear motors. Press **P** again to discard the running simulation and restore the EXACT original editable construction. Motors start off by default.
- Server owns simulation physics where supported. During simulation, edits and relationship changes are rejected; other players cannot simulate your work. The graph is bounded to 128 primitive models and 64 joints. Leaving the server or respawning clears simulation safely.
- This phase adds a **reversible physics simulation / compile preview**, not persistent shipping, sophisticated mechanical drives, electronics, mass calibration, or player-saved builds. Motion and stability must be tested in Roblox Studio, particularly CSG collision fidelity.


## Phase 07 — Shaft Fit & Physics Drive (2026.11.10.PHASE07.FIT-DRIVE)
- In Edit, choose a full Cylinder, press L, select a tube or drilled opening, align and confirm. The editor now enters a **Fit** stage. Scroll or [ / ] to change the aligned shaft's **diameter** in **0.05 U** steps. Click/Esc finishes. The axial offset and component position are not changed.
- In Assemble, create a Bearing or Slider; after confirmation, the same Fit stage opens. Scroll for 0.05-U diameter adjustments. A Fixed connection does not create a shaft-fitting stage.
- Diameter changes are server-authorized ONLY for owned full Cylinder shafts with a valid recorded Align association or a Bearing/Slider relationship to that opening. The bore metadata determines maximum allowed diameter at the shaft's actual radial offset. Invalid/oversized steps are rejected; every accepted adjustment supports undo/redo.
- Normal **V scaling on full Cylinders uses 0.25 U**, while ordinary blocks/tubes retain **0.5 U**. Fine-fit Y/Z diameters persist across subsequent scaling, history and future alignment.
- Mechanical attachment frames now inherit the housing's LOCAL bore orientation (including DrilledBlock local Y) rather than an arbitrary world-up roll basis, preventing rotation-dependent attachment-frame flips.
- Physics mode: in Assemble, aim at the chosen support and press P for grounded simulation; **Shift+P** starts an entirely ungrounded/free simulation (can fall under gravity). During simulation press **M** for motor on/off, **N** to reverse, **[ / ]** to change speed from 0.5x–4x by 0.5x, and **P** to stop and restore editing. Motor settings are session-only and reset when a new simulation starts.
- This phase does not add persistent shipping or electrical wiring; native-physics runtime stability still needs Roblox Studio testing.


## Phase 08 — Mechanical World (2026.11.10.PHASE08.MECHANICAL-WORLD)

### Mechanical authoring
- **Persistent grounding**: Equip Assemble (3), aim at any primitive/member of a rigid component, press **G** to toggle its entire body's Grounded assignment. Multiple grounded bodies are honored in physical simulation. With no explicit grounded parts, the aimed body remains the default support; **Shift+P** deliberately overrides both to simulate ungrounded.
- **World-space R/T/Y**: in Edit, rotations occur around the chosen world's Y/X/Z axes; grouped components rotate as one rigid body about their *complete geometric bounds center*, not their central primitive's arbitrary local axes. Rotation previews animate smoothly; server geometry remains exact.
- **Real-time shaft pose controls**: while inserting a cylindrical shaft in Edit L or Assemble, use **wheel** to change axial depth and **Q/E** (or **Shift+wheel**) to roll the shaft about the opening axis. The preview visually eases to its precise checked target. After confirming an alignment/Bearing/Slider/Cylindrical relationship, **wheel** fine-fits diameter by 0.05 U, **Alt+wheel** adjusts insertion depth, **Q/E** adjusts roll, and **click/Esc** ends fitting. Server validates full rigid component clearance.
- **Additional physical joint**: Cylindrical allows both sliding and rotation, distinct from Bearing/Slider/Fixed. Existing joint configuration is entered by aiming at a connected part and pressing **J**. **U** toggles travel limits and **[ / ]** adjusts their symmetrical range.
- **Dedicated gear transmission**: runtime generates a separate `Transmission` category containing **12T / 20T / 32T** tooth gears with open center bores, native metal segments and tooth-count/pitch metadata. In Assemble, press **K**, choose first and second gear to create a Gear Mesh relationship. Same tooth module, parallel axes, separate rigid bodies and pitch-center spacing are required. A gear pair's negative tooth ratio is applied to compatible bearing drive motors in simulated connected bodies. This is a *prototype* drive coupling: no electric controls, no gearbox config UI, and no claim of a native automatic angular GearConstraint.
- **Physics controls**: P simulate/stop, Shift+P force ungrounded, M motor toggle, N reverse, [ / ] speed, O pause/resume, U restart at authored pose, I report connected joint telemetry. Original construction remains preserved; all physical simulation clones are temporary.

### Physical look / feel
- Geometry uses consistent satin steel reflectance with local-only subtle grade. Clear blue/red ghost fills have **no Highlight outlines**.
- Grounded-body marks, slender bore-axis collars and gear-pair guides are rendered as **non-colliding 3D world cues**, not extra HUD panels. They disappear during simulation to avoid falsely indicating original part positions.
- Build/move and insertion ghosts use render-step critically damped interpolation; commit/validation uses the exact target CFrame. Accepted R/T/Y rotations receive a short smooth visual animation.
- Move arrow handles remain removed. Click once selects; a deliberate second hold-and-drag initiates the existing surface-aware move. Sphere scale grips remain unchanged.

### Deliberate limits
- Phase 08 is not electrical design, custom gear generator/profile editing, servo programming, persistent shipping, or full gear-force modeling. The 3D gear representation is faceted tooth geometry with ratio-aware motor coupling, subject to Roblox physics stability.
- Grounded flags and joint settings participate in local edit/undo history; engine playtesting is required before judging collisions, physics stability, and aesthetics.


## Placement overhaul — Drag-first mechanical authoring (2026.11.10.PHASE08.DRAG-MATE)

OPENWORKS uses GearBlocks as the primary interaction reference, adapted to first-person Roblox construction: you **place by physical proximity**, not by picking two separate endpoints in a manual wizard.

- **Build:** Select a primitive. Aim near another compatible construction. The ghost snaps to the hole axis, gear pitch-circle spacing, or a mating solid face. One ordinary click creates the new part AND its joint as a single history operation. Ground/floor placement still works normally.
- **Edit:** Click once to select a primitive or whole component. A deliberate hold-and-drag moves it, looking and walking updates the preview; the snapped target is recognized automatically. Release commits the rigid-body transform and its relationship in ONE server-authoritative action and undo entry.
- **Shaft to hole:** Full cylinders recognize circular/square/rectangular tubes and drilled blocks, even when aiming through a hollow opening at a surface behind it. The whole moving component is oriented to the hole's local axis; axial depth is quantized to 0.5 U, Q/E rolls the shaft in 5° steps, and mouse wheel nudges depth. Default relationship is Bearing; while snapped, press C to cycle Bearing, Slider, or Cylindrical (no two-endpoint wizard). Manual Assemble remains a fallback.
- **Gear to gear:** 12T/20T/32T Transmission gears recognize compatible mesh partners without K's two clicks. The moving gear snaps to the pitch-circle center distance and tooth-to-gap phase. Automatic Gear relationships preserve the separate physics gear-ratio system.
- **Gear to shaft:** Bring a gear's open center over a compatible Cylinder shaft (or insert a shaft through a gear); the gear and shaft snap coaxially and form a rigid **Fixed hub** relationship, not an incorrect bearing. Scroll to adjust insertion depth. The server checks bore clearance and axis alignment before committing.
- **Other faces:** Placing an ordinary solid flush against another owned solid automatically proposes a Fixed connection. The server checks actual face proximity; contact cannot be forged from a distant location.
- **Layering:** The recognizer scans compatible owned geometry under/near the aim ray, not only the first opaque ray hit. Tab cycles overlapping compatible snap targets. Alt+click selects the next occluded primitive behind the one under the crosshair. Holding Alt while moving bypasses snapping.
- **Visuals:** A subtle, world-space blue target fill highlights the recognized part. Existing red/blue previews and smooth 3D interpolation remain; exact geometry and clearance checks always happen on the server, with rollback on failure.
- **History/security:** Auto placement/mating and whole-component attachment share an atomic Assembly undo record. The server independently verifies template and ownership, shape compatibility, bore diameter, gear module and pitch distance, collisions, player range and relationship count. Existing shaft/target pairs can be re-posed without duplicating a joint.
- **Fallbacks:** L manual alignment, K manual gear mesh, and Assemble relationship editing remain for unusual constructions, but are not required for common placement.


## Bidirectional insertion, automatic rigid grouping & direct component editing (2026.11.10.PHASE08.BIDIRECTIONAL-COMPONENTS)

- **Drag either direction:** Cylinder-to-opening **or** an entire drilled block/tube/rigid housing component toward a stationary Cylinder. OPENWORKS recognizes the compatible shaft and bore under the aim ray and aligns the moving body coaxially. Rotated and angled openings keep their own relative geometry. Wheel adjusts insertion depth and Q/E shaft-relative roll.
- **Default = rigid assembly:** Placing the shaft inside a housing now **automatically groups them as one editable rigid component**. If either side already belongs to a component, all its members are retained and the assemblies merge (target's existing group ID wins). If neither side is grouped, a new group is created automatically. Gear hubs also merge into the rigid shaft component. No manual group/ungroup operation is required. A combined component uses ONE undoable batch.
- **Moving mechanisms remain possible:** While the blue bore snap is active, press **C** to cycle **Rigid → Bearing → Slider → Cylindrical**. Choosing a moving mechanical relationship keeps the two rigid bodies separate so they can rotate or slide during simulation.
- **Aligned shaft length:** Double-click a component member to edit it; select a Cylinder already aligned to a hole and press **V**. Only the shaft's **X-axis length spheres** are visible; the diameter stays unchanged. Its bore offset metadata follows its adjusted length/center. Fine fit diameter via the dedicated ±0.05 U fitting stage still works independently.
- **Edit components without ungrouping:** In Edit, **single-click** a grouped primitive to select its entire component. **Double-click the same primitive** to select it individually inside the component (no ungrouping). Click another member while in interior editing to select it; **E** returns to whole-component selection. Alt+click continues to cycle deeper physical layers.
- **Server safety:** Geometry transform and group merge are validated on the server, including bore diameter, collision, 128-member bound, player ownership/range, and joint type. Failed alignment restores the previous pose. Undo restores membership, positioning, shaft metadata and original component identities.
- **Scope:** Only automatic rigid bore/hub mating merges groups. Existing manual Bearing/Slider/Cylindrical relationships are preserved as mechanical joints; gears still use distinct gear-to-gear meshes.


## Unified Edit / Simulate and Precise Sizing (2026.11.10.PHASE08.UNIFIED-TOOLS-PRECISION)

The native hotbar remains four slots, now **1 Build, 2 Edit, 3 Simulate, 4 Inspect**. The older Assemble tool is removed from StarterPack and existing players. Its authoring operations have migrated into Edit, not discarded:
- **Edit** selects and adjusts primitives, resizes, moves, aligns, attaches and creates mechanical connections. Existing direct drag and double-click interior selection remain. Edit: **K** starts manual gear-to-gear meshing; **J** opens joint limit editing; **H** opens the older explicit housing/shaft relationship workflow when automatic snapping is insufficient; **Shift+Delete** removes an authored relationship without deleting its physical primitive.
- **Simulate** provides physics/grounding. **Click** or **G** toggles grounding on the aimed body; **P** simulates grounded, **Shift+P** forces an ungrounded simulation. Once running, M toggles drive, N reverses, [ / ] change drive speed, O pauses/resumes, U resets and I inspects telemetry. Simulate is no longer an assembly-authoring tool.
- **Shaft fit asks explicitly**: In Build or Edit, snap a shaft into a hole and confirm the placement/release. A compact world-workshop keyboard prompt appears: **1 Rigid** (merge component bodies), **2 Bearing** (rotation), **3 Slider** (linear), **4 Cylindrical** (rotation + linear). **Esc** cancels without creating a part or modifying a component. The native hotbar is temporarily suppressed while the prompt is visible; choice buttons provide a mouse alternative.
- **Precise numeric dimensions**: In Build or Edit press **N** to open dimension fields for X/Y/Z **in U**. Type numbers with up to **two decimal places (0.01 U)**, then Enter / Apply. **V** continues to use smooth 3D spherical grips. Cylinder Y/Z diameter is always kept equal; fixed-size templates remain fixed; tube/cube shape rules are enforced. Dimensions must be 0.25–64 U and pass the server's full geometry/collision validation. Numeric precision persists on a part through later edits and history.
- **Fitted shafts**: Ordinary V scaling remains length-only. N can also enter an exact Y/Z shaft diameter inside the housing; this is accepted only when the server confirms actual available bore clearance and no collision. The separate wheel 0.05-U fitting control continues to work.
- Electrical logic and programmable drives are not included in this change.

### Validation
Use `docs/PHASE_08_UNIFIED_EDIT_PRECISION_TEST.md` before approving the changes in Roblox Studio. GitHub integration checks are not equivalent to playtesting.


## Phase 09 — Mechanical Assemblies, Guided Springs & Real Fasteners (2026.11.10.PHASE09.ASSEMBLIES-AND-SPRINGS)

OPENWORKS now distinguishes **physical components**, **registered assemblies**, and **mechanical relationships**:

- **Component:** One rigid body made of several editable primitives. Welded/bolted parts are also physically fixed, but remain separately authored geometric pieces.
- **Assembly:** A registered collection of possibly disconnected components linked by bearings, sliding joints, gears, springs, bolts, and welds. While Edit is equipped, aim at a part and press **Ctrl+G** to register its connected mechanism as an assembly; **Ctrl+Shift+G** adds another connected mechanism to that registration. Names are generated as `Assembly 1`, `Assembly 2`, etc. Assembly identity is stored on authored parts, participates in undo/redo, and is distinct from rigid `ComponentId` membership. In **Simulate** aim at ANY registered member and press **P** to compile the **whole assembly**, not merely that member's local relationship graph. Assembly safety cap: 128 primitive models / 64 authored relationships.
- **Grounding:** Edit-mode body status is now a restrained 3D underbody guide: **green = grounded**, **orange = movable**. Physical copies carry matching green/orange highlights in simulation. In Simulate, click or G toggles grounding; P starts/stops, Shift+P runs ungrounded. Grounding never mutates the original model during temporary simulation.
- **Coaxial alignment:** Forward and reverse shaft-to-hole placement now align **directly to the real local opening axis**. Previous nearest-90-degree selection could produce flips depending on approach side. Manual insertion and direct dragging share the same axis calculation.
- **Engagement bounds:** An aligned shaft must maintain a real minimum axial overlap with its housing. Scrolling insertion and relationship pose requests are clamped/rejected beyond a bound computed from the shaft and housing lengths, instead of unlimited +/-64 U movement. Shaft resizing cannot silently detach a fitted relationship. Every Slider/Cylindrical and spring piston guide gets **mandatory native physics travel stops**; user joint limits can further narrow, but cannot enlarge these physical limits.
- **Shaft-in-tube spring:** Equip Edit, press **Shift+J**, click the shaft/tube in either order, then click its partner. The server verifies it fits, shares its axis and has enough travel. Simulation compiles a real `SpringConstraint` plus a guided `PrismaticConstraint` unless an existing slider already guides that same pair. **The housing should be grounded with Simulate G** when you want a static support.
- **Plate-to-plate spring:** The same **Shift+J** flow chooses two matching plates (or identically sized flattened blocks), face-to-face with aligned centers. The spring spans their faces; no invisible welded connection is fabricated.
- **Spring adjustment:** Aim at a connected spring in Edit, press **J**, then **[ / ]** adjusts stiffness, **Shift+[ / ]** damping, and **- / =** rest length. Spring tuning is server-validated and undoable.
- **Bolt and weld remain DISTINCT:** In Edit, **B** asks for two coaxial holes and automatically selects/places the largest physical prefabricated bolt that fits the two bores and distance. Three metal templates are available in **Build > Fasteners**: `Bolt_050U`, `Bolt_100U`, `Bolt_150U` (diameter variants with matching fixed lengths and visible heads). A Bolt relationship rigidly connects the hole-bearing bodies, and the instantiated fastener is a rigid member of its first body. A bolt can be undone, removed with its link, and simulated with the assembly. **Shift+B** creates a Weld only between actually touching solid surfaces, using a native `WeldConstraint`. These are not interchangeable validation paths.
- **Preserved:** Build, Edit, Simulate, Inspect tools; auto-snapping; precise N-size entry; sphere grips; component member double-click; original non-destructive construction and reversible simulation.

Limitations: Bolt heads use native faceted metal pieces, not threaded screw geometry; springs use Roblox's native solver, not an in-house finite-element spring model. As with all phases, full Studio physics testing is required before asserting stability.


## Phase 10 — Explicit Welding, Prefab Fastening and Simulate Properties (2026.11.10.PHASE10.EXPLICIT-WELD-PROPERTIES)

- **Grouping is not welding.** `ComponentId` organizes edit-mode selection/movement, and sets the simulation inclusion scope. It no longer implies physics `WeldConstraint` links across separately authored primitives. Geometry *within a single prefab primitive* is still compiled rigidly.
- **Weld tool 5:** Click two touching owned solid primitives to author a physical welded connection. No surface touching or component creation creates automatic welds; Esc cancels. Explicit joints and fasteners remain possible between members of a grouped component.
- **Physical bolts from Build > Fasteners:** Drag an actual bolt prefab through the first compatible opening; it snaps along the bore axis, placing its head outside. If the shaft fully passes one or two validated coaxial holes, the inserted prefab fastens to all those bodies. Placement checks shaft reach, bore diameter, alignment and collisions. Edit dragging also works for initially unfastened bolts. The old B-based automatic bolt-manufacture workflow is disabled.
- **Springs:** The construction coil is bright orange; its visual radius spans nearly the largest plate-face diameter that fits, with a small edge margin. Construction coil and guide visuals hide during simulation, while the native spring force stays active.
- **Simulate Properties:** Equip Simulate for a mouse-unlocked GUI. Click a block (or its running physical copy), choose an authored relationship, and enter spring stiffness/damping/rest length or joint limit parameters. Validated edits update the running native constraint without a simulation restart. Run/Stop and Ground buttons are provided. Editing via the old J/bracket shortcuts is no longer necessary.
- **Status:** Code is committed to `dev`; Studio engine playtesting remains necessary. See `docs/PHASE_10_EXPLICIT_WELDS_BOLTS_PROPERTIES_TEST.md`.


## Phase 11 — Multi-point mechanical fitting and chosen motion (2026.11.10.PHASE11.MULTIPOINT-MOTION-FITTING)

**Drag the WHOLE grouped construction onto multiple shafts or openings.** A component preview looks for all geometrically compatible bore/shaft pairings, not just one raycast target. It uses the primary socket to determine position/orientation and compares *all* secondary guides; when appropriate it automatically solves the remaining in-plane rotation from the full hole pattern. Candidate positions matching more fitted points are preferred, and the preview reports the guide count.

**Choose the motion AFTER fitting:** the connection prompt offers **1 Rotate + Slide** (Cylindrical, default / Enter), **2 Slide Only** (Slider), **3 Rotate Only** (Bearing), or **4 Fit Only** (no invisible joint). This is offered for ordinary single-shaft fits and larger groups. Automatic bore mating no longer has a rigid or editor-group choice. Only the deliberate Weld tool (or a physical bolt) creates an actual rigid fastener. Existing Hub snap still merges editor selection groups, but those groups are *not* physical welds.

**Separate joint on every fitted pair.** For multi-point fitting, the server recomputes every rod/hole match, assigns unique partners and validates real geometry. Every validated pair gets an independent chosen Bearing/Slider/Cylindrical relationship; a 4-hole/4-rod fit creates four real joints, not one joint with cosmetic contacts. All are created and removed as one undoable action. The authored complete-component placement is centered using the entire fitted pattern. As with any parallel constraint system, physical stability still depends on how the user welds the component bodies and the native solver.

**Example:** Build a bottom plate with four physical rods welded to it, an upper editor group of four corner hole blocks explicitly welded into a plate, snap that group over all four rods, choose **Slide Only**, then add a central plate-to-plate Spring and ground the bottom. Actual welds are still required within both structures; editor grouping alone does not create physical bonds.

**Status:** Phase 13 supersedes the earlier one-master-joint behavior. Prior phase sections are retained as historical notes; they are not current specifications.


## Phase 12 — Universal springs and full-component relationship visualizers

- **Any two physically authored primitives can have a Spring relationship**, irrespective of templates, dimensions, faces, separation, orientation or hole geometry. The author chooses an endpoint in each component in Edit (Shift+J). The spring uses their complete editor-group envelope for its default endpoint and orange coil presentation; it applies the real spring force between the selected physical parts. For an actual multi-primitive rigid structure, the player must have explicitly welded or bolted its constituent pieces. Grouping in Edit only controls selection/movement and does not physically transmit loads.
- **No automatic piston spring or auto-generated guide.** A spring never creates an implicit PrismaticConstraint, even for a shaft and tube. Players independently choose Slide Only, Rotate + Slide, bearing, Fit Only, or physical contact as needed. Existing spring relations also normalize to this general free-force behavior when rebuilt.
- **Full group-to-group multi-point snapping.** The entire moving editor component is transformed. The complete stationary editor component is considered for compatible guide contacts, regardless of which physical member the camera first hits. For equal-size N-rod / N-hole patterns, all N valid pairs are required, with a clear error like `Only 3/4 holes fitted` if one is misaligned. Server independently checks all member geometry and clearance before the authored operation. Other nearby components cannot accidentally count as part of the selected stationary group.
- **Relationship visuals.** While editing, different mechanisms have distinct color-coded axis/endpoint cues and readable labels: orange spring, cyan slider, violet bearing, teal rotate+slide, green welded, gold bolts/gears. Multi-point relations show every validated bore match as a small sphere, as well as total guide count and common travel stops. During drag, the stationary group receives selection highlights; each fitted point receives a cyan marker, while unmatched moving holes/shafts are marked red. Construction-only cues and spring coils hide during simulation.
- **Current behavior:** N separately matched guides create N real native mechanical constraints, not just visual markers. All visual indicators are construction-only. Components grouped in Edit still require user-authored welds or bolts to physically behave as one rigid body.


## Phase 13 — Independent multi-hole relationships and centered group snapping

- Four rods and four aligned holes produce **four separate native Slider relationships** when Slide Only is selected, one per unique hole/rod pair. All other selected motion types work by the same rule. The geometry engine cannot substitute the first matched pair for the other three.
- Multi-fit matches the **whole moving group** against the **whole stationary group**, solves rotation from the full pattern, rejects incomplete equal-size layouts and corrects lateral positioning from all fitted centers. An exact group-pivot transform is verified on the server to avoid a corner-based positioning offset.
- These are real individually inspectable relationships (SLIDE 1/4, 2/4, 3/4, 4/4); they compile into individual physics constraints during simulation. No new automatic welding or component-merging behavior is introduced.
- Fitting is committed transactionally; failed joint creation rolls back all new joints and geometry. Undo/redo treats a four-joint fit as one action.
- The previous Phase 11 and Phase 12 test/checklist files have been removed as requested. Existing visualized 1-joint mechanisms can be re-fitted to author missing paired relationships when valid.


## Phase 14 — Owned Plots and Manual Persistence

- **One plot per player in the server**, with 124×124-stud usable ground, a visible perimeter and separated 168-stud slot spacing. Plot 1 remains at the existing workshop world origin for single-player compatibility. Other server users receive their own slots, preventing construction interference. Plot assignment is temporary and released when players leave. Saved construction coordinates are **relative to the plot origin**, so moving to a different slot on a later session doesn't displace a saved mechanism.
- **Manual save ONLY:** press **F6** to unlock the mouse and open the plot panel, then click **SAVE PLOT**. The optional **LOAD LAST MANUAL SAVE** requires a second confirmation click because it replaces unsaved work. The server also automatically LOADS the last manually saved plot on join (this is NOT an autosave). The plot panel shows last successful manual save time and datastore state. Nothing saves on leave, shutdown, simulation or a timer. Save/Load cannot run while simulating.
- **Full mechanism persistence:** saves every player-owned primitive's template, dimensions, exact rotation, position, group identity, assembly identity/name, grounding, fit metadata and all authored mechanical relationship snapshots (Bearings, Sliders, Cylindrical, Spring, Weld, Bolt, Gear, limits and multi-fit joint identities). Loads create all parts first, then reconstruct the saved relationships; failed reconstruction rolls back instead of intentionally deleting the current workshop.
- **Plot ownership:** server validates Build/Edit placement within the assigned plot and blocks construction until loading completes. Separate owned plot geometry is not saved as user-built components. Save data uses `DataStoreService` key `OPENWORKS_ManualPlots_v1/player_{UserId}`, schema version 1. Maximum 500 parts, 128 stored relationships and 3.2 MB serialized JSON.
- **Studio setup:** publish the Roblox experience and turn on **Game Settings → Security → Enable Studio Access to API Services** to exercise real DataStore saves during Studio Play. If DataStore access fails, the plot reports an error rather than silently claiming a successful save. Avoid saving in production from an old test branch. In Studio, stop Play and rejoin to confirm persistence from the last explicit SAVE.
- **Important:** the plot world/ground is a runtime visual and physical boundary, not a saved construction. The game intentionally does NOT autosave any edits after the last manual save. Loading a plot discards those unsaved edits only after the player explicitly confirms.

## Phase 15 — Multi-rod alignment repair (no test documents)

- **Both sides of a fit represent whole structures.** Stationary target expansion includes editor `ComponentId` grouping AND physical, user-authored `Weld`, `Fixed` or `Bolt` connections. A lower plate welded to four guide rods is therefore detected as one four-post rigid target even if each post has a separate editor-group ID.
- **No single-hole overwrite.** The Edit preview retains SmartPlacement's solved multi-hole orientation and center. Wheel depth/roll adjustments operate from that solution, rather than recomputing and replacing it with a one-socket pose.
- **Correct roll direction.** The solver rotates around the moving opening's aligned axis, including opposite-facing hole blocks. It prefers the full pattern with the smallest radial mismatch and does not accept a loose four-of-four match when the physical constraints need tighter alignment.
- **General patterns.** Fitting requires the lesser number of compatible shaft and hole sockets, so extra holes/rods elsewhere in a connected rigid structure do not disable the exact set that can mate. Every verified pair still authors an independent chosen native relationship.
- **Feedback and performance.** Invalid previews immediately state the exact geometry/fit error in the HUD. Welded scope resolution is cached for each snap scan, avoiding repeated full graph searches. Single shaft/hole placement continues down its existing path.
- Code has been committed but cannot be Roblox Studio-playtested from the repository connector. The user-requested test documents remain removed.


## Phase 17 — Align → Position → Choose Motion; No Actuators Yet

- **Authoring flow:** move a part or editor component near a matching shaft/hole pattern for automatic full-pattern alignment. **First click/release** locks the recognized geometry, without creating any relationship. Only THEN may the player use the wheel to move the assembly along its valid insertion axis and Q/E to rotate it about the coaxial shaft. The camera can move without disrupting the locked fit. **Second click** finalizes positioning and opens the choice for Cylindrical (Rotate + Slide), Slider (Slide Only), Bearing (Rotate Only), or Fit Only. Confirming that choice authors the passive joint(s). Esc while positioning returns to free alignment. Physical welding still requires explicit Weld/Bolt work.
- **Zoom:** camera FOV zoom uses **Z** (zoom in) and **Shift+Z** (zoom out). **Ctrl+Z stays Undo.** Mouse wheel no longer changes camera FOV and is reserved for mechanical insertion/fitting adjustments and other editor operations.
- **Fundamental engineering rule: RELATIONSHIPS ALLOW MOTION; ACTUATORS CREATE MOTION.** Bearing, Slider and Cylindrical are passive native mechanical constraints; no relationship adds its own Hinge/Prismatic/Cylindrical motor, torque, velocity or artificial power. Spring relationships remain passive stored-energy components applying their native restoring force. Welds and bolts connect bodies rigidly. Gear relations are mechanical metadata/collision relationships, not powered motors.
- **No actuators exist yet.** Remove the legacy M motor toggle, N reverse drive, bracket speed control, simulated motor session/factors, automatic gear-powered drives and corresponding server actions. Runtime native joints explicitly set `ActuatorType.None`. Future servos, linear drives, motors and other actuators must be **distinct physical authored components** with explicit control/power; never quietly reinterpret a relationship as a power source.
- **Persistence unchanged:** F6 Save Plot remains the only DataStore write. No autosave. Assembly registration (Ctrl+G / Ctrl+Shift+G) and live orange spring visualization remain available.
- **Status:** Code committed to `dev`; native Roblox Studio input and physics behavior require an in-engine check. No new test documents were created.


## Phase 18 — Hand crank as the first physical manual actuator

- **Prefab:** `HandCrank` from the Studio-generated 31-piece v5.2 bank, with `ActuatorKind=HandCrank`, `Geometry` X-axis shaft, `ActuatorOutput` and `ManualGrip` attachments. `HandCrankLibrary.Ensure()` backfills only if the Studio bank doesn't already contain it; no existing prefab or template ID is replaced. Part colors/shape still use the project's dark-metal Build treatment.
- **Explicit output coupling:** drag a new or existing hand crank near the **END of another cylindrical shaft**. The output face automatically snaps coaxially to that shaft end; click to create an **explicit physical Weld relationship**. It is not a bearing motor and grouping alone never creates it. Alternatively, in Edit press **Shift+C**, select the crank, then select the shaft to manually couple already aligned endpoints. Server enforces correct axes, matching near-contact end positions, ownership, plot bounds and duplicate prevention. End tolerance is 0.045 studs, so floating couplings are rejected. The authored Weld relationship is in undo/redo and manual plot persistence.
- **Operate (current Studio-style interaction):** equip **Simulate** and press **P** while aiming at the mechanism. Aim at the running crank and **hold LMB**. Move the **locked** mouse horizontally to apply smooth, capped manual torque to the coupled shaft. Releasing LMB removes the torque immediately. There is no H shortcut, circular cursor interface, floating text or always-open Properties GUI. A short click on the crank opens its normal part inspector instead of applying sustained power. Click any other part to open its relationships and settings.
- **Actual physical torque:** the server installs a native `Torque` constraint on the **simulated HandCrank primary shaft only**. Direction is the current output axis; locked-mouse horizontal movement is sampled around 20 times per second and converted into a smoothed speed demand. Maximum manual input speed is 4 rad/s; maximum effort is 1400 native torque units. Heavy loads and blocked mechanisms oppose motion rather than being repositioned; releasing removes applied torque, preserving residual inertia. User ownership, equipment, range, active session, numeric bounds, server throttling and 0.35s input expiry are validated.
- **Safe grounding:** when the user starts simulating a crank mechanism with no explicit ground, prefer grounding the passive bearing *housing*, never the hand-crank output itself. Explicit player grounding still takes priority. Without a housing the assembly is free rather than secretly anchoring the actuator.
- **No implicit drive:** bearings/sliders/cylindrical relationships retain `ActuatorType.None`. No prior M motor controls are reinstated. Gear mesh and ratio refinement remains the next separate phase; current gear visuals do not constitute a validated realistic gear transmission.
- **Manual save:** unchanged. F6 is the only DataStore write. This implementation is committed to `dev` but requires Roblox Studio playtesting; no new checklist/test documents were added.


## Studio-like interaction and visualization pass — 2026-11-10

This section supersedes earlier experimental rendering and simulation UI descriptions above.

- **Mechanical relationships:** WorldVisuals uses `CylinderHandleAdornment` and `SphereHandleAdornment` attached to existing geometry. No helper Part, BillboardGui, world-space labels, or underbody grounding bars are created. Bearings, sliders, cylindrical guides, rigid connections and spring endpoints use concise colored 3D gizmos. Authored joint guides hide in physics simulation; actual live `SpringConstraint` coils remain visible.
- **Grounded vs moving:** one set of model `Highlight` fills only — green for grounded and orange for dynamic, both with `OutlineTransparency=1`. Old simulation-generated outlined Highlights are removed. Color is based on actual anchored simulation bodies during Play. Adornment/Highlight maps remove destroyed objects on reload, delete, mode transitions and simulator restarts.
- **Selection:** ordinary selection and multi/component selection now use clean BLUE outlines only (`FillTransparency=1`, `OutlineTransparency=0`). The old invisible selection-bounds Part and `SelectionBox` are removed. Deleting a selected part cleans its visual automatically. Multi-fit indicators use `SphereHandleAdornment` rather than neon physics Parts.
- **Resize grips:** scale spheres are real Neon material, with a brightened hover state. Move arrow visualization remains separate.
- **Simulate:** equipping Simulate retains the fixed-center first-person cursor and minimal crosshair. NO permanently open Properties HUD or keyboard shortcut overlay. **Click a body** to open its inspector on the right; the inspector shows mechanical relationships and editable settings in a name/value grid, and unlocks the pointer *only while open*. Close with **Esc** or the Close button to return to first-person aiming. Normal Simulate click does **not** toggle grounding; **G** does. **P** starts/stops simulation, **O** pauses, **U** resets. Short-clicking a crank inspects it; **hold-click + horizontal drag** rotates it smoothly. No ring widget.
- **UI skin:** shared `StudioTheme` applies Roblox Studio-inspired charcoal-gray panels, compact labels, neutral thin strokes, sharp 2-pixel corners and blue selection/active colors. Build/catalog, numeric sizing, mating choices, mechanical editor, inspector, plot save and contextual shortcuts use the same styling. The inspector opens only on selection, docked on the right; the Simulate HUD remains hidden.
- **Saved builds:** manual F6 saving remains the ONLY DataStore write. Relationship creation, assembly registration, and the gear/bolt/crank primitive bank remain unchanged.
- **Status:** source changes committed to `dev`; full Roblox Studio interaction/physics validation is still required. No new test/checklist files.
