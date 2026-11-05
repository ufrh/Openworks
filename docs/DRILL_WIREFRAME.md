# FORM — Drill wireframe and tool cleanup

Updated: 2026-11-05. Branch `dev`.

## Drill preview

The drill visualizer now uses **only line adornments**. It no longer
creates a translucent cylinder or uses a CylinderHandleAdornment for
its entrance circle.

- One thin **40-segment circular outline** at the intended drilling
  position, in the plane perpendicular to the selected face's
  **world-space normal**.
- Another circle at the planned hole depth, four longitudinal
  wireframe guides, and a faint center/depth axis.
- The ring's basis vectors come from the face normal; rotating the
  workpiece or drilling an upright/side face must not turn the circle
  sideways.
- For a blind hole, the back circle follows the selected depth. For
  a through-hole, the display uses the uncut stock's oriented bounding
  box to show the approximate span through the material, rather than
  the oversized CSG cutter used internally.
- Wheel diameter sizing and the through/blind toggle are unchanged.

Every guide is a pooled LineHandleAdornment with an invisible
non-queryable anchor. No visible Parts are created or raycasted.

## Removed editor tools

**Groove** and **Straight Kerf** were removed from the fabrication
toolbar, their width/depth fields, hover previews, and click handling.
The underlying historical operation data and cutter support are
retained for old documents and replay compatibility; no new
Groove/Kerf can be created from the debug editor.

**Saw (Profile)** remains, because the user requested removal of the
separate straight Groove/Kerf tools, not removal of arbitrary-profile
sawing.

## Studio acceptance

1. Hover Drill on the top face: circle lies flat on the face, never
   standing upright.
2. Hover Drill on a vertical side face: ring lies in that vertical
   plane, aligned to the face normal.
3. Rotate the workpiece and hover again. Ring orientation follows it.
4. Switch blind/through and adjust diameter with mouse wheel. Confirm
   the wireframe cylinders update without a filled body.
5. Verify both Groove and Straight Kerf buttons/fields are gone.
6. Create a normal New Body Sketch, Saw, Drill, Inset, and File
   operation. No fabrication path should have changed.

Source checks only; no Roblox Studio playtest was available from
this conversation.
