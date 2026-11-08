# OPENWORKS

Open-ended Roblox mechanical engineering and manufacturing sandbox.
Active development branch: `dev`.

## Architecture — FORGE 4.4.1

OpenWorks runs on the **actual FORGE Reforge 4.4.1** implementation
from the Ruckus repository. FORGE is the only infrastructure Kernel.
OpenWorks game-specific modes, tooling, manufacturing and assembly
systems sit **above** FORGE.

```text
src/
├── forge-shared/               # Original FORGE API, Engine and Kernel
├── shared/
│   └── FORM/                   # Mode-independent solid modeling engine
├── forge-server/
│   └── Kernel/Networking/     # Original FORGE server bridge
├── server/
│   ├── init.server.lua        # FORGE.Start server
│   └── Services/
│       └── OpenWorksDocuments.lua  # Validated document source authority
└── client/
    ├── init.client.lua        # Build badge + FORGE.Start
    ├── Controllers/
    │   └── OpenWorksController.lua
    ├── Modes/
    │   ├── FreeMode.lua
    │   ├── EditMode.lua
    │   ├── AssemblyMode.lua
    │   ├── Edit/              # Legacy fabrication adapter
    │   ├── Free/              # Character mode
    │   ├── EditWorkspace.lua
    │   ├── EditEnvironment.lua
    │   ├── AssemblyEnvironment.lua
    │   └── WorldProjection.lua
    ├── Experience/
    │   ├── Cameras/
    │   ├── Placement/
    │   ├── Visuals/
    │   └── ModeBar.lua
    ├── Systems/
    │   ├── Components/        # Rendering
    │   ├── Documents/         # FORGE revision/snapshot bridge
    │   └── Selection/         # Topology and picking
    └── Tools/
        ├── Inspection/
        ├── Sketch/
        ├── Snapping/
        ├── Transform/
        ├── Visuals/
        ├── ToolRegistry.lua
        ├── ToolController.lua
        └── ToolContext.lua
```

FORGE's registry, loader, dependency graph, lifecycle, scopes, signals,
network transport and developer diagnostics are used as-is. The sole
OpenWorks-specific FORGE compatibility tweak skips Ruckus-only data
and matchmaking server plugins when they are not installed.

## Q1 interaction modes

**Free:** normal Roblox character, fixed camera zoom, and client-local
physically simulated, draggable manufactured components. Their shapes are
rebuilt from FORM's latest accepted geometry whenever a cut finishes.
**Edit:** fixed 40 × 40 × 20 stud **fully sealed, opaque** midnight-steel/cyan box with the workspace grid at its exact vertical center (10 studs above the floor and 10 below the ceiling); the CAD camera stays inside this box and an ambient blue backdrop provides fallback coverage; the component's grid is based on
the **user-entered X/Z dimensions**, not chamber size. Press **P** (or the
PREVIEW button) to toggle a clean model-only view: all OpenWorks edit GUIs,
sketch adornments, construction grids, transform gizmos, and tool visualizers
are hidden, and unfinished sketches are paused and preserved. Press P again
to resume editing. **Assembly:** independent stage/camera, ready for Q3
physical alignment and mechanical constraints.

Only the selected workpiece is rendered in Edit; unselected solids remain retained in the document. The editor's live solid uses local Edit coordinates; when
leaving Edit, a client-local projection appears at the original world
placement. Free Mode copies are local physical bodies with collision and force-driven
dragging, but they are not yet synchronized across players or persisted on
the server. Only OpenWorks components use this drag/physics system; other
Workspace objects are unaffected.

The first component starts from a closed sketch, not a primitive block.
Workspace height defaults to **1,000 mm** and is independent from the
first sketch extrusion depth (**56 mm**).

## Q2 manufacturing — in progress

Edit Mode now includes adjustable construction snapping (1–560 mm) with
14/28/70/140 mm presets. It applies to sketch placement, face targeting,
saw cursor picks and Move handles. The component-sized construction grid
is **visible by default throughout Edit**, including after CSG cuts, unless
manually hidden or temporarily hidden by the P model-only preview.

Manufacturing source history is now validated by a **FORGE
OpenWorksDocuments server Service**. The client submits versioned
operations through `Systems/Documents/DocumentBridge.lua`, adopting
validated source snapshots. Operations reject stale revisions and can roll
back to a prior server-issued revision after a failed CSG compile.

`FORM/Features.lua` derives stable, local hole centerlines and diameters
from drill history, establishing Q3 mating-interface candidates.

The fabrication UI and native CSG compilation remain in
`Modes/Edit/LegacyFabricationAdapter.lua` while they are migrated to
dedicated Q2 tool modules. Component documents are server-authoritative
**for the current session**, but CSG visual meshes are still client-side.
Durable saving and multiplayer world-body replication are not implemented
yet. Actual Studio Play verification is required before Q2 is complete.

