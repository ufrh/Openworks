# Build and test the mechanical workbench

Use a fresh test workshop or keep unrelated components clear. These are manufactured parts, not generated hardware. Dimensions and Assembly positions below are **millimeters**; 280 mm = 1 stud. The source cylinder axis and guide travel are local Y. Enter positions in Assembly → Move, relative to the stage center; use rotation `0, 0, 0` throughout this first test.

## 1. A bearing you can actually see rotate

Manufacture these components. Rectangular dimensions are X × Y × Z; sketch the X/Z rectangle and extrude the Y thickness.

| Component | Dimensions | Assembly position X, Y, Z |
| --- | --- | --- |
| Housing | 168 × 56 × 168 | 0, 840, 0 |
| Shaft | Cylinder Ø28, length 224 | 0, 840, 0 |
| Lower end plate | 84 × 28 × 84 | 0, 713, 0 |
| Upper end plate | 84 × 28 × 84 | 0, 967, 0 |

1. In Edit, drill the **center of the housing's top face**, Ø31 mm, through. No other machining is needed. Create the shaft as a cylinder and the end plates as rectangular stock.
2. In Assembly → Parts, select each component. In Move, enter its position from the table and rotation `0, 0, 0`, then **Apply position + rotation**. All four share X/Z center; the shaft already passes through the bore.
3. In Mechanics, fix the housing and both end plates to the bench. Leave the shaft free.
4. Select the shaft and click **Use selected part as mover**. Click **Pick bearing housing / bore**, then the housing. Its bore becomes the target; use Align's reference list if you need to choose a different bore.
5. Return to Mechanics. Choose **Retained bearing**. Select each end plate in Parts and add it as a fixture. Exactly two plates should appear.
6. Click **Add validated relationship**, then **Check assembly**. Expected: valid, with 2 mm total axial endplay (1 mm at either end).
7. Start simulation. Select the shaft in Parts. In Test, leave **Motion / local Y**, enter spin `90`, and click **Spin +**. Watch the red end marker rotate. **Spin −** applies the opposite impulse; it is not a direction-setting motor command.
8. In Run, Pause, Reset, and Resume. Paused Reset should return the mechanism to its initial pose and retain pause. Running Reset should clear motion and keep running. Gravity/contact can change motion immediately after resuming.
9. Stop → Assembly. The original authored positions must remain unchanged. Re-enter and repeat.

To test an **unretained sliding bearing**, stop, remove the relationship, and move both end plates well away. Choose Sliding bearing and register the same shaft/housing with no fixture list. Its axial freedom allows gravity or Push to slide it out. Once overlap is lost, the active relationship count falls; Reset restores it. Do not expect an unretained vertical shaft to stay suspended while you inspect it.

To test the alignment tool independently, move the shaft's X position to 300 mm, select its **Shaft axis** reference in Align and set A; pick the housing's bore as B, then **Align axes (concentric)**. X/Z should return to the bore center while Y is preserved. A too-large shaft or a position crossing solid housing material must be rejected.

## 2. A carriage with measured linear travel

Keep the bearing setup separate, or start another test workshop. Manufacture these seven uncut rectangular components:

| Component | Dimensions X × Y × Z | Assembly position X, Y, Z |
| --- | --- | --- |
| Carriage | 56 × 112 × 56 | 0, 840, 0 |
| Left rail | 28 × 560 × 56 | −43, 840, 0 |
| Right rail | 28 × 560 × 56 | 43, 840, 0 |
| Rear rail | 56 × 560 × 28 | 0, 840, −43 |
| Front rail | 56 × 560 × 28 | 0, 840, 43 |
| Lower stop | 56 × 28 × 56 | 0, 630, 0 |
| Upper stop | 56 × 28 × 56 | 0, 1050, 0 |

1. Position all parts with zero rotation. Fix all four rails and both stops to the bench; leave the carriage free.
2. Select the carriage and click **Use selected part as mover**. Choose **Linear guide + stops**.
3. Add the four rails as fixtures first (any order among them), then the two stops (either order). The fixture list must contain six distinct parts in that grouping. No housing/bore B is needed for a guide.
4. Add the relationship and Check assembly. Expected: 1 mm rail clearance per side and 280 mm total stroke (±140 mm from the initial carriage center).
5. Start simulation. Select the carriage and Push along Motion. It should translate along Y and stop at the plates. A Spin impulse should not give it a rotational degree of freedom. Gravity loads the lower stop in this vertical setup; a small upward impulse may not visibly lift it.
6. Pause and Reset to inspect the centered pose, then resume. Stop must restore the authored center at Y=840 mm.

For a horizontal motion test, rotate and reposition the **whole manufactured fixture arrangement consistently**, including rails and stops. Rotating only the carriage should fail guide validation.

## 3. Reset and interaction acceptance

- Move and rotate in Local and World axes at several zoom levels. Escape and alt-tab during a drag must restore the pre-drag pose. Undo/redo should affect only accepted placements.
- Pan with MMB, orbit with RMB, zoom with the wheel, then F/Home and Reset view. Select both from Parts and directly in the viewport.
- Switch Free → Edit → Assembly → Simulation → Assembly → Free three times. Check character control, mouse release, FOV, selected component, gizmo visibility, and unchanged source geometry.
- Try starting with a shaft that is too large, a missing/floating guide rail, two stops on the same side, or a grounded mover. Expect a clear rejection with no partially active simulation.
- During Simulation, respawn the character. Expect Free mode and no leftover session. Delete a referenced rail/plate after stopping; its relationship must be removed.
- Save and restart Play with DataStore access enabled. Verify component geometry, positions, grounding, and relationships survive. A local codec test alone does not establish persistence.

For scripted setup and assertions, use `VERIFY_CAD_WORKFLOW.lua` and `VERIFY_LINEAR_WORKFLOW.lua` in the client Play Command Bar. These scripts clean up their own parts after completion; the manual builds above remain available to inspect.
