# OPENWORKS — Physical interaction and precision workbench

All interactions use actual Workspace objects. No Roblox Tool, Backpack, hotbar, or old fabrication UI.

## Required workshop objects

- `Workspace.Workbench` contains one or more BaseParts named `surface` (case-insensitive). Server creates invisible tabletop supports and overlap-query regions.
- A physical saw or file is a rigid, welded, unanchored Model or BasePart tagged with Boolean attribute `isTool = true`. Clickable geometry must have `CanQuery = true`.
- Tool operation is selected by String attribute `FabricationKind = Saw` or `File`, or inferred from the Model name containing `saw` or `file`.
- Materials are `FORMMaterial` tagged and `isMaterial = true`. The Studio **Spawn Test Sheet** button makes an unanchored physical steel sheet with `FORMNativeStock = true`, which supports the native rectangular-stock operation.
- Both tool and selected material must settle onto the Workbench to enter precision fabrication; their `OnWorkbench` attributes are set by the existing detector.

## Optional tool contact attachments

Add an **Attachment** named `BladeEdge` anywhere inside the welded saw model to precisely define the working blade contact. Its local **+X** is the stroke direction, **+Y** points out of the stock, and **+Z** is the cutting-plane normal.

Add `FileFace` to a file if desired. Without `BladeEdge`, OPENWORKS first looks for a BasePart named `Blade`, `SawBlade`, or `BladePart` and aligns the longest axis of that blade. If no blade is found, it uses the full tool's bounds, following the earlier saw visual alignment convention. A hand-authored attachment is still the accurate option for custom Blender geometry.

In precision mode, **R** rolls the physical tool 90 degrees around the stroke axis; **Shift+R** rolls it back 90 degrees. This does not change the cut plane and lets you correct models whose grip/blade faces are oriented differently.

The physical tool is never cloned into a separate cosmetic. An invisible target with server-controlled AlignPosition / AlignOrientation moves the same rigid assembly. **Every BasePart in the tool is forced to CanCollide=false, CanTouch=false, and CanQuery=false throughout fabrication**, and its previous values are restored on exit or completion. Dragging outside fabrication retains normal physics and collisions.

## Free-mode interaction

- **Hold LMB** on material or tool: physically lift and drag it. Release to drop.
- **Very short LMB click**: select instead of carry.
- While dragging, **wheel** changes reach; **Shift + WASD** rotates the assembly.

## Material inspection

- Short-click a material, or short-click a tool when exactly one workpiece is on the bench.
- **RMB drag** orbits; **MMB drag** pans; **wheel** zooms around the physical workpiece.
- In the right-side panel, select a saw/file that is physically present on the bench.
- **Escape** exits, restores normal camera, and releases any active fabrication motor.
- The inspection camera no longer requires the default Roblox `PlayerModule`, which may not exist in customized player scripts.

## Saw positioning and cutting

1. Select the steel sheet, then the saw. The real saw is aligned to the workpiece using `BladeEdge` (or the tool-bounds fallback).
2. A narrow **gold cutting guide** appears on the sheet. Move the mouse over the metal to position it. **Shift + horizontal mouse movement** also adjusts the cut offset.
3. Press **Q** to switch between cuts normal to local X and local Z on native rectangular stock.
4. **Hold LMB and manually move the mouse back and forth**. The actual physical saw follows each stroke. Repeated full reversals advance progress; releasing the mouse pauses.
5. When the twelve qualifying stroke reversals complete, the server calls `SawCut.split` using FORM. For a test sheet, the result is two independent unanchored physical Parts, both marked as FORM material and preserving the material appearance.
6. **RMB orbit** and **wheel zoom** remain available throughout; the camera remains focused on the current physical piece.

For a file, the same manual-stroke controls are available, but native test sheets currently support only a simple planar shave, **not** the older curved edge-filing preview.

## Scope and safety

- Saw geometry edits currently work only on rectangular native `Part` material with `FORMNativeStock = true`; arbitrary imported/EditableMesh FORM pieces need a mesh replacement adapter. The UI reports unsupported machining instead of deleting geometry.
- No fake tilted/oblique saw-cut mode is presented: the native-Part fragment renderer supports only the X/Z straight cut directions. More complex FORM split results require physical EditableMesh output.
- This code has been reviewed/committed on GitHub but **has not been tested inside Roblox Studio**. In Studio, verify: detection, grabbing, click selection, camera orbit, tool positioning, gold guide, manual stroke progress, two physical offcuts, and ESC restoration.
