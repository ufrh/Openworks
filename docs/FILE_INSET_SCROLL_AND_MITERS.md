> **2026-11-04 concave-corner fix:** The boxed triangular caps in L-shaped notches came from constant-width bevel cutters terminating directly at a concave vertical vertex. For newly filed top/bottom edges, FORM now flags such endpoints from the authored sketch profile and tapers the triangular cutting volume toward the actual corner vertex; it does NOT run an automatic miter operation. The edge screen picker now checks both adjacent faces for visibility and no longer requires the initial material raycast to land at the exact edge. Critically, the validation no longer rejects a valid **vertical** edge merely because its height is shorter than the selected bevel width; actual adjacent face widths are checked in the editor. Existing File history entries do not magically gain endpoint taper metadata—undo/reapply those File features to test the new behavior. Tapered cutter lofts remain experimental until tested in Roblox Studio.

# FORM — Edge File stability and vertical-edge targeting

Updated: 2026-11-04. Branch: `dev`.

## Corrected behaviors

**Automatic corner miter generation has been removed.** It previously applied a
separate tetrahedral subtraction to intersecting chamfers; Studio screenshots
showed malformed triangular gouges. A plain bevel termination is preferable
to a destructive junction fix. The shared, manually requested File feature
and its history entry remain intact. Existing File history replays without
creating any automatic miter geometry.

**File now targets straight manufactured edges at any angle.** The editor
selects by projecting the authored edge segment into screen space and
checking that the finished body is visible from the camera at that position.
It no longer probes the corner exclusively along the sum of two face
normals; that test rejected many interior vertical edges even when the camera
could see them. File selection makes no test for a world-Y/top-plane
orientation. This applies to vertical, horizontal, and angled edges.

**Concave versus convex is independent of orientation.** In FORM's
history-derived topology, concave sketch vertices and pocket vertical
corners are marked as interior. Floor-to-wall pocket seams are also
recognized. Exterior bevels subtract a small wedge; interior bevels
add a small triangular bridge. Color guidance: cyan for exterior,
green for interior. Both use the File width field and live scroll preview.

The selector still requires a straight, exposed feature edge shared by
two indexed planar faces, with the selected operation's bevel width
passing the size and normal-alignment checks. Curved boundaries and
arbitrary imported meshes are not yet supported.

## Studio acceptance checks

1. Start a **fresh block**; bevel one exterior top edge and inspect.
2. Bevel a second perpendicular edge. The compiler must no longer report
   corner-miter generation, and no automatic triangular junction cut occurs.
   Existing CSG damage cannot be automatically healed without recompiling
   the part from undamaged history or undoing a problematic feature.
3. File a **vertical outside corner** of a block.
4. Make a concave L-shaped body using New Body Sketch; hover its
   **vertical inside corner**. It should illuminate green. Click and verify
   the new bevel follows the entire upright edge.
5. Cut a rectangular pocket; test a vertical interior wall junction
   and the horizontal floor/wall seam separately.
6. Rotate a component and repeat vertical edge selection. The cursor
   should follow the rotated geometry rather than any world-space axis.
7. Use mouse wheel (1 mm or Shift+wheel 5 mm) to change File width while
   hovering a valid vertical edge. Preview and numeric field must agree.

No Roblox Studio runtime session is available from this conversation;
geometry and selection were reviewed in source but require playtesting.
A solitary beveled edge can still show a planar terminal triangle. A
general bevel junction solution will require properly shared corner topology
instead of a separate guessed CSG cut.
