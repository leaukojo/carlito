# 2026-11-26: gather, the park pawl's second steady state (Sonnet)

Question: does a parked `suv` already rolling back when P goes in end up held, or creep forever?
Scenario `rolled` added to `measure_grade`'s park mode (f5cd5ae); run lines in
`docs/vehicle_measurements.md` § Measure-tool run lines.

## Run lines (shown to work)

```
node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- suv park=16.7 rolled
node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- suv park=16.7 pawl verbose
```

`rolled`: 1.5 s settle on the foot brake, then N with no brake (hill hold off) until 0.3 m/s down
the slope (P went in at 0.310 m/s), then P (`GEAR_P`) for 20 s, no brake. The control (`pawl`) is
the existing settle-then-P start; its trace is the park mode's `verbose` line (no `lock_torque`
or speed column, `moved` instead).

## Rolled run: per second after P

All four wheels agree to 1e-4 rad/s, so one `omega` is shown; `_spin_held` was false on all four
wheels every second; `lock_torque` 3000.0 on all four.

| t s | speed m/s | moved mm | omega rad/s (each wheel) | `_spin_held` | `lock_torque` |
| --- | --- | --- | --- | --- | --- |
| 1 | 0.1071 | 133.5 | -0.02101 | false | 3000 |
| 2 | 0.1122 | 246.2 | -0.02386 | false | 3000 |
| 3 | 0.1130 | 359.2 | -0.02403 | false | 3000 |
| 4 | 0.1131 | 472.2 | -0.02401 | false | 3000 |
| 5 | 0.1130 | 585.3 | -0.02402 | false | 3000 |
| 6 | 0.1130 | 698.3 | -0.02401 | false | 3000 |
| 7 | 0.1130 | 811.3 | -0.02400 | false | 3000 |
| 8 | 0.1130 | 924.3 | -0.02402 | false | 3000 |
| 9 | 0.1130 | 1037.4 | -0.02401 | false | 3000 |
| 10 | 0.1130 | 1150.4 | -0.02401 | false | 3000 |
| 11 | 0.1130 | 1263.4 | -0.02401 | false | 3000 |
| 12 | 0.1130 | 1376.4 | -0.02400 | false | 3000 |
| 13 | 0.1130 | 1489.5 | -0.02401 | false | 3000 |
| 14 | 0.1130 | 1602.5 | -0.02401 | false | 3000 |
| 15 | 0.1130 | 1715.5 | -0.02401 | false | 3000 |
| 16 | 0.1130 | 1828.6 | -0.02401 | false | 3000 |
| 17 | 0.1130 | 1941.6 | -0.02401 | false | 3000 |
| 18 | 0.1130 | 2054.6 | -0.02401 | false | 3000 |
| 19 | 0.1130 | 2167.6 | -0.02401 | false | 3000 |
| 20 | 0.1130 | 2280.7 | -0.02402 | false | 3000 |

Peak 0.398 m/s (the roll-back, before P).

## Control: settle-then-P (`pawl`), 20 s

`moved` 0.4 mm from t = 1 s to 20 s (0.1 mm along, 0.2 mm across at the end of the 60 s run);
every wheel `omega` 0.00000, `_spin_held` true, `f_long` 780 N on `w0`, peak 0.005 m/s.

## Verdict

Creeps. A body already rolling at 0.31 m/s when P goes in settles at 0.113 m/s down the slope
(0.113 m of travel per second, 2.28 m in 20 s, no sign of stopping). All four wheels sit at
-0.024 rad/s (the older patch's figure was -0.034), above `WheelDrive.LOCK_STUCK_SPIN` (0.01), and
`_spin_held` never turns true: the `lock_holds` check at the end of `_couple_differentials`
returns at the first wheel over the tolerance, every tick. The control holds (0.4 mm).

Not explained by this gather: the body moves 0.113 m/s while the wheels turn only 0.024 rad/s
(a wheel of an assumed ~0.35 m radius at that speed would turn ~0.32 rad/s), so the pawl's lock holds the
driveline nearly still while the body slides over the tyres; where that slip lives (tyre contact
under a held wheel) is for the diagnose.
