# Stationary assembly and isolated simulation

Build: `2026.11.08.CAD-ASSEMBLY.1`.

## Ownership

FORM remains the manufacturing source of truth. Assembly owns a separate versioned layout: component source-frame poses, explicit ground fixtures, requested bore supports, and quarantined legacy relationships. Neither placement nor simulation rewrites FORM nodes or operations.

Free mode retains existing published world bodies. Assembly uses anchored local projections. Simulation compiles separate server-owned bodies into an isolated spatial session; these never replace the authored layout or Free bodies. Stop destroys the session, releases its streaming focus, and restores the saved layout when Assembly opens.

`OpenWorksAssembly` serializes validation and simulation startup per player. Placement requests carry component and layout revisions. Manufacturing mutations are rejected while assembly validation or simulation is active. Validation failures leave the accepted layout unchanged. Old saved joints are retained in `assembly.quarantined`; they are never compiled or silently upgraded.

The existing DataStore envelope remains version 1 for document compatibility; the added `assembly` payload has its own version 2. Existing source components and Free-world poses remain readable.

## Editing

The assembly manipulator adapts the existing custom editor gizmo through an isolated transform model. It supports local/world axes, configurable translation and angular increments, and numerical source-origin coordinates. No manufacturing document is passed to the manipulator.

Select a component by clicking its solid. Clicking a surviving source face selects its corresponding source plane. The Reference button cycles the component's source planes, drilled-hole axes, and uncut shaft axis. Set moving reference A and fixed reference B, then choose an operation:

- Concentric rotates and translates to a shared axis, preserving axial depth. It checks shaft diameter when a shaft and bore are selected.
- Coincident aligns opposed source planes and applies the entered signed offset.
- Parallel rotates about reference A without translating it.
- Distance aligns opposed planes with the specified signed spacing.

References are manufacturing datums, not persistent rendered triangle IDs. A source plane can remain a useful datum after machining removes part of the face. The final placement is still checked against the manufactured solids. Alignment creates no mechanical record.

Placement previews update immediately. On release, the server recompiles the solids and validates the candidate arrangement. The gizmo remains unavailable during validation. A rejected placement rolls back and identifies conflicting components in red. This implementation prioritizes correctness; recompiling the workshop on every placement is a known performance cost that should be measured in Studio before introducing a revision-keyed geometry cache.

## Geometry and mechanical scope

Broad-phase checks use oriented bounds and a linear tolerance of 0.0001 stud. Block/block overlap uses separating axes. Other overlapping bounds use GeometryService intersection and the existing material-volume reader. Intersections above 0.00000001 cubic stud are rejected. Engine failure rejects the placement rather than certifying unknown clearance. Collision-volume fallback is explicitly reported as an estimate; this is not a mathematical solid-kernel guarantee.

The first supported mechanical model is `BoreSupportV1`: one unmodified cylindrical shaft in one through-drill, surrounded by continuous block or convex sketch stock. Clearance must be 1–4 mm diametral, with sufficient axial engagement. Subsequent machining, unsupported housing shapes, loose fits, and unsupported walls fail validation. This deliberately narrow model avoids claiming that an arbitrary hole history still provides a bearing.

Registering this support is explicit. It compiles to an unpowered cylindrical constraint with free axial translation and rotation. It does not weld the shaft, create a hinge, create hardware, or suppress physical collisions. Once engagement is lost, the session removes the constraint. Only one support is modeled per shaft to avoid redundant ideal constraints. Physical manufactured surfaces can act as stops through collision; no retained revolute relationship is inferred from those contacts.

The ground-fixture button represents external stationary workshop support and is labeled as such. It does not fasten components to each other.

Rigid fastening, retained revolute joints, prismatic/ball relationships, multiple-bearing support, powered actuators, load-dependent retention, and automatic recognition of manufactured retainers remain unsupported. The legacy actuator endpoint now rejects requests because a passive bore cannot supply power. These require additional manufactured-hardware validators; enabling an ideal joint or motor without those validators would violate the mechanical model.

## Verification

Run `npm ci` and `npm test` from `scripts/tests`. This compiles all Lua/Luau source and verification scripts with Luau WASM and runs 16 domain assertions. The host tests use explicit Vector/CFrame math doubles; they do not execute Roblox engine APIs.

Studio checks:

1. Run `VERIFY_Q3_ASSEMBLY.lua` in the Command Bar for source-reference, block clearance, and cylindrical compiler checks.
2. Run `VERIFY_CAD_WORKFLOW.lua` in the **client Play** Command Bar in an otherwise valid workshop. It creates and cleans up test components, tests accepted and rejected placement, legacy installation rejection, support registration, repeated simulation, and unchanged authored poses/history. Existing interfering components can correctly make this test fail.
3. Run `VERIFY_Q4_PERSISTENCE.lua` in the server Command Bar for document, layout, grounding, and quarantine codec round-trips.
4. Manually exercise move/rotate rings at several camera zooms, local/world axes, numerical input, source-face picking, and RMB/MMB/Alt camera navigation. Attempt switching modes during a drag and during validation.
5. With Studio DataStore access explicitly enabled, save, stop Play, restart, and verify poses, grounding, components, supports, and quarantined legacy records. This is distinct from the codec test.
6. Verify an actual supported shaft slides and rotates, releases after leaving its bore, and collides with manufactured stops. Repeat mode changes and inspect for leaked folders, attachments, or constraints. Inspect collision behavior at small clearances; Roblox decomposition may disagree with render geometry.

At implementation time, host compilation and domain tests passed. Studio Play, live CSG intersections, dynamic support behavior, UI camera behavior, and DataStore reload were not executed in the development environment. The complete runtime acceptance scenario remains pending those checks.

## Retired paths

Removed force-based `AlignmentAssist`, old `FeatureMatcher`/`ShaftFit`, generated `FastenerSystem`, and the old relationship graph. The prior world joint reconstruction path is disabled. `ConstraintCompiler.compile` remains a rejecting compatibility boundary, while `compileResolved` accepts only validated supported models. The obsolete Q3 test that asserted a magically retained shaft has been replaced.

Engine API references: [GeometryService intersection](https://create.roblox.com/docs/reference/engine/classes/GeometryService#IntersectAsync), [CylindricalConstraint](https://create.roblox.com/docs/reference/engine/classes/CylindricalConstraint). The bore compiler explicitly sets inclination to zero so rotation and translation share the bore axis.
