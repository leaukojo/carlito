# 2026-11-26: unit 16, the tractor passes out of `measure_vehicles.gd`

Item: the Queue's top line (hitch, plough, arm move) [high, auto, Sonnet]. HEAD at start: 6922edb.
Contract: `sessions/2026-11-26-measure-split.md` § The pass contract, with the changes below.

## What moved

- `tools/measure_vehicles_hitch.gd`: `hitch` (the statics, `_body_tensor`, `_diag*`).
- `tools/measure_vehicles_plough.gd`: `plough`, `course`, `governor`, `FieldStrip`, the `Plough` stage enum.
- `tools/measure_vehicles_arm.gd`: `arm`.
- `measure_vehicles.gd` goes from 5746 to 4920 lines. It keeps `_hitch_pass`, `_plough_pass`,
  `_course` (the `trailer=` default for the course) and `_arm_pass`; `Phase.HITCH/PLOUGH/ARM`
  are gone, every one of the six runs in `Phase.PROBE` through `_probe`.
- Moved code was diffed against HEAD: only the substitutions below differ.

## Contract changes (for the next moves)

- A pass that restarts its clock mid-run keeps its own `_t` (`_t += delta` first in `tick`; the
  host's `t` argument is ignored there), so `_t = 0.0` in the moved code is unchanged.
- The report line's variant is `String(current["variant"])`; `title` is "<variant> (<drive>)".
- The probe chain is built where the strip used to be laid (before `_queue` is filled), because the
  plough pass prints its `course:` line and adds its strip to the scene in `_init`, and both come
  before the `strip:` line. The `circle` / `course` `trailer=` defaults moved up with it, in
  their old order.
- The plough pass takes the host's `_gate_line`, `_hunting_gate` and a lambda counting a FAIL
  (`_failures += 1`) as callables; hitch's `HITCH_WAIT_S` is read by plough as `Hitch.HITCH_WAIT_S`.
- A `Callable.call()` result needs an explicit type (`var hunt: Array = ...`): warnings are errors.
- The Edit tool is the only way to change a repo file here (the pretool guard blocks `sed -i`
  and shell redirects), so a large deletion is an Edit with the whole block as `old_string`.

## Runs

`scratchpad/tr/run.sh <outdir>`, `--fixed-fps 60`: `tractor-kenney 20 hitch`, `tractor-kenney 20
plough`, `... plough course`, `... plough governor`, `tractor-cvt 20 plough governor`,
`garbage-truck 60 arm`. Baseline at 6922edb, then after: all six logs identical apart from
`elapsed=` and `stock rebuild <n> ms`. Not run: `plough trace` (the trace lines moved verbatim).

Full suite: 2582 cases, 0 failures (the guide-table test from the last session passes now).
`check_docs`, `check_orphans` and `check_gd_text` clean.

## Commits

- ca04892: the three pass files, their `.uid` files, the host.
