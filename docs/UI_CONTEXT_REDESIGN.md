# OPENWORKS — Context-first UI redesign (November 12, 2026)

**Branch:** `feature/ui-reorganization-v2`  
**Build marker:** `2026.11.12.UI-V2-CONTEXT-CREATOR`  
**Verification:** GitHub Python source contracts and StyLua Luau syntax/AST parser; **not Roblox Studio Play**. This branch is experimental and `dev` is unchanged.

## What changed

### Primitive library and left controls

The existing Build > Place primitive catalog is anchored to the **right edge**, vertically centered, instead of overlaying the two compact left panels. Those left panels remain independent: **Subtools** (their real B/E/V/M, C/E, E/Y shortcuts) and **Controls** (context-dependent hotkeys). The cursor still obeys existing modal ownership.

### No permanent Explorer or Properties

The permanent right-side `UnifiedExplorer` and its visual hierarchy, tree, search, and separate Properties dock are **removed from the active project source**. The new `ContextEditor.lua` draws UI only when requested:

- **Right-click** an authored primitive or grouped component. A floating `RightClickEditor` opens near the pointer with object information and appearance controls. It is not persistently docked anywhere.
- An entire component can have **multiple independent mechanical relationships**: the contextual popup gathers them all from the real authored `SourceId`, `TargetId`, and `SecondTargetId` attributes for every primitive member. No maximum number of relationships is artificially hidden; the list scrolls.
- Click any relation in the list to open its editable properties **within the same floating popup**; use Back to choose another.
- Spring: stiffness, damping and free length. Bearing/slider/cylindrical: limits and limit enable. Bearing: additionally input key, motor enable, speed, torque and acceleration. The relation's other stored metadata is available read-only.
- A single **Confirm** action applies each chosen relationship's supported changes through the same server-validated `TuneSpring`, `AdjustJoint`, and `TuneBearingMotor` actions. A bearing's limits and motor use two existing validated calls where both change; these are **not an atomic transaction**. Errors report possible partial completion rather than pretending success.
- Material, finish and HEX color have a separate **CONFIRM APPEARANCE** action. The material and paint remotes are unchanged; the server now permits the same tightly validated property actions with any equipped OPENWORKS native tool, while preserving ownership, plot-loading, and running-simulation rejection.
- Removing a relation requires choosing Remove and then **CONFIRM REMOVE RELATIONSHIP**. It affects only the authored joint, never underlying primitives. New contextual edit/remove permissions are still constrained by server ownership and simulation checks.
- F2 can unlock or reopen the current contextual selection without resurrecting the old dock. The existing `OPENWORKS_ExplorerOpen` player attribute is retained only as an input-focus compatibility flag for the camera, tools and held actuators. It does **not** mean an Explorer GUI is present.

`AuthoredIndex.lua` is a **read-only data index**, not an Explorer UI. `ContextActionRegistry.lua`, `ExplorerData.lua`, and `UnifiedExplorer.lua` were deleted as obsolete standalone UI source.

### Centered assembly creation

With Assembly & Simulation > Assembly Editor equipped, press **N**:

1. A centered `AssemblyCreator` popup asks for the new assembly name.
2. **SELECT PRIMITIVES** dismisses the popup and returns mouse look to the build world.
3. World clicks/Alt-clicks toggle full components or specific primitive members using the existing `AssemblyToolController` membership logic. Draft membership is still local until Confirm.
4. A compact **top-center selection bar** displays the draft name, count and **CONFIRM / CANCEL**; existing Enter and Escape keybinds remain available without unlocking the cursor. F2 temporarily releases the pointer when buttons need clicking.
5. Existing authored assemblies use the same centered naming flow and existing `UpdateAssembly` membership remote. No new assembly schema or implicit welds.

During active simulation a separate compact top-center bar provides Stop/Pause/Reset, with existing P/O/U/I keyboard controls preserved. The current session is still constrained to its saved member IDs.

### Selection visuals are deliberate

