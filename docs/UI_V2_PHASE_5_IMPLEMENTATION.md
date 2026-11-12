# OPENWORKS UI v2 — Phase 5: Assembly & Simulation integration

**Branch:** `feature/ui-reorganization-v2`  
**Status:** Committed in source; GitHub Python source contracts used; **Roblox Studio Play verification NOT RUN**. Do not merge to `dev` until gameplay, persistence and multiplayer regression acceptance.

## Scope and design

One existing **Assembly & Simulation** native tool, with two subtools and a shared `UnifiedExplorer` Properties surface. No new assembly schema, no copied simulation engine, no new constraints, and no weakening of server authorization.

### Assembly Editor (E)

- The unified dock exposes **+ NEW / Create assembly** even when no authored part is selected.
- New assemblies start a **local draft** with an inline editable **Draft name** field and an explicitly chosen primitive membership set. Naming no longer requires a second dialog; the old modal remains unused as a fallback until Phase 6 cleanup.
- Draft controls remain visible with zero currently selected objects: **Create/Save**, **Discard**, name and member count. The draft is not saved or autosaved before confirmation.
- Clicking a primitive from the dock lets the user toggle precisely **that primitive**; clicking a full editor component can toggle its entire real primitive membership. Ordinary world click keeps the existing component behavior; Alt+click continues to target one primitive.
- Partial component slices belonging to other registered assemblies are never silently expanded into full membership. The established ownership checks reject adding an object from another assembly.
- Selecting an existing assembly enters its saved membership editor; editing its name and membership commits through the existing `UpdateAssembly` action, with the exact member IDs. New assemblies use existing `CreateAssembly` and preserve all authored IDs.
- Confirm, Cancel, Ctrl+Z/Y and Alt+arrow whole-assembly movement keep their validated server paths. Starting a new draft or opening another assembly while a draft is already open is rejected until it is saved/discarded. **Temporarily switching tools/subtools preserves the uncommitted local draft** and its name/member IDs; it does not add those members to saved simulation scope until an explicit Confirm.

### Simulation (Y)

- Select a saved assembly in Explorer and press **Run assembly**, or aim at a member and use the existing **P** shortcut. Both call the same `AssemblyController:StartRegisteredAssembly` and its `StartSimulation` server action; a valid registered membership and all existing graph/ownership conditions are still required.
- While running, the same Properties surface exposes **Stop and return to build**, **Pause/Resume**, **Reset**, and **Inspect mechanism**. O/U/I keyboard shortcuts now call the matching unified client control path; P toggles the same Start/Stop methods.
- The Info button calls the server's existing read-only `GetMechanismInfo` and presents a bounded, human-readable collection of assembly, gear/rack and native constraint telemetry. Telemetry is on demand (not an expensive per-frame server poll).
- **Ground/free** is only editable before simulation; current authored primitive grounding is reused, and the physical runtime's own grounding/kinematic rules remain unchanged.
- Switching back to Assembly Editor while simulating is blocked in `ToolController`. Other primary tools may still be equipped, but all server authoring operations remain blocked and the dock exposes a universal **Stop** escape so the player cannot strand a running simulation.
- Simulation context menus show Stop only for the assembly actually running, never an unrelated registered assembly.
- Existing passive hand crank (hold LMB), rack (Q/E) and bearing motor hold-key controllers are preserved. They now **reject input and release held motion** whenever the Explorer owns cursor focus. This prevents accidental actuation while operating UI controls.

### Visual and selection continuity

- The existing Phase 2 purple **whole-assembly bounding box** remains for a registered assembly selection, and purple per-primitive boxes remain while editing a draft. Duplicate selected/hovered assembly overlays are suppressed.
- Both Studio world selection and Explorer rows continue to identify the same authored primitive and saved assembly IDs. Simulated clones are inspected through authored identities, never persisted as new construction.
- The old assembly instructional panel and modal remain in code until the cleanup phase, but the unified dock is the active normal workflow. The shared crosshair now covers Assembly Editor in addition to Mechanics and Simulation.

## Files touched in Phase 5

