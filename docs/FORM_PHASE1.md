# FORM — Phase 1: construction sandbox

## Working slice

- Each newly created component retains editable parametric nodes rather than permanently replacing its source with a union.
- Primitives: Block, Cylinder (Y-axis), Tube, Hole Block.
- A node is **Add** or **Subtract**. The first node must be additive. Additional node operations compile in list order using GeometryService.
- Numeric transforms: Position (X/Y/Z), Size (X/Y/Z), Rotation (X/Y/Z); tube wall and hole bore where relevant.
- Positions and dimensions snap to 0.05 studs. Rotation snaps to 15 degrees. Minimum allowed size is 0.05 studs.
- CSG is computed locally and asynchronously; obsolete results are discarded after newer edits.
- Multiple nodes form one logical editable component and compile into one non-splitting solid.
- Entire preview is local, anchored, and non-collidable. It is not persisted, simulated, shipped, or replicated.

## Try it in Studio

1. Open the configured OPENWORKS place and start Rojo with `START_OPENWORKS.bat`. Connect Studio to port 34872.
2. Enter **Play**. The temporary `FORM // DEBUG 01` panel appears.
3. Click **Block** and select it (or select it by clicking the solid).
4. Click **- Cylinder**. You should see a centered vertical cylindrical cut through the block.
5. Navigate to the cutter using **Next Node >**, then change its **SIZE X** (diameter; Z stays equal). Press Enter or unfocus the box to recompile.
6. Edit **POS**, **SIZE**, **ROT** of any selected node. Use **< Prev Node** to edit the original block.
7. Try **Tube** and **Hole Block** as fresh components.
8. Orbit with right-mouse drag, pan with middle-mouse drag, zoom with the wheel, and focus the selected node with F.

The panel and scene grid are intentionally plain. The viewport preview is only a debug harness, not final Duotone.

## Constraints and deliberate omissions

- No save/load, multiplayer sync, permission validation, server compilation, shipping, physics, constraints, or FORGE integration yet.
- One component represents one CSG solid. Disconnected unions may fail and will surface an error instead of silently creating extra bodies.
- No 3D transform handles yet: precise transforms are entered numerically.
- A component's first additive node cannot be deleted from the debug panel; delete the entire component instead.
- 0.05 studs is the model/grid precision, **not a guarantee** that Roblox CSG can successfully resolve every feature at that scale.
- Roblox may simplify complex CSG meshes (20k triangle limit); collision fidelity and geometry precision need runtime testing.
- A successful repository commit does **not** prove Studio CSG will succeed on the target place. Test the cuts in Play mode and inspect the Output window if something fails.

## Technical boundaries

- `src/shared/FORM/Quantize.lua`: precision rules.
- `src/shared/FORM/Document.lua`: pure parametric state model.
- `src/shared/FORM/Compiler.lua`: CSG operations via `GeometryService:UnionAsync` and `SubtractAsync`.
- `src/client/Preview.lua`: async revision-aware preview management.
- `src/client/FORMDebug.lua`: temporary editor controls and camera.
- `src/client/init.client.lua`: starts the harness.

Roblox documentation: https://create.roblox.com/docs/reference/engine/classes/GeometryService
