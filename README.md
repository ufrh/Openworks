# OPENWORKS

**OPENWORKS** is a Roblox mechanical construction and engineering sandbox with a GearBlocks-like construction experience, physically meaningful mechanical relationships, and a separate engineering/fabrication direction. The stable pre-UI-v2 implementation lives on `dev`. UI v2 Phases 1–6 are isolated on `feature/ui-reorganization-v2`. Both use **Rojo** and **FORGE/Reforge** and still require Roblox Studio validation.

> **State:** Experimental. Do not assume a feature is Studio-verified merely because it is committed. See [current regression checks](docs/QA_REGRESSION.md) and [known limitations](docs/ARCHITECTURE.md#known-limitations).

## Start developing

1. Check out `feature/ui-reorganization-v2` to test UI v2 Phases 1–6 (`dev` remains the fallback); install the tools in [`rokit.toml`](rokit.toml) (or equivalent versions from [`aftman.toml`](aftman.toml)).
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

**Mechanics / Connect (Phase 4):** click a first physical part, then a second; the same compact connection picker appears for welding, springs, bearing/slider/cylindrical joints, hand-crank coupling, and gear-to-shaft mounting. Real bolt placement remains in Build > Fasteners. The picker presents only type-compatible choices; all actual collisions, fits and clearances remain server-validated. A shaft/hole motion choice opens the existing insertion/roll preview; click again to finalize, then adjust snug fit if applicable. **Esc** cancels the pending interaction. The old **F/H/Shift+J/Shift+C/R-to-cycle** mechanical creation routes are retired; Configure and the Explorer's Connections view own relationship adjustment/removal. Automatic Build shaft/hole and gear/shaft fittings now use this same connection picker, including **Fit Only** and **Adjust depth / roll** options.

Use the Explorer or right-click menu to select the first connection participant, or select either part directly from the 3D world. Selecting a second primitive in the Explorer uses the same workflow. Two orange bounds indicate pending participants; failed server validation turns the second red, and accepted connections briefly turn both green.

Build/Place still uses **B** to open the catalog when already active; Build/Edit still uses **E** for component interior editing when already active; Build/Resize uses **V** to toggle face handles when already active. A live fit reserves Q/E for shaft roll so E does not inadvertently switch subtools.

**Left shortcut sidebar:** Beneath the Plot/F6 button, a **Subtools** column displays every subtool and its real shortcut from `SubtoolDefinitions.lua` (for example Build: B/E/V/M). The current subtool is highlighted. Beneath it, a separate **Controls** panel displays the active tool's keybinds and updates for special contexts such as live shaft fitting, assembly drafts and running simulation. To click a subtool row, unlock the cursor with **F2**; switching then returns control to the workspace. F2 is the reliable UI shortcut because **Tab** is also used for Edit depth selection and Build fit-target cycling. These panels intentionally contain short key/action labels rather than lengthy instructional text.

Phase 2 implements shared aqua/purple/orange/green/red wireframe feedback, geometry ghosts and minimal mechanical indicators. **Exact CSG triangle edges and localized CSG collision outlines remain unfinished.** Phase 3 adds a docked unified Explorer/Properties panel with real assembly/component membership, connection inspection, contextual actions, hover tooltips, and inline paint/material/joint/motor/assembly configuration. Press **F2** to unlock the dock (**Tab** also works where it is not reserved for depth/fit targeting), or right-click an authored object for its context menu. Redundant standalone material, relationship and shortcut panels have been removed, and the remaining legacy Assembly/Mechanics HUDs are not instantiated when the unified dock is active. See [Phase 6 notes](docs/UI_V2_PHASE_6_IMPLEMENTATION.md), [Phase 5 notes](docs/UI_V2_PHASE_5_IMPLEMENTATION.md), [Phase 4 notes](docs/UI_V2_PHASE_4_IMPLEMENTATION.md), and the [regression matrix](docs/UI_V2_REGRESSION_MATRIX.md).

The following three ideas **must never be conflated**:

- **Primitive** = one authored construction model, potentially containing several **internal** physical parts.
- **Component** (`ComponentId`) = an editor selection/transform group of primitives, **not** an implicit physics weld.
- **Assembly** (`AssemblyId`, `AssemblyName`) = an explicitly named set of primitives that defines simulation scope, **not** a physics weld or automatic connectivity traversal.

A **mechanical relationship** restricts or permits motion. A distinct **actuator** creates powered motion (the current hand crank supplies capped manual torque). The gear system remains a passive, work-in-progress physical transmission.

## Assembly workflow — Phase 5

Equip **Assembly & Simulation > Assembly Editor (E)**. Choose **+ NEW** or press **N** to begin a **local assembly draft**, then edit its name in the unified Properties panel. Select primitives or whole components in the world; Alt+click targets an individual primitive within a component. From Explorer, use the Add/Remove membership action for individual primitives, or choose the full editor component. The dock displays member count and **Create/Save / Discard** even with no other object selected. Press **Enter** to confirm or **Esc** to discard. Temporary tool switches preserve the uncommitted draft without changing saved assembly membership. Ctrl+Z/Y still undo/redo server history, and Alt+arrows move a saved assembly.

Click an existing assembly or its member to edit membership; Properties also supports renaming without changing its other members. Unrelated component grouping is **never** a hidden physical weld. An assembly can include disconnected primitives, but simulation rejects true relationships that cross outside its explicit registered member set.

Switch to **Simulation (Y)**. Select an assembly in the Explorer and press **Run assembly**, or aim at its member and press **P**. The same Properties panel provides **Stop, Pause/Resume, Reset and Inspect mechanism**, with **P/O/U/I** keyboard equivalents. **G** toggles authored grounding before simulation, including from the selected primitive's Properties. During a running simulation, switching to Assembly Editor is blocked; switching to another primary tool still leaves a global Stop available in the dock. Holding LMB operates a valid hand crank; Q/E drive eligible racks, and configured motor keys drive powered bearings. Opening the dock releases held actuator input; no new motion resumes until another deliberate hold.

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

- `python scripts/verify_source.py` checks cross-file architecture invariants and source organization without Roblox Studio. GitHub Actions also runs pinned StyLua 2.1.0 with `--verify --syntax luau src` to **parse all Luau source and check AST-safe formatting on an ephemeral checkout**. Neither check executes Roblox gameplay, constraints, GUI events or DataStores.
- `rojo build default.project.json --output builds/openworks.rbxlx` verifies project mapping with an installed Rojo toolchain.
- `stylua --check src/` and `selene src/` can report style/type diagnostics; existing legacy source is **not yet guaranteed warning-free** under those tools. Do not mass-autoformat FORGE or large mechanic services during feature development without checking the diff.
- For gameplay changes, follow `docs/QA_REGRESSION.md`. Static checks cannot prove physics stability, GUI input behavior or DataStore access.

## Project history

Older phase-specific smoke tests remain in `docs/` for historical reference and are **not current requirements**. The previous append-only README is preserved verbatim at [`docs/ARCHIVED_IMPLEMENTATION_LOG.md`](docs/ARCHIVED_IMPLEMENTATION_LOG.md). Historical game versions and redesign boundaries remain on the existing archive branches; they are not modified by this organization pass.
