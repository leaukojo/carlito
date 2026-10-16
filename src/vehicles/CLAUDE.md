# Vehicles — rules

True of every vehicle; family rules nest beside the code. Tour, derivations, figures and the
rejected designs (read before proposing a shared refactor): `docs/vehicles.md`,
`docs/heavy_vehicles.md`.

## Structure

- Subclasses use only `_make_telemetry()` and `_tick_extras()`; a family reseeds its state in
  `reset_session_state()`, not `respawn()` (a respawn is a reset).
- A method's ABSENCE is behaviour: the attachment axis never goes on `BaseVehicle`. The
  `has_method` guards in `chase_camera.gd` and `tow_host.gd` look dead and are not.
- Driveline behaviour unique to one machine is a spec flag defaulting off, never a third seam.
  Extract only where two sites are identical, not merely analogous.
- Generated bodies (`kenney/*`: `gen_kenney_vehicles.gd`; `watercraft/*`: `gen_boat_variants.gd`):
  a change goes into the recipe and a regen in the same commit, never the `.tscn` / `.tres`.
- Never detune a vehicle to suit an on/off key: keyboard feel belongs to `src/input/`.
- Contract signals key on the FAMILY: a pre-spawn path holding a variant name maps it through
  `VehicleCatalog.family_of` first.

## Physics

- Brakes are declared hardware per body, never derived or enlarged to make a body hold (a creeper
  is a drivetrain fix). A tyre (mu) edit moves no brake figure.
- Every wheel-side torque (brake, retarder, TC hold, differential, crank, converter) is solved
  inside the semi-implicit spin step, never applied after it (a `move_toward` or post-tick torque).
- One engine law on the DELIVERED fuel `Drivetrain.applied_throttle`; never feed it the pedal.
  Telemetry reads `applied_throttle`; `ShiftPolicy` reads the pedal.
- 60 Hz: never remove or weaken a clamp, never raise the tick. A damper or drag term takes a
  clamp; an external force (thrust, sail) does not.
- Never set roll or pitch in `RigidBody3D.inertia` (Jolt computes them about `center_of_mass`);
  yaw only through `yaw_dynamic_index`. Read the tensor off `PhysicsDirectBodyState3D`.
- Understeer is the bar split and the tyre's load laws (`rear_lat_grip`: a real rear-tyre fact);
  tipping before sliding is the bar or `mu_lat`. Never a slower steer, a detuned lock or a lower COM.
- Drag is declared, never inherited: a new towed or attached rigid body needs its own
  resistance call.
- Free-body helpers live in `VehicleMath`, never a fourth copy.
- Towing is shared (`TowHost`, `TowedBody`, `CouplingProfile` in `base/`): fix a towing bug in
  `TowHost`, never on one machine; no `trailer_type` accessor. E cycles the attachment, V the body.
