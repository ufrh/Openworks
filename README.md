# OPENWORKS

A Roblox engineering and manufacturing sandbox.

**Current branch:** `dev` is the clean reconstruction branch. The former workbench, saw/file, and prototype machinery remain preserved on `archive/pre-foundation-reset-2026-11-03`.

## Phase 1 — FORM construction sandbox

A first client-local parametric CSG sandbox is now in the source tree. It supports creation and numeric editing of Block, Cylinder, Tube and Hole Block components; Add/Subtract nodes, a click-to-select preview, and an orbit/pan/zoom camera. The temporary debug UI is deliberately plain.

**See [Phase 1 instructions](docs/FORM_PHASE1.md)** for the Studio playtest checklist and limitations. The implementation is committed but has not been Studio-runtime validated.

## Development

1. Open the OPENWORKS place in Roblox Studio.
2. Run `START_OPENWORKS.bat` on Windows, select `dev`, and connect the Rojo Studio plugin to `localhost:34872`.
3. Press Play to load the construction sandbox.
4. Use `STOP_OPENWORKS.bat` to stop sync.

Rojo source mappings:
- `src/shared` -> `ReplicatedStorage/Openworks`
- `src/server` -> `ServerScriptService/Openworks`
- `src/client` -> `StarterPlayer/StarterPlayerScripts/Openworks`

FORGE integration, shipping/server validation, physics, persistence, and final Duotone interface are future phases.
