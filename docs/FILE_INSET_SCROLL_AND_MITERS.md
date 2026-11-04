# FORM editor — scroll sizing and corner junctions

Updated: 2026-11-04. Branch: `dev`.

## Live tool size control

While a fabrication tool is active, rotating the mouse wheel changes its
primary dimension **instead of zooming the camera**.

| Active tool | Mouse wheel notch | Shift+wheel |
|---|---:|---:|
| Drill | 2 mm diameter | 10 mm diameter |
| File Edge | 1 mm chamfer width | 5 mm chamfer width |
| Inset / Pocket | 2 mm inset border | 10 mm inset border |

The relevant numeric TextBox always receives the new value, so clicking to
commit uses the same precise number the user sees on screen. Minimum File
wheel width is 6 mm because smaller chamfers are especially unreliable in
CSG. Typing a number into the TextBox still works. The underlying operation
geometry is regenerated only when clicked; the hover preview is inexpensive.
Ctrl+MMB drag still zooms the camera while a fabrication tool owns the wheel.

**Inset border is a linear distance, not a rounded corner radius.**
True edge rounding / fillet radius is a separate future tool.

## Interior filing

This is available *without a mode toggle*:
- The selected edge between the floor and a pocket wall is treated as an
  interior corner. Convex vertices in a pocket's sidewalls are also interior.
- A concave vertical perimeter corner in a manufactured sketch profile is
  treated as an interior corner.
- Interior previews are green and labeled `INSIDE CHAMFER`.
  The resulting feature is a small **additive** triangular bridge.
- Exterior previews are cyan and labeled `OUTSIDE CHAMFER`.
  The resulting feature removes a corner chip from the stock.
- Curved, misaligned and oversized edges are rejected. Interior and exterior
  classification still depends on FORM's feature-history reconstruction.

## Exterior bevel junctions

Where two *enabled exterior File features* meet at the same vertex, the
compiler identifies a compatible trihedral junction:
- The two bevels must share one face normal and have three approximately
  orthogonal outward face normals in total.
- Each selected edge must point inward along the third material direction.
  This avoids treating an accidental crossed cut as a cube corner.
- If compatible, the compiler makes a small disposable tetrahedral
  **corner cleanup cutter** and subtracts it after the second File feature.
  The cutter removes a residual triangular spike where the bevels meet.
- If the small mesh or Boolean fails, it logs a warning and retains the
  completed bevels rather than breaking the document.
- The feature remains parametric: toggling or deleting either contributing
  File operation removes the derived junction patch on replay.

This is deliberately **not** a general CAD miter solver. A lone bevel still
has its triangular terminal cap. Acute angles, inside corners, unequal
profiles, nonorthogonal joints and multiple consecutive bevel junctions will
need proper topology-aware trimming in a later pass.

## Testing sequence

1. Start with a fresh Block, choose File Edge, and roll the wheel while
   hovering. Confirm the cyan preview changes, its dimension label changes,
   the File text field tracks the value, and the camera does not zoom.
2. Press Shift and scroll for faster increments. Make one exterior File
   operation and ensure its history records the displayed size.
3. Apply a second **perpendicular exterior chamfer** meeting the first at
   one original block corner. Confirm that the compiler status reports
   a corner miter when the CSG solver accepts the cleanup cutter. Inspect
   the corner for triangular residue or spikes.
4. Cut a rectangular recessed pocket. Hover its bottom/wall seam with File:
   the indicator should be green `INSIDE CHAMFER` rather than cyan.
   Click once and inspect for an additive interior bevel.
5. Choose Inset and use the wheel to change the border width. The offset
   perimeter should resize on the hovered *actual* planar face. Commit.
6. With any of these tools active, check Ctrl+MMB for camera zoom. Exit the
   tool and verify the mouse wheel returns to normal hybrid camera zoom.
7. Toggle/delete an existing File feature. Corner reliefs should follow
   the enabled File history on recompilation, not survive as stray geometry.

No automated Roblox Studio execution has been performed from this chat.
Inspect the real CSG result before trusting the miter algorithm on complicated
assemblies. If a corner miter makes an unusual cut, the compiler's
`ENABLE_CORNER_MITERS` local toggle can be set to false to disable just
the experimental junction cleanup without losing the basic File tool.
