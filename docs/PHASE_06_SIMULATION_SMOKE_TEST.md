# OPENWORKS Phase 06 — Physics Simulation Smoke Test

Build: `2026.11.10.PHASE06.SIMULATION` | branch: `dev` | Rojo port: `34872`

## A. First hinge simulation

1. Build a CircularTube housing, a Cylinder shaft, and use
   **Assemble (3)** to create a **Bearing** relationship between them.
   If necessary, put the shaft in a component with an attached bar to
   make shaft rotation visually obvious.
2. Aim at the **housing** (this body will stay anchored), press **P**.
   The assembly should become a live physical copy. Its original geometry
   is hidden, not moved or destroyed.
3. Observe it without motors: HingeConstraint is free (gravity / inertial
   motion), all members of a shaft component should rotate as ONE rigid body.
4. Press **M**. The hinge should turn with the built-in motor.
   Press M again to stop motor actuation.
5. Press **P** again. The temporary simulated copy should disappear, and
   the original geometry should reappear exactly at its pre-simulation
   position and orientation. You can select and edit it immediately.

## B. Linear and rigid links

1. Create a Slider relationship between an aligned shaft and tube. Aim at
   the tube, press P. The connected shaft should be able to translate
   along the opening's local X axis, without changing angle.
2. Press M to drive the PrismaticConstraint. The prototype applies a modest
   +/- travel stop to avoid an unbounded motor ejecting the shaft.
3. Add a Fixed connection to another component. In simulation, it should
   be welded to its connected body and move as part of that rigid mass.
4. Combine multiple shaft/component segments, connect by Bearing and Fixed
   and verify the complete connected relationship graph is compiled.

## C. Edit safety, ownership and cleanup

1. While simulation is active, switch to Build (1) or Edit (2): the server
   must reject any Place/Update/Group/Undo/Redo requests. Equip Assemble and
   press P to stop, then normal editing resumes.
2. Try P while aiming at a lone part with NO relationship: show
   "Add a Bearing, Slider, or Fixed relationship first" without changing it.
3. Test two players. Player A can simulate their own graph, not B's.
   B's authored geometry must remain visible/unchanged.
4. Stop while motors are on: all motor constraints and welds in the
   temporary physics folder must be destroyed, original transparency/
   collisions restored. Starting a second simulation should work.
5. Respawn or leave while simulating: temporary physics objects and
   visibility overrides should be cleaned up.
6. Confirm original editing undo/redo works after Stop. Simulation
   deliberately does NOT add a construction history entry.

## Known limits

- Selected body is used as the stationary support. No dedicated world-ground
  constraint selection or balancing is provided yet.
- Unpowered bearings/sliders allow passive native physics; motors are
  simplified constant-speed demonstration drives, not final electronics.
- Rigid component compilation uses WeldConstraints on duplicated geometry.
  No destructive CSG compile or persistent shipping occurs.
- Connection collision exclusions can hide real shaft/bore contact forces;
  accurate bearing friction and precision collision tuning remain future work.
- Full mechanisms depend on Roblox native constraint stability and the
  actual collision fidelity of generated CSG primitives.
- This build has not been exercised in a live Studio physics simulation by
  the assistant. Treat this list as its acceptance gate.
