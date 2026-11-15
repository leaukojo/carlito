# 2026-11-15: the rolling resistance as a moment on the wheel (Queue, approved item, Opus)

Started at 55d25e1. Brief: `2026-11-15-wheel-leftovers.md` finding 1, variant A (user,
2026-11-15). **Handed back**: three stop conditions fired; the change is undone, nothing of it is
committed. The whole change is `2026-11-15-rolling-moment.patch` (applies cleanly at 55d25e1:
`git apply`), so the next session starts from it, not from scratch.

Baselines at HEAD ran in a detached worktree (`.godot/` copied, removed after); every run
`--fixed-fps 60`. `wheel_slip` was read by an uncommitted probe in `measure_vehicles`' cruise
hold (the mean of `telemetry.wheel_slip` over the held tail), the same in both trees, reverted.

## What the patch does

`RayWheel.tick` on the ground: `roll_torque = (rolling_crr + surface_drag) * suspension_force *
wheel_radius` added to `_integrate_spin`'s brake argument only (never `hold_torque`), `roll_share =
roll / (brake + roll)` latched; `settle_spin` sets `force_roll = -sign(unbraked) * roll_share *
brake_reacted / r` (a readout); `heat_brake` takes `(1 - roll_share)`. Gone: `surface_drag_force`,
`taken`, the second `apply_force`, the old `COMPROMISE`; the soil's share takes a new one.
Measure tools that summed `force_roll` beside `force_long` follow (`measure_grade` stop ledger and
trailer drawbar; `measure_vehicles` top-speed balance and gap split); the rest pass counts
`_patch_held` (a free wheel the moment stopped reads `_spin_held`). Tests: the `surface_drag_force`
tests and the through-zero test go; `_free_pair_speeds` takes the moment as its brake; two new.
`test_brake_fade_wiring` needs nothing (its bodies tick airborne).

Tests on the patch: `test_wheel_spin` + `test_brake_fade_wiring` 168 cases, 0 failures.
`test_a_free_wheel_crawling_uphill_pays_its_whole_rolling_resistance` fails at HEAD
(`force_roll -0.00 N, crr N -311.70 N`). `test_a_coasting_body_loses_speed_at_its_rolling_
resistance` passes at HEAD too (derived: the system's deceleration is the same either way).

## Measured, HEAD -> patch

As the brief predicted:
- `measure_vehicles -- sedan 45 brake`, 100 %: 40.7 m 2.88 s -> 41.1 m 2.92 s (30 % 156.1 ->
  156.2 m, 60 % 61.9 m both). `measure_grade -- sedan stops`: 40.6 -> 41.0 m, energy check 0.986
  PASS both (rolling 0.005 -> 0.004 MJ, brakes 0.417 -> 0.419).
- `wheel_slip` on `surface=field`, cruise, no draft: `tractor-kenney` 2.87 / 2.85 / 3.02 % ->
  1.02 / 0.99 / 1.21 % at 15 / 25 / 34 km/h; `tractor-cvt` 3.01 / 3.02 / 3.00 -> 1.02 / 1.04 /
  1.07 %. (About 1 % left, not about 0.)
- `measure_grade -- tractor-kenney rollback grade=10 mud mfwd tipper verbose`: forward at 2.88 ->
  1.47 s; steady 0.16 -> 1.70 km/h, slip 1.08 -> 0.85.
- `all 45 track strict`: every body PASS, drift 0.000 both.

Stop conditions that fired:
1. **TC-held drive wheels pay their rolling resistance out of traction.** `measure_grade -- semi
   rollback grade=25 nohold verbose` (laden): rolled back 887.2 -> 1577.6 mm. Steady lines, t 3.0 s:
   HEAD `Fx front -3 rear 76748 N roll 154 N slip -0.00 / +0.12 | trailer Fx -9 N roll 1215 N`;
   patch `Fx front 154 rear 75861 N roll -604 N slip +0.00 / +0.12 | trailer Fx 1210 N roll 1215
   N`. The undriven wheels' drag is the same (HEAD's `taken` was 0 for them rolling back); the
   driven rear's force falls by 887 N. With the hold on (`grade=25 verbose`): forward at 4.32 s ->
   never (stands at +0.058 m). `sedan rollback nohold`: 48.5 -> 52.5 mm (10 %), 503.6 -> 508.2 mm
   (25 %); `semi rollback nohold` 10 %: 6.9 -> 7.0 mm.
   Cause, derived: `settle_spin` (and `settled_spin` in the diff solve) applies the TC hold first,
   then the brake law. A drive wheel at TC's ceiling (slip +0.12, the curve's peak) is then pulled
   below it by the moment's spin `T_r * compliance`; on the curve's rise the tyre loses
   `C r * T_r dt / (I (1 + k)) = (T_r / r) * k / (1 + k)`, about `crr N` of that axle (rear roll
   readout about 755 N; force lost 887 N). A real TC trims the engine to the slip target with
   every wheel torque in, so the engine pays the moment and the tyre stays at its peak.
2. **A standing body's `rest reading:` rose.** `measure_semi_launch -- semi steady strict
   trailer=bobtail`: axle-load step 0.11 -> 0.34 kg a tick (`rest_axle` |d|/tick 0.1 -> 0.3,
   crossings 9.3 -> 20.0 /s). Laden: 0.95 -> 0.79 (fell). `measure_vehicles -- semi 20 rest`
   (laden): rear axle 0.6 -> 0.9 kg a tick; the rims now stand still ("the rim lands 1.00 off
   the road's speed", HEAD 0.02). `tractor-kenney 20 rest`: rear 0.1 -> 0.0 kg a tick, rear
   drag flips 31.7 -> 4.7 /s. Not traced.
3. **A `doc=park` held cell moved over 1 mm**: `semi` 18 % hand, across -0.0 -> -1.7 mm (and 10 %
   cross across -0.5 -> -1.5 mm). Every other held cell within 0.7 mm; the four pawl slides as
   before. Not traced.

Also moved, not a listed stop:
- `measure_grade -- all creep`: every converter body holds less grade, `sedan` 7.0 -> 5.7 %,
  `sedan-sports` 8.6 -> 7.4, `pickup` 5.7 -> 5.3, `delivery` 7.0 -> 5.7, `firetruck` 8.6 -> 7.8;
  flat creep speeds unchanged. The derivation expected creep to hold the same or more (a still
  wheel's moment resists either way). Not traced.
- The rest pass's held count reads `_patch_held` on the patch; the laden `rest=brake` run prints
  4 of 4 at HEAD (`_spin_held`) and after.

## Hand-back

Queue: a gather line (Opus) for the per-tick logs that 2, 3 and the creep move need, then one
`diagnose` line at the top of Fable's list. The fix it points to for 1, not tried: the rolling
moment as a stage BEFORE the TC hold in the settle law (`settled_spin`, `settle_spin`, the latches
`WheelDrive` and `Differential` pass), the service brake and its ABS floor after. It restructures
the wheel's settle, so it is diagnosed first (skill § Diagnose only).

Left for the rest-gates item either way: `measure_semi_launch.gd:75-79`'s REST constants comment
names the two-caps fault and § One-tick caps, whose paragraph the patch removes.

## Commits

The journal's only.
