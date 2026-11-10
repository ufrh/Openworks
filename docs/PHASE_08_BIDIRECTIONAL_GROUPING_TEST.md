# OPENWORKS — Bidirectional Component Smart Placement Acceptance

Build marker: `2026.11.10.PHASE08.BIDIRECTIONAL-COMPONENTS`, branch `dev`.

This is a Studio acceptance checklist; repository verification does not prove physics or input behavior.

## A. Move a housing onto a stationary shaft
1. Build an ungrouped Cylinder shaft and a separate DrilledBlock opening.
2. Equip Edit. Click once on DrilledBlock to select it, then hold and move
   the DrilledBlock **toward the Cylinder**. The moving hole must align with
   the stationary cylinder's actual X axis, without pressing L/Assemble.
3. Scroll for insertion depth, Q/E for orientation about that shaft axis.
   The entire moving component should follow if the drilled block is
   grouped with additional bars or brackets.
4. Release. The housing and shaft should now form ONE rigid component.
   They must be selectable and movable together. No duplicate Bearing
   constraint should appear by default.
5. Repeat with a CircularTube (local X) and a rotated DrilledBlock
   (local Y), including a housing with an arbitrary authored roll.
6. Try a shaft wider than the hole or a housing crossbar that would
   collide with the shaft: preview must reject and server must roll back.

## B. Forward insertion automatically merges components
1. Build an already-grouped component consisting of a drilled block plus
   a bracket. Drag a separate Cylinder into its hole.
2. The Cylinder should join that SAME existing component. The bracket,
   hole, and new shaft should all be one rigid body.
3. Try two independently grouped bodies, one with the hole and one with
   a shaft. Drag either onto the other: their component memberships
   should merge, and every original member must remain.
4. For two ungrouped parts, a NEW group should be created automatically.
5. Build a gear and shaft; moving the gear's center onto the shaft should
   merge them into one rigid component, rather than fabricating a
   separate Fixed joint.
6. Ctrl+Z should restore BOTH original component IDs/memberships and
   exact transforms; Ctrl+Y should reconstruct the merged group.
   A newly built shaft should disappear on Undo alongside the merge.

## C. Preserve moving mechanical relationships
1. Begin dragging a shaft into a drilled opening.
2. While the blue snap is active, press C to cycle
   Rigid → Bearing → Slider → Cylindrical.
3. Choose Bearing and release. Two distinct rigid bodies should remain,
   with a native bearing relation and functional Phase 08 simulation.
4. Repeat by dragging a housing onto a shaft and choosing Slider.
   Verify source/target relationship orientation is stored correctly:
   shaft is the source, housing is the target, regardless of what moved.
5. Undo/redo the relation, including shaft alignment metadata.

## D. Double-click to edit a primitive inside a component
1. Click a grouped component member ONCE: select whole component.
2. Double-click the same visible member (normal interval approx. 0.34s):
   select exactly that primitive, retaining its ComponentId.
3. Select a different member while interior mode is active. It should
   select that member without ungrouping.
4. Press E: return to whole-component selection.
5. Confirm direct movement/rotation and other primitive edits inside
   the component still work, and Alt+click still cycles layers.
6. Confirm a fast second click doesn't accidentally start a drag.

## E. Aligned shaft length-only scaling
1. Align a Cylinder into a hole (rigid or Bearing).
2. In Edit, double-click the Cylinder (or Alt+click if occluded).
3. Press V. Only the shaft's two X-axis end spheres should appear.
4. Resize its length in 0.25 U increments. Y/Z diameter must stay fixed,
   with the shaft axis coaxial and the completed alignment retained.
5. Test a 0.05-U fine-fitted shaft; length resize must not quantize away
   its fitted diameter.
6. A malformed Update request trying to change the aligned cylinder's
   diameter must be rejected server-side. Actual shaft extension into a
   foreign part must be rejected.
7. Undo and redo the length change; the original shaft and group
   membership should return. Drag the shaft fully OUT of the opening,
   and confirm ordinary cylinder resize becomes available again.

## F. Stability and two-player validation
1. A cannot attach or merge a component belonging to B.
2. Verify no component exceeds 128 primitives through automatic merging.
3. Retry snapping with two overlapping holes; Tab cycles candidates.
4. Stop and start simulation after every group merge; the complete group
   must compile to ONE physical rigid body with no duplicate constraints.
5. Check Roblox Studio Output for runtime errors after each operation.

**Known limits:** Gear tooth geometry/torque simulation and other Phase 08
mechanical limitations still apply. This change intentionally does not
introduce electronics, persistent shipping, or a different UI design.
