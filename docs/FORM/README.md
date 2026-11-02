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

## OPENWORKS machinist sandbox — end-to-end prototype

The working machining API is `FORM/Machine.lua`, backed by the convex-component Boolean kernel and `Union.reconstruct` for watertight boundary rendering.

```lua
local Machine = require(ReplicatedStorage.Openworks.FORM.Machine)
local FORM = require(ReplicatedStorage.Openworks.FORM)

local workpiece = Machine.new(FORM.box(Vector3.new(100, 50, 40)))

local ok, removed = workpiece:apply({
    kind = 'drill',
    center = Vector3.zero,
    radius = 7,
    height = 70,
    segments = 12,
})

if ok then
    local mesh, reason, stats = workpiece:mesh()
    if mesh then
        print('Watertight result:', #mesh.triangles, FORM.signedVolume(mesh))
    else
        warn('Unified surface not valid:', reason)
    end
end
```

### Operations

- `drill`: center, radius, cutter height, polygon segment count (3–64), optional CFrame. The drill axis is local Y; center denotes the tool center. To make a blind hole, choose a center and height that only partially intersect the workpiece.
- `pocket`: center, size (Vector3), optional CFrame for a rectangular cutter.
- `slot`: from and to (Vector3, constant Y), radius, height, and segment count; a straight cutter sweep assembled from one box and two polygonal cylinders.
- `profile`: points (2–9 Vector3 coordinates at constant Y), radius, height and segment count; chains straight slot sweeps, up to 24 component cutters.
- `saw`: point and outward normal; keeps the negative side of the plane.
- `chamfer`: axisA/axisB (`X`, `Y`, `Z`), signA/signB (+1 or -1), distance; removes a 45-degree corner wedge along an exterior box-aligned edge.
- `fillet`: axisA/axisB, signA/signB, radius and segments (2–24); approximates an outer convex edge roundover by successive tangent-plane cuts. This is **faceted rounding**, not mathematically exact toroidal/analytic filleting.

Operations are **atomic** at the workpiece level. On rejection, neither the current geometry nor the operation history changes. `machine:undo()`, `machine:redo()`, `machine:reset()` and `machine:status()` are available. The immutable sequence of convex-piece states is the editable source of truth. The reconstructed surface is only an output representation, not the canonical editable topology.

### Interactive Studio demo

The client starts with a drilled plate and opens a machining controls panel. Use **1** for a second drill, **2** for a blind pocket, **3** for a rounded slot, **4** for a chamfer, **5** for a faceted fillet, **6** for a saw cut, **7** for a multi-segment milling sweep, **Z** undo, **Y** redo and **R** reset. Equivalent buttons are displayed. Only one EditableMesh/MeshPart preview is retained at a time; the previous pair is destroyed before rerendering. If manifold reconstruction fails, the preview renders the full convex-component geometry instead of dropping exterior triangles.

Server regression tests include `FORMTests.server.lua` and `MachineTests.server.lua`. The former verifies foundational cuts, adjacent-box union, rectangular slot and 14-mm drilled hole; the latter verifies machining, history, failure atomicity, genus checks and volume.

### Honest operating envelope

This is a reusable **engineering and fabrication prototype**, not a production universal CAD solver. It supports subtraction by **convex** cutter components, planar half-space removal and polygonal cylindrical tools, with bounded fragment counts (192), cutter count per operation (24) and history length (64). Curved geometry is tessellated. Fillets and chamfers in this phase target **axis-aligned convex exterior edges**, not arbitrary B-rep edge loops. Complex operations can still fail numerical or manifold validation; this is an explicit error, never a license to silently ignore invalid geometry. Roblox Vector3 values remain the current canonical vertex coordinates. Operations run locally in the Studio/client demonstration; server authority, persistence, physics-driven cutter motion, arbitrary non-convex cutter support, true analytic NURBS and arbitrary edge fillets are **not** implemented.

**Verification:** changes pushed to dev; Roblox Studio test outcome remains pending and must be checked from actual Output logs.

## Reconstruction stabilization — November 2026

The first integrated 0.8 Studio run failed: the rectangular cut produced 18 non-manifold edges and 7 residual T-junctions; the drilled cut caused 21,024 iterative edge splits, 1,338 residual junctions, and server/client script timeouts.

The follow-up repair replaces the unstable piece-by-piece polygon subtraction with a **global supporting-plane arrangement**. Every source face is divided using the same unique planes before testing whether an outward probe falls inside another retained convex component. That preserves the actual exposed boundary and produces matching surface segments at shared intersections.

`Weld.build` now spatially welds vertices and performs **one** conforming edge subdivision pass. It no longer recursively splits triangles up to 64 times. A CPU budget and explicit limits on candidate vertex scans, faces, repairs, planes, and cells prevent pathological examples from monopolizing Studio. Exceeding a limit is reported as a failed unification; the client continues displaying the convex-component fallback.

Independent Python reference geometry checks of the arrangement algorithm (with Vector3-like float32 quantization) produced the following outcomes:

