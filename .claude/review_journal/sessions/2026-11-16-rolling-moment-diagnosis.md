# 2026-11-16: the rolling moment's hand-back, diagnosed (Queue A2, diagnose only, Fable)

Started at 43ade9a. Read: `wheel.gd`'s `tick` from the suspension on, `apply_patch`,
`_integrate_spin`, `settle_spin` and the hold laws; `differential.gd` whole; the hand-back
(`2026-11-15-rolling-moment.md`, the wheel part of its `.patch`); the gather
(`2026-11-16-gather-rolling-moment.md`, runs (i) to (iv), and its raw logs for (iii)). Nothing
fixed, nothing run. "Patch" is the tree with the hand-back's patch applied.

| Stop | Verdict |
| --- | --- |
| 1, TC-held drive wheels lose traction | cause confirmed; the fix is the moment as its own stage before the TC hold: § 1, § Brief |
| creep holds less grade | explained; the stage does not remove it; a choice for the user: § 2 |
| 3, `doc=park` `semi` 18 % hand 1.7 mm across | not a fault of the patch: the cell alone moves 0.3 mm between trees: § 3 |
| 2, the bobtail's `rest reading:` 0.11 -> 0.34 kg | the stage does not remove it; its trigger is not in the gathered columns; one fault with a new one found in the 10 % cross cell: § 4, Queue |

## 1. Stop 1: the brake law takes the moment after the TC hold

`settle_spin` on the patch: the TC hold pins the wheel on `tcs_ceiling`, then the brake law takes
`brake_spin` off, and `brake_spin` is the moment's (`roll_torque * spin_compliance`). Gather (iv),
laden `semi`, 25 %, hold off, both driven wheels, every tick from 2.0 to 3.5 s:

    HEAD   omega == tcs_ceiling            slip 0.120  force_long 38370 N  force_roll 0
    patch  tcs_ceiling - omega == 0.0126   slip 0.119  force_long 37929 N  force_roll -380 N
           (== brake_spin, roll_share 1.000)

