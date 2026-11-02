# OPENWORKS — Metal File / First Curved Fabrication Pass

Filing is a manual, hold-to-complete process separate from the geometry engine. The first implementation rounds **external straight edges on convex workpieces** by using a series of tangent cutting planes to approximate a quarter-circle. It does not claim to be arbitrary freehand spline carving or curved separation.

## Setup

- Visual model: `ReplicatedStorage["Metal File"]` (Model or BasePart).
- Equippable Roblox Tool: `StarterPack["Metal File"]`. Same name, different container; see the existing `src/client/ToolVisual.lua` binding used by the hacksaw.
- A small **EQUIP METAL FILE** button appears in the top-right while the file is not equipped. It looks in the player's Backpack, Character, or ReplicatedStorage for a matching Tool. A File panel appears on the right **only while Metal File is equipped**. The hacksaw panel hides while filing. The stock UI remains left-docked.

## In Play

1. Spawn a block or sheet, select it, and press **Temporarily Secure / Release** to anchor it for fabrication.
2. Equip the **Metal File** via the Roblox hotbar. Hover near an outer edge of the workpiece; FORM computes the nearest two bounding faces.
3. Select **1 mm**, **3 mm**, or **6 mm** rounding radius. The radius must fit the workpiece (e.g., use 1 mm for thin sheet). Hover anywhere on a stock face; the guide now **snaps to the nearest valid outer edge**, instead of requiring pixel-perfect edge aiming. A gold quarter-circle contour previews the resulting rounded edge at both ends.
4. **Hold LMB** to file the chosen edge. FORM now **preflights** the selected edge on click. If the roundover is invalid, the Tool immediately displays a readable error. If valid, the file reciprocates while progress increases; releasing early cancels. No geometry or displayed mesh changes until completion.
5. At completion, `FileShape.apply` clips the local solid with five tangent planes (six conceptual curve segments) and verifies its sealed volume. The workpiece is replaced **once**, keeping its StockId, material, physical placement, and secured state. If rendering fails, the prior workpiece remains.
6. Other outer edges can be rounded with additional filing passes.

## Architecture

- `src/shared/FileShape.lua`: pick the two nearest axis-aligned bounding faces, show curved preview, and clip a convex FORM solid using the existing convex splitter.
- `src/client/FileUI.lua`: Tool activation, radius presets, pooled Neon guide lines, lightweight grip-based file stroke, completion-only geometry update.
- `src/client/StockUI.lua`: workpiece-level `refine` callback for transactional one-piece replacement.
- `src/server/FileTests.server.lua`: volume conservation, analytical radius sanity check, two separate edges, thin sheets, full-face edge snapping, already-rounded edge rejection, and tube rejection.

## Important limits

- This first milestone is **curved edge finishing**, not a swept-cut path system. Freehand curved profiles, metal filing across arbitrary surfaces, and curved cuts that divide a workpiece into separate pieces require the future general swept-subtraction and disconnected-solid detection system.
- Hollow tubes are not supported by the convex edge-filing backend. A tube-safe filing operation will need annular geometry handling.
- Completed roundovers generally require one EditableMesh to render; the guide uses ordinary pooled Parts. The generation is deferred until completion, and the old mesh is destroyed after its replacement is prepared successfully, but unique geometry still consumes the EditableMesh budget.
- All fabrication is client-local in the current M1/M2 prototype; authoritative server cutting, multiplayer replication, and manufacturing persistence are separate work.
- The changes were committed to `dev`, but the new interaction and tests have **not yet been run in a live Studio session**.

## Troubleshooting

- No Metal File equipped? Use the top-right **EQUIP METAL FILE** shortcut or the regular hotbar. A `Tool` and a visual `Model` are distinct; a Model alone is not an equippable Tool.
- Panel says **Secure the metal first**? Use the left-stock temporary secure control before attempting to file.
- No contour? Hover the face of a block or sheet and look for the gold curve on the nearest edge. Hollow tubes are intentionally unsupported.
- An error appears after clicking? Read the right panel or the Studio Output `[FILE]` warning. Geometry is left untouched on failed operations.
- The geometry and UI changes are committed but still require a **live Roblox Studio playtest**; the server tests run when the place starts, not in GitHub.
