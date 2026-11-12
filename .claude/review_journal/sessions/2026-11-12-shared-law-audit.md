# 2026-11-12: Shared-law audit (Queue item)

Started at 0379d46. Read-only but for S fixes. For each rule in `CLAUDE.md` and
`src/vehicles/CLAUDE.md` that names one law, predicate or accessor, every site in `src/`, `kit/`,
`addons/carlito_kit/`, `tools/` and `tests/` that computes the same thing another way, found by
grep and read at the site. Not read whole: any unit (this is a cross-cut, no `Reviewed at` moves).

## Findings

1. **`measure_grade.gd` `_ledger_tick`: contact velocity on the origin lever (S, a bug).**
   `var vel := b.linear_velocity + b.angular_velocity.cross(w.contact_point - b.global_position)`.
   `linear_velocity` is the COM's, so the lever runs from the COM: `VehicleMath.point_velocity`'s
   own doc ("on a body whose COM sits off its origin the origin lever is out by
   `angular_velocity x (com - origin)`"). Every wheeled body declares a `center_of_mass` off its
   origin. It feeds the descent ledger's `rolling` and `slip` columns; a straight descent has
   almost no body rate, so the figures barely move. `measure_vehicles.gd` `_split_deficit` already
   calls the helper.
2. **`tow_host.gd` `couple`: a second copy of point velocity (S).** `lever := trailer COM - chassis
   COM; trailer.linear_velocity = chassis.linear_velocity + chassis.angular_velocity.cross(lever)`
   is `VehicleMath.point_velocity(chassis, trailer COM)`, same operands in the same order.
3. **Seven axle splits beside `RayWheel.is_rear_z` (S).** Its doc: "Every axle split goes through
   this so no station is front to one site and rear to another."
   - `tools/gen_kenney_vehicles.gd` `_wheel_positions`: `if p.z < 0.0` (front), one line under
     `gd.axle_radius(RayWheel.is_rear_z(xz.y))`: a station at z == 0 takes the front radius and
     the rear slot. `_measure…` wheel half: `wheel_models[0 if tw.z < 0.0 else 1]`, same.
   - `tools/measure_semi_launch.gd` `_apply_geometry_override`: `positions[i].z < 0.0`.
   - `tests/test_truck.gd` (`_rear_count`, the retarder case), `tests/test_trailer.gd`,
     `tests/test_tractor.gd` (twice): `p.z > 0.0` / `pos.z < 0.0`.
   No shipped station sits at z == 0 (`test_vehicle_catalog` sweeps for it), so no output moves.
   `boat.gd`'s `p_local.z > 0.0` is a hull probe (stern wet), not an axle: left.
4. **`drone_air_data.gd`: `const AIR_DENSITY := 1.225` (S).** A second home for
   `VehicleMath.AIR_DENSITY`; `boat_sail.gd` aliases it (`const RHO_AIR := VehicleMath.AIR_DENSITY`).
5. **`boat.gd` `probe_force`: a copy of `VehicleMath.damped_force` (S).**
   `tick_cap := probe_mass * absf(vert_vel) / delta; damper := clampf(-damp * vert_vel, -tick_cap,
   tick_cap)` is `damped_force(vert_vel, damp, probe_mass, delta)` (`coeff_sq` 0).
6. **`measure_vehicles.gd`: two copies of `VehicleMath.moment_about` (S).**
   `1.0 / right.dot(state.inverse_inertia_tensor * right)` (pitch-transfer reading) and
   `1.0 / up.dot(state.inverse_inertia_tensor * up)` (`_yaw_index`).
7. **`VehicleTelemetry.engine_load_pct`: "delivered torque over peak torque" (S, wording).** The
   code is `engine_torque(rpm) * throttle / peak`: the full-load curve at the delivered fuel. On
   the one engine law the torque delivered at that fuel is `f * curve + (1 - f) * motoring`
   (`Drivetrain.crank_torque`); `fuel_rate_lph` beside it reads `f * (curve - motoring)`.
   Not proposed as a formula change: standing rule 3 lists `engine_load` as a simple labelled
   model, so the label is what must be exact.
8. **`debug_overlay.gd` `_flow_line`: a copy of `VehicleTelemetry.heading_from_forward` (S).**
   `fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)`, the helper's body to the character.
9. **Three inversions of the engine law (M, queued).** `Drivetrain.fuel_to_land`,
   `Drivetrain.drag_fuel` and `PedalMap._row_fuel` each compute `(net - motoring) / span` with
   `span = curve - motoring`; `PedalMap.governor_fuel` already calls `drag_fuel` as "the fuel for a
   net torque". They differ only where `span <= 0` (`drag_fuel` returns 0; the other two return 1
   when the target is above the motoring law).

