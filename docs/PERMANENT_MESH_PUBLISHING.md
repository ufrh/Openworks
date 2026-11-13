# OpenWorks permanent gear and bolt meshes

## Why mesh geometry disappeared

The older generator called `CreateDataModelContentAsync(Content.fromObject(editableMesh))` and then `CreateMeshPartAsync`. This makes a **static MeshPart with temporary DataModel-scoped Content**, not a published Roblox Mesh asset. The mesh may disappear after closing Studio. Saving the prefab Model alone does not publish its geometry.

`AssetService:CreateAssetAsync(editableMesh, Enum.AssetType.Mesh, ...)` can publish permanent Mesh assets **only from a locally installed Roblox Studio plugin**. Command Bar and ordinary runtime Scripts cannot perform that step. See [Roblox AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService) and [Studio plugins](https://create.roblox.com/docs/studio/plugins).

## Publish once (requires your Roblox Studio login)

1. **Sync latest `dev` into Roblox Studio**. Verify `ReplicatedStorage.Openworks.Construction.ProceduralPrefabLibrary` exists and is the new source. Open your actual OpenWorks place in **Edit mode** and enable Mesh / Image APIs if Studio requires it.
2. Create a `Script` in `ServerStorage` named `OpenworksPermanentMeshPublisher`. Paste `scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua` into the Script. Alternatively, import `OpenworksPermanentMeshPublisher.rbxmx` into Studio and select its Script. Do **not** paste the publisher into the Command Bar.
3. With the Script selected, choose **Plugins → Save as Local Plugin**, then delete the unused original Script from `ServerStorage`. The installed plugin gets the special capability necessary to publish Mesh assets.
4. From the **Plugins** tab, use **OpenWorks Meshes → Publish Missing**. The Output pane prints uploads, asset IDs, and failures. This requires suitable creator permissions. For a group-owned place, the plugin tries to publish to the group; your Studio account needs the required group asset permissions.
5. The plugin publishes **nine** unique base meshes: 8T/12T/20T/32T × spur/90° bevel, plus one threaded bolt. It automatically derives **40 gear prefabs + 5 bolt prefabs** by sizing those permanent bases. Visuals and fitting metadata remain unchanged.
6. Inspect the created `ReplicatedStorage.OPENWORKS_PublishedMeshAssets` Folder. It should contain nine `StringValue`s with positive mesh asset IDs and the attribute `Ready=true`. The plugin attempts to replace prefabs in `OPENWORKS_PrimitiveLibrary_DRAFT` and refresh the gallery. **Save/Publish the Roblox place** after publication; this saves the manifest and permanent prefab references.
7. Close and reopen Studio and play OpenWorks. Confirm the gear and bolt geometry remains. The runtime now uses `CreateMeshPartAsync(Content.fromAssetId(id))` for the nine published bases: no runtime EditableMesh allocation required.

### Updating the geometry later

Use the plugin's **Update Mesh Versions** button. It calls `CreateAssetVersionAsync()` on all nine existing asset IDs so their references don't change. Save/Publish the place afterward. **Publish Missing** skips existing IDs and safely resumes partial first-time publishing. If a mesh is still processing, the plugin retains the saved asset IDs; try Publish Missing again after Roblox finishes processing.

### Notes and limitations

- **The plugin cannot upload assets on its own without you running it in Studio and authorizing it through your Roblox account.** Source changes on GitHub do not upload asset bytes or magically publish mesh IDs.
- Keep the published manifest **outside** the generated draft library, because the runtime replaces generated prefab Models. Its `StringValue` entries must be saved in the `.rbxl/.rbxlx` place or the published experience. Don't delete that Folder, or OpenWorks returns to temporary preview generation.
- The `PublishedMeshAssetId` attribute in generated Models is informational; the nine manifest IDs are authoritative. `StaticDataModelMesh=false` marks published geometry. Gear tooth counts, shaft bores, metadata, separate collision rims, and automatic bolt selection are unchanged.
- Published Mesh assets may be moderated or inaccessible if owned by a creator not authorized to use them. If `CreateMeshPartAsync` fails, the runtime now reports the exact key and asset ID rather than silently returning a blank gear.
- This fixes **geometry persistence**, not motor, gear engagement, or physics torque failures. A separate live transmission test is still required.
