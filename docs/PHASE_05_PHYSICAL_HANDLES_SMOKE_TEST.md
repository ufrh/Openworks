# OPENWORKS — Physical Handles and Interaction Cohesion

Build marker: `2026.11.09.PHASE05.PHYSICAL-CONTEXT`
Branch `dev`; Rojo port 34872.

## Why an apparently clear shaft could be red

The earlier overlap validator used Roblox `GetPartsInPart` against every
constructed solid, with no distinction between an intended shaft/bore pairing
and a collision with an attached piece. The screenshot alone cannot prove
whether the bar or shaft actually interferes, because the full moving
component is shown as one red preview.

Phase 05 now checks shaft-to-selected-opening clearance analytically using
attributes ALREADY on the Studio generator v4 templates:

- `DrilledBlock_D...` has `HoleDiameterU` and a through hole on local Y.
- `CircularTube_W...` has `InnerDiameterU`, `WallU`, a channel on local X.
- `SquareTube_W...`, `RectangularTube_W...` have `InnerWidthU`,
  `InnerHeightU`, `WallU`, channel on local X.

For scaled CSG tubes the original bore size is adjusted by the ratio of
current outer Y/Z to generated outer Y/Z size. A verified cylinder running
coaxially with clearance is allowed through the SELECTED opening even when
Roblox reports a collision with the hollow PartOperation. ALL other moving
member geometry is still collision-checked against the housing. A red preview
now identifies the conflicting moving model and target model where possible.

### Clearance acceptance cases
1. Build `DrilledBlock_D1` and a full Cylinder with a diameter smaller than
   1 U (e.g. 0.75 U). Align via Edit L and via Assemble Bearing.
   The shaft should display BLUE if it is centered, while the rigid block
   and shaft remain distinct.
2. Make the shaft bigger than 1 U; RED should remain, even if the camera
   makes it look close to a fit.
3. Combine a shaft and perpendicular bar into one rigid component; insert
   so the shaft passes through the hole but the bar crosses a housing wall.
   RED is correct. Adjust axial offset until the bar clears; only then BLUE.
4. Test `CircularTube_W0.5` with a resized diameter. Verify clearance is
   measured from the SCALED internal bore, not the exterior size.
5. If the template lacks verifiable bore metadata, the system must NOT
   blindly ignore the housing. A red preview is accompanied by a named
   interference reason, and the server still validates independently.

## Physical move/scale/rotate handles

The physical handle visuals come from the archived FORM gizmo design:
- Move arrows: anchored cylinder stems and cloned `ReplicatedStorage.Cone`
  heads; local-only visual geometry; no collision, no querying.
- Scale: 3D cubes at both sides of each supported face, with fill-only
  Highlights and a thin SelectionBox. No GUI label pretending to be a handle.
- Rotate: three colored 3D segmented rings; no bounding-cube outlines.
- All three use the first-person center crosshair and world-space ray math.
  No unlocked cursor; no pixel-distance resize algorithm.

### Moving, scaling, rotation
1. Equip Edit and select a Block: move arrows and rotation rings appear.
2. Aim at a move arrow, hold left click, move/look/strafe, release. The
   temporary preview should translate ALONG that world axis, colored blue
   or red. Release commits one server Update; Ctrl+Z undoes it.
3. Aim at a rotation ring and drag. Its 3D ray-plane angle snaps to 90°
   turns. Release commits the same atomic transform as keyboard rotation.
4. Press V. Physical scale cubes appear. Hold left click on a face cube and
   move/look/walk; the opposite face stays anchored. Release confirms size.
   Sizing increments default to 0.5 U; [ / ] adjust.
5. Test whole rigid components. The selected component gets ONE continuous
   bounding outline, not individually outlined member highlights. Move or
   rotate with physical handles; members maintain relative offsets.
6. In Edit, aim at selected geometry, hold LMB and move your viewpoint/walk.
   After a small movement threshold the existing temporary G-move preview
   starts. Release to place; a simple click only selects.
7. Press G to move the selection without holding the mouse. Both forms of
   movement share geometry checks and surface-aware placement.
8. Toggle Build/Assemble/Inspect while a drag is active: previews and
   visual grips must be cleaned up, without stale camera settings.

## Contextual controls panel

The right-side panel now only lists the controls available for the current
Tool *and active sub-action*. For example, Scale shows drag, 3D movement,
increment adjustment, release, and exit; Assemble shows only the current
housing/shaft/insertion step plus delete/cancel. Rotation rings use the same
ray-based logic as scale and move. No new global toolbar or redundant tool
slot was added.

## Positioning and validation boundary

The server no longer rejects an otherwise-valid transform solely because
its CENTER is off a discrete grid. Size is still validated against the
available increments. Surface-placement previews keep all descendant parts
on the outside of the hit plane. The server still enforces ownership,
range, valid dimensions, and forbidden solid interference.

**Engine acceptance testing has not been run by the assistant.** Try the
clearance scenario from the screenshot, then move/scale/rotate a grouped
component, then switch modes during a drag. The generated CSG collision
fidelity and Roblox first-person Input order must be verified in Studio.
