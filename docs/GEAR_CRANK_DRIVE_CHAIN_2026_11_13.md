# Crank → shaft → gear → output transmission repair

## Reproduced failure pattern

In the November 13 recording, the hand-crank arm sweeps a large angle while the
gears barely change their tooth orientation. This strongly suggests a disconnected
crank/shaft or shaft/gear rigid link, *before* the teeth-to-teeth torque link.
Source inspection confirmed that OpenWorks requires authored HandCrank→shaft Weld
but could previously have visually adjacent crank and shaft with no connection.
A completely independent part is not powered merely because meshes overlap.

## Changes

- On simulation compile, **one** shaft end that is physically coincident with
  the hand-crank output can be given a temporary Weld even when older placement
  didn't author a relation. Multi-match cases remain rejected and surfaced in
  Output. Nothing is written to DataStores or permanent relationships.
- Gear hub fit repair continues to be constrained by the actual through-bore,
  axial overlap, eccentricity and shaft diameter, while allowing small snug
  differences. Never infer a weld from visual tooth contact.
- A gear on the crank's *actual spindle* can be driven directly by the crank
  through a gear/crank Weld; an independent shaft is not mandatory there.
- A crank in a registered gearbox **does not start** if its driven shaft is
  disconnected from all gears, or if two registered gears form zero valid
  transmission contacts. Error text includes the actual geometry rejection.
- The native torque solver is still bidirectional. It now logs stalls with
  measured speeds, torque effort, grounding and shaft-mount state.
- The published Roblox mesh asset IDs and all cloud saves remain unchanged.

## Studio acceptance

1. Sync latest dev. Put two gears of **matching module** (e.g. both
   `GearMesh_20T_S03`) on shaft bodies with proper Hub welds; mount a HandCrank
   to the input shaft and register crank, shafts, gears, bearings/housings in
   the same assembly. Ground housings, not gears or shafts.
2. In Simulate, hold the crank. The output shaft should turn in the opposite
   direction, and the RPM ratio should be the inverse tooth ratio.
3. Deliberately detach the input gear. The crank must **refuse** to claim a
   working gearbox and say there is no gear on its shaft.
4. Deliberately move the output gear outside valid pitch spacing or use
   different `Sxx` module variants. It must explain why meshing is invalid,
   rather than quietly spinning only the input.
5. Try the reverse drive, a second ratio, and 90° bevel input/output.

All automated tests validate source code structure, geometry contracts, and
Luau parseability. Only a live Roblox Studio test can validate physical torque.
