# OPENWORKS M2 — Manual hacksaw prototype

The saw is a player-operated interaction on top of FORM and the M1 physical workpiece registry. It does **not** regenerate the mesh each frame.

## Setup

- Put your visual model at `ReplicatedStorage.Hacksaw` (a Model or a single BasePart).
- Put a Roblox `Tool` named `Hacksaw` in `StarterPack` (or put the complete Tool somewhere under ReplicatedStorage and use the Equip button). The Tool and visual model can have the same name because they are in separate containers.
- The Roblox Tool retains its in-hand cosmetic. The matching ReplicatedStorage model is cloned as a separate Workspace saw for positioning and cutting, while the hand cosmetic is temporarily hidden. An optional `BladeEdge` Attachment in the model defines blade contact (+X stroke, +Y outward, +Z cutting-plane normal). Without it, the controller uses the model's bottom-center as an approximate contact origin.
- Optionally put an **Attachment** named `CutNormal` inside the Tool model; its **WorldAxis** is the normal of the cut plane. Without it the prototype uses the stock-local X axis (rotated by Q/E), so camera orbiting doesn't change the cut plane.
- `Metal File` uses its own filing controller; only sawing supports loose stock in this milestone.

## Manual test

1. Run Play and equip the Hacksaw through the Roblox hotbar or the compact **Equip Hacksaw** control on the right.
2. Click/select a raw piece. You can **temporarily secure it** for a stable cut and close-up camera, or leave it **loose** and cut it using the normal player camera.
3. Hover over the metal. A gold section outline and the actual **working saw model** appear while positioning; no EditableMesh is allocated for the preview. The held cosmetic saw returns when you stop targeting.
4. **Q/E** yaw the cutting plane by 15 degrees; **Z/X** tilt it 15 degrees for oblique cuts. **R** rotates the model for alignment; Shift+R flips teeth; **F** selects hovered stock; **V** toggles secured-stock camera focus. Secured stock uses normal Roblox RMB camera rotation and scroll-wheel zoom, starting at a close-up distance; loose stock does not take over the camera.
5. **Hold LMB** to move the already-visible Workspace saw model along the cut plane, reciprocating the blade and progressively penetrating the stock (3.8 seconds steel, 2.6 aluminum). The plane stays in local workpiece coordinates if the stock moves. Releasing early cancels without changing its FORM geometry.
6. A dark noncolliding kerf proxy visualizes progress. At completion, `SawCut.split` applies a **0.8 mm kerf**. Convex solids use FORM; hollow tubes use the annular tube splitter for supported transverse cuts. A secured workpiece retains the larger anchored fragment while the smaller drops. For loose stock, both resulting fragments are unanchored and inherit the original linear/angular velocities.
7. New geometry is rendered once per completed cut. Rectangular fragments become inexpensive native Parts; oblique cuts can require fresh EditableMeshes.

## Internals

- `src/shared/SawCut.lua`: plane intersection guide, world-to-FORM coordinate mapping, convex and tube cutting dispatch, and kerf volume verification.
- `src/shared/SawTube.lua`: non-convex hollow-tube cross-cuts, two-loop cut guides, annular caps, and profile metadata for repeat cuts.
- `src/server/SawTubeTests.server.lua`: analytical kerf checks, watertight genus-1 topology, angled cuts, repeat cuts, and invalid cut rejection.
- `src/client/StockUI.lua`: atomic two-piece workpiece replacement, density and physical state retention, fragment recentring, and stock palette docking.
- `src/client/SawUI.lua`: visible working saw during positioning, Tool input, 3D yaw/tilt control and **native** `CameraSubject` for secured stock. RMB rotates and the wheel zooms; no scriptable camera controller.
- `src/client/FabricationVisual.lua`: clone and move the real model in Workspace, with optional `BladeEdge` attachment alignment. See `docs/FABRICATION_MODELS.md`.
- `src/server/SawTests.server.lua`: centered, 3D angled, moving-local-plane, kerf conservation and thin-sheet tests.

## Known scope

This builds on the existing **client-local** M1 stock prototype. Cutting and workpiece replacement are not yet server-authoritative or multiplayer replicated. `FORM.Cut.split` still requires convex solids, but hollow cylindrical tubes have a dedicated profile-based path for straight or angled **complete cross-cuts**. Longitudinal slots, end-clipping cuts, and arbitrary nonconvex fabricated geometry remain unsupported. Tubular fragments retain their profile data so subsequent transverse cuts work. Collisions for EditableMesh fragments use the current hull creation mode and **won't reproduce the hollow bore for physics**. Mesh memory remains limited; tubes and oblique splits may exhaust client EditableMesh capacity, but rectangular stock cuts stay as native Parts.

No bespoke saw machine is encoded in FORM: the tool interaction chooses the plane and timing, while FORM computes the resulting physical workpieces.

A working live Studio session is still needed to confirm input events, model grip orientation, physics settling, and resource budgets.
