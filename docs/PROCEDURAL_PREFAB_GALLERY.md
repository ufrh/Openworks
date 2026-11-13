# OpenWorks — precision gear and bolt prefab gallery

## What ships

The `dev` source includes `src/shared/Construction/ProceduralPrefabLibrary.lua`, a
Studio/production generator for **45 catalog-ready prefabs**:

- 8T, 12T, 20T and 32T involute spur gears, five sizes each (**20**).
- Corresponding 90° *straight-tooth conical approximations* of bevel gears,
  using a shared 45° pitch cone and five sizes per count (**20**).
- Five hex-head bolts with one continuous body, chamfer, threaded relief and
  shaft reference pivot (**5**).

Five gear scales: `0.6`, `0.8`, `1.0`, `1.2`, `1.4`. Bolt
diameters are `0.5`, `0.75`, `1.0`, `1.25`, `1.5` U, with respective
lengths `4`, `6`, `8`, `10`, `12` U. Geometric spur module is
`0.25 * scale` studs; `GearModuleStuds` stores **circular pitch**
`pi * 0.25 * scale`, not the CAD module. Both gear kinds share circular pitch.
Gears should mesh **within matching scale indexes**. Equal tooth counts are
required for the 90° bevel solver; scale indexes must match.

The generated instances are registered at:

```
ReplicatedStorage
└─ OPENWORKS_PrimitiveLibrary_DRAFT
   ├─ Transmission
   │  ├─ GearMesh_08T_S01 .. S05   (and 12T, 20T, 32T)
   │  └─ Bevel90Mesh_08T_S01 .. S05 (and 12T, 20T, 32T)
   └─ Fasteners
      └─ BoltMesh_050U, _075U, _100U, _125U, _150U
```

All are ordinary cloneable Models with `PrimaryPart`, `ResizeMode=None`,
mechanical attributes for fitting, and a normal Build catalog entry. Other
previous prefabs and old saved `TemplateId`s are retained untouched.

## Roblox session-content requirement

`AssetService:CreateDataModelContentAsync` produces **session-scoped** static
mesh content; it is **not a permanent uploaded mesh asset**. We do not claim
that Command Bar models persisted as permanent assets. The game server runs
`Prefabs.Ensure()` after the original stock is provisioned and before the
Build registry is used. Thus every published server reconstructs the same
static geometry and exposes it through the same IDs each session; individual
placed prefab instances clone the static mesh and do not consume a separate
EditableMesh budget. This requires the experience's **Mesh / Image APIs** to
be enabled. Generator errors are logged, and existing legacy prefabs still
work. For a pipeline with no runtime mesh creation or with experiences that
cannot enable these APIs, publish the generated meshes as Roblox mesh assets
and replace the generation path with those persistent asset IDs.

Each visual gear is **one mesh**, with a real empty center bore and
visual-only collision until a compatible nonblocking collider is implemented. The bolt is one mesh plus
an invisible noncollidable shaft-center pivot used by BoltMath. There are
no tooth-box stacks, visual cylinder caps over the bores, or automatic welds.
Gear-to-gear motion still uses the existing shaft-centric transmission math.

## Studio gallery

1. Sync GitHub `dev` into Studio using your normal Rojo integration.
2. Open **View → Command Bar** while **not playing**.
3. Paste `scripts/studio/GeneratePrecisionPrefabs.luau` and execute once.
4. Inspect `Workspace.OPENWORKS_ProceduralPrefabGallery` (nine rows by five
   columns) and the catalog folders in ReplicatedStorage.
5. To recheck the display, run `require(game.ReplicatedStorage.Openworks.Construction.ProceduralPrefabLibrary).BuildGallery(true)`.

The gallery is placed at Z = -205, well outside the user plot. It is for
Studio inspection, not player construction. The prefabs are independently
registered in replicated storage by the server when the game starts.

## Runtime validation still needed

- Confirm the Mesh / Image APIs are enabled for the experience.
- Run generator in Studio to inspect bevel tooth taper, bore continuity,
  procedural thread visibility, and the 45-instance gallery.
- Check normal Build placement, gear mounting on a real shaft,
  matched-index spur / bevel mesh, and bolt hole alignment.
- Test physics/collision decomposition around the actual gear bores.
- Rejoin a **fresh** server to verify every prefab is regenerated and old
  plot/template IDs still load correctly.

This is a prefab-generator integration; it does not replace Smart Fit V2.

## Troubleshooting and verified generator command (v2)

In Studio **Edit mode**, sync `dev` and run the entire
`scripts/studio/GeneratePrecisionPrefabs.luau` in the Command Bar. The command
now throws an explicit error if the Rojo module is absent and reports the
precise failing gear/bolt stage. Successful output must include
`Ready=true, Count=45, Gallery=true`.

The generator now uses the **Box mesh creation path** from the successful
five-gear prototype to ensure the mesh visuals are created before any expensive
convex-decomposition step. **Gear meshes are currently visual-only
(`CanCollide=false`)**, so a box cannot block their bore. Shaft-centric
mechanical gear transmission does not depend on tooth-to-tooth collisions.
`OpenworksCollisionReady=false` explicitly records that full physical gear
collision is not yet implemented; this needs a separate Studio physics pass.
Solid bolt meshes retain Box collision as a temporary approximation.
This is an operational generation fix, not a claim that physical gear geometry
has been fully validated.

If `Static mesh bake failed` or `CreateEditableMesh` fails, confirm **Allow
Mesh / Image APIs** in Roblox Studio Experience Settings → Security (and in
published Experience configuration), plus the appropriate account/experience
permissions. Those security limitations cannot be bypassed by this script.

At runtime the gallery is created at `Workspace.OPENWORKS_ProceduralPrefabGallery`
with Z around `-205`, away from construction plots. The player's first-person
camera does **not** automatically move there during Play. Use the Edit-mode
Command Bar to view it, or focus it in Explorer using **F**. All generated mesh
content is session-scoped: it is recreated on each server startup, and does
not become a permanently uploaded Roblox mesh asset when you save the place.
