# FORM — Interior Corner Investigation (Exterior File Only)

Status: **experimental interior edge filing suspended**. Branch: `dev`.

## Why this was rolled back

Several attempts to correct the rectangular endcap where two ordinary
perimeter bevels meet at a concave L-shaped corner produced worse geometry.
The feature that created a vertical *interior edge bevel* used an additive
wedge, which sometimes refilled material already removed by exterior
perimeter bevels. Experimental end tapers, post-CSG junction cuts, and
preclipped additive polyhedra also failed Studio visual testing.

## Current safe prototype behavior

- The **File** tool can select normal exterior straight edges (top, bottom,
  vertical) and use the established subtractive triangular cutter.
- The **inside/concave** File option is disabled in the hover/click editor,
  rejected in Document:addOperation and excluded from Fabricator CSG replay.
- Existing FileMesh operations with `interior=true` remain in the history
  for reversibility but are marked `FILE INNER (PAUSED)` and ignored by
  compilation and surface picking. They are not silently deleted.
- No corner miter, preclip, additive wedge or secondary junction Boolean
  is currently applied.
- Fabricator's geometry cache key has been bumped so preview recompiles.
  This does not modify the original parametric history.

## The one issue to solve next

File *two ordinary external perimeter edges* that terminate at the **same
concave corner** of a simple L-shaped workpiece. Inspect the little
rectangular/triangular cap at their common endpoint.

The correct solution must be generated from **their shared convex bevel
surfaces**. At a concave polygon vertex, the cutter termination is not a
standard outside cube corner. Future development should:

1. Identify the exact two authored perimeter features and common endpoint.
2. Construct their intended new boundary intersection in the original
   workpiece plane, then solve the resulting corner face analytically.
3. Have both new bevels share that endpoint/face **within the same
   manufacturing feature** rather than running independent post-CSG patches.
4. Update the feature-history topology and preview from exactly the same
   final face/edge definitions.
5. Validate geometrically with numerical tests and check the actual Roblox
   CSG result on a simple L-profile before extending further.

Avoid re-enabling interior vertical filing as a workaround. This is a
separate task from forming a coherent junction between ordinary perimeter
bevels.

## Studio test

Start with a fresh L-shaped body, file **only its two ordinary upper
perimeter edges** leading into the concave corner. Confirm the File tool
does not offer the vertical inside edge and that the previous massive
additive block is gone. The small endpoint corner cap may remain; that
is the known outstanding defect.

This rollback is source-verified, not executed live in Roblox Studio.
