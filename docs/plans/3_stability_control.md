# Plan — Electronic stability control (ESC), and roll stability on the semis

The road bodies carry ABS and traction control (`GroundDriveSpec.abs_equipped`, `tcs_equipped`)
but nothing that brakes a single wheel to correct the yaw: a lift-off or a too-fast bend spins or
ploughs exactly as with no electronics. ESC compares the yaw rate the driver asks (steer and speed
through the body's own understeer gradient) with the yaw rate measured, and brakes one wheel (the
outer front against oversteer, the inner rear against understeer) and trims the engine. On the
semis the same controller adds roll stability: past a lateral-acceleration threshold under the
rig's tipping point, it brakes the rig and cuts the engine.

Written 2026-10-23. Status: **not started.**
Serves: the oversteer / understeer and yaw lesson, made visible by switching ESC off; an ESC-active
lamp and an ESC-off switch on the bus beside `tcs_off`.
State: done — nothing; next — phase 0; open findings — none.

The brake heat model has landed (`BrakeThermal`, `docs/vehicles.md` § Brake hardware): ESC's
brake use heats the brakes through it with no extra code.

## Decisions for the user (asked in phase 0)

1. **Switch.** One switch for TCS and ESC (SETTINGS ▸ TRACTION CONTROL becomes STABILITY CONTROL,
   the bridge's `tcs_off` covering both), or a separate `esc_off` input (the `contract-edit`
   skill), as many cars split a short press (TCS) from a long one (ESC).
2. **Equipment.** Proposed: every ABS road body (cars, vans, Kenney trucks, semis) takes ESC;
   `race`, `race-future` and the tractor do not (no ABS, or no road ESC on the machine).
3. **Handbrake.** ESC stands down while the handbrake is pulled (the J-turn stays a teachable
   manoeuvre) or keeps acting. Measured both ways in phase 4 before the user picks.
4. **Trailer.** The semi-trailer's own roll stability (its EBS, over ISO 11992) is in this plan or a
   later one. Proposed: later; this plan brakes the trailer only through the existing
   `trailer_brake_demand`.

## Phase 0 — Sources and decisions (effort: high; mode: plan-mode-first)

From pages actually opened, or labelled estimates:
- the regulated ESC test and its pass criteria: FMVSS 126 / UN R140's sine with dwell (yaw rate
  decay after the steer, lateral displacement), for cars and light vans; UN R13 Annex 21's
  heavy-vehicle stability function for the trucks and semis;
- the control structure a real ESC uses: the yaw-rate reference off a linear bicycle model,
  bounded by what the measured lateral acceleration can carry; the body slip angle estimate and its
  threshold; the deadband that keeps it out of normal driving;
- J1939's vehicle-dynamic-stability messages (the VDC PGNs), to set the truck's signals if they
  are in scope.
- The four decisions above, asked once, recorded here.

## Phase 1 — `StabilityControl`, pure and tested (effort: high; mode: plan-mode-first)

