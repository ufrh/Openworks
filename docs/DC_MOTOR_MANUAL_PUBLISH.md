# OpenWorks DC motor V4: manual publication without a plugin

This path does **not** use a Studio plugin. It publishes the same approved V4
EditableMesh geometry as six ordinary Roblox Mesh assets using Studio's Export
Selection / Importer UI. The native cylindrical shaft and two terminals remain
regular Parts and need **no mesh upload**.

## 1. Prepare the six meshes

Sync the latest `dev` source into Studio, then in **Edit mode**:

1. Run the contents of `scripts/studio/PreviewDCMotor.command.lua` in Command Bar.
   It creates `Workspace.OW_Motor_EditableMesh_Prototype`.
2. Run `scripts/studio/StageManualDCMotorExports.command.lua` in Command Bar.
   It creates `Workspace.OW_Motor_ManualExports` with six ready-to-export
   MeshParts at identity (zero) transform. This avoids encoding the preview's
   position or section offsets in the uploaded OBJ vertices.
3. In Explorer select **one** `*_EXPORT_OBJ` MeshPart at a time, right-click,
   choose **Save / Export > Export Selection** (wording may vary), and save as
   a distinct `.obj`. Repeat for all six:
   `RearCan`, `Armature`, `Housing`, `Endbell`, `Bearing`, `Bushing`.
   If glTF export is enabled, it can be used instead, but do not merge sections.

## 2. Import and upload through Studio

Open **File > Import** (3D Importer) and import all six files.
- Choose the OpenWorks experience's owner/creator (group if group-owned).
- Set **Upload to Roblox: ON**.
- Set **Import Only As Model: OFF** to upload individual mesh assets.
- Set **Scale Unit: Studs** and preserve original orientation.
- Keep **Merge Meshes: OFF** and **Add to Workspace: ON**.
- Verify the meshes are not unexpectedly scaled or reoriented.
- Copy the **MESH asset ID** for each part, not the parent Model asset ID.
  In the Importer, right-click an imported mesh entry to copy its asset ID,
  or inspect the imported MeshPart's MeshId after import.

If an exported temporary mesh does not survive export/import in your Studio
version, use the optional V4 local publisher plugin; the no-plugin path depends
on Studio accepting exported temporary MeshPart geometry.

## 3. Register the six asset IDs in OpenWorks

Open `scripts/studio/RegisterManualDCMotorMeshes.command.lua`.
Replace its six zero placeholders with your uploaded ID numbers. Paste the
whole script into Command Bar in **Edit mode**. It:

- checks all IDs load with `CreateMeshPartAsync` before modifying the manifest,
- writes `ReplicatedStorage.OPENWORKS_PublishedMotorMeshes` and sets
  `GeometryVersion=4`, `Ready=true`,
- updates `OPENWORKS_PrimitiveLibrary_DRAFT/Actuators/DCMotor`,
- rolls back the old manifest if primitive generation fails.

**Save and publish the Roblox PLACE**, not just the model. Keep the manifest
folder in the place. The server reads published mesh IDs each session; it does
not create an EditableMesh in Play.

## 4. Regression checks

- Close/reopen Studio and play. Build > Actuators > Brushed DC Motor must show
  all six detailed mesh sections (no hollow back).
- Try placement, selection, move, duplicate, assembly, simulate, stop, save,
  reload, and painting the motor body (factory colors remain intentional).
- Test collision from the outer body and shaft. Detailed visuals are
  noncollidable. The body cylinder is a simple conservative collision proxy.
- The output shaft is an ordinary cylindrical Part physically joined to the
  prefab body in simulation. This is **not** a mechanically powered output
  shaft yet. Existing bearing-motor relationships still control actual input.
- If the motor looks disassembled after manual upload, the Importer may have
  changed mesh coordinate origins, scales, or axes. Verify the six export
  sections were staged with zero CFrame and imported with Studs/no axis
  rotation before registering the asset IDs.

The existing plugin path is optional; Roblox's manual 3D Importer is a
supported way to upload OBJ mesh assets.