- **Allowed:** Explicitly selected primitive (one aqua oriented 12-edge box); explicitly selected full component (one anchor-local box); explicitly chosen assembly draft members (purple per primitive); explicitly chosen two-part connection participants (orange/red); brief acknowledged success flash (green).
- **Removed:** Passive primitive/component hover outlines; automatic smart-fit target boxes; persistent green/blue grounding boxes; simply aiming at a saved assembly creating a purple outline.
- A selection box updates every RenderStepped frame (the old 0.08s box-update throttle is gone). During Resize, it binds to the **actual live resize ghost**, not the old object size. The resize ghost geometry and wireframe redraw every render frame, and normal selection is restored when Resize ends. No server resizing calls are sent per frame; original commit/undo semantics remain.
- An empty right-click deselects the context. Destroyed objects remove stale visual ownership. Tool changes clear contextual selection; no residual hover or ground boxes should remain.

## Architecture and compatibility

- **New**: `src/client/Controllers/ContextEditor.lua`, `AuthoredIndex.lua`.
- **Removed**: `UnifiedExplorer.lua`, `ExplorerData.lua`, `ContextActionRegistry.lua`.
- **Updated**: Construction catalog/selection/resize, mechanical assembly selection and feedback, WorldVisuals grounding overlay, GhostWireframe, client bootstrap, ConstructionService's narrow contextual property-tool permissions, Python source checks, docs.
- Existing mechanical geometry and physics validators, assembly persistence, DataStore formats, simulation solver, and saved model identifiers are **not changed** by this redesign. The direct mechanical property update authorization now accepts any one of the three equipped native OPENWORKS tools; it still does **not** allow authoring while simulating.

## Required Roblox Studio acceptance — NOT RUN

1. **First run:** Sync the feature branch, restart Play, confirm `UI-V2-CONTEXT-CREATOR` and that no `OPENWORKS_UnifiedExplorerProperties` screen exists. Right-click context only; exactly one `OPENWORKS_ContextEditor` GUI.
2. **Left/right coexistence:** Build Place opens the PrimitiveCatalog on the right, not over the Subtools or Controls left panels. Test 720p, 1080p and 1440p windows and close/open repeatedly. Verify F6 plot UI does not conflict with the assembly popup or connection chooser.
3. **Relation discovery:** Create a component of multiple primitives with at least three separate relations—e.g. a bearing, slider and spring. Right-click *any* component member; confirm **all** relations appear without fake component-weld edges. Select different relations and Back within the **same popup**.
4. **Property editing:** For each relation, edit limits, spring values and powered-bearing motor keys/speed/torque/acceleration. Confirm accepted values persist through reload; server rejects invalid values and cannot edit during simulation. Verify no accidental partial motor/limit success is falsely reported.
5. **Appearance:** Right-click a primitive and full component, change physical material and a matte/chrome/etc finish and HEX swatch. Confirm and reload saved plot. Change property while Mechanics or Assembly tool is equipped; ensure server still checks ownership and active simulation.
6. **Assembly wizard:** Press N from Assembly Editor, type a valid/invalid name, click SELECT PRIMITIVES, select members via normal click/Alt-click, Confirm/Cancel via top-center toolbar or Enter/Escape. No permanent side panel or auto-save of unconfirmed membership. Switch tools and back; check draft persists.
7. **Selection-only:** Move crosshair over dozens of primitives with nothing selected: **no boxes**. Aim at a saved assembly: **no hover box**. Select one primitive: **one exact aqua box**. Select a whole rotated component: **one exact oriented box**. Select two separate primitives: independent boxes only. No persistent grounding outlines.
8. **Resize:** Select one primitive, enter Resize and drag each applicable face. The selection box and 0.65-transparent resize ghost must follow the current dimensions **every rendered frame**, without trailing on the previous size, and return cleanly to the authored selected object when resizing finishes/cancels.
9. **Fitting:** A connection's first/second selections still show pending orange/red and brief server-accepted green. A passive snap candidate without explicit selection should **not** draw a box; shape ghosts/clearance validation remain accurate.
10. **Input and cleanup:** Test right-click while a modal is open, select then delete, cancel, undo/redo, tool switches, respawn, F2, F6, held crank/motor/rack, and plot reload. No stale context popup, visual layers, leaked UI focus or default world clicks behind the popup.
11. **Regression:** Replay Phase 0 saved fixtures FIX-01 through FIX-06 on a disposable plot. Verify all mechanical simulation types and multiplayer ownership. Confirm no changes to `dev`.

**Important:** GitHub parsing/source assertions do not exercise actual mouse, camera, GUI controls, CSG, native Roblox constraints or DataStore behavior. Do not merge solely on CI success.
