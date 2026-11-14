# OpenWorks shaft-speed gearbox redesign (13 November 2026)

## Why this replaced the old approach

The old `GearTransmission` instantiated native Roblox `Torque` constraints and attempted to speed-match each gear pair by applying opposing forces. A detected mesh could still remain motionless even with a valid crank. The transmission now **commands physical shaft angular velocity** instead.

## Runtime path

1. The authored Assembly produces independent simulated bodies and real rigid Hub WeldConstraints.
2. `GearMath.AutoMeshStatus` detects compatible spur or bevel gear contacts. Every rigidly connected shaft/gear group becomes one graph node.
3. A held crank or powered bearing motor registers its desired shaft speed through `GearTransmission:SetDrive(instanceId, speed, budget, worldAxis)` each Heartbeat.
4. The solver propagates signed tooth ratios across the connected graph. Multiple motors produce a weighted compromise. Without a motor, measured `AssemblyAngularVelocity` initializes a passive backdrivable speed solution.
5. A virtual inertia and load budget limits acceleration. Each nondriven shaft receives a native `AngularVelocity` constraint pointing along its actual shaft axis with the computed target rad/s. The original crank or bearing motor remains the only motor on its own driven shaft.
6. On release, all external speed commands expire; the solver can follow existing physical angular motion. When no mesh or motion remains, actuators disable. Gear geometry and collision proxies remain static prefabs; **no CFrame animation** is performed.

## Important limits

- The gear model is **an angular-speed constraint**, not tooth-by-tooth collision. Roblox `AngularVelocity.MaxTorque` is an actuator force bound; no native `Torque` object is created.
- Virtual torque estimates are internal acceleration and diagnostic values, not physically conserved motor torque. Complex competing motors, high load and mechanical losses will need calibration.
- A shaft welded to a grounded physics island cannot spin regardless of its target speed. Ground the stationary bearing housing, not its shaft.
- The source tests validate graph signs, motor wiring, no native Torque instances and Luau syntax; **native physical shaft rotation must still be confirmed in Studio**.

## Acceptance test

Sync the latest `dev`. Create a registered assembly with a supported input and output shaft, two 20T S03 spur gears five studs apart, each gear rigidly mounted, passive bearings anchored through the housings, and one crank welded to the input shaft. Enter simulation, hold LMB for at least three seconds, and confirm the input shaft and gear rotate at about +2 rad/s while the output rotates at about -2 rad/s. Then reverse the driver, test a compound shared shaft, release the crank and test a second input.

The standalone `scripts/studio/TestGearTorqueTransfer.luau` fixture calls `ClearDrives` and `SetDrive` on the actual solver, checks published mesh geometry and measures native `AssemblyAngularVelocity`; it must be run from **Server Command Bar during Play Solo**.

Permanent published MeshPart asset IDs, authored assembly membership, saves and prefab fitting metadata are unchanged.