- A new `StabilityControl` class in `src/vehicles/base/`, static functions only (root rule 8), on the sensors a
  real unit has: speed, mean steer angle (`WheelDrive.mean_steer_angle`), yaw rate, lateral
  acceleration, wheel speeds. Never the sim's true body slip: an estimate from those sensors, as
  the real one does.
  - `reference_yaw(speed, steer, wheelbase, k_us, lat_acc)`: `v δ / (L + K v²)`, bounded by
    `|a_y| / v` plus a margin. `K` must be the body's real steady K, or ESC reads an understeer
    error in every steady bend: `BalanceModel.understeer_gradient` (the linear K) runs 0.16-0.31
    deg/g under the measured (`docs/handling.md` § Balance), so it cannot be the reference. Phase 1
    picks, with the user, between a per-body calibration on the spec (`esc_reference_k`, the step
    pass's measured K, as a real unit is calibrated on its car) and the corner model
    (`BalanceModel.corner_limit`'s turn, which reads K within 0.02 deg/g at low lock).
  - `intervention(yaw_err, slip_est, ...)`: which wheel, how much brake torque (proportional on
    the error past the deadband, its rise limited by a modulator pressure-rise rate, sourced or a
    labelled estimate), and the engine trim. Proportional and continuous: not the cycling or
    peak-following ABS/TC that `docs/vehicles.md` § Rejected designs turns down.
- Its gdUnit4 test file: inside the deadband it does nothing; oversteer picks the outer
  front, understeer the inner rear, either sign of turn; the reference's bound; the torque never
  past the wheel's declared brake.

## Phase 2 — Wire it in (effort: high; mode: plan-mode-first)

- Brake: `WheelDrive.tick` adds the chosen wheel's torque to its `brake_t` with ABS still on, so it
  is solved inside the spin step with the differentials, as every wheel torque is
  (`src/vehicles/CLAUDE.md` § Physics); the driver's pedal and ESC's torque add, capped at the
  hardware.
- Engine: a cap in the delivered-fuel chain beside the limiter and the shift cut, so the one
  engine law sees it on `Drivetrain.applied_throttle` (never the pedal); `ShiftPolicy` keeps
  reading the driver's demand.
- The 60 Hz loop: the yaw loop runs through the body's yaw inertia, slower than ABS's; the step
  pass's `chatter_runs` is the guard. A ring is solved in the controller's law, never by a filter
  that delays the correction.
- Equipment by a `GroundDriveSpec` flag beside `abs_equipped` / `tcs_equipped` (`esc_equipped`,
  default off), set in `tools/gen_kenney_vehicles.gd` + regen (the `vehicle-feel` skill) and the semis'
  `.tres`. The switch per decision 1 flows through `InputRouter` into `VehicleInput` (root rule 5),
  as `tcs_off` does.

## Phase 3 — Roll stability on the semis (effort: high; mode: plan-mode-first)

- A lateral-acceleration threshold under the rig's tipping point: past it, brake the tractor,
  send the trailer its demand through `trailer_brake_demand`, and cap the fuel. `BalanceModel.tip_g`
  reads one body's axle model, not a coupled rig, and a laden semi tips on its trailer: the
  threshold comes from phase 0's sources or the laden rig's measured tip in the corner pass, keyed
  on the coupled load the unit already knows (`WheelDrive.brake_load_kg`, EBS load sensing). A
  labelled estimate if neither holds.
- Done when: the bobtail and laden semis' tipped cells in the corner and step passes either hold or
  slow to the threshold, with no new chatter.

## Phase 4 — Telemetry, measurement, docs (effort: medium; mode: accept-edits)

- An ESC-active status bit (and the switch, per decision 1) through the `contract-edit` skill;
  the dashboard lights its tell-tale off the contract.
- Every measure tool gains a `noesc` flag, as `notc` is. The chassis tables (`doc=steer`, the
  corner pass, the K and balance figures) stay recorded with ESC off, their presets setting
  `noesc` themselves, since they measure the chassis; ESC's effect is its own table. ESC retires no handling COMPROMISE (the lift-off
  `rear_lat_grip` patches, `docs/handling.md` § Balance): they stand in for unmodelled chassis
  effects and are judged with ESC off.
- `measure_vehicles` gains a `sine` pass (sine with dwell at phase 0's steer amplitude and speed),
  reporting its criteria, on the bodies inside the regulation's mass range (cars, vans); the trucks
  are judged on phase 0's heavy-vehicle test if sourced, else on the step pass. Re-run with ESC on
  and off (background, `--fixed-fps 60`; a baseline at HEAD first, like with like):
  `-- doc=steer` (the step pass's spun and tipped cells), `-- <variant> 60 corner`, `-- <variant> 30
  handbrake` (decision 3), and `-- doc=accel` and the cruise tables to show ESC stays out of
  normal driving.
- Done when: every ESC body inside the sine pass's range passes it with ESC on, the step pass's
  lifted spins drop with ESC on and are unchanged with it off, the steady tables do not move, and
  the model goes into `docs/handling.md` (a new Stability control section) with its figures in
  `docs/vehicle_measurements.md` as a generated `<!-- measure:<id> -->` region (a `doc=<id>`
  preset), never loose figures: `tools/check_docs.mjs` holds the loose-figure count at its cap,
  and the top-level docs had 3 lines of headroom when this was written (trim, or the user raises a
  cap).
- The user drives `car_arena`'s wet bend and skidpad with ESC on and off for feel.
