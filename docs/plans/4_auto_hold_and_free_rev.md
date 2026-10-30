# Plan — Auto hold as a visible choice, and a free-rev cap in N/P

Two behaviours that misrepresent the vehicle to the learner:
- **Auto hold on keys and touch** (`InputRouter.auto_hold`, `AUTO_HOLD_BRAKE`): stopped in D or
  R with no throttle, the whole foot brake holds until the throttle asks to move. Always on for
  keys and touch, with no switch and no indicator, so most learners never feel converter creep or
  roll-back (`docs/drivetrain.md` § Creep, § Hill hold). A real car's auto hold is a button the
  driver turns on, with a lamp.
- **A free crank in N or P on the petrol map** runs to the rev limiter on a tenth of the pedal
  (`docs/drivetrain.md` § The pedal map: the map is a loaded dynamometer's, and a free crank nets
  positive torque at any rpm). A mechanic notices it at once.

Written 2026-10-23. Status: **not started.**
Serves: creep and roll-back felt on the keyboard and touch, the converter lesson; `rpm` in N
reading what a real engine does on a light pedal.
State: done — nothing; next — phase 0; open findings — none.

Order: 4, independent of plans 2-3.

## Phase 0 — Decisions and figures (effort: medium; mode: plan-mode-first)

Decisions for the user:
1. **Auto hold default.** Off (recommended: the realistic creep, the lesson) or on, as a
   SETTINGS toggle either way.
2. **Indicator.** A local dashboard indicator only (recommended: auto hold is a keys and touch aid
   that the bridge never gets, so publishing it as vehicle state would claim a system the bridge's
   driver cannot have), or a status bit through the `contract-edit` skill.
3. **Key.** Whether a key toggles it as well as SETTINGS, and which one (`src/input/` keymap).

Figures:
- A free-rev limit in N/P for a petrol car of the `CAR_BASE` class, from a page actually opened
  (an owner's manual or service document); none found means the plan asks the user before
  shipping an estimate.
- The current behaviour, measured headless: a `freerev` pass in `measure_vehicles` (in N, pedal
  stepped from 0.05 to 1.0, the settled rpm per step) on one body of each pedal map (`sedan`,
  `delivery`, `semi`, `tractor-kenney`). Only a map whose free crank runs away gets the cap.

## Phase 1 — Auto hold toggle (effort: low; mode: accept-edits)

- The toggle owner is `InputRouter` (`src/input/CLAUDE.md`: toggle owners live there), saved by
  `UserSettings`, shown in the pause menu beside TRACTION CONTROL (`src/ui/pause_menu.gd`), the
  default per decision 1. `auto_hold` never latches while it is off; hill-start assist
  (`WheelDrive.hold_step`) is unchanged on every ABS body.
- `tests/test_input_arbitration.gd`: off never latches; on keeps today's cases.
- The indicator per decision 2. The measure tools drive the bridge stash, which never had auto
  hold: no table moves.
- Update the auto hold bullet in `docs/drivetrain.md` § Hill hold.
- The user drives a stop and a pull-away on `sedan` and `garbage-truck` with it off, on keys.

## Phase 2 — Free-rev cap in N/P (effort: medium; mode: plan-mode-first)

- A `VehicleSpec` field (`free_rev_limit_rpm`, 0 = none) on the bodies phase 0 found running away,
  set in `tools/gen_kenney_vehicles.gd` + regen (the `vehicle-feel` skill).
- It is the limiter's own fuel cut at a lower line (`Drivetrain.limiter_cut` and the crossing
  tick landed on the line in `couple`), so the one engine law sees it on `applied_throttle`, never
  a pedal clamp. It applies only with the gear in N or P: never in a drive gear with the clutch
  open (a shift, the rev-match blip, a pull-away's slip), never on the stall test (`30 stall`, in
  D), and never in a PTO set-speed mode (`docs/truck.md` § The refuse body), which governs the
  crank itself.
- `tests/test_drivetrain.gd`: in N at a light and a full pedal the crank settles at or under the
  line; the blip and a D-gear launch are unchanged.
- Retire the free-crank line in `docs/drivetrain.md` § The pedal map; re-run the `freerev` pass
  (background, `--fixed-fps 60`). A new table goes in a generated `<!-- measure:<id> -->` region
  (`tools/check_docs.mjs` holds loose figures at their cap).
- The user revs `sedan` in N for feel.
