# OPENWORKS — shaft-centric gearbox transfer regression (Nov 2026)

This patch targets a silent failure in the **existing** native-physics gearbox, not a rewrite or a switch to tooth-contact physics. It does **not** modify saved plot schema, mesh-generation geometry, gear ratios or the chosen UI V2.

## Changes

- **Grounding:** A simulation started by clicking a gear/shaft no longer grounds that rotating part by default. When the user requested automatic grounding, a *passive bearing/slider housing* (not a welded gear or shaft) is chosen if one is in the registered assembly. Explicit user-grounded parts are still respected. If there is no such housing, the assembly remains free and the status explains that the user should ground the housing.
- **Gear-to-shaft connections:** Existing hub fitting still creates explicit Weld relationships. Newly copied gears, bolts and cranks now also keep their automatic Hub/BoltHole/CrankCoupling mate instead of losing their physical connection. Old saved reverse-direction Bearing/Slider/Cylindrical gear/shaft interfaces are restored as rigid welds if true geometry still fits.
- **Transmission:** Native Torque is explicitly enabled, remains applied to the welded shaft root, and applies bidirectional equal-work corrections. No gear tooth collision or independent rotation animation is used. Gear inspect diagnostics now distinguish an idle drive, an anchored shaft, an unmounted gear, both gears welded to the same rotating body, different tooth pitches, and valid torque contacts.
- **CI:** A separate static transfer contract tests native torque wiring, motor/crank input, welds, grounding, and torque sign. These checks **cannot prove Roblox physics dynamics**.

## Actual physical Studio smoke test

1. Sync `dev`, open **Play Solo** and use the **SERVER** Command Bar.
2. Paste the contents of `scripts/studio/TestGearTorqueTransfer.luau`.
3. The test uses real 20T/S03 gear prefabs if available, otherwise two fallback gear models. It creates two independent shafts in native passive hinges, each rigidly welded to its gear, with 5-stud pitch-center spacing, and applies a native input `AngularVelocity` motor.
4. Over three seconds the test logs both measured `AssemblyAngularVelocity` values, asserts one active mesh, and reports **PASS** only if the driven shaft rotates in the opposite direction. It automatically removes its test fixture.
5. This does not modify user assemblies, assets, saved data, or the game mode. A pass validates this isolated motor/hinge/torque route only, **not** all gameplay placement and multi-gear interactions.

## End-to-end in-game validation

- In Build, place two 20T S03 gears on two shafts through **Hub** fitting; each mount should create a Weld. Give each shaft a passive Bearing relationship with a housing. Ground the stationary housing, never the shafts or gears.
- Register both gears, shafts, housings and motor/crank into **the same named Assembly**, then simulate. Expect `2 gears / 1 automatic contact` and the secondary shaft to rotate opposite to the input.
- Inspect a gear with simulation's GetMechanismInfo to view live shaft angular velocity. `NO SHAFT WELD` means the gear must be hub-fitted; `Not engaged:` indicates wrong pitch, spacing, face overlap or shaft angles; `GROUNDED` signals an immobilized shaft; `idle` means motor/crank isn't powered.
- Test 12T/20T S03 spur gears (opposing rotation and 12/20 speed ratio), two 20T S03 90° bevel gears on perpendicular shafts, gear copied with F and mounted via Hub, and a multi-gear compound assembly with a shared shaft.
- Save, stop, reload, and repeat. Repeat in multiplayer to catch network/ownership behavior.

## Limits

- The rack-containing assembly router still uses its separate rack simulation path. This patch focuses on **native shaft-centric spur and bevel trains**.
- MeshParts remain session-baked, so permanent mesh publishing remains separate from this mechanical fix.
- **Studio runtime pass is still required**; automated checks validate source contracts but do not execute Roblox physics.
