# FORM verification plan

All tests must run without Roblox gameplay, with separate Studio integration tests for EditableMesh.

## First acceptance gate

1. Box(100,50,20) has expected bounds and volume 100000 mm³.
2. Valid box has 8 unique corner positions, 12 surface triangles if triangulated conventionally, no open edges, and consistent oriented volume.
3. Planar split through box interior produces closed positive-volume outputs.
4. Sum of output volumes matches original within the named numerical policy (zero-kerf split).
5. Oblique cut caps are planar, correctly wound, and manifold.
6. Outside plane yields one unchanged solid + empty other result without invalid geometry.
7. Coplanar, tangent, vertex-touching, edge-touching and near-tolerance cuts produce explicit defined results; no cracks or NaN.
8. Repeated split sequences preserve validity and bounded volume discrepancy.
9. Input geometry is not mutated by successful or failed operations.
10. Fixed seeded randomized boxes/planes should reproduce the same topology and measures.

## Future gates

- Holes and subtractive booleans: cavity orientation; multiple shells; grazing intersections.
- Bevels: multi-edge corners, concave edges, overlaps and tiny features.
- Deformation: no inversion; thickness/volume constraints where applicable.
- Geometry export: visual normals, correct scaling and collision consistency.
- Performance: fixed workpiece complexity budgets, peak memory, client rehydration time, operation log growth.

A test that checks only triangle count or only edge incidence is insufficient to assert a valid solid.

## v0.1 smoke test coverage (not Studio-verified)

Centered box: 8 vertices, 12 triangles, correct bounds and volume. Reversed triangle and missing triangle should fail basic edge checks. This is not yet full solid manifold validation.
