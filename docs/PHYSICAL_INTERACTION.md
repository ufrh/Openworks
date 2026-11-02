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

The physical tool is never cloned into a separate cosmetic. **Precision fabrication does not use AlignPosition or AlignOrientation.** Instead, the server temporarily anchors the entire rigid tool assembly and interpolates its pivot toward the blade-aligned target each Heartbeat (smooth kinematic CFrame motion). Every working tool part stays non-collidable, non-touchable, and non-queryable during the session. On exit, it returns to its resting pose above the tabletop, then its original anchor and collision states are restored. **Normal free dragging continues to use physics constraints**, unchanged.

## Free-mode interaction

- **Hold LMB** on material or tool: physically lift and drag it. Release to drop.
- **Very short LMB click**: select instead of carry.
- While dragging, **wheel** changes reach; **Shift + WASD** rotates the assembly.

## Material inspection

- Short-click a material, or short-click a tool when exactly one workpiece is on the bench.
- **RMB drag** orbits; **MMB drag** pans; **wheel** zooms around the physical workpiece.
- In the right-side panel, select a saw/file that is physically present on the bench.
- **Escape** exits, restores normal camera, and releases the temporary kinematic fabrication control. Finishing a cut or filing pass does **not** exit inspection.
- The inspection camera no longer requires the default Roblox `PlayerModule`, which may not exist in customized player scripts.

## Saw positioning and cutting

1. Select the steel sheet, then the saw. The real saw is aligned to the workpiece using `BladeEdge` (or the tool-bounds fallback).
2. A narrow **gold cutting guide** appears on the sheet. Move the mouse over the metal to position it. **Shift + horizontal mouse movement** also adjusts the cut offset.
3. Press **Q** to switch between cuts normal to local X and local Z on native rectangular stock.
4. **Hold LMB and manually move the mouse back and forth**. The actual physical saw follows each stroke; input is deliberately more sensitive for comfortable short wrist movements. Repeated direction reversals advance progress; releasing the mouse pauses.
5. When five qualifying stroke reversals complete, the server calls `SawCut.split` using FORM. The larger retained piece **remains the same Part and remains selected** (only its dimensions and CFrame change). An offcut appears as a separate unanchored, tagged physical Part. Both are positioned above tabletop collision support.
6. The retained material is temporarily stabilized on the workbench during fabrication, preventing physics tunneling and enabling successive cuts. Its original anchored state is restored after leaving the session.
7. **Move the cutting guide and saw again without exiting**. Progress resets for the next cut. Release LMB before starting another stroke sequence. RMB orbit, pan, wheel zoom and R/Shift+R tool roll continue to work.
8. **Only Esc (or Exit)** ends precision mode, restores the camera, and returns the saw to its physical resting position.

## Filing a physical metal edge

1. Place a rigid unanchored file Model on the workbench, tag it `isTool = true`, and name it with `File` or set `FabricationKind = File`. Optional `FileFace` Attachment defines the physical working contact and orientation.
2. Inspect a test sheet and select the file from the same workbench tool list. The actual file moves kinematically toward the sheet—no force-driven alignment constraints or collision.
3. Hover the sheet near any edge. A **teal line** previews which of the four top-side X/Z edges is selected.
4. Hold LMB and move the mouse back and forth. Five qualified direction reversals shave approximately **0.024 studs** off the selected side, translating the same Part to keep the opposite edge fixed. This is a measurable physical edge-sizing operation, not a fabricated hit counter.
5. Release LMB, hover another edge, and continue as often as needed. **Esc** is the only regular exit.

**Current representation limit:** Rectangular native Parts can be resized to file their sides, but they cannot visibly round/chamfer an edge. The existing `FileShape` geometry kernel supports edge-rounding solids, but rendering those true shapes requires a FORM-to-EditableMesh replacement path. No fake curved filing is claimed in this phase.

## Receiver health

The shared `PhysicalInteraction` RemoteEvent is reused on server restart instead of creating a new one. The server installs its receiver before loading the rest of the interaction code and publishes a replicated readiness flag and heartbeat. The client stops sending movement events when the receiver is offline or stale, rather than exhausting Roblox's invocation queue. Verify `[OPENWORKS:Interaction] Server ready on ...` appears in **server Output** on a fresh Play session. If a Studio/Rojo reload leaves a stale remote, stop and restart Play before testing further.

## Scope and safety

- Saw geometry edits currently work only on rectangular native `Part` material with `FORMNativeStock = true`; arbitrary imported/EditableMesh FORM pieces need a mesh replacement adapter. The UI reports unsupported machining instead of deleting geometry.
- No fake tilted/oblique saw-cut mode is presented: the native-Part fragment renderer supports only the X/Z straight cut directions. More complex FORM split results require physical EditableMesh output.
- This code has been reviewed/committed on GitHub but **has not been tested inside Roblox Studio**. In Studio, verify: detection, grabbing, click selection, camera orbit, tool positioning, gold guide, manual stroke progress, two physical offcuts, and ESC restoration.
