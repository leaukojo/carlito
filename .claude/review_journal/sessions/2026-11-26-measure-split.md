# 2026-11-26: unit 16's split, the contact passes out of `measure_vehicles.gd`

Item: the Queue's top line (unit 16's split) [high, plan, Opus]. HEAD at start: 0535096.
Plan approved by the user: kerb, side and scrape move to files of their own on one contract; the
tractor passes and the small parked probes are queued; the rest stays.

## Decisions

- Move now: `kerb`, `side`, `scrape` -> `tools/measure_vehicles_{kerb,side,scrape}.gd`.
- Queued: the tractor passes (`hitch`, `plough` with `course` / `governor` and `FieldStrip`, `arm`),
  then `stall` / `freerev` / `rest` / `handbrake`.
- Stay: accel, launch trace and gates, tracking, coast, braking, cornering, step, sine, the ESC
  reference, circle, cruise (they share the gates, `_rf_*` and `_reset_pass`; the tests preload
  `sine_series` / `tail_settled` from the file), and the doc tables (`_sweep`, `DOC_*`).

## Findings

1. Duplicated logic: `_wheelbase` twice.
   - `measure_vehicles.gd:5294`:
     `return maxf(float(ax["rear_z"]) - float(ax["front_z"]), 1e-3)`
   - `measure_semi_launch.gd:819`:
     `return float(ax["rear_z"]) - float(ax["front_z"])`
   - Fix: one `MeasureRig.wheelbase_of(spec)`. The `1e-3` floor guards a value no body reaches:
     `BalanceModel.from_spec` (`balance_model.gd:74`) divides by the same wheelbase with no floor.
   - The name is `wheelbase_of` because a plain `wheelbase` is a parse error: the local
     `var wheelbase` in `MeasureRig.pursuit_steer` shadows it, and warnings are errors.
2. Wrong comment: `_wheelbase`'s doc sits above `_start_side` (`measure_vehicles.gd:5058`):
   "## Wheelbase (m) off the axle stations, foremost front to rearmost rear. A tandem's effective
   wheelbase is shorter, ... ## The laid-over holds (§ side) on this body." It moves onto
   `MeasureRig.wheelbase_of`.
3. Shared setup in the host: `_pi_pedal` turns the PI's fuel command into a pedal. It has 13 host
   call sites, and the kerb crawl needs it. It moves to `MeasureRig.pi_pedal(car, u, v_set)`
   unchanged.

## The pass contract (what the next moves follow)

- A pass file `extends RefCounted` and never reads the host's `_` fields.
  - `_init` takes what it reads: the scene (kerb / scrape add their geometry under it), `START_Z`,
    the cap or `_trace`, its own `MeasureRig.PiHold` on `SPEED_HOLD_KP/_KI`, and two callables:
    `_reset_pass.bind(Phase.PROBE)` (called after each respawn) and `_finish_vehicle`.
  - `start(car, title, current)` and `tick(delta, t)`, with `t` the host's `_t`.
- The host builds the pass once, at the end of `_ready`: kerb, else side, else scrape, the old
  precedence. `_probe: Variant` is called dynamically, and `check_orphans` counts the call.
- Scrape's crawl is `measure_vehicles_kerb.gd`'s `static func crawl`, the one copy.
- Moved code was diffed against HEAD: only the substitutions above differ.

## Runs

Script: `scratchpad/split/run.sh <outdir> <helpers|moved|all>`, `--fixed-fps 60`. Nine runs:
- `sedan,semi 45 track corner`, `tractor-cvt 30 circle`, `sedan 60 step`, `tractor-kenney 20 hitch`
- `measure_semi_launch -- semi`
- `sedan,semi,tractor-kenney 60 kerb`, `sedan,semi 20 side trace`
- `firetruck 45 scrape onebody`, `semi 45 scrape steer=20 trace`

Baseline at 0535096, then after each commit. All nine logs are byte-identical, apart from
`elapsed=` and the reference table's wall-clock `stock rebuild <n> ms`.

Full suite at a8303eb: 2533 cases, 7 failures, all in one test outside this unit,
`test_vehicle_catalog.gd`'s `test_the_guide_tables_repeat_the_catalog_descriptions`:
- the guide's `car.md` `suv` row adds "governed to 180 km/h";
- `boat.md` and `drone.md` have no "What it is" table;
- no guide family table lists `drone-mk2`, `boat-speed-a`, `-j` or `boat-sail-a`.

The test reads `docs/guide/` and the catalog, none of which this session touched. Recent guide
commits (`1fd084e doc update`, `4ff57a9`) are the user's.

`check_orphans`, `check_docs` and `check_gd_text` are clean.

## Commits

- 095ceb7: `MeasureRig.pi_pedal` and `wheelbase_of` shared (findings 1 to 3).
- 9c5e673: kerb, side and scrape in `tools/measure_vehicles_{kerb,side,scrape}.gd`.
  `measure_vehicles.gd` goes from 6280 to 5746 lines.
- a8303eb: `tools/CLAUDE.md`'s measure-tool rule.

## Deferred

- The tractor passes, and then the small parked probes, are queued in `summary.md`.
