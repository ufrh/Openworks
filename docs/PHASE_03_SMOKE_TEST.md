# OPENWORKS — Phase 03: Editable Rigid Components

Build marker: `2026.11.09.PHASE03.COMPONENTS`. Branch: `dev`.
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
5. Press **G** and move the entire component to a different surface. All pieces
   should maintain their relative offsets. Click to commit.
6. Rotate the selected component with R/T/Y. Members must rotate together.
7. Press **F** to duplicate the component; the copy must contain 3 distinct
   primitives and be independently selectable. No overlaps allowed.
8. Press **E** to enter component editing. Click a single primitive inside.
   Press **V** to scale one native piece, or G to move that one piece.
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
