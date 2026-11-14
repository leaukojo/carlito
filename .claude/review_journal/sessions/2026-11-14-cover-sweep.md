# 2026-11-14: the cover sweep (Fable, diagnose only)

Started at 088c354. Sorts every hit of the skill's § Covers "where they sit" list in
`src kit tools tests` into model / cover / dead. Nothing is proved or fixed here: each cover's
Queue line starts with its proving run.

## How it was searched

`grep -rInE` over `*.gd` for `lerp`, `move_toward`, `smooth`, `hyster`, `deadband`, `snapped`,
`is_zero_approx`, `maxf(…, 1e-`, the comment words (`avoid`, `hide`, `flicker`, `jitter`,
`workaround`, `stability`, `chatter`, `oscillat`, `alternat`, `ring`, `noise`, `spike`, `glitch`,
`first tick / frame`, `skip the`, `retry`, `two-tick`, `averag`), every `const` named `*EPS*`,
`*FLOOR*`, `*SMOOTH*`, `*TAU*`, `*FILTER*`, `*HOLD*`, `*SETTLE*`, `*MARGIN*`, `*LEAK*`, `*TOL*`,
`*DEAD*`, and body or level names in an `if`. Each hit in `src/vehicles/base`, `truck`,
`tractor`, `src/ui` and `tools/measure_*` was read at its site.

Not read one by one, and left to each unit's review:

- the 49 `maxf(x, 1e-N)` denominators (the 20 in the land vehicles were read as a list: guards
  on a spec value or on `delta`, none on a value the sim produces);
- test tolerances and settle waits, which no word marks: `tests` was searched by comment word and
  by commit message (`git log -i --grep='widen\|loosen\|tolerance\|flak\|settle' -- tests`: four
  commits, none widening a tolerance);
- BETA units (drone debounces, the train's Davis clamp, the boat autopilot's `HELM_DEADBAND`):
  read at the comment only, all name a real controller or a one-tick clamp;
- `kit/` and `src/levels/`: every hit is authoring math (bilinear lookups, brush falloff, scatter
  jitter) or a camera-following snap of a ground plane.

No body or level name sits in an `if` in the vehicle code (`level.gd:455`'s `family == "train"`
is the spawn's rail placement).

## Covers (one Queue line each)

1. **`VehicleMath.RESIST_EPS`** (`vehicle_math.gd:138`, read at `:200`). "m/s floor below which
   resistance isn't applied (stops jitter)": the only reason is a symptom. `air_force` is the one
   reader; each axis is already one-tick clamped (`minf(…, body_mass * absf(u) / delta)`) and
   `signf(0) = 0`, so the force cannot reverse a velocity. Derived, not measured: at 0.05 m/s the
   drag is `0.5 * 1.225 * cda * 0.0025`, about 0.0015 N per m2 of `cda`. Probably dead.
2. **`measure_vehicles._sample_gates`' two-tick means** (`tools/measure_vehicles.gd:1812-1822`
   `over`, `:1828-1833` `xfer_mean`). "Under the tyre's LOW_SPEED_FLOOR a take-up's drive force
   alternates at the tick rate, which the body cannot follow and a steady reference must not
   chase." The gate averages the fault out of its own reading. Source: the proposal "The wheel
   and the body exchange one force" (`road_change`'s fade and the slip floor's alternation).
   `docs/handling.md:94` and the report line (`:2040`) say "two-tick mean".
3. **`measure_vehicles.CORNER_SMOOTH_S`** (`:64`, applied at `:2475`, `:2493`, `:2502`). A 0.25 s
   lag on `v * yaw_rate`, on the tyres' side force and on `telemetry.acc_lat` (already lagged by
   `ACCEL_SMOOTH`: smoothed twice) before the peak is taken; no reason given anywhere (it came
   with 07c3cbc "tyre feel"). The pass prints "smoothed" and "that tick" side by side at the tip
   and saturation ticks only, never for the peak the `doc=cornering` table carries.
