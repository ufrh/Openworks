# OPENWORKS — Phase 08 Mechanical World Studio Acceptance

Build marker: `2026.11.10.PHASE08.MECHANICAL-WORLD`
Branch: `dev`. Rojo: `34872`.

**Acceptance gate: Test in actual Roblox Studio Play mode**. Static GitHub
checks cannot prove physics stability or correct CSG collision.

## 1. Multiple grounded bodies
1. Assemble (3), aim at a primitive and press G. A grounded status should
   persist even after switching to Edit and back. Its 3D ground marks should
   be visible near the physical body, not floating in the HUD.
2. C-group several pieces, aim at any member, press G. Every member should
   gain the same Grounded property. Undo/redo should restore the assignment.
3. Ground two different components linked by joints. Simulate (P) with the
   crosshair on a third component: both explicitly grounded bodies should
   stay stationary. No extra fallback body should be grounded.
4. Clear all Grounded assignments. Now P should ground the aimed support,
   as in Phase 07.
5. Shift+P should deliberately simulate *everything ungrounded*, even if
   some components retain a Grounded flag. Stop with P to restore the
   original anchored construction.

## 2. Intuitive whole-component rotation
1. Group an asymmetrical L-shaped component (C); select it and rotate
   with R (world Y), T (world X), and Y (world Z) in various orders.
2. The whole component should turn around the geometric center of its
   complete bounds, not the original central primitive. Original member
   offsets and joint-relative positions should be preserved.
3. Rotation should have a short physically smooth ghost transition, but
   the committed pose should remain exactly 90° per key.
4. Move the rotated component on a surface using G or drag. Its last
   rotation must not reset or snap to an unrelated local orientation.
5. Rotate a single primitive and undo it. Repeated turns through a full
   revolution should return its exact original orientation.

## 3. Continuous shaft pose inside a hole
1. Make a drilled block, a cylinder shaft, and a rigid component with a
   shaft + offset handle.
2. In Edit, select shaft, press L, choose the drilled opening. Wheel changes
   insertion depth; Q/E or Shift+wheel rotates the *shaft and entire rigid
   component about the opening axis*. Moving should update a visually
   smoothed 3D preview with blue clear / red interference.
3. Confirm. Wheel now changes shaft diameter in 0.05 U steps; Alt+wheel
   still changes insertion depth and Q/E changes axial roll. Neither
   operation alters the shaft's length or separately moves the attached
   component pieces.
4. Repeat using Assemble (3) to create Bearing, Slider, Cylindrical.
   After selecting housing and shaft, rotation/depth can be adjusted
   before finalizing; post-finalization Fit preserves roll/depth edits.
5. Aim attached handle into housing wall: the server must reject real
   intersection, not just color it red locally.
6. Undo/redo a pose and a 0.05 U diameter change; verify positions,
   orientations, original shaft geometry and relationships remain intact.
7. Resize a shaft that has already been rolled to a non-90° angle; the
   resize/move operation must NOT reset its authored roll.

## 4. Separate gear creation and meshing
1. Open Build catalog (B). Under Transmission, find Gear_12T,
   Gear_20T, Gear_32T; each has an actual hollow center and visible
   native tooth/annulus geometry.
2. Insert a shaft through a gear's central opening; its invisible pivot
   must never block the shaft in construction OR simulation.
3. Place two gears with parallel X axes and the proper pitch-circle center
   spacing (the system reports required stud spacing). The two gears must
   belong to different rigid bodies.
4. Equip Assemble, press K, select Gear_12T then Gear_20T.
   Relationship should be named Gear with a negative ratio of -12/20.
   Wrong gear module, perpendicular axes, duplicate pair, or mismatched
   center distance must be rejected with an explanation.
5. Attach each gear to a bearing-supported rotating body, then simulate.
   Activate M and inspect relative tooth-count motor speed/direction.
   Gears' shaft components should rotate without phantom colliders.
6. Repeat in reverse selection order; confirm the expected reverse ratio.
   A pair without powered bearing joints can be freely simulated but is
   NOT expected to obtain automatic motor power merely from a Gear edge.
   Gear tooth physical contact may be limited by native solver fidelity.

## 5. Joint configuration and simulation controls
1. Aim at a Bearing, Slider, or Cylindrical body, press J, and toggle U
   to enable/disable travel limits. Press [ or ] to narrow/widen the
   symmetrical range; undo/redo must restore the old joint settings.
2. Run grounded P; test M motor, N reverse, [ ] speed, O pause/resume,
   U reset, I telemetry, P exit.
3. Pausing must freeze all moving physical copies; resume should restore
   motion. U should discard the old copy and rebuild it from the authored
   geometry, not from its last simulated location.
4. I must show a server-computed mechanism report including authored
   grounding, relationship types and available joint telemetry.
5. Verify originals are never mutated by simulation, and stop, respawn or
   disconnect cleans all temporary copies.
6. Test as two users: no player may ground or move the other's parts,
   set their joint parameters, or mesh their gears.

## 6. Physical-only visual cohesion
1. Look at the constructed workshop in normal Build and Edit. Satin
   industrial material, restrained local color grade, slim mechanical
   joint-axis guides and grounded visual cues should match the world.
2. Ghosts should ease smoothly into moved/rotated targets, but final
   placement must be exact, and red/blue validation based on true
   target geometry rather than the lagging presentation ghost.
3. During simulation, construction-time guides should disappear. On
   stopping simulation, guides should return with no stale world positions.
4. Scale spheres remain colored non-blooming physical grips, with move
   arrows and rotation rings still absent. HUD/layout styling remains the
   existing system, not a redesigned GUI.

## Known Phase 08 limits
The gears use preauthored tooth counts and native faceted physical
geometry, not mathematically exact involute profiles. Tooth ratio
propagates to associated bearing motors as an engineering prototype,
not a guaranteed collision-free gearbox or a true unpowered torque
transmission model. There is deliberately no electrical subsystem
or permanent shipping in this phase.

Any Studio exception, bad orientation or solver instability must be fixed
before calling the engine playtest complete.
