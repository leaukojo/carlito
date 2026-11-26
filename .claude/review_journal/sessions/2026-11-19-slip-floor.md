# 2026-11-19: the cover `TractorTelemetry.SLIP_FLOOR_KMH` (cover sweep (5))

HEAD 7ecf7e6. Item: `summary.md` Queue, the cover sweep's (5); its proving run:
`sessions/2026-11-14-cover-sweep.md` § Proving runs (5), amended by
`sessions/2026-11-15-wheel-leftovers.md` § 5. Ends in a proposal (a contract signal).

## What it covers

- `tractor_telemetry.gd:20-21` `SLIP_FLOOR_KMH := 0.5`, "Wheel speed below which slip reads 0
  (the ratio is noise near zero)", read at `slip_pct` (`:95`, `if wheel_speed_kmh <=
  SLIP_FLOOR_KMH: return 0.0`). One caller: `tractor.gd:184` (`wheel_slip`, contract `u8` %, warn
  60). `wheel_speed` is the rear axle's mean `|omega| * r` (r 0.805 m), `ground_speed` the body's
  `|speed|`, the COM's forward velocity (`base_vehicle.gd:259`).
- `git log -S SLIP_FLOOR_KMH`: the initial commit only, so no message gives a reason beyond the
  comment's symptom. `test_tractor.gd:101-104` repeats it and pins the floor.

## Proving run

Floor at 0 (`SLIP_FLOOR_KMH := 0.0`, the `<= 0` guard kept) and a per-tick print in
`Tractor._tick_extras` behind an env var (frame, signed speed, `wheel_speed`, `ground_speed`,
`wheel_slip`, pitch rate `angular_velocity . basis.x`, each rear's `omega`, `_spin_held` and its
contact's forward speed). Both reverted with `git checkout` right after the runs. Run line, each
body `tractor-kenney` and `tractor-cvt`, logs in the session's scratchpad:

```
SLIPLOG=1 node tools/godot_run.mjs -- --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- <body> 20 rest          # D, pedals up
... -- <body> 20 rest=n    ... -- <body> 20 rest=handbrake    ... -- <body> 15   # the accel pass: the pull-away
```

Every run printed its report and `[godot_run] exit=0`; 599 logged ticks a rest pass, 1621 the
accel pass.

| pass | ticks non-zero | where | largest | `wheel_speed` there |
| --- | --- | --- | --- | --- |
| `rest` (D; kenney: hill hold STANDSTILL on; cvt: clutch locked), 2 of 4 wheels held | 0 of 599 | | | rear `omega` exactly 0 every tick |
| `rest=handbrake` | 0 of 599 | | | the same |
| `rest=n` (0 of 4 held) | 15 of 599 | frames 3-8 and 19-27 only | 98 % | at most 0.102 km/h |
| accel (pull-away) | 13 (kenney), 8 (cvt) under 0.5 km/h | the settle's frames 3-7, then the launch's first ticks of spin | 99 % | |

Both bodies read the same to the digit in N (one chassis; the transmission is out of it).

- **In N, the spawn's settle.** The body is placed at the springs' unloaded height
  (`GroundDriveSpec.rest_ride_height`, `rest_length`; the game's `Level._rest_transform` and the
  rig alike) and drops onto them, pitching up to 0.049 rad/s. The free rear wheels follow their
  contacts (rim and contact speed 1 to 5 mm/s apart), the contact moves against the COM by the
  pitch rate times its lever, and the COM's speed passes through 0. Frame 25: COM -0.48 mm/s, rear
  contact -27.6 mm/s, rim -22.8 mm/s (`omega` -0.0283 rad/s), pitch -0.0267 rad/s: `wheel_slip` 98.
  Frames 9-18 read 0 (the COM outruns the rim, up to 0.139 km/h against 0: the unsigned clamp). From frame 29 to the run's end
  (600) the rears' `omega` is exactly 0 and the `<= 0` guard alone gives 0; `ground_speed` stays
  under 0.008 km/h after frame 60. Nothing is non-zero at rest once the body has settled.
- **The pull-away.** `tractor-kenney`: frames 8 and 9 read 80 and 99 % at 0.30 and 0.47 km/h,
  where the rim truly leads its contact (frame 9: rim 0.130 m/s, contact 0.058 m/s, COM
  -0.0007 m/s); frame 10 (0.63 km/h, published today) reads 89, then 81, 73, 67 %. `tractor-cvt`:
  frames 18-21 read 61, 99, 81, 68 % (frame 18: rim +0.051 m/s, contact -0.008 m/s), then 57 % at
  0.54 km/h. The pass's second launch (frames 725-730, 739-742) repeats both. Real spin, on one
  curve with the readings above the floor: the floor cuts that curve at 0.5 km/h.
- Above the floor, a launch's reading also carries the squat: frame 13 (kenney) reads 67 % COM
  to rim, 39 % contact to rim (contact 0.186, COM 0.100 m/s, pitch 0.086 rad/s). The floor does
  nothing there, and a real radar reads its own mount's speed, on the frame 2 to 8 ft above the
  ground (DJRVS II installation instructions, 11001-1208C Rev B, p. 4, opened), not the contact's:
  the body-point reading is the model. No finding.

## A real unit's floor

- The DJRVS II installation instructions (Dickey-john, 10 pages, all opened) give no velocity
  range. They treat a reading at standstill as an installation fault, not a thing to filter: p. 8,
  "Excessive vibration may cause ground speed (MPH) readings to be above zero when the vehicle is
  stationary. ... If the ground speed readings are above zero, the sensor must be mounted in an
  alternate, more stable location"; p. 4 (g) the same.
- A search summary gives the Radar II / III a range from 0.53 km/h (an agriexpo catalog page,
  403 when opened): not a sourced figure. Were it one, it floors `ground_speed`, not
  `wheel_speed`: a radar reading 0 under a turning wheel gives 100 %, the opposite of this floor.
  No page makes the floor a model.

## Finding

The floor hides, on a contract signal: a burst of up to 98 % (warn 60) for 0.42 s after each spawn
or respawn with the rears free (N), a true quotient of two points' speeds on a body still settling
onto its springs; and the first 2 to 4 ticks of a launch's real spin (61 to 99 %) under 0.5 km/h.
At rest after the settle it hides nothing: the wheel's ring is gone (d22b3ee) and a still wheel
reads `omega == 0` exactly. The comment's reason ("the ratio is noise near zero") is wrong now:
the ratio near zero is what the two speeds are. Sorted by § Covers: on a contract signal, so a
proposal recommending removal (`proposals.md`, "The tractor's `wheel_slip` loses its 0.5 km/h
floor"). The spawn's drop is a placement, not a fault in the slip law; the proposal names it as
the source of the burst and the one way to quiet it that is no cover.

No guard test: one that fails on the hidden burst cannot pass with the floor in, and a failing test
is not committed. The proposal's change rewrites `test_slip_is_unsigned_and_quiet_at_standstill`.

## Fixed

Nothing (a proposal).

## Commits

The journal's only. Then, on the user's word (2026-11-19): the floor removed (const, comment,
`docs/tractor.md`, the test's two floor asserts replaced by a crawl), commit `review: the
tractor's wheel_slip loses its 0.5 km/h floor`; the spawn's settle burst is left visible (summary.md, "Please verify", Known).
