# OPENWORKS UI v2 — Phase 2 visualization implementation

**Date:** 2026-11-12
**Branch:** `feature/ui-reorganization-v2` (do not merge to `dev` without Studio playtesting)
**Scope:** Shared local-only visualization system for selection, assembly, mechanical connections, construction ghosts and mechanical relationship cues.
**Status:** Source implementation committed; GitHub Python source-contract CI runs on this branch. Roblox Studio gameplay/performance and arbitrary CSG visual accuracy remain unverified.

## New client rendering modules

- `src/client/Controllers/VisualFeedback.lua` — central 12-line oriented bounding-box renderer, scoped owner layers, color roles, priority suppression, transient success pulse and automatic stale/expired cleanup. One folder: `Workspace.OPENWORKS_UIV2_Feedback`.
- `src/client/Controllers/GhostWireframe.lua` — geometry-following lines for native Box/Cylinder/Ball `Part` primitives; 0.65 transparent visual ghost; bounded to 384 strokes and refreshed at ~12.5Hz; orientation and translation are bound to ghost parts.
- `src/client/Controllers/WorldVisuals.lua` — rewritten authored relationship adornments with simple bearing/motor arcs, prismatic travel lines, cylindrical combined movement, native blue springs, and a manager-owned grounding/free state.
- The manager is instantiated once from `src/client/init.client.lua` and supplied to the existing Build/Edit, Mechanics, Assembly Editor, WorldVisuals and inspector controllers. Existing mechanical/CSG/persistence services remain unchanged.

## Color and shape vocabulary

| Context | Rendering |
| --- | --- |
| Hovered or selected primitive | One thin aqua-blue 12-edge outline at exact oriented part extents, no fill |
| Whole editor component | One bounding box aligned to its editor anchor local axes |
| Unrelated multi-selection | One independent aqua box per selected primitive |
| Targeted saved assembly | One whole-assembly purple box, no extra per-member outlines |
| Assembly membership editing | One purple box per included primitive, never implicitly complete a partial component |
| Pending first/second mechanical participants | Orange box per participant, with rejected participant turning red |
| Real connection success | Brief ~0.42s green boxes for the actual participants only **after** a successful server response |
| Authored grounded vs freely movable | Green vs blue boxes, shown during Assembly & Simulation |
| Placement/fit/resize ghost | 0.65 transparent geometry; cyan valid and red invalid strokes |
| Bearing (passive) | Blue 180° circular arrow + green fixed-origin dot |
| Bearing motor (enabled) | Orange half-circle arrow + tiny POW label |
| Slider | Blue travel line, green end dots, blue current-position dot |
| Cylindrical | Blue travel line and rotational arc, with dots |
| Spring | Existing native spring coil with blue BrickColor in authored world |
| Weld / Fixed / Bolt / Gear | No redundant persistent relationship artwork |

No helper Parts are generated for bounding boxes or joint guidance. Collider/geometry validation remains server-authoritative and identical.

## Migrated existing controllers

- `ConstructionController`: selection, whole components, multiselection, hover, smart snap target and Build/resize ghosts; forward/reverse Build/Edit smart-mates show orange pending geometry and flash real server-confirmed participants green, after a bounded replication lookup for new placements.
- `LayeredEditingController`: manual bore target cue, and precision alignment preview.
- `AssemblyController`: manual housing/shaft connections, Weld, Spring, crank coupling and mechanical fitting ghosts.
- `AssemblyToolController`: purple whole assembly vs per-member states.
- `RelationshipProperties`: inspector selection uses the shared renderer.
- `WorldVisuals`: grounding and relationship guides use shared state and minimal adornments, no highlight fills.

## Important limitations: DO NOT represent these as complete

1. **Exact cut/mesh edges of CSG PartOperation**: Roblox does not provide an established safe synchronous mesh-edge extraction path in the current project. GhostWireframe draws part-oriented extents for these objects, and shape-specific curves for supported native primitive Parts. A drilled block, ring, complex gear teeth, or CSG hole may therefore have a simplified wireframe even though the translucent solid and collision validation use the proper shape. Real per-triangle outlines for arbitrary CSG remain future work.
2. **Exact localized red overlap on CSG surfaces**: Existing `PreviewFeedback.Check` validates real intersection with `GetPartsInPart` and correctly rejects invalid placement. The current ghost renders invalid geometry red, not yet the exact subset of intersecting CSG edges. Exact localized collision rendering requires a separate robust surface-intersection implementation and a performance budget.
3. **Roblox Studio verification**: GitHub Actions runs static Python contract checks, not Luau compilation or a playable Studio session. The source still needs practical playtesting, including effects of arc geometry and client adornment visibility. The native spring Color property is BrickColor, so it will use Roblox's nearest available blue.
4. **Legacy instructional HUDs and remaining utility visual folders**: Their removal is planned for later UI v2 phases; Phase 2 replaces the overlapping selection and joint rendering but does not yet deliver the unified Explorer, Properties or context menus.

## Manual acceptance cases

- Start the branch, check marker `2026.11.12.UI-V2-PHASE2-VISUALS`, and verify exactly one `OPENWORKS_UIV2_Feedback` manager under Workspace.
- Hover a single primitive and a rotated grouped component; single zero-padded aqua bounds, no separate member boxes for a selected component.
- Multi-select unrelated primitives; each receives its own box. Select an existing grouped component; one local-oriented whole box.
- Enter/exit Build Place, Edit, Resize, Paint and Mechanics; no stale outlines after cancel, delete or tool switch. Test 30/60/144 FPS and high part count.
- Place a block, shaft/cylinder and a true CSG drilled part. Validate transparency, cyan/red strokes and the **documented CSG approximation**.
- Begin Weld with F; click first, second, finalize. First orange, both orange, then green only if server accepted. Repeat invalid weld, Spring and crank coupling. Also snap a new shaft into an existing hole from Build and drag an existing gear onto a shaft from Edit: automatic fit target/ghost goes orange; after a real committed relationship, both authored participants briefly turn green.
- Connect housing and shaft; red invalid preview, brief green success only after a real joint; test extra multi-hole bearings and fine shaft fitting.
- Switch Assembly Editor/Simulation: purple outer assembly box vs purple member boxes, grounded green vs free blue. Verify actual assembly membership unchanged.
- Check bearing, motor, slider, cylindrical and spring adornments; gear and rigid connections shouldn't draw phantom helper shapes.
- Start/stop and pause/reset simulation, undo/redo, reload saved mechanisms, respawn. No leaked adornments or physics changes.
- Test multiplayer plot ownership and large assemblies. Compare performance to Phase 0 fixtures; run full [QA_REGRESSION.md](QA_REGRESSION.md) and [UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md).

## Compatibility

- Original `dev` remains untouched by this branch.
- No server mechanical, geometry, assembly, persistence or DataStore schema files changed in Phase 2.
- Existing UI v2 Phase 1 server action authorization stays intact.
- Source-verified does **not** mean Studio-certified. Exact CSG edge and localized-intersection features are outstanding before fully meeting the originally approved visualization specification.
