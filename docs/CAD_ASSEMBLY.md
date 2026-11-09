# Mechanical workbench

Active development: mechanical workbench, retained pivots, X/Y guides, and external test-bench drives. Studio Play acceptance remains required.

## Ownership and modes

FORM remains the manufacturing source of truth. Assembly owns a separate versioned layout: source-frame poses, explicit bench fixtures, validated mechanical relationship requests, and quarantined legacy relationships. Placement and simulation never rewrite FORM nodes or operations.

Free retains the published world bodies and character controls. Edit operates on the selected manufacturing document. Assembly displays anchored local projections. Simulation compiles separate server-owned bodies in an isolated spatial session; Stop destroys them and restores the authored layout when Assembly opens. No temporary simulation displacement is saved into assembly poses.

Assembly validation and startup are serialized per player. Placement carries component and layout revisions; manufacturing mutations are rejected during validation or simulation. Compilation caches are keyed by component ID and revision, destroyed on deletion/disconnect, and cloned for each validation/session. Stale requests fail without changing accepted poses. Respawn invalidates in-flight placement/startup and returns the client to Free. Old joints remain quarantined and never compile automatically.

The document DataStore envelope remains version 1; the assembly payload remains version 2. Its supports array now carries the explicit model discriminator and required fixture IDs. Restore revalidates geometry and rejects duplicate mover relationships into quarantine. Fixture deletion removes dependent relationships.

## Controls

Assembly uses a shared four-page workbench. The page names and controls are:

- **Components:** component selection, fixed/free state, parametric mechanism examples, frame all, reset view, save.
- **Move:** W/E move/rotate, local/world axes, adjustable mm/degree snap, numeric position relative to the stage center, rotation, placement undo/redo, frame selected.
- **Align:** choose mover A, pick target B, select source planes/bore/shaft references, then align axes, mate faces, make parallel, or set spacing. Offsets are millimeters. Alignment positions geometry; it installs no joint.
- **Joints:** fix/release bench fixtures, select source bores, register real hardware-supported relationships, validate clearance, remove joints, and start simulation. For pivot joints, an optional geometric lookup can identify the manufactured pin and end caps; it never fabricates hardware.

References are manufacturing datums, not persistent rendered triangle IDs. A source plane can remain useful after machining removes part of that face; placement is still checked against the final solid. Concentric alignment preserves axial depth; adjust insertion with Move if the support validator requests more engagement.

Move previews immediately. On release, server clearance validation either accepts it or rolls back and highlights conflicts. Escape or losing window focus cancels an Assembly drag. Mode changes finish an active drag and wait for its validation; a pending request blocks a transition. Ctrl+Z/Y undo/redo accepted placements (up to 64); they do not undo manufacturing, fixture state, or relationship installation.

In Assembly and Simulation, RMB orbits, MMB pans, wheel zooms, F frames selection, and Home frames all. Reset view restores the stage/session focus, orbit angles, projection, and zoom. Edit retains its fixed workspace pivot. Free restores character camera/control and the previous FOV. Camera mouse state is released on focus/mode changes, and an active manipulator captures its drag.

Simulation has **Run**, **Drive**, **Test**, and **Parts** tabs. Pause freezes bodies and preserves velocities; Resume restores them. Reset restores initial positions, zeroes velocities, rebuilds released relationships, and preserves paused/running state. Stop returns to Assembly. Test applies a bounded one-shot spin or push to an ungrounded selected body along the relationship's motion axis or a chosen world axis. The Drive page independently controls bounded continuous motors, direction reversal, or position servos on an accepted joint. This is external bench equipment, not an installed manufactured motor. The spin value is nominal because inertia and collision response affect actual speed. A surface marker on cylinder ends makes rotation visible.

## Supported relationships

| Model | Required manufactured geometry | Allowed motion |
| --- | --- | --- |
| Sliding bearing (`BoreSupportV1`) | Uncut cylinder in one through-drilled convex housing | Axial slide and rotation; no retention |
| Retained bearing (`RetainedBoreV1`) | Same, with fixed housing and two separate fixed rectangular end plates covering shaft ends | Rotation and measured axial endplay |
| Linear guide (`LinearGuideV1`) | Uncut rectangular carriage surrounded on four sides by separate fixed rectangular rails | Axial slide, no rotation |
| Linear guide + stops (`LimitedGuideV1`) | Same four rails, plus two separate fixed rectangular end plates | Slide within measured stroke, no rotation |\n| Retained pin pivot (`RetainedPivotV1`) | Through-drilled links, separate cylindrical pin and two manufactured end caps | One rotational DOF, no axial release |

Bearings accept both legacy `Drill` and the UI's `DrillFace`, including side-face bores. The one active drill must be through, with a continuous surrounding wall in block or convex sketch stock. Shaft/bore diametral clearance is 1–4 mm. Unsupported additional machining, loose fits, insufficient wall, misalignment, or insufficient axial engagement fails validation.

