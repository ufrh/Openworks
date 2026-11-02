# OPENWORKS M2 — Manual hacksaw prototype

The saw is a player-operated interaction on top of FORM and the M1 physical workpiece registry. It does **not** regenerate the mesh each frame.

## Setup

- Put your visual model at `ReplicatedStorage.Hacksaw` (a Model or a single BasePart).
- Put a Roblox `Tool` named `Hacksaw` in `StarterPack` (or put the complete Tool somewhere under ReplicatedStorage and use the Equip button). The Tool and visual model can have the same name because they are in separate containers.
- If the Tool already has a direct `Handle`, the model is cloned and welded to it. If it has no Handle, the model's `Handle` part, PrimaryPart, or first BasePart is adopted as the Handle. For correct grip alignment, name the grip part **Handle** in your model and set the Tool's Grip to taste.
- Optionally put an **Attachment** named `CutNormal` inside the Tool model; its **WorldAxis** is the normal of the cut plane. Without it the prototype uses the stock-local X axis (rotated by Q/E), so camera orbiting doesn't change the cut plane.
- `Metal File` is reserved as the next manual fabrication tool; no filing behavior is implemented in this phase.

## Manual test

1. Run Play and equip the Hacksaw through the Roblox hotbar or the compact **Equip Hacksaw** control on the right.
2. Click a raw piece (or use **Select Next Piece**) and choose **Temporarily Secure / Release** on the **left-docked** Raw Stock panel. The piece must be anchored for this temporary vise prototype.
3. Hover the mouse over the secured piece. A gold intersection outline previews the actual cutting plane. No EditableMesh is allocated for the preview.
4. Press **Q/E** to rotate the cutting plane by 15 degrees; **V** toggles workpiece-centered orbit camera; **T** selects top-down; hold RMB and move the mouse to orbit, mouse wheel to zoom.
5. **Hold LMB** to operate the equipped Tool. The grip reciprocates while progress fills (3.8 seconds for steel, 2.6 for aluminum). Releasing early cancels without any changes.
6. At completion, `SawCut.split` applies a **0.8 mm kerf** as two FORM convex-plane splits. Both fragments are independently watertight. The larger fragment inherits the temporary anchored workholding state; the other is released into physics.
7. New geometry is rendered once per completed cut. Rectangular fragments become inexpensive native Parts; oblique cuts can require fresh EditableMeshes.

## Internals

- `src/shared/SawCut.lua`: plane intersection guide, world-to-FORM coordinate mapping, twin planar splits and kerf volume verification.
- `src/client/StockUI.lua`: atomic two-piece workpiece replacement, density and physical state retention, fragment recentring, and stock palette docking.
- `src/client/SawUI.lua`: Tool detection, fabricating controls, preview part pool, procedural Tool.Grip animation, and optional orbit camera.
- `src/client/ToolVisual.lua`: match the visual model in ReplicatedStorage to a Roblox Tool by name, with handle welding.
- `src/server/SawTests.server.lua`: geometric tests for centered/rotated steel cut, kerf volume and thin sheet.

## Known scope

This builds on the existing **client-local** M1 stock prototype. Cutting and workpiece replacement are not yet server-authoritative or multiplayer replicated. `FORM.Cut.split` currently requires convex solids: tubes and nonconvex manufactured geometry can fail. Collisions for EditableMesh fragments use the current hull creation mode and won't reproduce concave voids. Mesh memory remains limited; oblique splits may exhaust client EditableMesh capacity, but axis-aligned rectangular stock cuts stay as native Parts.

No bespoke saw machine is encoded in FORM: the tool interaction chooses the plane and timing, while FORM computes the resulting physical workpieces.

A working live Studio session is still needed to confirm input events, model grip orientation, physics settling, and resource budgets.
