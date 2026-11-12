# OPENWORKS UI v2 — Phase 3 unified Explorer / Properties

**Date:** 2026-11-12
**Branch:** `feature/ui-reorganization-v2` (feature branch, **not merged** to `dev`)
**Status:** Client implementation committed; GitHub source contracts pass; **Roblox Studio playtest and Luau runtime verification not yet performed**.

## Implemented

### One right-side editor dock

- `UnifiedExplorer.lua` owns the persistent right-side Explorer and Properties panel. Tab toggles the cursor between locked freecam and editable dock; the OPEN button in the dock also toggles focus when already unlocked.
- **Objects view**: real registered assemblies, editor components, primitives and unassigned objects. **Connections view**: actual server-authored mechanical relations, with real source/target endpoints and no fake component parenting.
- Components that span different assembly membership sets appear only through their **actual included primitives** beneath each assembly. The panel also displays the complete component-member count where the selected node is a partial slice.
- Search filters names and IDs. Explorer rows have explicit expand/collapse and contextual action buttons.
- Selection in Build/Edit updates the dock; selecting a primitive/component from the dock selects the existing construction model. World clicks under Mechanics/Configure or Simulation inspect the same dock, including mapped live simulated clones. Assembly Editor selection is also mirrored.
- Visual selection is delegated to Phase 2's shared `VisualFeedback` manager. No second Highlight overlay system is introduced.

### Inline Properties

- Primitives and components: name, anchor/pivot position, physical material, appearance and membership.
- Build/Paint: physical material presets; factory/matte/satin/gloss/metallic/chrome/brushed/pearl finishes; HEX color; color swatches. These use the original **SetMaterial** and **SetPaint** server actions rather than duplicated paint physics.
- Assembly: exact member count, grounding summary and name. In Assembly Editor, rename uses **UpdateAssembly** with the unchanged exact member ID set, and edit membership enters the existing assembly draft workflow.
- Mechanical relationship: endpoint list and kind; inline **TuneSpring**, **AdjustJoint**, **TuneBearingMotor**, **RemoveRelation**. Editing is available only under Mechanics/Configure when simulation is stopped. Clicking a part in Mechanics/Configure lists its actual connections.
- Assembly & Simulation: Ground/free before simulation and Start/Stop an exact registered assembly from Properties through the existing authoritative server routes. Simulated inspection is read-only.

### Context menu and tooltip system

- `ContextActionRegistry.lua` filters actions by selected entity kind, current equipped primary tool and subtool, assembly draft state and simulation state.
- Right-click an authored object while in locked freecam to show a compact contextual action menu. The cursor unlocks; choosing a transform returns to the workspace, whereas appearance/configuration keeps the dock focused.
- The same context menu is available by selecting the ellipsis in an Explorer row.
- Hover tooltips on docked controls and actions replace large, permanent keyboard guides.
- The native Tool activation handler now checks `OPENWORKS_ExplorerOpen`, preventing a click on the dock from accidentally placing, duplicating or editing a construction in the world.
- `CameraController`, `ToolController`, `ConstructionController`, `AssemblyController` and `AssemblyToolController` respect the shared cursor ownership flag. The old all-context keybind HUD no longer starts. Legacy construction/assembly/mechanical **instructional HUDs are hidden**, while their actual catalogs, input handlers and modal confirmation dialogs remain available as compatibility fallbacks.

## Files / ownership

| Module | Responsibility |
| --- | --- |
| `src/client/Controllers/ExplorerData.lua` | Build a read-only, owner-filtered authored hierarchy and connection dataset |
| `src/client/Controllers/ContextActionRegistry.lua` | Context-sensitive valid action menu descriptions and shortcuts |
| `src/client/Controllers/UnifiedExplorer.lua` | Own one dock, search, property grid, world/tree selection, tooltips and context menus |
| `src/client/init.client.lua` | Instantiate and connect dock to existing controllers |
| `src/client/Controllers/ConstructionController.lua` | Publish existing selections; let Paint and resize subtools reuse dock without legacy instruction HUD |
| `src/client/Controllers/AssemblyController.lua` | Direct Connect/Simulation selection into unified inspector without changing server actions |
| `src/client/Controllers/AssemblyToolController.lua` | Shared world/Explorer membership operation and hidden legacy instructions |
| `src/client/Controllers/ToolController.lua` | Prevent Tool.Activated while UI pointer ownership is active |
| `src/client/Controllers/CameraController.lua` | Respect dock pointer/camera focus |
| `scripts/verify_source.py` | Static contracts for ownership, tooling, permission gates, panels and API preservation |

## Out-of-scope / preserved for future phases

- **Phase 4** will consolidate the two-part Connect authoring flow, eliminate separate mechanical creation entry points and unify final confirmation. Phase 3 uses the exact same existing geometry validation.
- **Phase 5** will finish assembly/simulation interaction consolidation. Phase 3 provides Properties integration without changing simulation semantics.
- **Phase 6** will remove unused legacy UI modules after Studio verification. Legacy property and material picker GUIs are still constructed as disabled fallbacks; they are not the default dock.
- Phase 2's exact CSG mesh-edge extraction and precise localized CSG interference visuals are still incomplete.
- **No server simulation physics, mechanical service, assembly service or plot persistence schema changes** were made during Phase 3.

## Studio smoke-test checklist (NOT RUN)

1. Sync the feature branch, restart Play and confirm `2026.11.12.UI-V2-PHASE3-EXPLORER`. Verify exactly one `OPENWORKS_UnifiedExplorerProperties` ScreenGui on join and after respawn.
2. Press Tab: freecam stops and pointer unlocks. Search/expand/collapse Objects; switch to Connections and filter by part/relationship name. Press Tab or Esc to restore freecam. Right-click object in locked view; choose a valid context action. Click UI controls and verify no placement/dragging behind the dock.
3. Create two components and one named assembly that includes only some component primitives. Ensure the Explorer reports **only true assembly member IDs** while the remaining component members remain unassigned. Cross-component assembly membership must not imply a weld.
4. Select in Build/Edit, then select via Explorer. Verify one shared selected ID, proper aqua bounds and no duplicate ownership. Verify world selection in Mechanics/Configure opens the new dock and shows actual connected relations.
5. In Build/Paint, apply custom HEX plus each finish, restore factory and change physical material. Reload and verify paint/physical material persisted independently. Repeat for components that contain several primitives.
6. In Mechanics/Configure, select bearing/slider/cylindrical/spring via Connections; tune limits, spring and bearing motor; verify server rejection of invalid values. Validate no configuration changes during simulation.
7. In Assembly Editor, create an assembly with N, add/removes members using Explorer context and world clicks, confirm and rename inline. Verify `UpdateAssembly` does not silently alter the recorded member set. Undo/redo and saved reload must preserve membership exactly.
8. In Simulation, select a registered assembly from Explorer and Run/Stop. Verify no simulation of unregistered members; test grounding changes only while stopped. Select running models in-world and ensure Properties maps back to authored IDs.
9. Open/close numeric sizing, relationship choice, assembly naming and plot Save/Load modals. Verify cursor ownership, freecam, tool input, double-click selection, and Escape cancellation.
10. Test two players, >100 components, dynamic relationship changes, rapid tool switching, respawn, deletion and plot reload. Check CPU/FPS, stale UI rows and leaks. Follow [UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md) and [full QA regression](QA_REGRESSION.md).

**Static contract pass is not Studio proof.** The feature remains isolated until interactive validation is complete.
