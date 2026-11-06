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
