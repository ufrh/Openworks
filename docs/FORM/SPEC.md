# FORM — Solid modeling specification (Draft 0.1)

Status: **design contract**, not a claim of implemented behavior.

## Mission and boundaries

FORM models geometry and solid topology for Openworks. It must not know about players, tools, currencies, inventory, materials, physics constraints, or Roblox replication. Manufacturing translates tool motion into geometry operations; mechanics consumes mass/inertia derived from geometry and material properties elsewhere.

EditableMesh is a **rendering/export adapter**, not canonical state. Never use triangle counts or visual collision proxies as engineering measurement sources.

## Units and coordinate spaces

- Canonical length: **millimeters** (mm). Stored as finite Luau numbers; no requirement that 1 mm = 1 stud.
- Canonical area: mm²; volume: mm³; angles: radians; transforms: CFrame with translation numerically interpreted as millimeters **inside the kernel only**.
- Kernel uses right-handed local/model coordinates, with explicit winding convention validated by signed volume. Conversion to Roblox world studs happens in a dedicated adapter.
- A Solid has one local coordinate space. Transforms position solids in an Assembly, without rewriting vertices for ordinary movement.
- Unit conversion belongs at adapter boundaries. No rounded millimeter values in canonical calculations.

## Data model

- Vertex: unique stable identity + finite 3D position.
- Half-edge: directed edge with origin vertex, next, face, and optional opposite twin; supports boundary detection.
- Face: oriented polygon loop with optional inner loops; triangulation is generated, not authoritative.
- Shell: connected oriented faces. Outer shells enclose filled space; inner shells bound cavities.
- Solid: one or more disjoint closed shells with geometric orientation and manifold validity; disconnected islands may be normalized into separate Solids after cutting.
- Body/Workpiece: game-side identity, material and history; **not** a FORM Solid.
- Feature provenance: optional references to created surfaces/operations, not a guaranteed persistent face index.

Initial v0.1 implementation MAY use a validated **closed oriented triangle mesh with computed edge adjacency**, instead of persistent half-edges. Upgrade only when operations warrant it. A triangle mesh cannot automatically perform robust CAD B-rep booleans.

## Validity rules

A valid closed orientable manifold solid:
1. Has only finite coordinates and nondegenerate faces.
2. Has coherent face winding; each interior undirected edge has exactly two oppositely directed incidences.
3. Has no open boundaries, non-manifold edges, self-intersections, or crossing shell boundaries.
4. Has consistently oriented outer shells and cavity shells.
5. Computes positive material volume after cavities are accounted for.
6. May contain multiple disconnected components, which are explicitly enumerated.

Passing the two-faces-per-edge check is **necessary but not sufficient** for a valid solid. Check intersecting triangles, duplicated/coincident surfaces, and shell nesting separately.

## Numerical robustness

- All geometric predicates use a **named tolerance policy**, not scattered hard-coded epsilons.
- Distinguish absolute model-distance threshold (mm), relative threshold based on feature size, and angular/coplanarity thresholds.
- Initial trial values: absolute 1e-6 mm and relative 1e-9, **provisional** pending scale/conditioning tests. These are algorithmic safeguards, NOT machining tolerances or promises of accuracy.
- Do not silently snap intentional near-fit geometry or interpret a 0.01 mm gap as floating-point noise.
- Predicates near zero should return `ambiguous` or invoke a robust fallback instead of fabricating topology.
- Constrain maximum coordinate extents and minimum supported feature size after profiling; not specified yet.
- Operation failure must be explicit and atomic: no partially committed invalid solid.

## Initial public operations (design, not implemented)

- `primitives.box(sizeMm)` => valid closed Solid; later cylinder, tube, profile extrusion.
- `inspect.bounds(solid)`, `inspect.signedVolume(solid)`, `inspect.components(solid)`.
- `validate(solid)` => structured issues and tested invariants.
- `split.byPlane(solid, plane)` => two or more closed Solids + removed kerf region if requested.
- `boolean.subtract(a,b)`, `boolean.union(a,b)`, `boolean.intersect(a,b)` (later).
- `bevel.edges(solid, selection, profile)` (later).
- `deform.region(solid, field, constraints)` (later).
- `triangulate(solid)` => triangles appropriate for rendering; preserves geometry semantics through provenance where possible.

No operation should require Roblox Instances. No part of FORM should perform direct server/client RemoteEvent communication.

## Operation protocol

Every operation:
- Accepts immutable input geometry, typed parameters, coordinate-space metadata, and tolerance policy.
- Validates finite input values and manifold prerequisites.
- Returns new geometry + structured diagnostics + stable operation ID; failures leave prior state untouched.
- Can be serialized in a versioned **operation record** for client reconstruction, but records must not blindly trust arbitrary user-supplied geometry.
- Has pre/post-conditions, time/memory budgets, and deterministic ordering rules.

FORM does not independently certify security. The server must validate authoritative state and permitted changes; clients may produce previews and render locally.

## Rendering and physics adapters

- Client adapter maps canonical mesh to EditableMesh / MeshPart within Roblox API permissions and memory limits.
- Avoid assumptions that EditableMesh edits replicate automatically.
- Normals, UVs, smoothing, material visuals and triangulation are output concerns.
- Collision may be a simplified regenerated approximation: DO NOT equate collision fidelity to manufacturing dimensional accuracy.
- Mechanical simulation consumes fitted dimensions and analytical or computed mass properties; it need not collision-simulate microscopic threads or gear teeth.

## Explicit non-goals for FORM 0.1

Real-time voxel destruction; arbitrary smooth NURBS CAD; perfect floating-point boolean robustness; force-based material simulation; full Blender-style modifier stacks; network replication; game economy.

## Outstanding decisions requiring validation

- Which topology structure is best for arbitrary repeated cuts.
- Robust predicate/fallback algorithm strategy.
- Maximum practical solid complexity and feature resolution on target devices.
- Compact, deterministic operation serialization.
- Handling concave shells and arbitrary shell nesting.
