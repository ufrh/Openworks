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
│   └── init.server.lua        # FORGE.Start server
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

Existing FORM manufacturing remains accessible through
`Modes/Edit/LegacyFabricationAdapter.lua` until the full fabrication
migration in Q2. Its legacy debug UI has not yet been replaced with a
finished Duotone/FORGE.UI application.

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
Q2 covers manufacturing completion and server-authoritative documents.
Q3 covers physical assembly/relationships. Q4 covers integrated physics,
actuation, diagnostics and persistence.

Architecture decisions: [Q1 FORGE Architecture](docs/Q1_FORGE_ARCHITECTURE.md).

For the sealed-room and sketch visual checks, run `scripts/VERIFY_EDIT_CHAMBER.lua` and `scripts/VERIFY_SKETCH_GRID_ALIGNMENT.lua` in the Studio client Command Bar. The latter confirms small vertices and sketch strokes lie directly on the construction grid.
