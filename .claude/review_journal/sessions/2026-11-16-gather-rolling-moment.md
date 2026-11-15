# 2026-11-16: gather for the rolling moment (per-tick figures, HEAD vs patch)

Gather only: no cause, no fix. HEAD = c903d45; patch = HEAD + `2026-11-15-rolling-moment.patch`.
Two detached worktrees outside the repo (`.godot/` copied), removed after. Logs (one per run and
tree, `PROBE_B` body lines and `PROBE_W` wheel lines) and the probe diff stay in
`C:/Users/Ccamy/AppData/Local/Temp/claude/rm-logs/` (`<run>_head.log`, `<run>_patch.log`, `probe.diff`).

Reading the tables: the probe runs at the top of the tool's `_physics_process`, so each tick's line
is the state the previous physics tick left. Tick = the tool's `_ticks` in (i), `round(t * 60)`
after the release / settle elsewhere. `alt` = mean |second difference| / 4 (a pure ±a alternation
reads a); `flip` = share of ticks whose tick-to-tick difference changes sign. RL/FL = rear/front
left; `(d)` = driven. Left and right agree to the shown digits unless both are listed. On the patch
`force_roll` is a readout already inside `force_long`; at HEAD it is a second force beside it.
`taken` (HEAD only) is recomputed from the wheel's fields exactly as `apply_patch` forms it.
Drive torque = the wheel's `coupled_torque` (the tick's drive arrives through the coupling: per
wheel times two equals the shaft torque in every run). The TC hold's fields are `tcs_spin` (the
drive's share it may take back) and `tcs_ceiling` (the spin it holds at); `tcs_active` is the latch.

## Run lines (cwd = each worktree)

```
timeout 600 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_semi_launch.tscn -- semi steady strict trailer=bobtail
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan creep creep_hold=3.984375 verbose
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan creep creep_hold=3.28125 verbose
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=park park_cell=semi:hand:reg
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=park park_cell=semi:cross:5.7
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- semi rollback grade=25 nohold verbose
```

`creep_hold=` (probe arg) skips the flat run and the bisection: one trial at that angle. 3.984375 deg
(7.0 %) and 3.28125 deg (5.7 %) are the bisection's own grid angles that print as HEAD's and the
patch's held grade. `park_cell=` (probe arg) keeps the one `doc=park` job (same dict, same angle
`atan(0.18)` = 10.2039737 deg, laden with the box) and writes no doc.

## The probe

Uncommitted, read-only. `tools/probe_rm.gd` (new) prints per tick, for the unit and a coupled
trailer, the body speeds (forward, along and across the slope), yaw and pitch rate and position;
the unit's rpm, throttle, gear, coupling state, `coupling_torque`, `crank_torque`,
`drive._drive_torque` and ratio; per wheel `omega`, `_spin_held`, `_patch_held`, `brake_spin`,
`roll_share` (NA at HEAD), `long_slip`, `force_long`, `force_roll`, `force_lat`,
`suspension_force`, `coupled_torque`, `tcs_spin`, `tcs_ceiling`, `tcs_active`, `taken` (HEAD).
Hooks: `measure_semi_launch` (rest window), `measure_grade` (creep, park and roll-back windows, the
two pin arguments). The whole diff is the appendix; it `git apply`s at HEAD and on top of the patch.

## (i) `semi steady strict trailer=bobtail`: the rest window, ticks 433-612

Verdict lines:
- HEAD: `rest reading: speed sign changes 0.7 /s against 20, axle-load step 0.11 kg a tick against 2, over 180 ticks: PASS`
- patch: `rest reading: speed sign changes 0.7 /s against 20, axle-load step 0.34 kg a tick against 2, over 180 ticks: PASS`

Bobtail: four wheels, rear axle driven; no brake applied (HEAD `brake_spin` 0), gear byte 6.

| column | HEAD min / max / mean / alt (flip) | patch min / max / mean / alt (flip) |
|---|---|---|
| RL(d) omega | -2.22e-05 / 2.95e-05 / -5.62e-07 / 2.41e-06 (0.32) | 0 / 0 / 0 / 0 (0.00) |
| RL _spin_held | 0 throughout | 1 throughout (`_patch_held` 0 in both) |
| RL brake_spin | 0 throughout | 4.71e-03 / 4.71e-03 / 4.71e-03 / 5.43e-08 (0.63); roll_share 1.000 |
| RL long_slip | -1.27e-07 / 1.01e-07 / -3.43e-10 / 1.89e-08 (0.43) | -1.47e-05 / 1.64e-05 / -2.75e-07 / 1.54e-06 (0.46) |
| RL force_long | -0.016 / 0.013 / -4.19e-05 / 2.37e-03 (0.48) | -1.842 / 2.067 / -0.035 / 0.194 (0.48) |
| RL force_roll | -0.872 / 0.656 / 0.017 / 0.071 (0.32) | = force_long (readout) |
| RL taken | 0 / 0.016 / 2.27e-03 / 8.63e-04 (0.26) | NA |
| RL suspension_force | 18762.1 / 18768.1 / 18765.5 / 0.103 (0.08) | 18758.0 / 18770.8 / 18765.1 / 1.057 (0.34) |
| FL omega / held | ±3e-05, `_spin_held` 0 | 0, `_spin_held` 1, brake_spin 4.77e-03 |
| FL force_long | -0.016 / 0.013 / -4.19e-05 / 2.36e-03 (0.49) | -1.995 / 2.233 / -0.037 / 0.210 (0.48) |
| rear axle kg (tool) | 3829.1 / 3829.9 / 3829.7 / 0.055 (0.16) | 3828.6 / 3830.7 / 3829.6 / 0.162 (0.34) |
| body fwd speed | -5.40e-05 / 4.54e-05 / -6.83e-06 / 3.31e-07 (0.21) | -6.54e-05 / 6.40e-05 / 9.87e-06 / 8.77e-07 (0.35) |
| body pitch rate | -4.22e-05 / 5.17e-05 / 6.12e-06 / 5.62e-07 (0.24) | -6.01e-05 / 6.51e-05 / -8.66e-06 / 1.56e-06 (0.43) |

