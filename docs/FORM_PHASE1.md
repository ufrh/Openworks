# FORM — Phase 1 construction sandbox

The `dev` branch contains a local, temporary CAD-style construction harness. It is not yet a saveable or replicated game system.

## Workspace invariants

- **World-space workspace origin: `Vector3.zero`.** The 0.05-stud debug grid is fixed on the X/Z plane at Y=0 and never follows camera movement.
- **Camera orbit pivot is locked to `(0,0,0)`.** Orbit and FOV/dolly hybrid zoom change the view, never the workspace or the orbit center.
- Camera F/Home framing commands can change zoom to fit content but **cannot change the pivot**. Panning is intentionally disabled.
- All new primitives spawn centered at the origin with **0.05 × 0.05 × 0.05 stud** envelopes.
- Tube and Hole Block openings are inactive until their outer envelope can contain a valid opening.

## Camera

| Input | Behavior |
| --- | --- |
| RMB drag | Orbit fixed world origin |
| MMB drag | Alternate orbit |
| Ctrl+MMB drag | Zoom |
| Mouse wheel | Smooth hybrid FOV + dolly zoom |
| Drag the upper-right 3D view gizmo | Orbit |
| Click a gizmo axis / Numpad 1,3,7 | Standard cardinal view |
| Ctrl+Numpad 1,3,7 | Opposite cardinal view |
| Numpad 5 | Orthographic toggle where supported |
| Drag **ZOOM · DRAG UP/DOWN** button | Hybrid zoom |
| F / Numpad Period | Zoom to include selection, without moving the origin |
| Home | Zoom to include all components, without moving the origin |

The camera smooths its orbit angles, zoom distance and FOV independently and computes its final CFrame looking at `Vector3.zero` on each frame. Native orthographic view support depends on the Roblox client; unavailable clients remain in perspective, rather than using an extreme-distance approximation.

## Editing

1. In Roblox Studio, connect Rojo to `localhost:34872` using `START_OPENWORKS.bat`, and enter **Play**.
2. Spawn a Block in the temporary `FORM // DEBUG 01` panel. It appears centered on the origin.
3. Press **G** to move, **S** to resize, or **R** to rotate (or use the panel buttons). The manipulators are custom screen-projected GUI lines/rings and compact colored X/Y/Z controls, **not** Roblox Handles/ArcHandles.
4. Drag an axis control. Screen-space control dimensions scale with part magnification and are clamped to a small, usable size. Position and dimensions snap to **0.05 studs**; rotation snaps to **15 degrees**.
5. The authoritative parametric node updates **during the drag**. A translucent live source preview reflects each update immediately, with source color distinguishing additive and subtractive geometry. The compiled CSG result is rebuilt asynchronously with coalesced requests (roughly every 0.11 seconds while dragging), and compiled again on release. CSG can lag behind the source ghost during expensive operations; full Boolean cuts cannot be guaranteed every display frame.
6. Expand a Block to a useful dimension, add **- Cylinder**, then resize/position/rotate that subtractive source node and check the live Boolean result.
7. Original source nodes remain editable after compilation. Numeric POS/SIZE/ROT and bore/wall fields remain available.

## Code boundaries

- `src/shared/FORM/Quantize.lua`: 0.05 stud and 15-degree snapping.
- `src/shared/FORM/Document.lua`: pure parametric state and atomic transform validation.
- `src/shared/FORM/Compiler.lua`: CSG compilation with GeometryService.
- `src/client/Preview.lua`: live ghost plus throttled, revision-aware CSG compilation.
- `src/client/FORMDebug.lua`: temporary inputs and selected-node bridge.
- `src/client/BlenderCamera.lua`: fixed-origin camera with smooth hybrid zoom.
- `src/client/GridOverlay.lua`: fixed nonphysical 0.05-stud adornment grid.
- `src/client/ViewGizmo.lua`: draggable 3D ViewportFrame orientation and zoom control.
- `src/client/TransformGizmo.lua`: custom projected handles/rings, no stock Roblox handles.

## Known limitations

- This branch is **not verified in a running Roblox Studio session** by the code author; verify UI hit testing and transform behavior in Play mode.
- Roblox GeometryService may not resolve features as small as 0.05 studs. The grid snap precision does not guarantee CSG fidelity.
- No save/load, server compilation, validation, persistence, multiplayer replication, shipped assemblies, constraints, or FORGE integration yet.
- The 6×6-stud debug grid is a fixed visual patch, not an infinite world.
- Temporary 2D projected transform handles prioritize cleanliness and accessibility over full CAD affordances such as free-plane transform and pivot editing.

Roblox reference: https://create.roblox.com/docs/reference/engine/classes/GeometryService
