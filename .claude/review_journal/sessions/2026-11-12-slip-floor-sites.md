# 2026-11-12: The slip floor's two sites (Queue item)

Started at 02ee005. The item: `sessions/2026-11-12-wheels-3a.md`, finding 8 and § Decision. No unit
read whole, so no `Reviewed at` moves.

## Part 1: the airborne wheel reads the body's floor

`RayWheel.tick`'s off-the-ground `_integrate_spin` call stops at ten arguments, so its ABS floor and
TC ceiling take the default `floor_vel := LOW_SPEED_FLOOR`; the grounded call passes
`maxf(slip_floor, _own_slip_floor)`.

Baseline at 02ee005, lone run (`measure_grade.tscn -- suv-luxury asphalt mud`, `--fixed-fps 60`):
asphalt 42.2 deg (90.6 %), mud 19.3 deg (35.1 %).

Fix (574a31f): the call passes `slip_floor` as its eleventh argument (the body's, shared by
`size_cap_masses`; the wheel's `_own_slip_floor` is stale off the ground). New case
`test_tcs_holds_a_lifted_wheel_on_the_body_s_slip_floor`: a lifted driven wheel under TC on a body
at rest with `slip_floor = 4.0`. Before the fix it read 0.497917 rad/s (`0.12 * 1.5 / 0.36`, one
tick of free-spin decay) against the expected 1.327778 (`0.12 * 4.0 / 0.36`); after, it passes.

After, same lone run: asphalt 42.2 deg (90.6 %), mud 19.3 deg (35.1 %). No figure moves, so
nothing goes to the doc or to "Please verify". Not measured: which shipped bodies raise the floor
past 1.5 m/s, and any run that lifts a driven wheel under TC or ABS below that speed (a standing
climb on a uniform ramp lifts none).

## Part 2: `road_change` keeps the constant, and says so

No code change (565c065). Three texts said "the slip floor" for
`clampf(absf(v_long) / LOW_SPEED_FLOOR - 1.0, 0.0, 1.0)`:

- `wheel.gd`, `road_change`'s doc: "Faded out from twice the slip floor down to it ... below the
  floor slip is read against the floor" now names `LOW_SPEED_FLOOR` and says a body's raised
  `slip_floor` does not widen the fade.
- `docs/vehicles.md` § Following the body: "Below twice the slip floor" now reads "Below twice
  `LOW_SPEED_FLOOR` (the constant, not a body's raised slip floor)".
- `tests/test_wheel_spin.gd`, the fade case: "Twice the slip floor and up" now reads "Twice
  LOW_SPEED_FLOOR and up" (the case already used the constant).

Reopen only if a run shows a tick-rate ring between 1.5 m/s and a raised floor.

## Verification

`test_wheel_spin` 140 cases, 0 failures after part 1; full suite 2423 cases, 0 failures after
part 2; `check_docs` clean.