First 12 ticks of the window (they hold the patch's first change):

| tick | H RL susp | H RL F_long | H RL slip | H RL omega | H axle kg | P RL susp | P RL F_long | P RL slip | P axle kg | P pitch rate |
|---|---|---|---|---|---|---|---|---|---|---|
| 433 | 18764.1 | -4.87e-03 | -3.88e-08 | 2.78e-06 | 3829.6 | 18765.6 | 0.070 | 5.59e-07 | 3829.7 | -5.55e-05 |
| 434 | 18764.1 | -2.64e-04 | -2.10e-09 | 3.30e-06 | 3829.2 | 18765.6 | 0.070 | 5.60e-07 | 3829.7 | -5.61e-05 |
| 435 | 18765.0 | -7.28e-03 | -5.79e-08 | 1.79e-05 | 3829.9 | 18765.6 | 0.070 | 5.59e-07 | 3829.7 | -5.67e-05 |
| 436 | 18764.1 | 0.012 | 9.87e-08 | -6.97e-06 | 3829.6 | 18765.6 | 0.070 | 5.59e-07 | 3829.7 | -5.72e-05 |
| 437 | 18764.1 | -4.87e-03 | -3.88e-08 | 2.77e-06 | 3829.6 | 18765.6 | 0.070 | 5.59e-07 | 3829.7 | -5.78e-05 |
| 438 | 18764.1 | -2.65e-04 | -2.10e-09 | 3.30e-06 | 3829.2 | 18765.6 | 0.070 | 5.59e-07 | 3829.7 | -5.83e-05 |
| 439 | 18765.0 | -7.28e-03 | -5.79e-08 | 1.79e-05 | 3829.9 | 18762.0 | 0.070 | 5.60e-07 | 3828.9 | -4.89e-05 |
| 440 | 18764.1 | 0.012 | 9.87e-08 | -6.97e-06 | 3829.6 | 18768.3 | -0.759 | -6.03e-06 | 3830.2 | -5.93e-05 |
| 441 | 18764.1 | -4.87e-03 | -3.88e-08 | 2.78e-06 | 3829.6 | 18761.5 | 0.599 | 4.77e-06 | 3828.9 | -3.82e-05 |
| 442 | 18764.1 | -2.64e-04 | -2.10e-09 | 3.30e-06 | 3829.2 | 18764.8 | -1.548 | -1.23e-05 | 3829.6 | -4.00e-05 |
| 443 | 18765.0 | -7.28e-03 | -5.79e-08 | 1.79e-05 | 3829.9 | 18764.8 | -0.385 | -3.06e-06 | 3829.6 | -3.81e-05 |
| 444 | 18764.1 | 0.012 | 9.87e-08 | -6.97e-06 | 3829.6 | 18764.8 | -0.300 | -2.39e-06 | 3829.6 | -3.58e-05 |

Last 6 ticks (607-612): HEAD RL susp 18765.0 flat, F_long 0.012 / 4.6e-4 / 2.0e-4 / -3.8e-3 /
-6.8e-4 / 2.8e-3, omega 5e-6 to 1.4e-5; patch RL susp 18766.0 flat, F_long -0.028 to -0.021 smooth,
omega 0.

Observed: at HEAD every wheel turns free (`_spin_held` 0, omega within ±3e-5 rad/s, repeating a
4-tick pattern) and `force_long` flips sign tick to tick at ±0.002 N throughout; on the patch every
wheel stands held by the rolling moment (omega 0, `_spin_held` 1, `roll_share` 1), and the FIRST
column that alternates on the patch and not at HEAD is the driven rear-left `suspension_force` at
tick 439 (18765.6 -> 18762.0 -> 18768.3 -> 18761.5 N; at HEAD it moves 1 N on that 4-tick pattern),
with `rear_axle_kg` and the body pitch rate stepping the same tick and RL/FL `force_long` and
`long_slip` flipping sign from tick 440 at ±0.2 N (about 90 times HEAD's). Rear-left
`suspension_force` steps more than 2 N on 75 of the window's 180 ticks on the patch (HEAD: 3), in
bursts of 4-8 ticks.

## (ii) `sedan creep`, pinned: 7.0 % and 5.7 %, 3 s from the release

Verdict lines (`verbose` trial line, then the row; kmh/rpm/load are `nan` because the flat run is
skipped):
- 7.0 %: HEAD `3.98 deg  holds  -0.19 m` / `holds  7.0 % (4.0 deg)`; patch `3.98 deg  rolls  -0.25 m` / `holds  0.0 % (0.0 deg)`
- 5.7 %: HEAD `3.28 deg  holds  +0.01 m` / `holds  5.7 % (3.3 deg)`; patch `3.28 deg  holds  -0.03 m` / `holds  5.7 % (3.3 deg)`

Front-wheel drive, converter in D1 (`conv` 1), rpm 893.9 in both. Engine torque = coupling
(impeller) torque 7.70 N·m (HEAD) / 7.71 (patch); turbine torque = shaft / (ratio 17.55 x eff
0.9): 15.36 / 15.43 N·m at tick 180.

7.0 %, ticks 1-180:

| column | HEAD min / max / mean / alt (flip) | patch min / max / mean / alt (flip) |
|---|---|---|
| FL(d) omega | 0 / 0.075 / 0.029 / 2.24e-04 (0.35) | 0 / 0.066 / 2.29e-03 / 2.09e-04 (0.01) |
| FL _spin_held | 1 on ticks 1-2, then 0 | 1 on 1-2, 0 on 3-15, 1 from 16 (`_patch_held` 1 on ticks 1-2 only, both) |
| FL brake_spin | 0 after tick 2 | 4.99e-03 / 8.76e-03 / 8.64e-03 / 8.06e-06 (0.34); roll_share 0.989 mean |
| FL long_slip | -1.73e-05 / 0.012 / 0.012 / 3.28e-05 (0.49) | -2.70e-05 / 0.013 / 0.013 / 3.06e-05 (0.23) |
| FL force_long | 222.9 / 337.1 / 335.5 / 0.280 (0.53) | 222.3 / 368.3 / 355.7 / 0.228 (0.30) |
| FL force_roll | -0.503 / 28.4 / 22.4 / 0.027 (0.29) | -39.4 / 29.9 / 18.7 / 0.161 (0.30) |
| FL taken | 0 / 201.5 / 197.9 / 0.562 (0.52) | NA |
| FL drive torque | 120.3 / 121.8 / 121.2 / 2.78e-03 (0.26) | 120.5 / 121.8 / 121.8 / 2.59e-03 (0.01) |
| FL suspension_force | 3233.2 / 3274.3 / 3252.8 / 0.103 (0.52) | 3238.9 / 3284.2 / 3253.5 / 0.085 (0.37) |
| RL omega | -0.053 / 1.10e-04 / -0.049 / 2.09e-05 (0.28) | -0.077 / 0 / -0.071 / 1.72e-05 (0.22) |
| RL brake_spin | 0 after tick 2 | 9.73e-04 / 8.23e-03 / 8.10e-03 / 1.99e-05 (0.44) |
| RL force_long | -0.022 / 170.3 / 1.950 / 0.485 (0.54) | -0.597 / 169.9 / 29.9 / 0.561 (0.39) |
| RL force_roll | -0.482 / 28.5 / 27.9 / 0.079 (0.54) | -0.597 / 28.5 / 28.0 / 0.095 (0.34) |
| RL suspension_force | 2336.4 / 2372.2 / 2368.3 / 0.127 (0.55) | 2335.2 / 2376.6 / 2367.6 / 0.137 (0.34) |
| body speed along slope (m/s) | -0.020 / 5.09e-04 / -0.018 / 6.13e-06 (0.10) | -0.033 / 5.48e-04 / -0.029 / 9.44e-06 (0.06) |
| shaft torque (N·m) | 240.6 / 243.7 / 242.5 / 5.56e-03 (0.26) | 241.1 / 243.7 / 243.6 / 5.18e-03 (0.01) |
| position along slope from release (m) | -0.053 at 3 s | -0.087 at 3 s |

First ticks and the patch's change at tick 16:

| tick | H FL omega | H FL held | H FL F_long | H FL F_roll | H RL omega | H v along | P FL omega | P FL held | P FL F_long | P FL F_roll | P RL omega | P RL F_long | P v along |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 223.0 | -0.401 | 0 | 4.93e-04 | 0 | 1 | 222.5 | -0.637 | 0 | 169.9 | 5.34e-04 |
| 2 | 0 | 1 | 222.9 | -0.482 | 0 | 5.09e-04 | 0 | 1 | 222.3 | -0.639 | 0 | 169.7 | 5.48e-04 |
| 3 | 0.075 | 0 | 321.8 | -0.503 | 1.10e-04 | -1.53e-03 | 0.066 | 0 | 284.8 | -38.9 | 0 | -0.597 | -2.56e-03 |
| 4 | 0.071 | 0 | 335.0 | 0 | -6.73e-03 | -2.32e-03 | 0.058 | 0 | 297.5 | -38.9 | -2.11e-03 | 28.4 | -4.47e-03 |
| 13 | 0.053 | 0 | 335.7 | 0 | -0.025 | -9.54e-03 | 0.011 | 0 | 299.3 | -39.3 | -0.050 | 29.2 | -0.021 |
| 14 | 0.051 | 0 | 335.8 | 0 | -0.027 | -0.010 | 5.94e-03 | 0 | 299.5 | -39.4 | -0.055 | 29.2 | -0.023 |
| 15 | 0.049 | 0 | 335.9 | 0 | -0.029 | -0.011 | 1.23e-03 | 0 | 299.8 | -39.4 | -0.059 | 29.2 | -0.025 |
| 16 | 0.048 | 0 | 336.0 | 0 | -0.031 | -0.012 | 0 | 1 | 314.7 | -24.0 | -0.064 | 29.1 | -0.026 |
| 17 | 0.046 | 0 | 336.1 | 0 | -0.032 | -0.013 | 0 | 1 | 328.1 | -10.4 | -0.067 | 28.9 | -0.027 |
| 18 | 0.044 | 0 | 336.2 | 0 | -0.034 | -0.013 | 0 | 1 | 336.0 | -2.456 | -0.069 | 28.6 | -0.028 |
| 19 | 0.042 | 0 | 336.4 | 0 | -0.036 | -0.014 | 0 | 1 | 340.8 | 2.369 | -0.070 | 28.5 | -0.029 |
| 20 | 0.040 | 0 | 336.5 | 0 | -0.038 | -0.015 | 0 | 1 | 344.0 | 5.554 | -0.071 | 28.4 | -0.029 |

Ticks 5-12 run smoothly between the rows shown. HEAD FL `force_roll` stays 0 to tick 24, then
rises (7.7 at 25) to 26.1. Steady, ticks 175-180 (each column constant to the digits shown): HEAD
FL omega 0.025, held 0, F_long 337.0, F_roll 26.1, RL omega -0.053, RL F_long ±1e-3, v along -0.019;
patch FL omega 0, held 1, F_long 363.1, F_roll 24.7, RL omega -0.076, RL F_long 28.4, v along -0.030.

5.7 %, ticks 1-180 (mean, alt):

| column | HEAD | patch |
|---|---|---|
| FL(d) omega | 0.079 (2.1e-04) | 0.060 (1.9e-04) |
| FL _spin_held | 0 after tick 2 | 0 after tick 2 |
| FL brake_spin / roll_share | 0 | 8.70e-03 / 0.989 |
| FL force_long / force_roll | 332.1 / -11.0 | 294.3 / -38.9 |
| FL drive torque | 120.2 | 120.6 |
| RL omega / _spin_held | +2.55e-03 / 0 after tick 2 | 0 / 1 on every tick but 35-36 |
| RL force_long / force_roll | 1.54 / -0.003 | 27.5 / 26.0 |
| body speed along slope | +8.96e-04 m/s (forward) | -2.93e-03 m/s |
| position along slope at 3 s | +2.76 mm | -8.69 mm |

Observed: on 7.0 % the driven fronts spin forward on both trees from tick 3, but on the patch they
carry `force_roll` -38.9 N (HEAD 0) and slow to a stop at tick 16, after which they stand held
(`_spin_held` 1, omega 0) while the body keeps rolling back at 0.030 m/s against HEAD's fronts
turning at 0.025 rad/s and the body's 0.019 m/s; the drive torque per front wheel is within 0.6 N·m
(121.2 vs 121.8) and the converter's figures match to 0.2 %. On 5.7 % the fronts turn on both
trees (patch `force_roll` -38.9 N, HEAD -11.0), the undriven rears stand held on the patch (all
but ticks 35-36) and turn forward at HEAD, and the body creeps up at HEAD and back on the patch.

## (iii) `doc=park` `semi` cells, pinned (laden: box trailer, six trailer wheels)

Printed cell lines:
- 18 % hand: HEAD `semi 18.0 % hand  along +0.5 mm  across -0.4 mm  peak 0.016 m/s`; patch `along +0.5 mm  across -0.1 mm  peak 0.016 m/s`
- 10 % cross: HEAD `semi 10.0 % cross along +3.0 mm  across -0.7 mm  peak 0.045 m/s`; patch the same line

The pinned cell does NOT reproduce the journal's figures (HEAD across -0.0, patch -1.7 mm; 10 %
cross -0.5 / -1.5 mm), which came from the full `doc=park` sweep, where earlier jobs ran first in
the same process. `semi park=10.2039737 hand` (the per-body run line) prints the same as the pinned
cell in both trees.

18 % hand, 3600 ticks of hold; per wheel: held share / max |omega| / f_lat mean (alt) / f_long mean
(alt) / f_roll mean (alt) / suspension alt (left and right agree):

| wheels | HEAD | patch |
|---|---|---|
| unit front | 0.00 / 5.6e-03 / -1.3e-03 (0.025) / 4e-04 (6e-04) / 0.30 (0.012) / 0.08 | 1.00 / 0 / 0.103 (0.011) / -0.34 (7e-03) / -0.34 (7e-03) / 0.06 |
| unit rear (d) | 1.00 / 0 / -0.013 (0.021) / 7878.3 (0.026) / -0.91 (0.013) / 0.34 | 1.00 / 0 / 0.466 (0.011) / 7881.8 (0.018) / 69.1 (2e-04) / 0.10 |
| trailer axle 1 | 1.00 / 0 / 7.2e-03 (2.2e-03) / 6565.2 (0.044) / -0.37 (0.024) / 0.04 | 1.00 / 0 / -0.645 (5.1e-03) / 6563 (0.021) / 155.1 (8e-04) / 0.06 |
| trailer axle 2 | 1.00 / 0 / 8e-04 (2.0e-03) / 6633.2 (0.043) / -0.37 (0.024) / 0.03 | 1.00 / 0 / -0.186 (5.1e-03) / 6631 (0.021) / 158.5 (8e-04) / 0.07 |
| trailer axle 3 | 1.00 / 0 / -5.5e-03 (1.9e-03) / 6701.1 (0.045) / -0.37 (0.024) / 0.05 | 1.00 / 0 / 0.264 (5.1e-03) / 6698 (0.021) / 161.9 (8e-04) / 0.07 |

Bodies (min / max / alt (flip)): unit across speed HEAD ±3.6e-05 m/s, alt 1.2e-07 (0.27); patch
±6.5e-05, 6.4e-08 (0.14). Trailer across HEAD ±5.0e-05, 9.4e-09 (0.11); patch ±1.0e-04, 1.2e-08
(0.04). Yaw rate unit ±1.4e-06 / ±2.9e-06 rad/s, trailer ±2.7e-06 / ±5.7e-06. Across position of
the unit from the hold's first tick (mm) at ticks 300 / 600 / 1200 / 1800 / 2400 / 3600: HEAD
-0.02 / -0.12 / -0.46 / -0.43 / -0.10 / -0.36; patch -0.15 / -0.45 / -0.46 / +0.16 / +0.15 / -0.14
(trailer within 0.01 of the unit in both).

10 % cross, every wheel held in both trees (omega 0); unit wheels (f_lat mean (alt) / f_long mean
(alt) / f_roll mean / suspension alt):

| wheel | HEAD | patch |
|---|---|---|
| unit FL | 2465.2 (0.61) / -2579.8 (0.42) / 6.9 / 2.0 | 2467.3 (6.09) / -2600.5 (1.67) / -13.2 / 55.2 |
| unit FR | 2465.2 (0.60) / -1401.3 (0.27) / 5.6 / 1.6 | 2467.3 (6.09) / -1412.9 (2.54) / -4.7 / 19.1 |
| unit RL (d) | 3563.1 (0.74) / -2615.7 (0.61) / 6.5 / 1.9 | 3567.3 (5.56) / -2634.7 (5.88) / -20.7 / 4.2 |
| unit RR (d) | 3562.7 (0.74) / -2127.2 (0.50) / 5.3 / 3.0 | 3566.8 (5.57) / -2145.7 (6.04) / -13.4 / 4.0 |
| trailer, 6 wheels | f_lat alt 1.2-1.7, f_roll -13.8 (left, ~38.5 kN each) / -1.4 to -3.5 (right, ~19 kN) | f_lat alt 1.4-1.9, f_roll +21.7 / +0.1 to +0.5 |

Bodies, alt (flip): unit across speed HEAD 3.4e-06 (0.32), patch 1.2e-05 (0.70); along 6.7e-06
(0.08) / 3.2e-05 (0.65); yaw rate 3.4e-06 (0.29) / 1.5e-05 (0.69); trailer across 2.5e-06 (0.20)
/ 4.5e-06 (0.67), yaw 1.4e-06 (0.10) / 2.6e-06 (0.61). FL suspension alt per 60-tick window: both
trees 4-18 N to tick 780; from tick 781 HEAD 0.2-0.6 N, patch 32-70 N (flip 0.52-0.86) to the end.

| tick | H FL susp | H FL F_lat | H v across | H yaw rate | P FL susp | P FL F_lat | P FL F_long | P v across | P yaw rate |
|---|---|---|---|---|---|---|---|---|---|
| 768 | 31253.0 | 2454.1 | -1.85e-05 | -7.75e-05 | 31246.2 | 2444.8 | -2594.3 | -1.02e-04 | -1.60e-04 |
| 769 | 31258.0 | 2454.6 | -1.62e-05 | -7.75e-05 | 31256.1 | 2444.6 | -2601.3 | -4.65e-05 | -1.27e-04 |
| 770 | 31262.6 | 2455.5 | -1.36e-05 | -7.86e-05 | 31264.9 | 2448.1 | -2600.3 | -2.42e-05 | -1.09e-04 |
| 771 | 31266.7 | 2456.3 | -1.11e-05 | -7.86e-05 | 31380.5 | 2451.6 | -2607.8 | -2.62e-05 | -8.34e-05 |
| 772 | 31271.1 | 2457.5 | -7.29e-06 | -7.89e-05 | 31348.3 | 2467.2 | -2613.8 | -5.20e-08 | -9.61e-05 |
| 773 | 31276.6 | 2458.5 | -4.01e-06 | -7.81e-05 | 31213.0 | 2473.2 | -2605.6 | 3.57e-05 | -1.36e-04 |
| 774 | 31279.6 | 2459.6 | -8.91e-07 | -7.85e-05 | 31393.9 | 2458.1 | -2610.4 | 1.24e-05 | -1.01e-04 |
| 3597 | 31281.1 | 2461.6 | 1.28e-06 | -7.14e-07 | 31219.5 | 2471.3 | -2596.9 | 1.45e-05 | -1.51e-05 |
| 3598 | 31281.1 | 2461.7 | 1.24e-06 | -8.70e-07 | 31391.8 | 2455.0 | -2597.8 | -1.73e-05 | 1.94e-05 |
| 3599 | 31281.1 | 2461.6 | 1.28e-06 | -5.95e-07 | 31355.8 | 2471.0 | -2606.6 | -2.91e-06 | 8.00e-06 |
| 3600 | 31281.1 | 2461.7 | 1.23e-06 | -7.44e-07 | 31213.1 | 2473.4 | -2598.0 | 2.56e-05 | -2.80e-05 |

Observed: in the 18 % hand cell the tractor's undriven fronts turn free at HEAD (`_spin_held` 0,
omega up to 5.6e-3 rad/s) and stand held on the patch (omega 0, `_spin_held` 1), every trailer
wheel reads `force_roll` -0.37 N at HEAD and +155 to +162 N (readout) on the patch, and the unit's
across position wanders within ±0.5 mm in both trees with no tick-to-tick alternation in the body
speeds; in the 10 % cross cell, from tick 771 of the hold, the patch's front-left
`suspension_force` alternates tick to tick between about 31213 and 31394 N (`alt` 64-73 N per
60-tick window; HEAD 0.2-0.6 N) and the unit's across speed,
along speed and yaw rate alternate sign on about 70 % of ticks to the end of the hold, while both
cells' printed movement differs between the trees by 0.3 mm (18 %) and 0.0 mm (10 %).

