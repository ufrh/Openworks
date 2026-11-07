> **Nov 7 — internal Y, instant camera, first-sketch solid generation:** Create Component now only asks for X and Z (in mm); construction workspace Y is an automatic **1,000 mm**, not a user input and **not** the first extrusion depth. The sketch editor starts the first extrusion at **56 mm**, independently editable. The mode change snaps actual camera CFrame, orientation, zoom and projection on the initial frame (no entering/easing animation). First-sketch solid compilation now keeps the generated EditableMesh source alive with its actual visible MeshPart, rather than cloning a dynamic mesh then immediately deleting its source. `Fabricator` falls back to triangulating the profile into native right-triangle WedgeParts and `GeometryService:UnionAsync` if mesh creation is denied. The placement grid remains available via **Toggle Construction Grid**, but hides after a manufactured solid first appears so the view isn't just wireframe. `VERIFY_SKETCH_FIRST_WORKFLOW.lua` now actually compiles a solid and raycasts the native fallback, instead of checking only drawn wireframes. **Still awaiting live Roblox Studio validation of the mesh, fallback and transition.**

> **Nov 7 — character-first, grid placement, sketch-source components:** NORMAL PLAY is the default: the player retains Roblox walking and the default camera until clicking **Create Component**, entering a name + X/Y/Z grid dimensions (mm), placing the live cursor-following X/Z grid, and confirming the ground location. The permanent 6×6 world-origin grid has been removed. Placement draws **only** reusable `LineHandleAdornment` grid lines—no Part/box ghost—sized and moved by the actual specification, and retains that exact grid after placement. The CAD `BlenderCamera`, ViewGizmo and disabled character controls engage only after placement; **Exit Workspace** restores normal character movement/camera. The first closed 2D sketch is mandatory, and `Document:createSketchBody` creates the component from that outline's direct prism (`SketchBodyProfile`, `GeometryCutter.prism`), **not a Block, Cylinder, rounded L, or a stock/CSG-intersection placeholder**. No primitive choices remain in the Create Component dialog; legacy primitive source types persist internally for older components and verification compatibility only. Canceling the initial sketch leaves no empty body and returns to the character. The placed grid uses its specified X/Z footprint; Y specifies initial extrusion height with 1 mm precision. Source topology follows the sketched polygon rather than its rectangular workspace. Client Studio verification: `scripts/VERIFY_SKETCH_FIRST_WORKFLOW.lua`. **Live Studio sketch extrusion and camera/controls transition are not yet validated.**

> **Nov 6 — material-volume budget in cubic millimeters:** The component cap is now a numeric **175,616,000 mm³ of actual material** (the former 8 stud³ allowance), not the volume of an enclosing rectangular workpiece envelope. `MaterialVolume.lua` computes analytic material for Blocks, cylinders, and the profiled Rounded L. After manufacturing, it attempts signed tetrahedron volume of the actual CSG mesh; when EditableMesh readback is unavailable, it labels collision-derived mass/density as an estimate. Cuts decrease occupied material, while unions/extrusions increase it. On post-CSG overflow, `Preview.lua` rejects the result and restores the last accepted document snapshot. The creation dialog and workspace display volume used / maximum in mm³; geometric size constraints remain solely for editor/engine validity. `VERIFY_COMPONENT_WORKFLOW.lua` checks long thin stock and cylinders/rounded L shapes larger in AABB than the numeric budget. **Runtime CSG volume readback and rollback must be verified in Studio.**

> **Nov 6 — Create → Place → Edit workflow:** OpenWorks starts on a Create Component launcher rather than automatically entering the FORM editor. [Superseded Nov 7] Component specs formerly included primitive selection and a translucent placement box; the current flow is grid-only and requires a first sketch. Rounded Inside L defaults to 0.25×0.25×0.20 studs, with its inside quarter-circle radius occupying 92% of the available span; selection outlines are drawn only over finished manufactured solids to avoid a wireframe over temporary placeholder stock. Six camera-scaled face Scale handles return with 1 mm sizing precision; **material-volume cap = 175,616,000 mm³**, evaluated on the solid, not its enclosing dimensions. The three Neon rotation rings are complete 360° circles again. A per-component notepad stores local session notes. A two-click point measurement shows the 3D straight-line distance in mm; the old auto-hover surface ruler and test were deleted. Entry point `src/client/FORMDebug.lua`, modular GUI `ComponentPlacement.lua`, measurement `MeasurementTool.lua`, tests `VERIFY_COMPONENT_WORKFLOW.lua`, `VERIFY_TRANSFORM_GIZMO.lua`, `VERIFY_ROUNDED_L.lua`. **Roblox Studio runtime testing remains pending.**

