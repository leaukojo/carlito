# 02 — Engine torque model: a fuel cut must brake

Shared context: `00_README.md`. Root cause 1 (engine as a torque source). Size: small.

## Summary

When the rev limiter or the governor cuts fuel, the engine makes **zero** torque. A real engine
with its fuel cut is being driven by the wheels and makes **negative** torque (friction and
pumping: engine braking). Engine braking here exists only at exactly 0 pedal, and only the shift
cut honours that. Results: a governed truck going downhill with the pedal down runs faster than
with the pedal up; a lifted driven wheel latches in the limiter cut (patched by
`FREE_SPIN_DECAY`); the axle torque steps when an analog pedal goes from 1 % to 0 %.

## What happens

`src/vehicles/base/drivetrain.gd`:
- `process` (~lines 336-408): `applied_throttle = pedal * governor_scale(...)`, zeroed by
  `limiter_cut`, zeroed by the shift cut. Return value:
  `(wheel_torque(rpm, applied_throttle) + overrun_torque(rpm, pedal)) * clutch`.
- `overrun_torque` (~line 164): 0 for **any** throttle above 0 (a hard edge), else
  `-engine_brake_frac * peak * rpm01 * ratio / efficiency`, with `rpm01` linear from 0 at idle
  to 1 at redline.
- The overrun reads the **pedal**, not the delivered fuel (comment ~line 397: "a governed or
  limited engine with the pedal down is not on overrun"). The shift cut sets `pedal = 0`, so it
  does get engine braking (~lines 403-406). Three fuel cuts, two behaviours.

`src/vehicles/base/wheel.gd`:
- `FREE_SPIN_DECAY` (~line 31) exists because "a lifted wheel has no resisting torque once the
  limiter cuts the throttle (`Drivetrain.overrun_torque` reads the still-down pedal), so `omega`
  freezes at the tripping value and the cut never clears."

Rules that state today's behaviour (`src/vehicles/CLAUDE.md` § Drivetrain and brakes): "The
limiter and engine braking are hard edges: a fade band eats drive torque below redline and moves
top speeds." That rule is about a fade band **below redline**; the blend below creates none.

## Why it is wrong

- A full-throttle torque curve is already net of friction. The usual model is
  `T = f * T_wot(rpm) + (1 - f) * T_motoring(rpm)`, where `f` is the **delivered** fuel fraction
  (after limiter, governor and shift cut) and `T_motoring` is negative. At `f = 1` it equals the
  curve, so a top speed set by drag, or by a curve that droops to 0 at redline (the diesels), does
  not move. A body that sits on the limiter now cycles between drive and engine braking instead of
  drive and nothing, so its top speed may shift slightly: re-measure.
- Governor, from the code (not measured): at the limit the governor takes `f` to 0, the pedal is
  still down, so no overrun: the truck freewheels down the hill. Lifting the pedal brings overrun
  and slows it. That is backwards.
- Hard edge: with analog input (bridge, gamepad), 1 % pedal at high rpm gives +1 % of the curve,
  where under the blend it gives 1 % of the curve minus 99 % of the motoring torque (net engine
  braking). Releasing that last 1 % is a torque step.

## What it would retire or re-examine

- `RayWheel.FREE_SPIN_DECAY`: the limiter-latch reason disappears. Whether a small constant stays
  as an honest bearing and tyre loss on a lifted wheel is the planner's call.
  Its guards: `test_wheel_spin.test_a_free_wheel_falls_below_a_tripped_rev_limiter_within_a_few_ticks`
  and `test_wheel_spin.test_a_free_wheel_sheds_spin_and_never_reverses_or_gains`; its rule in
  `src/vehicles/CLAUDE.md` § The 60 Hz tick ("`RayWheel.FREE_SPIN_DECAY` lets a lifted wheel's
  limiter cut clear itself. Without it the cut latches until the driver lifts off").
- The "Overrun reads the PEDAL" comment-rule and its tests in `tests/test_drivetrain.gd`
  (`test_overrun_is_zero_with_any_throttle_in_neutral_and_at_idle`,
  `test_process_on_overrun_returns_negative_torque_with_no_load`,
  `test_overrun_signed_against_the_gear_and_scaled_by_ratio_and_rpm`): their intent survives, the
  "any throttle gives 0" part changes.

## Constraints

- Keep: overrun signed against the gear's rolling direction, 0 in N, divided by efficiency (a load
  the engine absorbs pays the driveline loss the other way).
- The shift cut stays "a lift" (it already is, under the blend).
- Telemetry (root rule 3): `applied_throttle` feeds fuel, coolant, battery and `engine_load`
  (`VehicleTelemetry.engine_load_pct`). A motoring engine burns no fuel, so `applied_throttle`
  stays the fuel fraction. J1939 negative percent torque is "deliberately not modelled"; whether a
  bus signal shows motoring is a contract decision (`contract-edit` skill) for the user.
- Traction control already holds a negative drive (overrun) on its own side
  (`RayWheel._integrate_spin`); it will see more negative-drive ticks. Check it.
- Governed bodies may settle at a slightly different speed, because engine braking now enters the
  governor band. Re-measure them: `van`, `pickup`, `pickup-flat` (180), `ambulance` (150),
  `garbage-truck` (85), `firetruck` (110), `semi` (90), `semi-conventional` (105),
  `tractor-kenney` (40).
  `Drivetrain.governed_upshift` logic is otherwise unaffected.
- The runtime road-speed cap (`Drivetrain.speed_cap_kmh`, which `TowHost.speed_cap_kmh` sets to
  5 km/h while a tipping body is up) goes through the same `governor_scale`, so it gains engine
  braking too.
- The coast-down pass of `measure_vehicles` (`coast`) prints a model line built on
  `Drivetrain.overrun_torque` (`docs/vehicles.md` § Measuring a vehicle); it moves with the model.
- Brief 05 (engine inertia) integrates crank speed from this net engine torque. Defining it here
  first keeps 05 smaller; merging 02 into 05 is acceptable if the planner prefers.

## Done

- One engine-torque law in terms of delivered fuel fraction: limiter, governor, shift cut and a
  released pedal all reduce the fraction, and fraction 0 is engine braking.
- A governed vehicle descending at its limit gets engine braking with the pedal down; a lifted
  driven wheel at the limiter slows by itself.
- Drag-limited top speeds unchanged; limiter-bound and governed settle speeds re-measured and
  documented.
- Tests state the new law; `docs/vehicles.md` and the `src/vehicles/CLAUDE.md` rules ("hard
  edges", "Overrun reads the PEDAL") rewritten.

## Open decisions (user)

- Motoring torque shape: keep `engine_brake_frac * peak * rpm01` (0 at idle, which matches an
  idle governor fuelling to hold idle) or a friction curve.
- Whether `FREE_SPIN_DECAY` stays as an explicit bearing loss.
- Whether motoring shows on the bus.

## Related

Brief 05 (crank speed integrated from a torque balance, which needs this net torque). The
`docs/TODO.md` item "Diesel governor and hand throttle" (the pedal as an engine-speed target)
builds on this law.
