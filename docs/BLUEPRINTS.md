# OPENWORKS — Physical Blueprint Drafting (M1)

Blueprints are physical sheets, not a full-screen CAD UI or a virtual hotbar. A player puts a sheet on the workbench and uses actual drafting instruments on the surface to create manufacturing geometry. This first milestone implements the paper and manual straightedge interaction. It deliberately does not manufacture metal, transfer layouts, or create circles yet.

## Studio prototype

On Play, the server places a small **OpenworksDraftingKit** on the largest `Workspace.Workbench.surface` if no physical blueprint already exists:

- **Blueprint Sheet**: unanchored BasePart with `isBlueprint = true`.
- **Drafting Ruler**: unanchored, physically movable BasePart with `isTool = true`, `DraftingKind = 'Ruler'`.
- **Drafting Pencil**: unanchored BasePart with `isTool = true`, `DraftingKind = 'Pencil'`.
- **Drafting Eraser**: unanchored BasePart with `isTool = true`, `DraftingKind = 'Eraser'`.

These are simple procedural placeholder models; replace them with custom rigid Models/parts in a later pass. The starter kit is for Studio. Real authored workspaces can place their own marked blueprint sheets and physical instruments.

## Player workflow

1. Leave the tools and blueprint sheet on a workbench; the existing detector sets `OnWorkbench` after they settle.
2. **Short-click the paper**. The free-grab system releases it, the sheet is temporarily secured, and a separate overhead drafting camera opens. No CAD panel appears.
3. **Hold LMB on the ruler and drag** to reposition it across the paper. While holding it, **scroll** to rotate it in 5-degree steps. Release to set it down. The ruler is the real Workspace Part, not a ghost preview.
4. **Click the pencil** to select the physical tool. Move the pointer to within roughly 7 mm of one of the ruler's long edges on the paper.
5. **Hold LMB and drag along the edge**; the pencil follows the projected contact and a dark ink preview tracks the ruler. Release to create a mathematically straight measured line. A tiny stroke is rejected.
6. **Click the eraser**, then click near a saved line to remove that complete line.
7. **Esc** restores the normal camera and the tool's physical resting location; the sheet is released onto the workbench. The ink remains attached to it when moved.

The ruler must rest approximately flat against the sheet and lie on the workbench. It can extend beyond the sheet; the actual drawn endpoints must fit within the paper margins. There are no UI tool selectors, Backpack tools, or CAD menus.

## Geometry model

`src/shared/BlueprintGeometry.lua` is a separate drawing domain from `FORM`. Drawing is layout definition, not machining. A blueprint stores a versioned JSON document on its physical Part:

```lua
{
    version = 1,
    units = 'mm',
    lines = {
        {kind = 'Line', a = {-20, 5}, b = {30, 5}},
    },
}
```

The world scale uses the existing `Stock.SCALE` (0.04 studs/mm). Coordinates are 2D, in the sheet's local X/Z plane, measured from its center. These values are independent of the sheet's world CFrame, so a player can lift, rotate, or move the sheet without changing the drawing. The lines are re-rendered as small, non-colliding `BlueprintInk` Parts welded to the paper; a line is saved only by the server after validating its tool and ruler placement. There is a 128-line cap in M1. Ink is geometric data, not a decal.

`BlueprintEvent` is server-authoritative for tool selection, paper locking, ruler placement, line creation, and erasing. The active client drives the visual drafting pencil responsively; the server validates the pointer and broadcasts its pose to other clients. Physical tools restore their original anchoring/collision state on exit. Only one player can draft on a given sheet at a time.

## Implementation and next milestones

- **M1**: physical paper, pencil, ruler placement and rotation, straight line drawing, erase, ink serialization, world camera, and workbench integration. This is the current implementation.
- **M2**: physical divider/compass drawing circles and arcs; rulers with tick marks; snapping and dimension annotations. Lines should be assigned manufacturing intents (cut, construction, center, bend) using physical methods.
- **M3**: transfer layout to FORM metal via physical tracing/transfer instruments and mapped coordinates, with manufacturability validation. Transfer must not fabricate the part. Closed interior geometry needs the appropriate real operation and geometry backend first.
- **M4**: blueprint copies, physical storage, revision history, assembly plans, and persistent player inventory/library of paper assets. M1 paper attributes survive movement during the current server session, but **do not** persist automatically through separate Play sessions.

## Smoke test

In a fresh Studio Play session with Rojo synchronized:

1. Confirm Output includes `[OPENWORKS:Blueprint] Physical paper, ruler constraint, saved ink and eraser passed` and `Drafting kit placed on the workbench`.
2. Short-click the sheet and confirm overhead camera. Try physically dragging the ruler and scrolling to rotate while holding it.
3. Click Pencil; draw along the ruler and release. Check `BlueprintInk` contains a Part and `OpenworksBlueprint` contains JSON on the sheet.
4. Click Eraser, then a drawn line: it disappears and its JSON entry is removed.
5. Exit with Escape, lift and move the physical paper, and confirm the ink moves with it.
6. Return to the sheet and confirm its previous lines still exist.
7. Confirm saw/file/scorer metalworking sessions still work independently, and drafting tools do not appear in metalwork's tool selector.

The code has been committed to GitHub, but real Roblox Studio gameplay and camera/physics verification still need to be performed.