## (iv) `semi rollback grade=25 nohold verbose` (laden), t = 2.0-3.5 s (ticks 120-210)

Verdict lines: HEAD `semi 25.0 %  rolled back 887.2 mm  forward never  held 0.00 s  (+24000 kg
towed)`; patch `rolled back 1577.6 mm  forward never  held 0.00 s  (+24000 kg towed)`. Steady
lines at t 3.0: HEAD `t 3.00 -0.644 m -0.64 km/h rpm 900 c 1 Fx front -3 rear 76748 N roll 154 N
slip -0.00 / +0.12 | trailer Fx -9 N roll 1215 N brake 0.00 drawbar 57370 N (grade 57044)`; patch
`t 3.00 -0.738 m -0.89 km/h rpm 900 c 1 Fx front 154 rear 75861 N roll -604 N slip +0.00 / +0.12 |
trailer Fx 1210 N roll 1215 N brake 0.00 drawbar 56710 N (grade 57044)`.

Driven wheels = the tractor's rear pair (left and right agree); D1, clutch slipping (`cstate` 1,
`conv` 0), throttle 1.

| column | HEAD min / max / mean / alt (flip) | patch min / max / mean / alt (flip) |
|---|---|---|
| RL(d) omega | 0.627 / 0.895 / 0.763 / 2.25e-05 (0.00) | 0.491 / 0.646 / 0.570 / 2.64e-05 (0.00) |
| RL tcs_ceiling | equal to omega every tick | 0.504 / 0.659 / 0.583; ceiling - omega = 0.0126-0.0127 every tick |
| RL tcs_spin / tcs_active | 1.650 / 1 every tick | 1.650 / 1 every tick |
| RL brake_spin / roll_share | 0 / NA | 0.0126-0.0127 (= ceiling - omega) / 1.000 |
| RL _spin_held | 0 | 0 |
| RL long_slip | 0.120 constant | 0.119 constant |
| RL force_long | 38250.7 / 38423.4 / 38369.7 / 1.002 (0.54) | 37811.5 / 37981.5 / 37929.0 / 0.952 (0.42) |
| RL force_roll | 0 (taken 35121 mean) | -380.4 / -378.4 / -379.8 / 0.011 (0.42) |
| RL drive torque | 17833.2 constant | 17833.2 constant |
| RL suspension_force | 54168.9 / 54450.4 / 54362.9 / 1.633 (0.54) | 54059.8 / 54339.8 / 54253.2 / 1.569 (0.42) |
| FL (undriven) force_long / force_roll | -1.47 / 76.8 | 76.9 / 77.8 |
| trailer w0 force_long / force_roll | -1.48 / 208.0 | 207.0 / 207.9 |
| body speed along slope (m/s) | -0.240 / -0.145 / -0.192 | -0.284 / -0.229 / -0.257 |
| engine rpm / crank torque / shaft torque | 900 / 2084.4 / 35666.4 constant | the same |

