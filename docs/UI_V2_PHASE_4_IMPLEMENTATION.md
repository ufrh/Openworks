# OPENWORKS UI v2 — Phase 4 unified mechanical connections

**Branch:** `feature/ui-reorganization-v2`
**Status:** IMPLEMENTED in source; GitHub static source contracts pass; Roblox Studio gameplay/physics verification **NOT RUN**. Do not merge to `dev` or claim full physics correctness until test fixtures pass.

## Design delivered

One mechanical authoring entry point: **Mechanics > Connect**. Equip native tool 2, select a first owned primitive (orange), select a second (orange), choose from a small contextual menu, and commit using existing server-validated geometry/mechanical actions. If the operation requires precision pose adjustment, the old physics-validated offset/roll preview remains active until finalization. A valid server reply flashes the real participants green; an invalid pair turns the second red without creating a partial connection.

You can choose participants by:
- Direct 3D clicks (including selecting a second part behind the first with the existing exclude ray).
- Primitive rows in the unified Explorer (the same state machine, not an independent connection implementation).
- Right-click a primitive > Connect to explicitly select the first participant.

**Escape** cancels the current operation; closing the choice menu retains the first selected part so a different second can be tried. Switching native tools or subtools discards unfinished selection/preview states. The compact chooser owns the mouse while open; clicking it does not activate the Roblox Tool. Native hotbar number keys are not relationship-choice shortcuts.

## Compatible connection choices

| Part geometry | Choice | Existing server API and validator |
| --- | --- | --- |
| Cylinder shaft + genuine bore/opening, either selection order | Cylindrical (rotate + slide) | Existing `CreateRelation`, `Alignment.Plan` and mechanical geometry validation |
| Shaft + bore | Bearing (rotate) | Same `CreateRelation` with kind `Bearing` |
| Shaft + bore | Slider (translate) | Same `CreateRelation` with kind `Slider` |
| Shaft + bore | Fit Only | Existing `SmartMate` with `mateKind=Bore`, `relationKind=FreeFit`, no joint |
| Any two eligible physically touching solids, or validated shaft in drilled bore | Rigid Weld | Existing `CreateWeld`; touching/contact and relationship conflict validation remain |
| Two compatible bodies | Spring | Existing `CreateSpring` |
| Two eligible coaxial openings | Physical bolt | **Build > Fasteners** is the supported route. Direct Connect > Bolt was removed in Phase 6 because the current server explicitly rejects manual `CreateBolt` |
| Hand crank + real shaft | Crank Coupling | Existing `CoupleHandCrank` |
| Gear/hub + shaft | Independent Rotation | Existing `SmartMate` Hub with `relationKind=Rotation` |
| Gear/hub + shaft | Rigid Mount | Existing `SmartMate` Hub with `relationKind=Rigid` |

Automatic **gear-to-gear meshing** and **rack engagement** remain passive Build/Simulation behaviors; they do not become manual pair relationship choices. A gear hub already has a Rigid mounting choice, so the picker does not duplicate it as a second Weld choice.

The chooser filters choices based on obvious part types; the server remains the final authority for all fit/clearance, relation exclusivity, ownership, collision, hardware position, distance and simulated-edit restrictions. No speculative green confirmation occurs before an accepted server response.

## Unified Build smart-fit menus

Build placement and Edit drag-to-fit keep their existing snapping/multi-hole fitting solutions, but now offer their choices through **the same inline connection picker** in `UnifiedExplorer`:
- Bore: Cylindrical, Slider, Bearing, Fit Only, Adjust depth/roll.
- Gear-to-shaft hub: Rotation or Rigid.
- Reverse shaft-to-hole and multi-hole fitTargets continue through existing construction logic.
- Phase 6 removed the retired `MateChoicePanel`; Build/Edit and manual L alignment now use the unified connection picker exclusively. If the shared UI is unavailable the operation safely cancels.

The authoritative server allows Mechanics to call SmartMate **only** for `Bore/FreeFit` and `Hub/Rotation|Rigid`; full smart gear/rack placement and other Build-only construction operations remain restricted to Build.

## Controller implementation

- `ConnectionCatalog.lua` — central, read-only list of compatible pair types and fitted mount types; resolves shaft, opening, gear, crank roles.
- `AssemblyController.lua` — `StartConnect`, `BeginConnect`, `PickConnectPart`, `ConnectClick`, `CommitConnect`: one pair workflow, existing shaft preview and server request actions; no F/H/Shift+J/Shift+C/K/R-to-cycle creation modes.
- `UnifiedExplorer.lua` — `ChooseConnection`, `ChooseFit`, `ChoosePair` and `CloseConnectionChoice`: one click-only contextual choice surface, shared by Build/Mechanics, with tooltip, selection synchronization, Escape and cursor ownership. Minimal crosshair persists in Mechanics/Simulation after old HUD removal.
- `ContextActionRegistry.lua` — adds context-valid Connect action to an authored primitive under Mechanics/Connect.
- `ConstructionController.lua` — automatic fitting now calls the shared choice surface, retaining frozen exact match and authored pose until finalization.
- `ConstructionService.lua` — narrowly authorizes Mechanics-only fit and hub mounting actions, with the existing full mechanical validation still required.
- `scripts/verify_source.py` — source checks on both picker entry paths, required actions, narrow server allowlist and removed redundant shortcut handling.

Legacy controller methods that are no longer reachable from player-facing keybinds may remain temporarily in source until the separate Phase 6 cleanup; leaving those methods cannot authorize mutation without server permission. No new gear physics, additional primitive manufacturing, electrical simulation, or persistence formats were introduced.

## Studio acceptance required before calling gameplay done

1. Run the new [Phase 4 regression](QA_REGRESSION.md#ui-v2-phase-4--unified-connect-workflow-studio-play-required) and all Phase 0 saved-machine fixtures [FIX-01–FIX-06](UI_V2_REGRESSION_MATRIX.md).
2. Confirm direct world first/second selection, Explorer row first/second selection and context-menu first selection produce identical authored mechanical results and visual state.
3. Check valid and invalid Weld, Spring and CrankCoupling pairs with real geometry. Separately test physical bolts through Build > Fasteners. Confirm both orange before selection and green only on accepted server response; invalid second remains red.
4. Fit a shaft into one hole and at least two aligned bores, in both directions; confirm exact depth, roll, mechanical limits, and post-fit snugging. Try all four bore picker choices in Build and Mechanics.
5. Mount a gear on a shaft as independent bearing and rigid welded gear; verify gear-to-gear meshing remains automatic and all ratio/rotation/backdrive behavior unchanged.
6. Check clicking any contextual menu never mutates geometry behind the UI, that Esc restores first-person mouse and that switching tools clears orange/red selections.
7. Confirm no unauthorized remote invocation through the Mechanics-only SmartMate allowlist, and no cross-player or active simulation authoring.
8. Reopen existing saved plots, validate all memberships/materials/relationships/identifiers, autosave, Ctrl+Z/Y, reset and replay in Simulation.

**Not yet completed:** Studio Play, live Roblox Luau execution and physical timing/performance benchmarks. Phase 6 added a CI Luau parser gate, but it cannot execute Roblox APIs. Phase 2 exact CSG mesh-edge and localized CSG interference rendering remain separate outstanding work.
