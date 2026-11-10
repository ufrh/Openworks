# OPENWORKS — Move-only interaction and fixed 0.5-U regression

Build marker: `2026.11.09.PHASE05.MOVE-ONLY-HALF-U` | branch `dev`

## Selection and movement
1. Equip **Edit (2)**. Aim at a Block and click once. It selects, but
   does not move; moving/looking around after releasing LMB leaves it still.
2. Select another part with a quick click; selection changes, with no drag.
3. Hold LMB on the **already selected** part and move/look for a moment
   (the activation threshold is deliberate, not a simple click). It enters
   the same temporary Move preview used by G; release commits.
4. Select a multi-primitive component. Move arrows appear near its central
   primitive. All construction parts stay rigidly placed relative to
   one another during a drag; red interference blocks finalization.
5. Aim the center crosshair at the colored cone or shaft of an arrow,
   hold LMB, move/look/walk: the component moves on that axis ONLY.
   Release commits one reversible change.
6. Rotating with R/T/Y stays available, but **dragging NEVER rotates**.
   There should be no 3D rotation rings visible.

## Sizing
1. Equip Build or Edit; V enters Scale, with six vivid colored spherical
   handles. They have SmoothPlastic, NOT Neon, to avoid bloom under
   postprocessing effects. No cube-shaped scale grips or box borders.
2. Hold LMB on a sphere and move/look/walk; the opposite face stays
   where it was, and size changes in **0.5 U** steps.
3. Press [ or ] while scaling: these keys should no longer change the
   step size. HUD and context panel should describe 0.5 U as FIXED.
4. Move an axis grip: axis movement should also snap at 0.5 U.
   Assemble insertion wheel/keys should move by 0.5 U.
5. Ordinary Build placement targets snap to 0.5 U tangential positions;
   exact surface support still keeps the construction outside the floor.
   Legacy fractional-sized parts (0.25 U) remain valid.

## Visibility & interaction
- When selected, move arrows have visible cylinder shafts and
  `ReplicatedStorage.Cone` tips, with no transparent-geometry dependency.
- Physical grips are not collision/query targets and do not interfere with
  the construction raycast.
- The normal SelectionBox highlight on a selected component remains as it
  was before this pass.
- Existing red/blue validity, bore-clearance logic, deletion, undo/redo,
  and right-side context help must remain intact.

**Studio playtest required:** GitHub source verification does not establish
that every first-person input ordering or handle placement is correct
in a running Roblox Play session.
