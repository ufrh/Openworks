> **Segmented miter correction (2026-11-04):** Studio showed overlapping triangular slivers at an L-shaped concave corner when File used multiple segments. The miter had used `seam = corner - (wallA + wallB) * inset`, moving the seam a full radius along **both** axes and creating a square top cap. The seam is now placed at the **midpoint between both rounded profiles** (`inset * 0.5` on both axes). The top is constructed as two matching triangles instead of a quad with an unmatched collinear vertex. The Studio regression now checks cap vertices, facet planarity, opposite manifold edge winding, and all tested segment counts. Only the corner-shell construction and its regression test changed in this fix. Roblox Studio CSG still needs visual testing.

# FORM — Real 90° mitered File corners and segmented rounding

Status: implemented in `dev`. **Requires Roblox Studio visual testing.**

## File segment controls

- `1` segment: original flat chamfer, unchanged for older operations.
- `2–12` segments: approximates a tangent quarter-circle edge fillet using
  real watertight cutter facets. More segments give a smoother result.
- Type a whole number in **File segments (1–12)** or press
  **Alt + Mouse Wheel** while File is active.
- Plain wheel continues to change File width (1 mm per notch,
  Shift + wheel 5 mm), as before.
- Small radii with too many segments are rejected because sub-1.5 mm
  cutting facets tend to be unreliable in Roblox CSG.

The segment count lives in each `FileMesh` operation, so the compiler,
history replay, selection topology and visual preview agree. Existing
FileMesh operations without `segments` are treated as `1`.

## Miter instead of a random triangle

At a **concave 90-degree L-profile corner**, if two perpendicular *exterior*
File edges meet at the same vertex and have matching width and segment
count, their profiles now meet at a **45-degree diagonal miter seam**.

The new geometry is a small watertight closed shell whose top perimeter
has a true 90-degree turn. Each side of the miter is a continuation of
its corresponding edge surface:

- One segment produces **two planar sloped faces sharing an edge**, not
  the previous independent triangular face.
- N segments produces **2×N rounded facet strips** whose matched vertices
  meet along the common diagonal seam.
- No additive interior-edge File, no long taper and no global second
  corner-system pass. The miter cut is localized to the existing notch.

Its surfaces use consistent outward face winding. An analytic seam
validation checks that every edge has exactly two incident faces.
The normal exterior File cuts remain separate and are not modified
outside their small shared corner.

**Important:** Matching width and segment count are currently required
for a miter. Mismatched profiles are left unjoined rather than producing
a misleading or distorted miter. A general variable-radius blend is
future work.

## Selection model

`HistoryTopology` now describes every rounded File facet and every
miter strip, retiring consumed sharp source edges. Coplanar construction
edges are hidden from the edge picker; the diagonal miter crease can
remain selectable if its adjoining facets are noncoplanar.

Because runtime CSG MeshPart readback failed previously, this is still
based on parametric history plus raycast visibility, not exact compiled
mesh triangles.

## Studio tests

1. Make a fresh Block. Set File to **1** segment: a normal flat bevel.
2. Change segments to **4**, then **8**; the edge should become smoother.
   Alt+Wheel changes segment count while ordinary wheel changes width.
3. Make a fresh L-shaped part and file its two top outer perimeter edges
   with the *same width and segment count*, starting with **1**.
4. Inspect the shared corner: the two bevels should meet on a 45-degree
   seam, and the top outline should remain a 90-degree corner. The
   fabrication summary should say `1 corner miters`.
5. Repeat with **4 segments** on both edges, then **8 segments**.
6. Repeat for lower edges if selectable on the component.
7. Test a convex outside block corner: no miter should appear.
8. Disable one File operation: its miter should disappear on recompile.
9. Test different widths/counts: the mismatched pair should be left
   without a miter, not triangulated incorrectly.

`scripts/VERIFY_CORNER_TRIANGLE.lua` is the existing filename for the
**new** Studio Command Bar analytic miter regression. It checks the
winding and connectivity of all facet strips for 1, 2, 3, 4, 6, 8 and
12 segments. The script does not confirm the final Roblox Boolean
rendering, which must be observed in Studio.

## Boundaries

This is limited to straight exterior edges, right-angle concave notch
junctions, matched profiles and reasonably sized cutters. Interior
vertical-edge File remains disabled. General arbitrary-angle fillets,
multi-body intersections and unequal-width corners are not solved.

**These code changes have not been executed in a Roblox Studio session
from this conversation.**
