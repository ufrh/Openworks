# OPENWORKS — Physical interaction and precision workbench

> Stability rollback: the experimental on-the-fly material switching and recent saw orientation rewrite were temporarily disabled after a regression. Exit and re-enter precision mode to change workpieces. The existing `BladeEdge` attachment and `R` tool-roll controls remain available.

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

The physical tool is never cloned into a separate cosmetic. **Precision fabrication does not use AlignPosition or AlignOrientation.** Instead, the server temporarily anchors the entire rigid tool assembly and interpolates its pivot toward the blade-aligned target each Heartbeat (smooth kinematic CFrame motion). Every working tool part stays non-collidable, non-touchable, and non-queryable during the session. On exit, it returns to its resting pose above the tabletop, then its original anchor and collision states are restored. **Normal free dragging continues to use physics constraints**, unchanged.

For saws without an authored `BladeEdge`, the initial tool roll now starts inverted 180° relative to the old fallback. This corrects the upside-down default for the test saw; `R` / `Shift+R` remain available to adjust custom tool geometry. A properly oriented `BladeEdge` Attachment continues to override the fallback without the automatic flip.

## Free-mode interaction

- **Hold LMB** on material or tool: physically lift and drag it. Release to drop.
- **Very short LMB click**: select instead of carry.
- While dragging, **wheel** changes reach; **Shift + WASD** rotates the assembly.

## Material inspection

- Short-click a material, or short-click a tool when exactly one workpiece is on the bench.
- **RMB drag** orbits; **MMB drag** pans; **wheel** zooms around the physical workpiece. Entering inspection and refocusing on another material ease toward the target instead of snapping. Exiting blends the inspection camera back to the gameplay camera over roughly 0.65 seconds.
- In the right-side panel, select a saw/file that is physically present on the bench.
- **P — Position Material:** Pause machining while keeping the same real sheet selected and secured. Drag it with LMB along the workbench on a **0.04-stud (1 mm) grid**. The server clamps its footprint to an authored `surface` and raises it above the tabletop after each move or rotation.
- **Flip / rotate:** Use `X` / `Z` for 90° local-axis tilts (Shift reverses), `F` / `G` for 180° flips around local X/Z, and `Y` for 15° turns (Shift reverses). The positioning panel also contains physical buttons for these operations. Press `P` again to resume fabrication; `Esc` still exits inspection altogether. RMB camera orbit remains available.
- **Accessible filing edges:** The teal filing guide and file toolpath adapt to whichever local face points upward after repositioning. Flipping makes the underside edges accessible; tilting a plate onto its side exposes other edge pairs. The real file travels end-to-end along the selected exposed edge.
- **Saw clearance and direction:** During each saw stroke, the tool's rotated bounding box is checked against the top of the current workpiece; it is elevated rather than allowed to dip beneath the cutting surface. Both saw and file travel directions have been reversed relative to earlier builds.
- **Escape** exits, restores normal camera, and releases the temporary kinematic fabrication control. Finishing a cut, filing pass, or repositioning does **not** exit inspection.
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
4. The **File Settings** section of the inspection panel lets you switch between **Round** and **Chamfer** and change **Size (mm)** with +/- buttons or an editable value. Sizes are clamped based on the selected plate thickness and validated again on the server. Rotate or flip the workpiece with P to work on a different face before filing; its original FORM geometry stays attached to the same physical Part.
5. Hold LMB and move the mouse back and forth. The physical file now sweeps almost the full edge length, from one endpoint to the other. Five qualified direction reversals apply a real FORM geometry modification to the chosen top edge.
6. On completion, FORM generates a rounded multi-segment edge or flat chamfer. The server bakes an EditableMesh using `AssetService:CreateDataModelContentAsync` into static, replicating mesh content, and builds a welded MeshPart with convex-hull collision. The mesh is explicitly untextured, while the original Part remains invisible and non-colliding as the workpiece's identity backing.
7. Release LMB, hover another edge, and continue as often as needed. **Esc** is the only regular exit.

**Limitations:** The current physical renderer supports convex edge geometry and hull collision rather than perfect microscopic contact fidelity. Re-filing the exact same previously rounded edge may be refused by the FORM edge detector; select a different unworked edge. Sawing an already filed mesh is blocked until the mesh-aware saw split adapter is installed. EditableMesh and static content baking require appropriate Creator Hub Mesh / Image API permissions and sufficient mesh memory; failures are reported rather than silently resizing the stock. Direct server EditableMesh references caused a magenta/cyan placeholder on clients, which is why finished geometry is now baked into replicating data-model content.

## Receiver health

The shared `PhysicalInteraction` RemoteEvent is reused on server restart instead of creating a new one. The server installs its receiver before loading the rest of the interaction code and publishes a replicated readiness flag and heartbeat. The client stops sending movement events when the receiver is offline or stale, rather than exhausting Roblox's invocation queue. Verify `[OPENWORKS:Interaction] Server ready on ...` appears in **server Output** on a fresh Play session. If a Studio/Rojo reload leaves a stale remote, stop and restart Play before testing further.

## Scope and safety

- Saw geometry edits currently work only on unfiled rectangular native `Part` stock marked `FORMNativeStock = true`. Already-filed shapes are preserved and rejected with an explicit message until mesh-aware sawing is added.
- No fake tilted/oblique saw-cut mode is presented: the native-Part fragment renderer supports only the X/Z straight cut directions. More complex FORM split results require physical EditableMesh output.
- This code has been reviewed/committed on GitHub but **has not been tested inside Roblox Studio**. In Studio, verify: detection, grabbing, click selection, camera orbit, tool positioning, gold guide, manual stroke progress, two physical offcuts, and ESC restoration.
