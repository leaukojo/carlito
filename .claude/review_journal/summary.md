# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions at dd4d5cd: 32 in `src kit tools tests`, 22 in `docs` (count with
`grep -rI COMPROMISE <dirs> | wc -l`). Goal: only real ones keep the label.

Past sessions: `sessions/`, each named by its date and item; a deleted one is in git history.

Units 1 to 3a were read before the skill asked for simpler implementations: they come back
through the most-commits rule, or sooner on the user's word. The mechanical sweep ran: the guards
(`check_orphans`, `check_docs`) cover public funcs and citations; duplicate tests with different
bodies are left to each unit's review.

## Queue

- A session takes the top READY line tagged for its model. A line marked "after" or "needs" is
  ready once the line it names is done; with no ready line for its model it stops and says which
  line, on which model, is next. With the Queue empty, the unit map's rule picks (the skill's
  step 1).
- A `diagnose` line: the skill's § Diagnose only. A hand-back goes to the top of the Queue.

- (after units 3 and 4 are reviewed: it touches both) Rigid crank's dead outputs (read
  `2026-11-11-drivetrain-2a.md` finding 2 and `2026-11-12-drivetrain-2b.md` § Deferred with
  `git show 31ec0bf:.claude/review_journal/sessions/<file>`). On a body where
  `Drivetrain.drives_wheels` is false, `process`'s returned axle torque reaches no wheel and
  `drive_wheel_omega` is always 0, so the branch's limiter, `crank_forward` and overrun do
  nothing. Remove them, `WheelDrive.tick`'s `axle_torque` path and the tests that pin them; keep
  the free-rev rpm, `applied_throttle` and the gearbox. Also check the branch's `esc_cap` line
  (untested, maybe dead) and reword the one test comment that describes `crank_forward`.
  [high, plan, Opus]

## Please verify (user, by driving)

- An AWD car (`suv`) on a steep grade: let it roll back, then select P. It stops within a few cm
  and stays (before: it crept on at ~0.1 m/s). `sessions/2026-11-26-pawl-rollback-fix.md`.

Verified: the trucks' roll stability, their retarder, Summer on snow (user, 2026-11-20).

Known, visible: a tractor spawned or respawned in N reads `wheel_slip` up to 98 % for about 0.4 s while it settles
onto its springs (`sessions/2026-11-19-slip-floor.md`); in D or on the handbrake it reads 0.

## Unit map

Sizes are GDScript lines at 716bf06, rounded. A unit's tests and `docs/` pages go with it.

