# FORM — Clipped Interior Bevels / Shared Corner Geometry

Updated: 2026-11-04 · Branch `dev` · Studio validation pending

## Why the previous junction attempt was wrong

The first junction approach used a **second subtractive Boolean** after
unioning an entire vertical inside bevel. It tried to guess an extension of
the two outside bevels into the filled area. In Studio that made the
corner *worse*, with a bigger box/protrusion. This approach is removed.

**Correct invariant:** Never union material in a region already removed
by an adjoining outside bevel.

## Current implementation

`BevelJunction.lua` defines **matching neighboring bevel planes** from
the *actual authored FileMesh/File features*. An inside and outside bevel
qualify only if:

- their original edges share a real endpoint (6 mm precision in studs);
- they share one matching outward wall normal;
- the non-shared exterior normal points toward the end of the inside
  (vertical) edge (top or bottom);
- the exterior edge points outward along the *other* concave wall;
- the outside edge is long enough to cover the entire inside-wedge width.

Each matching outside bevel yields a halfspace of material that may remain:

`(wallNormal + capNormal) · (position - corner) <= -outsideWidth`.

The `GeometryCutter.file` pathway now starts from the inside bevel's
normal triangular prism, **clips the convex polyhedron against every
matching halfspace**, triangulates the closed clipped volume, creates one
temporary MeshPart, and only THEN uses `GeometryService:UnionAsync`.

There is **no additional post-union junction CSG operation**. If an
inside bevel is created first, it is still pre-clipped using the full
enabled feature history, so later outside bevels can be added without
reintroducing boxed-off material. The whole part is recompiled after
history edits.

### Numeric L-corner example

At a vertical concave corner `x=z=0` with a top surface `y=1`,
an inside bevel width `0.20` and two upper outside bevels of width
`0.12` produce these clipping planes:

```
x + y <= 0.88
z + y <= 0.88
```

At the center of the inside chamfer `x=z=0.10`, the top of its newly
added wedge is `y=0.78` — **not** `y=1`. The bottom edges yield the
matching inverted limits.

This removes the mathematical source of the boxed cap: the inside
wedge simply never adds that upper/lower corner material.

## Shared selection topology

`HistoryTopology.lua` uses `GeometryCutter.fileFaces`, which runs the
**same pure polyhedron clipping** used to manufacture the temporary
mesh. It retires the original sharp edge, identifies the resulting
diagonal bevel face and top/bottom clipping faces, then connects their
newly formed trim edges to their adjacent planar surfaces. It no longer
guesses a separate bevel-junction face from unrelated points.

CSG mesh readback remains unsupported in this setup, so selection
still uses feature history plus camera/physics hit-testing.
The face model is not a full B-rep and cannot describe arbitrary
imported mesh topology.

## Test before treating this as fixed

Paste `scripts/VERIFY_BEVEL_JUNCTION.lua` into Roblox Studio Command
Bar after Rojo sync. This checks matching L corner planes, clipped
vertex positions, convex polyhedron manifoldness (every edge belongs to
two faces), and rejection of unrelated exterior edges.

Then test the actual CSG visual result:

1. Start a **fresh** L-shaped solid.
2. File both exterior top edges leading into its inside corner.
3. File the entire vertical inside edge. Watch the top junction for the
   former box; it should become joined sloped geometry.
4. Repeat with lower outside edges and inspect both corner ends.
5. Hover new bevel trim edges. The original sharp edge should no longer
   highlight; actual new boundaries should.
6. Disable and re-enable each File operation. The new surfaces and
   selection topology must follow the enabled feature history.
7. Reverse operation order (inside bevel first, then exterior edges).
   This should generate the same final solid.
8. Test an unrelated File on an exterior corner. It must not affect the
   inside bevel geometry.

### Limitations

- This is a limited straight 90-degree inside/outside bevel pairing,
  not a general N-way fillet/chamfer solver.
- It does not resolve every three-way bevel corner, and complex
  intersections with independent drill/Inset/Saw operations still need
  a stronger feature topology system.
- Temporary EditableMesh buffers are needed for the new *clipped cutter
  volume*, but never to read back compiled CSG.
- **The geometry was checked numerically with sample L-corner planes;
  the changed Roblox CSG pipeline has not been executed in Studio from
  this conversation.** If the Boolean fails it must report a visible
  error, not silently apply a fallback patch.