Drive torque 17833.2 N·m a wheel, engine and shaft torque and the TC latch are the same in both
trees. The loss is `crr N * k / (1 + k)` a wheel (380 * 63 / 64 = 374 N: the curve is linear up to
its peak, so the local slope is the secant's) plus the load the links take off with it
(`suspension_force` 54363 -> 54253 N, 0.2 % of the budget: 77 N): 451 N against 441 measured.
Two wheels: 882 N of the 887 N the steady lines lose.

What is true of the machine: a TC holds the slip with every wheel torque in, so the engine's
surplus pays the moment and the tyre stays on its peak. So the moment acts on the spin before the
TC hold reads it: § Brief.

What the fix gives, derived from the gather's forces: with the hold off the driven pair is back
on the ceiling and the eight undriven wheels drag as at HEAD (they roll back at HEAD too: 76.8 N a
front, 208 N a trailer wheel, both trees), so the cell returns to HEAD's 887 mm, not under it
(`2026-11-15-wheel-leftovers.md` finding 1 expected less: the driven wheels' share is the
engine's under TC). With the hold on the cell still never pulls away, and that is the fix
working: it sits 18 N under its limit at HEAD (`2026-11-15-wheel-fix-landed.md` § Still open)
and the undriven wheels now resist a crawl uphill (about 1.4 kN, zero at HEAD by the `taken`
fault).

## 2. The creep: two regimes, and a slide the judge reads as a roll

Gather (ii), `sedan` (front drive, 1150 kg, `crr N` 38.9 N a front wheel, 28.4 a rear, drive
121.8 N·m = 338 N a front wheel), per wheel at the steady end:

| | fronts | rears | body | sum up the slope |
| --- | --- | --- | --- | --- |
| HEAD, 7.0 % | turn at 0.025 rad/s, tyre 337.0 N, drag 26.1 N | roll back, drag 27.9 N | -0.019 m/s | 782 N |
| patch, 7.0 % | stand (`_spin_held`), tyre 363.1 N of which the moment 24.7 | roll back, 28.4 N | -0.030 m/s | 783 N |
| patch, 5.7 % | turn at 0.060 rad/s, tyre 294.3 N (the moment -38.9) | stand, 27.5 N | -0.003 m/s | 644 N |

Gravity along the slope: 783 N on 7.0 %, 645 N on 5.7 %. Both trees carry the grade. Neither
holds it still.

- **The capacity is the same**: `(T_d + T_r) / r` a front and `crr N` a rear, 811 N, 7.17 %, in
  both trees and on a real car (a standing wheel's moment acts either way).
- **Regime 1, the driven wheels turn.** The tyre needs slip to carry the drive, so a driven wheel
  holding a standing body turns forward at its slip speed, and the moment opposes that turn:
  `(T_d - T_r) / r` a front. With the rears' `crr N`: 651 N, **5.78 %** (measured: holds 5.7,
  the bisect's grid). Under HEAD the drag was keyed on the contact's speed and helped instead:
  the loss is `2 * crr *` the driven axle's share of the weight, 1.38 points here.
- **Regime 2, above that.** The body starts back, the fronts' reaction grows, the moment stops
  them (tick 16) and holds them still with what it has left (24.7 of 38.9 N). A wheel the moment
  holds has no patch spring (`_patch_held` needs `hold_torque`, the brake's and the lock's), so
  its whole force is the slip curve's on `-v`: the body slides at `F dt / m_cap` (363 N on the
  fronts' 199 kg cap mass: **30 mm/s**).
- **HEAD slid too, slower by exactly `g sin dt`.** Its drag's cap is `m_cap |v| / dt - taken`
  with `taken = f.x - m_cap g sin`, so `|v| = (drag + taken) dt / m_cap` = (26.1 + 197.9) /
  (199.1 * 60) = 18.8 mm/s. The difference, 11.3 mm/s, is `g sin dt` (9.8 * 0.0695 / 60 = 11.35):
  the gravity credit of `taken`, the fault the patch removes.
- **The judge**: `measure_grade`'s creep holds when the body is back under `CREEP_ROLL_M`
  (0.25 m) after `CREEP_HOLD_S` (10 s). 19 mm/s reads "holds -0.19 m", 30 mm/s "rolls -0.25 m".

So the table's fall (0.4 to 1.3 points a body) is regime 1's limit under a judge that counts
regime 2's slide as a roll. The stage of § 1 changes none of it (no TC in a creep).

What would hold the grade still up to its capacity is a patch that holds whenever the wheel
stands, whatever stood it (brake, lock or moment), released when the wheel turns. It is not the
moment inside `hold_torque` (`held_force_range` clamps the force inside the hold, so an undriven
wheel stays locked to STICK_SPEED: the hand-back's stop condition). A restructuring of the hold:
its own item, diagnosed first. Never: the moment keyed on the contact's speed, or switched off on
a driven wheel.

**For the user** (`proposals.md`): land the moment with the creep as measured, or hold it for the
standing patch.

## 3. Stop 3 does not reproduce on the cell alone

Gather (iii), `semi` 18 % hand, the cell run alone in each tree: across -0.4 mm at HEAD, -0.1 mm
on the patch (the hand-back, inside the full `doc=park` sweep: -0.0 and -1.7). Inside one 60 s
hold the unit's across position wanders within ±0.5 mm in both trees (HEAD -0.02, -0.12, -0.46,
-0.43, -0.10, -0.36 mm at six times), with no tick-rate alternation. 10 % cross alone: -0.7 mm in
both (the sweep: -0.5 and -1.5). The semi's across figure moves about 1 mm with what ran before
it in the process; the patch moves it 0.3 mm. A3's stop condition is re-worded in the Queue.

## 4. Standing bodies alternate on the patch: stop 2, and a new case

**Stop 2**, gather (i), bobtail `semi` standing. On the patch every wheel stands on the moment
(`omega` 0, `_spin_held` 1, `_patch_held` 0); at HEAD every wheel turns free.

- The along-wheel force answers the contact's speed 82 times harder than HEAD's tyre force
  (`force_long` alt 0.194 against 0.0024 N). Derived: a standing wheel's is `C v`, a free one's
  `C v / (1 + k)`, `k` about 63. HEAD had that stiff answer too, in the drag (`force_roll` alt
  0.071 N, peaks 0.87; the patch's `force_long` peaks 2.0).
- What alternates first is `suspension_force`, rear left, tick 439 (18765.6 -> 18762.0 ->
  18768.3 -> 18761.5 N), one tick BEFORE `force_long` moves, in bursts of 4 to 8 ticks, 5 times
  the size the links could feed back (`link_slope <= 0.22`, `force_long` ±2 N). So the long force
  follows; it is not the trigger.
- The trigger is not in the gathered columns: `compression`, its finite difference (the damper
  reads `(compression - _prev_compression) / delta`) and the spring, damper, bar and link terms
  were not logged.

**New, the 10 % cross cell** (gather (iii), raw log). Every wheel is brake-held in both trees
(`omega` 0, `_spin_held` 1, `_patch_held` 1 on every tick: no hold flag changes in the whole
hold). From tick 771 to the end of the hold the patch's front-left `suspension_force` runs a
3-tick cycle (31213 -> 31392 -> 31356 N; fronts ±90 N, rears ±4 N) and the unit's speeds across
and along and its yaw rate change sign on 70 % of ticks; HEAD goes quiet at the same time (0.2 to
0.6 N). The printed movement is the same (-0.7 mm), so `doc=park` does not see it. The patch's
held wheels' slip is already rougher before the cycle starts (tick 767 to 770: -3.6, -3.9, -5.4,
-3.3 e-5 against HEAD's -1.54, -1.55, -1.60, -1.66 e-5).

For a brake-held wheel the moment changes nothing (`roll_share` 0.005: the brake stops it either
way). The one thing the patch changes there is that `surface_drag_force` is gone. So what both
cases share: **a standing wheel lost a force that stopped its contact along the wheel in one
tick** (`m_cap |v| / dt - taken`: with the tyre's own, the whole one-tick cap), and is left with
the slip curve's slope, `a = C dt / m_cap` of that cap, which is 1 only on the wheel whose own
slip floor is the shared one (`floor_vel = maxf(slip_floor, _own_slip_floor)`; the `sedan`'s
rears 0.74; by hand the laden `semi`'s fronts about 0.3, and the fronts are where the cross cell
alternates). The patch spring's stiffness (`STICK_TICK_STIFFNESS` 0.25) is critical for a damper
at `a = 1`.

That is a hypothesis: under-damping alone decays, and a cycle that sustains needs a second path
(the damper's finite difference, the links' one-tick lag) that the columns do not show. The
Queue line (A2) logs the missing terms and runs the test that would prove it: on the patch, a
standing wheel (`omega == 0` after its settle) takes along the wheel the force that stops its
contact this tick, under its budget, where it takes the curve's now. It is static friction's own
discrete form, what the lateral axis already does, and no filter; whether it is the fix is
judged after the run.

## Brief: the moment as a stage of the settle law (A3's "Do", on top of the patch)

`RayWheel`:

- `_integrate_spin` takes `roll_torque` as its own argument and latches `roll_spin =
  roll_torque * spin_compliance`; `brake_spin` is the service brake's alone, as at HEAD.
- `settle_spin`, after `omega += torque * spin_compliance`: the moment first, `omega =
  move_toward(omega, 0.0, roll_spin)` (it stops a wheel and never reverses it; no ABS floor: the
  floor is the brake's), `roll_reacted` its torque (`|spin taken| / spin_compliance`), `force_roll
  = -signf(spin before it) * roll_reacted / wheel_radius` (a readout); then the TC hold and the
  brake as at HEAD, on the spin the moment left.
- `settled_spin(spin, can_take, stop_at, tcs_share, tcs_at, roll_take)` =
  `braked_spin(tcs(move_toward(spin, 0, roll_take)))`: monotone and piecewise linear, as its doc
  requires.
- Gone from the patch: `roll_share` (the split is exact now: `brake_reacted` is the brake's
  alone), so `heat_brake` is HEAD's line; the stop ledger of `measure_grade` and the other tool
  sites the patch moved to `roll_share * brake_reacted` read `roll_reacted`. `_spin_held` keeps
  HEAD's expression (`brake_spin > 0.0 and omega == 0.0`): a free wheel the moment stops is not
  "held", so `measure_vehicles`' rest pass can count `_spin_held` again.

`Differential`: `braked_coupling_torque`, `_settled_spread` and `settled_mean_spin` take
`roll_take` beside the other four arrays (`WheelDrive` fills it; the converter's solve reads it
through `settled_mean_spin`). `_settle_kinks` gains the moment's own kinks, `±roll_take`, and
maps every kink of the TC-and-brake law out through it: a kink `k > 0` sits at `k + roll_take`,
`k < 0` at `k - roll_take`, `k == 0` lies on the moment's flat, whose ends are kinks already.
`held` counts `roll_take[i] > 0.0`. The walk's last step ("past the last kink every output turns
with its full compliance") still holds: all three laws have slope 1 beyond their outer kinks.

Tests, failing on the patch as built:

- `settled_spin` with a spin past the ceiling, no brake, `tcs_share` 1.65, `roll_take` 0.0126
  returns the ceiling (the patch's law, the moment as `can_take`, returns the ceiling less
  0.0126).
- The existing `braked_coupling_torque` property tests (the settled spread is zero at the
  returned torque, or the capacity binds) with a `roll_take` on each output, the moment's kinks
  inside and outside the TC's.
- A driven bench wheel under TC at its ceiling reports the curve's peak as `force_long` with a
  rolling moment on it.

The run that fails now: `measure_grade -- semi rollback grade=25 nohold verbose`, patch 1577.6 mm,
steady `rear 75861 N`; after, within about 1 % of HEAD's 887.2 mm and `rear` about 76.7 kN, the
driven wheels on `tcs_ceiling` every tick.

Expected to stay as the patch measured: stops (`sedan` 100 %: 41.1 m; under ABS the moment is
inside the torque the floor holds, whichever stage carries it), `wheel_slip` on FIELD, `all 45
track strict`. Expected, not stops: `semi rollback` 25 % with the hold never forward (§ 1); the
creep table as § 2 unless the user holds the item.

## For other items (seen, not acted on)

- `measure_grade`'s creep column is a slide speed against a gate at both HEAD and the patch
  (§ 2): `docs/drivetrain.md`'s creep table reads as a static hold and is not one. For unit 16.
- The `semi` parked across 10 % carries -2.6 kN (left) and -1.4 to -2.1 kN (right) along each
  held wheel of the unit, in both trees: the patches wound against each other and the coupling.
  For the towing item.
- `doc=park`'s `semi` across figure depends on what ran before it in the process by about 1 mm
  (§ 3): unit 16, with the lone-against-sweep note the measure docs already carry.

## Deferred

Everything: this session fixes nothing. Queue: A2 (the standing alternation, Opus), A3 (the fix,
after A2 and the user's answer on the creep). `proposals.md`: the creep.

## Commits

The journal's only.
