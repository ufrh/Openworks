# OPENWORKS

An open-ended Roblox engineering and manufacturing sandbox.

**Source of truth:** `src/`. One Roblox place, one Rojo project. Do not hand-edit Rojo-owned scripts in Studio.

## Workflow

1. Clone `https://github.com/ufrh/Openworks.git` on Windows.
2. Install Git and Rojo and its Studio plugin (Foreman is supported).
3. Open your Openworks place in Roblox Studio.
4. Run `START_OPENWORKS.bat`, select your branch, and connect the Studio Rojo plugin to `localhost:34872`.
5. Run `STOP_OPENWORKS.bat` when finished.
6. Run `PUSH_OPENWORKS.bat` to commit and push changes.

START supports current branch, switching branches, and a **destructive** opt-in reset to `origin/dev`. The live sync only fast-forward pulls a clean local branch; it never auto-commits or overwrites edits.

## Layout

- `src/shared` -> ReplicatedStorage/Openworks
- `src/server` -> ServerScriptService/Openworks
- `src/client` -> StarterPlayerScripts/Openworks
- `scripts` -> project startup, shutdown, Git live sync and pushing
- `docs` -> architecture, decisions and milestones

## Current prototype

**FORM** is an implemented experimental machining kernel with validated convex cutting, subtractive drilling, pockets, slots, saw cuts, chamfers, faceted fillets, signed-volume checks, and unified watertight boundary reconstruction for supported cutters.

**Workshop phase** adds a playable parameter editor, stock setup, editable/reorderable operation timeline, tool-path overlays, project JSON import/export and optional per-player server save/load. Start Play after connecting Rojo; the new editor replaces the old preset-only demonstration.

- [Machining workshop guide](docs/WORKSHOP.md)
- [FORM kernel specification](docs/FORM/SPEC.md)
- [Geometry history and diagnostics](docs/FORM/README.md)

The geometry and manufacturing systems are **prototypes**. Studio runtime tests are necessary; source commits do not imply that a new feature has passed live verification. This is not a production CAD or CNC control system.
