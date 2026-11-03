# OPENWORKS — Physical interaction and precision workbench

All interactions use actual Workspace objects. No Roblox Tool, Backpack, hotbar, or old fabrication UI.

## Required workshop objects

- `Workspace.Workbench` contains one or more BaseParts named `surface` (case-insensitive). Server creates invisible tabletop supports and overlap-query regions.
- A physical saw or file is a rigid, welded, unanchored Model or BasePart tagged with Boolean attribute `isTool = true`. Clickable geometry must have `CanQuery = true`.
- Tool operation is selected by String attribute `FabricationKind = Saw` or `File`, or inferred from the Model name containing `saw` or `file`.
- Materials are `FORMMaterial` tagged and `isMaterial = true`. The Studio **Spawn Test Sheet** button makes an unanchored physical steel sheet with `FORMNativeStock = true`, which supports the native rectangular-stock operation.
- Both tool and selected material must settle onto the Workbench to enter precision fabrication; their `OnWorkbench` attributes are set by the existing detector.

## Optional tool contact attachments

Add an **Attachment** named `BladeEdge` anywhere inside the welded saw model to precisely define the working blade contact. Its local **+X** is the stroke direction, **+Y** points out of the stock, and **+Z** is the cutting-plane normal.

Add `FileFace` to a file if desired. Without `BladeEdge`, OPENWORKS first looks for a BasePart named `Blade`, `SawBlade`, or `BladePart` and aligns the longest axis of that blade. If no blade is found, it uses the full tool's bounds, following the earlier saw visual alignment convention. A hand-authored attachment is still the accurate option for custom Blender geometry.

In precision mode, **R** rolls the physical tool 90 degrees around the stroke axis; **Shift+R** rolls it back 90 degrees. This does not change the cut plane and lets you correct models whose grip/blade faces are oriented differently.

Saw orientation is explicitly calibrated rather than inferred from part color, names, or guessed blade geometry. The saw now starts in the orientation previously obtained by pressing **F** after spawn (the opposite of the older default). Set `SawFlip180 = true` on the physical saw model to override it with the earlier orientation. In precision mode, press **F** or click **FLIP SAW 180°** to toggle that roll immediately without restarting sawing; the selection is stored as the `SawFlip180` attribute on the physical saw for the current Play session. To make the choice permanent across fresh Studio Play sessions, set `SawFlip180` to the tested value on the saw model in Studio. The original `BladeEdge` Attachment is still supported for precise tool contact positioning; the top-of-workpiece clearance and **R** roll controls are unchanged.

The physical tool is never cloned into a separate cosmetic. **Precision fabrication does not use AlignPosition or AlignOrientation.** Instead, the server temporarily anchors the entire rigid tool assembly and interpolates its pivot toward the blade-aligned target each Heartbeat (smooth kinematic CFrame motion). Every working tool part stays non-collidable, non-touchable, and non-queryable during the session. On exit, it returns to its resting pose above the tabletop, then its original anchor and collision states are restored. **Normal free dragging continues to use physics constraints**, unchanged.


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
4. **Hold LMB and manually move the mouse back and forth**. The actual physical saw follows each stroke; input is deliberately more sensitive for comfortable short wrist movements. Repeated direction reversals advance progress; releasing the mouse pauses.
5. When five qualifying stroke reversals complete, the server calls `SawCut.split` using FORM. The larger retained piece **remains the same Part and remains selected** (only its dimensions and CFrame change). An offcut appears as a separate unanchored, tagged physical Part. Both are positioned above tabletop collision support.
6. The retained material is temporarily stabilized on the workbench during fabrication, preventing physics tunneling and enabling successive cuts. Its original anchored state is restored after leaving the session.
7. **Move the cutting guide and saw again without exiting**. Progress resets for the next cut, but the cut position no longer snaps to the center: the new aim is projected near the cursor over the retained piece, falling back to the previous cut point. Release LMB before starting another stroke sequence. RMB orbit, pan, wheel zoom and R/Shift+R tool roll continue to work.
8. **Only Esc (or Exit)** ends precision mode, restores the camera, and returns the saw to its physical resting position.

## Filing a physical metal edge

1. Place a rigid unanchored file Model on the workbench, tag it `isTool = true`, and name it with `File` or set `FabricationKind = File`. Optional `FileFace` Attachment defines the physical working contact and orientation.
2. Inspect a test sheet and select the file from the same workbench tool list. The actual file moves kinematically toward the sheet—no force-driven alignment constraints or collision.
3. Hover the sheet near any edge. A **teal line** previews which of the four top-side X/Z edges is selected.
4. The **File Settings** section of the inspection panel lets you switch between **Round** and **Chamfer** and change **Size (mm)** with +/- buttons or an editable value. Sizes are clamped based on the selected plate thickness and validated again on the server.
5. Hold LMB and move the mouse back and forth. Mouse movement maps to fixed stud increments, independent of material dimensions. The filing contact sweeps along the entire selected exposed edge, clamped precisely at its two endpoints. Saw strokes use a fixed physical range too. Five qualified direction reversals apply a FORM geometry modification to the world-up edge.
6. On completion, FORM generates a rounded multi-segment edge or flat chamfer. The server bakes an EditableMesh using `AssetService:CreateDataModelContentAsync` into static, replicating mesh content, and builds a welded MeshPart with convex-hull collision. The mesh is explicitly untextured, while the original Part remains invisible and non-colliding as the workpiece's identity backing.
7. Release LMB, hover another edge, and continue as often as needed. **Esc** is the only regular exit.

