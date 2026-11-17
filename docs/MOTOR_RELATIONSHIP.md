# OpenWorks — Motor relationship (shaft + drilled block)

**No motor primitive, no mesh publishing, no Studio plugin.**

The Motor relationship is offered by the existing **Build/Edit Smart Fit
shaft-in-hole popup**, alongside Bearing, Slider and Cylindrical, only when
the opening is a drilled/hole block. **Do not use Mechanics > Connect to create
a motor**. Fit the cylinder into the hole exactly as for an ordinary Bearing,
choose **Motor** in the existing popup, and confirm the insertion.
Internally Motor persists as a Bearing with `MotorRelationship=true` and
`MotorEnabled=true`, reusing the fitted-geometry validation, undo/redo,
autosave, simulation hinge and orange motor visualizer. It appears as
`Motor` in the contextual inspector and relationship index. The default
key is F. When multiple shaft/hole pairs fit together, only the selected
primary drilled hole becomes powered; the other fitted joints remain passive.

## Runtime implementation

OpenWorks now routes simulation through
`ConstructionService -> UnifiedSimulationService`, not the retired
`SimulationService`. The router starts:

- **PhysicalSimulationService** for normal shaft/gear/belt assemblies,
  using native `AngularVelocity` on the motor's shaft and
  `GearTransmission:SetDrive` to transmit speed through welded gears.
- **RackSimulationService** if the assembly contains a Rack or RackGuide;
  the motor controls its input shaft through the same
  `GearKinematics:Step` path as the hand crank.

Both engines use `BearingSupport` for **rigid-group validation only**.
No bearing or motor automatically anchors, grounds, or locks its housing,
regardless of editor grouping or whether it has a welded chassis. A housing
remains a mobile physical body (or moves with its real welded structure)
unless the builder explicitly sets **Grounded**. Grounding is never silently
removed from a rotor either: an explicitly grounded motor shaft reports
a construction error. Powered motor bearings are passive native hinges
with no motor actuator or angular hard-stop, so they cannot transmit
powered rotation to the housing through the hinge. The motor drive follows
the actual `HingeConstraint.Attachment1.WorldAxis`. A shaft welded to its
housing is rejected as mechanically locked. Authored construction hinges
also remain passive and never act as a second housing-side motor.

Studio Output prints `[OPENWORKS][SIM ROUTER]` with the selected engine and
`[OPENWORKS][MOTOR] ACTIVE ...` with motor and gear counts.
These are source-level changes; actual Studio behavior still needs testing.
Run `python scripts/check_active_motor_routes.py` after future motor changes
so retired simulation code cannot be mistaken for the active runtime.

## Configure

In Build or Edit, drag the shaft into a drilled hole block (or the
block onto the shaft), use the normal Smart Fit alignment/depth tools,
then choose **Motor** in the existing relationship popup. Right-click
one of the connected parts and open its **Motor** relationship to configure it.

- **Motor enabled:** enable or disable actuation
- **Motor key:** held/toggled keyboard input, defaults to F
- **Drive: Continuous / Servo:** continuous angular velocity vs bounded
  position target
- **Input: Hold / Toggle:** run while pressed or switch on/off each press
- **Speed (rad/s):** signed direction for Continuous; absolute rotation
  rate for Servo
- **Servo target (degrees):** relative hinge angle in [-180, 180]
- **Max torque:** limits driving force, 1–100,000
- **Acceleration:** controls continuous motor acceleration, 0.1–1,000

## Behavior

| Drive | Hold | Toggle |
|---|---|---|
| Continuous | rotates while pressed, stops on release | press to run, press again to stop |
| Servo | approaches target while held, returns to neutral 0° on release | press to target angle, press again to neutral 0° |

The motor drives the **shaft**, never the hole-block housing. All passive
and powered bearing housings remain **unanchored by default** and keep
their independently simulated movement. A housing welded to a vehicle
moves with that vehicle, not with its axle's rotation. The only anchored
members are those explicitly marked Grounded by the builder. If the
builder explicitly grounds a motor shaft/gear rotor, simulation rejects
the conflicting configuration rather than silently changing their flags.

- **No mounted gear:** the active physical engine keeps a passive
  `HingeConstraint` for axle positioning and a shaft-only
  `AngularVelocity` actuator, with continuous and servo settings
  enforced on the shaft. No powered hinge actuator acts on the housing.
- **Gear rigidly welded onto shaft:** for normal assemblies,
  `GearTransmission` commands physical `AngularVelocity` on the meshed
  output shaft with tooth-count speed ratios. Small output gears can run
  proportionally faster than the 35 rad/s motor-input ceiling; a separate
  240 rad/s physical-output safeguard applies. Output drive torque adapts
  to gearing and measured shaft load to avoid the previous slow gear bug.
  The rack-specific engine instead uses `GearKinematics` and its exact
  ratio-based scripted rotation, including servo goals. The shaft and its
  rigidly fitted gear always belong to the same rotor group.
- **Torque:** the physical motor has a configurable torque budget.
  Meshed physical output shafts use a boosted, load-aware speed actuator
  so actual angular speeds track the tooth ratios rather than stalling
  against an obsolete fixed output torque limit. This is not a fully
  physically accurate torque/power simulation.

Servo returns toward 0° using controlled rotation, not teleports. Existing
angular travel limits constrain native hinge servos; kinematic gears do not
have a physics hinge and cannot use native angular hard stops.

The server receives key transitions and hold liveness only. The server owns
and validates speed/force/angle parameters. Toggle behavior is edge-triggered
so repeated held-input heartbeats cannot double-toggle. Hold input times out if
the client loses focus/network. Simulation pause resets drive to the
off/neutral state. Stop destroys the runtime physics clones.

## Persistence and legacy compatibility

The saved relationship retains all motor fields in the existing relationship
snapshot. Legacy powered bearings without the new drive fields default to
Continuous + Hold + 90° servo target. Ordinary passive bearings remain
unpowered. Motor has no mesh, asset manifest, runtime authoring or plugin
requirement.

## Studio verification checklist

1. Select two unrelated primitives: they must not offer Motor.
2. Select a drilled hole block and shaft: Motor must be available. An
   improperly fitted pair must be rejected by existing bore validation.
3. In Simulate, test Continuous/Hold, Continuous/Toggle, Servo/Hold,
   Servo/Toggle; press/release key and switch direction. Repeat with and
   without a gear **rigidly welded** to the motor shaft.
4. Verify a free drilled housing remains **unanchored** while the shaft
   rotates independently and its gear drives the meshed outputs. A free
   housing can still move or tumble under external physics; no hidden
   angular stabilizer or world anchor is allowed. For a fixed test fixture,
   explicitly mark its support Grounded in the Assembly tool.
5. Verify torque/speed, servo target and any native-hinge angle limits.
6. Stop/restart simulation, save/reload plot, undo/redo creation/settings,
   and disconnect/reconnect shaft. Check no phantom drive persists.

Source is committed to `dev`. Studio simulation validation is still required.