4. **`MeasureRig.ESC_CHATTER_EPS`** (`tools/measure_rig.gd:272`). "a change under 0.5 % of a
   wheel's brake (~7 N·m on `van`) is the sensors' per-tick noise on a held touch":
   `tests/test_measure_chatter.gd:42` pins the case ("±0.0003 on a 0.011 share flips past 1 % of
   it"). An ESC whose inputs are steady does not flip its torque tick to tick; which input
   (`yaw_rate`, `lat_acc`, `_slip_est`, the steer mean) alternates on a held touch is not traced.
   `CHATTER_EPS` (1e-7 rad) and `CHATTER_REL` beside it are float-noise floors with a dated
   measurement: models.
5. **`TractorTelemetry.SLIP_FLOOR_KMH`** (`tractor_telemetry.gd:21`, `:95`; contract
   `wheel_slip`). "Wheel speed below which slip reads 0 (the ratio is noise near zero)";
   `test_tractor.gd:101` repeats it. A snap to zero on a contract signal with a symptom for a
   reason. Two things can be behind it: the ratio's own 0/0 at rest (a floor a real radar unit
   also has, and then it is a model wanting a source), and a standing tractor's wheel speed
   moving against a still body (the free wheel's ring of `proposals.md`), which would read up to
   100 %.
6. **`Articulation.YAW_CAP_SHARE`** (`articulation.gd:9-12`). "the towed tyres' caps stop the same
   yaw in the same tick, so a whole share makes a standing rig buzz". The cause is named and
   `test_a_coupled_rig_standing_still_stays_mirror_symmetric` guards the fault itself, but the
   half is a guess standing in for a shared cap: the plate and the tyres each size a one-tick
   stop on the same relative yaw without knowing of the other, the fault d849de9 fixed between
   the rolling drag and the tyre force with `taken`. With the tyres deadbeat and the plate at
   half, the pair still overshoots by half each tick (derived, not measured); and a turning rig's
   plate friction is cut to half its declared torque wherever the cap binds.
7. **`RayWheel.road_change`'s fade** (`wheel.gd:1134-1141`). "following the body rings it at the
   tick rate" below `LOW_SPEED_FLOOR`. Already in `proposals.md` (same proposal as 2): no new
   line.

Already recorded, no new line: `BaseVehicle.ACCEL_SMOOTH` and `TowedBody.accel_lat`'s borrow of
it (`proposals.md`); `measure_semi_launch`'s `REST_FLIPS_S` / `REST_STEP_KG`, sized over the free
wheel's ring and due down with it (`proposals.md`).

## Models (the reason names the machine, the driver or the integrator)

- One-tick caps and their kin, which `src/vehicles/CLAUDE.md` forbids weakening:
  `wheel.gd:527-532` (long and lateral caps), `STICK_TICK_STIFFNESS`, `surface_drag_force`'s cap,
  `air_force`'s per-axis clamp, `HELD_SHARE` (0.998, "just inside the settle's Coulomb check"),
  `slip_floor_for`, `load_scaled_mu`'s clamp ("bind on nothing shipped").
- Actuators and hardware with a travel time: `KeyShaper`, `_steer`'s `steer_speed`,
  `TowedBody.BRAKE_APPLY_S` / `BRAKE_RELEASE_S` (air reaching the chambers), the hitch, tippers,
  spreader gate, refuse arm, tanker surge, `FREE_SPIN_DECAY` (bearing loss, 4 s), the pad's
  dead zone.
- Controllers a real unit has: `StabilityControl`'s dead-band, `SLIP_LEAK_S`,
  `LAMP_RELEASE_DECEL` (R13), `TRAILER_RATE_FILTER_S`, `GOVERNOR_BAND`, `CVT_LOAD_TAU_S`,
  `CVT_RANGE_HYSTERESIS`, `ShiftPolicy.KICKDOWN_HOLD_S` and `LOAD_FILTER_S`, `HillHold.REST_SPEED`.
  Most say "estimate"; none claims a source it lacks. `TRAILER_RATE_FILTER_S` differentiates
  `accel_lat`: it is re-read when the `ACCEL_SMOOTH` proposal lands.
- Stand-ins labelled as such: the rigid crank's `RPM_SMOOTH`, `COOLANT_RATE`.
- Definitions, not readings: `MOVING_SPEED` (a bit needs a threshold; unsourced),
  `IMPACT_THRESHOLD` and the impact's peak-hold (it keeps a transient visible, the opposite of a
  cover), `OVERTURNED_S`.
- Display and shell: the chase camera's follow lag (a camera, not an instrument),
  `vehicle_select.SETTLE_FRAMES` and `boot.HOLD_FRAMES` (each names its cause: wheel poses and
  coupling land a tick late; the renderer compiles shaders on first draw).
- The tippers' `RAISED_ON` / `RAISED_OFF` and `_swap_collision` "only when the answer changes":
  the cause is named (a re-transformed shape rebuilds the compound and its inertia), and the
  input it guards against is a commanded spool, not a sim value.
- Tools: `measure_grade.DECEL_FILTER` (the test driver's foot, a PI's input), `PITCH_TRIM` and
  the settle-then-average windows (a steady figure excludes its transient by definition).

## Dead

None proved. Finding 1 is the candidate.

## Fixed

Nothing (diagnose only).

## After the report (user, same session)

- `ACCEL_SMOOTH`: approved, raw. Its proposal left `proposals.md` for the Queue (Opus).
- Fable's credits are short: the Queue now opens with Fable's items in order of worth (the wheel
  and body exchange first, as the source behind covers 2, 5 and 7; then the coupling's caps,
  which takes cover 6 with the towing wheel's `taken`; then `scrape onebody`). Each reads its
  unit's source files whole and leaves that unit's findings, so no unit is read on Fable twice.