| tick | H RL omega | H RL ceiling | H RL F_long | H v along | P RL omega | P RL ceiling | P RL brake_spin | P RL F_long | P RL F_roll | P v along |
|---|---|---|---|---|---|---|---|---|---|---|
| 120 | 0.627 | 0.627 | 38250.7 | -0.240 | 0.491 | 0.504 | 0.013 | 37811.5 | -378.4 | -0.284 |
| 121 | 0.630 | 0.630 | 38259.0 | -0.239 | 0.494 | 0.506 | 0.013 | 37824.3 | -378.6 | -0.284 |
| 122 | 0.634 | 0.634 | 38275.2 | -0.238 | 0.496 | 0.509 | 0.013 | 37840.2 | -378.7 | -0.283 |
| 123 | 0.637 | 0.637 | 38284.9 | -0.237 | 0.498 | 0.511 | 0.013 | 37847.8 | -378.8 | -0.283 |
| 124 | 0.641 | 0.641 | 38298.3 | -0.236 | 0.500 | 0.513 | 0.013 | 37862.4 | -379.0 | -0.282 |
| 125 | 0.644 | 0.644 | 38311.7 | -0.235 | 0.503 | 0.515 | 0.013 | 37875.2 | -379.2 | -0.282 |
| 126 | 0.648 | 0.648 | 38327.2 | -0.234 | 0.505 | 0.517 | 0.013 | 37886.5 | -379.3 | -0.281 |
| 127 | 0.651 | 0.651 | 38339.4 | -0.233 | 0.507 | 0.520 | 0.013 | 37904.4 | -379.5 | -0.280 |
| 128 | 0.654 | 0.654 | 38350.0 | -0.232 | 0.509 | 0.521 | 0.013 | 37909.0 | -379.5 | -0.280 |
| 129 | 0.658 | 0.658 | 38365.0 | -0.231 | 0.511 | 0.524 | 0.013 | 37926.4 | -379.7 | -0.279 |
| 130 | 0.661 | 0.661 | 38372.7 | -0.230 | 0.513 | 0.525 | 0.013 | 37934.0 | -379.8 | -0.279 |
| 131 | 0.664 | 0.664 | 38385.1 | -0.229 | 0.515 | 0.527 | 0.013 | 37941.0 | -379.9 | -0.278 |
| 210 | 0.895 | 0.895 | 38374.2 | -0.145 | 0.646 | 0.659 | 0.013 | 37931.2 | -379.8 | -0.229 |

