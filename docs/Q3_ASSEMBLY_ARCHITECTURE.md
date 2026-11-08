# OPENWORKS — Q3 / Physical Assembly

## Ownership and lifecycle

- `AssemblyController` owns the client Assembly-mode panel, selected
  component pair and ephemeral alignment assistance.
- `AlignmentAssist` applies *temporary, non-rigid* Roblox
  AlignPosition/AlignOrientation constraints with finite force/torque caps.
- `FeatureMatcher` matches actual authored `Drill` / `DrillFace`
  feature metadata, not CSG triangle/mesh IDs.
- `RelationshipGraph` is the authoritative per-player relationship
  inventory in the FORGE `OpenWorksAssembly` server Service.
- `ConstraintCompiler` turns explicitly installed relationships into
  Weld, Hinge, Prismatic, Cylindrical and BallSocket Roblox Constraints.
- `FastenerSystem` supplies simplified modeled bolt/pin shafts and
  heads with attached retainer welds. **This is not threaded contact
  physics**; the relationship constraint provides retention.

## Interaction

Enter Assembly. Drag component A, then drag B. If their drilled holes
are nearby, a force-limited guide helps center their bores without
preventing axial insertion. A single matching bore leaves twist free.
Two spaced bores solve the twist angle against one rigid pattern target;
extra compatible bores are checked against that same solution. The guide
vanishes on leaving the mode and never installs a permanent joint.

Explicit actions:

- **Install Bolt · Rigid** — creates a rigid relationship.
- **Install Pin · Revolute** — creates a hinge relationship.
- **Start/Stop hinge motor** — sets Q4 motor actuation, 2 rad/s / 220
  nominal torque in the current UI; server caps |speed| at 16 rad/s and
  torque at 50,000.
- **Remove last joint** — removes the actual server relationship and
  local stage constraints.
- **Save Workshop**, **World / Physics Status** — Q4 service controls.

Installation is checked on the server with FORM-recompiled source-local
frames, diameter compatibility, bore-axis orientation, lateral separation,
axial separation, ownership and relationship limits. Ordinary spatial
alignment does **not** weld parts. Bolt/pin installation currently
requires through holes. Blind holes are not assumed threaded.

## Degrees of freedom

| Type | Translations | Rotations | Roblox representation |
| --- | --- | --- | --- |
| Rigid | 0 | 0 | WeldConstraint |
| Revolute | 0 | 1 | HingeConstraint |
| Prismatic | 1 | 0 | PrismaticConstraint |
| Cylindrical | 1 | 1 | CylindricalConstraint |
| Ball | 0 | 3 | BallSocketConstraint |

The graph supports all five; the current UI directly exposes Bolt/Rigid
and Pin/Revolute only. A smooth shaft inserted through a hole without
explicit installation remains free under collision and gravity.

## Limitations

- Physics uses Roblox approximate contact/collision hulls, *not*
  exact analytic bore/friction simulation.
- Server ownership is per player. Cross-player shared assemblies,
  threads/nuts, bearing clearances, actual shaft insertion capture, servo
  wiring and procedural rails remain future systems.
- Assembly-stage parts are client-working physics copies; the server
  retains the installed graph and compiles relations on replicated Free
  Mode bodies.
- Studio tests remain required: `scripts/VERIFY_Q3_ASSEMBLY.lua`, plus
  manual two-hole assembly, installation, return-to-Free and re-entry.
