# OPENWORKS UI v2 — Phase 1 implementation (2026-11-12)

**Branch:** `feature/ui-reorganization-v2`
**Starting point:** `dev` @ `7eef04af7932d636ec448834956cdfe66721b000`
**Scope:** Three native tools, eight contextual subtools, client-side input routing, and compatible server tool authorization. **No changes to saved DataStore schema, geometry algorithms, gear kinematics, or physics services.**
**Verification status:** GitHub Actions source-contract workflow passes on this feature branch. **Not yet executed in Roblox Studio.**

## Implemented

### Primary native tool inventory

| Hotbar slot | ID (`OpenworksToolId`) | Displayed tool name |
| --- | --- | --- |
| 1 | `Build` | Build |
| 2 | `Mechanics` | Mechanics |
| 3 | `AssemblySimulation` | Assembly & Simulation |

Existing `Edit`, `Assembly`, `Simulate`, `Inspect`, `Weld`, and retired `Assemble` native tool instances are removed by `NativeToolProvisioner` on startup. No new Backpack UI is introduced; native hotbar remains the equip authority.

### Eight subtools

| Primary | Subtool | Shortcut | Mapped legacy controller mode |
| --- | --- | --- | --- |
| Build | Place | B | Build |
| Build | Edit | E | Edit |
| Build | Resize | V | Edit |
| Build | Paint | M | Edit |
| Mechanics | Connect | C | Mechanics |
| Mechanics | Configure | E | Mechanics |
| Assembly & Simulation | Assembly Editor | E | Assembly |
| Assembly & Simulation | Simulation | Y | Simulate |

- `ToolController` owns `PrimaryId`, `SubtoolId`, `LastSubtool`, `ActiveTool`, `Changed`, `SubtoolChanged`, and `Activated`.
- Subtool switching via shortcuts stores the last subtool under each primary and cancels old preview/authoring state when changing contexts.
- Modifier combinations (Ctrl/Alt/Shift) are not intercepted by subtool shortcuts. Existing F6, Ctrl+Z/Y, camera and native hotbar input remain.
- Modal/focused text input suppresses subtool shortcuts; the initialization guard protects active precision alignment from consuming E, which remains shaft roll during fitting.
- `OPENWORKS_PrimaryTool`, `OPENWORKS_ActiveSubtool` client player attributes are for UI only, never server authorization. Existing `OPENWORKS_ActiveTool` remains a compatibility view until the old panels are replaced.

### Build migration

- Place, Edit, Resize, Paint reuse the original construction and material services, not copies.
- Resize enters the existing face-handle mode; selecting a new primitive while Resize is active can start the handles.
- Paint enters the existing material/paint picker when an object is selected; when no object is selected, click/select it and press M again.
- Direct pickup/dragging is restricted to Build/Edit; Paint/Resize do not unexpectedly trigger a direct move.
- Build HUD title reflects the active subtool.

### Mechanics migration

- The native Weld tool is retired; **Mechanics > Connect, F** enters the existing validated two-body Weld workflow. F again or Esc leaves Weld selection and returns to connection authoring.
- **Mechanics > Connect**: click a physical opening then shaft for an existing bearing/slider/cylindrical workflow; **H** resets manual fitting; **Shift+J** starts Spring; **Shift+C** couples a hand crank; **Shift+Delete** removes a relationship; existing fitting alignment/roll/limits remain.
- **Mechanics > Configure**: click an authored object to inspect its relationships, adjust joint limits/spring settings and configure the bearing motor. The existing Properties panel is reused temporarily.
- The Properties panel hides Run/Stop and Ground controls when opened in Mechanics, because those mutations belong to Assembly & Simulation.
- The automatic build-time fit popup and geometry-smart mate behavior remain available in Build without duplicating the mechanical fit solvers.

### Assembly and simulation migration

- Native third tool uses `Assembly Editor` subtool for existing create/rename/member editing and `Simulation` subtool for registered-assembly testing.
- Assembly editor code remains the old controller with compatibility mode `Assembly`; Simulation controller still uses compatibility mode `Simulate` and its original held-input controllers.
- Server-side authorization accepts the **new primary Tool ID**, not untrusted client subtool attributes. Every action retains existing ownership, load, plot, collision, mechanical validation, and active simulation restrictions.
- Simulation-related control remotes (crank, rack and shaft motor) now require the new `AssemblySimulation` equipped native tool.

