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
