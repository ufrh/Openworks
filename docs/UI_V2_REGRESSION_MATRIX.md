# OPENWORKS UI v2 — Regression Matrix and Saved-Machine Fixtures

**Prepared in Phase 0.** Baseline commit: `7eef04af7932d636ec448834956cdfe66721b000`. Migration branch: `feature/ui-reorganization-v2`.

**Test status as of creation:** Source-contract CI for the baseline commit **passed**. The tests below are **NOT RUN IN STUDIO**. Fill in the actual baseline results and after-migration results before declaring the feature release-ready.

## Test environment and evidence

- Work in a disposable Roblox Studio test place/plot, using the synced `dev` baseline first. Never delete or overwrite an actual player's DataStore to produce fixtures.
- Preserve a copy of the baseline build/plot and exact source SHA; do not assume unsaved edits persist.
- Capture: console errors, visible UI/selection screenshots, a short video for any dynamic mechanism, saved plot timestamp, and approximate FPS before/after.
- Use the same plot, mechanism dimensions, camera location, and assembly membership for baseline and v2 comparison.
- Record outcomes as `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`; do not replace missing runtime observations with source assertions.
- Each test below must be run on baseline and on the final v2 implementation. Existing detailed engine tests remain in [QA_REGRESSION.md](QA_REGRESSION.md).

## A. Representative saved-machine fixtures

| ID | Fixture | Setup and baseline actions | Passing mechanical/persistence outcome |
| --- | --- | --- | --- |
| FIX-01 | Rigid component + painted frame | Place multiple blocks, group some as a component, explicitly weld touching solids, color some individually and others as component, nudge, duplicate, save and reload. | Component grouping does not secretly weld; intended welds persist; duplicated internal relations receive new IDs; copied component is independent; appearance and precise transforms round-trip. |
| FIX-02 | Multi-hole free hinge | Place two aligned drilled blocks and a long fitting shaft, select Rotation Only for both bores, fasten a lever to the shaft, ground supports, register exact members, save, simulate, reset and reload. | Two real bore contacts, no phantom collision or misalignment; lever rotates about physical shaft; all joints persist; reset restores authored pose. |
| FIX-03 | Spring-loaded slider | Place housing, fitted shaft/carriage and free spring between two objects; configure slider/cylindrical limits plus stiffness/damping/rest length; ground support; save/simulate/reload. | Shaft stops at actual housing end planes; spring remains passive and tunable; parameters, member IDs and original positions persist. |
| FIX-04 | Compound transmission | Rigidly mount 12T/20T/32T spur gears on separate supported axles, mesh automatically, attach hand crank, register exact assembly. Additionally test matched 45° and 90° bevel pairs in their own assembly or saved test state. | Ratios/directions and automatic mesh work without K-authored relationships; supported gears turn as intended, pause/reset restore authored state; unmatched/invalid mesh is not faked. |
| FIX-05 | Rack, guide, and pinion | Mount pinion on a supported shaft and place rack in grounded guide; create named assembly; hand-drive pinion and separately hold Q/E over guided rack, then save/reload. | Correct guided travel and travel stops; reciprocal backdrive; blocked or unsupported input doesn't move the mechanism; no unexpected native gear forces. |
| FIX-06 | Configured shaft motor | Create a shaft through real bearing hardware; enable Shaft Motor through current Simulate Properties, bind F, set representative speed/torque/acceleration (e.g. 3 rad/s, 3000 torque, 40 acceleration); save/simulate/reload. | F activates motor only on supported bearing; releasing F/pause/stop halts it; reversal works if configured; no floating powered joint; configuration persists. |

**Baseline evidence:** fill in after Studio testing.

| Fixture | Baseline result | Baseline evidence location | v2 result | v2 evidence location |
| --- | --- | --- | --- | --- |
| FIX-01 | NOT RUN | — | NOT RUN | — |
| FIX-02 | NOT RUN | — | NOT RUN | — |
| FIX-03 | NOT RUN | — | NOT RUN | — |
| FIX-04 | NOT RUN | — | NOT RUN | — |
| FIX-05 | NOT RUN | — | NOT RUN | — |
| FIX-06 | NOT RUN | — | NOT RUN | — |

