# 2026-11-12: Unit 2b, `tests/test_drivetrain.gd` + `docs/drivetrain.md`

Started at 86c6471. Both files read whole, against `drivetrain.gd` (read whole again).

## Findings

### Tests

1. **A case that tests nothing it names (S).** `test_the_esc_cap_holds_the_delivered_fuel_never_the_demand`
   loops `for inertia in [0.2, 0.0]` and says "on both engines, the crank and the rigid one".
   `engine_inertia = 0.0` does not select the rigid crank: `drives_wheels` reads
   `ground_drive.driven_front or driven_rear`, and `GroundDriveSpec.driven_rear` defaults true,
   so both passes run `_fuel_step`. Proof: see Commits (the rigid branch's `esc_cap` removed,
   the test still passes).
2. **Duplicate test (S).** `test_below_the_redline_the_engine_still_makes_its_curve` asserts
   `applied_throttle == 1.0` and `absf(torque) > 0` on a locked D1 at full pedal. The same run
   is asserted exactly by `test_the_driveline_loss_applies_by_the_torque_s_direction`
   (`drive == wheel_torque(spec, at_rpm, 1.0, 1)` to 1e-6, under the redline) and
   `test_exact_byte_change_cuts_throttle_for_the_declared_ticks` (`applied_throttle == 1.0`).
3. **Wrong comments (S).**
   - Header: "§6 at the bottom is the brake pedal's map". The brake pedal's test sits at line
     1907 of 2753, and no other section is numbered.
   - `test_a_launch_holds_its_start_gear_until_the_coupling_locks`: "rolling at 600 rpm in D3";
     the code is `_road_speed_for(dt, 3, 900.0)`.
   - `test_governed_upshift_reads_the_declared_radius_as_a_pure_scale`: two sentences run
     together ("...when the wheel fields move to the ground road_radius enters as...").

### Doc (`docs/drivetrain.md`), each checked against the value set in code

4. Line 10: crank inertia "1.5 on the vans, trucks and tractor". `VAN_BASE` is 0.40
   (`tools/gen_kenney_vehicles.gd:510`, `delivery_spec.tres:85`, `docs/sources.md:23`).
5. Line 15: `clutch_reserve` "1.5 on cars, 2.0 elsewhere". `VAN_BASE` is 1.5
   (`gen_kenney_vehicles.gd:510`).
6. Line 96: motoring "Medium diesel (Kenney trucks and vans) ... 0.10 / 0.15". `VAN_BASE`'s
   `engine_brake_frac` is 0.12 (`gen_kenney_vehicles.gd:502`, `delivery_spec.tres:82`).
7. Line 79 (and `docs/sources.md:476`): "the floored tractor upshifts at 2052".
   `ShiftPolicy.governed_up_rpm` is `setting / (1 + GOVERNED_UPSHIFT_DROOP * droop)` =
   2350 / 1.14 = 2061; 2052 is 2350 / 1.07².
8. Line 24: "A clutch stays locked until a shift". `coupling_step` also slips a locked clutch
   on anti-stall (`crank_rpm < idle and sync_rpm < idle`).

## Checked, no finding

- `node tools/check_docs.mjs`: every `Class.member`, path and `§` reference in the doc resolves.
- The doc's other design values match the code: idle / redline and the stall speeds (2375,
  1250), stall ratios and `lockup_gear`, the converter's K table, COUPLING_POINT,
  OVERRUN_CAPACITY, the shift table's light pairs and kickdown points, `start_gear_max`,
  `launch_rpm_over_idle`, `governor_droop`, the motoring shares of the cars, trucks, tractor
  and semis, the fuel efficiencies, the tractor's 1214 / 1575 rpm settings.
- The measured figures (creep grades, roll-back, climbs, traces) were not re-run.
- The test comments' hand arithmetic (start-gear loads, dwell ticks, kickdown landings,
  converter loads) checks out.

## Deferred

- Added to the queued rigid-crank item (2a, finding 2): the rigid branch's `esc_cap` line has
  no test (finding 1's proof), and its only writer is `WheelDrive.esc_step`; whether any
  rigid body reaches it was not checked. `test_wheels_turning_against_the_gear_get_no_engine_braking_and_no_limiter_cut`
  runs on the crank path, but its comment describes the rigid branch's `crank_forward`; it
  is reworded when that branch goes.
- Not moved: `test_the_pawl_holds_...` and the brake pedal's test exercise `WheelDrive`
  (unit 3) from this file. They are the only tests of `pawl_torque` and `brake_application`;
  unit 3 decides where they live.

## Commits

- Proof of finding 1: `drivetrain.gd`'s rigid branch changed to
  `applied_throttle = minf(applied_throttle, _torque_restore)` (no `esc_cap`);
  `test_drivetrain.gd` ran 159 cases, 0 failures, the ESC test PASSED. Break undone at once.
- f45f3e5: findings 1-3 (`test_drivetrain.gd`: 158 cases).
- 1f85257: findings 4-8 (`docs/drivetrain.md`, `docs/sources.md:476`).
- Full suite before the commits: 2422 cases, 0 failures. `check_docs` passes (docs at their
  3410-line cap: a doc fix here cannot add a line).
