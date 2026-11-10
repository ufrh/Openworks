# OPENWORKS — Phase 05 Mechanical Relationships & Sizing

Build marker: `2026.11.09.PHASE05.MECHANICS` | branch `dev`
Run `START_OPENWORKS.bat`, connect Rojo on port `34872` and Play.

## A. Adjustable world-space sizing

1. Equip Build (1), choose Block, press **V**.
2. The HUD must show **Scale step: 0.25 U** (one U remains 0.25
   Roblox studs, so 0.25 U = 0.0625 studs).
3. Hold left click on a highlighted face. Walk, strafe or move your first-person
   camera; the face should follow the crosshair ray's **world-space** drag
   intersection, not raw mouse pixel distance. Opposite face remains anchored.
4. Press **]** to cycle 0.5, 1, 2 U steps; **[** goes back down to 0.25 U.
   Step changes take effect on the NEXT drag, not halfway through a grab.
5. Place a Block sized e.g. 4.25 U X; no grid rejection is expected. Press V
   in Edit to resize it further and then try moving, rotating, undoing/redoing.
6. Repeat with Cylinder and Sphere (diameter behavior retained).
7. Repeat on CircularTube, SquareTube and RectangularTube.
   CircularTube: X length, Y diameter (also updates Z diameter).
   Square/RectangularTube: X length, Y width, Z depth independent.
8. Preview ghosts remain transparent, placed primitives stay dark gray Metal.

## B. Alignment hole-axis correction

The Studio generator `OPENWORKS_Primitive_Generator_v4.lua` defines:
- Cylinder and circular/square/rectangular tubes: hole/shaft along **local X**.
- **DrilledBlock**: `cylinder(..., Y_AXIS)`, hole through **local Y**.
  Prior alignment incorrectly treated it as local Z.

Equip Edit (2): choose Cylinder, press **L**, aim at DrilledBlock, click,
adjust offset with wheel, click to confirm. The shaft should go **through
the drilled face**, not through a side. Repeat for SquareTube: its hollow
channel runs along local X. Empty space must be genuinely clear; if Roblox's
precompiled CSG collider reports interference, the server rejects it.

## C. Assemble — direct mechanical relationships

The native **Assemble (3)** tool adds three relationship presets. There is
no extra CAD dialog and no mouse unlock.

1. Build a CircularTube_W0.5 and a Cylinder and ensure they are separate
   rigid bodies (do not combine shaft with its housing).
2. Equip **Assemble (3)**. HUD starts on **Bearing**.
3. Aim at the housing, click. It highlights green.
4. Aim at the shaft, click. It highlights amber; a cyan ghost previews
   the assembled shaft position. If the shaft is part of a larger rigid
   component, the ENTIRE component should move with it.
5. Use wheel / [ ] to choose insertion depth (1-U steps). The camera FOV
   should not zoom during insertion and should zoom normally afterwards.
6. Click to finalize. The server should create an
   `OPENWORKS_Relationships/Relationship_<id>` Folder containing two
   managed Attachments and a **HingeConstraint**.
7. Press **R** on Assemble to cycle **Slider** (PrismaticConstraint) and
   **Fixed** (WeldConstraint). Test each type on two separate owned bodies.
   Fixed preserves current placement; Bearing and Slider align axes.
8. Try aligning a shaft that is too large for the bore, or one with a
   protruding flange that overlaps the housing. It must fail atomically
   and NOT create a relationship.
9. Ctrl+Z after authoring should undo the positioning AND relationship
   in one history step. Ctrl+Y redoes it. Esc resets the guided selection.
10. In two-player Studio test, a player must not connect or modify another
    player's primitives. Existing Build/Edit/Inspect controls remain intact.

## D. Relationship cleanup / known limits

- Mechanical relationships are **real native constraints authored now**,
  but all construction parts remain anchored. **No simulated mechanical
  motion is claimed in this phase.** Shipping/physics runtime, rigid-member
  welding, motor control and simulation come afterwards.
- Native constraints reference each body through its selected PrimaryPart;
  additional member primitives of a rigid component are not yet welded
  into a simulated rigid body.
- Rebuilding an edited part through undo/redo should reconcile or remove
  relationships whose part instances are gone.
- Tube Y/Z resizing uses the precompiled CSG object's native Size scaling.
  This **scales the cross-section and its wall thickness together**;
  maintaining a constant manufacturing wall thickness will require
  a parametric geometry kernel / precompiled variants in a future pass.
- If selection, resizing, or relationship placement fails, inspect Studio
  Output and attach the full error text. No live Studio test was available
  to the assistant during development.
