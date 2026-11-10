# OPENWORKS Phase 02 — Construction Playtest

## Setup

1. On the local `dev` branch, run `START_OPENWORKS.bat`. The launcher should report `2026.11.09.PHASE02.CONSTRUCTION`.
2. Connect Rojo at port **34872**.
3. Keep your previously generated `ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT` in the Studio place. The client logs how many templates it found.
4. Press Play. The primitive showroom gallery should disappear **only in Play**, so it does not interfere with raycasts or movement.
5. Confirm no red script errors in Output. The native **Build / Edit / Assemble / Inspect** tools remain equipped through Roblox's default hotbar.

## Build tool

- Equip **Build** with key **1**.
- Press **B** for a clickable primitive catalog (first-person cursor unlocks while open).
- Choose `Block` or any other entry. The selection is a client-only translucent preview at the center crosshair.
- Aim at the ground or an existing piece. Click to place.
- Repeat and stack blocks against one another. Pieces should follow a **1 U = 0.25 studs** grid and touch at faces without overlapping.
- Rotate placement in 90-degree increments using **R** (Y axis), **T** (X axis), **Y** (Z axis).
- Press **X** to cycle the resize axis (local X, Y, Z), and **[ / ]** or **- / =** to change dimensions by 1 U.
- Native solids have free dimensional resizing subject to shape constraints. Tubes only resize along their length; fixed drilled/slot modules cannot resize.
- Press **Ctrl+Z** to undo and **Ctrl+Y** to redo.

## Edit tool

- Equip **Edit** with key **2**.
- Aim at one of your placed pieces and click to select it. It receives an outline.
- **G** enters move placement; aim at the new surface and click to confirm. **Esc** cancels.
- **R/T/Y** rotate the selected piece in 90-degree steps.
- **X** chooses a resize axis; **[ / ]** changes size when allowed.
- **F** or **Ctrl+D** copies a selected piece into a ghost preview; click to place it.
- **Delete/Backspace** deletes the selected piece.
- **Ctrl+Z / Ctrl+Y** undo and redo create, edit, and delete operations.
- Try selecting pieces from another player's build: editing them should be rejected.

## Required edge cases

- A 1 U block (0.25 studs) should place at exact Unit increments, including against neighboring pieces.
- A native Cylinder must stay perfectly circular when changing diameter; a Sphere must remain spherical.
- A precompiled tube with a hole must preserve its opening when extending its length.
- A fixed drilled module must reject resizing, but may be placed adjacent to ordinary blocks.
- Trying to intersect two solid pieces must be rejected by the server; face-to-face attachment should succeed.
- Joining parts into **one rigid component** is **not implemented**; Phase 03 will introduce that concept.
- A shaft placed inside an empty tube opening should be permitted if the CSG collision decomposition agrees. Extremely small holes still require physics tests.
- Equip Assemble/Inspect: they remain mode placeholders, with no destructive side effects.
- Reset the character; the four native tools should reappear without duplicates.
- Ctrl+Z and Ctrl+Y should affect only the current player's pieces.
- Play runs should not persist placement after server shutdown; blueprints/persistence are a later phase.

## Implementation notes

- A `RemoteFunction` named `OPENWORKS_ConstructionRequest` validates allowed tools, player ownership, placement range, template identifiers, Unit grid and dimension rules, part count, rate limit, and geometry interference on the server.
- Server never recompiles CSG: it clones Studio-precompiled primitive models.
- Overlap checks use `workspace:GetPartsInPart()` and a slightly shrunken probe for touching-face tolerance; verify CSG collision fidelity visually and physically.
- Preview placement currently uses center-screen raycasting and axis-aligned surface-normal snapping. Arbitrary sloped-face alignment, insertable bearings, mechanical relationships, and layered editing belong to later phases.
- Geometry is anchored during construction; grouping/physics simulation will come later.
- No game code has been run in a Roblox Studio Play environment by the assistant. This smoke test is the verification gate.
