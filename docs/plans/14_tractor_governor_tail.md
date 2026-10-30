# Plan — The tractor's governor tail at its sourced droop

At the top hand-throttle setting the tractor's all-speed governor runs on its torque curve's own
2200-2600 rpm tail, an 18 % droop, where the recipe sources 7 % and a Deere 6R's rated 2100 / fast
idle 2250 (`tools/gen_kenney_vehicles.gd`, the `pedal_map` COMPROMISE). The tail stayed because a
7 % tail (high idle ~2350) cut the top speed to ~35 km/h. Phase 2b's gearing (40 km/h at the
2200 rated speed) took that cost away: the road-speed limiter now sets the top speed. This plan
reshapes the tail and drops the COMPROMISE, and closes the plough hold's slip left by the 6R
geometry change (phase 2).

Written 2026-10-29. Status: **not started.**
Serves: the PTO-speed lesson (`tractor_pto_speed`): rpm sag under load reads a real governor's
droop, and `engine_load` near the top setting follows a sourced line, not a curve artefact;
the plough lesson's draft hold reads a working `wheel_slip`.
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — The tail and what it moves (effort: medium; mode: plan-mode-first)

- Source the 6R class's high idle / rated pair from a page actually opened (the recipe's 2100 /
  2250 has no `docs/sources.md` row yet), and the droop it gives.
- Measure at HEAD, alone, `--fixed-fps 60`: `measure_vehicles -- tractor-kenney 60` (top speed),
  `freerev`, `plough pto governor` (the droop gate), `cruise`; `tractor-cvt` likewise.
- Output: the proposed curve tail points and the figures they move. Done when the user has seen it.

## Phase 1 — The reshaped tail (effort: high; mode: plan-mode-first)

- The recipe's `torque_curve` tail and `redline_rpm` (high idle) only; the curve below rated stays
  (low-end torque is what pulls a drawbar trailer away; traction is ballast, never the curve).
- Retire `tractor-kenney` from `docs/vehicles.md` § Rejected designs' "torque-curve tails" entry and
  the COMPROMISE in `docs/drivetrain.md`'s governor paragraph.
- Regen (`vehicle-feel` skill); `test_tractor`, `test_vehicle_catalog`, `test_kenney_variants`
  pass; re-run the `doc=` tables carrying a tractor row (`cruise`, `freerev`, `accel`).
- Done when the user has driven the PTO-speed challenge and a road run for feel.

## Phase 2 — The plough hold slips (effort: high; mode: plan-mode-first)

- `measure_vehicles -- tractor-kenney 20 plough`: the 7 and 10 km/h holds reach only 3.9 / 3.8
  km/h, in D1 at 54-56 % slip (2WD, open diff, field grip 0.50), against 10 % before the 6R
  geometry change; the 3 km/h hold slips 16 %. The challenge `course` reads as before.
- Measure first which term carries it (the rear axle's load with the plough down, the open diff's
  peel, the draft against D497), then the user picks the fix; no detune.
- Re-run the `plough` and `course` passes; done when the 7 km/h hold holds its speed.
