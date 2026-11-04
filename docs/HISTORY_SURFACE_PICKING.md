> **Further update:** The File tool now also marks vertical re-entrant corners from concave sketch profiles and the inverse corners of subtractive profile cuts. This classification comes from the authored polygon winding, not guessed mesh normals. Interior beveling uses a separate subtractive triangular-prism cutter, so its exact result still depends on Roblox CSG resolving that cutter. Test pocket floor-wall corners and concave L-shaped notches separately.

> **2026-11-04 editor refinement:** Fixed the click-time `pose` nil crash in FORMDebug. Inset now consumes a face's own polygon (instead of reconstructing the mixed adjacency edge graph), supports simple concave polygons with explicit self-intersection/containment rejection, and triangulates arbitrary simple inset contours before producing the CSG cutter. Faces containing drilled openings can be inset around their **outer boundary** while holes remain as existing CSG voids; independent inset borders around inner hole loops are not yet modeled. File now distinguishes exposed outer edges from **re-entrant pocket floor/wall corners**, generating a subtractive inner-corner cutter and labeling its preview. Studio validation remains necessary for the resulting CSG cuts.

# FORM: history-based surface selection (CSG readback workaround)

**Status:** Implemented in `dev`; Roblox Studio validation still required.

## Why the old picker failed

On the produced `MeshPart`, `AssetService:CreateEditableMeshAsync(part.MeshContent)`
returned `Failed to load mesh`. This is a runtime readback problem, not
evidence that the manufactured part is invalid. Some mesh content is readable
via EditableMesh, but FORM cannot depend on reading back arbitrary CSG
Boolean output. The built-in native Block worked because its faces were
analytically known.

## New architecture

`HistoryTopology.lua` constructs **candidate** planar faces and mechanical
crease edges from the source primitive and the ordered, enabled parametric
features in `Document`:
- Original Block faces (six faces / twelve edges); Cylinder cap/side
  approximations, explicitly marked curved
- SketchExtrude Add/Remove/Intersect, including irregular closed and concave
  polygon outlines, new top/bottom faces and vertical contour walls
- Drill/DrillFace hole opening and interior/floor candidates (32 segments;
  curved boundaries not available to straight-edge File)
- Inset/InsetFace pocket lip, floor, and side faces
- Saw/Groove/GrooveFace straight channel surfaces
- File/FileMesh new planar chamfer face candidates

Only local source geometry is stored: no EditableMesh is allocated for
surface selection and **no `CreateEditableMeshAsync` calls occur** in the
active SurfacePicker. `SurfacePicker` caches by the rendered part instance and
the fabrication geometry key, using a Document snapshot so async jobs cannot
mutate underfoot. Selection candidates are converted into the displayed
part's coordinate frame; moving/rotating bodies remains inexpensive.

`SurfaceTopology.lua` now supports face hit-testing by authored polygon loops
and **raycast checks against the actual compiled solid** for proposed crease
edges. These reject edges from stock that were eliminated by cutting. The
raycast is based on collision fidelity, which is only an approximation of
the visual CSG mesh.

## What this means for tools

- **File**: hover near a straight exposed contour edge, including one created
  by a sketch or a pocket. It is selected from feature history rather than
  MeshContent. Clicking writes a FileMesh feature with explicit endpoints and
  adjacent normals. Curved/circular hole lips are deliberately excluded from
  straight-edge filing.
- **Drill**: hit an indexed planar side/top/bottom face; cutter follows the
  face normal, still supporting blind depth and scroll diameter.
- **Inset**: supports convex single-loop planar faces; faces with hole or
  raised-feature loops are explicitly rejected rather than misleadingly
  inset across missing material.
- **Groove / straight kerf**: selects a planar surface and two endpoints.
- **Saw (Profile)**: remains the separate sketch-plane cutter.

## Suggested Studio smoke test

1. Start with a new untouched Block, hover File across its top, bottom and
   vertical perimeter edges. No mesh-load error should appear.
2. Sketch an irregular new Body using Intersect. Wait for manufacturing,
   then File one of the **irregular exterior contour edges** that was
   not on the rectangular stock.
3. Drill two holes; observe circular previews and changing diameter with
   mouse wheel. Test a vertical side face.
4. Inset a broad, uncut convex planar face and File its pocket lip.
5. Undo a middle operation or toggle feature history; verify that edges
   disappear/reappear with the actual compiled part.
6. Make several File operations and verify the highlight doesn't keep
   selecting the old (now removed) sharp corner.

## Limitations / next milestones

- This approach does **not** recover an arbitrary externally imported
  triangle mesh or CSG geometry produced outside FORM history. It's an
  analytic approximation for FORM-authored features, not a B-rep kernel.
- Raycast collision fidelity can differ from visible CSG surfaces, especially
  near narrow holes and delicate edges; selection can fail close to such
  geometry. Stable face references and proper polygon clipping are still
  future features.
- Plane-boundary reconstruction for overlapping/complex Boolean operations
  remains approximate. Complex convexity, multiple contours, fillets and
  curved surface edges need a richer geometry kernel or an authored
  topology update pipeline.
- CSG cutters can still fail on very small, thin features. Selection and
  fabrication are separate stages.
- No local Roblox Studio session is accessible from this conversation, so
  runtime behavior must be checked in Studio.
