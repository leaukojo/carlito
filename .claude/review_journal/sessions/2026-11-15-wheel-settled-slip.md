# 2026-11-15: the body takes the tyre's force at the settled slip (Queue, approved, Opus): HANDED BACK

Started at 4447d29. Brief and derivation: `sessions/2026-11-14-wheel-body-one-force.md`. Plan
approved by the user (plan mode). Runs: `--fixed-fps 60`; the HEAD baseline in a detached worktree
at 4447d29 (import cache copied, since removed). The brief's stop condition hit (a parked cell);
the user chose the hand-back. Everything undone; the implementation is kept as
`sessions/2026-11-15-wheel-settled-slip.patch` (`git apply` checked clean at 4447d29).

## What the patch does (the brief's five steps, as built)

- `RayWheel.tick` stores the patch (`_patch_*`: axes, `v_long` / `v_lat`, the denominator, both
  budgets and cap masses, `lat_peak`, the spring force, `held` and its range, the curve, `delta`)
  and sizes the spin step off the start slip's force; `_slip_force(slip_vel)` (curve plus both
  caps, sets `long_cap`) and `_with_spring(f)` (spring, ellipse, held range) serve both reads.
- `apply_patch(body)` pushes the curve at the settled slip, the drag with its `taken`,
  `contact_force`, `patch_force`; sets the readouts. A non-`coupled_spin` wheel calls it at the end
  of `tick`; `WheelDrive.tick` per wheel after `_couple_differentials`, then
  `_report_to_controller` (moved out of `_couple_differentials`).
- Step 4: `_integrate_spin(..., zero_slip_stiffness)`, `zero_slip_rise(curve)`.
- `road_change`, `_prev_com_long`, `_prev_vel_valid`, `dv_long` gone.
- Tests (all 159 of `test_wheel_spin` pass with it): two new on a 1500 kg bench ticked by
  `WheelDrive` (no drivetrain), both failing at HEAD in the worktree: a coasting body's free-wheel
  slip never reverses (HEAD: 116 reversals over 29 ticks x 4 wheels; patch: 0), and a constant
  drive under the floor reaches the body (HEAD: least 0.580 of `T / r`; patch: over 0.95). One
  pure, step 4's. The decelerating-body test rewritten without the predictor (the settled force
  carries `brake - I a / r`: derived `s* = (a dt + tau) / k`). Gone with `road_change`: its test
  and `test_a_free_wheel_in_a_steady_turn_carries_no_drive`. `_sliding_wheel` brakes its wheel
  (documented as locked; it held the start force only because the force was read before the
  step). `_free_pair_speeds` steps the new order. Twelve sites drop `dv_long`.
- `docs/vehicles.md`: § Following the body rewritten as § One force at the patch (the 480 Hz
  figure dropped: not re-measured), the "Still there" ring line gone, the Rejected designs line
  says how this differs. `check_docs` passed (25 characters of headroom).
- Not run: the full suite (the measure runs held the checkout's lock), `doc=` tables.

## Measured (HEAD -> patch)

Matches the prototype where the prototype ran: `sedan 45 brake` 0-50 3.47 -> 3.20 s, 0-100 8.28 ->
8.03 s, launch grip use 0.91 -> 0.95, 100-0 41.6 -> 40.7 m (0.95 -> 0.98 g), 60 % 62.4 -> 61.9 m,
30 % 157.3 -> 156.1 m; every stop shorter. Rest: bobtail `semi` sign changes 1.3 -> 0.7 /s, speed
steps 2.40 -> 1.08 mm/s; `tractor-kenney` N 2.06 -> 1.95; laden `semi` axle step 0.80 -> 0.95 kg a
tick (`steady strict`, the towing item's, under the 2 kg gate). `all 45 track strict`: PASS
everywhere (the two non-zero drifts 0.031 -> 0.027 m and 0.015 -> 0.029 m). Creep: every body
creeps faster on the flat (van 4.8 -> 5.8 km/h); `hatchback-sports` holds 5.3 -> 4.9 % (one bisect
step, one body: inside the brief's tolerance).

## Findings (for the hand-back)

1. **Step 4 lets a pawl-held AWD body slide.** `measure_grade -- doc=park`: `suv 30.0 % pawl`
   along +0.2 mm -> -5000.2 mm, SLID after 50.5 s at 0.123 m/s peak. Every other cell within 1 mm
   (the trucks' and semis' pawl slides are at HEAD too). With HEAD's stiffness restored
   (`|reaction| / maxf(null_slip_torque, 1e-6)`, the rest of the patch kept) the cell reads +0.2 mm
   and the whole park table is HEAD's within 1 mm; creep as above. Mechanism, inferred from the
   code and not traced per tick: a wheel the lock holds stands at exactly zero slip with the patch
   spring carrying its load, so HEAD's secant there is about `|f r| / 1e-6`, a near-rigid wheel
   in `_couple_differentials`; the curve's first slope makes it compliant, and the one-pass solve
   (its `COMPROMISE`) then leaves a spread over `LOCK_STUCK_SPIN` (unit 3b's cover candidate), so
   `hold_by_lock` lets go. Fable's prototype had recorded step 4 as derived, never reached (its
   variant 3 printed variant 1's figures to the digit); the park table reaches it.
2. **A sedan rolls back further with the hill hold off.** `sedan rollback nohold`: 10 % 36.6 ->
   48.5 mm, 25 % 333.2 -> 503.6 mm; forward at 1.05 -> 0.97 s and 1.88 -> 1.87 s. Same with step 4
   dropped. Candidate cause, not proven: HEAD's spin step read the road's change as slip to buy
   back under the predictor's fade (old § Following the body: "an accelerating body costs its
   wheels `I * a * k / r`"), a false wheel inertia `(1 + k)` times the real one that slowed any
   acceleration under 3 m/s, the roll-back's included. If so the new figure is the honest one.
3. **A laden semi on 25 % with the hold on pulls away later.** `semi rollback`: 25 % forward at
   3.10 -> 4.27 s (roll-back -0.0 mm both; 10 % 1.17 -> 1.13 s). Same with step 4 dropped. Not
   traced. Every other launch here got sooner, so this one runs against the fix's own direction.

## Commits

None but the journal's.
