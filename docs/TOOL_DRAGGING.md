# OPENWORKS — Physical tool dragging

The `src/server/ToolDragging.server.lua` and `src/client/ToolDragging.client.lua` scripts implement a first-pass LT2-inspired tool grab.

## Setup

- The physical object is a welded, **unanchored** Model or BasePart in Workspace.
- Set the Boolean attribute `isTool = true` on its Model (or a standalone BasePart).
- Parts must have `CanQuery = true` to be clicked. No Roblox Tool or Backpack instance is used.
- No Studio-inserted DragDetector, attachments, constraints or GUI are needed.

## Controls

- Left-click and hold a tool: pick it up.
- Move mouse: carry in 3D, constrained by physical collisions.
- Mouse wheel: move held tool nearer/farther.
- Hold Shift + W/A/S/D: rotate (pitch/yaw).
- Release left-click: drop and return to free physics.

## Implementation and limitations

A server-validated remote temporarily creates an AlignPosition and AlignOrientation on the clicked welded part, tracking an invisible anchored target. The dragged object is given player network ownership during the grab; the temporary constraints and ownership are released on drop. Server verifies an `isTool` marker, reach, anchored state, and exclusive ownership before grabbing, and validates target positions/orientations and timeouts while moving.

The existing Workbench detection still determines availability independently, based on objects settling in the generated surface regions. Dragging itself does not mark a tool as usable.

This is an initial desktop mouse-and-keyboard implementation. Control feel, constraint strength, heavy assembly handling, camera conflicts, and multiplayer replication require Roblox Studio tests. Nothing in this change activates machining, FORM edits, or the old equipped-tool UIs.
