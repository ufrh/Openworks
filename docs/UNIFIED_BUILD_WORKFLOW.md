> **Archived design (superseded Nov 13, 2026).** Build and Edit are now separate native tools (hotbar 1 and 2). See [current workflow](EDIT_2_FITTING_CAMERA_SAVES.md).

# Unified Build workspace — 2026-11-12

**Current branch:** `dev` (UI V2 + shaft-centric integration). Build merges the former Place and Edit **user-facing subtools** into one contextual tool. This change does not alter the independent Mechanics or Assembly & Simulation native tools, server ownership checks, authored relationships or plot serialization.

## Controls

| Input | What happens |
|---|---|
| Equip **Build** | You can click authored primitives/components to select and edit immediately. There is no Edit/Place toggle. |
| **B** | Open the catalog. Selecting a primitive or blueprint starts a new placement ghost. |
| **Click** during placement | Stamp the chosen geometry (repeat for additional copies). Smart fitting still chooses compatible mechanical relationships. |
| **Enter** during placement | Stop stamping; immediately return to selected-geometry editing in Build. |
| **Esc** while catalog open | Close only the catalog, retaining prior selection or current placement. |
| **Esc** during placement | Stop stamping and return to editing. During a fit/resize/transform, Esc cancels that interaction first. |
| **Click** when not placing | Select authored geometry; second click+drag of selected object starts a transform. |
| **Right-click → Select / resize** during placement | Stop stamping and select the existing part in one action. |
| **V / N** | Resize grips / exact dimensions for a selected part or active ghost. |
| **M** | Open appearance/material properties of the selected part. |
| **G / F / Ctrl+D** | Move / duplicate selected geometry. |
| **R / T / Y** | Rotate selected geometry or the active placement ghost, whichever is in focus. |
| **C / U / E** | Group / ungroup / deep-select into a component. E is **not** a mode switch. |
| **Shift+B** | Save a selected complete grouped component to My Components. |
| **O / Shift+O** | Set/reset a selected primitive's or component's authored alignment origin. |
| **L, X, I, Tab** | Guided alignment, X-ray, isolate, select behind—while editing. |
| **Alt+arrow** | Nudge a selected primitive/component in Edit context. |

**Implementation detail:** `ConstructionController.Mode` still uses internal `"Edit"` for selecting and `"Build"` for stamping, because those pipelines have different previews, transform rules and fit validation. They are *interaction contexts*, never separate Roblox Tools or user-switchable subtools. `ToolController.ActiveId` stays the compatibility adapter `"Edit"` while Build is equipped; the construction controller dispatches click actions against its internal context. The server authenticates the equipped native Build Tool, not client mode strings.

## Studio smoke test (not yet performed)

1. Equip Build and verify only a single **CONTROLS** panel on left. Click an existing block to select; E must enter component interior instead of changing modes.
2. Press B, select a primitive, click twice to place two instances. Enter to return to selection; click and move an authored block. Repeat with Escape.
3. With placement active, press B and then Esc: the library should close and the ghost should remain. Right-click a placed block → Select / resize: it must select the placed block and clear the ghost.
4. On a selected primitive, use V and N to resize, M to change appearance, G to move, F to duplicate, and Alt+arrow nudge. Re-test the same V/N operations on an active placement ghost.
5. Create a component from two primitives (C); save it using Shift+B or right-click → Save to component library; choose it from My Components, stamp two copies, save and reload the plot.
6. Test bore/hub/bolt smart fitting from Build placement. Check size/depth limits and no accidental implicit weld except the rigid gear/pulley hub weld.
7. Switch to Mechanics Connect and Assembly & Simulation. Simulate a named assembly, stop, re-equip Build and select geometry. No stale selection boxes or duplicated GUI owners.
8. Verify uncommitted placement/resize cancel cleanly on tool switch; all remotes remain server-authorized.

## Validation notes

`python scripts/verify_source.py` tests the cross-file routing and UI contracts; `git diff --check` checks patch whitespace. No Roblox Studio game session, Luau compiler, network physics test, or DataStore test was run in this environment. Those still require the above smoke test.
