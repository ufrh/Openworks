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