The window has no step: ticks 132-209 continue these trends.

Observed: with the same drive torque (17833.2 N·m per driven wheel), the same engine and shaft
torque and TC latched on both trees, HEAD's driven rears sit exactly on `tcs_ceiling` (slip 0.120,
`force_roll` 0), while the patch's sit 0.0126 rad/s below it every tick, equal to their
`brake_spin` (`roll_share` 1), at slip 0.119, with `force_long` 441 N lower per wheel (37929 vs
38370 mean) and a `force_roll` readout of -380 N; the body rolls back 0.065 m/s faster on average.

## Not gathered

- The journal's `doc=park` figures (18 % hand across -0.0 / -1.7 mm, 10 % cross -0.5 / -1.5 mm):
  the pinned cell prints -0.4 / -0.1 and -0.7 / -0.7 mm. They come from the full sweep, which the
  brief forbids running; the per-tick logs here are of the cell alone.
- `surface_drag_force` as a separate column at HEAD: it is `force_roll` itself (HEAD applies it as
  `force_roll`); `taken` is logged. On the patch neither exists (NA).
- The turbine torque is not a stored field: given above as shaft torque / (ratio x efficiency).
  Engine torque is `crank_torque(rpm, applied_throttle)`, equal to `coupling_torque` in every run.
- The drive torque argument `drive_t` (the rigid crank's `axle_torque` split) is not stored; in
  these runs every wheel's drive came through the coupling (twice `coupled_torque` equals the shaft
  torque), so `coupled_torque` is the whole of it.
