# OPENWORKS — Unified Edit, Simulate and Numeric Dimensions

Build: `2026.11.10.PHASE08.UNIFIED-TOOLS-PRECISION`. Branch `dev`.

## A. Native tools and permissions
1. Start Play on fresh character. Hotbar is **Build / Edit / Simulate /
   Inspect**, in that order. Assemble is absent from Backpack and
   StarterPack, even when re-running a place with an old saved Tool.
2. Equip Edit. K enters manual Gear Mesh; click first/second gear; result
   is a Gear relationship and should be undoable through Ctrl+Z.
3. Equip Edit. J configures bearing/slider/cylindrical limits; U and [ ]
   adjust them. H opens the older manual housing->shaft relationship wizard
   only as a fallback. Esc exits each mode.
4. With Edit equipped, Shift+Delete removes the aimed *relationship*
   without deleting the primitive; normal Delete still deletes geometry.
5. Equip Simulate. Click a housing or press G while aimed at it; the body
   gains or loses a persistent Grounded flag. P starts simulation; M
   toggles motors; N reverses; [ ] change speed; O pauses; U resets;
   I inspects. P stops. Shift+P starts completely ungrounded.
6. Attempt Place or CreateRelation with Simulate equipped via a remote:
   the server must reject editing. Attempt StartSimulation with only Edit
   equipped: the server must reject it.

## B. One-release shaft connection choice
1. Build a drilled block, then bring a cylinder into the opening.
   A blue coaxial snap appears automatically; click ONCE.
2. A choice panel appears with 1 Rigid, 2 Bearing, 3 Slider, 4 Cylindrical.
   Press 2. It must create a bearing relationship, *not* merge the parts.
   Press P in Simulate to verify the shaft spins about the proper axis.
3. Build another cylinder, align to a fresh hole, press 1. The two pieces
   must merge into one rigid editable component.
4. Test 3 and 4, verifying the correct native constraint is authored.
5. Repeat by dragging a pre-existing shaft OR moving the housing itself
   onto a stationary shaft. The choice should appear AFTER release in Edit.
6. Esc should cancel without moving the original, creating the Build part,
   modifying group membership, or introducing a history entry.
7. While the panel is open, 1–4 must select relationship types, not equip
   other tools. Buttons must also work. After selection, the hotbar works
   normally again. Switching tools mid-prompt should cancel safely.
8. Ctrl+Z should undo the selected mechanical relationship and any atomic
   associated placement, then Ctrl+Y restore it.

## C. Exact numeric size in U
1. In Build select Block, aim at a valid surface, press N. The numeric
   panel displays current X/Y/Z dimensions in **U**. Enter values such
   as 2.35, 1.75, 0.82. Enter or Apply. Preview geometry should resize
   exactly; place and inspect final measurements.
2. In Edit double-click a member inside a rigid component, press N.
   Enter a new dimension, apply. Check only that primitive changes
   size, membership survives, and Ctrl+Z restores original dimensions.
3. Choose a Cylinder, press N. Enter X=4.52 and Y=1.13; Z should
   automatically match Y. Zero, negative, non-finite, >64-U, and
   three-decimal inputs must be rejected.
4. With a shaft *already fitted inside a drilled block*, press V:
   only the two X-axis length grips should appear. Press N and enter
   exact X length and Y diameter. A diameter that exceeds bore clearance
   should be rejected and should leave prior size intact. A correctly
   fitting precise diameter should be accepted and persist on reselect.
5. After precise size editing, use the ordinary physical sphere handles
   and move the component; the 0.01-U detail must not be rounded away.
6. Verify that fixed-size gear templates and nonresizeable prefabs cannot
   be numerically enlarged; all dimension changes still obey physical
   collisions and server-side range/ownership checks.
7. Try to submit an improperly quantized size directly via remote:
   it must be rejected. The numeric editor and geometry should return to
   stable states on Escape, tool switching and respawn.

## D. Regression
1. Automatic gear-on-shaft and gear-to-gear snap still work without the
   old two-click Assemble tool.
2. Click once selects; second hold-and-drag moves; double-click selects
   primitive inside a component without ungrouping.
3. Shaft insertion depth (wheel) and roll (Q/E) work before the four-key
   choice panel appears.
4. Grounded flags, bearing angles, rigid merges and Undo/Redo are still
   intact when switching between Edit and Simulate.
5. Watch Studio Output for nil calls and invalid Enum/ContextAction errors.

**Requires Studio playtesting**. This document is a manual acceptance plan
for the branch; it does not claim Roblox engine execution.
