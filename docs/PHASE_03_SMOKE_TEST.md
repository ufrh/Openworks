# OPENWORKS — Phase 03: Editable Rigid Components

Build marker: `2026.11.09.PHASE03.CENTER-PIVOT-SCALE`. Branch: `dev`.
FORGE 4.4.1, native Roblox Tools and first-person mouse lock remain unchanged.

## Startup
1. Start `START_OPENWORKS.bat` on `dev`, connect Rojo at port 34872, and press Play.
2. Verify the four native tools appear as before.
3. Confirm the Studio primitive library is available.
4. Verify the normal placed Block, Cylinder, DrilledBlock and Tubes are **dark gray Metal**.
   Precompiled CSG unions should be uniformly colored (UsePartColor = true).
   Preview ghosts remain transparently tinted for selection/placement clarity.

## Build your first component
1. Equip Build (1), choose Block in the B catalog, place three distinct pieces touching.
2. Equip Edit (2). Left-click the first. Hold Shift and click the second and third.
3. The HUD should report 3 selected primitives. Press **C** to combine them.
4. Click any piece again. All three should highlight as one **Rigid component**.
5. Press **G** and move the entire component to a different surface. The
   placement pivot should be the **most central primitive** (closest to the
   combined geometry's bounding-box center), *not* the first selected piece.
   All pieces must keep their relative offsets. Click to commit.
6. Rotate the selected component with R/T/Y. Members must rotate together.
7. Press **F** to duplicate the component; the copy must contain 3 distinct
   primitives and be independently selectable. No overlaps allowed.
8. While the component itself is selected, press **V**: scaling should
   automatically enter primitive editing, preferring the piece under the
   crosshair (otherwise the central member). Drag one of the scale grips and
   verify only that primitive changes. Alternatively press **E** to enter
   component editing and click a specific piece, then V to resize or G to move.
   Other members must remain in place. Press E to return to full-component
   selection (all members highlight).
9. With the group selected, press **U** to ungroup. Each primitive should be
   separately selectable with no geometry lost.

## History / regressions
- Press Ctrl+Z after grouping, ungrouping, whole-component move/rotate,
  duplication, or deleting a component. The previous component membership
  and geometry must be restored.
- Press Ctrl+Y to redo those operations.
- While editing inside a component, deleting a primitive should remove only
  that primitive. If one remains, it should become an ordinary ungrouped piece.
- Construct a shaft from cylinders, group it, enter with E, resize one section,
  exit with E, and move the complete shaft as a unit.
- Open B and verify the mouse unlocks **only for the catalog**. V drag scaling
  still keeps the mouse locked as in the approved Phase 02 controls.
- Check another player cannot group, move, or delete your primitives.
- Confirm Build and Edit still work for ungrouped pieces.

## Design boundary
This is a **logical rigid component** system for the anchored construction
phase, not a simulated physical rigid body yet. No welding or simulation is
performed. Membership is serialized as per-primitive ComponentId and
ComponentAnchorId attributes, preserving all authored primitives and their
individual transforms. Physics constraint compilation is Phase 06.

All edits are server validated. Group/ungroup/transform/duplicate/delete are
recorded as *atomic* batches in the same 50-operation undo history used by
ordinary construction. The scene is still ephemeral across Play sessions.

## Open issues / verification
- No live Roblox Studio execution has been performed by the assistant; this
  checklist is the acceptance gate.
- Moving an entire component positions it using the anchor primitive; the
  placement target can be adjusted by choosing/building an anchor.
- There are no freehand CAD transforms, component nesting, or physical joints yet.
- Phase 04 will add obscured-depth selection, transparency, and coaxial insertion.

## Phase 03 center-pivot / scale regression checks

- Make a visibly lopsided group: long plate, small block at one end, small
  block close to the midpoint. Click the end block first while combining.
  Move and duplicate the component. The pivot should now follow the most
  central primitive, not the end block used to start selection.
- Group several cylinders. Select the component as a whole, press V, drag
  a highlighted scale handle, and confirm a single cylinder changes while
  the rest remain connected logically. Press E to return to full selection.
- Scale one *ungrouped* Block using V; Phase 02 scaling must still work.
- Try Sphere uniform diameter and Cylinder radial-diameter resizing. The
  edited part must remain snapped to the 1 U grid and must not be rejected
  solely because its Y/Z half-Unit center parity changed.
- Open B and close B; only B releases the cursor. Scaling stays in locked
  first person; camera freezes only during the active drag.
- Undo/redo a successful resize and move, and inspect for data loss.
