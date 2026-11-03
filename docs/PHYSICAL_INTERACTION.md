# OPENWORKS — Physical interaction and precision workbench

All interactions use actual Workspace objects. No Roblox Tool, Backpack, hotbar, or old fabrication UI.

## Required workshop objects

- `Workspace.Workbench` contains one or more BaseParts named `surface` (case-insensitive). Server creates invisible tabletop supports and overlap-query regions.
- A physical saw or file is a rigid, welded, unanchored Model or BasePart tagged with Boolean attribute `isTool = true`. Clickable geometry must have `CanQuery = true`.
- Tool operation is selected by String attribute `FabricationKind = Saw` or `File`, or inferred from the Model name containing `saw` or `file`.
- Materials are `FORMMaterial` tagged and `isMaterial = true`. The Studio **Spawn Test Sheet** button makes an unanchored physical steel sheet with `FORMNativeStock = true`, which supports the native rectangular-stock operation.
- Both tool and selected material must settle onto the Workbench to enter precision fabrication; their `OnWorkbench` attributes are set by the existing detector.

## Optional tool contact attachments

A saw should have an **Attachment** named `BladeEdge` at its cutting edge. Its complete orientation now defines the mount: local **+X** follows the cut, local **+Y** points up away from the stock, and local **+Z** is perpendicular to the blade. Without the attachment, OPENWORKS falls back to finding a BasePart whose name contains `blade` and uses its longest dimension as the cutting direction; the next longest becomes the blade's upright direction. If no blade is identified, the primary Part is used. A Part named `Teeth` can indicate which side should face downward. The server converts that blade geometry into a single fixed mounting offset, then forces it to align to the active cutting path.

`FileFace` is still supported for files; **R** and **Shift+R** rotate a file only. Saw rotation is automatic: no F flip, saw roll controls, or per-frame corrective rotations remain.

During precision mode the real Workspace saw or scorer is temporarily anchored for kinematic placement. The saw is set directly to its correct path frame every Heartbeat. The scorer's original model is moved locally each render frame for responsive mouse tracking. The server validates score coordinates and broadcasts poses to other clients, but does not write a competing anchored pose on Heartbeat. There is no hidden scorer clone. On exit, original anchor and collision states are restored. Normal free dragging still uses physics constraints.


## Free-mode interaction

- **Hold LMB** on material or tool: physically lift and drag it. Release to drop.
- **Very short LMB click**: select instead of carry.
- While dragging, **wheel** changes reach; **Shift + WASD** rotates the assembly.

## Material inspection

- Short-click a material, or short-click a tool when exactly one workpiece is on the bench.
- **RMB drag** orbits; **MMB drag** pans; **wheel** zooms around the physical workpiece. Entering inspection and refocusing on another material ease toward the target instead of snapping. Exiting blends the inspection camera back to the gameplay camera over roughly 0.65 seconds.
- In the right-side panel, select a saw/file that is physically present on the bench.
- **Switch the active workpiece without exiting:** When the saw or file is active and LMB is released, click another marked material resting on the workbench, press **Tab** / **Shift+Tab** to cycle, or choose a material from the precision panel's workpiece list. The same physical tool stays active. The server secures the new piece, releases the previous one, clears stroke progress, and verifies it is on the workbench and within reach. The camera smoothly interpolates to the new selection without ending inspection. Release LMB before starting a new stroke on the switched piece.
- **Flip the physical workpiece:** Press **X** or **Z**, or use **FLIP MATERIAL X/Z** in the precision panel while LMB is released. This rotates the secured part 180° and keeps it seated. Filing and saw toolpaths use the face pointing upward globally rather than assuming local +Y is always the top. Release LMB before flipping and press it again to resume.
- **Escape** exits, restores normal camera, and releases the temporary kinematic fabrication control. Finishing a cut or filing pass does **not** exit inspection.
- The inspection camera no longer requires the default Roblox `PlayerModule`, which may not exist in customized player scripts.

## Saw positioning and cutting