## Checked and left (a different formula, on purpose or out of scope)

- `Drivetrain.retarder_slip_cap` reads `LOW_SPEED_FLOOR`, not the wheel's `slip_floor`: its doc
  says so ("its least floor ... so the cap only tightens"), and a smaller denominator does lower
  `headroom`. The retarder's demand is 0 under 1.5 m/s. A third reader of the constant beside the
  queued slip-floor item's two; nothing to change.
- `Drivetrain._process_crank`'s pull-away cap `fuel * engine_torque(spec, rpm) - accessory_torque`
  leaves the motoring share out on purpose: capped there, the crank's net is `(1 - f) * motoring`,
  which is the comment's "the crank sinks to it on its own motoring".
- `Drivetrain.wheel_torque` + `overrun_torque` (the rigid crank's form of the law): the queued
  rigid-crank item.
- `telemetry.throttle = input.throttle` (`base_vehicle.gd`): the contract's pedal, said at the
  site; fuel, coolant and `engine_load` read `applied_throttle`. `WheelDrive.hold_step` and
  `InputRouter.auto_hold` / `brake_override` read the pedal as the driver's intent.
- Boat thrust (`thrust_scale(input.throttle, ..)`), plane prop rpm, train traction read the pedal:
  each is that body's own thrust law, not the engine law. No boat, plane or train spec declares
  `speed_limit_kmh` and only tow hosts set `speed_cap_kmh`, so pedal and delivered fuel differ
  only by the idle floor. For units 23, 25, 26.
- `Bridge.is_active()` outside `src/input/`: `vehicle_select.gd` (MANUAL needs a peer's gear
  byte), `pause_menu.gd` `_lab_off_reason` ("a live bridge (fallback included)"), and the three
  `ActionRegistry.context(.., Bridge.is_active(), .., InputRouter.bridge_drives())` callers pass
  both. Each asks "is a peer connected", none "who drives". `Bridge.get_input_values()` has one
  reader, `bridge_source.gd`.
- Ray masks: every gameplay ray masks `Layers.SOLID` (`wheel.gd`, `chase_camera.gd`,
  `drone_hook.gd`, `drone_sensors.gd`, `three_point_hitch.gd`, `level.gd`); no `.tscn` overrides
  the camera's. The four authoring rays are unmasked on purpose (`src/physics/CLAUDE.md`).
- `b.transposed() * state.inverse_inertia_tensor * b` (the body-frame inverse tensor) is in
  `wheel.gd` `size_cap_masses`, `tractor.gd` `hitch_effective_mass` and `measure_vehicles.gd`
  `_body_tensor`: three one-line copies, each naming the first. No fourth; a helper would be new
  code for one line.
- `train_sim.gd` `coupler_force`'s damper is `damped_force` with the sign mirrored
  (`clampf(damp * rel_vel, ..)`); analogous, not identical. `articulation.gd`'s Coulomb cap, the
  wheel's damper and `surface_drag_force` clamps are other laws (a constant force, a share).
- `balance_model.gd` `_corner_state` restates `air_force` for a steady turn in still air, on
  `VehicleMath.AIR_DENSITY`, gated on `drag_area > 0` as `WheelDrive._apply_resistance` is.
- `VehicleCatalog.family_of`: every pre-spawn variant reader maps through it (`level.gd`,
  `level_info.gd`, `challenge_def.gd`, `vehicle_select.gd`).
- `declare_angular_damp`: `base_vehicle.gd` and `towed_body.gd` only; no other body sets
  `angular_damp`. `inertia` is written once (`base_vehicle.gd` `_declare_yaw`, yaw only).
- Pitch and roll: `VehicleMath.pitch_deg` / `roll_deg` have no second copy in `src/`.

## Fixed

- f5f086b: finding 3. `gen_kenney_vehicles.tscn` re-run after it: 19/19 variants written, no
  file changed.
- 9aa1612: finding 1. `measure_grade -- semi descent` (lone, `--fixed-fps 60`) before and after:
  only the four stop rows' `tyre slip` moves (0.583 to 0.580, 0.581 to 0.579 twice, 0.618 to
  0.616 MJ) and their closure reads 1.000 where it read 1.001; every row PASS both ways. No doc
  quotes those figures.
- e6ae034: finding 2. 45a2563: findings 4 and 5. 6b7b658: finding 6. 7374acb: finding 8.
- 5149e39: finding 7, with the guide's source comment that quotes it
  (`docs/guide/auxiliary.md`).

Full suite after the fixes: 2422 cases, 0 failures. `measure_vehicles -- sedan 60 step` and
`measure_semi_launch -- semi` run clean (the tests load neither).

## Deferred

- Finding 9, to the Queue: it touches the fuel step inside the physics tick and needs the
  `span <= 0` case decided.
