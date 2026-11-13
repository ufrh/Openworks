# OPENWORKS

**OPENWORKS** is a Roblox mechanical construction and engineering sandbox with a GearBlocks-like construction experience, physically meaningful mechanical relationships, and a separate engineering/fabrication direction. The **`dev` branch is the integrated UI V2 + shaft-centric implementation**. The original UI V2 baseline remains on `feature/ui-reorganization-v2`; both use **Rojo** and **FORGE/Reforge** and still require Roblox Studio validation.

> **Development branch:** `dev` now contains the UI V2 + shaft-centric integration, matching the implementation initially prepared on `integration/ui-v2-shaft-systems`. The integrated systems include (Component Bank, alignment origins, welded hubs, pulley belts and physical gear/belt simulation). See [integration notes and acceptance tests](docs/UI_V2_SHAFT_INTEGRATION.md). **State:** Experimental. Do not assume a feature is Studio-verified merely because it is committed. See [current regression checks](docs/QA_REGRESSION.md) and [known limitations](docs/ARCHITECTURE.md#known-limitations).

**Publish the integrated build to GitHub:** Run `PUBLISH_DEV.bat` from this extracted folder. It verifies that local `dev` contains the integration, pushes it to `ufrh/Openworks`, and checks the remote SHA afterward. The standard `PUSH_OPENWORKS.bat` also now pushes existing commits when there are no uncommitted changes.

## Start developing

1. Check out `dev` to work on the integrated UI V2 build; install the tools in [`rokit.toml`](rokit.toml) (or equivalent versions from [`aftman.toml`](aftman.toml)).
2. Run `START_OPENWORKS.bat` (Windows) or `scripts/start-dev.ps1` using PowerShell.
3. Connect the Roblox Studio Rojo plugin to **localhost:34872**. The place ID and Rojo mapping are in `default.project.json`.
4. The **Studio-generated primitive bank** must exist in `ReplicatedStorage` and be saved with the place. The server only backfills some dynamic prefab families. Restart **Play** after switching code because Roblox caches ModuleScripts.
5. Press Play and inspect the Output window for the OPENWORKS build marker and FORGE banner. Perform the [smoke test](docs/QA_REGRESSION.md) after changing simulation, serialization or mechanical constraints.

The in-game plot is isolated per player. Published Studio DataStore tests require enabling Studio API Services. **A plot loads the latest saved version on join.** The current persistence system autosaves dirty plots periodically and attempts a final flush on exit; F6 opens manual Save/Load. Test persistence on disposable plots before relying on a save.

## Native tools — UI v2

The Roblox hotbar has **four** primary tools. **Build** is for placing geometry; **Edit** is its own tool in slot 2 for selecting, manipulating, fitting, resizing, painting and saving reusable components. Mechanics and Assembly & Simulation retain their respective subtools.

| Hotbar | Tool | Action | Key | Current workflow |
|---|---|---|---|---|
| 1 | **Build** | Browse / place parts | B / Click | Open primitive and saved-component catalog, then place into the workspace |
| 1 | **Build** | Finish placing | Enter / Esc | Clear the active placement preview, without editing existing parts |
| 2 | **Edit** | Select / transform | Click / G / F | Select, group, move, duplicate, rotate or delete geometry |
| 2 | **Edit** | Fitting | L | Select a shaft or opening-bearing part, then target an opening or shaft and confirm fitting relationship |
| 2 | **Edit** | Resize / appearance | V / N / M | Neon grips, exact dimensions, and material / finish / color controls |
| 2 | **Edit** | Component Bank | Shift+B | Save a selected complete component as a reusable blueprint |
| 3 | **Mechanics** | Connect / configure | C / E | Create and edit mechanical joints, springs, belts and motors |
| 4 | **Assembly & Simulation** | Assembly / Simulate | E / Y | Group mechanism, ground and run a registered assembly |

The free camera uses **mouse wheel** for FOV zoom, except while actively adjusting shaft insertion depth. See [Edit tool, camera, fitting and save recovery](docs/EDIT_2_FITTING_CAMERA_SAVES.md).

Older [Unified Build workflow](docs/UNIFIED_BUILD_WORKFLOW.md) is historical; use the new Edit/Build guide above for current controls.

**Mechanics / Connect:** select two physical parts, choose a compatible mechanical relationship, then confirm. Orange boxes represent explicitly chosen participants; rejected pairs turn red and accepted connections flash green. Automatic Build shaft/hole and gear/shaft fitting, plus manual L alignment, share the same contextual relationship chooser. **Build > Fasteners** remains the supported physical bolt workflow. The server validates all ownership, clearance, fit and simulation boundaries.

**Left shortcut sidebar:** Build shows a single contextual **Controls** panel (no redundant Place/Edit subtool list). Mechanics shows C/E and Assembly & Simulation shows E/Y with Controls below. The Build controls reflect editing, catalog selection, active placement, movement, resizing and fitting. **F2** unlocks the cursor when UI interaction is needed; **Tab** is reserved for depth and fit-target cycling where applicable.

**Primitive library:** Press **B** while in Build to open the right-side catalog. Choosing a primitive or saved component starts its placement ghost; click to stamp, **Enter** or **Esc** to resume selecting existing geometry, without changing tools. Esc while the library is open closes only the library. **Shift+B** saves a selected grouped component. V and M remain available while editing.

**Right-click editing:** There is **no permanent Explorer or Properties dock**. Right-click an authored primitive or grouped component to open a single floating context panel. The panel lists every authored mechanical relationship involving that object or its component members. Click a relationship to edit its supported limits, spring properties or bearing-motor settings **inside that same panel**, then press **Confirm**. Read-only relationship metadata is also displayed. Material/finish/color changes use their own Confirm action in the same panel. Those changes use existing server APIs; simulation blocks authoring.

**Selection outlines:** Only deliberately selected primitives, whole editor components, selected assembly draft members and active connection participants have selection boxes. Passive hover, automatic snap acquisition, aim-only assembly previews and permanent grounding boxes no longer draw outlines. Selected geometry is re-evaluated each render frame, including during live resize, and clears when selection is lost or the selected object is removed.

Exact CSG triangle edges and localized CSG intersection outlines remain unfinished; see [current contextual UI implementation](docs/UI_CONTEXT_REDESIGN.md), [Phase 6 history](docs/UI_V2_PHASE_6_IMPLEMENTATION.md), and [regression checks](docs/QA_REGRESSION.md).

The following three ideas **must never be conflated**:

- **Primitive** = one authored construction model, potentially containing several **internal** physical parts.
- **Component** (`ComponentId`) = an editor selection/transform group of primitives, **not** an implicit physics weld.
- **Assembly** (`AssemblyId`, `AssemblyName`) = an explicitly named set of primitives that defines simulation scope, **not** a physics weld or automatic connectivity traversal.

A **mechanical relationship** restricts or permits motion. A distinct **actuator** creates powered motion (the current hand crank supplies capped manual torque). The gear system remains a passive, work-in-progress physical transmission.

## Assembly workflow — centered creation

Equip **Assembly & Simulation > Assembly Editor (E)** and press **N**. A **centered name popup** opens. Enter a name, then select **SELECT PRIMITIVES**. The dialog closes so you can click authored primitives or components in the world; Alt+click targets one primitive from a component. A compact **top-center selection bar** shows the name, chosen member count, **CONFIRM**, and **CANCEL**. Press Enter to save or Escape to discard. Temporarily switching tools preserves an uncommitted draft without saving any membership.

Right-click a registered assembly member and choose **Open assembly** or edit through Assembly Editor to inspect its explicit registered membership. Assembly selection never welds components, and all names and member IDs use the existing server's creation/update actions.

For **Simulation (Y)**, aim at a registered member and press **P**, or right-click an assembly to access its available simulation controls. While running, a small **top-center simulation strip** shows STOP/PAUSE/RESET; existing **P/O/U/I** shortcuts remain. Grounding is a physical property, not a permanent selection box. Opening contextual UI releases active crank, rack and motor controls. Studio Play is still required to validate these interactions.

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
