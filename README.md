# OPENWORKS

An open-ended Roblox engineering/manufacturing sandbox.

**Development:** `dev` contains a locally editable, parametric FORM construction prototype. The previous workbench, saw/file, and fabrication prototype remain preserved on the `archive/pre-foundation-reset-2026-11-03` branch.

## Current construction slice

- CSG-backed Block, Cylinder, Tube, and Hole Block components with editable Add/Subtract source nodes.
- All primitive envelopes start at **0.05 × 0.05 × 0.05 studs**.
- Fixed construction workspace/grid and camera orbit pivot at **(0,0,0)**.
- Smooth camera with **RMB/MMB orbit**, blended FOV/dolly wheel zoom and a draggable zoom control. No pan.
- Custom, camera-responsive X/Y/Z Move/Scale/Rotate manipulators instead of oversized built-in Roblox handles.
- During gizmo dragging, source nodes and a translucent preview update immediately; actual GeometryService compilation is coalesced asynchronously and finalized at release.
- Temporary debug UI; final Duotone interface has not been built.

[Phase 1 controls, instructions, limitations](docs/FORM_PHASE1.md)

## Development workflow

1. Open the configured OPENWORKS Roblox place in Studio.
2. Run `START_OPENWORKS.bat` on Windows, select the `dev` branch, and connect Rojo to `localhost:34872`.
3. Press Play to use the FORM construction harness.
4. Use `STOP_OPENWORKS.bat` when finished.

Rojo mappings: `src/shared` → ReplicatedStorage/Openworks; `src/server` → ServerScriptService/Openworks; `src/client` → StarterPlayerScripts/Openworks.

This source has been committed, but the most recent camera and gizmo changes require a real Studio playtest. No save/load, shipping, network replication, physics assembly or FORGE integration is included.
