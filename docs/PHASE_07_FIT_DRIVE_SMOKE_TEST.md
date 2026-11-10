# OPENWORKS — Phase 07 Shaft Fitting & Physics Drives

Branch: `dev` • Build marker: `2026.11.10.PHASE07.FIT-DRIVE`

## A. Post-alignment fine fit

1. Create a DrilledBlock with a known hole diameter and a full Cylinder
   slightly smaller than its bore. Edit (2), select Cylinder, press L,
   choose DrilledBlock, choose offset, click **confirm alignment**.
2. Without switching tools, scroll UP: shaft Y/Z diameter increases by
   **0.05 U** per notch, and X (length) stays exactly the same. Scroll DOWN
   to reduce diameter. The shaft position and its alignment do not change.
3. The server stops increasing size before collision with the bore wall.
   The HUD displays the actual current diameter and the server message
   reports remaining diametral clearance. Click or Esc to finish fitting.
4. Repeat with CircularTube, SquareTube, a rotated DrilledBlock, a rotated
   housing, and a shaft component with an attached cross-bar. The bar must
   never be accidentally resized or shifted by diameter fitting.
5. In Assemble (3), create a Bearing or Slider and click finalize. It should
   enter the same Fit mode; scroll modifies the connected shaft's diameter,
   not the insertion depth. Fixed connections exit normally.
6. A random Cylinder with no completed alignment/relationship MUST NOT be
   able to call FitShaft successfully. Two-player test must reject fitting
   another owner's shaft/opening. Undo and redo preserve 0.05-U size steps.
7. Scroll back/down to loosen the fit; check it doesn't shrink below 0.25 U.

## B. Normal resize increment

1. Equip Build, choose Cylinder and press V: step is **0.25 U**.
2. Repeat in Edit with placed Cylinder (and after fine-fitting): 0.25 U.
3. Block, SquareTube and CircularTube remain **0.5 U** for V scaling.
   Post-fit scroll only appears in the dedicated Fit stage and uses 0.05 U.
4. No adjustment binds for the basic resizing increment are reintroduced.

## C. Hole block rotation

1. Create a Bearing with a DrilledBlock local-Y hole. Rotate the
   DrilledBlock about R/T/Y in several distinct orientations BEFORE
   creating the relationship and running physics.
2. Use the same cylinder as shaft, confirm alignment and fit. With Assemble,
   aim at the housing and press P and M. The shaft should rotate about the
   ACTUAL rotated hole axis, not world-up or a side axis.
3. Repeat using a tube local-X opening. Attachments for both ends of the
   relationship should share the same world transform at simulation start.

## D. Phase 07 drive / grounding

1. Assemble, aim at housing, press **P**: selected body stays anchored.
   M toggles powered Hinge/Prismatic motion; **N** flips its direction.
2. **[ / ]** adjust a running motor from 0.5x to 4.0x in 0.5x steps.
   The HUD should reflect rate and forward/reverse direction.
3. Press P to stop and ensure original anchored edit geometry is restored.
4. Equip Assemble, aim at an assembly and press **Shift+P**. No body should
   be anchored by OPENWORKS. Gravity should be free to move the assembly.
   P stops and restores the original construction.
5. Confirm the active context-right panel lists only current Fit controls
   during fitting and motor controls during simulation. Basic WASD remains
   unchanged throughout.
6. Confirm server rejects arbitrary motor tuning outside simulation, and
   editing remains locked while physics runs.

**Studio playtest is required.** Repository verification cannot establish
real joint rotational stability or the fidelity of precompiled CSG collisions.
