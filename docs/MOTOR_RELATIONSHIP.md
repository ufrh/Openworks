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

Both routes anchor the drilled hole block at simulation start, release
any previously grounded shaft/drive-gear rigid group in temporary simulation
state only, and reject a shaft actually welded to its hole-block housing.

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

The motor drives the **shaft**, never the hole-block housing. If the assembly
has no explicit grounding, its motor hole block is grounded automatically
to keep the housing stationary. **The motor's hole block is always fixed in
simulation**, even when other parts were explicitly grounded. The driven
shaft and every gear welded to its rigid group are always released from
grounding during simulation; this does not modify saved construction flags.

- **No mounted gear:** the continuous drive uses a passive
  `HingeConstraint` with a smooth, torque-limited `AngularVelocity`
  actuator attached to the shaft, matching the standalone hand-crank
  drive. Servo uses the physical hinge's `ActuatorType=Servo`, target
  angle, angular speed and `ServoMaxTorque`.
- **Gear rigidly welded onto shaft:** the kinematic gear solver owns the
  complete shaft-and-gear rigid group. No native hinge motor is allowed to
  compete with it. The motor's key input drives the **same shaft ID and axle
  orientation** as a hand crank; its welded input gear, meshed output gears
  and compound trains advance together. For older builds where a
  concentric, clearance-validated gear sits on the shaft but the Hub weld is
  absent, the simulation temporarily includes that orphan gear in the shaft
  group. The author should Smart Fit that gear to save the weld permanently;
  geometrically invalid hubs are rejected with a useful error. Server
  Heartbeat integrates rotation without a fixed 60 Hz gate. Geared servo
  control uses a signed, unwrapped
  shaft angle with a capped target displacement to prevent overshoot.
- **Torque:** native shaft motors and servos honor physical drive budgets.
  Geared groups are kinematic, like hand-crank-driven gear trains, so their
  `Max torque` cannot yet model dynamic gear loads or stall force. It remains
  persisted for future load-aware transmission.

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
4. Verify the hole block remains motionless while its shaft rotates, and
   confirm the welded input gear drives meshed output gears. Keep the
   housing ungrounded for the first test; the motor should supply its
   default support when no other part was explicitly grounded.
5. Verify torque/speed, servo target and any native-hinge angle limits.
6. Stop/restart simulation, save/reload plot, undo/redo creation/settings,
   and disconnect/reconnect shaft. Check no phantom drive persists.

Source is committed to `dev`. Studio simulation validation is still required.
