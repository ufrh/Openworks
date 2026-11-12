# OPENWORKS UI v2 — Phase 0 Baseline (2026-11-12)

**Status:** Repository isolation and source baseline recorded. **Studio runtime baseline remains UNVERIFIED** and is a release gate before Phase 1 can be considered production-safe.

## Frozen baseline

- Repository: `ufrh/Openworks`
- Original branch: `dev`
- Exact starting commit: `7eef04af7932d636ec448834956cdfe66721b000`
- Migration branch: `feature/ui-reorganization-v2`, created from that exact commit
- Base commit message: `fix(snapping): attach drilled holes at crosshair depth on finite shaft, not midpoint`
- Existing GitHub Actions source-contract run: [#287](https://github.com/ufrh/Openworks/actions/runs/43161587441) — **success**, same commit
- Original code remains unchanged in this phase; these are documentation-only commits.
- Restoration reference: checkout/reset to the frozen starting SHA on an isolated development copy; do not reset or overwrite `dev` and do not clear player DataStores.

### Scope of Phase 0

Document the old player-facing behavior, permissions, persistence, key workflows, representative saved-machine scenarios, and the test gates required before tool consolidation. This baseline documents source behavior and expected tests; it **does not certify that Roblox Studio physics or DataStore operations were observed**.

## Current six native tools (source of truth)

| Tool | Current ownership | Input/UI evidence |
| --- | --- | --- |
| Build | Primitive catalog, placement, snapping and fit previews | `ToolDefinitions.lua`, `ConstructionController.lua` |
| Edit | Selection, grouping, transform, sizing, painting, most relation creation | `ConstructionController.lua`, `LayeredEditingController.lua`, `AssemblyController.lua` |
| Assembly | Explicitly named assembly membership, rename, assembly nudging | `AssemblyToolController.lua` |
| Simulate | Assembly simulation, grounding, inspection, powered inputs | `AssemblyController.lua`, `RelationshipProperties.lua` |
| Inspect | Depth-based selection, X-ray and isolation | `ConstructionController.lua`, `LayeredEditingController.lua` |
| Weld | Two-body explicit weld authoring | `AssemblyController.lua` |

`src/shared/Construction/ToolDefinitions.lua` and `src/server/Runtime/NativeToolProvisioner.lua` define/provision these; current hotbar uses native Roblox Tools. The server uses old tool IDs to authorize many mutations. **Never delete these tool IDs without a coordinated client/server authorization migration.**

## Existing user interaction inventory

### Shared camera, selection, and history

- Persistent Scriptable freecam: mouse look, WASD, Space/Ctrl vertical, Shift speed, Z/Shift+Z FOV.
- Crosshair targeting; selection of primitives and whole components; Shift multi-select; double click inside component; depth cycling; X-ray; isolate.
- Undo/redo metadata and construction where supported; cancel operations via Escape.
- Several separate HUDs and input listeners currently compete for interaction state and display instructions.

### Build and Edit

- Primitive catalog backed by Studio-generated library; generic blocks, cylinders/shaft, tubes, drilled objects, gear/rack templates, fasteners and crank.
- Snap-to-face/center/edge and plot grid; ghost validity; smart shaft/gear/rack placement; forward and reverse shaft-hole alignment; multi-hole fitting.
- Insert depth/roll, fine fitting, per-face resize grips, numeric dimensions, R/T/Y rotations, direct drag, Alt-arrow coarse/fine nudging.
- Group/ungroup/edit member, duplicate with internal relationship remapping, delete, paint/physical materials.
- Material presets: Steel, Aluminum, Rubber, Plastic, Wood, Concrete. Paint: Factory, Matte, Satin, Gloss, Metallic, Chrome, Brushed, Pearl.

### Mechanical authoring

- Bearing (rotation), Slider (translation), Cylindrical (both), fit-only alignment, explicit Weld/Fixed/Bolt, general Spring, gear-to-shaft Rotation/Rigid, hand-crank coupling.
- Joint limits; spring stiffness/damping/free length; shaft motor (toggle, hold key, velocity, torque, acceleration); remove relationship.
- Physical hardware is a prerequisite for joint validity. Auto gear meshing does **not** require manual authored gear-pair links.
- The old server explicitly requires `Weld` to create a weld, `Edit` for most relationships, `Simulate` for joint property changes and simulation. This is a migration hazard.

### Assemblies and simulation

- Primitive != component != named assembly. Components do **not** implicitly weld; assembly is an exact simulation membership set, possibly including a subset of a component.
- Assembly create/name/select members/reopen/rename/nudge/undo; simulated assembly target shown purple.
- Simulate only registered members; missing connected members should block simulation rather than silently auto-enroll.
- Grounding, start/stop, pause, reset; hand crank LMB, guided rack Q/E, bound bearing motor input; telemetry and Properties.
- Simulation builds temporary clones and must not alter saved authored geometry.

### Persistence

- Plot load on join, autosave when dirty, final flush on leave/shutdown, F6 manual save/reload with confirmation.
- On-disk/DataStore schema, IDs, materials/finishes, relationships, grounding, memberships and exact poses must remain compatible.
- **Documentation discrepancy:** root README currently says F6 is the only save and there is no autosave; `docs/ARCHITECTURE.md`, `docs/QA_REGRESSION.md`, and `PlotPersistence.lua` describe autosave. Verify actual Studio persistence rather than repeating the stale README statement.

## Phase 0 source audit (read-only)

Nineteen lightweight static presence checks were performed against 20 code/document files at the frozen SHA; **19/19 passed**. They confirmed the old six tool IDs and server gating, main joint kinds and authoring services, geometry and smart matching, multi-fit utility, selection and input paths, paint/material separation, save-related code, assembly editor, freecam, and simulation controls.

These are presence/contract sanity checks, **not** Luau compilation or physics tests. The existing GitHub Actions source-contract workflow independently passed at the frozen SHA; its only verification command is `python3 scripts/verify_source.py`.

Static check tooling unavailable in the current session: local repository clone/Roblox Studio, Rojo, Stylua, Selene and execution of the Python source verifier. The reported CI success is observed through GitHub Actions, not reproduced locally.

## Known risks to watch before removing legacy UI

1. Multiple controllers listen for the same inputs and manage their own cursor/modal and selection states.
2. Tool-based server permission checks will reject new tool IDs until deliberately migrated; simply renaming the hotbar is unsafe.
3. Mechanical configuration currently lives under Simulate permission, although v2 moves authoring to Mechanics > Configure.
4. Build smart mating and Edit manual fitting use different orchestration paths, even when they call shared geometry validators.
5. Inspector, naming, numeric sizing, mating choice, paint, and plot menus each manage cursor ownership.
6. Existing visualization and instruction panels include legacy Highlights/instructional text, so the new renderer must be tested for orphaned states and Highlight budgets.
7. Geometry and mechanical clone behaviors need actual Studio regression, especially small-scale physics, complex transmissions and multiplayer isolation.
8. Historical documentation is inconsistent about autosave and Shift+P. Use current source plus fresh Studio observations as ground truth.

## Phase 0 exit gates

- [x] Create isolated migration branch from a verified `dev` SHA.
- [x] Preserve a complete, reversible baseline commit reference.
- [x] Record current native tools, major workflows and authorization ownership.
- [x] Confirm latest CI source-contract result for the frozen commit.
- [x] Add representative machine regression scenarios with identifiers and pass criteria.
- [ ] **IN-STUDIO:** capture before-change screenshots/video of all six original tool interactions and UI surfaces.
- [ ] **IN-STUDIO:** verify the representative saved-machine fixtures in a disposable test plot/place and record results.
- [ ] **IN-STUDIO:** record timing/performance and logs for complex assembly simulation and save/load.
- [ ] **IN-STUDIO:** verify autosave/manual persistence on a disposable saved plot; do not touch production player saves.

**Do not mark the runtime baseline verified or merge Phase 1 solely on source audit evidence.**

Next: [UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md). Retain [current QA regression](QA_REGRESSION.md) as the full engine regression suite.
