# 2026-11-12: shared-law audit (a cross-cut, no unit read whole)

Compressed 2026-11-16. For each rule in `CLAUDE.md` and `src/vehicles/CLAUDE.md` that names one
law, predicate or accessor: every site in `src/`, `kit/`, `addons/carlito_kit/`, `tools/` and
`tests/` that computes the same thing another way. The full file:
`git show c903d45:.claude/review_journal/sessions/2026-11-12-shared-law-audit.md`.

Fixed (findings 1 to 8): f5f086b (seven axle splits onto `RayWheel.is_rear_z`), 9aa1612
(`measure_grade._ledger_tick`'s contact velocity on the origin lever), e6ae034 (`TowHost.couple`'s
copy of `point_velocity`), 45a2563 (`drone_air_data`'s `AIR_DENSITY`, `boat.gd`'s copy of
`damped_force`), 6b7b658 (two copies of `moment_about` in `measure_vehicles`), 7374acb
(`debug_overlay`'s copy of `heading_from_forward`), 5149e39 (`engine_load_pct`'s wording).

## Open: finding 9, three inversions of the engine law (Queue)

`Drivetrain.fuel_to_land`, `Drivetrain.drag_fuel` and `PedalMap._row_fuel` each compute
`(net - motoring) / span` with `span = curve - motoring`; `PedalMap.governor_fuel` already calls
`drag_fuel` as "the fuel for a net torque". They differ only where `span <= 0` (`drag_fuel`
returns 0; the other two return 1 when the target is above the motoring law). It touches the fuel
step inside the physics tick and needs the `span <= 0` case decided.

## Checked and left (a different formula on purpose, or out of scope): do not re-flag

- `Drivetrain.retarder_slip_cap` reads `LOW_SPEED_FLOOR`, not the wheel's `slip_floor`: its doc
  says so ("its least floor ... so the cap only tightens"). The retarder's demand is 0 under
  1.5 m/s.
- `Drivetrain._process_crank`'s pull-away cap `fuel * engine_torque(spec, rpm) - accessory_torque`
  leaves the motoring share out on purpose ("the crank sinks to it on its own motoring").
- `Drivetrain.wheel_torque` + `overrun_torque` (the rigid crank's form of the law): the queued
  rigid-crank item.
- `telemetry.throttle = input.throttle` (`base_vehicle.gd`): the contract's pedal, said at the
  site; fuel, coolant and `engine_load` read `applied_throttle`. `WheelDrive.hold_step` and
  `InputRouter.auto_hold` / `brake_override` read the pedal as the driver's intent.
- Boat thrust, plane prop rpm, train traction read the pedal: each is that body's own thrust law.
  No boat, plane or train spec declares `speed_limit_kmh` and only tow hosts set `speed_cap_kmh`,
  so pedal and delivered fuel differ only by the idle floor. For units 23, 25, 26.
- `Bridge.is_active()` outside `src/input/`: `vehicle_select.gd` (MANUAL needs a peer's gear
  byte), `pause_menu.gd` `_lab_off_reason`, and the three `ActionRegistry.context(..)` callers
  pass both. Each asks "is a peer connected", none "who drives".
- Ray masks: every gameplay ray masks `Layers.SOLID`; no `.tscn` overrides the camera's. The four
  authoring rays are unmasked on purpose (`src/physics/CLAUDE.md`).
- `b.transposed() * state.inverse_inertia_tensor * b` is in `wheel.gd` `size_cap_masses`,
  `tractor.gd` `hitch_effective_mass` and `measure_vehicles.gd` `_body_tensor`: three one-line
  copies, each naming the first. A helper would be new code for one line.
- `train_sim.gd` `coupler_force`'s damper is `damped_force` with the sign mirrored: analogous, not
  identical. `articulation.gd`'s Coulomb cap and the wheel's damper are other laws.
- `balance_model.gd` `_corner_state` restates `air_force` for a steady turn in still air, on
  `VehicleMath.AIR_DENSITY`, gated on `drag_area > 0` as `WheelDrive._apply_resistance` is.
- `VehicleCatalog.family_of`: every pre-spawn variant reader maps through it.
- `declare_angular_damp`: `base_vehicle.gd` and `towed_body.gd` only. `inertia` is written once
  (`base_vehicle.gd` `_declare_yaw`, yaw only).
- `VehicleMath.pitch_deg` / `roll_deg` have no second copy in `src/`.
- `boat.gd`'s `p_local.z > 0.0` is a hull probe (stern wet), not an axle split.
