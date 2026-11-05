# FORM — Drill preview and fabrication animations

Updated: 2026-11-05. Branch `dev`.

## Corrected idle Drill preview

The idle cursor is intentionally **one thin circular outline** on the
selected manufactured face—no giant through-hole shaft or filled cylinder.
Its circle basis is constructed from the selected face's real world-space
normal, so it follows top, side and rotated faces.

The dimension badge is now attached to a dedicated `Attachment` at the
actual world-space drill point. The old badge positioned an absolute
world coordinate through `StudsOffsetWorldSpace`, which could appear
detached from the workpiece depending on camera/adornee placement.

The old long cyan beam was caused or amplified by showing an entire
through-hole guide while hovering. Those depth rails are now shown **only
while the drilling animation runs**. Through-hole feed distance is
calculated to the exit of the stock's axis-aligned **local** box, never
the grossly oversized Boolean drill cutter. For complex previously
manufactured bodies, the visible bottom guide is only approximate.

## Operation animations (adornments only)

The client-only `ToolVisualizer` owns a single short animation state,
updated through the existing `FORMDebug` RenderStepped callback. All
frames recycle the existing pooled `LineHandleAdornment` instances.

- **Drill:** ~0.85 s, drilling rings move along the inward face normal;
  four short depth rails and two rotating flute lines show feed and spin.
- **File:** ~0.90 s, four back-and-forth scraper passes across the
  selected manufactured edge, honoring its segment count and width.
- **Inset:** ~0.65 s, the polygon border descends to its chosen depth.
- **Sketch / Saw profile:** ~0.80 s, the authored path is traced in order
  after successful commit.

These are **visual effects**, not a new physics tool system. The validated
document operation is committed once through the existing
`Document:addOperation` path and the existing asynchronous
`Preview:render` call continues to compile the final solid. Input is
guarded against repeated clicks during animation; changing tool or
component cancels just the remaining visual effect, never the already
committed feature.

## Studio acceptance checks

1. Select Drill and hover over the top of a new Block. Exactly one
   thin circular outline and a badge should follow the pointer, with no
   long floating rod and no detached label.
2. Hover over a vertical side face. The circle should rotate into
   that surface's plane. Orbit and rotate the stock to confirm.
3. Click Drill: the animated feed and rotating flute lines should
   briefly appear, then vanish without lingering artifacts.
4. Drill blind versus through: the former animates the entered depth,
   the latter uses the stock exit distance.
5. Set File to 1 segment and click a normal exterior edge. Observe
   four scraping passes. Repeat with 4 or 8 segments.
6. Perform Inset, Saw (Profile), and Sketch Extrude; observe their
   transient path/depth effects. Verify fabrication history contains
   only one entry per click.
7. Change tool or select a different body mid-animation; remaining
   animation guides should disappear. The committed feature must stay.
8. Verify Groove and Straight Kerf are still absent from the editor,
   while historical features still replay.

No Roblox Studio runtime is available in this chat. These changes passed
source checks but **must be visually tested in Studio**.
