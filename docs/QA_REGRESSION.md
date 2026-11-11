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
- [ ] For gear/shaft selection, the popup offers ONLY Rotation and Rigid; both create the intended native physical connection. Check gear placement in both directions and undo/redo after selecting.
- [ ] Manual Edit > L > choose drilled opening > confirm preview ALSO opens the same relationship picker. Choosing a real joint creates a bearing/slider/cylindrical relationship; Fit Only performs geometry-only Align; Cancel/Adjust remains in preview for further positioning.
- [ ] Shaft in a hole: alignment first, then depth/roll adjustment, correct geometric collision handling both forward and reverse.
- [ ] Bearing permits rotation; Slider permits travel inside shaft length; Cylindrical permits both. None self-actuates. Fixed, Weld and Bolt do not invent motion.
- [ ] Springs are passive, obey their configured stiffness/damping and show their physical coil in simulation. No duplicate static spring visuals while simulating.
- [ ] Multiple bearings and multi-fit grouped shafts stay aligned and don't create floating relations.
- [ ] Couple a hand crank to shafts of at least two different diameters. Its entire radial geometry and output diameter resize to match; the output end stays flush. Resize a coupled shaft using numeric sizing or 0.05-U fine fitting: its crank follows atomically, and undo/redo and F6 save/load reconstruct both sizes correctly. Moving a coupled shaft end away without its crank is rejected.
- [ ] Register a named assembly containing a hand crank, shaft, bearing and grounded housing. In Simulate, HOLD LMB over crank: it accelerates toward a fixed speed under bounded torque; RELEASE LMB and rotation drive stops immediately (inertia may persist). The input is not based on mouse drag, does not change the camera, and cannot create infinite torque. Check quick click/release races, switching tools, leaving range, missing hold packets, pause, stop, reset and respawn.
- [ ] Weld a fitted shaft within the empty clearance bore of a drilled block with the Weld tool, even though its solid faces do not touch. They remain completely rigid in simulation. Reject unrelated non-touching solids, a shaft outside the hole, misaligned/oversize shafts, and conflicting existing motion relationships.
- [ ] Build and Edit gear-to-shaft hub placement both ways (drag gear onto shaft; move shaft into gear). Only Rotation (native unpowered hinge, no axial travel) or Rigid (explicit weld) appear; no automatic editor grouping or third mode. Reject a shaft exceeding the gear bore and duplicate/incompatible joint types.
- [ ] Use a geared assembly with a rigid gear/shaft mount and a freely rotating gear/shaft mount. Rotation allows relative spin but not slide; Rigid transmits torque. Gear-to-gear contact remains passive and may slip until separately tuned.
- [ ] P start/stop, Shift+P free, O pause/resume, U reset. Original authored geometry/metadata return intact; repeated simulation doesn't leak physics clones.
- [ ] Gear teeth physically mesh in either direction where intended; record observed slippage/jamming as current physics work, not proof of correct transmission.

## UI and persistence
- [ ] Left-side passive Simulate panel and controls list visible, right inspector opens on click, Esc closes it; ordinary mouse remains first-person locked.
- [ ] Assembly naming, plot saving, properties, numeric editor and mate selection unlock cursor only while modal is open, then restore lock.
- [ ] Manually save with F6; leave, rejoin, verify all parts/components/named assemblies/relations/grounding persisted. Undo history must not be persisted.
- [ ] Manual Save failure displays an error, clears Busy, and never writes an empty fallback over a valid previous save.
- [ ] Explicit Load restores last saved state without autosaving changes made since. A corrupt/unavailable document returns Error and does not strand the plot in Loading.
- [ ] After all scenarios, Output has no Luau errors and no orphan `OPENWORKS_Local...` visual folders, old ghost Parts, or extra `OPENWORKS_Simulated` sessions.

## Verify code without Studio

Run `python scripts/verify_source.py` from the repository root. This is a static consistency check only; it cannot validate Luau syntax, input behavior or physics. Use the installed Rojo toolchain to perform `rojo build default.project.json --output builds/openworks.rbxlx` and then complete the actual Play tests above.
