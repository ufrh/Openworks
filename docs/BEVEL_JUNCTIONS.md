# Tiny triangular cap at an L-shaped concave corner

Status: source implemented on `dev`; Roblox Studio CSG visual test pending.

## Exactly what this addresses

Two **ordinary exterior top perimeter File operations** meet at the inside
vertex of an L-shaped workpiece. A small square-ended cap can remain there.
Instead of re-enabling vertical inside filing or a general bevel miter,
FORM now generates one **small four-point corner cut** that leaves a
triangular slope at that vertex.

`CornerTriangle.lua` accepts ONLY two exterior File features whose:
- endpoints coincide at one corner;
- outward top normals both point up;
- wall normals are perpendicular;
- edge rays point along each other's outward wall normals, identifying a
  concave notch rather than a convex outside block corner.

The four points are the original top corner, the corner moved inward by
each existing bevel width along each adjoining wall, and the corner
moved down by the smaller bevel width. They define a bounded tetrahedral
chip of the **existing solid**. There is no additive wedge and no
repeated patch per edge. Once the second File is compiled, the original
normal exterior filing results remain unchanged except at that one corner.

The face picker derives the corresponding small triangular surface from
the same four points. Existing vertical interior File history stays
paused and is not included in compilation or feature picking.

## Acceptance test

1. Create a new L-shaped sketch body.
2. File *only* the two top outer perimeter edges meeting at the concave
   notch corner.
3. Inspect their shared cap: it should be a **single triangular slope**,
   without a square post or a long gouge down either edge.
4. Check the FORM fabrication summary for `1 corner triangles`.
5. File a normal convex outside block corner: the count should remain
   `0 corner triangles`.
6. Confirm that interior vertical edge filing is still unavailable.

A Studio Command Bar math check is included at
`scripts/VERIFY_CORNER_TRIANGLE.lua` for matching/narrowness rules.
It does **not** certify the appearance of Roblox's resulting CSG mesh.

If the exact corner is not resolved, the next step is inspecting the
actual CSG geometry, not introducing any more generalized bevel systems.
