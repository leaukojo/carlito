# Plan — Train: the reverser, the brake pipe and wheel–rail adhesion

The train's motion disagrees with what it publishes in three places. The bridge's N still pulls at
full tractive effort, the brake acts on the pedal while the published `brake_pipe` lags behind it,
and the tractive effort has no adhesion limit (320 kN on a 50 t head is μ 0.65). This plan makes
the motion follow the reverser, the pipe and the rail. Findings: `reviews/A_vehicle_physics.md`
#1, #3, #4.

Written 2026-11-05. Status: **not started.**
Serves: the bridge lesson that N means no drive (`gear`, `ST_NEUTRAL`), and `brake_pipe` as a
signal read out of the brake that stops the train (rule 3).
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — Sources and decisions (effort: medium; mode: plan-mode-first)

Read only; the output is a short report and the user's answers.
- Open a source for dry-rail adhesion (μ) and for an EMU's starting tractive effort and
  acceleration; cite the pages opened (`docs/sources.md`). The 320 kN / 14 m/s corner in
  `train_sim.gd` has no source today.
- Decisions, each with a recommendation:
  1. Adhesion: cap the head's force at `mu_adh × m_loco × g`, or spread the tractive effort over
     motored cars as an EMU does. Recommended: the cap. It is one line, and the consist keeps one
     powered car.
  2. Full service vs the 2.5 bar warn: keep a full service application above 2.5 bar, or reword
     the contract's warn as "full service". Recommended: keep full service above the warn, so the
     warn keeps meaning emergency.
- A wheelslip signal on the bus is a new feature and stays out of this plan.

Done when the user has answered the decisions.

## Phase 1 — The reverser gates traction (effort: medium; mode: accept-edits)

- `train.gd:103-124`: the traction reads `absf(throttle) × Drivetrain.drive_sign(gear_byte)`, and
  `motor_current` uses the same force.
- The local path is unchanged: it never asks for N with the pedal down.
- Test: a bridge `gear` N with `accel` > 0 gives zero tractive effort, and D and R pull in their
  own direction.
- Done when the test is green and the user has driven N / D / R from sloppyCAN.

## Phase 2 — The brake acts through the pipe (effort: high; mode: plan-mode-first)

- `TrainSim.step`'s brake demand reads the pipe:
  `(BRAKE_PIPE_CHARGED - pipe) / PIPE_APPLY_RANGE`. Today it reads `input.brake` directly.
- `PIPE_APPLY_RANGE` follows decision 2. A contract text change goes through the
  `contract-edit` skill.
- Tests: the pure pipe → demand law, plus apply and release lag against the pipe rates.
- Done when the user has felt the lag on a stop and a release.

## Phase 3 — The adhesion limit (effort: high; mode: plan-mode-first)

- The cap from decision 1, with its sourced μ and the re-sourced tractive corner
  (`docs/rail.md`, `docs/sources.md`).
- Measure the consist's starting acceleration headless, in the background (`--fixed-fps 60`),
  and record it in `docs/rail.md`.
- Done when the figure matches the source's range and the user has driven a start.
