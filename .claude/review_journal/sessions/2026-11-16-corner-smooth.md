# 2026-11-16: A5, `CORNER_SMOOTH_S` (cover sweep 3) (Sonnet, auto)

Started at c1a37ec (HEAD then 65cfd41's journal commit). Brief: `summary.md` A5; proving run:
`2026-11-14-cover-sweep.md` § Proving runs (3).

## Proving run

Uncommitted probe (reverted): raw peaks beside the smoothed ones under the same slip-angle gate
(`lat` = `v * yaw_rate`, `|across| / mass`, `|acc_lat|`), plus a per-tick line while `lat` > 0.8 g
or `acc_lat` > 2 g. `measure_vehicles -- <v> 60 track corner`, `--fixed-fps 60`.

| body | `v r` raw / smoothed | tyres raw / smoothed (at the peak) | `acc_lat` raw / smoothed |
|---|---|---|---|
| `sedan` | 0.926 / 0.903 (0.023) | 0.908 / 0.891 | 0.907 / 0.890 |
| `suv` | 0.806 / 0.793 | 0.817 / 0.804 | 0.817 / 0.805 |
| `semi` | 0.288 / 0.281 | 0.626 / 0.604 (0.022) | 0.324 / 0.306 |
| `tractor-kenney` | 0.758 / 0.744 | 0.741 / 0.724 | **10.510 / 1.774** |

The brief's bar (every body within 0.02 g) is not met: the lag stays; `doc=cornering` not re-run.

## What the raw reads did

- `sedan`: the raw `v r` is not a tick alternation. Ticks are smooth (+0.004 g each). After the
  front saturates it hunts about the winding lock: 0.926 (t 8.683, the peak, slip 0.088, far
  inside the 0.5 gate) -> 0.804 (9.05 to 9.15) -> 0.875 (9.40) -> 0.826 (9.60) -> 0.897 (10.0), a
  swing of ~0.1 g over ~0.6 s. A body hunting in yaw past saturation, a model-side
  swing the smoothing averages (`docs/vehicle_measurements.md`: "the peak itself can be a yaw
  swing past it"). So the lag reads the swing's mean, not a hidden fault: kept, and the constant
  now says that (it gave no reason). Not a cover over a tick-rate source.
- `semi`'s tyre-force 0.022 g gap is the same lag on a rising `across / mass` (the headline there
  is `v r`, 0.007 g).
- `tractor-kenney`: `acc_lat` raw is **10.51 g on one tick** (t=6.700, slip 0.45, inside the
  0.5 gate; the tick before 8.48 g, speed 3.2 m/s; the body is tipping, `<-- SLID`), and again
  7.29 g / 2.51 g at t=7.35 / 7.333 at 0.6 m/s. The printed "path 1.77 g at most" is that spike
  after the 0.25 s mean: the smoothing hides a one-tick raw spike that A4 let through. Source not
  traced here (a contact impact as the body tips, or a velocity step in `accel`).

## Done

- 1b4c144: comment on `CORNER_SMOOTH_S` states its reason with the measured figures (tools only; no
  behaviour change). `check_docs` clean.
- Queued (stage B): the tractor's raw `acc_lat` spike at the tip.
