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

The solid-modeling kernel FORM is **planned**, not implemented. Experimental code remains outside production source until reviewed.

## First milestone

Design and test procedural solid representations, planar slicing, topology validation and an EditableMesh adapter. No gameplay systems are implemented yet.
