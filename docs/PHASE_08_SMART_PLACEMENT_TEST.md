# OPENWORKS — Drag-first Placement Overhaul: Studio Test Guide

Build: `2026.11.10.PHASE08.DRAG-MATE` • Branch `dev` • First-person construction

**This is an acceptance checklist, not a claim of an engine playtest.**

## A. Automatically insert a shaft while building
1. In Build, place a DrilledBlock with an open bore.
2. Select a Cylinder from the library. Move/look toward the opening; the
   ghost should find the hole axis and show a blue target highlight even
   when the crosshair ray passes THROUGH the opening to the wall behind.
3. The cylinder should snap coaxially and remain movable in depth with
   the wheel. Q/E changes roll. Click ONE time: the cylinder is placed,
   its bearing created, and the manual Align wizard is never opened.
4. During shaft snapping, press C to cycle Bearing / Slider / Cylindrical
   before clicking. The selected type should be used without any two-click
   Assemble workflow.
5. Press Ctrl+Z: the created Cylinder AND its new bearing should disappear.
   Ctrl+Y should restore both together. Check it physically in simulation.
6. Try a shaft larger than the hole. The preview should be RED, and the
   server must refuse it. Try an attached cross-bar that intersects the
   housing; likewise reject the WHOLE moving component.
7. Repeat with rotated DrilledBlock (local Y), CircularTube (local X),
   SquareTube and RectangularTube. All align to the actual opening axis.
8. Aim away from all openings; shaft should return to ordinary surface
   placement without creating a phantom connection.

## B. Move-to-attach without any two-click flow
1. Build an unconnected shaft and separate hollow support. Equip Edit.
2. Click the shaft ONCE. Selection should not move.
3. Hold and drag that selected shaft into the support. It should recognize
   the hole automatically; release to align and create the Bearing.
4. Group a shaft with a handle, then drag any member of the component
   near an opening. The complete rigid component should move in ONE pose.
   The handle may not intersect the housing.
5. Undo the move: the original position and no new relationship should
   be restored. Redo applies the connection together.
6. With an existing connected shaft, drag again into the SAME housing.
   It must not create duplicate physical constraints.

## C. Automatic gear pitch snapping
1. Build Gear_12T and Gear_20T separately, with centers initially away.
2. Drag the 20T toward the 12T. Its center should snap to approximately
   1.27 studs from the first gear, with parallel axes and coplanar faces.
   Release; OPENWORKS should create a Gear relationship WITHOUT K.
3. Test a 32T + 12T pair and verify the tooth-count ratio. Gears with
   incompatible pitches must not connect. An existing gear mesh should not
   generate duplicate relations on re-position.
4. Test automatic gear-on-shaft mounting: drag a Gear_12T center over
   a compatible Cylinder shaft, or drag the shaft through the open gear.
   It should snap coaxially and create a Fixed (rigid hub) relationship
   with no extra clicks. The wheel adjusts hub insertion depth. A shaft
   too large for the gear bore must stay RED and be rejected.
5. Create bearings for both gears' shafts and simulate. Ratio-aware
   motor coupling should still work. Gear center pivots must remain
   invisible and noncolliding.

## D. Faces, overlap and selection
1. Move a Block onto another Block's flat face. Preview supports the
   physical contact plane; one drop creates a Fixed link.
2. Aim at the floor or empty world; placement should NOT create Fixed.
3. Move away from the target while holding: snap should disengage.
   Hold Alt: snap should temporarily bypass, without changing normal
   selection. Release Alt and approach again to re-snap.
4. Put a Cylinder behind a housing: Alt+click should cycle to the
   next selectable geometry layer rather than requiring X-ray mode.
5. If two concentric tubes provide compatible openings, Tab cycles the
   candidate target while placing. Each highlight should identify the
   intended target. After leaving move mode, no stale target highlight.
6. Confirm the existing first-person selection, drag movement, six
   sphere scaling grips, and R/T/Y rotation are unaffected.

## E. Safety and performance
1. Two-player: A must not auto-mate to B's private construction; no
   unauthorized relation should be created or part transformed.
2. Attempt malformed target IDs/modes via remote: rejected without
   mutation. Server range and collision guards remain authoritative.
3. Build around 100-200 parts; scan snapping should remain responsive
   without frame drops from every-model / every-frame orientation search.
4. Simulation start/stop and returning to Edit should restore authored
   parts and clear temporary previews.
5. Verify invalid attempts do not create history records or leave half
   of a relationship. Undo/redo restore both geometry and joints.

## Limitations
Gears still use approximate toothed prefab geometry with ratio-aware motor
coupling, not an involute solver or passive torque transmission. First-
person physical snapping, collision fidelity, and input ordering must be
validated in Roblox Studio. Electrical/electronic design remains separate.
