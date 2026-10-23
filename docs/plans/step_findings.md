# Plan — Two step-pass findings: an unsettled CVT tractor, a held semi rollover

The step pass reads a held step once its tail settles (`measure_vehicles.tail_settled`, up to
`STEP_HOLD_MAX_S`). Run on every body, that hold shows two things no plan owns:
- `tractor-cvt`'s held steps at 25 and 34 km/h never settle;
- the laden `semi` rolls on a held step at a steady g under its measured ceiling.

This plan finds each one's mechanism and fixes it where it lives, or states it as measured physics.

Written 2026-10-23. Status: **open.**

## The evidence (2026-10-23, `-- <v> 60 step`, the settle-gated pass)

- **`tractor-cvt`:**
  - every held step at 25 and 34 km/h, at all three locks, reaches the 8 s cap `UNSETTLED`;
  - at 15 km/h each settles at 3.02 s;
  - the lifted steps read normally;
  - `tractor-kenney`, the same body on the powershift, settles every held step at 3.02 s;
  - its K reads its pred to +0.02 / +0.00 at 25 / 34 km/h. `tractor-cvt` reads +0.04 / −0.08,
    against an unsettled tail.

  On the CVT the foot pedal commands ground speed (`docs/tractor.md` § The CVT tractor), and the
  step pass drives it with its PI speed pedal. That makes a speed loop around a speed loop: the
  first suspect.
- **The laden `semi`** (`semi trailer=box`):
  - its 50 km/h 30 % held step is upright at 3 s, at a steady 0.33 g with two wheels up and 11 deg
    of roll, and rolls at 3.73 s;
  - without roll steer (`rollsteer=0,0`) it rolls at 3.28 s, so roll steer is not the cause;
  - the box's `rollover_g` is 0.45, and the rollover rows (`measure_semi_launch` P7, in
    `docs/truck.md` § Truck sizing (derivations)) put the tall bodies' wheel lift under it, not
    the roll;
  - `semi-conventional` laden rolls its 70 km/h 20 % held step without roll steer, and not with it.

## Constraints that bind every phase

- Root `CLAUDE.md`, `src/vehicles/CLAUDE.md`, and its `truck/` and `tractor/` rules:
  - tipping before sliding is the bar or `mu_lat`, never a lower COM, slower steer or detuned lock;
  - a towing bug is fixed in `TowHost` (shared), never on one machine;
  - a semi spec change is made on both `semi_spec.tres` and `conventional_spec.tres`;
  - never weaken a clamp or raise the tick.
- **Diagnose first.** A trace is a temporary probe, reverted and never committed, unless it earns
  a place as a flag or print in the tool.
- **A tool artefact is fixed in the tool; a sim bug in the sim, with a test (rule 8).** No spec
  moves to make a measurement settle or a rig stay upright.
- Runs: `--fixed-fps 60`, one headless Godot at a time on this checkout, long sweeps in the
  background. Ask the user about feel only.
- Figures: a measured output lives in a generated `measure:` region, and prose points at it.
  `docs/` sits at its line cap (`node tools/check_docs.mjs`), so an addition is paid for by a cut.

## Phase 1 — `tractor-cvt`'s held steps never settle

Effort **medium**. Permission **normal**.

1. **Name the gate.** `UNSETTLED` prints which of `tail_settled`'s gates failed, with its value.
   That is a lasting print, with a test in `tests/test_measure_settle.gd`.
2. **Trace** the 25 and 34 km/h 10 % held steps over the full 8 s, beside `tractor-kenney`'s, per
   tick:
   - speed, the PI pedal and its integral;
   - `Drivetrain.cvt_i`, the engaged range (`gear`), crank rpm, the managed setting;
   - the limit-load state.

   Read the period and amplitude of whatever oscillates, and which signal leads.
3. **Close it where it lives:**
   - **the PI pedal fights the CVT's ground-speed command:** the step pass drives a CVT's pedal
     as that command, its share of the road-speed limit. Check the corner and circle passes,
     which share the PI pedal (`CORNER_PEDAL_KP` / `_KI`), for the same fault and fix them alike;
   - **the controller hunts under a steady load** (range hysteresis, `cvt_setting_step`,
     limit-load control): fix it in `Drivetrain`, with a test. Never slow the controller to hide
     a limit cycle;
   - **the body's own response** (a real CVT under a constant pedal): state it in
     `docs/tractor.md` § The CVT tractor, with the trace's figures in a generated region.

**Done:** `tractor-cvt`'s held steps settle within the cap and its K reads its pred as
`tractor-kenney`'s does, or the oscillation is named with its period, amplitude and owner. Suite
and both CI gates green; `docs/tractor.md` updated if the fix is the body's.

## Phase 2 — The laden semi rolls on a held step

Effort **high**. Permission **plan-mode-first**: the classification decides whether shared towing
code moves.

1. **Trace** `semi trailer=box`'s 50 km/h 30 % held step to the roll, beside its 20 % step (which
   stands), per tick:
   - the path's g, speed, the mean steer;
   - the tractor's and the trailer's roll, and their difference against the plate's roll stop
     (`ROLL_LIMIT_DEG`);
   - every wheel's load and the order in which they lift;
   - the anti-roll bars' forces.
2. **Read the mechanism:**
   - is the g climbing, for example the PI pedal winning back speed and tightening the turn?
   - is the roll creeping at a constant g (a slow divergence through the roll stop, a bar on a
     lifted partner, the tyres' lateral load)?
   - or is a roll oscillation growing?

   Compare the held tip with the rig's slow tip (P7, `measure_semi_launch -- semi trailer=box`)
   and its `rollover_g`.
3. **Bracket it across the fleet:** the same held steps on the other bodies (`trailer=<tanker|
   tipper|flatbed|bobtail>`) and on `semi-conventional`, with and without roll steer. That shows
   which rigs a long hold tips and at what g.
4. **Classify and close:**
   - **measured physics:** a laden box at a steady 0.33 g with two wheels up keeps rolling, which
     a real rig with this 1.44 m track does too (the track COMPROMISE: every ceiling reads ~25 %
     low). State the held step's tip beside P7's in `docs/truck.md` § Truck sizing (derivations).
     No spec moves;
   - **a mechanism artefact** (the roll stop winding up, a clamp, the bar latch on a lifted
     wheel): fix it in the shared towing code (`TowHost`, the fifth wheel) or `RayWheel`, with a
     test. Then re-measure the rollover rows (P7 on every body), both `measure_semi_launch` gates,
     and the semis' step sweeps, and restate both spec headers.

**Done:** the held rollover is explained by a measured mechanism, and `docs/truck.md` § Truck
sizing (derivations) states it; or the artefact is fixed and every rollover row is re-measured.
Suite and both CI gates green.

## Phase 3 — Distill and close

Effort **low**. Permission **accept-edits**. Needs phases 1 and 2.

- Distil each outcome into `docs/tractor.md` / `docs/truck.md` (and `docs/vehicle_measurements.md`
  for a new flag or print), at most one CLAUDE.md line if a constraint emerged.
- Delete this plan; repoint anything that names it (`check_docs` clean).
