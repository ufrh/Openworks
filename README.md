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

## Confirming the Studio build

When you press **Play**, a small bottom-right badge reads `OPENWORKS / STUDIO DEV`
with the running client `BUILD`, loaded `GIZMO` module revision, and
`READY` or `BOOT ERROR` startup state. This badge is created **before**
loading the editor, so it remains visible if FORM's require/startup fails.
The same version is printed in Studio Output.

Current version marker: **BUILD 2026.11.06.02**, **GIZMO-CLEAN-TIPS.6**. The three rotation rings share one radius; Move uses `ReplicatedStorage.Cone` without square tip outlines, the selected workpiece's SelectionBox stroke is thin, and hovering planar manufactured faces (without an active tool) displays read-only millimeter dimensions.

If the badge is missing, the latest `src/client/init.client.lua` has not
run in that Play session. Stop Play and verify your local `dev` branch is
updated and the Rojo Studio plugin is connected to `localhost:34872`.
If the badge appears but the gizmo revision says `UNSTAMPED` or
`GIZMO NOT SYNCED`, the client entry script updated but the gizmo module
did not. If it displays `BOOT ERROR`, read the matching `[OPENWORKS]`
warning in the Studio Output window.

The dev launcher runs `git fetch`, but its automatic pull deliberately
**skips when there are uncommitted local changes, local commits ahead of
origin, or a non-fast-forward state**. Check the launcher/live-sync output
and `git status` rather than assuming a successful fetch updated the
working tree. Preserve local changes before merging or discarding anything.
`ModuleScript` requires are cached during Play: even after Rojo has synced,
**Stop and Play again** to get a new instance of the updated editor.
