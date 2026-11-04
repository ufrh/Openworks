# FORM — Shared Bevel Junctions (Prototype)

Updated: 2026-11-04 · `dev`

## Problem visible in Studio

Filing an L-shaped workpiece's two top perimeter edges and then its
**vertical concave edge** created a rectangular block at the intersection.
The File feature used an independent triangular-prism Boolean for each
edge. An interior File **adds** a wedge along the entire vertical edge,
which can refill material that the top and bottom bevels previously
removed. The earlier automatic tetrahedral miter and endpoint-taper
experiments did not solve this consistently.

## Current solution

`BevelJunction.lua` is a shared deterministic model used by:

- **Fabricator**: After the second of two compatible File operations, it
  continues the already-authored *outside bevel's slope* across the added
  interior wedge, using a short, bounded planar cutter that follows the
  perimeter into the inside corner. It only applies when an inside and
  outside File share a real endpoint and one wall face and their edge
  directions are nearly perpendicular.
- **HistoryTopology**: Builds the same junction pairings, clips the
  interior bevel face polygon against the neighboring outside bevel
  planes, and exposes the resulting V-shaped boundary lines and planar
  triangular corner-wedge faces to the edge/face picker. The original
  sharp edge is retired and the new bevel trim lines are connected to
  their adjacent logical faces.

This is done **during normal replay**, not as an independent user feature
or arbitrary auto-miter. A File feature can still be individually
disabled or deleted; its related junctions disappear on recompilation.

The same mechanism is intended to work whether the interior File is
committed before or after its neighboring exterior File.

### Geometry scope

A valid junction must have:

- one additive concave straight File and one subtractive convex File
- an actual shared vertex and a shared outward wall normal
- nearly perpendicular edge directions, with the outer edge proceeding
  along the exposed inner-corner wall ray, not backward into the solid
- enough outer-edge span to cover the entire added wedge
- independently validated cutting widths and a bounded CSG region

A plain joint between two convex bevels, a rounded edge, an arbitrary
imported mesh or complex nonorthogonal intersection is **not** handled.

## Numerical geometry check

`scripts/VERIFY_BEVEL_JUNCTION.lua` can be pasted into the Studio
Command Bar after Rojo sync. It asserts that the four matching
top/bottom L-corner outer bevels all produce valid planar patch geometry,
while an opposite-arm bevel and two exterior bevels are rejected.

The example uses an inside vertical wedge of width 0.20 studs and
outside top bevels of width 0.12 studs. For a 90° L notch the inside
chamfer is clipped by the planes

```
x + y = 1 - 0.12
z + y = 1 - 0.12
x + z = 0.20
```

whose common junction point is `(0.10, 0.78, 0.10)`. This creates a
sloped joined wedge, not a vertical rectangular end cap. The normal
directions reverse as expected for bottom-plane bevels.

This mathematical check is NOT a substitute for visual confirmation of
`GeometryService` Boolean behavior in Studio.

## Studio acceptance sequence

1. Create a **fresh** L-shaped body using New Body Sketch.
2. File the two top perimeter edges heading away from its inside corner.
3. File the **full vertical inside edge**. Inspect the upper junction:
   it should become sloped instead of forming a square block.
4. Repeat on the bottom edges. The compiled status should include
   `joined corners` when compatible junctions were recognized.
5. Hover the newly generated bevel trim lines and junction edges.
   The green/cyan File preview must target the NEW manufactured edge
   rather than the original sharp vertex.
6. Disable just the vertical File feature in history. Joined geometry
   and its new edge candidates should disappear. Re-enable it.
7. Reverse the order: file the vertical edge first and then top edges.
8. Verify that an unrelated nearby exterior bevel does NOT create
   a spurious corner trim.

## Known limitations

This is a **restricted analytic feature graph**, not a complete CAD B-rep
or general polygon-Boolean topology kernel. It currently handles the
specific straight perpendicular concave/convex corner intersection shown
in the user's L-profile screenshot; other junctions are unchanged.

Generated CSG mesh readback is unavailable in the current Studio setup,
so selection still uses authored history plus CSG raycast visibility.
Very narrow bevels, disconnected Boolean solids, and intersections with
unrelated drill/groove cutters may be unstable or require more topology.

**The algorithm has been reviewed against sample L-corner coordinates
but has not been executed in Roblox Studio from this chat.** If a
junction cutter fails, the compiler reports an error rather than
silently applying a guessed corner patch.
