# OPENWORKS Phase 02 — Construction Playtest

## Setup

1. On the local `dev` branch, run `START_OPENWORKS.bat`. The launcher should report `2026.11.09.PHASE02.LOCKED-SCALE`.
2. Connect Rojo at port **34872**.
3. Keep your previously generated `ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT` in the Studio place. The client logs how many templates it found.
4. Press Play. The primitive showroom gallery should disappear **only in Play**, so it does not interfere with raycasts or movement.
5. Confirm no red script errors in Output. The native **Build / Edit / Assemble / Inspect** tools remain equipped through Roblox's default hotbar.

## Build tool

- Equip **Build** with key **1**.
- Press **B** to open the clickable primitive catalog. The pointer should unlock immediately; clicking an entry should work without leaving first-person mode. Closing B/Esc should relock it.
- Choose `Block` or any other entry. The selection is a client-only translucent preview at the center crosshair.
- Aim at the ground or an existing piece. Click to place.
- Repeat and stack blocks against one another. Pieces should follow a **1 U = 0.25 studs** grid and touch at faces without overlapping.
- Rotate placement in 90-degree increments using **R** (Y axis), **T** (X axis), **Y** (Z axis).
- Aim the Build preview at a surface and press **V** to freeze it in **Scale** mode. The mouse **stays locked** and colored face handles appear: red X, green Y, blue Z. Aim your center crosshair at a grip (it enlarges), hold left click, and drag. Mouse movement adjusts the size in 1 U increments while the opposing face stays anchored. Press V/Esc to return to normal first-person placement.
- Native solids have free dimensional resizing subject to shape constraints. Tubes only resize along their length; fixed drilled/slot modules cannot resize.
- Press **Ctrl+Z** to undo and **Ctrl+Y** to redo.

## Edit tool

- Equip **Edit** with key **2**.
- Aim at one of your placed pieces and click to select it. It receives an outline.
- **G** enters move placement; aim at the new surface and click to confirm. **Esc** cancels.
- **R/T/Y** rotate the selected piece in 90-degree steps.
- **V** opens the draggable Scale gizmo on the selection, with first-person mouse lock preserved. Aim the crosshair at a grip, hold left click, and drag. The camera stays fixed *only while dragging*; on mouse release the server commits one rescale operation (one undo step). Press V/Esc to dismiss the handles and resume first-person aiming.
- **F** or **Ctrl+D** copies a selected piece into a ghost preview; click to place it.
- **Delete/Backspace** deletes the selected piece.
- **Ctrl+Z / Ctrl+Y** undo and redo create, edit, and delete operations.
- Try selecting pieces from another player's build: editing them should be rejected.

## Required edge cases

- A 1 U block (0.25 studs) should place at exact Unit increments, including against neighboring pieces.
- A native Cylinder must stay perfectly circular when dragging radial handles; a Sphere must remain spherical when dragging its uniform scale handle.
- A precompiled tube with a hole must preserve its opening when dragging its length-only axis handle.
- A fixed drilled module must not show any resize grips, but may be placed adjacent to ordinary blocks.
- Trying to intersect two solid pieces must be rejected by the server; face-to-face attachment should succeed.
- Joining parts into **one rigid component** is **not implemented**; Phase 03 will introduce that concept.
- A shaft placed inside an empty tube opening should be permitted if the CSG collision decomposition agrees. Extremely small holes still require physics tests.
- Equip Assemble/Inspect: they remain mode placeholders, with no destructive side effects.
- Reset the character; the four native tools should reappear without duplicates.\n- While the catalog is open, verify mouse moves normally across the whole screen and the view does not turn. While scaling, verify the cursor **never unlocks**, normal first-person looking works until a grip is grabbed, the camera stays still during held drag, and no accidental piece is placed.\n- Rotate a rectangular block and drag a face; check the opposite face remains in place. Test the minimum 1 U limit and undo a completed drag with Ctrl+Z.
- Ctrl+Z and Ctrl+Y should affect only the current player's pieces.
- Play runs should not persist placement after server shutdown; blueprints/persistence are a later phase.

## Implementation notes

- A `RemoteFunction` named `OPENWORKS_ConstructionRequest` validates allowed tools, player ownership, placement range, template identifiers, Unit grid and dimension rules, part count, rate limit, and geometry interference on the server.
- Server never recompiles CSG: it clones Studio-precompiled primitive models.
- Overlap checks use `workspace:GetPartsInPart()` and a slightly shrunken probe for touching-face tolerance; verify CSG collision fidelity visually and physically.
- Preview placement currently uses center-screen raycasting and axis-aligned surface-normal snapping. Arbitrary sloped-face alignment, insertable bearings, mechanical relationships, and layered editing belong to later phases.
- Geometry is anchored during construction; grouping/physics simulation will come later.
- No game code has been run in a Roblox Studio Play environment by the assistant. This smoke test is the verification gate.
