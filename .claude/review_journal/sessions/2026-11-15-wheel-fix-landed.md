# 2026-11-15: the wheel fix (d22b3ee), its whole record

One file for the chain: Fable's derivation (2026-11-14), the first hand-back, its diagnosis, the
landing. Compressed 2026-11-16. The full files are in git:
`git show c903d45:.claude/review_journal/sessions/<name>` for `2026-11-14-wheel-body-one-force.md`,
`2026-11-15-wheel-settled-slip.md` (and `.patch`), `2026-11-15-gather-semi-rollback.md`,
`2026-11-15-wheel-handback-diagnosis.md`.

## What landed (d22b3ee; tables 7a7cd9f)

Symbols, used by every later wheel file: `v` the contact's speed, `u = omega r`, `s = u - v` the
slip, `C` the tyre's slope (N per m/s), `a = C dt / m` (the share of the slip the body closes),
`k = C r^2 dt / I` (`reaction_stiffness`), `tau = T r dt / I`.

- Before: the body took `C s` at the slip the tick started on, the wheel reacted the force at the
  slip its step ended on. Free, `s' = (1 / (1 + k) - a) s` reversed every tick (the ring); driven,
  the body got about `(T / r) / (1 + a)`; each contact added `C dt` kg to the body under the floor.
- Now: `RayWheel.apply_patch` gives the body the CURVE (never the secant) at the settled slip
  `s* = (s + tau) / (1 + k)`: `s' = (1 - a) s*`, no reversal, the drive whole, the body's mass
  `M + sum I / r^2`. `road_change` and its predictor are gone. The law: `docs/vehicles.md`
  § One force at the patch.
- The zero-slip guard (`_integrate_spin`): `|R| / maxf(null_slip_torque, 1e-6)`, and under the
  threshold `max` with the curve's first slope. A held wheel's reaction is its patch spring's, so
  its stiffness stays rigid; without that a pawl-held `suv` slid 5 m on 30 %.
- Guards: `test_a_held_wheel_at_zero_slip_stays_rigid_under_its_patch_spring`,
  `test_a_pushed_body_gains_speed_on_its_mass_and_its_wheels_inertia`, and the two bench tests (a
  coasting wheel's slip never reverses; a constant drive under the floor reaches the body).

## Measured (before -> after), `--fixed-fps 60`

- `doc=park`: every held cell within 1 mm along and across but `semi 30 % cross` along
  15.5 -> 14.2 mm (it creeps before too). Largest other: `semi 30 % foot` across -0.2 -> -1.1. The
  pawl slides (`garbage-truck`, `semi`, 10 and 30 %) are unchanged.
- `all creep`: every body creeps faster on the flat (van 4.8 -> 5.8 km/h, suv 5.4 -> 6.1); held
  grade the same but `hatchback-sports` 5.3 -> 4.9 % (one bisect step).
- `sedan rollback`: hold on 0.3 / 1.0 -> 0.0 / 0.0 mm, forward at 0.97 / 1.10 -> 0.88 / 0.98 s;
  `nohold` 36.6 / 333.2 -> 48.5 / 503.6 mm (the honest mass: 1.51 measured, 1.58 derived).
- `semi rollback`: 10 % forward at 1.17 -> 1.13 s, 15 % 1.27 -> 1.23, 20 % 1.47 -> 1.40; 25 %
  3.10 -> 4.27 s (the coast cell, below). `nohold` 10 % 6.0 -> 6.9 mm, 25 % 927.3 -> 886.0 mm.
- `sedan 45 brake`: 0-50 3.47 -> 3.20 s, 0-100 8.28 -> 8.03 s, launch grip use 0.91 -> 0.95; stops
  30 % 157.3 -> 156.1 m, 60 % 62.4 -> 61.9 m, 100 % 41.6 -> 40.7 m (0.95 -> 0.98 g).
- `tractor-kenney 8 trace`: the take-up alternated tick to tick (`a g` 0.12 0.04 0.13 0.09); now
  a smooth rise to a 0.45 g plateau.
- `measure_semi_launch` bobtail `steady`: sign changes 1.3 -> 0.7 /s, axle step 0.12 -> 0.11 kg;
  laden `steady strict` axle step 0.80 -> 0.95 kg a tick (under the 2 kg gate).
- `measure_vehicles semi 20 rest`: rear axle 0.7 -> 0.6 kg a tick, drag 7 -> 11 N a wheel.
  `trailer=bobtail`: sign changes 1.3 -> 0.7 /s, rear axle p-p 1.5 -> 0.7 kg, speed step in the
  first second 2.40 -> 1.08 mm/s; drag-sign flips at 0 N 8.0 -> 13.7 /s.
- `all 45 track strict`: every body PASS (the two non-zero drifts 0.027 and 0.029 m).
- `doc=` tables, all sixteen: launches about a quarter second sooner, stops shorter, cruise and
  wind within a digit, the ESC table unmoved. `doc=brake_fade`: on ice the laden `semi` jackknifes
  at 75 deg with the foot brake and the retarder, as before.

## The `suv`'s climb (Queue)

`doc=grade`: `suv` asphalt 79.0 -> 71.3 %; every other body the same or up a bisect step.
`measure_grade -- suv verbose` after the fix:

    33.75 deg CLIMB  speed 3.84 | 39.38 fail -1.93 m/s | 36.56 fail 0.00 m/s (suspension 9359 N)
    35.16 deg CLIMB  speed 3.53 | 35.86 fail +10.49 m/s, sum f_long 3940 N | 35.51 CLIMB

Not monotonic; 35.86's failure reads as a slide back with the tyres nearly unloaded. Not traced.

The Queue line's "Do": run the same at d22b3ee~1 (a detached worktree outside the repo, `.godot/`
copied) and after; for the first trial that differs, log per tick from the start each wheel's
`force_long`, `long_slip`, `suspension_force`, the TC hold and the body's pitch: say whether the
front lifts (the harsher launch the honest mass gives), the centre diff winds up, or TC bites
differently. A cause and a brief; fix nothing; a fix ends in a proposal.

