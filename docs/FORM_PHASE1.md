# FORM — Phase 1: construction sandbox

## Working slice

- Each newly created component retains editable parametric nodes rather than permanently replacing its source with a union.
- Primitives: Block, Cylinder (Y-axis), Tube, Hole Block; **every primitive spawns with a 0.05 x 0.05 x 0.05 stud envelope**.
- Tube and Hole Block are solid when their 0.05-stud bodies cannot physically accommodate the hole; after you enlarge them sufficiently their parametric bores become active.
- A node is **Add** or **Subtract**. The first node must be additive. Additional node operations compile in list order using GeometryService.
- Numeric transforms: Position (X/Y/Z), Size (X/Y/Z), Rotation (X/Y/Z); tube wall and hole bore where relevant.
- Positions and dimensions snap to 0.05 studs. Rotation snaps to 15 degrees. Minimum allowed size is 0.05 studs.
- CSG is computed locally and asynchronously; obsolete results are discarded after newer edits.
- Multiple nodes form one logical editable component and compile into one non-splitting solid.
- Entire preview is local, anchored, and non-collidable. It is not persisted, simulated, shipped, or replicated.

## Try it in Studio

1. Open the configured OPENWORKS place and start Rojo with `START_OPENWORKS.bat`. Connect Studio to port 34872.
2. Enter **Play**. The temporary `FORM // DEBUG 01` panel appears.
3. Click **Block**. A tiny 0.05 x 0.05 x 0.05 component appears and the camera frames it automatically.
4. Enlarge the original block using the numeric SIZE fields (for example, X=2, Y=1, Z=2).
5. Click **- Cylinder**. It also begins at 0.05 studs. On the cutter, enlarge SIZE X (diameter) to about 0.5 and SIZE Y (height) to about 2, then the result should be a vertical cylindrical cut. CSG may not resolve every feature as small as 0.05 studs.
6. Navigate between editable source nodes with **< Prev Node** / **Next Node >**, and test recompilation.
7. Edit **POS**, **SIZE**, **ROT** of any selected node. Try **Tube** and **Hole Block** as new components; enlarge their X/Z dimensions enough for an opening.
8. Select a component and press **G**, **S**, or **R** (or the temporary buttons) to show **Move**, **Scale**, or **Rotate** handles in the 3D viewport. Drag a handle to manipulate the selected source node; the translucent transform proxy follows during the drag. Releasing the mouse triggers CSG recompilation.
9. Move/resize uses 0.05-stud snapping and rotation uses 15-degree snapping. This manipulates the active node, *not* the already-compiled PartOperation. Click **Hide Handles** to hide manipulators (press G/S/R to show again).
10. Use viewport camera controls: **RMB drag orbit**, **MMB drag pan**, **Ctrl+MMB drag dolly/zoom**, **wheel zoom**; optionally **Alt+LMB drag** to orbit.
11. Use **Numpad 1/3/7** for Front/Right/Top orthographic views; **Ctrl+Numpad 1/3/7** for Back/Left/Bottom. **Numpad 5** toggles orthographic/perspective.
12. Use **Numpad 2/4/6/8** to orbit 15 degrees, **Numpad 9** to flip to the opposite view; **Shift+Numpad 4/6** rolls the camera, **Ctrl+Numpad 2/4/6/8** pans.
13. Press **F** or **Numpad .** to frame the selection; **Home** frames all components. The top-right 3D ViewportFrame gizmo can be **dragged with left mouse** to orbit freely, or clicked on its axes for cardinal views without a numpad.
14. Drag the mouse while orbiting with RMB and confirm the pointer locks until release. MMB should pan. The **HAND · DRAG TO PAN** control below the view gizmo also pans. Wheel zoom combines dolly and focal-length changes, with interpolation; neither the grid nor the orbit pivot should jump.
15. Inspect the construction grid: it uses client-only LineHandleAdornments, not 3D grid Parts. Visible lines are **0.05 studs apart** across a 6x6 stud patch centered near your camera focus, with stronger lines at 0.5-stud intervals.

The panel and scene grid are intentionally plain. The viewport preview is only a debug harness, not final Duotone.

## Constraints and deliberate omissions

- No save/load, multiplayer sync, permission validation, server compilation, shipping, physics, constraints, or FORGE integration yet.
- One component represents one CSG solid. Disconnected unions may fail and will surface an error instead of silently creating extra bodies.
- Temporary 3D transform handles (Move, Scale, Rotate) are available. They're not the finished Duotone gizmos, and they apply to the selected source node. The compiled CSG solid updates on mouse release.
- Camera navigation follows Blender viewport fundamentals, but not every Blender mode or preference (no fly/walk navigation, camera-object view, or camera roll via gesture).
- Native orthographic projection is used where supported by the Roblox client. When it is unavailable, the camera stays in perspective instead of using an extreme camera-distance approximation. Orthographic feature availability varies between Studio versions.
- A component's first additive node cannot be deleted from the debug panel; delete the entire component instead.
- 0.05 studs is the model/grid precision, **not a guarantee** that Roblox CSG can successfully resolve every feature at that scale.
- Roblox may simplify complex CSG meshes (20k triangle limit); collision fidelity and geometry precision need runtime testing.
- A successful repository commit does **not** prove Studio CSG will succeed on the target place. Test the cuts in Play mode and inspect the Output window if something fails.

## Technical boundaries

- `src/shared/FORM/Quantize.lua`: precision rules.
- `src/shared/FORM/Document.lua`: pure parametric state model, including atomic viewport transform editing.
- `src/shared/FORM/Compiler.lua`: CSG operations via `GeometryService:UnionAsync` and `SubtractAsync`.
- `src/client/Preview.lua`: async revision-aware preview management.
- `src/client/FORMDebug.lua`: temporary editor controls and selection.
- `src/client/ViewGizmo.lua`: interactive 3D orientation widget in a ViewportFrame, with a drag-to-pan hand button.
- `src/client/TransformGizmo.lua`: live Move/Scale/Rotate handles that edit parametric nodes and defer CSG until drag release.
- `src/client/GridOverlay.lua`: 0.05-stud debug grid using LineHandleAdornments with a single invisible anchor.
- `src/client/BlenderCamera.lua`: independent Blender-style viewport controller.
- `src/client/init.client.lua`: starts the harness.

Roblox documentation: https://create.roblox.com/docs/reference/engine/classes/GeometryService
