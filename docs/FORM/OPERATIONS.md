# Operation contracts

## Planar split (first target)

Input: a validated solid in local mm coordinates and a plane specified by point and normalized normal. An optional kerf thickness >=0 represents removed material rather than a zero-thickness separation.

Output: validated closed positive-volume connected components on either side plus a nonnegative removed volume when kerf>0. Output component order is deterministic.

Algorithm outline: classify vertices robustly; clip intersected faces; construct intersection loops; triangulate cap faces with consistent winding; split disconnected shells; validate results; rollback on failure.

Complex cases (concave intersections, holes in cap loops, coincident faces) must be detected and either supported correctly or rejected with diagnostics. Do not silently drop geometry.

## Material removal (future)

Consume an explicitly defined swept tool volume, produce new valid material geometry, and report removed volume. Manufacturing is responsible for deciding whether the tool motion could remove that material.

## Bevel (future)

Require selected topological edges and profile/width; reject widths that cannot fit without violating constraints rather than generating inverted faces.

## Deform (future)

Take a displacement/transform field and fixed-region constraints, regenerate valid surface geometry, and report any invalid inverted or overlapping result.
