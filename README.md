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

**Free:** normal Roblox character, component creation, world-space component
projections. **Edit:** fixed 40 × 40 × 20 stud midnight-steel/cyan editing
chamber, separate from the world; the component's grid is based on the
**user-entered X/Z dimensions**, not chamber size. **Assembly:** independent
stage and camera, ready for Q3 physical assembly and constraint systems.

Only the selected workpiece is rendered in Edit; unselected solids remain retained in the document. The editor's live solid uses local Edit coordinates; when
leaving Edit, a client-local projection appears at the original world
placement. These visual copies are not yet physics-authoritative or saved.

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
- Check Output for `[OPENWORKS]` and `[FORGE]` errors.

**Studio runtime tests have not been executed by the GitHub-only coding
workflow.** Do not treat code commits as a verified playable build.
Q2 covers manufacturing completion and server-authoritative documents.
Q3 covers physical assembly/relationships. Q4 covers integrated physics,
actuation, diagnostics and persistence.

Architecture decisions: [Q1 FORGE Architecture](docs/Q1_FORGE_ARCHITECTURE.md).
