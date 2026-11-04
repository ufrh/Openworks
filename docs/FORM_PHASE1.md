# FORM Phase 1 — Parametric primitive editor

## Correct construction model

FORM is a **primitive-based engineering editor**, not a freeform Boolean modeler. A component contains one editable parametric primitive. The user cannot add Boolean operands or run Union/Subtract in the construction interface.

- **Block and Cylinder** are ordinary native Roblox Parts. Translation, rotation, and resizing update their `CFrame` and `Size` directly, without CSG or replacement.
- **Tube and Hole Block** are named parametric templates. Their internal cylindrical voids are manufactured using `GeometryService:SubtractAsync` only when the template dimensions or its bore/wall parameter changes enough to require it.
- Tubes and hole blocks start as solid 0.05 × 0.05 × 0.05-stud envelopes; their internal opening becomes valid only after dimensions allow it.
- **Moving and rotating any primitive, including a CSG-manufactured special primitive, must not trigger a Boolean operation.**
- While resizing an existing special primitive, its **single visible solid** updates immediately. Its internal cut is manufactured once after mouse release. A tiny amount of temporary cut distortion may occur during stretching, until the final parametric rebuild.
- The old subtract/add editor controls, operand stacks, and duplicate ghost previews have been removed.

This architecture is extendable with later *named primitives* such as Curved L, rounded corner, brackets, etc. Such templates define their own parameters and internal manufacturing, rather than exposing unrestricted Boolean editing.

## Camera and grid

- The workspace/grid and orbit target are fixed at world (0,0,0); no pan.
- RMB/MMB drag: orbit; Ctrl+MMB or mouse wheel: smooth hybrid FOV + dolly zoom.
- Top-right orientation gizmo can be dragged for orbit, clicked for axis views, or its lower Zoom button dragged vertically.
- Numpad cardinal views and F/Home zoom-to-fit retain the fixed origin.
- Adornment grid lines are 0.05 studs apart over a fixed 6×6-stud patch.

## Transform UI and test

1. Sync `dev`, connect Rojo at localhost:34872, and enter Studio Play.
2. Spawn **Block** (0.05 studs per axis). Select **S** for face resize: there are separate handles on **Left, Right, Top, Bottom, Front and Back**. Drag Top outward: only the top face should move; the bottom stays anchored. Drag Bottom: only the bottom should move.
3. Use **G** to move, **R** to rotate. The previous stock Roblox handles and arc handles are restored, with a smaller interaction proxy.
4. Check that ordinary Block/Cylinder resizing, moving, and rotating changes the single visible solid immediately with **no visible duplicate/trailing ghost and no CSG rebuilding**.
5. Spawn **Hole Block**, resize until it supports an opening, and set its **HOLE** diameter. CSG should run to manufacture that internal hole. Subsequent **G/R** movements should transform the same geometry without any rebuild.
6. Resize the Hole Block again: the current solid follows the drag instantly, then FORM remanufactures the exact inner hole on release.
7. For tubes and cylinders, X and Z represent a linked radial diameter, rather than independent rectangular face dimensions.

## Source

- `src/shared/FORM/Document.lua`: one parametric primitive per component, 0.05 stud and 15° precision.
- `src/shared/FORM/Compiler.lua`: only manufactures internal cuts for special templates.
- `src/client/Preview.lua`: one visible instance; native property updates and size-change-triggered template manufacture.
- `src/client/TransformGizmo.lua`: restored Roblox handles with all six face grips, opposite-face anchored scaling.
- `src/client/FORMDebug.lua`: primitive creation and numeric editing; no unrestricted Boolean tools.

## Limits

- GeometryService can fail on very small features; a 0.05-stud grid does not guarantee a 0.05-stud watertight hole.
- This is local and unsaved. Server shipping, multiplayer, constraints, and FORGE integration are not implemented.
- GitHub source verification is not a Roblox Studio runtime test. Verify all six faces and inspect Output if a special template cannot manufacture a cut.
