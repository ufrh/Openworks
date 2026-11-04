# FORM Sketch → Extrude prototype

Branch: `dev` in `ufrh/Openworks`.

## Goals

Build custom solids and remove or add arbitrary polygonal material through Roblox CSG.
The *authoritative document* stores sketches and operation parameters, **not**
EditableMesh assets. Meshes exist only while the compiler is processing a
feature. Material transforms do not recompile unchanged geometry.

## UI / controls

The temporary left FORM debug panel contains:

- **New Body Sketch** — draw directly on the global X/Z grid at Y = 0, with
  snapping at 0.05 studs. Draw an outline then extrude to make a workpiece.
- **Sketch / Extrude** — sketch on the top face of a selected workpiece. The
  sketch uses that workpiece's local X/Z plane and follows its rotation.
- The separate right-side **FORM / PROFILE SKETCH** panel has
  Add / Remove / Intersect (existing workpiece), depth in millimeters,
  Through switch (Remove only), Undo Vertex, Close Profile and Commit.
- **Left click:** add a point. **Enter:** close polygon. Clicking near the first
  vertex also closes. **Backspace:** undo point or reopen a closed outline.
  **Escape:** exit the sketch.
- A 0.1-stud local grid is displayed over the selected workpiece's top face.
  The preview shows the snapped edges; after closing it shows the extrusion
  boundaries and depth in 3D. Editing / snapping coordinates remain 0.05 studs.
- The left panel **FEATURE HISTORY** lists the six newest fabrication features,
  with ON/OFF toggles and individual X (delete). Undo Last Cut also works.

Both modes share a 64-point maximum for each polygon. Straight edges and
concave polygon outlines are supported. Holes *inside* a single sketch, arcs,
curves, and fully parametric 2D constraints are **not yet implemented**. A
circular hole remains available from the Drill tool.

### Boolean operations

- **Add:** extrude the profile upward from the top face, overlapping the
  workpiece by a small margin so UnionAsync has a connected volume.
- **Remove:** extrude down, either to a user-specified blind depth or through
  the entire source workpiece.
- **Intersect:** retain material inside the extruded profile.
- **New Body:** compute the sketch's overall bounds; create a native bounding
  Block with minimum corner on the snapped grid; intersect it against the
  full-height profile extrusion to produce the sketched silhouette.

All CSG uses GeometryService with `SplitApart = false`. Current implementation
expects one result body. Split bodies and free disconnected Union bodies need
a separate explicit workflow later.

## Geometry backend

1. `SketchProfile.prepare` validates point count, finite coordinates, zero-length
   edges, overlaps / self-intersections and area; removes redundant collinear
   points and normalizes winding to positive signed X/Z area.
2. Ear clipping triangulates concave simple polygons.
3. `Extrusion.create` builds a watertight manifold: two caps with opposing
   triangle winding plus two triangles per polygon side. Geometry is built
   around its bounding-box center in material-local space.
4. `AssetService:CreateEditableMesh()` allocates the temporary object.
5. `AssetService:CreateMeshPartAsync(Content.fromObject(editable))` provides
   the cutter/addend to GeometryService.
6. `SubtractAsync`, `UnionAsync`, or `IntersectAsync` returns new geometry.
7. The temporary MeshPart and EditableMesh are destroyed on **success or error**;
   only the finished CSG result stays in the preview.
8. `Fabricator.compile` serializes compiler runs to limit simultaneous
   temporary EditableMesh allocations across components.
9. `Document` retains operation type, polygon points, depth, mode, and enabled
   state. A changed operation rebuilds via ordered replay. Features can be
   disabled or removed, with the current model rebuilt.

Other existing features remain: Drill, straight Saw, 0.05 snap, smooth
transform visuals, Blender-style camera, and original colored gizmo controls.

## In-Studio smoke test checklist

- With **no selected material**, select New Body Sketch. Draw an L-shaped
  six-point polygon, click the first point (or Enter), set depth to 56 mm,
  and commit. Verify it creates an L-shaped solid with bottom at world Y = 0,
  not a rectangle. Verify a MeshPart or PartOperation is present in preview.
- Create a Block. Pick Sketch / Extrude. Draw a triangle on its top face,
  choose Remove and Through, then commit. Inspect the opening from below.
- Undo, then try a blind Remove at 28 mm; verify the bottom is not pierced.
- Sketch a narrow rectangle on the edge, choose Add and depth 56 mm. Verify a
  protrusion appears on the top and is connected to the base.
- Choose Intersect with a smaller polygon inside a block; verify only the
  intersection remains.
- Try an inward notch or concave sketch. Verify it triangulates without
  filling the notch.
- Draw a bow-tie self-intersecting polygon: Close Profile should reject it.
- Toggle a history feature OFF and ON; delete one middle feature, verifying
  CSG recompiles without rewriting the surviving history.
- Change workpiece size after adding a sketch feature; polygon coordinates
  should remain anchored to the minimum X/Z material boundaries.
- During rapid edits, inspect status and memory. The compiler must not retain
  the temporary EditableMeshes after CSG finishes.

## Expected limits and blockers

- This is a client-only prototype: no shipping, persistence or replication yet.
- Roblox EditableMesh APIs and mesh-based CSG may need current permissions,
  published-experience settings and the Solid Modeling On Meshes beta in Studio.
- Out-of-budget creation and invalid mesh CSG return explicit errors. **Unlike a
  straight saw cut, an arbitrary concave profile has no equivalent native-Part
  fallback**, so FORM must not silently replace it with a bounding rectangle.
- 64 vertices is a prototype safety cap, not a CSG guarantee. Some valid
  profiles may still fail the engine's geometry limits or numeric tolerances.
- CSG operations are asynchronous; compilation is intentionally performed
  on commit and subsequent history changes, not every mouse movement.
- No in-engine playtest was possible during implementation. Verify these
  workflows in Studio and report the first runtime error before extending.

## Files

- `src/shared/FORM/SketchProfile.lua` — validation and triangulation
- `src/shared/FORM/Extrusion.lua` — disposable generated extruded solid
- `src/shared/FORM/Document.lua` — editable feature history and edge anchors
- `src/shared/FORM/Fabricator.lua` — serialized CSG replay
- `src/client/SketchEditor.lua` — interactive sketch UI and 3D wireframe
- `src/client/FORMDebug.lua` — tool integration, standalone body creation
- `src/client/Preview.lua` — asynchronous render replacement
