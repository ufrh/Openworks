# OPENWORKS Phase 04 — Layered Editing & Axial Insertion

Build marker: `2026.11.09.PHASE04.LAYERED-ALIGN`
Branch: `dev` — Rojo port `34872`

Phase 04 extends the approved first-person construction controls. There is
**no** new Roblox Tool instance or custom hotbar, and no new CAD workspace.

## Inspection and editing

1. Build several blocks and place one in front of another. Enter **Edit (2)**.
2. Aim at the group. Click selects the frontmost constructed piece.
3. Press **Tab** to select the next obscured piece along your crosshair ray.
   **Shift+Tab** traverses backward. Selection outline should remain visible
   even when the part is behind another one.
4. Press **X** to toggle X-ray (others become translucent, selection stays
   opaque). Press X again to restore original metal appearance.
5. Press **I** to isolate the selected primitive or whole component. Other
   constructed primitives hide locally, not on the server. Press I again
   to restore them. No geometry or ownership may change.
6. Equip **Inspect (4)**. Click and Tab should also pick/cycle depths. Inspect
   shows the selected primitive's dimensions or component bounding box in U.
   X-ray/isolate also work in Inspect; **Edit (2)** retains the selection.
7. While inside an editable component (E from Edit), Tab can select an
   individual primitive behind another component member.
8. Switching to Build (1) clears X-ray/isolate. All constructed pieces should
   become fully visible again. The native hotbar still works.

## Coaxial insertion workflow

1. Build a circular/square **Tube** and a full **Cylinder** (not HalfCylinder).
   Tubes run along local X; DrilledBlocks are assumed to have the hole
   through local Z. These assumptions may need per-template metadata later.
2. Equip **Edit (2)**, select the Cylinder shaft and press **A**.
3. Look at a visible surface of the Tube. A green highlight indicates a
   supported opening target. A yellow highlight indicates an unsupported
   primitive. Click the Tube to select its axial center as the destination.
   Press Tab to cycle candidate targets behind other constructions.
4. A translucent shaft preview should snap coaxially to the tube opening.
   The source remains untouched until you confirm.
5. Scroll the wheel to change insertion offset in whole 1-U steps. The FOV
   should remain constant **only while inserting**; normal FOV wheel zoom
   returns afterwards. [ / ] also nudge offset.
6. Click again to commit. The server validates grid position, working range,
   ownership, geometry interference, and the actual target. If any part
   intersects another solid, the request is rejected without moving the
   source. **Esc** cancels without changing geometry.
7. Build a flange + cylinder shaft as a single Phase 03 component, select
   the component and press A. Alignment should move *all* component members
   together while taking the cylinder as the axis reference. No parts may
   shear apart.
8. Try using a DrilledBlock instead of a Tube. Verify its through-hole
   is oriented correctly. Check a too-large cylinder is rejected if the
   precompiled collider reports solid interference.
9. Try overlapping a second bearing or other geometry on the shaft and
   insert it through the hole. The server must reject the assembly if
   any of its solid members collide with the opening at the chosen offset.

## Regression tests

- B opens the primitive library and **only B unlocks the mouse**.
- V retains locked first-person scaling. Drag a face in a grouped component;
  the edited primitive should remain in the same logical group.
- G on components still uses the centrally selected primitive pivot.
- Group, ungroup, duplicate, undo/redo should work. Align is one atomic
  history operation, reversible by Ctrl+Z.
- In two-player tests, neither player can modify another player's
  construction via the alignment action.
- Cancel or switch Tools mid-alignment; preview/highlights/visibility
  should clean up and wheel FOV should resume.

## What this phase DOES NOT do

- **No bearing, slider, or other joint is created.** Phase 05 will attach
  rigid bodies through mechanical relationships.
- There is no numeric bore/clearance certificate until the Studio-generated
  primitive catalog has reliable bore metadata. Fit is checked against the
  actual precompiled collision geometry via `GetPartsInPart`.
- The current Shaft detector recognizes Cylinder templates. The current
  Opening detector recognizes CircularTube, SquareTube/RectangularTube,
  and DrilledBlock template families. HalfTube is not a closed opening.
- An opening's assumed axis is its model pivot's X (tubes) or Z
  (DrilledBlock). Geometry variants with off-center openings or alternate
  axes must be extended with explicit per-template metadata.
- Arbitrary sketch geometry, nested assembly relations, and pre-shipping
  physics simulation remain future milestones.

No Roblox Studio Play session was executed by the assistant. This checklist
is the gameplay acceptance gate.
