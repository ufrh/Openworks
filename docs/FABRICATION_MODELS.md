# OPENWORKS — Physical Work Models (Prototype)

The equipped Roblox Tool retains its **visible cosmetic model in the player's hand**. During an active fabrication pass, the hand cosmetic is temporarily hidden and the matching **ReplicatedStorage working model** is cloned into Workspace and independently moved through the secured workpiece. At release or completion, the hand cosmetic returns. The working model remains local to the player in the current prototype.

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

The original asset is never moved out of ReplicatedStorage. A clone can be attached cosmetically to an otherwise empty hand Tool, while a **separate clone** drives actual working motion in Workspace. The two do not appear simultaneously: the hand cosmetic hides for the active pass and is restored afterward. All moving working-model pieces are anchored, noncolliding, nonqueryable, and locally controlled. They cannot push stock by contact yet; stock separation and mass remain determined by FORM.

## Alignment markers (recommended)

Put a Roblox `Attachment` inside a BasePart of each **ReplicatedStorage Model**:

- **Hacksaw: `BladeEdge`** — place at the teeth's contact point. Orient its **+X axis along the blade's back-and-forth stroke**, **+Y outward from the metal**, and **+Z perpendicular to the blade's cutting plane**.
- **Metal File: `FileFace`** — place where the filing teeth should touch the edge. Set **+X along the long filing stroke**, **+Y pointing away from the metal**, and **+Z completing the right-handed frame**.

The controller aligns these markers with the chosen cutting/filing frame. For Hacksaw models missing a marker, it first looks for a BasePart named `Blade`, `SawBlade`, or `BladePart` and uses its dimensions and orientation. Otherwise it estimates the contact point from the model bounds, rotating its longest axis to follow the stroke. This heuristic cannot know where the teeth are on a single exported mesh: for precise alignment, place a `BladeEdge` Attachment. **R** rotates the working saw model in 90-degree steps when testing an ambiguous orientation.

## Saw interaction

1. Equip `Hacksaw`, secure stock, aim at the surface.
2. On equip, the hand-held cosmetic remains visible and the camera automatically **sets CameraSubject to the selected metal workpiece**, then uses a Scriptable orbit centered on its changing position (V toggle; T top-down; hold RMB to orbit; wheel zoom). **F** changes selection and camera focus to the stock under the cursor. After a cut, the camera transfers to the surviving selected fragment. On unequip, it restores the previous camera type and subject. Gold guide shows FORM's cutting plane.
3. Holding LMB hides the hand cosmetic, shows the actual Workspace saw and reciprocates the blade **along its length**, while its contact point feeds **from one side of the intended cut to the other** and progressively penetrates the metal. The combined cut travel drives the progress bar.
4. A thin, dark **visual kerf proxy** grows **along the cut** as the saw advances. This is intentionally a cheap overlay rather than an EditableMesh change every frame.
5. When the saw completes its full travel, FORM performs the true cut exactly once and the offcut falls. Releasing early cancels without changing the stock. The original equipped cosmetic is restored at either outcome.
6. Q/E rotate the plane; **R rotates the working model** by 90 degrees for alignment (not the cut plane); F selects/focuses the hovered metal, V toggles workpiece orbit, T sets top-down, RMB drag orbits, and the wheel zooms.

## File interaction

1. Equip `Metal File`, secure a block or sheet and aim near an outside edge.
2. The gold arc shows the future roundover. The actual workspace file is positioned at the corner.
3. Holding LMB temporarily hides the hand-held Metal File and slides the independent working model along the edge while progressing toward the rounded contour. On completion or cancellation, the cosmetic returns.
4. FORM validates the roundover when filing starts, but applies the geometric update **once when the pass finishes**. Releasing early cancels.

## Known scope

This is **kinematic, visible world-model contact**, not a physical-force solver and not per-frame mesh subtraction. Before completion, the underlying uncut mesh remains, so in some camera angles the blade may intersect visible stock; the progressive groove is only a presentation cue. Future work can provide true transient cutaway geometry and load-sensitive strokes.

The current M1/M2 workpiece registry is client-local; no server-authoritative tool physics or cross-player replication is claimed. All edits still inherit the existing FORM convexity, tubing, and EditableMesh-memory constraints. These changes have been committed but require a live Studio test for model alignment and control feel.