| # | Unit | Paths | Size | Reviewed at | Result |
|---|------|-------|------|-------------|--------|
| 1 | COMPROMISE triage | every `COMPROMISE` in `src/`, `kit/`, `tools/`, `tests/`, `docs/` | 72 mentions | c6686e0 | 18 mentions relabelled (design choices, an estimate, an engine limit, a code debt); 54 real ones stay; 1 fix queued |
| 2a | Drivetrain: the class | `src/vehicles/base/drivetrain.gd` | 1.6k | ab672ce | 4 wrong comments on the rigid crank fixed; no dead symbol; both `COMPROMISE` labels real; 1 fix queued (the rigid branch's dead outputs) |
| 2b | Drivetrain: its tests and doc | `tests/test_drivetrain.gd`, `docs/drivetrain.md` | 2.8k tests + 0.4k doc | 1f85257 | 1 hollow test case and 1 duplicate test removed, 3 wrong test comments and 5 wrong doc figures fixed (heavy vans' inertia, reserve and motoring; the tractor's governed upshift; anti-stall); the doc's measured figures not re-run |
| 2c | Drivetrain: the small files | `differential.gd`, `torque_converter.gd`, `shift_policy.gd`, `pedal_map.gd` in `src/vehicles/base/`; `tests/test_differential.gd`, `test_shift_policy.gd`, `test_torque_converter.gd` | 1.0k + 1.2k tests | dd8dd5e | `start_gear` put on the one engine law (it read the drive without the motoring share; the semis' part-pedal start gear moves); 1 duplicate test and 3 dead fixture lines removed, 3 history-worded test comments fixed; no dead symbol, no wrong comment, the one `COMPROMISE` real |
| 3a | Wheels: the wheel | `src/vehicles/base/wheel.gd` | 1.1k | 8294fee | 6 wrong or misplaced comments fixed, 1 misnamed parameter renamed (`surface_drag_force`'s `mass`); no dead symbol; the 3 `COMPROMISE` labels real; notes for its next read: `sessions/2026-11-15-wheel-leftovers.md` and `sessions/2026-11-16-contact-reading-steps.md`, § For unit 3a's next read |
| 3b | Wheels: the owner | `src/vehicles/base/wheel_drive.gd` | 1.1k | 4dc88e9 | 3 wrong comments fixed, 2 duplicates (ESC clear, dust half track) and 1 dead clamp removed; `LOCK_STUCK_SPIN` is the one pass's tolerance, not a cover; the 3 `COMPROMISE` labels real; the pawl's second steady state diagnosed and fixed (`sessions/2026-11-26-pawl-rollback-fix.md`) |
| 3c | Wheels: the tests | `tests/test_wheel_spin.gd` | 2.8k tests | | |
| 4 | Vehicle base, rest | `src/vehicles/base/` minus units 2, 3, 5; `src/vehicles/tyres/`; `docs/vehicles.md`, `docs/handling.md` | about 4k | | not reviewed; the derivations of `balance_model.gd` and `stability_control.gd` are checked (the swinging axle's lever fixed: `sessions/2026-11-19-swing-axle-lever.md`) and Fable's notes to start from: `sessions/2026-11-15-unit4-derivations.md` § For unit 4's review |
| 5 | Towing | `tow_host`, `towed_body`, `articulation`, `coupling_profile` in `src/vehicles/base/`; `tests/test_trailer.gd`, `test_tow_host.gd`, `test_drawbar_trailer.gd` | 3.2k tests | | not reviewed; findings to start from: `sessions/2026-11-19-towing-one-tick-caps.md` § Unit 5 findings |
| 6 | Truck | `src/vehicles/truck/`, `tests/test_truck.gd`, `docs/truck.md` | 1.0k | | |
| 7 | Tractor | `src/vehicles/tractor/`, `tests/test_tractor.gd`, `docs/tractor.md` | 1.7k | | |
| 8 | Input | `src/input/`, `tests/test_input_arbitration.gd`, `test_key_shaper.gd`, `test_input_map.gd` | 2.1k | | |
| 9 | Bridge and contract | `src/bridge/`, `contract/`, `tests/test_contract.gd`, `tools/gen_js_contract.mjs` | 0.5k + 1.2k tests | | |
| 10 | UI | `src/ui/`, `tests/test_dashboard.gd` | 5.8k | | |
| 11 | Shell | `src/shell/`, `tests/test_boot_params.gd` | 1.9k | | |
| 12 | Challenges | `src/challenges/`, `tests/test_challenge_*.gd` | 1.7k | | |
| 13 | Levels | `src/levels/`, `src/physics/`, `src/water/` | 2.2k | | |
| 14 | Kit runtime | `kit/bake/`, `kit/helpers/`, `kit/terrain/`, `tests/test_bake.gd`, `test_road.gd`, `docs/level_kit.md` | 4.3k | | |
| 15 | Kit editor addon | `addons/carlito_kit/`, `docs/making_a_level.md` | 5.1k | | |
| 16a | Measure tools: `measure_vehicles` host | `measure_vehicles.gd`'s args, queue, spawn, accel / launch trace and gates, tracking, coast, braking, report and doc tables; `docs/vehicle_measurements.md` | 2.8k + 0.7k doc | | split from 16 at a8303eb; the rule and the pass contract: `sessions/2026-11-26-measure-split.md` |
| 16b | Measure tools: lateral and cruise | `measure_vehicles.gd`'s cornering, step, sine, ESC reference, circle, cruise probes; `tests/test_measure_sine.gd`, `test_measure_settle.gd` | 1.8k + 0.2k tests | | |
| 16c | Measure tools: tractor passes | `measure_vehicles_{hitch,plough,arm}.gd` | 0.9k | | moved out of the host (ca04892), not yet reviewed |
| 16d | Measure tools: shared and the moved passes | `measure_vehicles_{kerb,side,scrape,parked}.gd` (parked: stall, freerev, rest, handbrake, moved at 6feded8), `measure_rig.gd`, `tc_pedal.gd`, `doc_region.gd`; `tests/test_measure_chatter.gd`, `test_measure_ground.gd` | 1.9k + 0.2k tests | | |
| 16e | Measure tools: grade | `measure_grade.gd`, `tests/test_measure_descent.gd` | 2.3k + 0.1k tests | | |
| 16f | Measure tools: the rest | `measure_rough.gd`, `measure_semi_launch.gd`, `measure_air_loss.gd` | 1.9k | | |
| 17 | Generators | `tools/gen_*`, `tests/test_kit_gen.gd`, `test_kenney_variants.gd`, `test_vehicle_catalog.gd` | over 6k | | |
| 18 | Build and CI tools | rest of `tools/`, `tools/git-hooks/`, `.github/`, `docs/deploying.md`, `docs/machine_setup.md` | | | |
| 19 | Unowned tests | tests no other unit lists, `tests/fixtures/`, `*_fixtures.gd` | | | |
| 20 | System docs | `docs/overview.md`, `systems.md`, `sources.md`, `TODO.md`, `HUMAN_EXPLANATIONS.md`, `README.md` | 1.3k | | |
| 21 | Player guide | `docs/guide/` | | | |
| 22 | Agent instructions | every `CLAUDE.md`, `.claude/skills/` | | | |
| 23 | BETA: boat | `src/vehicles/boat/`, `watercraft/`, `tests/test_boat*.gd`, `docs/boat.md` | 0.6k | | |
| 24 | BETA: drone | `src/vehicles/drone/`, `tests/test_drone*.gd`, `tools/measure_drone.gd` | 2.3k | | |
| 25 | BETA: plane | `src/vehicles/plane/`, `docs/flight.md` | 0.3k | | |
| 26 | BETA: train | `src/vehicles/train/`, `docs/rail.md` | 0.5k | | |
