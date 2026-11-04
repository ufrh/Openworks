> **Update (2026-11-04):** The previous stock-envelope File/Inset and top-face-only Drill/Groove controls have been replaced by the compiled-surface selection implementation. See [COMPILED_SURFACE_SELECTION.md](COMPILED_SURFACE_SELECTION.md) for the current UI behavior and limitations. Legacy feature kinds remain supported for older documents.

# FORM Precision Fabrication — Preview / Tool Pass

Branch: `dev` • Updated 2026-11-04.

## What this implements

The editor now has a unified vocabulary for a finished workpiece and the
tool's **non-destructive preview**. None of the cursor indicators allocate
EditableMeshes, perform CSG or modify a Document. Actual fabrication happens
on commit and is replayed from a parameterized feature history.

### Sketch / profile cuts

- Sketch strokes use rounded cylindrical segments, smaller camera-scaled
  handles and a **single fill-only Highlight** for the full stroke model.
- Closed sketches show tinted extrusion sidewalls plus top, bottom and
  vertical boundary lines. A near-first-vertex cursor highlights the
  closure point.
- **Sketch / Extrude** retains Add, Remove, Intersect controls.
- **Saw (Profile)** enters the same sketch tool but fixes its mode to Remove.
  This removes an arbitrary closed volume via temporary mesh CSG. Through
  or blind cutting remains adjustable.
- New Body Sketch stays available on the world construction grid. Its preview
  accurately spans the floor plane to the selected height.

### Drill

- Hovering over a manufactured top face previews a translucent cylindrical
  removal volume, a crisp ring, and a dimension badge.
- **Mouse wheel** changes diameter in **2 mm increments**, or **10 mm** while
  holding Shift. Camera zoom is suppressed only while Drill owns the wheel.
  Use Ctrl+MMB drag / view gizmo zoom while actively drilling.
- **Through / Blind** button toggles whether the cutter spans the stock.
  **Blind depth** is a separate numeric field.
- Positions still snap to 0.05 studs (14 mm); diameters/depths are
  recorded at **1 mm** precision, with a **5 mm experimental minimum**.
  Roblox CSG may reject some very small or narrow features; failures
  surface in the FORM status panel.
- The preview's cylinder is a lightweight Part with a single Highlight.
  The circular perimeter uses one reusable CylinderHandleAdornment.
- Left click commits, with the feature stored as `Drill`.

### Inset / Pocket

- `Inset / Pocket` removes a rectangular pocket inside the upper boundary of
  a **Block workpiece**, with adjustable border thickness and blind depth.
- Hover previews the pocket depth and width. Click to commit.
- Currently refers to the **uncut stock envelope**, not an arbitrary generated
  polygonal face. This is intentionally not presented as arbitrary-face inset.
- Native Part cutter, no EditableMesh allocation.

### Groove

- Choose **Groove**, click a start point, then an endpoint on the same stock.
- Sets independent width and blind depth in mm. Hover after the first click
  previews the channel as a tinted cuboid.
- A native rectangular cutting volume spans the path. Paths are straight;
  smooth/freehand curved grooves are a future feature.

### File Edge

- Choose **File Edge**, enter chamfer width and hover near one of the
  four upper outer perimeter edges of a rectangular stock envelope.
- A teal highlighted strip shows which edge will be filed.
- Click to commit the resulting triangular-prism cutter with a sloped bevel
  through GeometryService:SubtractAsync.
- The cutter is a temporary watertight EditableMesh converted to a MeshPart
  and immediately released after CSG. Unsupported arbitrary mesh/Boolean
  edges aren't silently guessed; this pass only supports X+/X-/Z+/Z-
  **top straight perimeter edges on Block stock**.
- Rounded fillets and true freehand/brush filing are future milestones.

### Straight Kerf

- Legacy narrow saw cuts are still available as **Straight Kerf**, a separate
  through-cut operation. Two clicks select the kerf path. Native fallback is
  retained when an EditableMesh saw cutter can't be generated.

### History / compilation

- All new operations participate in per-feature ON/OFF and delete, snapshot
  copying, parametric recompilation, and geometry cache invalidation.
- The same neutral-white CSG inputs and disposal safeguards used by the
  previous sketch-extrusion pass are retained.
- No geometry is repeatedly compiled during hover or numeric edits.
- A feature can fail due to CSG engine limits, but it doesn't silently
  substitute a rectangular result for a failed complex mesh cut.

## Short in-Studio acceptance checklist

1. Create a Block, choose Drill, hover on its top. Expect a colored cylinder
   with a circular perimeter and a dynamic diameter/depth badge. Wheel should
   resize the circle without zooming the camera.
2. Set Drill to Blind and depth to 28 mm. Drill. Inspect from below: it should
   retain material underneath. Switch to Through; drill again elsewhere.
3. Click Inset / Pocket and set border 28 mm, depth 28 mm. Hover/commit.
   Confirm a recessed central rectangular pocket and unchanged outer walls.
4. Choose File Edge, set 14 mm. Hover near one of the four upper outside edges.
   The teal strip should follow the nearest supported edge; click.
   Inspect for a sloped chamfer and consistent color.
5. Choose Groove, set width 28 mm and depth 28 mm. Place two endpoints.
   Confirm a blind channel, distinct from Straight Kerf's through slot.
6. Choose Saw (Profile), sketch a concave profile, Enter to close, choose
   blind 28 mm or Through, commit. Check that the sketch preview has
   translucent walls and that material gets removed.
7. Toggle the newest features OFF/ON in the fabrication history, delete one
   middle feature and check that later operations replay successfully.
8. Resize the Block. Verify edge-relative drill and groove features move
   with the appropriate minimum X/Z stock boundaries, and the last valid
   preview isn't distorted while a CSG job compiles.
9. Repeat with several CSG features and watch for transient EditableMesh
   allocation failures or camera input conflicts.

## Known limitations

- No Studio playtest or Luau static analyzer was available from this chat.
  This code was reviewed and pushed; the first live test is essential.
- CSG may struggle with very small dimensions; millimeter-accurate input
  storage is not a guarantee of millimeter-accurate tessellation.
- Sketch geometry only uses the selected stock's local **upper** face. Face
  selection and cutting on arbitrary CSG faces are not yet implemented.
- Inset and File use envelope geometry, not post-CSG surface topology.
- User-defined curves, multiple sketch loops, freehand filing, fillets,
  shell/hollow, and assembly relationships remain future work.
- This is still a client-side editor prototype without warehouse shipping,
  physics or document persistence.

## Files changed

- `src/client/SketchEditor.lua`
- `src/client/ToolVisualizer.lua` (new)
- `src/client/FORMDebug.lua`
- `src/client/BlenderCamera.lua`
- `src/shared/FORM/Document.lua`
- `src/shared/FORM/Cutters.lua`
- `src/shared/FORM/FileCutter.lua` (new)
- `src/shared/FORM/Fabricator.lua`
