# Plan — Lab switches: ABS, axle diffs and Ackermann, on and off

The learning materials teach by "with and without". The game already lets a student flip TC, ESC,
auto hold, the tractor's diff lock and MFWD, the tyre class and the tractor's gearbox, but three
mechanisms the physics already models can only be compared headless (`measure_vehicles` flags) or
by changing vehicle, which changes everything else too: ABS (only `race` lacks it), the axle
differentials (open / LSD / Torsen are fixed per variant) and the Ackermann fraction (`f = 1.0` on
every wheeled body). This plan exposes those three as player-facing switches on the existing
models. No new physics.

Written 2026-10-30. Status: **not started.**
Serves: the learning materials' A/B lessons: a full-pedal stop with and without ABS (locked
wheels, no steering, a longer or shorter stop); an open versus locked axle with one wheel on low
grip and in a tight turn (peel, then scrub and wind-up); parallel versus Ackermann steering at full
lock (both fronts fighting, a wider circle: `docs/handling.md` § Steering geometry's table).
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — Survey and decisions (effort: medium; mode: plan-mode-first)

Read only; the output is a short report and the user's answers.
- Where each mechanism is read at runtime: ABS (`ABS_SLIP`, its users: the coupling opening a
  clutch under ABS, hill-start assist "on every ABS body", ESC "every road body with ABS",
  `BrakeSizing`), the axle and centre diffs (`WheelDrive._couple_differentials`, `Differential`,
  the tractor's `diff_lock` path), `GroundDriveSpec.ackermann` (`WheelDrive.ackermann_angle`).
- Whether an override can live per spawned body without mutating the shared spec `.tres`
  (a shared resource written at runtime leaks into every later spawn and the garage preview).
- What a student can watch the effect on: the F3 readouts and cluster today (wheel speeds, slip,
  steer angles). If a lesson's effect is invisible there, list the smallest readout that shows it.
- Decisions for the user, each with a recommendation:
  1. Local only (a SETTINGS group like STABILITY CONTROL) or also on the bus (contract signals,
     `contract-edit` skill). Recommended: local only; ESC's `esc_off` is the precedent if the bus
     is wanted later.
  2. Session-wide and unsaved (like CONDITIONS) or saved (like SETTINGS). Recommended: session-wide,
     so a student never starts a later visit with ABS off unknowingly.
  3. ABS off takes ESC and TC with it (a real ESC acts through the ABS modulator) or leaves them.
     Recommended: takes them, lamps lit as `esc_off` does.
  4. The diff switch's values: STOCK / OPEN / LOCKED per driven axle, or one switch for every
     driven axle. Recommended: one switch, centre diff untouched.
  5. The Ackermann values: STOCK (1.0) / PARALLEL (0), or a third point at 0.5.
- A challenge always runs stock (the tyre class's rule, `Boot._fit_tyre`).

Done when the user has answered the decisions.

## Phase 1 — The switch plumbing and ABS (effort: high; mode: plan-mode-first)

- The switch state as phase 0 decided, reaching the vehicle only through `VehicleInput` from
  `InputRouter` (root rule 5); the arbitration as pure static functions with tests
  (`tests/test_input_arbitration.gd`); kept through a respawn and a variant cycle, stock in a
  challenge.
- The UI row(s) in the decided screen, with the touch and CONTROLS sides generated from
  `ActionRegistry` as every other action is.
- ABS off: the brake step without the ABS hold, and whatever phase 0 found depends on ABS
  (ESC, TC, hill-start assist, the coupling's opening) following decision 3. `BrakeSizing` and
  `test_vehicle_catalog` judge the stock hardware, unchanged.
- Tests: the override is a pure function of spec plus switch. Measure: `measure_vehicles --
  sedan 30 brake` with and without, run headless in the background (`--fixed-fps 60`).
- Done when the user has driven a full-pedal stop and a braked turn on `sedan`, both ways.

## Phase 2 — The axle diff switch (effort: high; mode: plan-mode-first)

- OPEN replaces a driven axle's bias with the open diff; LOCKED uses the unbounded coupling the
  tractor's `diff_lock` already uses; STOCK is the spec. The centre diff and the tractor's own
  lock and MFWD stay as they are (on the tractor the switch is hidden or mirrors `diff_lock`:
  decide in phase 0's report).
- Check the solve order's one-pass COMPROMISE (`docs/vehicles.md` § Both pedals) still holds on a
  locked car axle; `BrakeSizing.stall_hold_margin` stays a stock-only check.
- Tests: the coupling chosen per switch value. Measure: `measure_grade` with one side on low grip
  if a split surface exists, else the rough-ground course (`measure_rough`), and `circle`
  (`measure_vehicles -- sedan 30 circle`) for the locked axle's scrub.
- Done when the user has driven a car through the level 1 wallow and a tight turn, open and locked.

## Phase 3 — The Ackermann switch (effort: medium; mode: accept-edits)

- PARALLEL sets the per-body fraction to 0 through the same override path; `mean_steer_angle()`
  and guidance unchanged (they read the driver's angle).
- Tests: `test_vehicle_catalog`'s Ackermann asserts stay on the stock spec; one new test that the
  override's `f` reaches `WheelDrive.ackermann_angle`. Measure: `circle` with the switch both ways
  against the table in `docs/handling.md` § Steering geometry.
- Done when the user has driven full lock on `sedan` and `tractor-kenney`, both ways.

## Phase 4 — Docs (effort: low; mode: accept-edits)

- `docs/systems.md` (the switch group, where it lives), `docs/vehicles.md` / `docs/handling.md`
  (one line each at ABS, the diffs, Ackermann pointing at the switch), `docs/HUMAN_EXPLANATIONS.md`
  (one sentence). Then distil and delete this plan (root `CLAUDE.md` § Where things go).
