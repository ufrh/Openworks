# Precision prefab mechanical integration — Studio acceptance

`GearMesh_XXT_SXX`, `Bevel90Mesh_XXT_SXX`, and `BoltMesh_XXXU` are immutable template IDs.
The 45-piece gallery is **not** production validation. The server generates
transient static MeshParts each session; no persistent MeshId is assumed.

## Mechanical collision

* Gear and bolt MeshParts are visual-only and non-queryable (box collision
  would fill a gear bore). Twelve slim tangent box proxies provide each gear
  with an annular physical rim. Gear/gear collisions are disabled only in the
  simulation transmission group; collision with non-gears remains active.
* Bolts use the shank-centered `Geometry` Cylinder as physical collision and
  a separate head cylinder. The authored bolt remains one simulation body.
* Construction, simulation and rack simulation honor the same collision policy.
* This is **coarse collision**, not per-tooth contact or a physically threaded
  bolt. Gear transmission torque is shaft-centric and mathematical.

## Checklist (Roblox Studio Play Solo, then multiplayer)

1. Sync `dev`; turn on Mesh / Image APIs. Start an empty plot. Confirm 45 new
   templates in `ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT`, plus old
   template IDs for save compatibility.
2. Build two new spur gears of **matching size/module** (e.g. both S03),
   mount one on each shaft using Edit; shafts must pass through real holes.
   Confirm a rigid Weld relationship for each shaft/gear mount, no Bearing
   mounted between gear and shaft, and a freely rotating shaft bearing.
3. Register *all* gears, shafts and housings in one Assembly. Drive one shaft.
   Verify the output shaft rotates opposite at the expected ratio and driving
   the output backdrives the input. Add a second gear on a shared shaft and
   repeat for compound speed ratios.
4. Mount a matching pair of 90-degree bevel gears on perpendicular shafts at
   a shared cone apex. Verify SmartPlacement preview, manual GearMesh action,
   torque transmission, and live reverse direction. Ensure parallel-only
   validation does not reject a correct bevel mesh.
5. Drag a small bolt through a drilled hole, then through two aligned holes.
   Verify rigid welds from the physical bolt to each target, and that the
   visible hex head remains outside the first face. Repeat with Build > Bolt
   on two drilled bodies: automatic selection should prefer the new
   `BoltMesh_*` catalog and reject oversize/too-short bolts.
6. Confirm invalid gear module/tooth geometry and wrong shaft diameters are
   rejected with useful errors. Verify camera selection through gear bores
   hits the shaft, not an invisible full-box collision hull.
7. Simulate, stop, save, rejoin, and load. Confirm fitting relationships and
   physical bolts survive and their generated templates are available before
   plot restoration. Also load an old plot referencing `Bolt_050U`.
8. If Mesh APIs are unavailable, verify the game keeps old native gears and
   bolts usable, reports the generation error, and never overwrites a good save.

**Not yet proven without a Roblox Studio runtime playtest:** collision under
high load; high-speed gear synchronization; geometry passing through many
aligned holes; assembly network ownership under multiplayer contention.
