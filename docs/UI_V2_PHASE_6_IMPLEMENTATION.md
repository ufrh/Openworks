# OPENWORKS UI v2 — Phase 6 cleanup, compatibility and regression handoff

**Branch:** `feature/ui-reorganization-v2`
**Build marker:** `2026.11.12.UI-V2-PHASE6-CLEANUP`
**Status:** Source cleanup implemented. GitHub Python contracts and pinned StyLua parser/AST verification pass. **Roblox Studio runtime and physics tests have NOT been performed.**
**Merge policy:** Keep `dev` untouched until Studio QA explicitly passes, including existing saved builds.

## Phase 6 changes

### One active UI owner

- Removed five **obsolete client modules**: `ContextKeybinds.lua`, `ComponentOutline.lua`, `MateChoicePanel.lua`, `MaterialPickerController.lua`, and `RelationshipProperties.lua`.
- Build's automatic shaft/hole and gear mount fitting, **plus manual L alignment**, now use `UnifiedExplorer:ChooseFit`, not separate modal implementations. Missing UI cancels the pending operation rather than showing a second menu or committing without confirmation.
- The shared dock owns context-sensitive paint/material, joint properties, assembly drafts and simulation controls. No duplicate live relationship or paint window is created.
- The feature's bootstrap assigns the shared `UnifiedExplorer` to all domain controllers **before** their `Start()` methods, preventing allocation of the unused Mechanics and Assembly Editor instructional HUDs. Unused fallback creation code may remain dormant and should only be removed after in-engine playtesting.
- The old client-only selection/inspector folders and obsolete ComponentOutline renderer were retired. Selection, fitting states and purple registered-assembly feedback remain under the shared `VisualFeedback` manager. No construction helper Part was added.

### Mechanical connection correctness

- The Phase 4 menu mistakenly offered direct `Connect > Bolt`, but the current server's `CreateBolt` action rejects it and directs users to **Build > Fasteners**. That misleading choice has been removed (and cannot dispatch `CreateBolt`). Physical bolts still use the existing Build prefab placement/smart-fitting workflow.
- Bearings, cylindrical joints, sliders, springs, cranks, welds and gear-to-shaft mounts keep existing validated service actions; UI context choices do not create implicit relationships.
- Manual L shaft/hole and gear alignment now use the same one-click relationship picker; current precision depth, roll, multi-hole fit and physical rejection rules remain with existing controllers/server code.
- No changes to `MechanicalService.lua`, `SimulationService.lua`, `AssemblyService.lua`, or `PlotPersistence.lua` in this phase. This means the original `dev` plots and all persistence schema stay unchanged. Phase 4 separately introduced a narrow `ConstructionService` tool authorization allowlist; it was not broadened in Phase 6.

### Stronger automated verification

The GitHub workflow now has **two separate jobs**:

1. `verify-source`: `python3 scripts/verify_source.py`. Checks architecture boundaries, saved ID/membership contracts, relation properties, real visual ownership, input gates, and Phase 6 dead-module removal. New tests also check that unified dock references are assigned before legacy HUD startup.
2. `parse-luau`: Installs **StyLua 2.1.0** and runs `stylua --verify --syntax luau src`. This parses all Lua/Luau client/server/shared source and re-parses the formatted output to verify AST integrity. Formatting happens only on the disposable GitHub runner checkout; no source formatting changes are committed. This does not execute Roblox APIs or provide a formal Luau typecheck.

The project also retains local optional tools (`rojo`, `stylua`, `selene`) pinned by `rokit.toml`. Automated verification is stronger than in Phases 1–5, but source/parsing successes cannot certify working physics or UI in Studio.

## Remaining known limitations

- The original Phase 2 **exact CSG mesh-edge wireframes and localized collision-edge red visualization** remain incomplete; bounding/ghost approximations are still used on some CSG shapes.
- Roblox Studio client runtime correctness has **not** been verified. The Luau parser does not resolve all Roblox API types, RemoteFunction behavior, or physical constraints. Existing startup hooks, GUI object lifetime, controls, snapping and simulation require real Studio Play.
- No in-engine performance benchmark, multiplayer playtest, save/reload test, actual motor/gear/shaft physics regression, or live Rojo project build has been performed in this ChatGPT pass.
- Build > Fasteners remains the supported physical Bolt workflow; no general manual Connect > Bolt creation is offered.

## Manual Studio acceptance (mandatory)

1. Check out `feature/ui-reorganization-v2`, start Rojo and **restart Studio Play**. Confirm Phase 6 marker, exactly three native tools with eight valid subtools, and only the unified Explorer/Properties dock. Verify the removed modules are not referenced in Output.
2. **Cold start, tool switches and respawn:** ensure no legacy assembly naming modal, old contextual shortcut pane, separate Mechanical Properties panel or Material Picker appears in PlayerGui. Confirm Build's primitive catalog, precision sizing, resize grips and F6 plots still work.
3. **Construction:** place Block/Cylinder/CSG drilled objects; direct-drag, resize, multi-select, components, undo/redo, painting/materials, snapping, fitting and loading saved geometry without misplaced outlines or input leaks. Test rotated parts and known CSG approximation.
4. **Mechanical Connect:** choose two objects from world and Explorer; verify orange pending participants, applicable options, successful green confirmation, rejected red secondary, escape cancellation, and no extra legacy picker. Test both L manual alignment and automatic Build/Edit fitting on shafts/gears and multi-hole pins.
5. **Bolt:** direct Connect must **not** advertise the unsupported Bolt action. Use Build > Fasteners to insert actual bolt prefabs and verify collision/clearance and save/reload.
6. **Assembly Editor:** create named assemblies and edit exact member lists (including disconnected objects and partial components); check purple visualization, drag/nudge, cancel, rename, undo/redo and save/reload, with no hidden welds.
7. **Simulation:** start a registered assembly (from Explorer or P), pause/resume, reset and stop. Confirm authored objects restore and simulated clones are never persisted. Test grounding, active editor lockout, crank, motors, rack and gear backdrive. Opening UI during held actuation must release input.
8. **Persistence:** use a disposable copy of an old plot. Load all Phase 0 FIX-01 to FIX-06 fixtures and older saved assemblies; validate IDs, materials, metadata, fitted bores, mechanical relation limits and component partial membership. Run, stop, save, quit and reload.
9. **Multiplayer and robustness:** test two user plots, out-of-range and foreign-owned part operations, denied server writes while simulating, cursor focus, 30/60/144 FPS, many components, repeated respawns, no hidden adornments or memory leaks.
10. Record Roblox Studio Output and pass/fail for every regression in [QA_REGRESSION.md](QA_REGRESSION.md) and [UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md). Fix actual runtime errors before merging.

**Exit rule:** GitHub source checks and Luau parsing green **plus** Studio smoke/fixture acceptance. Do not merge merely on CI success.
