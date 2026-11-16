# OpenWorks brushed DC motor primitive

The `DCMotor` template is registered automatically in
`ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT.Actuators`
when `ConstructionService.Start()` runs. The template ID is permanent and
does not depend on the uploaded asset IDs. Catalog name: **Brushed DC Motor**.

## Authoring and appearance

- Three **closed, full-thickness** metal EditableMeshes, each a separate static
  material section: `RearCan`, `Housing`, and `Endbell`.
- 24-sided smooth circular surfaces; hard, independent face-corner normals on
  stamped front/back faces, ventilation cut edges, and housing seams.
- Three actual cut-through windows in the rear steel can and four actual
  curved openings in the stamped front face, with inner walls and end caps.
- Recessed outer housing, raised bearing collar with through bore, native
  solid plain cylindrical output shaft, and solid rear electrical terminals.
- Conservative per-section triangle budget (<2,500), no DoubleSided fallback.
- Simple native cylinder collision and query proxies. Detailed MeshParts never
  participate in collision or ray selection. Output shaft remains a solid Part.
- Runtime uses permanent, published mesh asset IDs. **No live EditableMesh
  generation or CSG during gameplay**.

## Preview in Studio

1. Sync `dev` into Roblox Studio.
2. In Studio **Edit mode**, paste `scripts/studio/PreviewDCMotor.command.lua`
   into Command Bar. It installs a *temporary* detailed motor in the Actuators
   primitive library and shows one in `Workspace.OW_Motor_EditableMesh_Prototype`.
3. Inspect from the front, sides, and rear. `DoubleSided` is false on every
   MeshPart. All visible rear and front shell edges are backed by real walls.

The preview's DataModel mesh Content may not survive a Studio restart.
Do not ship it as a permanent primitive.

## Publish once for use in a live game

1. Enable Roblox Studio's **CreateAssetAsync Luau API** beta and restart Studio.
   Enable Mesh / Image APIs under Experience Settings > Security if required.
2. Install `scripts/studio/OpenworksMotorMeshPublisher.plugin.lua` as a
   **local Studio plugin** (save a Script as a local plugin in Studio).
   A Command Bar Script cannot publish these mesh assets.
3. Use **Plugins > OpenWorks Meshes > Publish DC Motor**. The plugin uploads
   each of the three mesh sections once, verifies asset loading, stores the
   permanent IDs in `ReplicatedStorage.OPENWORKS_PublishedMotorMeshes`,
   and refreshes the Actuators primitive.
4. Save/publish the **place**. Reopen Studio and ensure `DCMotor` is marked
   `PublishedMotorVisual=true`.
5. Play-test Build, copy, save/load, selection, and simulation. If the manifest
   is missing or an asset cannot load, OpenWorks uses fully solid native Parts
   as a fallback; those do not contain cut-through vent detail.

The publisher does not publish without your Studio account and asset rights.
The generator uses `CreateAssetAsync`, **not**
`CreateAssetVersionAsync` (mesh version uploads fail on the existing plugin).

## Current scope

This change adds the motor as a **real selectable/saveable primitive** and
the production mesh/physics representation. The motor's shaft has an
`ActuatorOutput` attachment and `ActuatorOutputAxis=X`; its appearance does
**not** yet automatically create or power a shaft/gear relationship. The
existing motorized-bearing system continues to own powered rotation.