> **Nov 6 — exposed File + inside Smooth + manufactured selection:** File picking now clips the selected straight stock edge to the actually accessible segment on either side of raised `SketchExtrude Add` footprints, accounting for the requested cutter width. Both preview and committed FileMesh use the clipped endpoints. HistoryTopology retires only the affected sharp interval so unfiled portions remain selectable. A dedicated **Smooth Inside Edge** tool adds a bounded 8-facet quarter-round on a straight concave 90° edge with a configurable radius; it uses additive CSG and is stored as `SmoothInside` history, not the previously paused interior File path. The Document disallows File and Smooth operations that meet a smoothed corner. Selection cyan now uses an approximately 0.85-pixel `WireframeHandleAdornment` drawn from authored manufactured edges (rather than a `SelectionBox` around mesh bounds); Move arrows are shorter and slimmer while preserving identical XYZ lengths. Tests: `scripts/VERIFY_EDGE_SEGMENTS.lua` and `scripts/VERIFY_TRANSFORM_GIZMO.lua`. **Studio CSG runtime and visual validation remain pending.**

> **Nov 6 — thin selection outline / face measurements:** Reduced the selected workpiece's cyan `SelectionBox.LineThickness` from `0.018` to `0.003`, and removed the `SelectionBox` decorations from all three Move arrowheads/shafts, which were drawing bounding **squares** around the cloned `ReplicatedStorage.Cone` mesh. The solid highlighted Cone and shaft remain clickable and unchanged. A new **read-only surface hover** layer shows the actual known planar manufactured face polygon, two offset CAD-style dimension baselines and orthogonal **millimeter extents**. It uses cached `HistoryTopology.faceAt`, not CSG mesh readback, and is suppressed during any fabrication/sketch tool, camera drag, text entry, or gizmo interaction. Curved faces and unknown/stale compiled topology are ignored rather than displaying inaccurate dimensions. For irregular surfaces, the measurements are projected face-plane bounding extents, not an arbitrary edge length or surface area. No physics Parts are created except one invisible, non-queryable adornment origin. Studio test: [VERIFY_SURFACE_MEASUREMENTS.lua](../scripts/VERIFY_SURFACE_MEASUREMENTS.lua). Build `2026.11.06.02` / `GIZMO-CLEAN-TIPS.6`; Studio runtime validation pending.

> **November 6 — current FORM gizmo spec:** All three Rotate axes have one **identical radius**, based on the full component bounding-sphere radius plus a camera-scaled margin (no more X/Y/Z-dependent radii). Move arrowheads clone the existing `ReplicatedStorage.Cone` MeshPart, authored with its tip along **local +Y**, and are rotated to point along the chosen world-space axis; stems still converge at the component pivot. Handle `Highlight` instances now use **FillTransparency=0** and **OutlineTransparency=1**. Move/Scale borders are `SelectionBox` adornments; each ring gets one `WireframeHandleAdornment` contour instead of 48 rectangular SelectionBoxes. The selected workpiece's cyan border now uses a `SelectionBox` adornment instead of an outline-only Highlight. Note: SelectionBox follows a part's **bounding volume**, not every cut face of a CSG MeshPart; precise mesh silhouette outlining would require a separate geometry representation. Studio build: `2026.11.06.01`, gizmo revision `GIZMO-UNIFORM-CONE.5`. Playtest pending.

> **Current transform-gizmo decision (Nov 5, 2026):** Mimic the **appearance** of Roblox Studio's Move / Scale / Rotate tools, but **do not use native Handles or ArcHandles** because FORM requires precise, camera-dependent control over their displayed size. The active implementation in `TransformGizmo.lua` now renders Move as solid highlighted cylinder shafts and WedgePart heads, Scale as six highlighted cube Parts, and Rotate as three colored 48-segment solid-cylinder rings with Highlights. The rings are camera-scaled, fully local-only and clickable through Part raycasting with a screen-space tolerance fallback; rotation still uses our existing `planeRadial` drag. No native ArcHandles remain. Version stamp: `BUILD 2026.11.05.02` / `GIZMO-SCALED-PARTS.4`. See [VERIFY_TRANSFORM_GIZMO.lua](../scripts/VERIFY_TRANSFORM_GIZMO.lua). Runtime Studio visual testing is pending; the older notes below document previous superseded experiments.

