# OPENWORKS — Direct Drag Only

Build marker: `2026.11.10.PHASE05.DIRECT-DRAG-ONLY` (`dev`).

The separate move arrows and MoveGizmo controller have been removed.

1. Equip Edit (2) and click an unselected primitive or component once.
   It should highlight without moving.
2. Aim at that **already selected** object, hold left mouse and move/look.
   After the deliberate drag threshold, it should enter the existing
   ground/surface-aware temporary move preview.
3. Release left mouse to confirm a blue placement. A red overlap
   blocks committing and leaves the object where it was.
4. Try G as an alternative to drag-moving the selected piece or group.
5. Press V: the six colored spherical scale grips should still work.
6. Press R/T/Y: rotation remains keyboard controlled.
7. No move arrows or rotation rings should be present in Edit mode.
8. Switch to Build and Assemble. Ensure existing selection/placement,
   shaft-alignment, undo/redo, and scale behavior still work.

Not playtested in Roblox Studio; this is the acceptance checklist.
