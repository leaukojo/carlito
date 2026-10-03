# Vehicles — rules

True of every vehicle; family rules nest beside the code (`drone/`, `train/`, `truck/`, `tractor/`,
`kenney/`). Tour, derivations, measured figures: `docs/vehicles.md` (`docs/heavy_vehicles.md` for
truck / trailer / tractor).

## Subclassing `BaseVehicle`

- Subclasses use only the two seams, `_make_telemetry()` and `_tick_extras()` (runs last, so rpm and
  telemetry motion are current). Never fork `_physics_process`.
- A subclass that steers itself slews from the surface it last applied, never from `_steer`:
  re-slewing the base's already-slewed value cancels (`boat.gd` `_autopilot`).
- A respawn is a reset. A family reseeds its subsystems in `reset_session_state()`, not `respawn()`
  (`tests/test_respawn_reset.gd`). Only a hard ordering constraint overrides `respawn()` (the drone
  drops its crate first).
- A method's ABSENCE is behaviour. The attachment axis (`ATTACHMENT_AXIS` in
  `tests/test_vehicle_catalog.gd`) never goes on `BaseVehicle`, or every car grows an ATTACH button
  and an `artic` readout; what the tractor and semi share is an owned object both forward to.
  - Before deleting a `has_method` guard, check the receiver's static type: the guards in
    `chase_camera.gd` and `tow_host.gd` look dead and are not.
- A telemetry field moves up to `VehicleTelemetry` only when it is family-agnostic body state
  (`pitch`, `roll`, `altitude`, `vspeed`).
- Extract only where two sites are identical, not merely analogous: `engine_load_pct` is shared,
  the four reservoirs are not (see Rejected).
- `BaseVehicle._level_root()` is the one level lookup; a new world query calls it. Before adding a
  walk, check whether a collision layer answers it (`Layers.SOLID` omits `Containment`).

## Specs and generated vehicles

- The ground drive is optional (boat, drone and train have none); code outside the wheeled path
  reads it through `drive != null`.
- Driveline behaviour unique to one machine is a spec flag defaulting off (`rear_diff_lockable`,
  `front_axle_engageable`), never a third seam.
- `has_engine` gates garage and selector readouts, never physics: `Drivetrain` runs for every family
  because the gear byte is the direction latch and the source of `ST_REVERSE` / `ST_NEUTRAL`.
- Weight split: declare `front_weight` in the recipe. A raw `com_z` is only for a body tuned by
  driving (garbage truck). `com_z = 0` is wherever Kenney put the origin, not 50/50.
- Steering lock: pick the lock in degrees, then divide (`min_steer_frac` scales the body's own
  `max_steer_deg`). The taper is linear from a standstill, so check a slow body at its working
  speed. Guard: `test_a_steering_taper_never_out_limits_the_tyres`.
- Never detune a vehicle to suit an on/off key: keyboard feel belongs to `src/input/` (its CLAUDE.md).
- Generated bodies: `kenney/*` (`tools/gen_kenney_vehicles.gd`) and `watercraft/*`
  (`tools/gen_boat_variants.gd`). A feel change goes into the recipe and a regen in the same
  commit, never into the `.tscn` / `.tres`. A failing `test_kenney_variants` / `test_boat_variants`
  is fixed the same way, because the derived values (brakes, handbrake, Cd*A) move with it.
  Hand-authored collision survives a regen by whitelist (`kenney/CLAUDE.md`, `tools/CLAUDE.md`).
  - A Kenney spec flag must also be in the generator's family baseline, or the next regen wipes it.
    Edit the spec the shipped SCENE loads (`test_tractor` walks catalog → scene → spec).

## Drivetrain and brakes

- Hierarchy: brake > TRANSMISSIBLE drive (`min(peak drive, driven wheels * mu_long * N * r)`) >
  handbrake. Guard: `test_vehicle_catalog.test_kenney_specs_keep_force_hierarchy`. Drift comes from
  `handbrake_grip`, never handbrake torque. It is a total: a wheel holds only against its own
  drive, which first gear beats on the heavies, so both pedals held are
  `InputRouter.brake_override`'s.