| Input | Triangle count | Edge incidence | Winding defects | Euler | Reconstructed volume |
|---|---:|---|---:|---:|---:|
| Two adjacent boxes | 20 | all edges twice | 0 | 2 | 12,000 mm^3 |
| Rectangular through-slot | 64 | all edges twice | 0 | 0 | 84,000 mm^3 |
| 12-sided 14-mm drilled hole, 100x50x20 stock | 296 | all edges twice | 0 | 0 | approximately 92,650 mm^3 |

**Important:** the reference validation is not the Roblox Studio runtime. The new Luau modules must still pass the actual `FORMTests.server.lua` and `MachineTests.server.lua` suites. Their failures are authoritative and should be investigated rather than bypassed.

## Direct stock-and-cutter reconstruction (post-Studio failure repair)

The 21:54–21:56 Studio run reported that *intermediate cutting was materially correct* while both rectangular and drilled fragment unions still failed manifold validation. It also exposed false `VOLUME_MISMATCH` rejection for 0.0005–0.0013 mm³ intermediate rounding drift, zero-removal operations being committed, and planar face grouping failures on some edge-finished pieces.

The active `Machine:mesh()` implementation now **reconstructs the output surface from the original stock plus the saved convex cutter solids for all applied operations**, rather than trying to assemble a manifold from the residual convex fragments. `Union.fromStockAndCutters(stock, cutters, expectedVolume)` subtracts each cutter from the exterior stock polygons and adds inward-facing cutter surfaces clipped to the stock and other cutters. This supports overlapping cutters and multiple machining operations while retaining the convex-fragment workpiece for authoritative volume calculations and history.

The single-tool `Union.subtractBoundary(stock, cutter, expectedVolume)` API is used by strict rectangular and drill tests. Edge conformity and volume validation are still required before returning a surface. An invalid result explicitly returns a reason and detailed stats; the Studio client preserves the complete convex-piece fallback preview.

`Machine:apply()` now rejects `NO_MATERIAL_REMOVED` without advancing history. Stored historical cutter shapes are committed atomically with geometry states, and undo/redo rebuilds with only cutters applied at the current cursor. Saw/chamfer/faceted-fillet half-space operations are also recorded as bounded tool volumes encompassing the original stock. Cut volume tolerance scales with solid volume, capped at 0.002 mm³ for small/intermediate solids, without disabling final stock-volume checks.

**Independent geometry reference results (not Roblox runtime):** A corresponding float32-quantized stock-minus-cutters implementation passes edge closure, correct winding/positive volume, and Euler checks for the 100×50×40 mm workpiece with (1) a through-hole, (2) that hole plus a blind pocket, and (3) both plus a rounded through-slot. Reconstructed meshes contain 156, 270, and 826 triangles, respectively, with expected volume 192650, 190090, and 184240 mm³ and Euler 0, 0, −2. Those reference tests support the design; Studio's Luau results are still unverified.

The older `Union.reconstruct(pieces)` remains a bounded experimental convex-fragment union used for adjacent-block diagnostics. The machining workbench no longer depends on it. This is a geometry prototype with explicit budgets, not an unrestricted analytic CAD solver.

## Repeated-machining convexity lineage guard

The 22:10 Studio run passed rectangular and drilled unified boundary tests. MachineTests also passed drilling and blind-pocket removal but failed on the next slot cutter: a convex fragment produced by FORM's earlier clipping reported a 0.002752123 mm triangle-plane deviation despite its construction by successive convex half-space intersections.

`Cut.split` now retains a module-private, weak-keyed provenance registry for pieces that came from *successful, topology-checked, volume-conserving* planar splits. For these generated pieces only, an additional maximum propagated convexity drift of 0.01 mm is allowed. Arbitrary user-supplied/non-convex solids still have to pass the original strict geometric convexity check. A lineage piece with excessive distortion fails with `CONVEX_LINEAGE_DRIFT` rather than silently continuing. The regression suite explicitly checks that a drilled non-convex manifold is not accepted as input to convex splitting, in addition to the drill → pocket → slot sequence.

This is a **bounded float32 geometry workaround**, not exact convex arithmetic. If accumulated drift routinely approaches 0.01 mm, the correct next architectural change is a high-precision canonical geometry representation rather than further widening tolerances.

**Runtime verification:** the lineage patch has been committed but has not yet been tested in Roblox Studio.

## Studio integration: combined operations now validated; direct convex finishing

The 22:21 Studio run established successful **runtime** results (not just reference checks) for 12-sided through drilling, a blind rectangular pocket, a rounded through-slot, the combined 796-triangle workpiece (Euler -2), a saw cut after undo, and the 45-degree chamfer (Euler 2). The only remaining failure at that point was faceted fillet reconstruction: the fillet removed 168.0681 mm³, but rebuilding the exterior from overlapping large half-space proxy cutters resulted in 12 non-manifold edges and 12 bowtie vertices.

`Machine:mesh()` now uses the **validated native convex-piece mesh directly** whenever a machining state consists of exactly one convex piece with matching volume and Euler characteristic 2. This avoids an unnecessary second Boolean representation of a filleted or chamfered solid. Multiple-piece machined models continue using the original-stock-plus-cutter-history reconstruction pipeline. Regression tests require both chamfer and fillet to select this direct mesh path.

**Verification:** direct convex fast path committed, but its Roblox Studio runtime test has not yet been run. Previous Studio results remain authoritative for the earlier completed operations.
