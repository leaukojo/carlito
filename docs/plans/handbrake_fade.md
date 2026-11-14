# Plan — The handbrake fades with its brake

A hot brake is weak whichever way it is applied: the handbrake and a truck's spring brakes push
the same lining onto the same metal as the foot brake. The game fades only the foot brake, so a
driver who has cooked the brakes on a descent still has a full-strength handbrake, an escape most
real vehicles do not give. This plan applies the brake's fade to its parking torque, and gives the
player guide a section that explains the two ways one brake is applied.

Written 2026-11-13. Status: **not started.**
Serves: `brake_temp` and `handbrake` behaving as on a real vehicle (standing rule 3: a simple
honest model). No contract signal is added or retyped; `handbrake`'s description is reworded.
State: done: nothing. Next: phase 1. Open findings: none.

Each phase is one session and ends with the suite (`node tools/godot_run.mjs --tests -- -a tests`)
and a short "please verify" list for the user. Phase 2 needs phase 1 merged: it describes the code.

Models: the session's own model, never a subagent doing the phase. Opus for both phases.

Queue: no conflict with `.claude/review_journal/summary.md` at 99c2456. F1 bisects a standing
truck by handbrake state with every brake at ambient (fade factor 1), so its tables do not move;
if F1 has edited the same lines of `wheel_drive.gd` first, this change goes on top of it.

## Decisions (user, 2026-11-13, unless marked)

- **D1, one factor.** The parking torque takes the same `RayWheel.brake_fade()` as the service
  torque on that wheel: one lump, one lining, one curve. No second curve, no new spec field.
- **D2, the handbrake is no backup for a faded brake.** The real case where it is one (boiled
  fluid, a soft pedal, a cable that still works) is fluid fade, which the game does not model. It
  goes under "What the game leaves out".