1. Select the steel sheet, then the saw. The real saw is aligned to the workpiece using `BladeEdge` (or the tool-bounds fallback).
2. A narrow **gold cutting guide** appears on the sheet. Move the mouse over the metal to position it. **Shift + horizontal mouse movement** also adjusts the cut offset.
3. Press **Q** to switch between cuts normal to local X and local Z on native rectangular stock.
4. **On an unscored part of the sheet, hold LMB and move the mouse back and forth manually.** The saw follows each stroke. **On a saved score, click LMB once instead:** the server validates the path, moves the saw automatically along it, and completes the cut without further mouse motion. Esc cancels the operation and exits inspection.
5. When five qualifying stroke reversals complete, the server calls `SawCut.split` using FORM. The larger retained piece **remains the same Part and remains selected** (only its dimensions and CFrame change). An offcut appears as a separate unanchored, tagged physical Part. Both are positioned above tabletop collision support.
6. The retained material is temporarily stabilized on the workbench during fabrication, preventing physics tunneling and enabling successive cuts. Its original anchored state is restored after leaving the session.
7. **Move the cutting guide and saw again without exiting**. After an automatic cut, hover another score and click once, or select unscored metal for normal manual sawing. RMB orbit, pan, and wheel zoom remain available. Saw flip and roll controls have been removed.
8. **Only Esc (or Exit)** ends precision mode, restores the camera, and returns the saw to its physical resting position.

## Filing a physical metal edge

1. Place a rigid unanchored file Model on the workbench, tag it `isTool = true`, and name it with `File` or set `FabricationKind = File`. Optional `FileFace` Attachment defines the physical working contact and orientation.
2. Inspect a test sheet and select the file from the same workbench tool list. The actual file moves kinematically toward the sheet—no force-driven alignment constraints or collision.
3. Hover within 0.27 studs of an exposed edge. The single green guide snaps to the real edge, including the outline of a previously curved-cut piece; it uses the current FORM contour, not the rectangular backing Part. A generic rectangular guide is not shown while no physical edge is snapped.
4. The **File Settings** section of the inspection panel lets you switch between **Round** and **Chamfer** and change **Size (mm)** with +/- buttons or an editable value. Sizes are clamped based on the selected plate thickness and validated again on the server.
5. Hold LMB to **lock the highlighted physical edge**, then file back and forth. The contact follows the locked perimeter by arc length and turns with curved segments instead of sliding along an imagined straight bounding-box edge. Release LMB to unlock and select another edge. Five qualified direction reversals apply the FORM operation at the locked edge. If no contour is nearby, the previous freehand filing movement remains available.
6. On completion, FORM generates a rounded multi-segment edge or flat chamfer. The server bakes an EditableMesh using `AssetService:CreateDataModelContentAsync` into static, replicating mesh content, and builds a welded MeshPart with convex-hull collision. The mesh is explicitly untextured, while the original Part remains invisible and non-colliding as the workpiece's identity backing.
7. Release LMB, hover another edge, and continue as often as needed. **Esc** is the regular exit. The edge lock resets on workpiece switches and material flips.

**Machined contours:** A previously cut piece with a constant-thickness prismatic solid is filed against its actual outline, including curved and concave sidewalls. Only an isolated sharp corner with adequately long incident edges receives the corner-rounding/chamfer operation. Curved segments receive a localized inward removal pass while their other contour samples stay unchanged. FORM rejects missing or unsupported shaped geometry instead of silently reverting to the rectangular backing. The resulting FORM solid remains available for another score, saw cut or file pass. Studio starts with geometry regressions enabled and logs either [OPENWORKS:FORM] success or the failure warning in Server Output. On untouched rectangular stock, the original top-edge Round/Chamfer filing behavior remains. Variable-height filing geometry still uses the original 3D plane filing path. The baked EditableMesh renderer preserves exact geometry vertices and separates face-normal smoothing from topology. Roblox physical collision remains an approximation; mesh baking still requires Creator Hub permissions.

## Scoring metal (Workspace.Scorer)