## B. UI/UX baseline and final v2 acceptance

| Test | Priority | Baseline to capture | v2 acceptance |
| --- | --- | --- | --- |
| UI-01 Native tools | P0 | Six hotbar tools appear once each, also after respawn | Exactly three native tools (Build, Mechanics, Assembly & Simulation); no duplicates or legacy tool objects. |
| UI-02 Subtools | P0 | Old Build/Edit/Assembly/Simulate/Inspect/Weld flows | All eight subtools reachable, correct context-specific shortcuts, previous subtool restored when returning. |
| UI-03 Input ownership | P0 | Observe collisions among B/E/V/M/R/T/Y/Tab/Alt combinations | One action per keystroke in correct context; no held-input leakage or duplicate triggers after switching. |
| UI-04 Cancel and switching | P0 | Cancel move, resize, mate, assembly draft, modal | Esc unwinds active operation first; tool switch rolls back unfinished operations; committed changes retained. |
| UI-05 Freecam | P0 | Initial camera, FOV, mouse look, flight, respawn | Identical camera feel and limits; opening/closing modal never causes camera jump or lost cursor. |
| UI-06 Selection | P0 | Primitive, component, inner member, multiselect, depth/X-ray/isolate | Same entity/ID selection semantics; one thin aqua box for primitive/component; correct per-object multi selection. |
| UI-07 Explorer objects | P0 | Baseline assembly/member names and IDs via old UI | Object tree reflects actual assembly IDs and partial component membership; selects synchronously with 3D. |
| UI-08 Explorer connections | P1 | Existing relations identified through old inspector | Connection view shows actual relationship endpoints with no implicit parent/child or fake rigid connections. |
| UI-09 Properties | P0 | Baseline numeric sizing, material, paint, springs, limits and motors | One shared panel edits correct object/relation, updates immediately, respects simulation read/write restrictions. |
| UI-10 Context menus | P1 | Existing key-driven actions | RMB exposes only valid current actions, matches keyboard behavior, does not force unwanted tool switches. |
| UI-11 Tooltips | P1 | Existing instructional HUD behavior | Accurate concise hover text with shortcuts; no permanent instructional prose in the workspace HUD. |
| UI-12 Visual renderer | P0 | Legacy selection/ghost/grounding/joint cues | Bound-accurate boxes; aqua selected, purple assembly, orange pending, green finalized, red invalid; no stale adornments. |
| UI-13 Connection steps | P0 | Weld, spring, bearing, slider, cylinder, bolt and crank coupling | First and second selections orange; final server-confirmed success flashes green; rejected operation never flashes green or leaves half-relations. |
| UI-14 Specialized fit | P0 | Forward/reverse shaft fitting, target cycling, depth and snug scroll | Same final server geometry as preview; supports multi-hole, gear hubs and mouse-targeted shaft position; rejection shows correct interference. |
| UI-15 Grounding | P0 | Ground/release before sim, persistent grounding | Grounded green, free blue; exact authored state retained and correct during simulation; transient connection green is not mistaken for grounding. |
| UI-16 Assembly scope | P0 | Explicit partial member registration and unregistered connected-body rejection | Preserves exact members, names, transform and boundary validation; purple target and per-member outline never enroll extra solids. |
| UI-17 Simulation | P0 | P, O, U, LMB crank, Q/E rack, configured motor hold, inspection | Running, pause, reset, stop and input-release semantics unchanged; no construction edits while running; original geometry restored. |
| UI-18 Save/load | P0 | F6 Save/Load, autosave, reload confirmation, busy/error handling | Existing schema and IDs compatible; dirty-only writes; no silent empty overwrite; save/load of every fixture exact. |
| UI-19 Undo/redo | P0 | Transform, group, duplicate, attach/detach, assembly membership | Atomic history and restored relation metadata; no orphan refs; history remains volatile across load. |
| UI-20 Multiplayer | P0 | Two separated player plots and independent controls | No cross-plot editing, foreign highlighting, or remote invocation bypass. |
| UI-21 Performance | P1 | FPS and log while moving large component/assembly and simulating gear train | No sustained frame degradation or unbounded adornment/highlight growth; visual easing never alters authoritative geometry. |
| UI-22 Modal stacking | P0 | Material/numeric/catalog/relationship/name/plot menus | One cursor owner; close/cancel/respawn restores lock; no invisible input overlay consumes clicks. |

