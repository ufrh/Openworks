# OPENWORKS — Phase 09 Engine Acceptance Checklist

Build: `2026.11.10.PHASE09.ASSEMBLIES-AND-SPRINGS` • dev branch. This document outlines tests; it
does NOT claim to have run Roblox Studio.

## A. No more wrong-side hole snapping
1. Build DrilledBlock with a full Cylinder; drag shaft to the opening
   from the positive local axis direction and create Bearing.
2. Undo. Repeat from the opposite side of the same hole. The two
   accepted shaft poses must be coaxial with exactly the same opening,
   with no 90°/180° inexplicable visual flip.
3. Rotate DrilledBlock on R/T/Y and repeat both approaches. Repeat the
   reverse workflow: drag the housing ONTO the stationary shaft.
4. Use a rotated tube (local X). Verify different approach directions,
   Q/E axial roll and wheel insertion depth preserve both orientations.

## B. Hard engagement and physical travel stops
1. Create a long shaft inside a short tube and choose Slider (3).
   Scroll toward the end: preview must stop where the shaft loses
   its required minimum engagement, never allow a floating attachment.
2. Try a forged out-of-range `PoseShaft` remote offset: reject; no part
   should move. Try resizing an already aligned shaft completely out of
   the tube: reject/rollback without clearing alignment metadata.
3. Simulate. Power the slider with M and watch it stop at both axial
   limits, without dismounting even when user-defined limits are off.
4. Repeat with Cylindrical (4), including rotation while sliding. Test
   joint J/[ ] and verify requested travel broader than shaft geometry
   is rejected. Test an extremely short shaft: Slider rejected if it
   cannot allow usable travel.

## C. Registered assemblies
1. Make one motor-bearing mechanism; make a separate spring or slider
   mechanism nearby but NOT joined by a relationship.
2. In Edit, aim at first mechanism and press Ctrl+G to register Assembly 1.
3. Aim at the second disconnected mechanism and press Ctrl+Shift+G.
   The two mechanisms must share a registered AssemblyId but must NOT
   become a single rigid component.
4. Enter Simulate, aim at any member of Assembly 1, press P. Both
   mechanisms must appear and simulate together. Stop/Reset must restore
   ALL originals without moving their authored positions.
5. Ctrl+Z and Ctrl+Y undo/redo registration and assembly additions;
   component grouping remains intact. Creating an assembly from a single
   rigid component without any joint must also simulate successfully.
6. User 2 must never be able to register/use user 1's assembly.

## D. Green grounded / orange moving
1. Edit: aim at multiple components and enter Simulate. G toggles
   grounded status. Only grounded bodies show green underbody guides;
   freely moving bodies show orange underbody guides.
2. Simulate P: physics clones render subtle green/orange body outlines.
   Green bodies stay anchored; orange bodies move under gravity/drive.
3. Shift+P deliberately ungrounds even previously grounded groups.
   P restores authored geometry and status colors without stale cues.

## E. Both spring use cases
1. Make CircularTube housing and Cylinder shaft with a snug bore.
   In Edit Shift+J chooses first part, then partner (either click order).
   Choose grounded housing G in Simulate, press P. The shaft should
   compress/rebound axially under load while remaining within its guide.
2. Press J aimed at the spring. [ ] adjusts stiffness, Shift+[ ]
   damping, -/= natural rest length. Undo/Redo the settings.
3. Make TWO equally sized Plate primitives or matching flattened Blocks,
   parallel with centered facing surfaces and a physical gap. Shift+J,
   select both. The spring should span them and act as a true native
   SpringConstraint, not a weld.
4. Reject mismatched plate sizes, offset/nonparallel plate faces,
   unrelated primitive pairs, shafts too large for a tube, or shafts
   with insufficient travel.
5. If a Slider already links the shaft and tube, spring should NOT
   add a second conflicting prismatic guide during simulation.

## F. Bolt versus welded rigid connection
1. Build two drilled blocks/plates with aligned through-holes.
   In Edit press B and select each hole. The system should choose a
   suitable fixed-length Bolt_050U, Bolt_100U or Bolt_150U template,
   place its physical shaft and head and create a Bolt relationship.
2. Reposition holes so they are off-axis: B should reject. Test
   too-narrow holes and excessive separation: reject; no fabricated
   bolt or phantom constraint remains.
3. In Edit Shift+B selects two TOUCHING solid parts. A Weld is authored;
   try two separated solids: reject. Welding must not insert a bolt.
4. Simulate the two bolted/welded constructions. Both must move as
   rigidly linked bodies. Original authored positions remain unchanged
   after P stop.
5. Undo/Redo bolt placement restores its physical fastener and link.
   Shift+Delete removes an authored bolt together with the fastener.
6. Invalid CreateRelation(kind=Bolt/Spring/Weld) requests must not
   bypass their dedicated validation methods.

## G. Integration regressions
- Gear meshing, motor ratio, fixed hubs, numeric size (N), drag previews,
  double-click component member, separate Edit/Simulate permissions.
- Observe Studio Output for exceptions, incorrect constraints, jitter,
  one-sided alignment flips, and failed restore/undo.
- Performance: 128 primitive models and 64 relationships is the
  intentional current safe maximum; document frame time in Play.

This is a Studio acceptance plan, not a physics test result.
