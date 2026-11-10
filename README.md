# OPENWORKS

A Roblox mechanical construction and engineering sandbox. The active `dev` branch includes the Phase 05 mechanical relationship authoring prototype: first-person native Roblox Tools, primitive catalog, drag resizing, placement/editing, undo/redo, multi-selection, editable rigid component groups, dark gray Metal primitives, layered depth selection, X-ray/isolation, and guided coaxial alignment (L in Edit), first-person Assemble tool authoring Bearing/Slider/Fixed constraints, and fixed 0.5-U sizing and movement increments. The pre-redesign editor is preserved in an archive branch.

## Direction

**GearBlocks is the main experience and interaction reference** for placing, snapping, aligning, connecting, and operating mechanical parts. OPENWORKS should expand that concept without making the editor harder to use.

Current guiding decisions (details will be finalized in the new design document):
- GearBlocks-like scale; no microscopic voxel resolution for its own sake.
- Modular building with adjustable sizing increments, but no mandatory position-grid validation; curved shapes and prefabs such as gears and shafts.
- Custom rigid parts built from modular/voxel material, then optimized into finished components.
- No reliance on destructive CSG modeling or arbitrarily scaling finished components.
- Functional mechanical relationships and intuitive assembly, with room to expand transmissions, flexible elements, and electronics.
- Design and document the experience before implementing the new game systems.

## Framework preserved

- `src/forge-shared/` — original FORGE/Reforge 4.4.1 shared Kernel, API, Engine, UI.
- `src/forge-server/` — FORGE server networking.
- `default.project.json` — existing Rojo mappings, place ID, and port 34872.
- Local scripts and Roblox toolchain configuration.

Game-specific code lives in `src/client/`, `src/server/`, and `src/shared/Construction/`. The primitive library comes from the Studio generator and must be saved in the place. Phase 05 usability fixes need a Studio playtest; see `docs/PHASE_05_USABILITY_TEST.md`. Components are logical rigid groups in anchored construction mode; mechanical relationships are stored as real server-owned Roblox Hinge/Prismatic/Weld constraints, but construction stays anchored until shipping/simulation in a later phase.

## Run

On the `dev` branch run `START_OPENWORKS.bat`, connect the Rojo plugin to `localhost:34872`, and press Play. Client and server should log the framework version. Construction and layered editing are wired, but gameplay behavior must be verified with the in-Studio smoke test.

If you already have OPENWORKS open in Studio, restart the play session and clear any stale game-specific instances that may survive Rojo synchronization; the existing project uses `$ignoreUnknownInstances`.

## Archive

The full pre-redesign implementation (FORM, editor, assemblies, simulation, verification scripts, docs) is preserved in:

`archive/pre-gearblocks-redesign-2026-11-08`

Previous archive `archive/pre-foundation-reset-2026-11-03` and the `main` branch remain untouched.

See `docs/REBUILD_NOTES.md` for the reset boundary and next design step.


## Current usability changes
- Alignment uses the actual hole/shaft world-space axis and offset without a grid-based position rejection. 0.5-U insertion nudges are the interface default.
- Moving a component onto a surface calculates the whole assembly's lowest geometry point, rather than burying its outer pieces below the floor.
- Placement and shaft insertion previews are blue when collision-free and red for intersections. Red previews cannot be finalized; the server remains the final authority.
- Resizing defaults to 0.5 U, with [ / ] selecting 0.25, 0.5, 1, or 2 U.
- A contextual shortcuts list appears on the right for the equipped Tool and current operation.
- Edit supports Delete for pieces/components; Assemble supports Delete for an authored relationship on the aimed part.


## Cohesion and interaction pass — 2026.11.09.PHASE05.PHYSICAL-CONTEXT
- In Edit, a click selects; **hold and move/look to drag** a selected primitive/component. Release positions it through the same temporary G-move workflow. **G** remains a separate placement mode.
- Physical scale controls use six smooth colored sphere grips, with no Neon bloom. There are no move-arrow or rotation-ring controls.
- Whole components use one continuously updated selection bounds outline, not a separate Highlight outline per member.
- The right controls panel lists only relevant keybinds for the active Tool's current substate (catalog, normal edit, scale, alignment, move, assemble selection/placement).
- Live red/blue feedback describes the actual interfering model. Selecting a hollow bore permits the intended *cylindrical shaft* to overlap its collision representation ONLY after a metadata-derived radial clearance test. The rest of the moving assembly still undergoes full collision tests.
- Exact bore metadata is read from Studio Generator v4 (`HoleDiameterU`, `InnerDiameterU`, `InnerWidthU`, `InnerHeightU`, `WallU`), including tube cross-section resizing.
- World position is not subject to a mandatory grid test. Size increments stay quantized; surface support and range/collision/ownership rules remain authoritative.
- Rotation rings are removed: dragging never rotates geometry. Existing R/T/Y discrete rotation shortcuts remain unchanged.


## Move-only drag and half-Unit cleanup
- **Single click selects** the same way as before. It never starts a move. A second deliberate hold-and-drag on the already selected primitive/component begins a temporary move and releases to place; the `G` move shortcut remains available.
- **No rotation-on-drag**. No rotation rings or ring capture; R/T/Y are still the only rotation inputs.
- **Fixed 0.5 U** increments for new size changes, drag-move displacement, insertion-depth nudges, and ordinary placement snapping. No [ / ] step-size adjustment. Older geometry with 0.25-U dimensions remains readable/valid; the server does not reject world positions for missing a grid.
- Scale grips are **colored smooth non-blooming spheres**. Their SmoothPlastic material and fill-only Highlights mimic vivid neon hues without Neon-material bloom; no cube borders.
- Component/single-part selection highlighting is preserved.


## Direct drag only (2026-11-10)
- Removed the move-arrow gizmo and all its input bindings. Edit selection continues to work with one click; holding and moving a previously selected object or component starts the existing temporary move, with surface-aware placement and red/blue collision feedback.
- The G move shortcut remains available, but no physical axis-move handles are displayed. R/T/Y rotation and V spherical scaling are unchanged.
