# OpenWorks 2.0 — Roblox Rebuild

**Clean mainline foundation** for the Roblox/Luau engineering sandbox. This tree replaces the previous placeholder. Old files are removed from `main` but remain in Git commit history—no separate archive branch, no history rewrite.

## Running it

1. Clone or pull `ufrh/Openworks` on branch `main`.
2. Run `aftman install` if you use Aftman, or install Rojo 7.5+ and its Studio plugin.
3. Run `START_OPENWORKS.bat` (or `rojo serve default.project.json --port 34872`).
4. Connect the Rojo Studio plugin to localhost port **34872**.
5. Open a clean Studio baseplate and Play. The first-person OpenWorks block controller should appear.

For Studio saves, publish your test place and enable **Game Settings → Security → Enable Studio Access to API Services**. Until enabled, block editing works in volatile mode but cannot be saved across sessions.

## Architecture

- `ReplicatedStorage/FORGE`: **FORGE 3.2.0** core/service/controller/transport subset adapted from the user's Ruckus repository (Ruckus-only matchmaking, data/profile subsystem, avatars, progression and UI omitted).
- `ReplicatedStorage/OpenWorks/Shared`: integer engineering units and a versioned `BlockDocument`.
- `ServerScriptService/Services`: registered FORGE `ConstructionService`, `GeometryService`, `PersistenceService`.
- `StarterPlayerScripts/Controllers`: registered FORGE `BuildController`.
- `ServerScriptService/FORGE`, `StarterPlayerScripts/FORGE`: thin FORGE bootstrap scripts.
- Roblox Parts and collisions are derived from source documents; clients never write authoritative source state.

**Slice 01:** A first-person block can be placed, selected, moved, uniformly resized, deleted, undone, redone, and persisted when DataStore access is available. The server validates all accepted edits; geometry is a disposable projection of data.

This is a **first vertical slice**, not the full OpenWorks feature set: modifier-based geometry, true machined holes, SmartFit, mechanical joints, complete simulation states, advanced manipulation handles, and Harmonics come later.

See [architecture](docs/ARCHITECTURE.md) and [slice test plan](docs/SLICE_01.md).

## Prototype controls

| Input | Action |
| --- | --- |
| 1 + click | Block placement at center-screen hit |
| 2 + click | Select own block |
| G + click | Move selected block |
| R / F | Grow / shrink selected block uniformly by 0.25u |
| Backspace | Delete selected block |
| Ctrl+Z / Ctrl+Y | Undo / redo |

The prototype uses a 32-block maximum per player to stay within the FORGE snapshot payload cap, and sends owner snapshots rather than optimized deltas. Incremental replication and per-feature geometry invalidation are separate next-slice tasks.

## Source hygiene

The repository now has **one** Rojo project, **one** FORGE runtime and **one** set of OpenWorks services. No old client/server scripts or obsolete architecture docs from the placeholder are carried forward.

`main` was updated with a normal parented commit; previous commits are still recoverable via Git history. No archive branch was created.