Linear rails must be uncut rectangles aligned with the carriage axes, cover all four local X/Z sides, provide 0.5–2 mm clearance per side, and retain sufficient axial overlap. Travel may follow the moving carriage's local X or Y axis. End plates must be grounded, square to travel, cover the mover end, and enclose it without penetration. Bounds come from actual plate faces. Travel that would lose bearing/rail engagement before reaching a stop is rejected.

All movers must be free from the bench. Crank–rod–slider examples now use three separate retained-pin hinges and a physically bounded X-axis prismatic guide. Guides and conventional bearings remain limited to one relationship per mover. Retained pin pivots allow multiple independent link references on one manufactured component; each pivot needs its own pin and retainers. Compiled constraints are Cylindrical, Prismatic, or Hinge constraints, with collisions enabled. Continuous motor and servo actuation are available in the separate test bench. Cylindrical inclination is zero so rotation and translation share the axis. Constraints are removed when support engagement is lost, and Reset restores the original validated arrangement. No screws, welds, hidden retainers, or rail geometry are generated.

These are idealized bench mechanism models, not stress/contact engineering analysis. Threads, clamp preload, stress/fatigue, spherical bearings, gearing, belts, screw transmissions, and fully manufactured electrical actuator hardware remain unsupported. The bench drive is a controllable external input rather than a fabricated motor. The legacy motor endpoint explicitly rejects requests. The bench fixture is external support, not a connection between manufactured parts.

## Clearance and limits

Broad phase uses oriented bounds and 0.0001-stud linear tolerance. Block overlap uses separating axes; overlapping manufactured shapes use GeometryService intersection and material-volume measurement. Intersections over 0.00000001 cubic stud are rejected. Engine failure rejects placement rather than certifying unknown clearance. Collision-volume fallback is reported as an estimate. Roblox decomposition may disagree with rendered small holes or tight clearances; engine acceptance testing is required.

## Verification

`cd scripts/tests && npm ci && npm test` compiles all source/verification Lua with Luau WASM and runs 60 assertions covering references, placement math, DrillFace and side bores, bearing retention, rail/stops validation, compiler configuration, pause/reset, and mode rollback/cleanup with Free fallback. Vector/CFrame/Instance doubles exercise real module logic; they do not simulate Roblox physics or execute live CSG/UI/DataStores.

Studio acceptance:

1. Run `scripts/VERIFY_Q3_ASSEMBLY.lua` in the Command Bar for real Instance/compiler and clearance checks.
2. In **client Play** Command Bar, run `scripts/VERIFY_CAD_WORKFLOW.lua` in an otherwise valid workshop. It creates/cleans up its parts and tests UI-style drilling, rejected placement, explicit support, spin/push, pause/reset, repeated stop, and unchanged authored history/poses.
3. Run `scripts/VERIFY_LINEAR_WORKFLOW.lua` in the same context for manufactured carriage/rails/stops, relationship replacement, validation, simulation reset, and dependency removal. Existing conflicting workshop parts can correctly fail these tests.
4. Run `scripts/VERIFY_Q4_PERSISTENCE.lua` server-side for codec round-trips. Separately enable Studio DataStore access and verify save → stop Play → restart preserves all supported relationship types and fixtures.
5. Follow [the manual recipe](MECHANICAL_QUICKSTART.md): visually verify rotation/sliding/stops, released supports, collision behavior, mode/camera restoration, failed transitions, and respawn. Repeat to check for leaked folders, attachments, or controls.

Host compilation and 60 assertions passed. Studio Play, dynamic physics, CSG collision fidelity, UI usability, and actual DataStore reload have not been executed in this environment. This build is ready for that acceptance pass; those runtime checks are not represented as passed.


## Slider–crank acceptance target

The slider–crank diagram's mechanism is represented by a **crank pivot**,
**two connecting-rod pivots**, and a **prismatic slider guide**. The
`Slider-crank assembly` command creates 19 authored FORM parts:
four motion/structure pieces, three manufactured pins, six end caps,
four linear rails, and two travel stops. No invisible mechanical hardware
is added. The actual joint constraints are compiled only in Simulation.

Use **Simulation → Drive** to choose the crank Revolute joint, set RPM and
maximum torque, and start/reverse/stop the external motor. **Position servo**
targets an angle in degrees, or a distance in millimeters for a slider
guide. These commands don't create a motor or change the manufacturing
history. Stopping simulation restores CAD poses; Reset rebuilds constraints
at the original poses.

A Studio Play end-to-end test is in `scripts/VERIFY_SLIDER_CRANK.lua`.
It creates a persistent example and checks geometry, all four mechanical
relationships, validation, motor, Reset, and CAD-pose preservation. It must
be run in a clean stage with supported CSG permissions. Source-only
verification is not a substitute for Studio's live collision and solver
behavior; an unsupported fit fails closed rather than silently disabling
collisions.
