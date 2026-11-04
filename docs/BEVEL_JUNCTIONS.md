# FORM — Direct shared 45° miter seam

Status: implemented on `dev`; Roblox Studio Boolean visual test pending.

## Why the segmented corner produced slivers

The previous design subtracted two independent full-length rounded File
cutters, **then subtracted a third standalone miter cutter** at their common
concave L corner. Even when that corner cutter had a mathematically closed
shell, the three overlapping CSG cuts could create thin seams, extra
triangles or inverted-looking facets.

The third cutter is now **completely removed** from Fabricator. There is
no separate CornerTriangle.faces() geometry to Boolean afterward.

## Current implementation

A pair of exterior File operations qualifies for the direct miter only if:
- both edges end at the same concave 90-degree L-profile vertex;
- both have equal File width (within 1 mm) and equal segment counts;
- both share the appropriate outward top/bottom normal and perpendicular
  wall normals.

`CornerTriangle.miterEnds` produces **one diagonal plane** passing
through the original common vertex. For either cutter, each cross-section
vertex at that end is projected along the longitudinal edge direction
until it lies on this exact plane. The other end remains unchanged.

The two independent **edge cutters** therefore share an identical set
of seam vertices for their corresponding segment bands. Their exposed
surfaces meet directly on that seam without an extra miter patch.

The first edge's cutter already receives its miter end during compilation,
even if the second edge's File operation occurs later in history. This is
possible because Fabricator first discovers all enabled File pairs before
replaying fabrication operations. The same pairing is repeated by
HistoryTopology using the same miter-plane and vertex-projection methods.

For a right-angle L corner, the seam lies on the 45-degree plane
`(wallA - wallB) · (point - corner) = 0`. For equal width and segments,
corresponding edge-band points coincide exactly (up to floating-point
roundoff). Reversed edge direction is handled by choosing either the
start or end ring.

**One segment** still creates a straight chamfer; **2–12 segments**
create faceted quarter-round edges. Interior vertical-edge filing
remains paused. Different segment counts/widths are left unpaired;
no automatic mismatched-profile patch is created.

## Geometry and editor topology

- `GeometryCutter.prism` projects the appropriate end-ring vertices
  onto the joint plane before constructing its disposable CSG cutter.
- `GeometryCutter.fileSurfaceFaces` uses the very same projection to
  expose manufactured chamfer and fillet facets for HistoryTopology.
- The original sharp edge is retired from selection; adjacent rounded
  strips share vertex positions at the diagonal seam.
- No generated CSG MeshPart readback is needed.

## Studio acceptance sequence

1. Start with a **fresh L-shaped part** and set File to 1 segment.
2. File the two top exterior edges meeting at its concave corner, using
   equal widths. Confirm the joint follows one diagonal seam.
3. Repeat with 4 and 8 segments. The old overlapping slivers should be
   absent because there is no independent corner patch.
4. Check File's operation count. Fabrication should report
   `1 corner miters` for a matched pair.
5. Reverse the order in which the two edges are filed, then verify the
   same joined result.
6. Disable either operation. The other File returns to its ordinary
   uncoupled end geometry.
7. File an unrelated convex corner. No miter is created.
8. Verify sketching, Drill, Inset and other non-File operations still
   compile normally.

`scripts/VERIFY_CORNER_TRIANGLE.lua` now checks all segment counts 1–12
and both endpoint orientations for equal shared seam vertex coordinates,
planar strips, and rejected mismatched pairings.

The projection geometry was checked numerically against an L-corner
model outside Studio. The Roblox CSG Boolean result and the Studio
Command Bar regression **have not been executed in this session**.

### Known limitations

This is a special-case direct miter for two matching exterior straight
File edges at a concave right-angle vertex. It is not a general B-rep
fillet solver, multi-edge corner solver, or variable-radius fillet.
Two CSG subtract operations still occur—one per File—but their cutter
end-caps now coincide exactly rather than overlapping a third patch.
Roblox may still require additional tolerance handling at coplanar seams.
