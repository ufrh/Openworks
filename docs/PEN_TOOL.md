# OPENWORKS — Pen Tool Metal Layout (M1)

The active scoring workflow now uses an on-material, Photoshop-style **cubic Bézier Pen Tool**. It works in the existing workpiece inspection camera with the existing physical `Workspace.Scorer`, without a blueprint sheet, physical ruler, or a separate CAD GUI. Players define the intended cut profile in local material coordinates, then save it as a real FORM score. The score is not a cut; manufacturing still requires the saw.

## Controls

1. Place a FORM workpiece and the physical Scorer on the workbench. Inspect the metal and select **Scorer**.
2. **Click** to place a corner anchor. Subsequent clicks add straight segments.
3. **Click and drag** as you place an anchor to define its tangent handles for a smooth curve. Cyan anchors, turquoise tangent handles, and gold curve previews appear directly on the metal.
4. **Drag an existing anchor** to reposition it, or drag a handle to refine the curve. While dragging a handle, hold **Alt** to break its mirrored tangent and create an independent/cusp handle.
5. **Backspace** removes the last anchor. **Enter** commits the current open contour as a permanent score. Invalid curves extending beyond the supported material face are rejected with feedback, not clipped silently.
6. **Escape** clears an unfinished path; press again to exit inspection. **F** switches to the earlier hand-driven freehand scoring mode; F again switches back to the Pen Tool (discarding any uncommitted Pen Tool anchors when leaving it).
7. Switch to the physical Saw, hover the saved score and click to use existing automatic score-following fabrication (current FORM cutter limits apply).

There are up to **12 anchors** per open contour, sampled into no more than 256 points. This is an open-contour layout system, not yet closed interior pocket or hole cutting. Out-of-bounds control handles are permitted within reasonable length, but an actual sampled curve must remain on the exposed material face. If the user switches workpieces or flips the metal, uncommitted Pen Tool anchors are discarded to avoid drawing on the wrong face.

## Implementation

- `src/shared/PenPath.lua` validates anchor and control-handle coordinates and samples cubic Bézier segments directly into workpiece-local points. The path is **not** passed through the earlier freehand smoothing routine, which would otherwise distort intentionally designed curves.
- `src/client/PenPathEditor.lua` handles interactive anchor placement/editing, mirrored/independent tangent handles, ghost preview, and pooled physical world-space preview parts. The editor is active inside the existing inspection camera, not a separate ScreenGui.
- `src/client/PhysicalInteraction.client.lua` routes the scorer's mouse/keyboard input into the Pen Tool by default, updates the real visible Scorer's pose while hovering, and submits authored anchors only when the user commits.
- `src/server/PhysicalInteraction.server.lua` verifies Pen Tool input and stock bounds, samples the authoritative path, adds it to `ScorePath`, and uses existing welded score marks. Clients cannot directly write score attributes.
- `src/shared/PenPathRegression.lua` tests straight segments, actual cubic curvature, invalid handles, stock-boundary overshoot, and rotated workpieces. Studio's test sheet script runs this check at startup.

The physical ruler and previous blueprint system remain as optional experimental prototypes, but no longer spawn by default. To test them again, set `Workspace.EnableLayoutRuler = true` or `Workspace.EnableBlueprintKit = true` (Boolean attributes) before Studio Play.

## Playtest

Sync `dev` and restart Studio Play. In Server Output look for `[OPENWORKS:PenTool] straight/smooth Bézier scoring, geometry limits and rotated metal passed`. Use Spawn Test Sheet. Select the sheet and Scorer; place two anchor points, drag a third, and adjust handles. Press Enter and verify the in-progress gold path becomes a permanent dark score that moves with the workpiece. Switch to the saw and try its score following. Then check Backspace, Escape, Alt-breaking handles and F toggling freehand.

This code has been committed to the repository. Direct GUI, camera, physical-model, and cutting behavior still require a live Studio playtest.
