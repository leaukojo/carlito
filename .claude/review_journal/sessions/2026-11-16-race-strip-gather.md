# 2026-11-16: gather for A9, `race` / `race-future` leaving the strip

Item A8 (Sonnet). Figures only, no cause guessed, no tune. The probe in `_tick_accel` was
uncommitted and is reverted (`git status` clean).

## Reproduction

`node tools/godot_run.mjs -- --headless --path . [--fixed-fps 60] res://tools/measure_vehicles.tscn -- race,race-future 60`

Both leave, with and without `--fixed-fps 60`, and the printed figures are identical in the two:

| body | top (lost) | lateral peak | distance used |
|---|---|---|---|
| `race` | 283.2 km/h | 54.1 m (edge 20 m) | 2940 m |
| `race-future` | 294.5 km/h | 58.2 m | 2886 m |

## Once (probe, first tick at 240 km/h)

| | `race` | `race-future` |
|---|---|---|
| mass | 900 kg | 850 kg |
| `inverse_inertia` (body frame x, y, z) | 0.00158, 0.001372, 0.004759 | 0.001392, 0.001349, 0.003793 |
| yaw inertia (1 / y) | 729 kg m^2 | 741 kg m^2 |
| `center_of_mass` | (0, 0.3, 0.290) | (0, 0.3, 0.350) |
| `aero_centre` | (0, 0.5, -0.31) | (0, 0.62, -0.25) |
| `downforce_front` / `downforce_area` | 0.400 / 2.240 | 0.400 / 2.240 |
| `side_area` / `drag_area` | 2.290 / 0.630 | 2.380 / 0.630 |
| `rear_lat_grip` | 1.150 | 1.150 |
| wheelbase | 1.824 m | 1.824 m |

Wheel contact points in body space (both): front x = ±0.63, z = 0.3485 (y 0.0656); rear x = ±0.63,
z = 2.1725 (y 0.0895); forward is -z.

## The run: `race`, probe ticks at 60 Hz, 240 km/h (66.7 m/s) until 24 m off centre

`vx` = the body's velocity across the strip (world x), `yawr` = angular velocity y, `hdg` = heading
(pi = straight down the strip), `lat` = each wheel's `force_lat` (FL FR RL RR, N), `slip` = side
slip angle at each contact point from the body's velocity there (rad), `susp` = `suspension_force`.

| t (s) | v m/s | hdg | yawr | vx | x | lat N | slip rad | susp N | aero side N | downforce N |
|---|---|---|---|---|---|---|---|---|---|---|
| 21.18 (start) | 66.68 | -3.14159 | 0 | 0 | 0 | 0 | 0 | 2830 2830 4641 4641 | 0 | 6104 |
| 29.50 | 72.90 | 3.14159 | 0 | 0.00002 | 0 | 0 | 0 | 3062 3062 5008 5008 | 0 | 7296 |
| 34.50 | 75.44 | 3.14159 | 0 | 0.00024 | 0 | 0 | 0 | 3163 3163 5167 5167 | 0 | 7812 |
| 36.50 (vx first > 1 mm/s) | 76.26 | 3.14158 | -0.00001 | 0.00101 | 0.002 | 0 | 0 | 3197 3196 5220 5220 | 0.0 | 7982 |
| 37.83 | 76.76 | 3.14154 | -0.00005 | 0.0031 | 0.004 | 0 0 1 1 | 0 | 3217 3217 5252 5252 | 0.1 | 8086 |
| 39.50 | 77.32 | 3.14134 | -0.00025 | 0.0137 | 0.016 | 2 2 3 3 | 0 | 3241 3239 5290 5288 | 0.6 | 8206 |
| 41.17 | 77.83 | 3.14012 | -0.00161 | 0.0783 | 0.078 | 14 14 21 21 | -0.000 -0.000 -0.001 -0.001 | 3267 3256 5328 5316 | 4.0 | 8314 |
| 42.83 | 78.29 | 3.13193 | -0.01108 | 0.507 | 0.463 | 99 98 141 141 | -0.003 -0.003 -0.004 -0.004 | 3316 3245 5395 5310 | 27.6 | 8412 |
| 44.50 | 78.65 | 3.07281 | -0.08149 | 3.573 | 3.113 | 745 691 1031 1027 | -0.024 -0.024 -0.026 -0.026 | 3555 3038 5690 5067 | 204 | 8494 |
| 46.08 | 77.05 | 2.72544 | -0.38952 | 21.64 | 19.69 | 4728 2610 5810 5251 | -0.137 -0.138 -0.146 -0.147 | 4622 1821 6996 3625 | 1135 | 8282 |
| 46.27 (end) | 76.27 | 2.67287 | -0.33256 | 22.70 | 23.80 | 0 0 0 0 | -0.209 -0.224 -0.206 -0.221 | 0 0 0 0 | 1395 | 8197 |

The speed across grows from about 1e-5 m/s (t 27.8) through 1e-3 (t 36.5) to 0.08 (t 41.2) to 3.6
(t 44.5): a smooth, steady growth, with no step. From t 36.5 each 100 ticks (1.67 s) multiplies it
by about 4; the heading drifts the same way. On the first tick over 1 mm/s nothing else has moved: `lat` reads
0, the aero side force 0.0 N, `yawr` -1e-5 rad/s, `susp` equal left to right to within 1 N. The left
`susp` falls under the right's as it grows (the body rolls). The wheels leave the ground
at t 46.1 (x about 20 m: the strip's edge), after the divergence is already at 3.6 m/s.

## `race-future`, same probe

Same shape; `vx` > 1 mm/s at t 34.27 (v 79.7 m/s), 0.0086 at t 36.4, 0.136 at t 38.9, 2.66 at
t 41.4 (hdg 3.09084, yawr -0.062, `lat` 534 515 731 733 N, `slip` about -0.02, aero side 179 N),
23.6 m/s across at t 43.3 as the wheels leave the ground. Start: `susp` 2669 2669 4561 4561 N,
downforce 6106 N at 66.7 m/s; at 80 m/s 8707 N. The sign of `vx`, `yawr` and the side force match
`race`'s in both runs (all positive across, negative yaw rate).

## Not answered here (A9's)

- Where the first 1e-5 m/s of `vx` comes from: the probe starts at 240 km/h, so the ticks before it
  are not logged, and `vx` already reads 0.00000 to five digits there.
- The probe's `hdg` is the body's forward axis in the world x-z plane, so it includes the roll's
  contribution only through the basis; no separate roll angle was logged.
- The spec's `center_of_mass` z (0.290 / 0.350) sits at the front axle's z (0.3485) in the numbers
  above, while the measured `susp` split at the start (front 5660 N of 14942 N, 38 %) puts the
  centre of mass about 1.48 m from the origin, 0.62 of the wheelbase behind the front axle. Which
  frame each is in was not traced: A9 reads `center_of_mass` and the wheel stations from the code
  before deriving an axle split from either.
