# OPENWORKS

An open-ended Roblox mechanical engineering and manufacturing sandbox.

Active development branch: `dev`. The obsolete workbench/saw/file system is preserved at `archive/pre-foundation-reset-2026-11-03`.

## FORM prototype

FORM is a **parametric primitive editor**, not an arbitrary Union/Subtract modeling tool. Every primitive begins at 0.05 × 0.05 × 0.05 studs.

- Native **Block** and **Cylinder** update CFrame/Size directly when moved, rotated, or resized.
- Special **Tube** and **Hole Block** types are individually parameterized; CSG is used *internally* only to manufacture their void when their shape changes.
- A modified special primitive is remanufactured after a resize or bore/wall change, **not** on every translation or rotation.
- The construction workspace, 0.05-stud debug grid, and orbit target are fixed at (0,0,0).
- Smooth hybrid FOV/dolly camera: RMB/MMB orbit, wheel zoom, and ViewportFrame view/zoom controls.
- Restored six-face Roblox resize handles, move handles, and rotate arcs. Opposite faces stay anchored during per-face resize.
- One visible solid per component: no neon ghost and no extra, trailing CSG preview.
- Temporary debug UI; final Duotone interface is postponed.

See [FORM Phase 1 instructions](docs/FORM_PHASE1.md).

## Local development

Run `START_OPENWORKS.bat` with `dev`, connect the Studio Rojo plugin to localhost:34872, and press Play. Use `STOP_OPENWORKS.bat` when finished. Rojo maps src/shared, src/client, and src/server into the Roblox place.

Recent changes are source-verified but not yet Studio-runtime tested. Save/load, mechanical physics, multiplayer/shipping, and FORGE integration are not yet implemented.
