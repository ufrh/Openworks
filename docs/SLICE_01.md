# Slice 01 — Playtest and acceptance checks

**Goal:** Verify one authoritative Block lifecycle from first-person preview through validated FORGE command to saved document and generated Roblox Part.

## Manual test in Roblox Studio

1. Start Rojo and connect the plugin. Press Play. Confirm FORGE reports server and client startup with no errors. OpenWorks control strip and center-screen crosshair should appear.
2. Press **1**, look at floor, click: a 1-stud (4u) metal Block appears at the preview.
3. Press **2**, look at your Block, click: outline highlights. Press **R** then **F**: size increases and decreases by 0.25u on each axis.
4. Press **G**, aim at another floor position, click: selected Block moves.
5. Press **Backspace**: selected Block disappears. Press **Ctrl+Z** to restore, **Ctrl+Y** to remove again.
6. Stop and restart Play (with a published game and Studio API access enabled): saved Block IDs, dimensions, and positions should reload.
7. Try constructing before your player character spawns, moving beyond 70 studs from your character, supplying an invalid block id or stale revision from an exploit harness: server must reject commands.
8. Disconnect a player: their runtime Parts should be cleaned up; player data should remain in DataStore.

## Engineering checks

- No direct server authority is given to client-rendered ghost or selection.
- Compiled Parts have `OpenWorksId` and `OpenWorksOwner` attributes for click selection; authoring data is still stored separately.
- Every accepted edit increments document revision. Undo and redo are new server edits, never blind client snapshots.
- One owner cannot delete/resize/move another owner's block.
- Saves use document serialization, never `Workspace:GetDescendants()` scraping.
- FORGE endpoint schema/rate limits and service ownership checks both apply.
- Fresh, untouched places may need a generated floor; an existing Studio Baseplate is retained.

## Known first-slice limitations

- Player workspace plots are not isolated; players can see each other's parts but cannot edit them via the service.
- Entire owner snapshots are replicated and up to 32 source Blocks are supported; production will use deltas and partial recompilation.
- DataStore permission/access is needed for persistence, otherwise the UI shows a volatile session.
- No geometry booleans/fillets/SmartFit, no mechanical constraints or actual machine simulation yet.
- Full rotation manipulation and stabilization/active physics tests are separate milestones.
- Source exists on GitHub but must be exercised in Roblox Studio; static checks cannot prove engine behavior.

## Next development gate

After this slice passes, we add selectable axis resizing/rotation, stronger document schemas/transaction log, more primitives, then a spike to validate drilling true render + collision holes using available Roblox geometry APIs.