- (i) laden and `measure_vehicles -- semi 20 rest`: not asked, not run.

## Appendix: the probe diff (at HEAD)

```diff
diff --git a/tools/measure_grade.gd b/tools/measure_grade.gd
--- a/tools/measure_grade.gd
+++ b/tools/measure_grade.gd
@@ -140,6 +140,7 @@ var _creep_sum := Vector3.ZERO        ## flat run's last CREEP_MEAN_S: speed m/s
 var _creep_n := 0
 var _creep_row := {}
 var _creep_rows: Array[Dictionary] = []
+var _creep_pin := NAN  ## PROBE: `creep_hold=<deg>`
 var _roll_queue: Array[Dictionary] = []  ## rollback mode: variant + grade jobs left
 var _roll_rows: Array[Dictionary] = []
 var _roll_grade := 0.0                ## the current rollback job's grade, %
@@ -285,6 +286,7 @@ func _ready() -> void:
 	_tipper = args.has("tipper")
 	if args.has("creep"):
 		_nohold = true  ## creep alone: a hill hold would shorten the roll-back window
+		_creep_pin = MeasureRig.float_flag(args, "creep_hold=", NAN)  ## PROBE: one trial at this angle
 		_start_creep(which)
 		return
 	if args.has("rollback"):
@@ -718,6 +720,16 @@ func _start_park(which: String, angle_deg: float, mode: String) -> void:
 					_park_queue.append({"variant": v, "angle": a, "mode": m})
 			_park_queue.append({"variant": v, "mode": "hand", "reg": true,
 					"angle": rad_to_deg(atan(BrakeSizing.regulation_grade(MeasureRig.rig_mass(v))))})
+		## PROBE: `park_cell=<variant>:<mode>:<reg|angle>` keeps that one doc cell, writes no doc.
+		var cell := MeasureRig.flag(OS.get_cmdline_user_args(), "park_cell=")
+		if cell != "":
+			var want := cell.split(":")
+			_park_doc = false
+			_park_queue.assign(_park_queue.filter(func(j: Dictionary) -> bool:
+				return j["variant"] == want[0] and j["mode"] == want[1] and (bool(j.get("reg", false))
+						if want[2] == "reg" else (not j.get("reg", false)
+						and is_equal_approx(float(j["angle"]), float(want[2]))))))
+			print("PROBE park_cell %s: %s" % [cell, _park_queue])
 	elif Catalog.VARIANTS.has(which):
 		_park_queue.append({"variant": which, "angle": angle_deg, "mode": mode})
 	else:
@@ -769,6 +781,8 @@ func _park_step() -> void:
 		return
 	_park_peak = maxf(_park_peak, _car.linear_velocity.length())
 	var moved := (_car.global_position - _start).length()
+	preload("res://tools/probe_rm.gd").dump("park", int(round(_t * 60.0)), _t, _car, _angle,
+			",moved_mm=%.4f" % (moved * 1000.0))
 	if _verbose:
 		_trace_t += get_physics_process_delta_time()
 		if _trace_t >= 1.0:
@@ -891,6 +905,13 @@ func _next_creep() -> void:
 	_creep_flat = true
 	_creep_sum = Vector3.ZERO
 	_creep_n = 0
+	if not is_nan(_creep_pin):  ## PROBE: skip the flat run and the bisection, one trial
+		_creep_row = {"variant": _variant, "kmh": NAN, "rpm": NAN, "load": NAN}
+		_creep_flat = false
+		_step = BISECT_STEPS - 1
+		_best = 0.0
+		_begin_creep(_creep_pin)
+		return
 	_begin_creep(0.0)
 
 
@@ -914,6 +935,9 @@ func _creep_step() -> void:
 	_drive(0.0, 0.0)
 	var up_slope := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3(0.0, 0.0, -1.0)
 	var gain := (_car.global_position - _start).dot(up_slope)
+	if not _creep_flat and _t <= 3.0 + 1e-6:
+		preload("res://tools/probe_rm.gd").dump("creep", int(round(_t * 60.0)), _t, _car, _angle,
+				",gain=%.6f" % gain)
 	if _creep_flat:
 		if _t >= CREEP_FLAT_S - CREEP_MEAN_S:
 			var dt: Drivetrain = _car.drivetrain
@@ -1035,6 +1059,9 @@ func _roll_step() -> void:
 	_roll_min = minf(_roll_min, gain)
 	if _car.drive.hill_holding:
 		_roll_held = _t
+	if _t >= 2.0 - 1e-6 and _t <= 3.5 + 1e-6:
+		preload("res://tools/probe_rm.gd").dump("roll", int(round(_t * 60.0)), _t, _car, _angle,
+				",gain=%.6f" % gain)
 	if _verbose and int(round(_t * 60.0)) % 30 == 0:
 		_print_roll_forces(gain)
 	if is_nan(_roll_go) and gain >= ROLL_GO_M:
diff --git a/tools/measure_semi_launch.gd b/tools/measure_semi_launch.gd
--- a/tools/measure_semi_launch.gd
+++ b/tools/measure_semi_launch.gd
@@ -540,6 +540,9 @@ func _advance(s: Dictionary) -> void:
 				_steady_kg["rest_axle"].append(s["rear_axle_kg"])
 				_steady_kg["rest_trailer"].append(s["trailer_axle_kg"])
 				_rest_speed.append(s["speed"])
+				preload("res://tools/probe_rm.gd").dump("rest", _ticks, _t, _car, 0.0,
+						",rear_axle_kg=%.4f,trailer_axle_kg=%.4f,tool_speed=%.6f,tool_pitch=%.6f"
+						% [s["rear_axle_kg"], s["trailer_axle_kg"], s["speed"], s["pitch"]])
 			# The countdown has run, so the swap sticks; restart the settle so the run always
 			# reports a static pose the trailer it is measuring actually made.
 			if _trailer_pending and _ticks >= TowHost.SPAWN_COUPLE_TICKS:
diff --git a/tools/probe_rm.gd b/tools/probe_rm.gd
new file mode 100644
--- /dev/null
+++ b/tools/probe_rm.gd
@@ -0,0 +1,58 @@
+extends RefCounted
+## Uncommitted per-tick probe (rolling-moment gather). Reads only; prints one PROBE_B line per body
+## and one PROBE_W line per wheel.
+
+const MeasureRig := preload("res://tools/measure_rig.gd")
+
+
+static func dump(tag: String, tick: int, t: float, car: BaseVehicle, slope_deg: float,
+		extra := "") -> void:
+	var host := MeasureRig.coupled_host(car)
+	var trailer: TowedBody = host.trailer if host != null else null
+	_body(tag, tick, t, "unit", car, slope_deg, _unit_extra(car) + extra)
+	_wheels(tag, tick, t, "unit", car, car.wheels)
+	if trailer != null and is_instance_valid(trailer):
+		_body(tag, tick, t, "trailer", trailer, slope_deg, "")
+		_wheels(tag, tick, t, "trailer", trailer, trailer.wheels)
+
+
+static func _unit_extra(car: BaseVehicle) -> String:
+	var dt: Drivetrain = car.drivetrain
+	if dt == null:
+		return ""
+	var ratio := Drivetrain.ratio_for_byte(car.spec, dt.gear_byte)
+	return ",rpm=%.2f,thr=%.4f,gear=%d,cstate=%d,conv=%d,coupling_T=%.6f,crank_T=%.6f,shaft_T=%.6f,ratio=%.4f,eff=%.4f" % [
+		dt.rpm, dt.applied_throttle, dt.gear_byte, dt.coupling_state, 1 if dt.converting else 0,
+		dt.coupling_torque, Drivetrain.crank_torque(car.spec, dt.rpm, dt.applied_throttle, dt.running),
+		float(car.drive.get("_drive_torque")), ratio, car.spec.efficiency]
+
+
+static func _body(tag: String, tick: int, t: float, label: String, body: RigidBody3D,
+		slope_deg: float, extra: String) -> void:
+	var b := body.global_transform.basis
+	var tilt := Basis(Vector3.RIGHT, deg_to_rad(slope_deg))
+	var v := body.linear_velocity
+	var w := body.angular_velocity
+	var p := body.global_position
+	print("PROBE_B,%s,%d,%.4f,%s,v_fwd=%.10f,v_along=%.10f,v_across=%.10f,yaw_rate=%.10f,pitch_rate=%.10f,pos=%.10f;%.10f;%.10f,along=%.10f,across=%.10f%s" % [
+		tag, tick, t, label, v.dot(-b.z), v.dot(tilt * Vector3.FORWARD), v.dot(tilt * Vector3.RIGHT),
+		w.dot(b.y), w.dot(b.x), p.x, p.y, p.z, p.dot(tilt * Vector3.FORWARD),
+		p.dot(tilt * Vector3.RIGHT), extra])
+
+
+static func _wheels(tag: String, tick: int, t: float, label: String, body: RigidBody3D,
+		wheels: Array[RayWheel]) -> void:
+	for i in wheels.size():
+		var w := wheels[i]
+		var rs: Variant = w.get("roll_share")
+		var taken := "NA"
+		if rs == null and w.in_contact:
+			taken = "%.6f" % maxf(-signf(w._patch_v_long) * (w.force_long
+					+ w._patch_long_mass * body.get_gravity().dot(w._patch_forward)), 0.0)
+		print("PROBE_W,%s,%d,%.4f,%s,%d,%s%.2f,%s,%s,c=%d,omega=%.10f,spin_held=%d,patch_held=%d,brake_spin=%.10f,roll_share=%s,long_slip=%.10f,force_long=%.6f,force_roll=%.6f,force_lat=%.6f,susp=%.6f,coupled_T=%.6f,tcs_spin=%.10f,tcs_ceiling=%.10f,tcs_active=%d,taken=%s" % [
+			tag, tick, t, label, i, "R" if w.is_rear else "F", w.anchor.z,
+			"L" if w.anchor.x < 0.0 else "R", "d" if w.driven else "-", 1 if w.in_contact else 0,
+			w.omega, 1 if w._spin_held else 0, 1 if w._patch_held else 0, w.brake_spin,
+			"NA" if rs == null else "%.10f" % float(rs), w.long_slip, w.force_long, w.force_roll,
+			w.force_lat, w.suspension_force, w.coupled_torque, w.tcs_spin, w.tcs_ceiling,
+			1 if w.tcs_active else 0, taken])
```