- Put the physical tool named **Scorer** directly under `Workspace` and rest it on the workbench alongside marked FORM stock. The interaction server automatically marks it as `isTool = true` and `FabricationKind = Scorer` during Play. It can be a Part or Model; fabrication mode temporarily anchors its physical parts and restores their original anchored states on exit.
- Inspect the material and select **SCORER**. Hold **LMB** on the exposed, world-up metal face and draw with the mouse. The actual `Workspace.Scorer` is moved on the client every render frame, with its working point following the filtered gold trace. The server also moves the physical tool and keeps authoritative score data. There is no local clone, and the original tool is not hidden. Release LMB to commit.
- A successful stroke is filtered, twice Gaussian-smoothed and rebuilt with an adaptive cubic spline. Its evenly spaced points are stored as JSON in the workpiece's `FORMScorePaths` attribute. A reusable gold segment pool previews that smoothed curve while drawing. A `OpenworksScoreMarks` folder contains welded, non-colliding dark groove lines that move and flip with the workpiece. Paths use local coordinates so they do not drift when the stock is repositioned.
- Up to 12 score paths with up to 256 stored spline points each are supported. Raw input is compressed adaptively when a long stroke exceeds 512 points instead of abruptly stopping recording. The server still validates the exposed face and workbench reach.
- **Manual saw cuts require no scores:** On an unscored sheet, the system generates a temporary two-point cut path from the selected axis and offset. Those endpoints now use the stock's **half-extent** instead of the full extent, avoiding the previous bogus `Score points are outside the material` error on manually cut, already-shaped pieces.
- **Automatic score cutting:** When the saw is selected, hover within 0.22 studs of a saved score and click once. The server rechecks the local-space score reference, preflights the cutting geometry, and takes control of the saw. The blade follows the actual stored points and tangent with short reciprocating motion; progress is shown in the inspection panel. No manual sawing gestures are required. Invalid paths are rejected before animation where possible. On completion, FORM produces the physical offcuts.
- **Diagonal straight cuts:** Angled scored planes use `SawCut.split` followed by the existing convex FORM mesh renderer for both offcuts. These require EditableMesh / content-baking privileges; a failure is returned without modifying the workpiece. Nearly axis-aligned scores snap to exact native X/Z planes so rectangular Part geometry stays valid.
- **Curved cutting:** Click a curved score to start the automatic operation. The server validates its path with `PathCut.split` first, animates a progressive saw sweep, then uses the validated geometry to remove a 0.8 mm kerf and produce two distinct FORM solids. The curve is not flattened to a plane. Curved cuts still need the appropriate EditableMesh / baking permissions.
- **Reusable shape cutting:** `PrismProfile.extract` obtains the current solid's actual top-face perimeter, including existing concave cuts. `PathCut.split` clips the new kerf against that perimeter, not the original rectangular backing. Repeated straight, diagonal and curved cuts on constant-thickness machined pieces are supported, and the results remain fully editable prismatic FORM solids. Scores may start or end directly at the metal's real boundary. A cut is rejected only when it is geometrically impossible for the current planar-through-cut algorithm (such as disconnected paths or a non-manifold result). Closed pockets, holes and variable-height 3D milling still require general solid boolean operations; they are not silently approximated as rectangular cuts.
- **Shaped collision:** Curved offcuts use `PreciseConvexDecomposition` rather than a single convex hull. Roblox collision approximates the shape and is not an exact per-triangle representation. EditableMesh creation and baking permissions are still required.
- In the current first pass, a completed saw split removes the old score paths from the retained backing Part. Reprojecting surviving score segments onto the two new physical fragments is follow-up work.
- For custom scorer geometry, place an optional `ScoreTip` Attachment at the actual working tip for exact orientation. Without one, the server attempts to find a Part named `Tip`, `Point`, `Nib`, or `ScoringTip`; otherwise it infers a tip from the longest dimension and aligns that shaft upright. If a particularly asymmetric model looks reversed, add `ScoreTip` rather than rewriting interaction logic.

## Receiver health

The shared `PhysicalInteraction` RemoteEvent is reused on server restart instead of creating a new one. The server installs its receiver before loading the rest of the interaction code and publishes a replicated readiness flag and heartbeat. The client stops sending movement events when the receiver is offline or stale, rather than exhausting Roblox's invocation queue. Verify `[OPENWORKS:Interaction] Server ready on ...` appears in **server Output** on a fresh Play session. If a Studio/Rojo reload leaves a stale remote, stop and restart Play before testing further.

## Scope and safety

- Both split pieces carry their actual mesh solids, and scored or manual straight/curved cuts reuse constant-thickness contour geometry. Imported solids without a `FORMNativeStock` backing Part still need an adapter.
- Repeated prismatic contour machining is supported. True arbitrary 3D booleans (complex holes, already-rounded varying-height stock, split paths generating three or more islands), exact collision, and CNC-grade tolerances remain separate geometry-kernel work. These are architectural limits of the current algorithm, not artificial gameplay prerequisites.
- This code has been reviewed/committed on GitHub but **has not been tested inside Roblox Studio**. In Studio, verify: detection, grabbing, click selection, camera orbit, tool positioning, gold guide, manual stroke progress, two physical offcuts, and ESC restoration.
