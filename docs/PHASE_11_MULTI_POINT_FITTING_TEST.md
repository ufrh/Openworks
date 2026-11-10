# OPENWORKS Phase 11 — Multi-point Fit Acceptance Tests

Build tag: `2026.11.10.PHASE11.MULTIPOINT-MOTION-FITTING`
Branch: `dev`
**Manual Roblox Studio tests required; these cases have not been run by the coding agent.**

## Test A — One rod and one hole: new non-rigid default
1. Place a rod next to a drilled block. Drag the rod into the opening (also test
   dragging the hole block over a stationary rod).
2. Confirm blue valid preview and release. The motion chooser must show:
   **1 Rotate + Slide (default)**, **2 Slide Only**, **3 Rotate Only**,
   **4 Fit Only**, with mouse-clickable choices and Enter for the default.
3. Pick 1. In Simulate, the joint must allow axial travel plus rotation.
4. Undo and repeat with 2: sliding only. Repeat with 3: rotation only.
5. Repeat with 4: positioning is committed but no mechanical relationship
   or invisible WeldConstraint is created.
6. The old "Rigid" choice must not appear; only the Weld tool makes a rigid bond.
7. Verify the opposite shaft/hole approach orientation doesn't flip the body.

## Test B — A plate with four guided holes over four fixed rods
1. Assemble a bottom support using separate blocks. Put four matching rods
   in an equal square pattern and **manually Weld** each rod into its physical
   support. Grouping the rods as a component is EDITOR-ONLY, not a weld.
2. Build an upper plate from four compatible hole blocks connected with
   flat structure. Explicitly Weld its parts together, then group the top
   parts as one editor component (Edit C).
3. Move the *whole top component* near the four rods. Blue snap should align
   ALL FOUR holes onto the rods, not just one. Preview HUD should show
   **4 points**. Try approaching from above, below and at a rotated yaw.
4. Release and choose **2 Slide Only**. This creates ONE Slider on the primary
   pair; the other three are verified fitting/clearance contacts, not extra
   PrismaticConstraints and not WeldConstraints.
5. Ground the bottom with Simulate. Run the assembly; the upper plate should
   move along the four posts (depending on mass, friction and spring force).
6. Create a spring using the matching flat center blocks on top and bottom
   (Edit Shift+J two-click pair). Start Simulate, click either central block,
   select Spring, and tune stiffness, damping and rest length in Properties.
7. Stop. No edit geometry should have moved permanently.
8. Remove one rod's weld: that rod should NOT remain secretly attached due
   to group membership or the multi-fit operation.

## Test C — Different valid hole patterns, insertion depth and roll
1. Use two or three holes in a non-square pattern, with corresponding shafts.
   Move the assembly in from the front and reverse.
2. Start with a 30–90 degree rotational mismatch around the primary shaft.
   Check that the additional hole positions drive automatic yaw/roll matching.
3. Change the axial insertion depth with mouse wheel; all guides must stay
   aligned and have enough overlap. Release only when blue.
4. Try different rod lengths. For Slider / Cylindrical, the shortest engaged
   rod should prevent unlimited travel, without a floating/disconnected joint.
5. Confirm all secondary guides keep their relative component positions.

## Test D — Invalid fittings must be rejected, not ignored
1. Offset one rod laterally beyond the hole clearance. The assembly should
   NOT be silently treated as a valid four-point fit; penetration must be
   marked red/rejected, or fewer valid points must be clearly indicated.
2. Make one hole too small for its rod. There should be a red invalid
   preview if the solid interferes; no bypassing the bore clearance.
3. Misalign one axis or tilt a rod. Reject the physically impossible contact.
4. Place an unrelated solid in the middle. The entire assembly must reject
   penetration even if the four bore fits themselves are valid.
5. Excess >32 fit contacts should fail safely with a clear message.
6. Test with 2 players; one player cannot cause changes to another's geometry
   or declare another player's rod to be their fitting target.

## Test E — Other regressions
- Four-hole editor component drag moves all pieces together before simulation,
  but without explicit welds the pieces separate under physics.
- Spring visual orange in construction, gone during simulation.
- Bolt prefab fastening remains independent of shaft mating.
- Existing explicit Weld/Bolt relations are not silently removed by snap.
- Native joint options and travel constraints remain editable in Simulate GUI.
- Undo/redo restores the multi-fit pose, joint metadata and group IDs.
- Build catalog, numeric sizing, previews and direct drag still work.
- Watch Studio Output for construction validation errors, recursion spikes,
  bad collision exclusions or native solver instability. Capture the exact
  log and which test step failed.

**Note:** The multi-fit imposes one chosen kinematic relation, not four separate
slider constraints. Actual collision friction/jitter depends on Roblox's solver;
engine-level load/stability must be verified in Studio.
