# 2026-11-13: F1's rest guard (what `REST_FLIPS_S` and `REST_STEP_KG` are sized on)

Compressed 2026-11-16 to what the Queue still reads (the rest-gates item, the towing item). The
full file: `git show c903d45:.claude/review_journal/sessions/2026-11-13-f1-rest-guard.md`.
Commits: 17842e1 (the guard, CI runs it laden on both tractor units), 6604613 (the parked-rocking
plan distilled).

Run: `node tools/godot_run.mjs -- --headless --path . --fixed-fps 60
res://tools/measure_semi_launch.tscn -- <unit> [trailer=bobtail] steady strict`, the
`rest reading:` line (speed sign changes a second, `axle_load` step a tick).

## The two limits

`REST_FLIPS_S` 20 /s and `REST_STEP_KG` 2 kg each sit between the ring that was left on the day
and the fault the gate guards (F1, the standing rock):

| rig | d849de9 (F1 fixed) | `wheel.gd` at d849de9~1 (F1's fault) |
| --- | --- | --- |
| `semi`, box | 0.0 /s, 0.81 kg: PASS | 59.7 /s, 12.67 kg: FAIL |
| `semi`, bobtail | 6.7 /s, 0.46 kg: PASS | 59.7 /s, 98.50 kg: FAIL |
| `semi-conventional`, box | 0.0 /s, 0.00 kg: PASS | 59.7 /s, 8.23 kg: FAIL |
| `semi-conventional`, bobtail | 5.0 /s, 0.34 kg: PASS | 59.7 /s, 139.00 kg: FAIL |

So the old margins: flips 20 against 6.7 read (3x) and 59.7 at fault; step 2 kg against 0.81 read
(2.5x) and 8.2 at fault. The gate's comment says the limits are a tolerance over a known ring.
Since the wheel fix (d22b3ee): bobtail 0.7 /s and 0.11 kg, laden 0.0 /s and 0.95 kg
(`2026-11-15-wheel-fix-landed.md` § Measured).

On the day, whole-kg `axle_load` changes at rest: `semi` box 73 % of ticks (0.8 kg a tick, 3 max),
bobtail 52 %; `semi-conventional` box 0 %, bobtail 31 %. `trailer_axle_load`: 0.0 kg a tick.

## For the towing item

- The roll-back that moved with F1's fix (`measure_grade -- <v> rollback [nohold]`, d849de9
  against `wheel.gd` at d849de9~1): only the laden `semi` 25 % `nohold`, 685.1 -> 927.4 mm; every
  other cell within 1 mm. Cause: `2026-11-15-wheel-leftovers.md` finding 1 (`taken`).
- Seen, not traced: a standing rig drifts at a steady 0.04 to 0.2 mm/s in the 7 to 10 s window
  (`rest`: laden `semi` +0.04 in D, -0.20 on the foot brake with every wheel held;
  `semi-conventional` -0.17). Settling, or a slide.
- `pickup` 10 % cross in `doc=park` moved 0.2 -> 0.9 mm with F1's fix: under a millimetre in a
  minute, not traced.
