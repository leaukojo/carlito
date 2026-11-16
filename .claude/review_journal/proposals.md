# Proposals

Changes that need the user's decision. One entry each: what, evidence, cost, risk. An approved
entry moves to the Queue in `summary.md`; a refused one is deleted.

Approved 2026-11-16 and written into Queue A3: the converter creep lands as measured
with the rolling moment (`sessions/2026-11-16-rolling-moment-diagnosis.md` § 2). The other
choice, a patch that holds any standing wheel, was not taken.

## The trailers' roll-over lift tables, re-measured on the raw sensor (A4, 2026-11-16)

- **What.** `trailer_roll_lift_g` in `src/vehicles/truck/trailers/{box,flatbed,tanker,tipper}_spec.tres`
  takes the raw first-lift g (`measure_semi_launch -- semi trailer=<t> ramp noesc notrsp`, "first
  wheel lift", trailer's), then `doc=trailer_roll` and `measure_semi_launch -- semi
  doc=trailer_roll` are re-run.
- **Evidence.** The tables were measured off the smoothed `TowedBody.accel_lat`, which b76f263 made
  raw. First-lift g, baseline at 32d269b vs after: box 0.353 -> 0.342 (table 0.355), flatbed
  0.561 -> 0.556 (0.562), tanker 0.382 -> 0.378 (0.384), tipper 0.438 -> 0.434 (0.438). With full
  protection (`doc=trailer_roll`, ESC on, roll-over on) the 18-run sweep now lifts a trailer
  wheel in 1 run (was 0); none goes over. Runs and logs: `sessions/2026-11-16-accel-raw.md`.
- **Cost.** Four one-number edits, then the two `doc=` runs (about 5 min).
- **Risk.** Roll-over control acts about 0.01 g sooner on the box, which changes when a laden rig
  brakes in a hard corner. Without it, the control is late by the same amount.
