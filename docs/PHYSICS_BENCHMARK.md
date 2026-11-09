# OPENWORKS — Constraint and Scale Physics Laboratory

> **Experimental branch:** `experiments/physics-constraint-scale-bench` (from `dev`).
> Nothing in this branch is intended for merging into the clean rebuild until measurements justify it.

## Purpose

Determine the smallest *practically stable* OPENWORKS mechanical construction scale. Every one of the 17 mechanisms is generated at the same five reference sizes: **0.375 / 0.25 / 0.1875 / 0.125 / 0.0625 studs**. 0.375 studs is the largest candidate after encouraging preliminary hands-on testing; the new comparison searches downward for the first unstable scale. The reference is the nominal 1-unit structural dimension in the fixture, not necessarily the thickness of every beam or shaft. The smaller decorative/shaft dimensions are scaled proportionally.

**Scope:** native Roblox constraints exclusively. WeldConstraints are used to make rigid multipart assemblies; no custom force/kinematic solvers, runtime CSG, or procedural mesh generation.

## Running in Studio

1. Commit or stash any **uncommitted local** work. This branch was created remotely and does not automatically switch your local checkout.
2. In the OPENWORKS repo, run `git fetch origin` and `git switch experiments/physics-constraint-scale-bench`.
3. Use existing `START_OPENWORKS.bat` to start Rojo on the branch, attach Studio to the same project/port, and press **Play**. This branch does **not** alter FORGE, the dev bootstrap, or the Rojo project file.
4. The Studio-only `PhysicsBenchmark.server.lua` spawns five stations automatically. The client UI provides **Previous / Next / Run Test / Run All 17 / Stop / Export CSV** and camera focus controls.
5. Click **Run Test** to do the current test at all five scales, or **Run All 17** for the complete suite. Three trials per phase are configured.
6. Click **Export CSV**, focus the results textbox, press Ctrl+A then Ctrl+C, and paste into a local CSV file **before ending Play**. The server also prints CSV chunks to Studio Output as a fallback.
7. When finished, switch back to `dev` and restart Rojo. Do not merge the experiment branch just to obtain measurements.

Runs create/destroy only `Workspace.OPENWORKS_PhysicsBenchmark` and `ReplicatedStorage.OWPhysicsBenchmarkRemote`. The whole benchmark is gated behind `RunService:IsStudio()`.

## Test fixture inventory

| # | Mechanism | Native physics relationships |
|---|---|---|
| 01 | Hinged pendulum | Hinge; angle limits |
| 02 | Motorized flywheel | Motor Hinge; welded shaft; eccentric load |
| 03 | Linear carriage | Motor Prismatic; translation limits |
| 04 | Telescoping spindle | Cylindrical; simultaneous translation and rotation |
| 05 | Ball socket arm | BallSocket; tilt and twist limits |
| 06 | Spring and damper | Spring + Prismatic guidance |
| 07 | Torsion return lever | Hinge + TorsionSpring |
| 08 | Rope winch hoist | Rope; winch actuation |
| 09 | Dual rod linkage | Two RodConstraints and hanging masses |
| 10 | Rigid cantilever | Six RigidConstraints and end load |
| 11 | Universal joint drive | Motor Hinge + Universal + BallSocket support |
| 12 | Planar platform | PlaneConstraint |
| 13 | Four-bar linkage | Four HingeConstraints in a closed loop |
| 14 | Slider-crank | Three Hinges + Prismatic |
| 15 | Wheel suspension | Spring + Prismatic + wheel Hinge + impact floor |
| 16 | Double-bearing shaft | Two coaxial Hinges sharing a shaft |
| 17 | Shared crank network | Three linked slider-cranks welded to one supported drive shaft |

The tests are real constraint assemblies, not animated props. **Do not infer that they are functional from construction alone**; run them in Studio and inspect errors, visible movement, and the reported measurements.

## Test matrix

For each mechanism and each of the five scale variants, the system records the following across **three fresh trials** of **seven seconds per phase**:

- **Idle:** zero actuator command / free settling;
- **Normal:** nominal motor input, cycling of linear actuators;
- **Heavy:** enables physical ballast plus controlled external impulses;
- **Extreme:** high angular speed, reversals, extra loads, and stronger impulses.

Fresh rigs are rebuilt for every phase and trial, eliminating accumulated state. The `ReferenceScale` remains **0.75** specifically to preserve the geometric meaning of the previous 0.375-stud candidate; changing it would silently enlarge all five rigs and invalidate the comparison. Candidate/reference controls are stored in `src/server/Bench/Config.lua`. Motor force/torque and spring parameters use documented scaling approximations, with **constant density and unchanged global gravity**. These are *comparison heuristics*, not strict physical similarity under gravity. Some phenomena (e.g. spring natural frequency, fixed RPM, collision speed) cannot all be dynamically similar at once.

The tests intentionally disable inter-part collision in most fixtures so constraint instability is distinguishable from mesh contact. The suspension has a physical wheel-to-floor collision. Real-world collisions, teeth meshing, and user-built complex machines need a later, separate test campaign.

## Output columns

- `test`, `reference_studs`, `physics_stepping`, `gravity`, `phase`, `trial`, `samples`
- `mean_rel_joint_error`, `peak_rel_joint_error`: max per-sample anchor/axis/length violations, normalized by reference size
- `mean_axis_error_deg`, `peak_axis_error_deg`: Hinge and Prismatic axis divergence, degrees
- `mean_motor_speed_error`: relative actuator speed-magnitude error, where a motor applies
- `mean_heartbeat_dt_s`, `peak_heartbeat_dt_s`: **frame timing proxy, not actual physics solver time**
- `mean_physics_throttle_pct`, `invalid_samples`, `status`, `detail`

`BUILD_ERROR` or `INTERRUPTED` results should be treated as **invalid tests**, not physics failures. The monitoring system records constraint violations but cannot detect every form of instability; verify motion visually. In particular, Spring settling and universal joint transmission are not comprehensively measured by these baseline fields. Pass/fail limits should be agreed *after inspecting the first run*, not guessed in advance.

## Fixed versus Adaptive

The stepping mode is recorded when readable; if Roblox blocks scripted access, the CSV contains RECORD_MANUALLY and you must label the exported run yourself. **`Workspace.PhysicsSteppingMethod` is not scriptable**. In Studio Explorer > Workspace > Properties, set the PhysicsSteppingMethod to **Fixed**, run/export the entire matrix, then change to **Adaptive** and repeat under otherwise identical settings. Monitor actual solver cost with Studio **MicroProfiler (Ctrl+F6)** and Studio physics diagnostics, not Heartbeat alone.

Also record Studio build, graphics load, hardware, server/client configuration, and whether the application was foregrounded. Single-client Play with server-owned benchmark assemblies is recommended for the first controlled pass.

## Interpreting results

The chosen construction minimum must survive **every mandatory mechanical rig** at repeatable error/throughput tolerances, not merely run an isolated spinning hinge once. Consider the difference between microscopic measurement noise and visible mechanical failure, require multiple trial replicates, and do not confuse small parts' natural inertia differences with solver problems.

**Verification status:** All fixtures, runner, UI and CSV export have been written to this branch; their behavior has **not** yet been executed or validated in Roblox Studio from this environment. First review must check for startup/runtime errors and whether each rig truly executes its intended motion. Then collect real data before setting scale limits.