> **November 5 gizmo reliability correction:** The previous ConeHandleAdornment and LineHandleAdornment positioning did not reliably render the move heads outward or the shafts all the way to the center. Move arrows are now single world-space `WireframeHandleAdornment` drawings: each line runs from the true component pivot to the shaft tip, with a six-sided cone-outline arrowhead constructed explicitly beyond that point along the axis. The arrowheads cannot inherit an incorrect local cone rotation. Invisible raycast proxies remain outside the solid. Rotate now renders each XYZ ring using the same explicit world-space point sequence used for hit testing (no `Scale` or local CFrame assumptions), prioritizes circumference hits, and subscribes directly to adornment mouse-down/up events so GUI-processed clicks can start a drag. Ring paths are redrawn only after a frame/radius/hover change. See [VERIFY_TRANSFORM_GIZMO.lua](../scripts/VERIFY_TRANSFORM_GIZMO.lua). This still requires a Roblox Studio runtime check before declaring the visual issue resolved.

> **November 5 transform correction:** Move arrows now use a single X/Y/Z pivot at the component center, with all three line shafts extending from that pivot beyond their positive face. Their ConeHandleAdornments follow the world-space axis using `CFrame.lookAt(...)` directly (the old extra 90° X rotation incorrectly tipped the cones). Scale handles have additional clearance from their face. Rotate mode uses three real `WireframeHandleAdornment` rings (one in each plane) instead of tiny isolated sphere knobs; rings are selectable along their circumference using the projected 72-segment path, while rotation dragging still uses the existing planeRadial math. The invisible hit spheres remain as a fallback. Ring radius adapts to the part's dimensions and camera zoom. See [VERIFY_TRANSFORM_GIZMO.lua](../scripts/VERIFY_TRANSFORM_GIZMO.lua) for a client Studio test. This remains unverified in a running Roblox Studio session.

# FORM — Adornment-based editor visualization

Updated 2026-11-04 · branch `dev`

## What changed

The viewport's transient visualizations have moved away from creating
visible anchored Parts. Actual manufactured material and CSG cutters are
unchanged.

- **ToolVisualizer:** Pooled `LineHandleAdornment` segments show edge and
  face outlines, drill center guides, File segment strips, and inset/groove
  limits. `BoxHandleAdornment` provides a transparent removal-volume
  overlay; `CylinderHandleAdornment` shows cylindrical drilling and the
  bore entrance ring. Existing `BillboardGui` measurements remain.
- **SketchEditor:** The sketch grid, active profile strokes, vertices, and
  extrude-side wall guides use line, sphere and box adornments. Sketch
  geometry data, snap, polygon closure, camera and commit behavior are
  unchanged.
- **TransformGizmo:** Move stems/arrowheads use line/cone adornments;
  scale and rotate knobs use sphere adornments. The original pointer
  raycasting and drag calculations stay intact, using **invisible,
  queryable** Part hit targets solely for interaction. The external
  `ReplicatedStorage.Cone` mesh is no longer required for the gizmo.
- **GridOverlay:** Already used line adornments. No change necessary.

These are local-only editor overlays. They don't collide, cast shadows,
affect CSG, or take part in the material's physics. Each visualization
system has one invisible non-queryable origin Part with CFrame identity
to establish the world frame for its HandleAdornments.

The visualizer pools adornments instead of allocating new geometry every
frame; only the currently used guides are visible.

## Roblox Studio visual acceptance tests

1. Open the warehouse editor and select a Block. The gizmo should show
   move arrows, six scale points and rotation knobs in their modes.
   Drag all three axes; the hit targets should still capture the mouse.
2. Enter New Body Sketch. The grid, point markers, cursor-to-last-point
   line, and closed profile outlines should remain visible. Commit a
   sketch extrusion and inspect its preview walls.
3. Hover Drill over top and side faces. Confirm a translucent cylindrical
   guide, circular entrance ring and dimension badge. Scroll to change
   diameter. Verify the guides don't raycast as physical objects.
4. Hover Inset, Groove and Kerf. Their preview volumes should show
   clean outlines without opaque or shadow-casting parts.
5. Hover File for 1, 4 and 8 segments. Segment lines should follow
   the profile. Hover the full exterior vertical edge and confirm capture.
6. Exit each tool, deselect the body and enter/exit sketch mode. Old
   adornments should disappear immediately; no persistent ghost parts.
7. Check Studio Output for unsupported adornment property errors. If a
   platform build differs, use the class/property listed in Roblox's
   Creator Hub docs rather than falling back to visible Parts.
8. Confirm sketch/drill/File/Inset/Saw still compile into proper physical
   CSG results after clicking. Adornments are visualization only.

## Scope and limitations

The physical gizmo raycast targets are intentionally kept as **invisible
Parts** until click selection is moved to screen-space math or direct
HandleAdornment interaction. This preserves input behavior.

The preview volume is an analytic primitive overlay and does not exactly
display an arbitrary Boolean intersection at every face of the compiled
mesh. The real result is visible after committing a feature.

**The code was source-audited but has not been executed in a Studio session
from this conversation.**