- Kenney `brake_torque` derives from the tyre (`BRAKE_GRIP_FRAC * mu_long * N * r`), with no
  per-family knob, and `brake_bias_front` splits it by each axle's load-scaled grip in a full-pedal
  stop (an even split locks the unloaded axle and under-brakes the loaded one); negative = even. With AWD and a close-ratio
  first, the hierarchy floor can exceed the tyre: fix gear 1 or torque, never the brake. The
  hand-built semis are not grip-derived (their retarder hangs off `brake_torque`).
- The brake goes through the semi-implicit spin step (`* spin_compliance`), never a move_toward
  after it: outside it, a held brake needs the tyre to carry `1 + reaction_stiffness` times its
  torque and any firm pedal locks. Guard: `test_wheel_spin` § brakes.
- ABS (`abs_equipped`, road vehicles; not the tractor, the race cars or the plane) caps the foot
  brake and retarder at `RayWheel.ABS_SLIP`, the grip peak. A handbrake or spring brake is a
  mechanical hold no ABS modulates: a wheel under one brakes without it.
- TC (`tcs_equipped`, the car family minus the race cars) caps drive at `RayWheel.TCS_SLIP`, per
  wheel and drive-only (never brakes); the bridge's `tcs_off` disables it.
- The tyre class (`mu_long` / `mu_lat`) is the root of everything brake-shaped: brake, retarder
  rating, hierarchy floor, taper margin. A mu edit is a re-derivation (recipe + regen), never a
  number edit.
- The rev limiter judges `wheel_engine_rpm` (raw), never `Drivetrain.rpm` (its lerp never reaches
  redline). The limiter, the governor and the shift cut all ride `applied_throttle`.
- The limiter and engine braking are hard edges: a fade band eats drive torque below redline and
  moves top speeds. A lazy launch is fixed at the launch (grip, gear 1, `shift_up_rpm`), not at the
  limiter.
- `converter_free_rpm` is a floor under the wheels, never a ceiling, and the converter multiplies
  no torque (COMPROMISE at `drivetrain.gd`).
- Declaring `speed_limit_kmh`: re-measure the variant (a governor below the next upshift strands
  the gearbox; `governed_upshift` handles it). The value is contract-visible: whole km/h, 0-250
  (`test_vehicle_catalog`).
- Every differential is declared: a friction coupling between its outputs, solved INSIDE the spin
  step through `RayWheel.spin_compliance`, never applied as a post-tick torque (that is `1 + k`
  times too strong and makes every LSD a spool). It is never a traction cap or a grip-aware split
  (rule 3).
  - `centre_diff_rigid` is allowed only where the driver can disengage the axle
    (`test_vehicle_catalog`). An open centre caps AWD at its lightest axle.
  - Changing a diff moves accel and grade figures: re-measure with `measure_vehicles` /
    `measure_grade` / `measure_rough`.

## The 60 Hz tick

