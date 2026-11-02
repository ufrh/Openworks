# OPENWORKS — Physical Work Models (Prototype)

The equipped Roblox Tool is the **interaction trigger**, not the geometry that performs fabrication. The actual visual tool is cloned from **ReplicatedStorage** into Workspace and independently positioned against a secured workpiece. It remains local to the player in the current prototype.

## Required assets

```text
ReplicatedStorage
├── Hacksaw                Model (or BasePart; world-space moving saw)
└── Metal File             Model (or BasePart; world-space moving file)

StarterPack (optional for local prototype)
├── Hacksaw                Tool (activation only)
└── Metal File             Tool (activation only)
```

You can use your existing Tools in StarterPack and equip from the Roblox hotbar. The prototype's Equip buttons also look for Tools in Backpack, Character, or ReplicatedStorage. **If there is only a visual Model in ReplicatedStorage, the Equip button makes a local handleless activation Tool** so a missing Tool doesn't block testing.

The original model is **not** moved or welded into the hand Tool. A clone is made under Workspace when aiming at a valid secured workpiece. All cloned pieces are anchored, noncolliding, nonqueryable, and locally controlled. They cannot push stock around by contact yet; stock separation and mass are still determined by FORM.

## Alignment markers (recommended)

Put a Roblox `Attachment` inside a BasePart of each **ReplicatedStorage Model**:

- **Hacksaw: `BladeEdge`** — place at the teeth's contact point. Orient its **+X axis along the blade's back-and-forth stroke**, **+Y outward from the metal**, and **+Z perpendicular to the blade's cutting plane**.
- **Metal File: `FileFace`** — place where the filing teeth should touch the edge. Set **+X along the long filing stroke**, **+Y pointing away from the metal**, and **+Z completing the right-handed frame**.

The controller aligns these markers with the chosen cutting/filing frame. If an Attachment is missing, it uses the **bottom center of the model bounds** as an approximate contact point. That fallback will likely look off with complex Blender meshes: a properly oriented Attachment is best.

## Saw interaction

1. Equip `Hacksaw`, secure stock, aim at the surface.
2. Gold guide shows FORM's cutting plane; the actual workspace saw aligns to that plane.
3. Holding LMB reciprocates the saw **along its blade length** while its contact point moves **from the entry surface through the cross-section**. Its penetration distance drives the progress bar.
4. A thin, dark **visual kerf proxy** grows during the stroke. This is intentionally a cheap overlay rather than an EditableMesh change every frame.
5. Upon reaching the other side, FORM performs the true cut exactly once and the offcut falls. Releasing early cancels without changing the stock.
6. Q/E rotate the plane; V, T, RMB drag and wheel retain the existing fabrication camera controls.

## File interaction

1. Equip `Metal File`, secure a block or sheet and aim near an outside edge.
2. The gold arc shows the future roundover. The actual workspace file is positioned at the corner.
3. Holding LMB slides the model along the edge while progressively moving it toward the rounded contour.
4. FORM validates the roundover when filing starts, but applies the geometric update **once when the pass finishes**. Releasing early cancels.

## Known scope

This is **kinematic, visible world-model contact**, not a physical-force solver and not per-frame mesh subtraction. Before completion, the underlying uncut mesh remains, so in some camera angles the blade may intersect visible stock; the progressive groove is only a presentation cue. Future work can provide true transient cutaway geometry and load-sensitive strokes.

The current M1/M2 workpiece registry is client-local; no server-authoritative tool physics or cross-player replication is claimed. All edits still inherit the existing FORM convexity, tubing, and EditableMesh-memory constraints. These changes have been committed but require a live Studio test for model alignment and control feel.