- **D3, a hot brake parks on less (to confirm at phase 1's start).** `BrakeSizing`'s parking
  grade is a cold figure and stays one, as the pedal map stays cold. A body parked on a steep
  grade with brakes past their onset can roll until they cool; the P pawl does not fade. That is
  the modelled hardware's behaviour, not a fault to cover.
- **D4, left out.** Separate handbrake shoes inside a rear disc's hub (cooler lining); a disc
  shrinking as it cools under a parked caliper. Named in the guide, not modelled.
- **D5, unchanged.** A locked wheel still heats nothing; the retarder and engine braking still
  heat nothing; a body with no thermal model (`brake_heat_capacity` 0: the plane) reads factor 1.

## Phase 1: the parking torque fades

Effort: medium. Mode: accept-edits. Model: Opus. Skill: `vehicle-feel` (brakes).

Sites (read at 99c2456):
- `src/vehicles/base/wheel_drive.gd:658-662`: `parking_torque(...)` is added to `brake_t` and
  `friction_t` unfaded, under the comment "Heats the drum but never fades: hot-drum parking is
  out of scope". Multiply it by `w.brake_fade()`; the comment states the present rule.
- `src/vehicles/base/towed_body.gd:173-176, 190`: `service * w.brake_fade() + parking`. The
  parking term takes the factor too; the comment follows.
- The torque still enters `RayWheel.tick` as `brake_t` (solved in the spin step, never after it).

Before editing, list every other reader of `handbrake_torque` and of the parking application
(`BrakeSizing`, `Drivetrain`'s hold near line 1030, `semi.gd:100`, `TowHost.tick_towing`,
`HillHold`) and say for each whether it predicts a hold from the cold torque. A predictor that
decides something at run time from a torque the wheel no longer gets is a finding: stop and report
it, do not patch around it. `BrakeSizing`'s gates are cold sizing and stay (D3).

Tests (`tests/test_brake_fade_wiring.gd`):
- `test_a_hot_parking_brake_commands_its_whole_torque` becomes its opposite: at `HOT` the rear
  wheels command `handbrake_torque * 0.5`, and still heat.
- `test_a_towed_bodys_service_brake_fades_and_its_parking_brake_does_not`: both fade.
- New: foot brake and handbrake together on a hot rear wheel command
  `(service + parking) * factor`; a cold wheel commands the whole of both (the regression guard
  for every cold figure in `docs/`).
- The suite's header comment (lines 2-5) follows.

Docs, reworded in place (the `docs/*.md` budget is full: `tools/check_docs.mjs`):
- `docs/vehicles.md:272` "parking brakes heat but never fade".
- `docs/guide/brakes.md:99-100` "the handbrake heats but never fades": the one sentence only;
  phase 2 writes the section.
- `contract/carlito_contract.json`, `handbrake`: "It locks the rears at speed and parks the laden
  vehicle on its regulation grade" is true of a cold brake only. Say so, and that it fades with
  its brake (the `contract-edit` skill; a description only).
- `docs/vehicle_measurements.md`: its handbrake and parking runs are cold and do not move; no
  measure run unless one of them is found to heat a brake past its onset.

Measured headless before the verify list is written: per body, `BrakeSizing.rear_lock_ratio`
and `BrakeSizing.park_grade` cold, and both with `handbrake_torque` scaled by its curve's factor
at 300 °C and at the curve's last point. Where the hot ratio stays above 1 the handbrake still
locks the rears and the player sees no difference at speed; the table says which bodies change
and how, and goes in the session's report (not in `docs/`).

Please verify (user, by driving), on the body the table shows changing most: heat the brakes on
Level 2's long grade on the foot brake, then (a) pull the handbrake at speed and (b) stop on the
grade on the handbrake alone. Expected, with the figures from the table: (a) the rears lock later
or not at all and the body slows less than with cold brakes; (b) it may creep until the brakes
cool, and holds in P.

## Phase 2: the guide explains how one brake is applied two ways

Effort: medium. Mode: accept-edits. Model: Opus.

The page exists: `docs/guide/brakes.md` (hardware, pedal, handbrake, heat and fade, retarder, air
and spring brakes). This phase adds to it and follows `docs/guide/template.md`; no new page.

- **New section, "One brake, two ways to apply it"**, after "The handbrake". The real idea first:
  the pedal pushes the pad with fluid (a car) or air (a truck); the handbrake pulls the same pad
  with a cable, or a truck's spring pushes the same shoe. Then the game: one torque per wheel made
  of both applications, one temperature, one fade factor on the sum.
- **Figure 1** (a new SVG in the guide's `img/`, named "brake-two-ways"): one rear disc and caliper in section, the hydraulic line
  from the pedal and the cable from the lever both ending on the same pad. Drawn by hand to the
  template's rules (own class prefix, `--fig-*` tokens, about 420 wide), alt text and caption.
- **Figure 2** (another, named "brake-heat-path"): where a stop's energy goes. Speed into the brake's lump
  as heat, out to the air faster with road speed; a locked wheel sends it to the tyre instead.
  Check it against `BrakeThermal.step` and `RayWheel.heat_brake`.
- **"Heat and fade" rewritten where it says the handbrake never fades**: a worked case with game
  figures, each with its source comment (the `BrakeThermal` curve point read, the body's
  `handbrake_torque`): what the handbrake of one car and one drum truck gives cold and at one hot
  temperature.
- **"What the game leaves out"** gains D2 and D4 in plain words: no fluid fade, so no soft pedal
  and no handbrake that outlasts the foot brake; no separate handbrake shoes; no disc shrinking
  under a parked caliper.
- **"Try it in the game"** gains the hot-handbrake step from phase 1's verify list.
- `glossary.md`: the Handbrake and Brake fade entries say the handbrake fades with its brake.
  `simplifications.md` and `inventory.md`: follow if they list the old rule (grep "fade").
- Real-world statements carry no figure unless a page was opened for it (root `CLAUDE.md`).
- Close: `node tools/check_docs.mjs`; serve the guide (`npx serve docs/guide`) and look at the
  page at desktop and phone width, light and dark.

Please verify (user): read the new section and both figures in the served guide.