- Stability at the locked 60 Hz (root rule 9) lives in:
  - `RayWheel`: damper ≤ one-tick reversal, suspension force cap, low-speed slip floors, one-tick
    lateral cap (a towed body's off its solver tensor: `TowedBody._size_lateral_caps`);
  - the semi-implicit spin step;
  - the boat's probe clamps;
  - `VehicleMath.damped_force`.

  Never remove or weaken a clamp; never raise the tick. A damper or drag term takes a clamp; an
  external force (thrust, sail) does not.
- Wheel spin is semi-implicit: divide the NET torque by `1 + reaction_stiffness`. Never cap the
  reaction term instead, which walks the wheel to a steady slip nothing paid for
  (`test_wheel_spin`). The step follows the body's last-tick change at the CENTRE OF MASS
  (`dv_long`), never the contact's, which rings the pitch at the tick rate.
- `RayWheel.FREE_SPIN_DECAY` lets a lifted wheel's limiter cut clear itself. Without it the cut
  latches until the driver lifts off.
- The clamps are sized by `corner_mass`. A runtime `mass` write is `BaseVehicle.set_live_mass`,
  never a bare assignment (it re-shares the corners; `test_body_inertia` pins the pair).
- `ChaseCamera` follows `get_global_transform_interpolated()`, never `global_transform` in
  `_process`.

## Wheels and ground

- Never set `RigidBody3D.inertia`: Jolt computes the tensor about the declared `center_of_mass`, so
  a COM height is pure data. Read the tensor only through
  `PhysicsDirectBodyState3D.inverse_inertia`; `inertia` reads `ZERO` on a computed body. Guard:
  `tests/test_body_inertia.gd`.
- A car-family COM height (`com_y`) stays below ~45 % of the body's AABB height. If a narrow body
  tips before it slides, the levers are the anti-roll bar or `mu_lat`, never a lower COM.
- Anti-roll bar: both wheels of an axle read the snapshot the body's tick (`WheelDrive.tick`,
  `TowedBody.tick_towed`) latches for every wheel before any wheel ticks (`latch_bar`). A live
  read is a phantom left-only damper that steers the car (`test_wheel_spin.test_the_bar_reads_one_shared_snapshot_whatever_the_tick_order`). Size
  a rate with `measure_vehicles -- <variant> 45 corner` (4-8 deg roll), then re-run `track`.
- Suspension force acts along the contact normal, never the chassis up axis, which would push a
  pitched body along. Regression check: `measure_vehicles`' `balance` line.
- Surface drag (`RayWheel.surface_drag_force`) is a body force outside the friction circle and the
  spin step, capped per tick.
- Surface grip multiplies mu and leaves the clamps alone. `channel_grip` is clamped to [0, 1].
  `grip_at` pow-sharpens weights exactly like the splat shader. The wheel takes the nearest surface
  within `SURFACE_GRIP_REACH`, never XZ alone (a bridge would grip like the ice painted under it).
  Use cached decoded images, never `get_image()` per tick.
- `RayWheel.is_rear_z` is the one front/rear predicate (ties go front; `test_vehicle_catalog`
  asserts no wheel station sits at z = 0).
- RayWheel is single-radius; bigger visual wheels are visual only (`wheel_visual_radius`,
  `visual_lift`). Wheel scenes are radius-normalized. Per-instance tweaks ride the visual's
  children (RayWheel overwrites the root). The right-side flip is `Basis(Vector3.RIGHT, PI)`,
  never `UP` (local Y is the axle): `wheel_drive.gd` applies it, trailer scenes author it.

## Drag and downforce

- Drag is declared, never inherited. Every chassis runs `DAMP_MODE_REPLACE` at 0, so a wheeled
  body's resistance is its ground drive's `drag_area` + `rolling_resistance` (N read off the
  springs). A new towed or attached rigid body needs its own resistance call. Free bodies declare
  neither (`test_vehicle_catalog` checks both directions).
- Downforce is a force through the springs, never a grip multiplier. A wing must declare
  `drag_area`, and its `cl` must fit inside the suspension travel at top speed
  (`test_vehicle_catalog` checks both). Re-measure after any change.

## Free bodies (boat, drone, plane)

- Shared helpers live in `VehicleMath`. Add new ones there, not as a fourth copy.
- `air_damper` is a drag path on `vel - wind`, never an angular damper: attitude dampers and the
  boat's `drag_yaw` stay raw `clamped_damper` / `damped_force`. Its `axis` masks WORLD space, so a
  body-frame split (boat windage) cannot use it.
- `flow_authority` is the one control-authority curve. Prop wash is the only difference between
  the boat rudder and the plane surfaces.
- The sail (`BoatSail`) is an external force with no clamp. Its no-go zone emerges from `drag_lat`
  and must never be clamped. `sail_area == 0` keeps the powerboats out of it.

## Towing

- Shared coupling lives in `base/` (`tow_host.gd`, `towed_body.gd`, `articulation.gd`,
  `coupling_profile.gd`); `FifthWheel` and `Drawbar` are only `CouplingProfile`s. Fix a towing bug
  in `TowHost`, never on one machine. No `trailer_type`-shaped accessor: what is on the back shows
  through mass and through what it declares.
