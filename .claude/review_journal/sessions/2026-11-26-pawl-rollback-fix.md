# 2026-11-26: fix, the park pawl creeping after a roll-back (Opus)

Brief: `sessions/2026-11-26-pawl-rollback-diagnose.md`. HEAD b8c32ee. User approved committing the
driving change to dev (no proposal entry).

## Fix

The pawl's lock solved over the couplings under it (`Differential.falling_root` on
`-_settled_drive_spin`), as the crank above a rigid coupling is. Nested always: one path; with no
coupling moving the mean the spread is linear and the root is one interpolation.

## Evidence

- New test `test_an_awd_body_rolling_back_holds_on_the_pawl` (the brief's fixture) fails before:
  every wheel -0.034165 rad/s, not held; passes after. `test_wheel_spin.gd`: 0 failures, the
  pawl, open-axle (1e-9), slipping-pawl and park-crank tests unchanged.
- `measure_grade -- suv park=16.7 rolled`: 2280.7 mm creep before; after, 22.0 mm, every wheel
  0.00000 and held from t = 1 s to 20 s, peak 0.398 m/s.
- `measure_grade -- suv park=16.7 pawl`: along +0.1 mm, across -0.2 mm, peak 0.005 m/s.
- `LOCK_STUCK_SPIN` kept at 0.01, its reason reworded (the remaining one pass: an axle after the
  centre). The `COMPROMISE` label stays and narrows: the count is unchanged.
- `measure_grade -- doc=park`: every figure the same as the 2026-11-20 table (only its date moved).
- Full suite: 2583 cases, 0 failures. `check_docs` clean.

## Commits

- 6ce6a58 the fix, its test, comments, `docs/vehicles.md`, the park table's date.
