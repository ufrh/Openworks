# FORM Compiled Surface Selection — First Pass

**Branch:** `dev`  
**Date:** 2026-11-04  
**Status:** Implemented in source. Roblox Studio smoke test still required.

## Goal
Select actual faces and mechanical crease edges on the *latest compiled part*
instead of deriving all fabrication interactions from the four outer edges
or the upper surface of the original rectangular stock.

## Architecture
- `SurfaceTopology.lua`: reads the current CSG `MeshPart.MeshContent`
  into a **temporary** read-only `EditableMesh`. Welds coincident mesh
  vertex positions, connects coplanar triangles into logical planar faces,
  identifies hard face-boundary edges, and merges collinear edge fragments
  where possible. The EditableMesh is destroyed immediately after indexing.
- `SurfacePicker.lua`: indexes only when a preview solid is replaced;
  caches by actual BasePart instance, handles async/stale completion, and
  surfaces permission/memory/read errors. Native Block surfaces are
  reconstructed analytically from that rendered Part, not from the
  uncut Document envelope. A native Cylinder does not yet offer full
  crease-edge extraction.
- `FaceTools.lua`: boundary loops and precision planar offsets for
  **single-loop convex faces**. Unsupported concave/multi-loop/holed
  faces return an error instead of silently cutting the wrong rectangle.
- `GeometryCutter.lua`: disposable watertight extrusion geometry for
  arbitrary selected crease edges and planar face contours. Geometry is
  stored in the selected body's local coordinates as parametric history
  and replayed through the existing CSG compiler.
- No EditableMesh allocation in RenderStepped or hover. No mesh body
  changes until a feature is clicked and committed.

## Tool behavior
**File Edge** targets a real compiled crease segment. The hovered edge is
lit in cyan; on click it stores edge endpoints and its two adjacent face
normals. `FileMesh` creates a triangular-prism 45°-style chamfer cutter
aligned to those faces. Straight sharp edges are supported; rounded fillet
blending and topological naming after upstream edits are not yet supported.

**Inset / Pocket** selects a real connected planar face. The preview traces
the offset perimeter. Click to create a blind, inwardly extruded pocket in
`InsetFace`. One convex boundary only. Complex top faces with holes,
concave boundaries, or fillets need a dedicated polygon-offset kernel.
The prior `Inset` (stock rectangle) remains readable for historical parts
but new UI clicks create `InsetFace`.

**Drill** targets any indexed planar manufactured face, with its barrel
aligned to the chosen face normal. The existing 2 mm mouse-wheel diameter
increment, blind depth and through modes remain. New operations are recorded
as `DrillFace`. A planar side face is valid; arbitrary curved cylinder
walls are not yet selectable as logical planar faces.

**Groove / Straight Kerf** now use two points on the same selected planar
surface, oriented by its normal. Groove is blind by depth; Kerf cuts through.
The latest operations are `GrooveFace`. The original straight Saw/Groove
history entries still compile for compatibility.

**Saw (Profile)** retains its existing closed-polygon sketch editor on the
stock's top construction plane. Fully arbitrary sketch plane orientation,
concave face offsets and curved surface projection are separate work.

## What to test
1. Create a Block, select File Edge, hover each of its 12 sharp edges,
   including *bottom and vertical* edges. It must highlight the actual
   selected edge, then commit a chamfer.
2. Use New Body Sketch to create an L-shaped or concave-profile object.
   Once CSG finishes compiling/indexing, file a *new edge that did not
   exist on the source block*. Test the edge after drilling and pocketing.
3. Select a broad flat face (preferably without holes), set an Inset border
   and depth, and click. The inset should follow that face's own contour,
   not the source rectangle. Concave and holed faces should reject clearly.
4. Drill a hole on a vertical side face. Scroll changes diameter; blind
   depth follows the inward normal. Test Through from a side face too.
5. Draw Groove endpoints on a vertical face. Verify a shallow channel;
   repeat with Straight Kerf and verify a through slot.
6. Move or rotate an already fabricated part: the picker must follow
   current preview positions. Make a further cut and ensure the
   selection cache is rebuilt on the new CSG result.
7. Toggle/deactivate/reorder prior history operations and check that
   selected-surface features either recompile or clearly fail, rather than
   silently cutting another surface.
8. Watch the FORM status text. If `CreateEditableMeshAsync` fails due
   to CSG `MeshContent` access, permissions or memory, the surface
   index should say so instead of reverting to stock-based picking.

## Important limitations
- This is an experimental topology reconstruction, not a stable B-rep CAD
  kernel. Surface IDs are *not* guaranteed to persist after upstream CSG
  changes; the chosen local feature geometry is stored at commit time.
- CSG mesh read permissions and memory budgets can prevent selection.
  No successful Roblox Studio test has been run from this conversation.
- `GeometryService` Boolean results can fail on small, thin or intricate
  cutter volumes; the Editor reports failures.
- Face offset is currently **convex polygon / one boundary loop only**;
  circle holes, concave loops and connected islands are intentionally not
  treated as simple faces for inset.
- File acts on *straight, sharp* edge segments and currently uses a planar
  bevel rather than a rounded freeform file or fillet.
- Circular and smooth curved surfaces are not yet a logical CAD surface
  type; triangle boundary selection is not equivalent to curved-edge CAD.
- Sketch / profile Saw still uses its top-aligned construction plane.
- Preview is local only; assembly/warehouse shipping is not part of
  this implementation.
