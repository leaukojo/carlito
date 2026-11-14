# 2026-11-14: ground under a deck, the start test (fix from the brief)

Item: the Queue's top Opus line (the brief from `2026-11-14-sweep-rest-disagree.md` § Which
trigger). Plan approved by the user in plan mode (it stands for the proposal: the fix changes a
contact).

## Findings

1. **The deck case** (the brief): `RayWheel._contact_pass`, after a sweep that hit, never asks
   whether the sweep left out a body the tyre starts inside. Fix: the start rest test, the
   engine's own skip test, sends the wheel to `_carried_sweep`.
2. **A dangling citation**: `docs/vehicles.md` § Contact, "Cost, `semi` + `box`: the cast costs an
   order of magnitude over the ray, natively and on web (`kerb`, `docs/vehicle_measurements.md`
   § Measure-tool run lines)". No measure tool times the contact (`grep get_ticks_usec tools/*.gd`:
   only `_build_reference`'s ESC table timing), and the run lines name no cost readout. Queued.

## Log

- The fixture (`test_ground_under_a_deck_leaves_the_tread_on_the_deck`, the helper's `under`
  restored) fails at HEAD: `Expecting '0.010840' in range between '0.058000' <> '0.062000'`.
- The fix in `_contact_pass`: the start rest test hoisted above the no-hit branch (it already ran
  there), and after it, a non-empty start sets `_swept_past` and returns. `test_wheel_spin` 158
  cases, 0 failures; the fixture passes on both welded flags and both gaps.
- `docs/vehicles.md` § Contact synced; the docs total sat at its cap (269723), so the sentence was
  tightened to fit (269721).
- Runs, `--fixed-fps 60`, after then before (HEAD's `wheel.gd`), each with a temporary timing
  probe summed over `_contact_query` (reverted by the run script).
- Full suite: 2507 cases, 0 failures.

## Measured (f7bac55 against 782de27's wheel)

Diffed with the timing lines filtered out:

- Byte-equal: `sedan,semi 45 side`; `scrape` (two bodies, `steer=60`, `onebody`) but one count; the
  CI gates, all PASS: `all 45 track strict` (drift 0.000 / 0.031 / 0.015 m), `measure_semi_launch`
  both units (floors P2 13801 / 11346 N, P6 13822 / 11382 N; rest reading 0.00 / 0.80 kg a tick),
  `measure_air_loss -- all strict` 9 of 9.
- `scrape`, two bodies: `firetruck`'s sweeps by contact 1 -> 10, its forces equal to the newton.
- `scrape onebody`: `firetruck` FR still 26 sweeps, 501 N across (two bodies: 217 N). The last
  session's expectation (it stops flipping with the rest test) does not hold: nothing moved, so the
  skip is not its cause. Queued for diagnosis.
- `sedan,semi 45 kerb`: only the `semi`'s 20 cm coast at 30 km/h moved: 8 cast start overlaps (the
  tyre inside the kerb at full bump, now read there) and 8 sweeps by contact; peak |a_y| 4.77 ->
  2.89 g, min speed 7.73 -> 7.75 m/s, end 7.74 -> 7.87; RL / RR "on the new level +0.18 -> +0.09 m
  ahead, lean 60 -> 39 deg, largest tick 126 -> 122 / 121 mm, peak 16.3 -> 14.9 / 14.8 kN". The
  brief expected 22 ticks (a deleted probe's tally, "start inside" on the 20 cm kerb); here the
  `sedan` is byte-equal and the `semi` moves on 8, the count af471cd's trigger gave. Not reconciled:
  the probe is gone (the kept-probe Queue item would settle it).
- Cost (the probe, native, summed over `_contact_query`): `kerb` 20.88 -> 21.70 us a query
  (89014 queries), `side` 2.33 -> 2.26, `scrape` 23.59 -> 23.69, `onebody` 23.70 -> 23.86. The extra
  rest test is under the timing noise but on `kerb` (+4 %).

## Commits

- f7bac55 wheel: a body the sweep left out sends the wheel to the sweep by contact (with the
  fixture test and the `docs/vehicles.md` sync).
