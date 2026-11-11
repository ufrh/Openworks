# OPENWORKS — Current Studio regression checklist

Run after changing the shared geometry code, construction services, tool dispatch, input controllers, simulation or persistence. **This is a manual acceptance list**, not a claim the tests have already passed. File a specific bug with Studio Output, build marker and reproduction if any case fails.

## Setup and startup
- [ ] Sync `dev` in Rojo, restart Play, confirm current client/server marker and FORGE banner in Output.
- [ ] Tool hotbar has Build, Edit, Assembly, Simulate, Inspect, Weld **once each** after first join and after respawn; no legacy Assemble tool or duplicate tool.
- [ ] Studio empty plot reaches `Ready` when API access is enabled; if API unavailable, show `Error` (never permanent `Loading`). Building still works; saving stays disabled.
- [ ] Player plots do not overlap; construction and remote actions cannot edit other players' models.

## Build / Edit / components
- [ ] Place block, cylinder, shaft, drilled block, gear, bolt and hand crank from the primitive bank. Preview fits and placement match final server geometry.
- [ ] Resize a primitive with Neon scale grips; numeric sizing and snapping work; no leftover scale handle/ghost after cancel or tool switch.
- [ ] Select several primitives and combine with C; component highlights as **one outer boundary** with no shadow doubles.
- [ ] Drag/copy/rotate grouped and ungrouped primitives. Ghost is cohesive, no part shadows; cancel restores originals exactly; delete removes selection adornments.
- [ ] Edit one primitive inside a component without implicitly welding it; ungroup/recombine; undo and redo metadata does not recreate physics Parts or break mechanical references.

## Named assemblies
- [ ] Equip Assembly, N, name dialog, Enter; selected components and individual primitives turn purple.
- [ ] Click whole component to toggle **all** members; Alt+click one inside component to toggle just that primitive. Confirm with Enter; Esc leaves prior assembly unchanged.
- [ ] Reopen a named assembly, rename using R, add/remove members, confirm. **Ctrl+Z/Ctrl+Y with Assembly equipped** restores names and membership in place; reloading a manual save preserves it.
- [ ] Deny mixed ownership, nonexistent IDs and attempts to add a primitive belonging to a second assembly. Reject empty assembly and more than 128 primitives.
- [ ] Aim at any saved member with Simulate: every **actual registered member** highlights purple, including disconnected primitives and partial editor components. Highlight clears immediately on tool switch or starting sim; no stray purple outline.
- [ ] If a mechanical joint crosses to an unregistered member, P refuses. Add that member explicitly in Assembly, P simulates exactly the registered set.
- [ ] Selection/ghost/inspector Highlights remain visible and clear after delete, undo, plot reload and respawn.

