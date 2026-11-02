# OPENWORKS — Physical Work Models (Prototype)

The equipped Roblox Tool retains its **visible cosmetic model in the player's hand**. When aiming at a cuttable workpiece, the hand cosmetic hides and the matching **ReplicatedStorage working model** becomes visible for positioning, before any cut begins. As soon as targeting ends or the pass is interrupted/completed, the hand cosmetic is restored. The working model is moved through secured **or loose** workpieces. All effects remain local in this prototype. The working model remains local to the player in the current prototype.

## Required assets

```text
ReplicatedStorage
├── Hacksaw                Model (or BasePart; world-space moving saw)
└── Metal File             Model (or BasePart; world-space moving file)

StarterPack (optional for local prototype)
├── Hacksaw                Tool (equipped cosmetic + input)
└── Metal File             Tool (equipped cosmetic + input)
```

You can use your existing Tools in StarterPack and equip from the Roblox hotbar. The prototype's Equip buttons also look for Tools in Backpack, Character, or ReplicatedStorage. **If there is only a visual Model in ReplicatedStorage, the Equip button makes a local handleless activation Tool** so a missing Tool doesn't block testing.

The original asset is never moved out of ReplicatedStorage. A clone can be attached cosmetically to an otherwise empty hand Tool, while a **separate clone** drives actual working motion in Workspace. The two do not appear simultaneously: the hand cosmetic hides during **preview positioning and active sawing**, and is restored afterward. All moving working-model pieces are anchored, noncolliding, nonqueryable, and locally controlled. They cannot push stock by contact yet; stock separation and mass remain determined by FORM.

## Alignment markers (recommended)

Put a Roblox `Attachment` inside a BasePart of each **ReplicatedStorage Model**:

- **Hacksaw: `BladeEdge`** — place at the teeth's contact point. Orient its **+X axis along the blade's back-and-forth stroke**, **+Y outward from the metal**, and **+Z perpendicular to the blade's cutting plane**.
- **Metal File: `FileFace`** — place where the filing teeth should touch the edge. Set **+X along the long filing stroke**, **+Y pointing away from the metal**, and **+Z completing the right-handed frame**.

The controller aligns these markers with the chosen cutting/filing frame. For Hacksaw models missing a marker, it first looks for a BasePart named `Blade`, `SawBlade`, or `BladePart` and uses its dimensions and orientation. Otherwise it estimates the contact point from the model bounds, rotating its longest axis to follow the stroke. This heuristic cannot know where the teeth are on a single exported mesh: for precise alignment, place a `BladeEdge` Attachment. **R** rotates the working saw model in 90-degree steps when testing an ambiguous orientation. **Shift+R** flips the tooth-facing direction by 180 degrees around the stroke axis.

## Saw interaction

1. Equip `Hacksaw` and aim at any raw-stock piece, secured **or unanchored**. Securing is optional for sawing (but still required for the present filing operation).
2. When the **selected** stock is secured, the camera uses Roblox's built-in `CameraType.Custom` and `CameraSubject = selectedPart` with an initial close-up of about 4.5 studs, allowing **normal RMB orbit** and **native mouse-wheel zoom** (0.7–22 studs). No scriptable camera rotation is used. **Loose stock never triggers the workpiece camera**: your usual camera stays intact. **F** selects and focuses stock under the cursor; **V** enables/disables automatic secured-stock focus. Camera subject and previous zoom limits are restored when unsecuring or unequipping. Gold preview shows FORM's cutting plane.
3. The working Workspace saw appears **while positioning** along the gold guide, before LMB. Holding LMB starts the reciprocal blade strokes and advances the blade **along the cut** as well as **through the metal**. The combined cut travel drives the progress bar. With loose stock, the planned cut plane and saw pose follow the piece's moving/rotating local frame.
4. **Q/E** yaw the cut plane and **Z/X** tilt it, both in 15-degree steps. Oblique cuts can therefore cross the workpiece in 3D, subject to FORM geometry validity. A thin, dark visual kerf proxy grows along the cut without modifying an EditableMesh every frame.
5. At full travel, FORM performs the cut exactly once. A secured piece retains workholding for the larger fragment and drops the offcut. A **loose piece splits into two loose fragments**, inheriting the previous linear and angular velocities. Releasing early cancels without changing the stock. The hand cosmetic is restored at either outcome.
6. Q/E yaw the cutting plane, Z/X tilt it, R rotates the working model 90 degrees, and Shift+R flips the blade teeth. **F** selects hovered metal, **V** toggles secured-stock camera focus. RMB and mouse wheel use the normal Roblox camera controls. The former scriptable-orbit and T top-down overrides are removed.

## File interaction

1. Equip `Metal File`, secure a block or sheet and aim near an outside edge.
2. The gold arc shows the future roundover. The actual workspace file is positioned at the corner.
3. Holding LMB temporarily hides the hand-held Metal File and slides the independent working model along the edge while progressing toward the rounded contour. On completion or cancellation, the cosmetic returns.
4. FORM validates the roundover when filing starts, but applies the geometric update **once when the pass finishes**. Releasing early cancels.

## Known scope

This is **kinematic, visible world-model contact**, not a physical-force solver and not per-frame mesh subtraction. Free workpieces remain physically simulated, but sawing does not apply a simulated reaction force or frictional restraint. Before completion, the underlying uncut mesh remains, so in some camera angles the blade may intersect visible stock; the progressive groove is only a presentation cue. Future work can provide true transient cutaway geometry and load-sensitive strokes.

The current M1/M2 workpiece registry is client-local; no server-authoritative tool physics or cross-player replication is claimed. All edits still inherit the existing FORM convexity, tubing, and EditableMesh-memory constraints. These changes have been committed but require a live Studio test for model alignment and control feel.
