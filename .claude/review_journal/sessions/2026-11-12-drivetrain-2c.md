# 2026-11-12: Unit 2c, the drivetrain's small files

Started at 8d8558c. Read whole: `differential.gd`, `torque_converter.gd`, `shift_policy.gd`,
`pedal_map.gd` (`src/vehicles/base/`), `tests/test_differential.gd`, `test_shift_policy.gd`,
`test_torque_converter.gd`; the `docs/drivetrain.md` sections they cite (The pedal map,
Converter, Creep, The shift policy, The load).

## Findings

1. **`ShiftPolicy.start_gear` reads a different drive law than the rest of the policy (proposed,
   then approved and fixed).**
   Its reserve test is `Drivetrain.wheel_torque(spec, line, PedalMap.fuel(spec, pedal, line), g)
   < START_RESERVE * road`. `wheel_torque` is `curve * fuel * ratio * efficiency`: it leaves out
   the unfuelled share of the motoring law. Every other reading in the file (`holds_grade`,
   `lugging`, `_floored_accel`) goes through `drive_at`, which is `Drivetrain.crank_torque`,
   `f * curve + (1 - f) * motoring`, the "one engine law" of `src/vehicles/CLAUDE.md`, and
   `pedal_map.gd`'s header says the policy "predicts what the crank makes". Equal at full pedal,
   so `_pick_start_gear` (pedal 1.0) is unaffected; `_start_gear_step` passes the driver's
   `demand`. Measured with a throwaway gdUnit probe on the shipped specs (deleted after the run),
   `start_gear` against the same function on `drive_at`, 801 standing loads from 0 to D1's limit:
   - `semi` and `semi-conventional` (LINEAR, friction 0.05, launch 900 rpm): the D1 launch drive
     reads 3567 N·m against the law's 1069 at pedal 0.1 (-70 %), 10700 against 8757 at 0.3
     (-18 %), 17833 against 16446 at 0.5 (-8 %), 32100 against 31822 at 0.9 (-1 %). The start
     gear comes out one gear taller on 2-15 % of the loads (bobtail 9 t at pedal 0.3: D6 where
     the law gives D5 from 1583 N·m; 33 t at pedal 0.3: D2 where the law gives D1 from 3589).
   - `tractor-kenney` (ALL_SPEED): no difference at any pedal; the governor fuels 1 at the
     launch line.
   No test covers it: `_loaded_spec` has no friction, so both laws agree there. Player-visible
   (which gear a part-pedal launch holds), so it goes to `proposals.md`.
2. **Duplicate test (S).** `test_drivetrain.gd`'s `test_auto_shift_never_touches_neutral_or_reverse`
   (`auto_shift(spec, GEAR_N, 4000.0) == GEAR_N`, the same for R) is a subset of
   `test_shift_policy.gd`'s `test_n_r_and_p_never_shift_whatever_the_policy_says` (N, R and P, both
   rpm ends, both pedals, kickdown armed, skip-shifts). Both reach only `auto_shift`'s
   `if not is_drive(byte): return normalize_byte(byte)`, which returns before the spec or any
   other argument is read. Proof: with that guard disabled the `test_shift_policy` test fails
   (guard restored at once).
3. **Dead fixture lines (S).** `test_torque_converter.gd`'s `_spec()` set `ground_drive`,
   `coupling = CONVERTER` and `engine_inertia = 0.2`. Nothing the file calls reads them:
   `capacity_coefficient` and `idle_band` read `Drivetrain.stall_rpm` (idle and redline) and
   `engine_torque` (the curve); the solves take the crank's compliance as the literal
   `TICK / 0.2`. Proof: removed, the 10 cases pass.
4. **History in three test comments (S)**, against "present tense, no history":
   `test_differential.gd` "an all-open body is today's equal split"; `test_shift_policy.gd` "The
   fixed-threshold rule the box ran before the policy" and "No estimate is today's map".

## Checked, no finding

- No dead symbol: every public function and constant of the four files has a caller in `src/`
  or is used inside its own file (`coupling_torque` by `braked_coupling_torque`'s no-hold path;
  `shift_dead_s`, `descending`, `flat_load`, `capacity_shape`, `governor_fuel` likewise).
- Every `Class.member`, path and `§` the four files' comments cite resolves (`RayWheel.spin_compliance`
  is a var; the doc sections are bold paragraph heads).
- `_brake_kinks` and `_settle_kinks` list exactly the slope changes of `RayWheel.braked_spin`
  and `settled_spin` (worked through `brake_room` and `tcs_take`).
- `CAPACITY_SHAPE` is `(12.3 / K)^2` of the K figures its comment quotes (0.710, 0.569, 0.310,
  0.061).
- `Differential.falling_root` brackets on `dir * capacity`, so it needs a finite capacity (read
  from the code, not run); it gets one: `Drivetrain._capacity` is capped at
  `clutch_rating * ramp` before `_solve_output`, its only caller's source.
- The one `COMPROMISE` in the unit (`TorqueConverter.IDLE_CAPACITY`) states what is true and
  its undo cost; it stays.
- The three test files' hand arithmetic checks out (kickdown holds, skip-shift dwell times,
  start-gear slip times, landing floors, grade logic, the lock-up's 120 N·m, the park pawl).
- `docs/drivetrain.md` on these files (LIGHT_PEDAL, the 1.1 landing and reserve, the 0.85
  ceiling, the 2 % grade, START_RESERVE, COUPLING_POINT, OVERRUN_CAPACITY, the K table, the
  PETROL rows) matches the code.
- `PedalMap` has no test file of its own; its tests are in `test_drivetrain.gd` (unit 2b).

## Commits

- b4ed767 the three test comments (finding 4).
- 576bd74 the duplicate N/R test removed (finding 2).
- 7fba41c `_spec()`'s three unused lines removed (finding 3).

- dd8dd5e finding 1, approved by the user in the session: `start_gear` reads `drive_at`; a new
  case, `test_the_start_gears_launch_drive_nets_the_motoring_out_at_part_pedal`, separates the
  two laws. Full suite 2422 cases, 0 failures. The one documented part-pedal semi figure
  (`docs/drivetrain.md`: `semi` + 24 t, 8 %, pedal 0.6) re-run: D1 start, to D4, 187.7 m, as
  written. On the flat hard road the probe's first differing load (1583 N·m bobtail, 3589 at
  33 t, pedal 0.3) sits well over the rolling load, so the change shows on a grade or soft
  ground.

## Deferred

Nothing.
