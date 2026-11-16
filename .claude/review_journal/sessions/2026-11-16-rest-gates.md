# 2026-11-16: A7, the standing rig's rest gates (Sonnet)

Run: `node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_semi_launch.tscn -- <unit> [trailer=bobtail] steady strict`.

| rig | flips /s | step kg a tick |
| --- | --- | --- |
| `semi`, box | 0.0 | 0.01 |
| `semi`, bobtail | 0.3 | 0.02 |
| `semi-conventional`, box | 0.0 | 0.00 |
| `semi-conventional`, bobtail | 1.0 | 0.03 |

Fault on the day (`2026-11-13-f1-rest-guard.md`): 59.7 /s, 8.2 kg or more.

Limits: `REST_FLIPS_S` 20 -> 3 (3x the worst read, the old margin; 20x under the fault).
`REST_STEP_KG` 2 -> 1: the old 2.5x margin over 0.03 would be 0.08 kg, but the towing item (c)
reads whole-kg AXLE steps of up to 1 kg on the laden `semi` (`measure_vehicles -- semi 20 rest`),
so it stays at 1 kg until (c) lands (stage B); 8x under the fault. Tighten it then.

Comment (`measure_semi_launch.gd:75-81`): the "each under its own one-tick cap" sentence was stale
(A3 gave the rolling drag no cap of its own; `docs/vehicles.md` § One-tick caps says so), reworded;
the free-wheel reading is 1 /s and 0.03 kg now (was "7 /s and 1 kg"). `docs/vehicles.md` and
`vehicle_measurements.md` name the constants only: no change. No test pins the limits.

Commit: a16a944. Full suite and `check_docs` pass.
