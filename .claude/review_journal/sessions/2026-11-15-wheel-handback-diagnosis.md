# 2026-11-15: the wheel fix's hand-back, diagnosed (Queue, Fable's item 1, diagnose only)

Started at 88cb664. Read: `wheel.gd`'s tick, spin step and settle; `wheel_drive.gd`'s tick and
`_couple_differentials`; `measure_grade.gd`'s park and roll-back; the hand-back
(`2026-11-15-wheel-settled-slip.md`, its `.patch`), the gather (`2026-11-15-gather-semi-rollback.md`)
and the derivation (`2026-11-14-wheel-body-one-force.md`). Nothing fixed. The patch's `src/` part
was applied with a probe for six runs and reverted (`git status` clean after). Runs:
`--headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- ...`.

Verdict: the fix is right. One line of it is wrong (step 4's guard, (a)); (b) and (c) are the
fix's own honest result. The patch applies clean at 88cb664 (`git apply --check`, whole).

Symbols as in the derivation: `s` slip velocity, `C` the tyre's slope (N per m/s), `k = C r^2 dt
/ I`, `tau = T r dt / I`, `a` the share of the slip the body closes.

## (a) Step 4's guard replaces the hold's stiffness, not only the curve's

Step 4 as built (`_integrate_spin`):

    var reaction_stiffness := absf(reaction_torque) / null_slip_torque \
            if null_slip_torque > 1e-6 else zero_slip_stiffness

The secant `|R| / null_slip_torque` has the curve's first slope as its limit at zero slip only
when the reaction is the curve's alone (`R = C s r`, so `|R| / N = C r^2 dt / I = k0`). A held
wheel's reaction is its patch spring's (`_patch_spring`, `held_force_range`), which does not fall
with the slip: the secant's limit is unbounded, and HEAD's `|R| / maxf(N, 1e-6)` is that limit.
The wheel is rigid for the tick, which is what the hold presumes: `held_force_range` already
bounded the patch's force by what the brake and the lock react, and `hold_by_lock` holds a wheel
only while every locked wheel reads under `LOCK_STUCK_SPIN`. A brake does not care (its check
`brake_spin >= |spin|` scales with the compliance on both sides); the pawl does, because the lock
zeroes only the locked wheels' mean and the centre diff then moves it.

Proven, `suv park=16.7 pawl verbose` on the patch as built, a print where the branch is taken with
`|R| > 1`:

    PROBE3 f=538 rear=false slip_vel=-0.0000000029 null=0.00000058 R=-280.7 k0=11.87 head_k=280747353 held=true step=-0.30291
    PROBE3 f=538 rear=true  slip_vel=-0.0000000029 null=0.00000059 R=-479.6 k0=24.56 head_k=479620151 held=true step=-0.26066

- Tick 538 (about 7.5 s into the hold): the contact's speed falls to 2.9e-9 m/s,
  `null_slip_torque` passes under 1e-6, and the stiffness drops from 2.8e8 to 11.9 (front) and
  24.6 (rear). The spring's reaction turns the held wheels -0.303 and -0.261 rad/s in that one
  tick; the lock zeroes the mean, the spread is over `LOCK_STUCK_SPIN` (0.01), `hold_by_lock` is
  skipped, `_spin_held` goes false and the patch springs along the wheel are dropped.
- It fires on that tick only (2 prints, one per axle pair). From then the body slides at 0.11 m/s
  on the slip curve alone, all four wheels at -0.034 rad/s, `held false`, to the end:
  `along -5000.2 mm ... SLID (51.9 s)`. The 50 s is the time to slide 5 m, not when it let go.
- With the guard amended (below), same run: the branch is met on 133 ticks,
  `along +0.2 mm ... peak 0.006 m/s`, every wheel `omega 0.00000 held true` at 1, 30 and 59 s.
  HEAD's cell is +0.2 mm.

The amended guard (two lines; the rest of step 4 stays):

    var reaction_stiffness := absf(reaction_torque) / maxf(null_slip_torque, 1e-6)
    if null_slip_torque <= 1e-6:
        reaction_stiffness = maxf(reaction_stiffness, zero_slip_stiffness)

It is continuous: a curve-only reaction under the threshold reads `k0 * N / 1e-6 <= k0`, so the
`max` gives `k0`; a spring-carried one reads HEAD's value. It is no `max` at speed (the brief's
caution holds: a saturated tyre's secant is under `k0`).

Is step 4 needed at all? Yes, with the patch. An unheld wheel under 3e-9 m/s of slip that gets a
torque (a brake let go after a stand of some seconds, the creep or the clutch arriving) has no
stiffness: it takes the whole `tau`, and the patch now gives the body the curve at `s* = tau` in
the same tick, up to `min(budget, long_mass * tau / dt)`. A sedan (`I` 1.2, `r` 0.36, cap mass
199 kg) gets up to 21 times the drive for that tick. Derived, not run: the suv run shows a standing
body does get under the threshold (133 ticks in 60 s). HEAD has the same wheel jump and pays it one
tick later off the start slip; not measured there.

## (b) HEAD's roll-back was short by a false mass: the new figure is the honest one

HEAD's map under the floor with no predictor (`road_change` is zero under 1.5 m/s), every wheel
in contact, the body gaining `A` a tick in steady acceleration:

    wheel:  (tau_i - k s_i) / (1 + k) = A      ->  s_i = (tau_i - A (1 + k)) / k
    body:   M A = M g_par dt + sum C s_i dt
    with C dt / k = I / r^2:
            (M + sum (1 + k) I / r^2) A = M g_par dt + sum T_i dt / r

The whole drive arrives, on a body that weighs `M + sum (1 + k) I / r^2`. And `(1 + k) I / r^2 =
I / r^2 + C dt`: **each contact adds `C dt` kg, its tyre's slope times the tick**, which the
one-tick cap bounds at the contact's cap mass (`long_mass`), reached wherever its own
`slip_floor_for` floor binds. The prototype's "the body gets `1 / (1 + a)` of the drive" and the
old § Following the body's "an accelerating body costs its wheels `I a k / r`" are this law on one
wheel. A TC-pinned wheel carries it too (its start slip is `0.12 F - A`, so its force drops
`C A`). The patch's map gives `M + sum I / r^2`, the real figure.

Checked on the sedan, 25 %, hold off (`sedan rollback nohold grade=25`, patched, a print per wheel
in the roll-back): mass 1150 kg; each wheel `I` 1.2, `r` 0.36 (9.3 kg); cap mass 199.1 kg; the
shared floor 2.32 m/s is the fronts' own (budget 3311 N, so `C dt` = 199 kg each), the rears
(budget 2457 N) carry `2457 * 8.333 / 60 / 2.3165` = 147 kg each. `sum C dt` = 693 kg on 1187 kg:
HEAD's body is 1.58 times too heavy there. Measured roll-back, patch over HEAD: 503.7 / 333.2 =
1.51, forward at 1.87 against 1.88 s (the same force history over two masses crosses zero at the
same time). The 10 % cell (36.6 -> 48.5 mm, 1.33) is mostly the creep holding the grade, a smaller
share of free roll.

So: nothing to fix. Every body under about 5 km/h accelerated as if up to half as heavy again;
that is where the launch's quarter second came from, and the roll-back grows by the same law.

## (c) The laden `semi` on 25 % does not pull away, before or after

`semi rollback grade=25 verbose`, the steady lines (t 3 to 10 s), HEAD and patched alike:

    Fx front 0  rear 76803 N  roll -762 N  slip +0.00 / +0.12  | trailer Fx 4 N roll 0 N brake 0.00  drawbar 57033 N (grade 57044)

- Patched drive wheel, per tick: `bud=38401.7 cap=38403.2 fx=38401.68 N=54415.0 den=3.9027`,
  `u - v` = 0.4683 = 0.12 x 3.9027: on the TC ceiling, at the budget, every tick.
- The rig needs `32000 * 9.8 * 0.24254 + 762` = 76821 N and has 76803 N: 18 N short (0.02 %).
  Its speed falls the whole run: patched 15.48 -> 12.87 mm/s over 5 s (-0.52 mm/s2, 17 N on
  32.2 t); HEAD -0.41 mm/s2 from the printed gains (the same force on HEAD's false mass: `sum C
  dt` = 16.2 t on 32.2 t predicts a ratio of 1.50; the gains, rounded to mm, read 1.3 to 1.4).
- So `forward at` reads when a coast passes 0.1 m, on the speed the launch transient left: 25 mm/s
  at HEAD, 15 patched. Through that transient the patched rig is ahead (gain 0.045 against 0.041 m
  at 1.0 s; rear `Fx` 84.3 against 82.4 kN while the trailer's brake is still coming off, `brake
  0.23`, trailer `Fx` -17.3 against -12.5 kN; then the dip, 74.7 against 74.2 kN at 1.5 s). What
  is left is a surge less a dip over the rig's mass, a difference of two impulses: not derived in
  closed form, and it does not need to be. Neither version climbs this cell.
- Not explained: why the cell sits 0.02 % under the limit. No feedback holds it there (the force
  is the budget, the speed just decays); it reads as chance.

The patch is not slower here. The cell cannot judge a launch.

## For other items (seen, not traced further)

- **Fable's item 2 and the towing item's (a), `surface_drag_force`'s `taken`.** In (c) eight of the
  rig's ten wheels carry no rolling drag: `roll -762 N` is the two drive wheels' (`0.0070 x 2 x
  54.4 kN`), the fronts and the trailer read 0. Derived from `tick`: a free wheel's `taken` is
  `long_mass * g sin`, so its cap is `long_mass * (|v| / dt - g sin)`, zero under `g sin * dt`
  uphill: 39.6 mm/s on 25 %, 16 mm/s on 10 %. Gravity's share is taken off the cap of a wheel whose
  gravity another wheel's tyre is already holding. With their drag (about 1.5 kN) the rig in (c)
  would stop instead of coasting. Same fault as the towing item's (a), on every free wheel.
- **Unit 3b, `LOCK_STUCK_SPIN`.** The slide in (a) is a second steady state under a pawl that has
  torque to spare (`park_pawl_torque` 3000 against 1460 N·m of grade at the rims): the lock zeroes the mean, the centre diff
  (`centre_diff_bias` 3) moves it, all four wheels sit at -0.034 rad/s, over the 0.01 gate, for
  50 s, and nothing re-holds them. Candidate, not run: at HEAD an AWD body put in P while rolling
  back under `PAWL_ENGAGE_SPEED` on 30 % may settle into the same creep and never hold. The run
  that shows it: `suv` rolling back at about 0.3 m/s on 16.7 deg, then P, 20 s.

## Deferred

Everything: this session fixes nothing. The Queue's wheel-fix item is ready again, with the
amendments above written into it.

## Commits

The journal's only.
