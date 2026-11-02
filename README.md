# OPENWORKS

An open-ended Roblox engineering and manufacturing sandbox.

**Source of truth:** `src/`. One Roblox place, one Rojo project. Do not hand-edit Rojo-owned scripts in Studio.

## Workflow

1. Clone `https://github.com/ufrh/Openworks.git` on Windows.
2. Install Git and Rojo and its Studio plugin (Foreman is supported).
3. Open your Openworks place in Roblox Studio.
4. Run `START_OPENWORKS.bat`, select `dev`, and connect the Studio Rojo plugin to `localhost:34872`.
5. Run `STOP_OPENWORKS.bat` when finished.
6. Run `PUSH_OPENWORKS.bat` to commit and push changes.

START supports current branch, switching branches, and a **destructive** opt-in reset to `origin/dev`. The live sync only fast-forward pulls a clean local branch; it never auto-commits or overwrites edits.

## Layout

- `src/shared` -> ReplicatedStorage/Openworks
- `src/server` -> ServerScriptService/Openworks
- `src/client` -> StarterPlayerScripts/Openworks
- `scripts` -> project startup, shutdown, Git live sync and pushing
- `docs` -> architecture, decisions and milestones

## Current status — interaction reset

The old gameplay interaction prototype has been retired from `dev`. Its stock creation UI, saw/file UI, equipped-tool/backpack code, dragging controls, fabrication tool visuals/motion, timeline editor, and WorkshopStorage remote were removed. The client bootstrap no longer creates UI, spawns stock, or starts fabrication. No replacement interaction or detection code is installed yet.

The **FORM geometry kernel** remains, as do reusable pure geometry, material, and project-operation modules (`Stock`, `SawCut`, `SawTube`, `FileShape`, `Workshop`), the optional `FORMRenderer` adapter, and headless geometry tests.

The next prototype will be built around the player's Studio-authored `Workspace.Workbench`, whose parts named `surface` will be the references for automatically generated workspace detection proxies. Physical saw and file models are rigid assemblies; there will be no Roblox Tool equip workflow. Implement detection in a separate step rather than restoring the retired UI.

Older machining/workshop documents under `docs/` describe experiments and do **not** mean those interfaces are active.

**Verification:** this change is a source reset, not a Roblox Studio runtime test.
