# OPENWORKS

A Roblox mechanical construction and engineering sandbox. This repository is a **clean design-first rebuild baseline** as of November 8, 2026.

## Direction

**GearBlocks is the main experience and interaction reference** for placing, snapping, aligning, connecting, and operating mechanical parts. OPENWORKS should expand that concept without making the editor harder to use.

Current guiding decisions (details will be finalized in the new design document):
- GearBlocks-like scale; no microscopic voxel resolution for its own sake.
- Modular, grid-aligned building with curved shapes and specialized prefabs such as gears and shafts.
- Custom rigid parts built from modular/voxel material, then optimized into finished components.
- No reliance on destructive CSG modeling or arbitrarily scaling finished components.
- Functional mechanical relationships and intuitive assembly, with room to expand transmissions, flexible elements, and electronics.
- Design and document the experience before implementing the new game systems.

## Framework preserved

- `src/forge-shared/` — original FORGE/Reforge 4.4.1 shared Kernel, API, Engine, UI.
- `src/forge-server/` — FORGE server networking.
- `default.project.json` — existing Rojo mappings, place ID, and port 34872.
- Local scripts and Roblox toolchain configuration.

The game-specific `src/client/`, `src/server/`, and `src/shared/` trees have been reduced to minimal bootstrap stubs. They intentionally contain **no playable construction editor** yet.

## Run

On the `dev` branch run `START_OPENWORKS.bat`, connect the Rojo plugin to `localhost:34872`, and press Play. Client and server should log the framework version. This is a smoke test for the preserved framework, **not** a verified gameplay build.

If you already have OPENWORKS open in Studio, restart the play session and clear any stale game-specific instances that may survive Rojo synchronization; the existing project uses `$ignoreUnknownInstances`.

## Archive

The full pre-redesign implementation (FORM, editor, assemblies, simulation, verification scripts, docs) is preserved in:

`archive/pre-gearblocks-redesign-2026-11-08`

Previous archive `archive/pre-foundation-reset-2026-11-03` and the `main` branch remain untouched.

See `docs/REBUILD_NOTES.md` for the reset boundary and next design step.
