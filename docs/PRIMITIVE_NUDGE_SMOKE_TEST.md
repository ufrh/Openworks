# Primitive Nudge — Roblox Studio acceptance tests

This is an implementation smoke test, **not** a substitute for running Studio. Verify that the unified **Build** tool is equipped throughout.

1. **Standalone primitive:** Place a block, press Enter to return to selection, click that block. Press Alt+Up and Alt+Down. The block alone moves by **0.25 studs** each tap, on world Y. Alt+Left/Right follows the camera-relative horizontal right axis, even as the camera turns.
2. **Fine nudge:** With the same block selected, hold Shift+Alt and press any arrow. Confirm **0.05-stud** steps, not 0.25. Hold an arrow to repeat at a controlled cadence; releasing the arrow or Alt stops movement.
3. **Member inside a grouped component:** Group several primitives using **C**. Click the whole component and verify Alt+arrows move the entire group. Double-click one member to deep-select it, then Alt+arrows: only that member moves, its `ComponentId` stays unchanged, and the others remain stationary.
4. **Multiple independent primitives:** Select several ungrouped blocks using Shift+click. Press Alt+arrow: the entire selection moves in **one transaction** without creating a component. Undo once with Ctrl+Z: all members return to their original positions. Redo once with Ctrl+Y: they all move forward.
5. **Mechanical attachment:** Weld two primitives or fit a shaft/bearing, then try nudging just one endpoint. Its fitted/welded relationship must be detached if the relative movement is physically incompatible, and **Ctrl+Z** must restore both geometry and the removed relationship. Nudge both endpoints together by the same offset and confirm compatible internal relationships are preserved.
6. **Validation and rollback:** Nudge toward another solid until the next step would penetrate it. Confirm the server rejects that step, the source stays at its prior pose and no partial movement or extra undo entry is recorded. Repeat near the plot boundary.
7. **Input conflicts:** Open the primitive catalog, Component Bank name field, paint picker, numerical size panel, pivot editing, or a mechanical fitting workflow. Alt+arrows must not move construction while those controls are active. Other tools—Assembly, Simulate, Inspect, Weld and Belt—must not trigger Build nudges.
8. **Persistence:** Save, leave, and rejoin. The nudged positions and any preserved/disconnected authored joints must reload correctly.

Actual Lua compilation, on-device input priority, physical constraints, and network latency still require Studio testing.
