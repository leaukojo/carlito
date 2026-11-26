# 2026-11-19: a swinging front axle's roll lever (unit 4, finding 1's fix)

Started at cadee91. Item: the Queue line "A swinging front axle's roll takes the weight on the
wrong lever"; brief: `sessions/2026-11-15-unit4-derivations.md` § Finding 1's brief. Prediction
only (`BalanceModel`); nothing the physics tick reads changes. Changes left uncommitted for the
parent session.

## Brief against HEAD

`_roll_state` is still `balance_model.gd:146-194`, the forms as the brief quotes them (`:168`
free, `:170` gate, `:176` on the stop, `:184` front lifted, `:190` rear lifted). The tests are at
the brief's lines (`:835`, `:851`, `:873`, `:888`). No drift.

Two points of the brief's test forms, checked by hand from its own derivation before editing:

- `:835`'s rear: the brief writes `rear * t_r / 2 == (weight_h - pivot_w) * (g + phi)`, a
  shorthand that drops the side force's own share at the pivot. From
  `k_r phi = moment - pivot_m + (weight_h - pivot_w) phi`: `rear * t_r / 2 == weight_h * (g + phi)
  - pivot_w * phi - pivot_m`. Written so.
- `:888`'s `wide` half, re-derived as the brief asks. `_swing_spec(stop, 1e9)`: `h` 0.77,
  `pivot_h` 0.57, front share 0.4, so `1 - pivot_w / weight_h` = 0.704; the triangle 0.830 g, the
  trapezoid's base 0.974 g. At 10 deg the new tip is 0.974 - 0.1745 * 0.704 = 0.851 g, over the
  triangle: a 10 deg stop no longer tips at the rear's first lift (at HEAD 0.7995 < 0.830, it
  did). The rear-lifted form with rigid tyres asks the front for `moment - cap_r t_r / 2 +
  (weight_h - pivot_w) stop`, so the tip is at the first lift exactly when the new trapezoid is
  under the triangle: a stop past 11.7 deg. `wide` takes 15 deg (0.790 < 0.830), and the test
  asserts that precondition instead of assuming it.

## Baseline at HEAD (cadee91)