[Q2 technical design](docs/Q2_MANUFACTURING_ARCHITECTURE.md).

## Start locally

Run `START_OPENWORKS.bat` on `dev`, connect the Roblox Studio Rojo plugin
to `localhost:34872`, and press Play. The project includes the FORGE
source and secure server transport: no separate Ruckus Rojo session is
required.

The bottom-right build badge should report
`FORGE 4.4.1 / Free · Edit · Assembly`. The top-center Mode Bar switches
between modes. FORGE receives mode transition timing/failure metrics. Create a component in Free Mode by specifying its X/Z
workspace and placing the grid on the ground, then enter Edit.

## Studio verification

- Run `scripts/VERIFY_Q1_SERVER.lua` in the server command bar.
- Run `scripts/VERIFY_Q1_FORGE.lua` in the client command bar.
- Validate first sketch + solid with `scripts/VERIFY_SKETCH_FIRST_WORKFLOW.lua`.
- Verify existing snap/visualizer behavior with
  `scripts/VERIFY_SNAP_OVERLAYS.lua`.
- Run `scripts/VERIFY_FORM_SKETCH_REMOVAL.lua` to verify centered
  subtraction cutters and valid Boolean solids.
- In Play, confirm Free Mode wheel zoom stays fixed, drag a component,
  then enter Edit, drill/remove material, and return to Free: the geometry
  should refresh at its previous physical pose. Press P twice in Edit to
  check that all OpenWorks visualizers hide and restore cleanly.
- Check Output for `[OPENWORKS]` and `[FORGE]` errors.

**Studio runtime tests have not been executed by the GitHub-only coding
workflow.** Do not treat code commits as a verified playable build.
Q2 source-document validation is integrated. Q3 and Q4 systems are
implemented in source but still require Studio acceptance testing,
especially GeometryService CSG, joint behavior, network replication and
DataStore permissions.

Architecture decisions: [Q1 FORGE Architecture](docs/Q1_FORGE_ARCHITECTURE.md).

For the sealed-room and sketch visual checks, run `scripts/VERIFY_EDIT_CHAMBER.lua` and `scripts/VERIFY_SKETCH_GRID_ALIGNMENT.lua` in the Studio client Command Bar. The latter confirms small vertices and sketch strokes lie directly on the construction grid.

## Q2 Play checks

- `scripts/VERIFY_Q2_MANUFACTURING.lua` — snap, source coordinates and features.
- `scripts/VERIFY_Q2_FORGE_DOCUMENTS.lua` — actual server RPC, stale revisions, notes and rollback.
- `scripts/VERIFY_FORM_SKETCH_REMOVAL.lua` — centered Boolean cutter and compiled result.


## Q3 assembly implementation

Assembly Mode now supports physically draggable workpieces, force-limited
hole alignment, **explicit** Bolt/Rigid and Pin/Revolute installation,
multi-hole matching, joint removal and hinge motor controls. A match
never creates a joint on its own. The server validates actual manufactured
hole source frames before accepting installation. The relationship graph
also models prismatic/cylindrical/ball joints, whose player controls
are not yet exposed. Bolts/pins have simplified metallic visuals;
threaded physical engagement is not simulated.

[Q3 Architecture](docs/Q3_ASSEMBLY_ARCHITECTURE.md) ·
[Q3 Studio Verification](scripts/VERIFY_Q3_ASSEMBLY.lua)

## Q4 world physics and saving

The server now rebuilds published component geometry from authoritative
FORM operation history and publishes physical bodies under
`Workspace.OPENWORKS_Published`, with owner-restricted replicated
DragDetector interaction. Client Free Mode drops its local duplicate when
that server body arrives. Published bodies preserve pose/velocity when
manufacturing geometry changes; installed relationships compile into
physical constraints, and revolute motors accept bounded actuation.

Workshop source snapshots, installed joints and physical poses use
per-player DataStore persistence, a tagged geometry codec, 120-second
autosaving, manual Save Workshop, PlayerRemoving and BindToClose saving.
**Studio DataStore writes are off by default**; enable explicitly by
setting `OpenworksEnableStudioDataStore=true` on `game` before Play
and enabling Studio API access.

Run `scripts/VERIFY_Q4_PERSISTENCE.lua` on the Studio SERVER command bar
and `scripts/VERIFY_Q4_WORLD.lua` on the CLIENT command bar.
Manually verify installed hinges, rigid fasteners, physics motion,
re-compilation and reconnection.

[Q4 Physics and Persistence](docs/Q4_SIMULATION_PERSISTENCE.md)

**Not yet Studio-verified.** CSG permission/runtime availability,
collision fidelity, large-history networking, save behavior in a published
experience, and high-load physics still require real Play tests. Q3/Q4
are implementation milestones, not production certification.
