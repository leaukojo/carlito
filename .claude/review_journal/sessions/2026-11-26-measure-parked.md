# 2026-11-26: unit 16, the parked probes out of `measure_vehicles.gd`

Item: the Queue's top line (stall, freerev, rest, handbrake move) [medium, auto, Sonnet]. HEAD at
start: 099f398. Contract: `sessions/2026-11-26-measure-split.md` § The pass contract as amended by
`sessions/2026-11-26-measure-tractor-passes.md` § Contract changes.

## What moved

- One shared `tools/measure_vehicles_parked.gd` (`Kind { STALL, FREEREV, REST, HANDBRAKE }`), the
  smaller choice: four files would each repeat the header, `_init`, `start` and `tick` (about 25
  lines), and stall and handbrake share the `_probe_*` state.
- It holds the constants (`STALL_*`, `FREEREV_*`, `REST_*`, `HB_*`), the four probes, `_swing` and
  the `rest` printers. The host keeps `_stall`, `_freerev`, `_rest`, `_hb_turn`, `_rest_state`,
  `_rest_crr` (flag parse) and `_freerev_table` (it reads `ParkedPass.FREEREV_*`).
- `Phase.STALL / FREEREV / REST / HANDBRAKE` are gone: all four run in `Phase.PROBE`.
- `measure_vehicles.gd` goes from 4920 to 4547 lines.
- The host builds the pass first in the chain (stall, freerev, rest, handbrake: the old order
  among them). `Kind` is passed as an `int` (an int variable into an enum parameter is a warning,
  and warnings are errors).
- The pass takes `START_Z`, `_seconds`, `BRAKE_LOCK_SLIP` (the braking pass shares it), `_trailer`,
  `_rest_state` and `_rest_crr` in `_init`; the variant is `String(current["variant"])`.
- Every pass keeps its own `_t` (`_t += delta` first in `tick`, `_t = 0.0` after `_restart.call()`):
  the same sum from zero as the host's, so freerev's own `_t = 0.0` per step is unchanged.
- Diffed against HEAD: only `_reset_pass(Phase.X)` -> `_restart.call()` + `_t = 0.0`,
  `_finish_vehicle()` -> `_finish.call()`, `_variant`, `START_Z` and `BRAKE_LOCK_SLIP` differ.
- Precedence: a `cruise`, `sine`, `step` or `circle` flag given with one of the four now wins over
  it (they are checked before `_probe` in `_next_vehicle`); such combinations are not run lines.

## Runs

`scratchpad/parked/run.sh <outdir>`, `--fixed-fps 60`: `sedan,semi 30 stall`, `sedan,delivery,semi,
tractor-kenney 40 freerev`, `semi 20 rest`, `semi 20 rest=brake`, `semi 20 rest=n`, `semi 20
rest=handbrake crr=0.012`, `sedan 30 handbrake`. Baseline at 099f398, then after: all seven logs
identical apart from `elapsed=` and `stock rebuild <n> ms`.

Full suite: 2582 cases, 0 failures. `check_docs`, `check_orphans` and `check_gd_text` clean.

## Commits

- 6feded8: `measure_vehicles_parked.gd` (and its `.uid`), the host.

## Deferred

Nothing: the move is whole. The host's remaining probes (accel, coast, tracking, cornering, step,
sine, circle, cruise, braking) share the gates, `_rf_*` and `_reset_pass` and stay (the split
session's decision).
