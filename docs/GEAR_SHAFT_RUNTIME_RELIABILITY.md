# OpenWorks — Gearbox reliability / persistent mesh editions

## Fixed in this changeset

- An already-inserted gear and shaft in the **same editor component** can now be welded in place through the Hub operation. Editor grouping is no longer mistaken for a physical joint, and duplicate/contradictory joints are rejected.

- A physically inserted **gear on a shaft** that lost its authored Hub Weld can still participate in shaft-centric transmission inside a registered assembly. The simulation checks true concentric bore clearance via `Smart.HubFits` and makes a temporary Weld when there is exactly one valid shaft. No data/saves are changed, and the existing explicit authored relationship always wins. Two candidate shafts are intentionally **not** welded automatically.
- An already authorized hand-crank-to-shaft Weld is not deactivated merely because old saved dimensions or axial offsets differ from the new crank template. The crank still requires a genuine Weld, a coaxial cylindrical output and user-held input. Motor max effort is raised from 1,400 to 6,500 Roblox units for loaded multiple-gear assemblies; not infinite torque.
- The mesh solver requires both gears to belong to **shaft-mounted** groups. New contacts require full tooth module, axle angle, pitch radius and face-overlap validation. Previously engaged meshes retain small bounded tolerances so passive hinge drift does not drop torque each 100 ms. Includes 45°/90° bevel engagement hysteresis.
- The existing force-based `Torque` solver is preserved; no kinematic CFrame animation or fake tooth contact. Debug inspection shows active contacts, torque effort, angular speed, mounting repair, and whether the crank motor is actually coupled and held.
- The Studio smoke test now **requires the real published 20T S03 gear prefab** instead of silently falling back to rectangular geometry.

## Studio acceptance (not established by GitHub CI)

1. Publish / load the permanent mesh assets, sync `dev`, and confirm `ReplicatedStorage.OPENWORKS_PrimitiveLibrary_DRAFT.Transmission.GearMesh_20T_S03` survives a restart.
2. Build two **20T S03** spur gears, each on a correctly fitted, freely rotating shaft supported by a grounded bearing housing; place centers 5 studs apart and overlapping axial faces.
3. Add a hand crank with an authored Weld to the input shaft. Register **both shafts, gears, housings and crank into the same Assembly** and simulate. The startup status should report `2 gears / 1 torque mesh(es)`; hold the crank. Output should rotate in the opposite direction.
4. Use simulation's mechanism inspection on crank then gears; check crank `SHAFT COUPLED`, drive `ON`, both angular velocities, `effort`, and zero grounding on moving shaft. If a hub weld was recovered in simulation, remove and redo that mount in Edit to make it persistent.
5. Run `scripts/studio/TestGearTorqueTransfer.luau` from Studio's **Server Command Bar during Play Solo**. This isolates native hinges and actual published gear geometry from UI and plot state and prints PASS/FAIL.
6. Test 12T/20T spur same-size module, 90° bevel pair with equal tooth count and shared pitch apex, compound train, backdrive, save/reload, copy, and multiplayer.

## Limitations

- A runtime inferred gear/shaft weld is **simulation-only**. It never silently alters saved authoring history or DataStores. You can make that relation persistent with Edit > Hub.
- A visually touching gear pair with mismatched sizes/tooth module cannot mesh; they must actually have the same physical tooth module. Similarly a crank merely touching a shaft without an authored Weld isn't coupled.
- Assemblies containing racks still use the legacy rack simulator. Native-tooth collision is not the power-transfer mechanism.
- GitHub's static and Luau AST checks cannot prove live Roblox physics. The Studio test remains a required acceptance gate.
