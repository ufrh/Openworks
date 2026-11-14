# OpenWorks permanent gear and bolt meshes

## Why mesh geometry disappeared

The older generator called `CreateDataModelContentAsync(Content.fromObject(editableMesh))` and then `CreateMeshPartAsync`. This makes a **static MeshPart with temporary DataModel-scoped Content**, not a published Roblox Mesh asset. The mesh may disappear after closing Studio. Saving the prefab Model alone does not publish its geometry.

`AssetService:CreateAssetAsync(editableMesh, Enum.AssetType.Mesh, ...)` can publish permanent Mesh assets **only from a locally installed Roblox Studio plugin** (or supported creator tooling environments). The required **CreateAssetAsync Luau API Studio beta** must also be enabled. Ordinary runtime Scripts cannot perform that step. See [Roblox AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService) and [Studio plugins](https://create.roblox.com/docs/studio/plugins).

## Publish once (requires your Roblox Studio login)

1. **Sync latest `dev` into Roblox Studio**. Verify `ReplicatedStorage.Openworks.Construction.ProceduralPrefabLibrary` exists and is the new source. Open your actual OpenWorks place in **Edit mode** and enable Mesh / Image APIs if Studio requires it.
2. **Enable File → Beta Features → CreateAssetAsync Luau API. Save and completely restart Studio.** This is a separate opt-in from Mesh / Image APIs, and Roblox throws `CreateAssetAsync and CreateAssetVersionAsync are not available yet` if it is disabled. Automatic beta enrollment does not necessarily enable it.
3. Create a `Script` in `ServerStorage` named `OpenworksPermanentMeshPublisher`. Paste `scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua` into the Script. Alternatively, import `OpenworksPermanentMeshPublisher.rbxmx` into Studio and select its Script. Do **not** paste the publisher into the Command Bar.
4. With the Script selected, choose **Plugins → Save as Local Plugin**, then delete the unused original Script from `ServerStorage`. The installed plugin gets the special capability necessary to publish Mesh assets.
5. From the **Plugins** tab, use **OpenWorks Meshes → Publish Missing**. The Output pane prints uploads, asset IDs, and failures. This requires suitable creator permissions. For a group-owned place, the plugin tries to publish to the group; your Studio account needs the required group asset permissions.
6. The plugin publishes **nine** unique base meshes: 8T/12T/20T/32T × spur/90° bevel, plus one threaded bolt. It automatically derives **40 gear prefabs + 5 bolt prefabs** by sizing those permanent bases. Visuals and fitting metadata remain unchanged.
7. Inspect the created `ReplicatedStorage.OPENWORKS_PublishedMeshAssets` Folder. It should contain nine `StringValue`s with positive mesh asset IDs and the attribute `Ready=true`. The plugin attempts to replace prefabs in `OPENWORKS_PrimitiveLibrary_DRAFT` and refresh the gallery. **Save/Publish the Roblox place** after publication; this saves the manifest and permanent prefab references.
8. Close and reopen Studio and play OpenWorks. Confirm the gear and bolt geometry remains. The runtime now uses `CreateMeshPartAsync(Content.fromAssetId(id))` for the nine published bases: no runtime EditableMesh allocation required.

### Updating the geometry later

**Gear geometry revision 5 (cardinal tooth-gap alignment, spur and 90° bevel)**

1. Sync the latest `dev`. **Reinstall the updated local plugin** from `scripts/studio/OpenworksPermanentMeshPublisher.rbxmx` or the matching `.plugin.lua` source (Plugins → Save as Local Plugin). An older installed plugin may still mark your gear assets as version 4.
2. In Edit mode choose **OpenWorks Meshes → Update Mesh Versions**, **not** Publish Missing. Eight gear bases (8T, 12T, 20T, 32T, spur and bevel) are uploaded with `CreateAssetVersionAsync()` **using the same permanent mesh asset IDs**. The existing bolt asset is skipped; no saved constructions or DataStores are cleared.
3. Confirm `ReplicatedStorage.OPENWORKS_PublishedMeshAssets.GearGeometryVersion == 5` and the eight gear StringValues have `ProfileVersion == 5`. **Save/Publish the Roblox place**, then restart Studio if the mesh cache still shows old teeth. Roblox asset processing/moderation can delay visible updates.

The regenerated involute profile has a **half-tooth angular offset**; local +Y, -Y, +Z, and -Z (the four lines through a gear face) lie in *gaps* rather than tooth tips. Every tooth remains intact, so the gear ratio, shaft bore, physics, and continuous meshing work as before.

**Publish Missing** continues to resume first-time publication; when an existing version-4 gear manifest needs this geometry change, the updated plugin instructs you to choose **Update Mesh Versions** instead. Per-gear `ProfileVersion` metadata keeps phase alignment correct if an upload is interrupted partway. If an upload is still processing, retry **Update Mesh Versions**; never delete the mesh manifest or clear plot saves.

### Notes and limitations

- **The plugin cannot upload assets on its own without you running it in Studio and authorizing it through your Roblox account.** Source changes on GitHub do not upload asset bytes or magically publish mesh IDs.
- Keep the published manifest **outside** the generated draft library, because the runtime replaces generated prefab Models. Its `StringValue` entries must be saved in the `.rbxl/.rbxlx` place or the published experience. Don't delete that Folder, or OpenWorks returns to temporary preview generation.
- The `PublishedMeshAssetId` attribute in generated Models is informational; the nine manifest IDs are authoritative. `StaticDataModelMesh=false` marks published geometry. Gear tooth counts, shaft bores, metadata, separate collision rims, and automatic bolt selection are unchanged.
- Published Mesh assets may be moderated or inaccessible if owned by a creator not authorized to use them. If `CreateMeshPartAsync` fails, the runtime now reports the exact key and asset ID rather than silently returning a blank gear.
- This fixes **geometry persistence**, not motor, gear engagement, or physics torque failures. A separate live transmission test is still required.
