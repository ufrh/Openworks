# OPENWORKS Phase 10 — Studio Acceptance Checklist

Build: `2026.11.10.PHASE10.EXPLICIT-WELD-PROPERTIES` on `dev`.
This is a manual test plan, NOT a claim that Roblox Studio testing was run.

## A — Editor components are NOT automatic physics welds
1. Place two separate blocks with contacting faces. Do NOT use Weld.
2. In Simulate run one block. Confirm there is no implicit welded attachment.
3. Stop. Select both blocks in Edit and press C to make a component.
4. Move the group in Edit. It should move together.
5. Simulate this component: both enter the scope, but should remain separate
   bodies under gravity unless manually fastened.
6. Repeat with shaft-in-hole connection choice 1 Group, then undo and redo.

## B — Intentional Weld tool
1. Equip native Weld (slot 5). Click a block, then a different touching block.
2. Simulate; the bodies should now maintain their welded relative positions.
3. Try two separated blocks: reject, with no orphan joint.
4. Create a component with two touching unfastened members. Welding those two
   members explicitly should succeed despite their shared ComponentId.
5. Clicking the same block twice or hitting Esc must not make a weld.
6. Verify undo/redo of authored welds and no automatic weld on face placement.

## C — Bolt prefab insertion
1. Build two separate drilled blocks with coaxial through-holes and a gap
   small enough for one stocked bolt to pass FULLY through both.
2. Build > Fasteners: choose a matching Bolt prefab and aim at the opening.
3. A coaxial blue preview should place the bolt head outside the entry face.
4. Confirm; the actual physical prefab stays, with both bodies fastened.
5. Simulate and make sure both bodies move with the bolt.
6. Repeat with one body; only the pierced body should be fastened.
7. Reject a bolt that is too thick/short, off-axis, or collides with other
   solids. Failed operations must leave no ghost constraints or parts.
8. Place an unfastened bolt first and then drag it into a hole from Edit.
9. Undo/redo bolting and relationship removal, observing bolt restoration.

## D — Spring presentation
1. Build two matching 4 × 0.5 × 4 U plates and author a plate spring.
2. Confirm the coil is orange and maximally fills the common plate face,
   leaving a small edge clearance.
3. Rotate both plates so their common normal is X or Z. Radius must match
   actual face dimensions, not the wrong world axis.
4. Test a shaft-in-tube spring: orange coil fits the shaft/tube size.
5. Simulate. Original coil AND construction guides disappear, but the native
   spring remains active and can compress/rebound. Stop: visuals reappear.

## E — Simulate relationship properties GUI
1. Equip Simulate: cursor unlocks, standard Properties GUI appears.
2. Click an authored block, then one of its relationships from the list.
3. For Spring, set Stiffness, Damping, Rest length (U) and Apply.
4. For Bearing/Slider/Cylindrical, edit lower/upper limits and enable status.
5. Invalid numeric or physically impossible settings should be rejected.
6. Run simulation with the GUI. Select a live simulated part, choose its
   relationship and change the spring properties again; motion should update
   live without stopping or rebuilding. Repeat for joint limits.
7. A Bolt/Weld relationship should have no fake tunable fields.
8. Confirm all changes persist after Stop, but original geometry restores.
9. Verify another player cannot tune your authored relationships.

## F — Regression
Verify shaft alignment from both sides, insertion and linear hard stops,
gear/hub behavior, component editing, undo/redo, spring travel, full registered
assemblies, grounding colors, and no Studio Output exceptions.
