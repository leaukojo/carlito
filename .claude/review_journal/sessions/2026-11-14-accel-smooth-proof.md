# 2026-11-14: `BaseVehicle.ACCEL_SMOOTH`, the proving run (Opus, plan)

Started at 54e7f4b. Follows `2026-11-14-accel-smooth.md` (the diagnose verdict: a cover).
Ends in a proposal; no code ships. Temporary edits are undone after each run.

## Consumers a raw signal moves

- `src/challenges/defs/car_corner_budget.tres`: `SignalLimitConstraint` on `accLat`, fails on the
  first tick outside its band.
- `tools/measure_vehicles.gd`: corner pass (`acc_lat` at 2498, 2502, 2529), sine pass (3527),
  rest (3140, 3170); `tools/measure_semi_launch.gd:409`.
- `TowedBody.accel_lat` borrows the constant (`towed_body.gd:208`): left alone in every run.

## Runs

### Standing, at HEAD (the `rest` pass prints raw and sent, so no edit was needed)

`measure_vehicles.tscn -- <variant> 20 rest`, `--fixed-fps 60`:

| body | raw accel p-p | accLong as sent p-p |
|------|---------------|---------------------|
| `semi` (bobtail, D) | 0.001 m/s2 | 0.000 |
| `tractor-kenney` (D, hill hold) | 0.001 m/s2 | 0.000 |

The 2.435 m/s2 tick alternation of 2026-11-13 is gone at HEAD (F1's fix): standing, the lag
hides nothing.

### Driving (uncommitted probe in `BaseVehicle`, reverted)

Probe after `base_vehicle.gd:283`: per 2 s window, raw `body_accel` p-p and sent p-p per axis,
and `hf` = RMS of the raw second difference / 4 (the tick-rate amplitude: pure alternation of
amplitude A gives A). Runs: `-- <variant> 60 cruise` for `sedan-sports`, `semi`,
`tractor-kenney`; `-- sedan-sports 60 track corner`. The first window (spawn drop) dropped.

| body (cruise, all speeds) | `hf` x median / p90 | y | z |
|---|---|---|---|
| `sedan-sports` | 0.000 / 0.062 | 0 / 0 | 0.001 / 0.022 |
| `semi` | 0.004 / 0.032 | 0 / 0 | 0.004 / 0.025 |
| `tractor-kenney` | 0.029 / 0.182 | 0 / 0 | 0.002 / 0.022 |

- The large raw-vs-sent gaps (x up to 3.1, z up to 9.0 m/s2 p-p) are real events: each cruise
  speed restarts from a respawn drop (z 14 m/s2 raw, 6.5 sent) and the launches' shifts (tractor
  x 8.6 raw, 5.7 sent). The lag shortens real jolts; it does not stand between a fault and a
  reader there.
- Held speeds: `hf` 0.000 to 0.015 on every body. Nothing to hide.
- Corner (`sedan-sports`, the `car_corner_budget` body): steady corner `y` raw 2.72 vs sent
  2.71 p-p, `hf` 0.06 to 0.09 m/s2; on the wind-down raw exceeds sent by up to 0.45 m/s2 p-p.
  Against the challenge's 4.0 m/s2 limit, raw would fail a tick or two earlier near the edge.
- The one tick-rate source: `tractor-kenney` launching, `hf` x 0.11 to 0.28 m/s2 in the windows
  under about 3 m/s, 0.01 to 0.04 above, on all three launches. `RayWheel.road_change`
  (`wheel.gd:1138`) fades its patch from full at 3.0 m/s (`2 * LOW_SPEED_FLOOR`) to none at 1.5.
  The band matches proposal "The wheel and the body exchange one force" (the free wheel's
  slip reversing every tick, the body getting `T / ((1 + a) r)` below the floor). Matched by
  speed band, not proven by a run with the fade removed: that run belongs to the proposal.

## Verdict

At HEAD the lag hides no fault standing and almost none driving; it attenuates real events
(landings, shift jolts) by about half. Still a cover by its stated reason (no source), so the
choice is between sending raw and declaring a sourced sensor filter: a proposal
(`proposals.md`, "accLong / accLat / acc_vert: raw or a declared sensor filter"). The tractor's
low-speed content is the existing proposal's, not a new Queue line.
