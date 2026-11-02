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

The old gameplay interaction prototype has been retired from `dev`. Its stock creation UI, saw/file UI, equipped-tool/backpack code, dragging controls, fabrication tool visuals/motion, timeline editor, and WorkshopStorage remote were removed. The client bootstrap no longer creates UI, spawns stock, or starts fabrication. No old tool UI, drag controls, or fabrication interactions are active. A new workbench detector is installed independently.

The **FORM geometry kernel** remains, as do reusable pure geometry, material, and project-operation modules (`Stock`, `SawCut`, `SawTube`, `FileShape`, `Workshop`), the optional `FORMRenderer` adapter, with the old automatic runtime tests removed.

Workbench detection uses the Studio-authored `Workspace.Workbench`: every descendant BasePart named `surface` generates an invisible proximity proxy at runtime. Tag tool Models (or standalone Parts) with Boolean attribute `isTool = true`. FORM-rendered parts receive `isMaterial = true` and the CollectionService tag `FORMMaterial` via `FORMMaterial.mark(instance)`. The detector publishes `OnWorkbench` on detected objects and `ToolCount` / `MaterialCount` on the workbench. FORM meshes created only on a client are not visible to the server detector; authoritative world materials must be replicated/server-created.

Older machining/workshop documents under `docs/` describe experiments and do **not** mean those interfaces are active.

**Verification:** this change is a source reset, not a Roblox Studio runtime test.
