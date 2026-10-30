# Plan — ESC's reference K: past the table, other tyres, other loads, the coupled rig

ESC's yaw reference reads the body's K off a table built offline from the corner model at the
spec's stock tyre and load (`GroundDriveSpec.esc_reference_k`, `StabilityControl.reference_table`).
Four gaps follow (`docs/handling.md` § Stability control, Limits): the table is held flat past its end,
so K under-reads at the limit (the sedan's table ends near 0.74 g, its limit near 0.86); a tyre
swap (`WheelDrive.fit_tyre`) or a laden hopper (`BaseVehicle.set_live_mass`) keeps the stock
table; and a coupled semi reads the bare unit's K, though the trailer moves the rig's balance. A
reference too understeery reads a false oversteer (needless braking); too oversteery, a late catch.

Written 2026-10-25. Status: **not started.**
Serves: the yaw lesson staying honest when the player fits other tyres, loads the truck or tows:
ESC brakes for what the body does, not for a table of another body.
State: done — nothing; next — phase 0; open findings — none.

## Decisions for the user (asked in phase 0)

1. **Past the table.** Extend the sweep to the model's limit, or extrapolate its last slope, or
   keep it flat (measured first: how often a step or corner run reads past the end).
2. **Tyre and load.** One table per tyre class baked offline, a table rebuilt on a swap or load
   change (cost measured: `BalanceModel.k_curve` runs 3-30 ms a body on desktop, too slow per
   tick, perhaps fine per swap), or a correction on the stock table.
3. **The coupled rig.** A rig reference (the corner model has no coupled form; phase 4 of plan 3
   judged the unit's K in the steady tables only), a correction keyed on the coupled load the unit
   senses (`WheelDrive.brake_load_kg`), or the unit's K kept with its bound.

## Phase 0 — Measure the gaps, then decide (effort: high; mode: plan-mode-first)

- Background, `--fixed-fps 60`, `noesc` for the chassis's own K: the step pass's K against the
  table's K at each held cell on the stock tyre, on each tyre class (`tyre=`), on the laden
  `garbage-truck` and on the coupled semis (box, bobtail); how far past the table's end the step
  and corner passes read, and the yaw error ESC would read there.
- The three decisions above, asked once with those numbers, recorded here.

## Phase 1 — The reference, pure and tested (effort: high; mode: plan-mode-first)

- Per the decisions, in `StabilityControl` / `BalanceModel` (root rule 8); gdUnit4 on each new
  path; `test_vehicle_catalog`'s staleness check extended to any new baked table.

## Phase 2 — Measure and document (effort: medium; mode: accept-edits)

- With ESC on, baseline at HEAD first, like with like: the step pass's ESC braking share on held
  steady cells (should fall where a false error was read), `doc=esc`, the semis' step and corner
  passes; no chatter. `docs/handling.md` § Stability control updated in place; figures only in a
  `<!-- measure:<id> -->` region.