## Still open from the chain

- **The laden `semi`'s axle-load step is not the wheel's.** 0.7 kg a tick before the fix, 0.6 on
  the prototype, 0.6 after, with no speed sign change: the towing item's (c).
- **The laden `semi` on 25 % with the hold on is a coast cell, not a launch.** Steady, t 3 to
  10 s: `Fx rear 76803 N, roll -762 N, drawbar 57033 N (grade 57044)`; the drive wheels sit on the
  TC ceiling at the budget every tick. The rig needs 76821 N and has 76803: 18 N short (0.02 %),
  its speed decays, and `forward at` reads when the coast the launch transient left passes 0.1 m.
  Any force lost there turns "forward at 4.3 s" into "never": the cell cannot judge a launch.

## Unit 3b (`wheel_drive.gd`): findings for its review on Opus

Line numbers are 193e05e's, before d22b3ee moved the file: find by name.

- Wrong comment, `tick`: "resistance reads this tick's spring load so it must follow the wheel
  loop". `_apply_resistance` passes `VehicleMath.air_force` the velocity, the wind, the basis, two
  areas, the mass and `delta`; no spring load is read.
- Cover candidate, `LOCK_STUCK_SPIN`: an epsilon under which a pawl-locked wheel "reads as
  stopped", because the one-pass solve (its `COMPROMISE`) leaves a 7.5e-4 rad/s spread. Not in the
  cover sweep. Prove: set it to 0 and read `suv-luxury` parked on 16 %.
- `LOCK_STUCK_SPIN`'s second steady state (seen on the unamended patch, candidate at HEAD, not
  run): a pawl with torque to spare (`park_pawl_torque` 3000 against 1460 N·m of grade) zeroes the
  locked wheels' mean, the centre diff (`centre_diff_bias` 3) moves it, all four wheels sit at
  -0.034 rad/s, over the 0.01 gate, and nothing re-holds them. The run that shows it: `suv`
  rolling back at about 0.3 m/s on 16.7 deg, then P, 20 s.
- `tick`'s loop sets `abs_slip` per wheel from two loop-invariant reads: hoistable, S.
- `_build_dust` and `_soft_dot_texture` build a particle emitter in code, 67 lines. Whether a
  `.tscn` would carry it is for the review; no cost named.
- Seen and sound: the retarder's `COMPROMISE` is real; `_settled_drive_spin` saves and restores
  `_coupling` around its trial solve; `hold_step`, `esc_step` and `drive_omega` match their
  comments.
- Already queued: the rigid crank's `axle_torque` path.

## Commits

d22b3ee (the fix), 7a7cd9f (the `doc=` tables).