### Persistence and compatibility

- The server still handles `Place`, `SmartMate`, `CreateWeld`, `CreateRelation`, `TuneSpring`, `TuneBearingMotor`, `CreateAssembly`, `StartSimulation`, etc. via the SAME existing API action strings; no saved schema or ID migrations.
- Geometry mutation, undo/redo, named assembly membership, spring/motor parameters and plots remain in their pre-existing services.
- Simulated running assemblies cannot accept authoring modifications through these actions. Joint tuning moved from Simulate to Mechanics/Configure.
- Existing custom GUI/hotkey guides remain during Phase 1 for compatibility, and have been updated for Mechanics. Later phases replace them with unified Explorer/Properties and concise tooltips.

## Files changed

- `src/shared/Construction/ToolDefinitions.lua`
- `src/shared/Construction/SubtoolDefinitions.lua` (new)
- `src/server/Runtime/NativeToolProvisioner.lua`
- `src/server/Runtime/ConstructionService.lua` (tool permissions only)
- `src/client/Controllers/ToolController.lua`
- `src/client/Controllers/ConstructionController.lua`
- `src/client/Controllers/AssemblyController.lua`
- `src/client/Controllers/RelationshipProperties.lua`
- `src/client/Controllers/ContextKeybinds.lua`
- `src/client/init.client.lua`
- `scripts/verify_source.py` (migrated assertions)
- `.github/workflows/source-contracts.yml` (feature branch CI)
- `README.md` and Phase 1 docs

## Mandatory Studio smoke test before enabling Phase 2

1. Sync **feature/ui-reorganization-v2**, restart Play (not just hot reload), verify Forge banner and `UI-V2-PHASE1-TOOL-ROUTER` marker.
2. Check hotbar **exactly three tools** after join and after respawn; equip 1/2/3; no old native Tool objects. Cycle subtools B/E/V/M, C/E, E/Y and return: last subtool must persist.
3. Build > Place: use B catalog, place block and shaft, test smart snap, gear snap, reverse shaft fitting and fit popup. Build > Edit: select, drag, group, duplicate, Alt+nudge, delete, Ctrl+Z/Y. Build > Resize: resize selected part. Build > Paint: apply paint and physical material.
4. Mechanics > Connect: use H and choose a housing/shaft, create Bearing; choose Shift+J and make a spring; F to weld two solids; Shift+C to couple an existing hand crank. None of these should change Build geometry except intended connection authoring.
5. Mechanics > Configure: click fitted bearing; tune limit and motor fields. Test Ctrl+Z/Y in Connect, and verify authoring is rejected during active simulation.
6. Assembly & Simulation > Assembly Editor: press N, name assembly, select members, press Enter; rename, nudge, undo/redo. Switch to Simulation with Y; verify purple preview, G grounding, P start/stop, O pause, U reset, LMB crank, guided rack Q/E, and hold-key motor.
7. While entering shaft insertion depth/roll, E must adjust roll rather than switch to Configure. Ctrl/Alt/Shift chords must not switch subtools unexpectedly. All modals must restore cursor lock and freecam.
8. Run FIX-01 through FIX-06 and UI-01 through UI-22 from [UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md) and the existing [QA regression](QA_REGRESSION.md) on **disposable** saved plots. Record exact fail messages and source SHA.
9. Check current autosave/manual save loads old fixtures without schema changes. Do not clear or rewrite production saves. 
10. Before merging, run source contract and review any Luau/Studio errors plus before/after FPS. A passing GitHub Actions Python static check does not certify Roblox runtime.

## Deferred to subsequent phases, not implemented in Phase 1

- Unified Explorer with Objects/Connections tree, persistent Properties panel, right-click context menus and tooltips.
- Shared thin bounding-box/adornment visualization and the orange-then-green multi-object confirmation protocol.
- Fully consolidated Connect selection/fitting UI; temporary hotkeys still expose legacy operations.
- Removal of all legacy instructional text and obsolete UI/controller code.
- In-Study runtime verification (this environment cannot run Roblox Studio).

**Phase 1 source implementation status:** COMMITTED; CI source-contract PASSED. **Studio gameplay acceptance:** NOT RUN. Keep `dev` unchanged until real acceptance tests pass.
