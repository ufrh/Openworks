# Unified gear/shaft mounting and drivetrain

## Design invariant (12 November 2026)

A gear is a wheel rigidly fixed to its shaft. Its hub never provides its own free-spinning bearing. There are no independent/dependent gear modes.

- Moving a shaft into a gear **or** a gear onto a shaft produces a validated `Weld` relationship and a real `WeldConstraint`. Neither mount operation grounds or anchors the parts.
- One shaft may pass through **several** correctly aligned gear hubs. Each engaged hub receives its own weld. A single drag/fit is one atomic undo/redo action.
- Each bore must pass the existing circular clearance, coaxiality, overlap, and server collision checks. A gear outside the shaft's axial span is not mounted.
- Gear-to-gear contact is **never** a weld. Tooth geometry discovers spur/bevel contact and establishes angular speed ratios.
- Motion follows the rigid **shaft + gear** body. The target output shaft rotates only when its existing relationships permit it; grounded output shafts, slider-locked shafts, or exceeded bearing angle limits stall the connected train.

## Implemented in this branch

- Removed the Rotation/Rigid hub popup; hubs now directly create `Weld`.
- Normalized older saved gear/shaft `Bearing` mounts to `Weld` on restoration.
- Added server-side multi-hub discovery for shafts crossing several aligned gears, with individual verified welds and one undo transaction.
- Updated `GearKinematics` to require a welded shaft in each rotating gear group, reject slider-blocked shafts, and honor authored bearing angular limits.

## Remaining simulation architecture change — REQUIRED before declaring this complete

**Do not misrepresent the existing scripted gearbox as native physics.** `SimulationService.lua` currently anchors kinematic gear groups, disables collision/native joints for them, and `GearKinematics.lua` rotates the groups by `Model:PivotTo()`. That pre-existing behavior is not the requested final drivetrain.

Replace that old arrangement as one cohesive change:

1. In simulation, create internal prefab welds, preserve the **authored gear-to-shaft WeldConstraints**, and keep the resulting rotating bodies unanchored unless explicitly grounded by the player.
2. Rebuild native bearing/cylindrical/slider relationships against those **welded shaft bodies**. A bearing housing constrains the shaft axis; a slider blocks its relative rotation.
3. Automatic tooth contact should calculate the speed ratio and apply bounded drive torque/velocity to the **output shaft** through its physical assembly, instead of teleporting independent gear models or applying torque to an isolated gear pivot. Respect angular limits and motion locks across the whole connected train.
4. Keep the power direction reversible and support one-to-many connections, equal-axis compound gears, bevel gear axes, hand cranks, powered motors, and rack-and-pinion backdrive. Avoid introducing conflicting native and scripted drives on the same shaft.
5. Simulate physical settling, grounding, collisions, and bearing support without anchoring a body merely because it contains a gear. Preserve the deterministic auto-mesh detection and reject impossible or inconsistent cyclic ratios.

## Regression / acceptance tests (Roblox Studio)

1. Slide one long shaft through **three separate gears** at distinct axial positions. One fit creates three welds, each with a separate gear-to-shaft relation; one Undo removes all three, Redo restores all three.
2. Reverse the operation: drag each gear onto the same stationary shaft at a mouse-chosen position. No Rotation/Rigid modal; no gear jumps to the midpoint.
3. Move a gear outside the shaft's axial length, misalign the center, or choose a diameter exceeding the bore. The operation must reject without partial welds or stale transforms.
4. Save and reload an assembly containing old free-hub gear mounts. Their restored relationships should be rigid; edited/saved plot remains loadable.
5. Mount two differently sized meshed gears on **separate shafts**. Driving the input shaft must turn the output shaft and its gear together at the tooth-count ratio.
6. Place two gears at different axial offsets **on the same shaft**, then mesh each with another shaft. Both gears must stay at the same angular speed while outputs follow their individual ratios.
7. Ground an output shaft, add a Slider in place of a bearing, or set a tight bearing angle limit. The gear train must not clip through or keep rotating past the blocked output.
8. Repeat with reversible drives, multiple simultaneous meshes, bevel pairs at 45° and 90°, racks, motor/key hold/release, assembly stop/restart, and undo/redo/persistence.
9. Verify that in final simulation none of the rotating gear/shaft bodies are anchored, except where an **explicit user ground** makes them immobile.

Do not merge as a fully finished physics rework until acceptance tests 5–9 pass with native mechanical constraints.
