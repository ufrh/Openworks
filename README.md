# OPENWORKS

**OPENWORKS** is a Roblox mechanical construction and engineering sandbox with a GearBlocks-like construction experience, physically meaningful mechanical relationships, and a separate engineering/fabrication direction. The stable pre-UI-v2 implementation lives on `dev`. UI v2 Phase 1 is isolated on `feature/ui-reorganization-v2`. Both use **Rojo** and **FORGE/Reforge** and still require Roblox Studio validation.

> **State:** Experimental. Do not assume a feature is Studio-verified merely because it is committed. See [current regression checks](docs/QA_REGRESSION.md) and [known limitations](docs/ARCHITECTURE.md#known-limitations).

## Start developing

1. Check out `feature/ui-reorganization-v2` to test UI v2 Phase 1 (`dev` remains the fallback); install the tools in [`rokit.toml`](rokit.toml) (or equivalent versions from [`aftman.toml`](aftman.toml)).
2. Run `START_OPENWORKS.bat` (Windows) or `scripts/start-dev.ps1` using PowerShell.
3. Connect the Roblox Studio Rojo plugin to **localhost:34872**. The place ID and Rojo mapping are in `default.project.json`.
4. The **Studio-generated primitive bank** must exist in `ReplicatedStorage` and be saved with the place. The server only backfills some dynamic prefab families. Restart **Play** after switching code because Roblox caches ModuleScripts.
5. Press Play and inspect the Output window for the OPENWORKS build marker and FORGE banner. Perform the [smoke test](docs/QA_REGRESSION.md) after changing simulation, serialization or mechanical constraints.

The in-game plot is isolated per player. Published Studio DataStore tests require enabling Studio API Services. **A plot loads the latest saved version on join.** The current persistence system autosaves dirty plots periodically and attempts a final flush on exit; F6 opens manual Save/Load. Test persistence on disposable plots before relying on a save.

## Native tools — UI v2 Phase 1

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

**Temporary Phase 1 shortcuts within Mechanics / Connect:** click physical housing then shaft for manual fitting; **H** resets that workflow, **F** enters two-part Weld (press F again or Esc to exit), **Shift+J** selects two endpoints for Spring, **Shift+C** couples a crank to a shaft. **Shift+Delete** removes a relation. Existing constraints and geometry validation are unchanged. These paths will be unified into one contextual connection interface in a later phase.

Build/Place still uses **B** to open the catalog when already active; Build/Edit still uses **E** for component interior editing when already active; Build/Resize uses **V** to toggle face handles when already active. A live fit reserves Q/E for shaft roll so E does not inadvertently switch subtools.

The old six-tool instructional HUDs, visualizers, and separate property windows are **still present during Phase 1**. Consolidating them belongs to subsequent UI v2 phases. See [Phase 1 implementation notes](docs/UI_V2_PHASE_1_IMPLEMENTATION.md) and the [regression matrix](docs/UI_V2_REGRESSION_MATRIX.md).

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
