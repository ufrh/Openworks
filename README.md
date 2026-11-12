# OPENWORKS

**OPENWORKS** is a Roblox mechanical construction and engineering sandbox with a GearBlocks-like construction experience, physically meaningful mechanical relationships, and a separate engineering/fabrication direction. The stable pre-UI-v2 implementation lives on `dev`. UI v2 Phases 1–4 are isolated on `feature/ui-reorganization-v2`. Both use **Rojo** and **FORGE/Reforge** and still require Roblox Studio validation.

> **State:** Experimental. Do not assume a feature is Studio-verified merely because it is committed. See [current regression checks](docs/QA_REGRESSION.md) and [known limitations](docs/ARCHITECTURE.md#known-limitations).

## Start developing

1. Check out `feature/ui-reorganization-v2` to test UI v2 Phases 1–4 (`dev` remains the fallback); install the tools in [`rokit.toml`](rokit.toml) (or equivalent versions from [`aftman.toml`](aftman.toml)).
2. Run `START_OPENWORKS.bat` (Windows) or `scripts/start-dev.ps1` using PowerShell.
3. Connect the Roblox Studio Rojo plugin to **localhost:34872**. The place ID and Rojo mapping are in `default.project.json`.
4. The **Studio-generated primitive bank** must exist in `ReplicatedStorage` and be saved with the place. The server only backfills some dynamic prefab families. Restart **Play** after switching code because Roblox caches ModuleScripts.
5. Press Play and inspect the Output window for the OPENWORKS build marker and FORGE banner. Perform the [smoke test](docs/QA_REGRESSION.md) after changing simulation, serialization or mechanical constraints.

The in-game plot is isolated per player. Published Studio DataStore tests require enabling Studio API Services. **A plot loads the latest saved version on join.** The current persistence system autosaves dirty plots periodically and attempts a final flush on exit; F6 opens manual Save/Load. Test persistence on disposable plots before relying on a save.

## Native tools — UI v2

The native Roblox hotbar now contains **exactly three** primary tools. Letter keys change **subtools within the equipped primary tool**; switching primary tools remembers their last subtool.

| Hotbar | Primary tool | Subtool | Key | Current workflow |
|---|---|---|---|---|
| 1 | **Build** | Place | B | Catalog, placement, snapping, geometry previews |
| 1 | **Build** | Edit | E | Select, group, drag, duplicate, transform |
| 1 | **Build** | Resize | V | Neon face resize and precise dimensions |
| 1 | **Build** | Paint | M | Colors, finishes, physical material presets |
| 2 | **Mechanics** | Connect | C | Bearing/slider/cylindrical joint, spring, weld, crank coupling |
| 2 | **Mechanics** | Configure | E | Inspect and adjust joint, spring and bearing motor properties |
| 3 | **Assembly & Simulation** | Assembly Editor | E | Create/edit named assembly membership |
| 3 | **Assembly & Simulation** | Simulation | Y | Ground and test registered assembly |

**Mechanics / Connect (Phase 4):** click a first physical part, then a second; the same compact connection picker appears for welding, springs, bearing/slider/cylindrical joints, bolt insertion, hand-crank coupling, and gear-to-shaft mounting. The picker presents only type-compatible choices; all actual collisions, fits and clearances remain server-validated. A shaft/hole motion choice opens the existing insertion/roll preview; click again to finalize, then adjust snug fit if applicable. **Esc** cancels the pending interaction. The old **F/H/Shift+J/Shift+C/R-to-cycle** mechanical creation routes are retired; Configure and the Explorer's Connections view own relationship adjustment/removal. Automatic Build shaft/hole and gear/shaft fittings now use this same connection picker, including **Fit Only** and **Adjust depth / roll** options.

Use the Explorer or right-click menu to select the first connection participant, or select either part directly from the 3D world. Selecting a second primitive in the Explorer uses the same workflow. Two orange bounds indicate pending participants; failed server validation turns the second red, and accepted connections briefly turn both green.

Build/Place still uses **B** to open the catalog when already active; Build/Edit still uses **E** for component interior editing when already active; Build/Resize uses **V** to toggle face handles when already active. A live fit reserves Q/E for shaft roll so E does not inadvertently switch subtools.

Phase 2 implements shared aqua/purple/orange/green/red wireframe feedback, geometry ghosts and minimal mechanical indicators. **Exact CSG triangle edges and localized CSG collision outlines remain unfinished.** Phase 3 adds a docked unified Explorer/Properties panel with real assembly/component membership, connection inspection, contextual actions, hover tooltips, and inline paint/material/joint/motor/assembly configuration. Press **Tab** to unlock the dock, or right-click an authored object for its context menu. Persistent legacy instruction HUDs are hidden; some modal editing components remain as fallbacks pending Studio testing. See [Phase 4 notes](docs/UI_V2_PHASE_4_IMPLEMENTATION.md), [Phase 3 notes](docs/UI_V2_PHASE_3_IMPLEMENTATION.md), and the [regression matrix](docs/UI_V2_REGRESSION_MATRIX.md).

The following three ideas **must never be conflated**:

- **Primitive** = one authored construction model, potentially containing several **internal** physical parts.
- **Component** (`ComponentId`) = an editor selection/transform group of primitives, **not** an implicit physics weld.
- **Assembly** (`AssemblyId`, `AssemblyName`) = an explicitly named set of primitives that defines simulation scope, **not** a physics weld or automatic connectivity traversal.

A **mechanical relationship** restricts or permits motion. A distinct **actuator** creates powered motion (the current hand crank supplies capped manual torque). The gear system remains a passive, work-in-progress physical transmission.

## Assembly workflow

Equip **Assembly & Simulation**, select the **Assembly Editor** subtool (**E**). Press **N** and name it; click primitives or whole components to toggle inclusion; **Alt + click** selects one primitive inside a component; press **Enter** to commit. **Ctrl+Z / Ctrl+Y** undo and redo assembly membership changes without switching tools. Aim at an existing assembly member and click to edit membership; **R** renames. Assemblies can include disconnected objects, but a simulation is rejected when a real relationship crosses into an unregistered part. Press **Esc** to cancel the draft.

In **Assembly & Simulation**, press **Y** for the **Simulation** subtool and aim at a registered member to preview its complete assembly in **purple**. **P** starts/stops it with the authored grounding state, **G** toggles grounding before simulation, **O** pauses, and **U** resets. Clicking a running part opens Properties. Hold LMB on a correctly coupled hand crank to drive it at the server-controlled rate; release to stop. Shift+P is no longer a separate simulation mode.

## Where code lives

| Location | Responsibility |
|---|---|
| `src/client/Controllers/` | Tool/input state, UI, camera, local ghost visuals and inspector |
| `src/server/Runtime/` | Authoritative construction, validation, relationships, assembly membership, physics simulation, plots and saves |
| `src/shared/Construction/` | Pure geometry, fit calculations, primitive definitions, tool definitions and shared configuration |
| `src/forge-shared/`, `src/forge-server/` | FORGE framework; preserve its boundary |
| `docs/ARCHITECTURE.md` | Ownership rules, data flow, invariants, constraints and known limits |
| `docs/QA_REGRESSION.md` | In-Studio verification checklist and release gates |
| `docs/README.md` | Documentation index and legacy test references |
| `docs/ARCHIVED_IMPLEMENTATION_LOG.md` | Full unedited historical development notes formerly appended to the README |

## Code checks

- `python scripts/verify_source.py` checks cross-file architecture invariants and source organization without Roblox Studio. It **does not compile or execute Luau**.
- `rojo build default.project.json --output builds/openworks.rbxlx` verifies project mapping with an installed Rojo toolchain.
- `stylua --check src/` and `selene src/` can report style/type diagnostics; existing legacy source is **not yet guaranteed warning-free** under those tools. Do not mass-autoformat FORGE or large mechanic services during feature development without checking the diff.
- For gameplay changes, follow `docs/QA_REGRESSION.md`. Static checks cannot prove physics stability, GUI input behavior or DataStore access.

## Project history

Older phase-specific smoke tests remain in `docs/` for historical reference and are **not current requirements**. The previous append-only README is preserved verbatim at [`docs/ARCHIVED_IMPLEMENTATION_LOG.md`](docs/ARCHIVED_IMPLEMENTATION_LOG.md). Historical game versions and redesign boundaries remain on the existing archive branches; they are not modified by this organization pass.
