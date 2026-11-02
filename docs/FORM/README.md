# FORM

Custom solid modeling kernel for OPENWORKS.

## Implemented prototypes

- `FORM.box(Vector3)`: centered triangular boundary mesh in millimeters.
- `FORM.bounds(solid)` and `FORM.signedVolume(solid)`.
- `FORM.validate(solid)`: basic edge incidence, winding and signed-volume checks, **not** a complete manifold/self-intersection validator.
- `Cut.split(solid, point, normal)`: convex solid planar split, including intersected existing vertices and edges. Tangent cuts return `nil, 'PLANE_DOES_NOT_INTERSECT'`.
- `Boolean.subtract(stock, tool)`: convex stock minus a convex tool, using a sequence of plane cuts. Returns **an array of independent convex solid pieces** and removed volume, not a welded manifold with a single cavity shell.
- `FORMRenderer`: EditableMesh output with angle-based face-corner normals.
- Studio smoke/regression tests live in `src/server/FORMTests.server.lua`.

## Preview

Client playtest demonstrates a rectangular through-opening. Press `[` to reduce exploded separation, `]` to increase it and `0` to fit pieces together.

## Limitations

Both operands must currently be convex. The subtraction method produces a collection of convex solids, potentially with internal coincident seams; it **does not** implement general mesh CSG, boolean union, cylindrical cuts, merged through-hole topology, bevels, or fabrication simulation. It is an experimental algorithm with finite precision, not a production CAD kernel.

The new coincident-cut and subtraction tests have **not yet been confirmed passing in Roblox Studio**. Never infer correctness from visual appearance alone.

See SPEC.md, OPERATIONS.md and TEST_PLAN.md for the full target design.

## FORM 0.7 — surface extraction prototype

`Surface.extract(pieces)` filters triangles whose outward side appears to be inside another convex piece. It returns a renderable triangle soup and statistics for discarded faces and suspected partial overlaps. This reduces hidden internal surfaces in the single-EditableMesh preview.

This is **not a topology union**. It does not split partially overlapped faces, merge/weld common vertices, solve T-junctions, or validate one watertight manifold. A triangle-centroid visibility test can wrongly discard a partly exposed face; the result is diagnostic and visual only, not suitable for canonical manufacturing geometry or authoritative volume calculations. Volume is still determined from the original retained convex pieces.

Full unification requires intersection-aware face subdivision, surface classification, vertex welding, and manifold verification. The server tests report surface counts but do not assert manifold closure.

## FORM 0.8 — intersection-aware surface prototype

`Union.surface(pieces)` clips each convex piece's face polygons against neighboring convex volumes instead of discarding an entire triangle based on its midpoint. Its output is an **unwelded rendering triangle soup** with subdivision statistics.

The algorithm is deliberately not used in the active preview yet. It must be verified for numerical stability, matching seams, T-junctions, coincident exterior faces, and watertightness before replacing the complete-piece rendering.

The current test runs it against the rectangular subtraction and reports triangle counts. It **does not** claim validated unified topology. Next milestone: stitch and weld subdivisions consistently, prove edge incidence and volume, then enable the preview. The code has not yet been playtested in Studio.

## FORM 0.8 — weld and topology diagnostics

`Weld.build(surface, tolerance)` deduplicates near-coincident vertex positions using neighboring spatial buckets, remaps faces, detects collapsed/duplicate triangles and checks for vertices lying along unsplit mesh edges (T-junctions). It runs `FORM.validate` on the resulting indexed mesh.

The rectangular subtraction test now prints weld statistics. Only when these checks pass does it assert reconstructed signed volume against the convex piece total. The drilled preview remains unchanged.

**This is not complete topology unification**: welding cannot substitute for conforming face subdivision, and the current validation does not prove absence of self-intersections or all non-manifold vertex configurations. A failed manifold report is a diagnostic, not a successful union. The updated tests have not been run in Studio yet.

## FORM 0.8 — unified topology acceptance pipeline

The 0.8 pipeline has been integrated into `Union.reconstruct(pieces, expectedVolume?, weldTolerance?)` and `Boolean.subtractUnified(stock, cutter)`:

1. Recover each convex piece's oriented planar polygons from its existing triangulation.
2. Subdivide polygons by clipping against neighboring convex volumes, retaining only exposed areas.
3. Triangulate exterior polygons, spatially weld coincident vertices, discard collapsed/duplicate triangles, and split T-junction edges.
4. Validate oriented two-face edge incidence, connected vertex fans, and zero remaining T-junctions.
5. Check signed volume against the sum of original convex pieces. Report connected components and Euler characteristic as additional diagnostics.

The server now includes strict tests for a joined pair of boxes (one component, Euler=2), a rectangular through-slot (one component, Euler=0), and a polygonal drilled hole (one component, Euler=0). It reports explicit failures instead of accepting a visually convincing mesh. The drilled test uses a 14 mm diameter 12-sided cutter through 20 mm-wide stock, avoiding a tangent/non-manifold boundary at the stock edges.

The client attempts the unified drilled mesh and renders the original complete convex fragments through one EditableMesh if reconstruction is rejected. The experimental `Surface.extract` centroid filter is no longer part of this path.

**Verification status:** implementation and regression tests committed; not yet executed in Roblox Studio. Independent reference geometry checks of analogous rectangular and 12-sided through-holes passed closed-edge and volume checks; these do not establish runtime correctness of the Luau code.

**Scope:** this joins the exterior boundary of an assembly of valid convex components. The Boolean cutter remains convex; this is not yet an unrestricted CAD B-rep or a proof against all geometric self-intersections, coplanar overlap degeneracies, pathological tiny features, or arbitrary repeated machining history. No claim is made of exact double-precision canonical geometry; FORM still uses Vector3.