## Mechanical relationships and physics
- [ ] Aim/place a shaft in a drilled hole, or a gear onto a shaft, using Build or Edit. A mouse-clickable relationship popup opens on the first valid fit (not keyboard-number selection); test every option by clicking the actual full-width button, including fast double-click prevention.
- [ ] During relationship selection, the mouse cursor unlocks over a top-layer modal; no invisible construction hitbox catches the button click. Pressing 1–9 or numpad numbers must NOT select a relationship, equip a hotbar tool or move the popup. Esc, Cancel and clicking outside dismiss; the cursor and native Backpack return to their previous state.
- [ ] For shaft/hole selection, choose Rotate+Slide, Slide, Rotate, or Fit Only. The Adjust depth/roll option returns to the locked preview without making a joint; scroll/Q/E, click again and choose a physical relationship. Test forward and reverse drilled-block fits and multi-guide shafts.
- [ ] For gear/shaft selection, the popup offers ONLY Rotation and Rigid; both record the correct authored relationship. During gear simulation these are interpreted kinematically instead of creating a native bearing force. Check placement both directions, undo/redo, and that Rotation does not rigidly link the gear to the shaft.
- [ ] Manual Edit > L > choose drilled opening > confirm preview ALSO opens the same relationship picker. Choosing a real joint creates a bearing/slider/cylindrical relationship; Fit Only performs geometry-only Align; Cancel/Adjust remains in preview for further positioning.
- [ ] Shaft in a hole: alignment first, then depth/roll adjustment, correct geometric collision handling both forward and reverse.
- [ ] Bearing permits rotation; Slider permits travel inside shaft length; Cylindrical permits both. None self-actuates. Fixed, Weld and Bolt do not invent motion.
- [ ] Springs are passive, obey their configured stiffness/damping and show their physical coil in simulation. No duplicate static spring visuals while simulating.
- [ ] Multiple bearings and multi-fit grouped shafts stay aligned and don't create floating relations.
- [ ] Couple a hand crank to shafts of at least two different diameters. Its entire radial geometry and output diameter resize to match; the output end stays flush. Resize a coupled shaft using numeric sizing or 0.05-U fine fitting: its crank follows atomically, and undo/redo and F6 save/load reconstruct both sizes correctly. Moving a coupled shaft end away without its crank is rejected.
- [ ] Register a named assembly containing a hand crank, coaxially welded shaft, bearing and grounded housing WITHOUT any gear. In Simulate, HOLD LMB on the crank: the standalone ungeared shaft uses native AngularVelocity and reaches a fixed speed within bounded torque. Release to disable the motor; remaining inertia is physical. Check normal safety conditions, input races, release and pause.
- [ ] With ONE HandCrank in a running assembly,
- [ ] Position two correctly meshed Transmission gears, each rigidly attached to its own shaft with separate grounded bearing housings, and DO NOT press K or create a Gear relationship. HOLD LMB: both gear/shaft groups rotate kinematically at the correct inverse tooth-count ratio with no native physics influences. Release, pause, stop or watchdog timeout must immediately stop scripted rotation (no simulated coasting).
- [ ] Move gears farther than the actual pitch-circle engagement distance: the runtime must disengage them immediately rather than remember the previous K relationship. Verify incompatible tooth modules, non-parallel axes, face separation and gear pairs welded on the same axle cannot generate a spurious mesh.
- [ ] Old saved K Gear metadata may still exist on the plot, but auto-engagement must behave identically after removing that metadata. Pressing K now explains that automatic meshing is enabled and does not open a manual pair-creation state.
- [ ] In the running simulator, inspect Workspace.OPENWORKS_Simulated: every rigid body containing a gear (and its welded shaft/crank) is fully anchored, noncolliding, queryable on visible geometry, and has NO native HingeConstraint, WeldConstraint, Torque or AngularVelocity attached. A separate un-geared mechanism in the SAME registered assembly must still use its ordinary native physical constraints.
- [ ] Kinematic gears pause, resume, reset and return to the exact authored edit pose when simulation stops. Contradictory rigid gear loops stay still; a grounded gear train cannot rotate. Make multiple gear stages and use reversed local shaft X axes to verify signed ratio propagation.
- [ ] Test automatically engaged chains of three or more meshed gears,
- [ ] Weld a fitted shaft within the empty clearance bore of a drilled block with the Weld tool, even though its solid faces do not touch. They remain completely rigid in simulation. Reject unrelated non-touching solids, a shaft outside the hole, misaligned/oversize shafts, and conflicting existing motion relationships.
- [ ] Build and Edit gear-to-shaft hub placement both ways (drag gear onto shaft; move shaft into gear). Only Rotation (native unpowered hinge, no axial travel) or Rigid (explicit weld) appear; no automatic editor grouping or third mode. Reject a shaft exceeding the gear bore and duplicate/incompatible joint types.
- [ ] Manually align a selected shaft through a gear using Edit > L; the gear's actual annular bore is selectable. Set insertion depth, confirm and choose ONLY Rotation or Rigid. Confirm both types create the correct authored relation and persist across F6 save/load and undo/redo.
- [ ] Mount a gear on a shaft and insert a shaft into a gear via smart Build/Edit snapping. The cursor can target a gear rim even if its noncolliding center pivot isn't raycastable; show a valid ghost only for truly concentric alignment, sufficient diameter clearance and shaft overlap. Reject oversize, off-center, skewed, or barely disengaged shafts without allowing unrelated intersecting parts.
- [ ] Gear hub snap acquisition is restricted to the actual center bore or shaft axis (tiny 0.24-stud aim tolerance, 0.34-stud radial proximity); aiming at outer teeth must NOT attract the shaft or gear. Confirm the camera can aim THROUGH an empty, non-queryable gear pivot, snap at the true center, and retain alignment without target flicker.
- [ ] Test 12T, 20T and 32T gear bores with the minimum standard 0.375-stud diameter shaft. The old 12T 0.28-stud bore was unusable; the regenerated 12T bore must physically fit with clearance. Old template geometry must be rebuilt, not merely change its radius attribute.
- [ ] Test shaft-in-gear and gear-on-shaft with short and long shafts; different shaft end insertion depths must be selectable without snaps grabbing gear teeth. With multiple close gears, the correctly aimed center should outrank previously preferred nearby targets.
- [ ] In Assembly simulation, a Rotation hub does NOT rigidly connect the gear and shaft, but the gear can still rotate independently when engaged with another gear. A Rigid gear mount moves its attached shaft with the gear. Neither uses a native bearing constraint while part of a geared kinematic body.
- [ ] Use a geared assembly with Rigid and Rotation gear/shaft mounts. Rotation allows independent rotation; Rigid transmits rotation. Meshing is automatic from geometry and must NOT require a saved Gear relationship.
- [ ] P start/stop, Shift+P free, O pause/resume, U reset. Original authored geometry/metadata return intact; repeated simulation doesn't leak physics clones.
- [ ] All gear-containing rigid groups are anchored, noncolliding and driven only through scripted kinematics, including attached shafts and cranks. Native bearings and internal weld constraints must NOT apply forces to the geared groups; other non-geared bodies still receive normal Roblox physics. Verify ratio direction, speed, cycle lockouts, grounding, independent groups and that visible tooth phase, backdriving and torque conservation still require further modeling.

## UI and persistence
- [ ] Left-side passive Simulate panel and controls list visible, right inspector opens on click, Esc closes it; ordinary mouse remains first-person locked.
- [ ] Assembly naming, plot saving, properties, numeric editor and mate selection unlock cursor only while modal is open, then restore lock.
- [ ] Manually save with F6; leave, rejoin, verify all parts/components/named assemblies/relations/grounding persisted. Undo history must not be persisted.
- [ ] Manual Save failure displays an error, clears Busy, and never writes an empty fallback over a valid previous save.
- [ ] Explicit Load restores last saved state without autosaving changes made since. A corrupt/unavailable document returns Error and does not strand the plot in Loading.
- [ ] After all scenarios, Output has no Luau errors and no orphan `OPENWORKS_Local...` visual folders, old ghost Parts, or extra `OPENWORKS_Simulated` sessions.

## Verify code without Studio

Run `python scripts/verify_source.py` from the repository root. This is a static consistency check only; it cannot validate Luau syntax, input behavior or physics. Use the installed Rojo toolchain to perform `rojo build default.project.json --output builds/openworks.rbxlx` and then complete the actual Play tests above.
