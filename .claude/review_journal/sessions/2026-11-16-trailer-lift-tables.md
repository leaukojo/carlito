# 2026-11-16: A4b, the trailers' roll-over lift tables on the raw `accel_lat` (Opus, auto)

Started at fa7c9d6. Brief: `summary.md` stage A, A4b (approved by the user). Evidence:
`2026-11-16-accel-raw.md` § Runs.

## Runs (`--fixed-fps 60`)

- First wheel lift, trailer's g (`measure_semi_launch -- semi trailer=<t> ramp noesc notrsp`):
  box 0.342, flatbed 0.556, tanker 0.378, tipper 0.434, the same as A4's after-run. The static
  bogie reads 17571 / 10277 / 15343 / 13977 kg; the table's x stays (brief: bogie load unchanged).
  Written into each `<t>_spec.tres`, dated 2026-11-16 (was 0.355 / 0.562 / 0.384 / 0.438).
- Baseline before (the committed tables, A4's), ESC on and roll-over on: corner chatter 0 / 2,
  step 0 / 11 with a trailer wheel up in 1 of 18 and none over; P7 step 0 / 0, wind-on 0 / 1.
- After (`measure_vehicles -- doc=trailer_roll`, `measure_semi_launch -- semi doc=trailer_roll`),
  ESC on and roll-over on: corner 0.30 -> 0.28 g, VDC 2.43 -> 2.58 s, chatter 0 / 2 -> 0 / 1;
  step: none over, a wheel up in 1 of 18, VDC 3.43 -> 6.23 s, chatter 0 / 11; P7 step unchanged
  (0 / 0), wind-on VDC 3.97 -> 3.95 s, chatter 0 / 1 -> 0 / 0. Off / on: the step's VDC
  12.17 -> 12.50 s, the P7 step lifts at 0.344 g (was 0.343). Off / off and on / off unchanged.
- Stop condition (a trailer over, or chatter above the baseline, with both on): not hit. The
  longer VDC time on the step is the control acting from the lower, measured threshold.

## Done

- 65cfd41: the four `trailer_roll_lift_g` and both `doc=trailer_roll` regions.
- `test_trailer`, `test_stability_control` pass (119); the full suite passes (2524, 0 failures);
  `check_docs` clean (pre-commit).