`measure_vehicles -- <tractor> 60 track corner` (`--fixed-fps 60`):

    tractor-kenney: peak 0.74 g (slid); tips first at 0.72 g smoothed; pred rear first, -1.9 %,
      unsaturated (0.62 / 0.63, ends on fold); model tips at 0.64 g; roll 6.3 deg at the peak
      (pred inf at the tyres' 0.72 g), front 30 % (pred 24 %) of the load transfer
    tractor-cvt: peak 0.72 g; tips first at 0.70 g smoothed; pred rear first, -1.9 %, unsaturated
      (0.62 / 0.63, ends on fold); model tips at 0.64 g; roll 6.1 deg (pred inf at 0.71 g), front
      29 % (pred 24 %)

`gen_kenney_vehicles`: no file written differently (`git status` clean but the session file); the
tractors' balance line: `K -0.27 deg/g at 0.15 g ..., LLTD 24 %; limit 0.86 g, rear first (front
0.88 / rear 0.86 g, -2.1 %), roll inf deg there`.

## The fix (uncommitted)

`balance_model.gd` `_roll_state`: the brief's forms, `pivot_w = cap_f * pivot_h` (read with
`f.get("pivot_h", 0.0)`, 0 on every body without a swinging front, so `(k_f - pivot_w) * stop` is
`k_f * 0` there as before); free `phi = (moment - pivot_m) / (k_r - weight_h + pivot_w)`, `psi =
pivot_m / (k_f - pivot_w)`, `df = 2 k_f psi / t_f`, `free = phi - psi <= stop`, the gate `k_r >
weight_h - pivot_w and k_f > pivot_w`; the stop (`:185`) and rear-lifted (`:199`) forms take
`(k_f - pivot_w) * stop`. The front-lifted form and `_corner_wheels` untouched. Doc comment and the
two branch comments follow.

Tests, `test_balance_model.gd`: new `test_inside_its_stop_the_side_force_and_the_weight_share_one_lever`
(the brief's fixture); `test_inside_its_stop_a_swinging_front_carries_only_its_pivots_moment` and
`test_the_front_takes_up_roll_without_a_step_at_its_stop` take the new free front
(`_free_front`, `2 pivot_m k_f / ((k_f - pivot_w) t_f)`) and rear forms;
`test_past_its_stop_a_rolled_body_tips_on_the_wider_base` takes `_trapezoid_g` (`- stop (1 -
pivot_w / weight_h)`) and its `wide` half 15 deg with the precondition asserted (above).
`test_on_stiff_tyres_the_rear_inner_lifts_on_the_stability_triangle` unchanged, passes.

The new fixture against HEAD's `balance_model.gd` (a temporary one-test suite, deleted after; the
gdUnit suite stops at its first failing test, so the whole file at HEAD shows only the first):
`phi` +2.662 % at 0.1 / 0.3 / 0.5 g, FAILED; after, 0.00000 %, PASSED. After, on
`tractor-kenney`: `tip_g` 0.6525 (HEAD 0.6354, the derivation's hand figure 0.652); at 0.1 / 0.3 /
0.5 g roll 0.4964 / 1.4891 / 2.4819 deg, front transfer 2143.7 / 6431.0 / 10718.4 N (the
derivation's "one lever" and "beam's own lever" figures exactly). `test_balance_model`: 54 cases,
0 failures.

The doc comment of `_roll_state` stays as at HEAD: a clause on the pivot's lever put the block at
12 lines, over `check_docs`' 10; its "see the comments within" points at the branch comments,
which now state the lever.

## Runs after

`measure_vehicles -- <tractor> 60 track corner`: every measured figure byte-equal to HEAD on both
tractors (the logs diffed with the predicted cells masked). The predictions moved:

    Pred cell:       rear first, -1.9 %, unsaturated (0.62 / 0.63, ends on fold)
                  -> rear first, -1.0 %, unsaturated (0.63 / 0.64, ends on fold)   (both tractors)
    model tips at:   0.64 g -> 0.65 g
    LLTD pred:       24 % -> 25 %   (measured 30 % / 29 %, unchanged)

`corner_limit` still returns a turn (not empty): the stop condition is not met. The tip, by a
temporary one-test suite (deleted): the rear's first lift 0.65224 g, `tip_g` 0.65250 g; just under
the tip the body sits on the stop at 12.892 deg with the front at 26053 N of its 26068 N cap. The
derivation's hand figures (the front 0.4 % under its cap, ~12.9 deg, ~0.653 g) hold: the tip
leaves the rear's first lift by 0.0003 g. `docs/tractor.md:179-183` ("`BalanceModel` lifts the
rear inner on that triangle", the tip under the lugs' slide) stays true: unchanged.

`gen_kenney_vehicles`: no spec or scene written differently (`git status` after the run shows only
this session's files), so `esc_reference_k` and every generated input the sim reads are as at
HEAD. Its printed balance line for both tractors moves only `LLTD 24 %` -> `LLTD 25 %`.

Followed: `docs/vehicle_measurements.md` § Cornering's two tractor rows (the Pred cell, from the
run's own print; the measured cells and the header date untouched) and the recipe comment
`gen_kenney_vehicles.gd:566` (`0.62 / 0.63` -> `0.63 / 0.64`). Nothing else in `docs/` cites a
moved figure (grep for the old cell, `LLTD 24`, `0.64 g`, `0.635`).

Tests: `test_balance_model` 54 / 0 failures, `test_vehicle_catalog` 55 / 0 (no ESC table moved),
`test_tyre_class` 16 / 0; the suite 2527 cases, 0 failures. `check_docs` clean.

Prediction only, checked: the diff touches `balance_model.gd` (read by the generator's report,
`measure_vehicles`' pred columns and `StabilityControl.reference_table`, a generator-time table
that came out unchanged), tests, a doc table and a tool comment; nothing the physics tick reads.

Committed by the parent session after review: 3aa82a3 (the continuity of the free and on-stop
forms at `phi - psi = stop` re-checked by hand: both reduce to `psi (k_f - pivot_w) = pivot_m`).

Journal: the Queue line removed; unit 4's Result names this file. `2026-11-16-trailer-lift-tables.md`
deleted (the eleventh newest, named nowhere).
