# OPENWORKS

**OPENWORKS** is a Roblox mechanical construction and engineering sandbox with a GearBlocks-like construction experience, physically meaningful mechanical relationships, and a separate engineering/fabrication direction. The active implementation lives on `dev`, uses **Rojo** and **FORGE/Reforge**, and is currently undergoing in-engine validation.

> **State:** Experimental. Do not assume a feature is Studio-verified merely because it is committed. See [current regression checks](docs/QA_REGRESSION.md) and [known limitations](docs/ARCHITECTURE.md#known-limitations).

## Start developing

1. Check out `dev`; install the tools in [`rokit.toml`](rokit.toml) (or equivalent versions from [`aftman.toml`](aftman.toml)).
2. Run `START_OPENWORKS.bat` (Windows) or `scripts/start-dev.ps1` using PowerShell.
3. Connect the Roblox Studio Rojo plugin to **localhost:34872**. The place ID and Rojo mapping are in `default.project.json`.
4. The **Studio-generated primitive bank** must exist in `ReplicatedStorage` and be saved with the place. The server only backfills some dynamic prefab families. Restart **Play** after switching code because Roblox caches ModuleScripts.
5. Press Play and inspect the Output window for the OPENWORKS build marker and FORGE banner. Perform the [smoke test](docs/QA_REGRESSION.md) after changing simulation, serialization or mechanical constraints.

The in-game plot is isolated per player. Published Studio DataStore tests require enabling Studio API Services. **A plot loads the latest explicitly saved version when you join; F6 Save is the only DataStore write.** No automatic saving happens when you leave.

## Native tools

| Tool | Purpose |
|---|---|
| **Build** | Primitive catalog, placement, snapping, hole/shaft fitting, resizing |
| **Edit** | Select/transform geometry, combine or ungroup components, author mechanical relationships |
| **Assembly** | Create named assemblies and explicitly choose their primitives/components |
| **Simulate** | Preview the aimed assembly in **purple**; P runs physics only for registered members |
| **Inspect** | Inspect or select obstructed geometry |
| **Weld** | Make explicit rigid physical welds between valid solids |

The following three ideas **must never be conflated**:

- **Primitive** = one authored construction model, potentially containing several **internal** physical parts.
- **Component** (`ComponentId`) = an editor selection/transform group of primitives, **not** an implicit physics weld.
- **Assembly** (`AssemblyId`, `AssemblyName`) = an explicitly named set of primitives that defines simulation scope, **not** a physics weld or automatic connectivity traversal.

A **mechanical relationship** restricts or permits motion. A distinct **actuator** creates powered motion (the current hand crank supplies capped manual torque). The gear system remains a passive, work-in-progress physical transmission.

## Assembly workflow

Equip **Assembly**. Press **N** and name it; click primitives or whole components to toggle inclusion; **Alt + click** selects one primitive inside a component; press **Enter** to commit. **Ctrl+Z / Ctrl+Y** undo and redo assembly membership changes without switching tools. Aim at an existing assembly member and click to edit membership; **R** renames. Assemblies can include disconnected objects, but a simulation is rejected when a real relationship crosses into an unregistered part. Press **Esc** to cancel the draft.

Equip **Simulate** and aim at a member to preview the complete saved assembly in **purple**. **P** starts/stops the assembly; **Shift+P** starts free, **G** toggles grounding before simulation, **O** pauses, and **U** resets. Clicking a running part opens the mechanical Properties inspector. Hold LMB and move the locked mouse horizontally on a properly coupled hand crank to supply physical torque.

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
