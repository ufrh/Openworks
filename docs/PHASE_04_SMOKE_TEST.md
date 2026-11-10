# OPENWORKS Phase 04 — Layered Editing & Axial Insertion

Build marker: `2026.11.09.PHASE04.SCALE-SENSITIVITY`
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
2. Equip **Edit (2)**, select the Cylinder shaft and press **L**.
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
   the component and press L. Alignment should move *all* component members
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

## Grid and first-person drag regression (latest patch)

1. Create a tube and cylinder whose dimensions have different odd/even Unit
   parity (for example, a 4-U tube body and a 3-U cylinder shaft). Align the
   Cylinder using A, scroll to adjust axial offset, click confirm. It should
   not report "Position is not aligned to the Unit grid" solely because the
   centers have opposite parity. The shaft remains **coaxial**, not offset
   by half a Unit to fake a whole-Unit snap.
2. The half-Unit center lattice (0.5 U / 0.125 studs) is enabled only by
   **server-validated shaft alignment**. Normal Build and Edit placement
   still snaps faces at 1 U increments.
3. After aligning, resize the cylinder, undo and redo it; the validated
   assembly precision should survive history restoration. Other players
   must not submit arbitrary alignment requests for others' geometry.
4. Equip Build, aim a Block ghost at a surface, press V, aim at a handle and
   hold left click. **The camera should continue turning naturally as the
   mouse moves**, while the face resizes in whole Units. Release to commit,
   V/Esc to exit. No camera Scriptable mode or frozen camera CFrame.
5. Repeat on a selected placed Block in Edit mode; verify one server
   history step per drag. Verify ordinary first-person look still works
   during and immediately after resizing.
6. Only the B primitive library may unlock the mouse cursor.


## Scale input and movement-key regression — DRAG-FIX

1. Equip Build (1), select a resizable Block, aim it at the floor, press V.
   Handles appear, camera stays normal first-person, and the cursor stays locked.
2. Simply hold left mouse and move the mouse horizontally/vertically.
   The **closest visible axis handle** is selected automatically; it no longer
   requires a tiny 33-pixel precise hover. The selected face highlights and
   dimensions should visibly update each 1 U increment.
3. Test clicking while a native Tool is equipped. MouseButton1 can be marked
   processed by Roblox; that must **not** block scale input. Native Tool.Activated
   is an alternate scale-grab trigger while V mode is active.
4. Repeat with a placed part using Edit (2) -> select -> V. Dragging should
   preview immediately and submit a single server edit on mouse release.
   No Scriptable camera, no frozen camera CFrame.
5. While building/editing, press **A** or **D** and confirm they only
   perform native left/right movement. Alignment is now **L**, not A.
6. Select a Cylinder/shaft in Edit and press **L**; confirm the guided
   alignment selection appears, then Esc cancels. Native WASD stays intact.
7. Check the controller/status text reads the selected scaling axis and
   the resulting size in Units. All validation errors still appear in the HUD.


## Vector3/Vector2 drag-type regression

The prior resize gizmo called `delta:Dot(drag.ScreenDirection)` with a Roblox
MouseMovement `InputObject.Delta` (Vector3) and a projected axis (Vector2).
This raises a runtime type error, preventing any resize preview from updating.
The input path now converts delta.X/delta.Y to Vector2 first.

1. Equip Build, choose a resizable Block, aim at floor, and press V.
2. Hold left click and drag. Preview must resize on screen with whole-Unit steps.
3. Equip Edit, select a placed Block, press V, hold click, drag, release.
   The edit should persist and undo/redo should restore dimensions.
4. Confirm Studio Output has no Vector3/Vector2 type error in ResizeGizmo.
5. If no size change occurs, inspect Studio Output for the next error rather
   than changing the input behavior again without a reproduced failure.


## Scaling sensitivity regression

- Previous drag responsiveness depended on perspective projection. At close
  distances a 1-U step could require extremely large mouse movement.
- Scale sensitivity is now a fixed **7 pixels of projected mouse travel per
  Unit**, regardless of zoom, object distance, or primitive size.
- Test V resizing with a Block both near and far from the camera. Both should
  update quickly, in the same small amount of mouse travel.
- Dragging sideways along a handle's indicated direction should immediately
  move by 1 U without camera freeze. Existing grid validation still applies.