- E (`next_attachment`) always cycles the attachment, V (`next_vehicle`) always the body: one key
  for both would do different things per vehicle. `cycle_implement()` is an unconditional `-> void`.
- The trailer is a child of the towing unit's PARENT, never the unit, which would apply the parent
  transform twice.

## Telemetry

- Read `Drivetrain.applied_throttle`, never `input.throttle`: it carries the limiter, governor and
  shift cuts. Only the contract's `throttle` signal is the pedal.
- `engine_load` is divided by `Drivetrain.peak_torque(spec)`, never by the torque at the current
  rpm, which cancels to throttle.
- Contract signals key on the FAMILY: a pre-spawn path holding a variant name maps it through
  `VehicleCatalog.family_of` first (`dashboard.bind()`, `level_baker.validate_spawns`).
- `_reseed_telemetry` copies onto the LIVE object, never a replacement: Dashboard and Bridge cache
  the instance.
- Every member var of a telemetry class IS a wire signal: `to_bridge_dict` walks the property
  list (only the `WIRE_*` tables and the synthesised `slip` are not identity). Guard:
  `test_to_bridge_dict_invents_no_signal`.
- `pto_load` is a parasitic term added to `engine_load`, not real torque. If a real driveline drag
  replaces it, this term goes.

## Lamps

- Lamp and warning bits ride `VehicleInput` and are mirrored verbatim: sloppyCAN is the sole
  authority, an absent bit is off, and there is **no local blink timer** (a lamp flashes because
  the source toggles its bit, J1939-73 DM1 flash rates included). Guard: `tests/test_lamps.gd`
  scans `lamp_set.gd` and `drone_indicators.gd` only.
- Head/brake/turn/LED share one material per group on `material_override`. Markers, flash and
  strobe get a private copy on surface override 0, so `material_override` reads `null` on a
  correctly lit marker (tests use a `_marker_mat()` helper).
- `LampSet` tolerates a missing lamp path silently. Guard: `test_vehicle_catalog` (every variant)
  and `test_trailer` / `test_drawbar_trailer` (every trailer).

## Measuring

- Changed gearing, mass, tyres, wheel positions, a diff, a wing or a governor? Re-measure with
  `tools/measure_vehicles.tscn` (run lines: `tools/CLAUDE.md`; reading guide: `docs/vehicles.md`).
- Spawns put the body at `BaseVehicle.rest_ride_height()` with the wheels just touching, so chassis
  contact at t = 0 is a real problem.

## Rejected — do not re-propose

- `FreeBodyDrive` / `HullBuoyancy`: boat, plane and drone drag share no shape, and buoyancy has one
  consumer.
- `VehicleSpec.air_drive` / `.water_drive`: the vehicle node is already the single home
  (`test_boat_variants` guards the boat's recipe copy).
- A polymorphic `spec.drive`: retires no `null` guard and adds a downcast to each.
- Splitting `Drivetrain` into gearbox and rpm: the gearbox is load-bearing on every family.
  COMPROMISE: the wheel-less bodies run an engine model nothing observes.
- Unifying the four reservoirs (truck air, train brake pipe, drone pack, fuel): four different
  models, two of which gate.
- Merging `TowedBody.Consumer` with `ImplementBase.Connection`: different sets (see the enum
  headers).
- Torque-curve tails on the six curves ending at `(redline, 0)` (the 3200-rpm heavies,
  `tractor-kenney`): they would move tuned top speeds for nothing.
- Open-diff friction (the open diff is an ideal 1.0): bodies that should fight one-wheel peel
  declare an LSD.
- Fixing the floored 2WD tractor in mud: it is the open diff's peel (held at the grip peak it
  climbs 9.2 %); MFWD and the diff lock are the answer.
- Converter torque multiplication to speed launches: under 0.1 s on any body behind its reference
  (`docs/vehicles.md` § Converter).
- Auto-respawn on overturn (`base_vehicle.gd`).
