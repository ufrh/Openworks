# Phase 01 — Native Tools and first-person camera

This phase is an input/control foundation. It does not implement placement,
snapping, editing, or mechanical relationships yet.

## Run
1. Pull the latest `dev` branch locally and run `START_OPENWORKS.bat`.
2. Connect Rojo to the existing OPENWORKS place (port 34872), then press Play.
3. Confirm the default Roblox Backpack hotbar shows **Build, Edit, Assemble, Inspect**.
4. Press 1–4 to equip each tool. No handle/model should appear in hand.
5. Click with each equipped tool. The client Output should log the activation.
6. Walk/look around using Roblox's native first-person controls.
7. Scroll the mouse wheel: FieldOfView should smoothly change without dollying.
8. Reset/respawn. The same four tools should return, without duplicates.
9. Confirm the existing Studio-generated `ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT`
   is reported with a template count; absence warns but does not break startup.
10. Verify FORGE starts on server and client without a boot error.

## Ownership and synchronization

- Native Tools are created server-side in `StarterPack`, and Roblox clones them
  to the player's Backpack on spawn.
- Tool effects are client events today; authoritative construction will be
  added behind server-validated requests in the next phases.
- `src/shared/Construction/ToolDefinitions.lua` is the tool order/catalog.
- `src/shared/Construction/PrimitiveRegistry.lua` reads Studio-generated assets.
- The primitive library is authored/stored in the Studio place, **not** in Rojo.
- FORGE sources, networking bridge, Rojo place ID and port remain unchanged.

## Not yet implemented

Primitive placement, selection and hit-testing, gizmos, snapping, undo/redo,
component graph, layered editing, mechanical relationships and simulation.

## Known validation limits

No Roblox Studio Play session or live input automation was run as part of this commit.
Tool availability, FOV scroll interception, and respawn behavior require the above
interactive smoke test before Phase 01 is treated as verified.
