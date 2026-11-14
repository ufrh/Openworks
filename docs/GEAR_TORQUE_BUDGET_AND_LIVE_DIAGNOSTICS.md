# OpenWorks native gearbox torque budget and live-input diagnostics

## Studio observation

On Nov 13, a rebuilt two-gear assembly reported `Input crank armed: 2 gears / 1 real torque link(s)`, but no rotation transferred. This only verifies graph membership and initial geometric mesh detection, **not** sustained crank input, applied torque, or physically unanchored rigid bodies.

## What changed

- Retain the native `AngularVelocity` motor on the crank-driven shaft and the real physics `Torque` constraints coupling welded shaft assemblies. **No scripted CFrame animations.**
- Bound speed-error coupling effort to 72% of manual crank torque, divided by `max(1, abs(gear ratio))`, so an enormous correction can't cancel the input motor's entire available torque. This is intentionally an accessible gameplay torque limit, not friction-accurate tooth simulation.
- Avoid NaN/Infinity forces by detecting anchored *physics assembly roots*, nonfinite `AssemblyMass`, and clamping inertia estimates. A physically anchored output should not be silently treated as a movable rotor.
- Begin with a small, nonzero angular target rather than relying exclusively on the next Heartbeat; ease toward the full 2 rad/s target while LMB is held.
- Report early release, held-input watchdog expiration, or the player's physics root becoming too far away.
- After approximately one second of sustained hold, inspect motor target, actual shaft angular speed, enabled state, received input packets, physical assembly anchoring, output speed, coupling effort and linked-gear engagement; warn with `[OPENWORKS][GEARS] LIVE DRIVE STALL` if motor or output remains stationary. Throttle repeats.
- Extend the isolated Studio smoke test to print the final actual rotational state.

## Studio acceptance

1. Sync `dev` and restart Play Solo. Simulate two matching gear prefabs, each rigidly mounted to its shaft and supported by a proper passive bearing housing, with both assemblies registered together.
2. Hold LMB over the HandCrank for **at least three seconds**. The server must receive held-input pulses, the native drive motor must remain enabled, and both shafts should turn at the expected opposite sign and gear ratio.
3. If it still fails, read the new `LIVE DRIVE STALL` line. `motor enabled=false` or `input pulses=0` points to control/watchdog. Input root `anchored=true` or invalid mass points to an illegal rigid tie to a grounded part. Nonzero input speed with zero output and bounded nonzero effort suggests output support or collision blocking. If both speeds are nonzero but gears do not visibly follow, inspect the prefab internal welds/PrimaryParts.
4. Run `scripts/studio/TestGearTorqueTransfer.luau` from the **Server Command Bar in Play Solo** to test the shared transmission solver independently of the user's construction graph.

Static CI verifies source contracts and numerical torque limits, but cannot prove physical Roblox constraint behavior. Do **not** claim the gearbox is working until this Play Solo acceptance passes.