- `src/client/Controllers/AssemblyToolController.lua` — local draft naming/membership and simulation edit guards; status and purple preview sync.
- `src/client/Controllers/UnifiedExplorer.lua` — New Assembly, draft name/member controls, global simulation controls, reactive status and inspection, selection-sensitive context options.
- `src/client/Controllers/AssemblyController.lua` — single authoritative client Start/Stop path; key-based Pause/Reset/Info routes to unified UI.
- `src/client/Controllers/ContextActionRegistry.lua` — hide irrelevant assembly edits, restrict running-session actions to active assembly.
- `src/client/Controllers/ToolController.lua` — prevent switching to Assembly Editor during active simulation.
- `src/client/Controllers/HandCrankController.lua`, `RackControlController.lua`, `MotorControlController.lua` — block/release held actuator controls on UI focus.
- `src/client/init.client.lua` — Phase 5 build marker.
- `scripts/verify_source.py` — Phase 5 static contracts.
- Documentation and regression additions.

**No changes to** `MechanicalService.lua`, `SimulationService.lua`, `AssemblyService.lua`, `PlotPersistence.lua`, or existing saved DataStore schema.

## Studio acceptance — required, not run

1. Sync the feature branch and restart Play; verify the `UI-V2-PHASE5-ASSEMBLY-SIM` banner and exactly one unified dock. Check all eight subtools and no residual instruction HUDs.
2. Equip Assembly & Simulation > Assembly Editor: with **nothing selected**, use + NEW; type a name; add one primitive, add one whole component, remove a single component primitive, confirm. Verify exact authored AssemblyId and AssemblyName and no implicit weld.
3. Test creating a draft and cancelling with zero, one and many members; no partial metadata or DataStore writes. Begin a second draft while one is active: the first must not be lost. Test 48-char name limit and trim/invalid character handling.
4. Select an existing assembly from world and from Explorer. Rename and change membership; verify server UpdateAssembly preserves all unchanged member IDs, all mechanical relationships and undo/redo history.
5. Place a component whose members span multiple saved assemblies; the Explorer's partial entries must remain read-only at whole-component scope, and attempts to include a member owned by another assembly must reject without silently stealing it.
6. In Simulation, select a saved assembly in Explorer while the camera looks at empty space; **Run assembly** must simulate exactly the chosen registered set. Repeat by aiming at an assembly member and pressing P.
7. Pause/resume (O), reset (U), inspect telemetry (I) and stop (P) from both dock and keyboard. Pausing must freeze physics; resetting must restore the same assembly session, and stopping must restore authored geometry.
8. Try entering Assembly Editor with E during active simulation; do not allow it. Switch to a different native tool; the global Stop action must remain available, and authored modifications still reject at the server.
9. Hold hand crank LMB, rack Q/E or powered bearing motor key. Open the dock with Tab, context menu or click UI: the held action must stop; closing the dock does not restart actuation until a new deliberate hold.
10. Repeat simulation of disconnected registered members, relationships that cross outside the registration, grounded supports, spring trains, gears, racks, backlash/branching and motor configuration. Do **not** allow creation or editing of a mechanical relationship while simulation is running.
11. Reload older saved plots with several named assemblies, mixed component membership, springs and bearings. Run/stop then save, quit and reload: authored transforms and IDs unchanged; simulated clones never saved.
12. Test respawn, two player-owned plots, large assemblies, FPS and UI event cleanup. Log Output errors and actual runtime behavior before acceptance.

See also the [Phase 0 fixture matrix](UI_V2_REGRESSION_MATRIX.md) and [full QA regression](QA_REGRESSION.md).

## Known outstanding work

- The feature is **not Studio-certified**. Phase 6 added StyLua parsing/AST verification in CI alongside Python source contracts; neither can execute Roblox constraints.
- Phase 6 source cleanup is complete: unused parallel UI modules were deleted, duplicate runtime HUDs are no longer allocated and syntax parser verification is enabled. Studio runtime regression and physical benchmarks remain outstanding.
- Phase 2: exact CSG triangle-edge and localized invalid-intersection red visualization remain incomplete.
- Phase 6 removed the misleading manual Connect > Bolt menu option because `ConstructionService` rejects direct `CreateBolt`. Physical bolt construction remains supported through Build > Fasteners.

**Phase 5 result:** unified source implementation complete; acceptance is pending direct Studio testing.
