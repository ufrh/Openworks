# OPENWORKS — Phase 05 Usability Pass

Build marker: `2026.11.09.PHASE05.FREE-ALIGN-FEEDBACK` | Branch: `dev`

## 1. Default sizing increment

1. Equip Build (1), choose Block, press V.
2. The HUD and the right-side controls list must both show **0.5 U** as the
   initial sizing step. Press [ once for 0.25 U, ] for 0.5 U, 1 U and 2 U.
3. Hold a face grip and walk/strafe/look around. Scaling follows the 3D
   crosshair ray and never counts pixel motion. Release and confirm the
   size, including fractional dimensions. Repeat in Edit.
4. Exit/re-enter Scale; the current user-selected step is retained during
   this play session. A newly started play session defaults to 0.5 U.

## 2. Alignment no longer requires a placement grid

1. Create a Cylinder shaft and a DrilledBlock, SquareTube and CircularTube
   with different 0.25-U or 0.5-U size increments.
2. In Edit (2), select the Cylinder, press L, choose the actual hole, and
   adjust insertion with the wheel in **0.5 U** increments.
3. In Assemble (3), click housing, click shaft, and likewise adjust at
   0.5 U intervals. The shaft must remain exactly coaxial, including
   off-grid center positions; its placement must NOT return a message
   that its position is not on the construction grid.
4. For the DrilledBlock, the hole goes through local **Y**, not its side.
   For the tubes, the channel is local **X**.
5. No user may align to somebody else's geometry. Physically interfering
   geometry is still rejected on the server. Grid snap restrictions are
   removed only for *authorized assembly operations / whole component
   transforms*, not arbitrary malicious client-supplied edits.

## 3. Whole-component surface support

1. Build an asymmetric component: one long block below the central member,
   and two smaller blocks above/alongside it. Combine with C.
2. Select group, press G, aim at the floor, click. All constituent geometry
   must rest on/above the floor. Its lower extreme—not the center of the
   central primitive—is what determines vertical placement.
3. Rotate the preview with R/T/Y, try several orientations and face normals
   before confirming. The whole component must stay above the surface.
4. Test component copy F with the same geometry. Repositioning must not
   break the rigid grouping or change member offsets.
5. Test a wall and other constructed objects. Interference should be red
   and the submitted transform should never clip into another construction.

## 4. Red / blue interactive feedback

1. Build a Block, aim at open floor: ghost should be **blue**.
2. Aim the same block to penetrate an existing constructed part: ghost
   should change **red**. Clicking leaves construction unchanged and
   explains the interference.
3. Repeat for whole-component G move/F copy, ignoring the selected
   source members but checking all other constructions.
4. Create a Cylinder that fits a hollow tube: Edit L and Assemble bearing
   insertion should preview **blue**. Increase shaft size so it collides
   with the tube's wall, or attach a flange and adjust axial offset into
   the housing: preview should become **red**. Scroll back to a clear
   offset and see **blue** return. Red cannot finalize.
5. All checks run locally for immediate feedback; server validates every
   committed action. No user can override validation by spoofing colors.

## 5. Contextual shortcuts and Delete

1. Equip Build, Edit, Inspect, Assemble in sequence. A compact right-side
   **CONTROLS / TOOL** list must update for each tool.
2. Enter V Scale, L alignment, G component movement, and Assemble bearing
   selection. The right panel should show only the controls relevant to
   that active context, plus WASD, Mouse, and Space.
3. In Edit press Delete to remove a selected primitive/component.
4. In Assemble, aim at a connected body, press Delete or Backspace.
   This deletes an authored mechanical relationship, **not** the
   underlying geometry. Ctrl+Z/Y should undo/redo relationship removal.
5. Exiting a tool hides its context list and switching tools does not
   leave an alignment preview or incorrectly tint built components.

## Limits

Parts remain anchored in Phase 05; actual constraint simulation/shipping
is separate. Blue/red is computed with the existing precompiled CSG
collision geometry, and may differ slightly from authoritative server
checks at mesh edges. Physical clipping is still prohibited, rather than
silently accepted. Studio playtest is required; no in-engine run was made
by the assistant.
