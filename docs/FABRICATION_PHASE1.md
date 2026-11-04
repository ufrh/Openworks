# FORM — First Fabrication Pass (November 2026)

This is an in-client **prototype**, not the finished physical-machine system.

## Behavior
- The visible grid has **0.1-stud spacing**. Material edge coordinates and transform increments remain **0.05 studs**.
- New Block: 1 × 0.4 × 1 studs. New Cylinder: 0.5 × 0.4 × 0.5 studs.
- A new workpiece's local *minimum corner* is placed at (0, 0, 0), meaning its **bottom face** sits on the y=0 work plane. The engine still stores the corresponding part center.
- Numeric **MIN** fields edit minimum corner coordinates, **SIZE** edits the envelope without shifting that corner, and gizmo face handles keep the opposite face anchored.
- Rotation uses the existing center pivot. When a shape is rotated, only its reference corner is guaranteed a grid-aligned construction origin; arbitrary rotated faces cannot all coincide with world-axis grid lines.

## Tools (temporary debug UI)
1. Select or create a Block/Cylinder.
2. Choose **Drill**. Enter diameter in millimeters, then click the **upper surface** to create a *through-hole*. Size and position snap to 0.05 stud (14 mm).
3. Choose **Saw**. Enter the cut's kerf in millimeters. Click a start point and an endpoint on the **upper surface** to subtract a **straight full-depth** slot.
4. Press **Undo Last Cut** to remove the last operation and rebuild from source.
5. **Exit Tool** returns to Move mode.
6. **EditableMesh saw** toggle: ON tries a temporary watertight EditableMesh cutting volume, converts it with `AssetService:CreateMeshPartAsync(Content.fromObject(editable), {})`, runs CSG and destroys **both** temporary assets. If the budget or mesh CSG APIs are unavailable, it retries with an equivalent native Part cutter. OFF always uses native cutters.

**Important:** Fabrication instructions (cut positions and diameters/kerfs) are saved in the local `Document` component history, not the cutter meshes. They are stored relative to the **minimum X/Z material edges**, not its center. History is replayed on base dimensions changing. World transforms alone do not replay CSG.

This mode does **not** yet include freehand continuous saw strokes, variable drilling depths, curved saw paths, filing, joints, multibody manufacturing, server replication, save/load, physical tool movement, shipping, or simulation. It is a proof of the subtractive geometry architecture.

## Implementation
- `src/shared/FORM/Document.lua`: boundary snapping and undoable fabrication source data
- `src/shared/FORM/Cutters.lua`: temporary cutter creation/disposal, budget fallback
- `src/shared/FORM/Fabricator.lua`: ordered CSG replay and output validation
- `src/shared/FORM/Compiler.lua`: native material envelopes
- `src/client/Preview.lua`: async manufactured solid display and revision rejection
- `src/client/FORMDebug.lua`: material and fabrication debug controls

## Recommended Studio smoke tests
- Create Block: MIN = (0,0,0), bottom face y=0; SIZE = (1,0.4,1).
- With Move gizmo, move 0.05 studs: check **boundary** coordinates snap rather than center.
- Scale +X: opposite -X face should remain fixed.
- Drill 56 mm diameter through top: expect a visible opening, remove via Undo.
- Saw 14 mm kerf across top with two points: expect a full-depth straight groove.
- Toggle EditableMesh saw ON then OFF, compare the outputs. ON should report whether native fallback occurred.
- Modify base SIZE after a hole: verify holes stay aligned to their boundary offsets.
- Repeat drills/saws: CSG should compile asynchronously, without retaining EditableMesh objects.
- Check Roblox Studio Output for CSG errors and whether the **Solid Modeling On Meshes** beta is enabled.

## Engine constraints
- This is client-side for now. An EditableMesh can be destroyed to reclaim its own allocation; finished CSG mesh assets still consume ordinary render/collision memory.
- CSG on MeshParts and `SweepPartAsync` may require the **Solid Modeling On Meshes** beta feature.
- In published experiences, EditableMesh APIs may require Allow Mesh/Image APIs and the relevant ownership or permissions.
- Complex or invalid cutter geometry, triangle budgets, and repeated CSG costs remain real constraints.
- This requires actual in-Studio playtesting; repository commits alone do not verify runtime behavior.
