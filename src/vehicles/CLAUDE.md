# Vehicles — rules

True of every vehicle; family rules nest beside the code. Read `docs/vehicles.md` (and its
family doc, via `docs/overview.md`) before proposing a shared refactor: it lists the rejected designs.

## Structure

- Subclasses use only `_make_telemetry()` and `_tick_extras()`; a family reseeds its state in
  `reset_session_state()`, not `respawn()` (a respawn is a reset).
- A method's ABSENCE is behaviour: the attachment axis never goes on `BaseVehicle`. The
  `has_method` guards in `chase_camera.gd` and `tow_host.gd` look dead and are not.
- Driveline behaviour unique to one machine is a spec flag defaulting off, never a third seam.
  Extract only where two sites are identical, not merely analogous.
- Generated bodies (`kenney/*`, `watercraft/*`) change in their recipe plus a regen, never the
  `.tscn` / `.tres` (the `vehicle-feel` skill). Keyboard feel belongs to `src/input/`, never a detune.
- Contract signals key on the FAMILY: a pre-spawn path holding a variant name maps it through
  `VehicleCatalog.family_of` first.

## Physics

- Brakes are declared hardware per body, never derived or enlarged to make a body hold (a creeper
  is a drivetrain fix). A tyre swap moves only the class factor on mu and crr; fitment stays the body's.
- Every wheel-side torque (brake, retarder, TC hold, differential, crank, converter) is solved
  inside the semi-implicit spin step, never applied after it (a `move_toward` or post-tick torque).
- One engine law on the DELIVERED fuel `Drivetrain.applied_throttle`; never feed it the pedal.
  Telemetry reads `applied_throttle`; `ShiftPolicy` reads the driver's demand (`PedalMap.demand`).
- 60 Hz: never remove or weaken a clamp, never raise the tick. A damper or drag term takes a
  clamp; an external force (thrust, sail) does not.
- Never set roll or pitch in `RigidBody3D.inertia` (Jolt computes them about `center_of_mass`);
  yaw only through `yaw_dynamic_index`. Read the tensor off `PhysicsDirectBodyState3D`.
- Understeer: the bar split, tyre load laws (`rear_lat_grip`), sourced roll and compliance steer;
  tipping before sliding: the bar or `mu_lat`. Never a slower steer, a detuned lock or a lower COM.
- Drag and angular damping are declared, never inherited: a new towed or attached rigid body
  needs its own resistance call and `VehicleMath.declare_angular_damp`.
- Free-body helpers live in `VehicleMath`, never a fourth copy.
- Towing is shared (`TowHost`, `TowedBody`, `CouplingProfile` in `base/`): fix a towing bug in
  `TowHost`, never on one machine; no `trailer_type` accessor. E cycles the attachment, V the body.
