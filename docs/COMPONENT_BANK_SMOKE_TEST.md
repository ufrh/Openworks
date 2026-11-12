# Component Bank + Unified Build: Studio acceptance test

This phase has source-contract coverage, **not verified in Roblox Studio**. Test with Studio API Services enabled if DataStore access is otherwise denied.

## Single Build tool
1. Start, equip **Build**. Verify no Edit tool remains (including a server hot reload and respawn).
2. Aim at an existing block; click selects it. **G** moves; **V** resizes; **O** edits the pivot; **M** edits paint/material. Verify the other native tools still work.
3. Press **B**; both primitives and **MY COMPONENT BANK** are visible. Select a primitive. Verify it follows the cursor as a ghost. Place it once, then press **Enter**. The ghost disappears and clicking now selects the placed part with Build still equipped.
4. Select a primitive and press **Backspace** to delete. Undo with Ctrl+Z. Press **Shift+Backspace** while aiming at a relationship, ensure it removes the relationship, not geometry.
5. Open the catalog and close it with **Enter**. Open a numeric size dialog, enter a number, press **Enter**, confirm size is applied rather than discarded. Check the paint HEX and assembly naming dialogs similarly. Escape is not required anywhere in OpenWorks.

## Bank save and reuse (internal mechanical relationships)
1. Construct a 3–8-member component with a genuine shaft fitted into two aligned openings, one bearing, a rigid gear/shaft weld, a painted plate, and a custom component alignment pivot. Group it with **C** in Build.
2. With the **whole component** selected, press **Shift+B**, give it a unique name, and press Enter. Expect a definite saved confirmation. Attempt the same name again: expect a duplicate-name error without corrupting the previous save.
3. Press **B** and select your saved item. Confirm one cohesive ghost follows the cursor and its chosen pivot works for dragging/rotation. Position it away from the original and click.
4. Confirm all member dimensions, material/paint, fitted geometries, pivot, bearings, internal welds and tuning are preserved. The copy must have fresh primitive IDs, a new ComponentId, and new relationship IDs. No relationship may point to an original member.
5. Inspect the copy in Simulate after registering it as an assembly. Verify the bearing rotates, the gear stays welded to its shaft and motor/key settings work when authored. Test an internally connected two-pulley belt, if present.
6. Place a second bank copy elsewhere. Edit or delete the first copy; the original and second copy must not change. Use **Ctrl+Z** to undo the second placement and **Ctrl+Y** to redo; all internal joints must return.
7. Delete one entire bank-placed component with **Backspace**, then undo. Both geometry and its relationships must be restored, without orphaned constraints.
8. Put one spring or weld from a component member to an **external** constructed part. Save that component. The confirmation should report that the external relation was omitted. Bank instances must NOT connect to that outside part.
9. Attempt a bank placement that intersects an existing solid or outside your plot. It should show invalid preview and the server must reject it, leaving no partial parts, relation folders or history actions.
10. Exit Studio and rejoin. The bank entries must remain, independent of plot autosaves. Remove a bank item using its two-step × confirmation, rejoin, ensure it is gone; existing placed instances must remain.
11. Check Output and DataStore diagnostics for failed calls, incomplete loads, invalid source contracts, or stale aliases.

## Deliberate limits

- Saved blueprints are based on **prebaked primitive templates and authored relative transforms**, not arbitrary runtime EditableMesh/CSG blob serialization.
- Bank content is private per player, max **16 blueprints**, max **64 primitives per blueprint**, max **500 KB** of encoded bank data.
- Only **wholly internal authored mechanical relationships** copy. Automatic gear engagement remains geometry-driven.
- Every bank placement is a new editor component, **not** a pre-registered simulation assembly; explicitly assign it to an assembly before simulation.
- Network, runtime Luau, DataStore access, world collision, visual placement, undo and simulation behavior need actual Studio verification.
