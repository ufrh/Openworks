# OPENWORKS

An open-ended Roblox engineering and manufacturing sandbox.

## Status

Foundation reset for FORM's parametric CSG construction system. The former physical workbench, saw/file, stock, blueprint, and legacy FORM prototypes are preserved on `archive/pre-foundation-reset-2026-11-03` and removed from active `dev`.

This is a **clean scaffold**, not a working geometry editor. FORGE integration, FORM CSG implementation, construction interactions, and debug controls are separate upcoming tasks.

## Development

- `default.project.json` is the Rojo project, using port 34872 and the configured Roblox place.
- `src/shared` maps to `ReplicatedStorage/Openworks`.
- `src/server` maps to `ServerScriptService/Openworks`.
- `src/client` maps to `StarterPlayer/StarterPlayerScripts/Openworks`.
- `scripts/` and the root BAT launchers retain the existing workflow.
- Open the place in Studio, run `START_OPENWORKS.bat`, and connect Rojo.

## FORM direction

- Parametric, non-destructive, CSG-backed solid primitives.
- Default position/resize snapping: 0.05 studs; minimum primitive dimension: 0.05 studs.
- Default rotation snapping: 15 degrees.
- Many primitives may form one editable manufactured component.
- Client construction is local; shipping uses validated definitions for server compilation.
- Temporary debugging controls first; finished Duotone UI later.

This README describes intended architecture, not implemented behavior.
