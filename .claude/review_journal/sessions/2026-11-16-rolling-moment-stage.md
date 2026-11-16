# 2026-11-16: the rolling moment, landed as a stage before the TC hold (Queue A3, Opus)

Started at 44495c5 (after A2). Plan approved by the user: `~/.claude/plans/vast-foraging-wren.md`.
Inputs: `2026-11-15-rolling-moment.md` + `.patch` (deleted after landing; both at 44495c5),
`2026-11-16-rolling-moment-diagnosis.md`
§ Brief. State: done: the change, the runs, the user's OK to land (2026-11-16), the docs.

## The change (uncommitted until the user has seen the moves)

- The patch applied over A2 (`git apply -3`, clean).
- The stage (`wheel.gd`): `roll_spin` / `roll_reacted` replace `roll_share`; `_integrate_spin` takes
  `roll_torque`; `settle_spin` applies the moment before TC and the brake; `settled_spin(...,
  roll_take)`; `heat_brake` and `brake_reacted` are the brake's alone again.
- `differential.gd`: `roll_take` beside the other arrays; `_settle_kinks` maps `_held_kinks`
  (HEAD's `_settle_kinks`, renamed) out through `±roll_take`. `wheel_drive.gd`: `_outputs`' 7th array,
  the far side's 0, the converter's `held[6]`, `_settled_drive_spin`.
- Tools: `measure_grade`'s stop ledger reads `roll_reacted` over the settled spin;
  `measure_vehicles`' rest pass counts `_spin_held` again (as at HEAD).
- Tests: the TC-past-ceiling case with a moment (`test_differential`), the kink and never-reverses
  sweeps with moments, the settled mean with one, a TC-held step with a moment
  (`test_tcs_holds_a_floored_drive_at_its_slip`). `test_wheel_spin` 161, `test_differential` 20,
  `test_brake_fade_wiring` 10: all pass.

## Runs (HEAD 44495c5 vs the change, `--fixed-fps 60`, scratch worktrees)

| Run | HEAD | after |
| --- | --- | --- |
| suite | - | 2523 / 2523 (the patch's removed drag tests: 3 fewer cases) |
| bobtail `rest reading:` | 0.7 /s, 0.01 kg a tick | 0.3 /s, 0.02 kg a tick |
| laden `rest reading:` | 0.0 /s, 0.00 kg | 0.0 /s, 0.01 kg |
| `semi 20 rest` | rear 0.0 kg a tick, rims turn | rear 0.0 kg a tick, rims stand ("1.00 off the road") |
| `sedan 45 brake` 100 % | 40.7 m 2.88 s | 41.1 m (30 %: 156.1 -> 156.3 m) |
| `sedan stops` | 40.6 m, energy 0.986 PASS | 41.0 m, energy 0.986 PASS |
| FIELD `wheel_slip`, `tractor-kenney` 15 km/h | 2.87 % | 1.02 % |
| `semi rollback grade=25 nohold` | 887.1 mm | 911.6 mm |
| `semi rollback` 25 % (hold) | forward 4.27 s | forward 9.53 s |
| `sedan rollback nohold` 10 / 25 % | 48.5 / 503.6 mm | 52.5 / 507.7 mm |
| `semi rollback nohold` 10 % | 6.9 mm | 7.0 mm |
| `all creep` | `sedan` 7.0 % | `sedan` 5.7 %, each body 0 to 1.3 points down |
| `doc=park` | - | no cell over 0.5 mm along or 0.7 across from HEAD |
| `all 45 track strict` | 19 PASS | 19 PASS |
| `doc=cruise`, `doc=top` | - | within a digit (rpm by 1-5, `hatchback-sports` top 227 -> 228) |

- The semi on 25 % with the hold off: the steady forces are HEAD's (the unit's uphill total
  76893 against 76899 N, the trailer 1206 against 1206 N, the driven rears on the TC ceiling); the
  extra 24 mm is the first second's launch (1.04 against 1.02 km/h back at 1 s), the deceleration
  after it the same. The brief expected about 1 %; it reads 2.8 %.
- The cross cell (`park_cell=semi:cross:5.7`, the gather's probe and a stand-in dump of
  `suspension_force`, both trees, from 15 s): HEAD's held wheels already reverse by more than 2 N
  both ways (the unit's rears 45 and 39 times in 45 s, the largest 3.8 N); after, 42 and 42, the
  largest 4.9 N; the trailer's 1 to 10 times in both. The brief's "HEAD: under 1 N" was another
  reading of another log; like for like the cell is HEAD's, and the patch's ±90 N cycle is gone.
- **The rest gate fired by its letter** (0.01 -> 0.02 kg, one print unit; the patch as built read
  0.34). The user landed it ("Land it", 2026-11-16); A7 sizes the rest gates on these figures.
- `docs/tractor.md`'s mud bullet: the rig moves off at 1.47 s (was "several seconds") and crawls
  at 1.70 km/h with every tyre at 0.85 slip; the drag cap's explanation went with the cap.
- `docs/drivetrain.md`'s creep table: re-measured, and headed as what the judge reads (a slide
  under `CREEP_ROLL_M` in `CREEP_HOLD_S`, not a static hold).

## Seen, not acted on

- `doc=brake_fade`'s `semi` foot-brake descent on ice now stays on the ramp to the end, still
  jackknifed at 75.1° (HEAD: it left the ramp). The jackknife on ice stands in both trees.

## Commits

- becd1d6: the change, its tests and docs, the `doc=` tables re-run.
- The journal's.
