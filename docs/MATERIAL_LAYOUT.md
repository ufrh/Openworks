# OPENWORKS — Direct Material Layout (M1)

The active default workflow is physical marking **on the metal**, not applying a virtual CAD profile or transferring a blueprint. A real ruler constrains the existing physical Scorer; the user must still trace by hand. The finished scored line is stored in the workpiece's existing `FORMScorePaths` and can be followed by the saw.

## Studio setup

- The metal workpiece is a marked FORM sheet on `Workspace.Workbench`, such as one created with Spawn Test Sheet.
- The physical `Workspace.Scorer` is a Model or BasePart; existing scorer detection applies. Keep its tip attachment and physics assembly as in `PHYSICAL_INTERACTION.md`.
- `Workspace.Layout Ruler` is automatically spawned on the workbench in Studio unless another ruler with `DraftingKind = 'Ruler'` already exists. It is a solid metallic ruler with dark edges and physical tick marks, tagged `isTool = true`.
- The previous paper blueprint drafting prototype remains in the repository but **does not automatically spawn**. To spawn its drafting kit in Studio, set the boolean Workspace attribute `EnableBlueprintKit = true` before Play. This keeps the paper-based alternative reversible.

## Player interaction

1. Position a piece of metal on the workbench and select it. In the inspection camera, select the physical Scorer.
2. **Hold LMB over the ruler's body** to pick it up in inspection mode. Move the mouse to position it on the metal. **Scroll while holding** to rotate by 5° increments. The actual Workspace ruler follows the mouse, and its server-validated position stays on the exposed material face.
3. Release LMB to set the ruler in place. It remains temporarily kinematically secured during the scorer session so it does not fall off the part as you mark.
4. Move the cursor to within approximately 0.27 studs of a ruler's long edge. The scorer's hover contact turns **green** when constrained. Press LMB just beside the physical edge, then move the mouse along it; the scorer traces the exact ruler direction, not an imprecise freehand line. A click directly on the ruler's body moves the ruler; clicking near the edge traces it.
5. Release to save the score. This adds a normal persistent FORM score to the metal, with local coordinates and welded visible groove marks.
6. Exit Scorer using Escape, switch to the saw, and hover the new line. The saw recognizes the existing score for a subsequent cut (subject to the current cutter's geometry limits).
7. If no physical ruler is nearby, manual freehand scoring remains available as before.

The ruler is never a Roblox Tool/hotbar item and is not a new UI drawing mode. The only UI is the existing metal inspection status, reused for feedback. Scoring is still manual, not generated automatically by selecting a shape.

## Architecture and constraints

- `src/shared/MaterialLayout.lua` computes exposed-face ruler frames and constraints. The ruler is positioned in the workpiece's world-exposed plane even if the sheet is flipped.
- `src/client/PhysicalInteraction.client.lua` drives the physical ruler at render rate while dragged, snaps local scoring preview points to a frozen ruler guide during each score, and sends motion to the server.
- `src/server/PhysicalInteraction.server.lua` validates player proximity, locks the physical ruler, authorizes constrained motion, and independently projects every received score point onto the selected ruler line. It restores the ruler's original physics settings when the scorer session ends.
- The existing `ScorePath` stores marks and the existing saw reads those marks. There is no alternate cut backend.
- `src/shared/MaterialLayoutRegression.lua` checks straightness, material-surface validity, rotated ruler placement, and rejection of far-off rulers. The Studio test-sheet script invokes it at startup.
- This milestone implements **one physical straightedge** on a locally planar FORM metal face. True irregular 3D surfaces, measurement annotations, compasses, dividers, squares, center punches, physical dye, and persistence across new game sessions are later work.
- Existing automatic scored saw cutting is unchanged, including its current limitations.

## Playtest

1. Sync `dev`, restart Play, and check Output for `[OPENWORKS:Layout] Physical metal-layout ruler spawned on workbench` and the regression success line.
2. Spawn a steel sheet and let it settle on the bench.
3. Select the metal, then Scorer; drag the ruler onto the metal, using the wheel to rotate.
4. Trace along a ruler edge and release; confirm the green snap and a perfectly straight saved score.
5. Change ruler angle and draw a diagonal, then change to Saw and try cutting along the score.
6. Check scorer still works freehand away from the ruler, and Ruler/Scorer both return to physics state on leaving inspection.

Code is committed, but live Studio interaction and replication have not been validated yet.
