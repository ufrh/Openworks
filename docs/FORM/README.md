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
