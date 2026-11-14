# Gearbox failure captured in user's November 13 Studio recording

Observed: the right-hand gear and hand crank rotate, but the left-hand gear and its output shaft remain stationary. This isolates the visible failure to output-side mounting / gear-to-gear engagement rather than to the crank input.

## Fixes

- The simulator now infers a physics-only welded hub for a **unique**, physically inserted shaft with slight construction alignment drift and press-fit clearance. It does not change the saved assembly, and rejects ambiguous candidates.
- Native torque is delivered to visibly engaged gear bodies even when their own shaft mount is not recognized; an unmounted gear can spin, but **its shaft will not spin until actually welded**. The live inspector labels those loose gears explicitly.
- Runtime spur pair detection uses module-scaled, bounded spacing tolerance and physical tooth-tip overlap, not a hard-coded 0.09-stud limit for all gear sizes. *Different tooth modules still cannot mesh.*
- At simulation startup Output warns about excluded gears, missing hub welds and the closest rejected mesh reason. Persistent mesh IDs are not touched.

## Acceptance

After syncing `dev`, Play Solo: add two supported shafts and two spur gears of the **same Size Sxx** (different tooth counts are fine), mount each by Hub/Weld, add to one named Assembly, simulate and crank. Observe two rotating shafts with ratio `-teethInput/teethOutput`. If it still fails, use `Info` on either gear or read `[OPENWORKS][GEARS]` messages in Output: new warnings distinguish incompatible modules, spacing, missing shaft mount and assembly membership. Also check the output shaft is not grounded.

The provided video cannot prove precisely which rejection occurred on the server. All automated checks are static; actual native physics requires Studio playback.