**P0 = release blocker.** `NOT RUN` is not a pass. For UI-01/02/03 the expected baseline has six old tools; compare behavior rather than expecting the new UI on the old commit.

## C. Migration authorization matrix (server contract)

| Existing server action(s) | Old allowed tool | New allowed primary/subtool context | Safeguard |
| --- | --- | --- | --- |
| Place/Update/Delete/Rotate/Group/Ungroup/Transform/Duplicate | Build/Edit, often Edit-only | Build / appropriate subtool | Preserve ownership, plot checks, history and simulation lock. |
| SmartMate, Align, FitShaft, PoseShaft | Build/Edit plus Edit-gated operations | Build auto-fit handoff or Mechanics / Connect or Configure | Reuse actual clearance/fit tests; do not grant generalized remote mutation. |
| CreateRelation, CreateSpring, CreateBolt, CoupleHandCrank | Edit | Mechanics / Connect | Validate pair geometry and prevent partial commits. |
| CreateWeld | Weld | Mechanics / Connect | Explicit, validated rigid connection only. |
| AdjustJoint, TuneSpring, TuneBearingMotor | Simulate | Mechanics / Configure (authored, stopped state) | Preserve motor/limits semantics and prevent unauthorized edits while running. |
| CreateAssembly/UpdateAssembly | Assembly | Assembly & Simulation / Assembly Editor | Preserve exact member IDs, ownership and partial component inclusion. |
| SetGrounded | Simulate/Edit | Assembly & Simulation / Simulation or approved configuration context | Server checks ownership and authored vs simulated state. |
| Start/Pause/Reset/StopSimulation, BeginCrank, BeginRack | Simulate | Assembly & Simulation / Simulation | Validate actively equipped tool and subtool/session authority. |
| GetMechanismInfo | Read-only | Simulation/inspection | No unintended mutation. |
| SetMaterial/SetPaint | Edit | Build / Paint | Preserve physical vs cosmetic material separation. |
| SavePlot/LoadPlot, Undo/Redo | Tool-agnostic with restrictions | Universal | Never bypass active-load, simulation, ownership or concurrency protections. |

**Note:** These are targeted migrations, not permission grants already implemented. Do not trust client-reported subtool IDs without validation; an equipped native tool and explicit server-side action allowlists remain essential.

## D. Execution and exit record

1. Run source contract and record source SHA/CI link.
2. Perform all FIX-01 through FIX-06 on the **baseline** and capture a manual or autosaved test plot for each, with screenshots/video. Using one plot per fixture or separate disposable test states avoids overwriting unrelated work.
3. Perform UI-01 through UI-22 as applicable on baseline; record actual behavior, bugs and console output.
4. After UI v2 code changes, repeat all fixtures, UI acceptance and the repo's [full current QA suite](QA_REGRESSION.md).
5. Check saves made before the migration still load under v2 **without migration**, then verify reload/undo and save back to new sessions.
6. Do not merge if any P0 fails or cannot be tested; preserve `7eef04af7932d636ec448834956cdfe66721b000` as rollback reference.

## Phase 0 recorded results

- [x] Frozen branch and baseline SHA
- [x] Existing source-contract CI passed at that SHA
- [x] Static source inventory checked (19 presence checks, all passed)
- [x] Test fixtures and migration acceptance criteria defined
- [ ] Baseline machine fixtures executed inside Roblox Studio
- [ ] Evidence and results entered above
- [ ] Baseline screenshots and performance sample captured

**Truth in reporting:** the first four items are repository-complete; the last three require real Studio access and have not been executed.