**Limitations:** The current physical renderer supports convex edge geometry and hull collision rather than perfect microscopic contact fidelity. Re-filing the exact same previously rounded edge may be refused by the FORM edge detector; select a different unworked edge. Previously filed convex solids can now be sawed: the source FORM solid is split, and two new shaped mesh visuals are baked for the retained workpiece and offcut. Mesh creation failures leave the original geometry unchanged. EditableMesh and static content baking require appropriate Creator Hub Mesh / Image API permissions and sufficient mesh memory; failures are reported rather than silently resizing the stock. Direct server EditableMesh references caused a magenta/cyan placeholder on clients, which is why finished geometry is now baked into replicating data-model content.

## Scoring metal (Workspace.Scorer)

- Put the physical tool named **Scorer** directly under `Workspace` and rest it on the workbench alongside marked FORM stock. The interaction server automatically marks it as `isTool = true` and `FabricationKind = Scorer` during Play. It can be a Part or Model; fabrication mode temporarily anchors its physical parts and restores their original anchored states on exit.
- Inspect the material and select **SCORER**. Hold **LMB** on the exposed, world-up metal face and draw with the mouse. The visible scoring tool is locally positioned at the same filtered tip that produces the temporary gold trace; the server also tracks that tip for other clients. Release LMB to commit it. Smoothing removes small jitter without the previous excessive lateral lag when drawing bends.
- A successful stroke is simplified into a bounded polyline and written as JSON to the stock Part's `FORMScorePaths` attribute. A `OpenworksScoreMarks` folder contains welded, non-colliding dark groove lines that move and flip with the workpiece. Paths use local coordinates so they do not drift when the stock is repositioned.
- Up to eight paths and 128 input points per path are retained. The tool still requires proximity to the workbench and validates every submitted point against the exposed face on the server.
- **Saw guidance:** When the saw is selected, hover within 0.22 studs of a saved score. Straight scores at any angle engage the thin green guide and orient the physical saw along the stored tangent as it strokes. The client sends the local-space score reference; the server independently rechecks the path before each motion and uses its cutting plane for the actual FORM split, not a loose screen-space offset. Short scores can qualify; their extended plane cuts all the way through the stock on completion.
- **Diagonal straight cuts:** Angled scored planes use `SawCut.split` followed by the existing convex FORM mesh renderer for both offcuts. These require EditableMesh / content-baking privileges; a failure is returned without modifying the workpiece. Nearly axis-aligned scores snap to exact native X/Z planes so rectangular Part geometry stays valid.
- **Curved-score safety:** Hovering a genuinely curved score shows a clear unsupported-cut message. LMB is prevented from performing a misleading straight-plane split while the cursor is engaged with that score. Move off the curve for freehand straight sawing.
- **Curved scores are not yet cuttable.** Their guides are recorded and visible, but the existing FORM saw splitter is planar and cannot reproduce a curved kerf. Cutting a curved score would require a genuine swept-kerf split, so it is intentionally not claimed as a supported material-removal operation.
- In the current first pass, a completed saw split removes the old score paths from the retained backing Part. Reprojecting surviving score segments onto the two new physical fragments is follow-up work.
- For custom scorer geometry, place an optional `ScoreTip` Attachment at the actual working tip for exact orientation. Without one, the server attempts to find a Part named `Tip`, `Point`, `Nib`, or `ScoringTip`; otherwise it infers a tip from the longest dimension and aligns that shaft upright. If a particularly asymmetric model looks reversed, add `ScoreTip` rather than rewriting interaction logic.

## Receiver health

The shared `PhysicalInteraction` RemoteEvent is reused on server restart instead of creating a new one. The server installs its receiver before loading the rest of the interaction code and publishes a replicated readiness flag and heartbeat. The client stops sending movement events when the receiver is offline or stale, rather than exhausting Roblox's invocation queue. Verify `[OPENWORKS:Interaction] Server ready on ...` appears in **server Output** on a fresh Play session. If a Studio/Rojo reload leaves a stale remote, stop and restart Play before testing further.

## Scope and safety

- Saw geometry now accepts previously filed rectangular-backed FORM workpieces. Both split pieces retain their actual altered mesh surfaces. Imported solids without a `FORMNativeStock` Part backing remain unsupported.
- No fake tilted/oblique saw-cut mode is presented: the native-Part fragment renderer supports only the X/Z straight cut directions. More complex FORM split results require physical EditableMesh output.
- This code has been reviewed/committed on GitHub but **has not been tested inside Roblox Studio**. In Studio, verify: detection, grabbing, click selection, camera orbit, tool positioning, gold guide, manual stroke progress, two physical offcuts, and ESC restoration.
