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

The servo uses `HingeConstraint.ActuatorType=Servo`,
`TargetAngle`, `AngularSpeed`, and `ServoMaxTorque`. The continuous drive
uses `ActuatorType=Motor`, `AngularVelocity`, `MotorMaxTorque`, and
`MotorMaxAcceleration`. Servo returns to 0° using its configured speed and
torque rather than teleporting. Existing angular travel limits still apply;
if a target lies outside those limits, the hinge cannot reach it.

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
   Servo/Toggle; press/release key and switch direction.
4. Verify torque/speed, servo target and any angle limits.
5. Stop/restart simulation, save/reload plot, undo/redo creation/settings,
   and disconnect/reconnect shaft. Check no phantom drive persists.

Source is committed to `dev`. Studio simulation validation is still required.
