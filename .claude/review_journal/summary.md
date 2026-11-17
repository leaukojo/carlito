# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions at 3c9c2fb: 33 in `src kit tools tests`, 22 in `docs` (count with
`grep -rI COMPROMISE <dirs> | wc -l`). Goal: only real ones keep the label.

Past sessions: `sessions/`, each named by its date and item. A file compressed on 2026-11-16
names the commit that holds its full text.

Units 1 to 3a were read before the skill asked for simpler implementations: they come back
through the most-commits rule, or sooner on the user's word. The mechanical sweep ran: the guards
(`check_orphans`, `check_docs`) cover public funcs and citations; duplicate tests with different
bodies are left to each unit's review.

## Queue

Three stages, in this order (user, 2026-11-16): **A**, what lands before the user's plans; **the
pause**, where the review stops and the plans run; **B**, what waits until they are done.

- A session takes the top READY line tagged for its model in stage A. A line marked "after" or
  "needs" is ready once the line it names is done. With no ready line for its model it stops and
  says which line, on which model, is next: it never reaches below the pause for work, and reads
  no unit in its place.
- Stage B and the unit map open when the pause is over.
- Fable is not used (user, 2026-11-16): every line is Opus's or Sonnet's. A `diagnose` line is
  Opus's and fixes nothing; what earns the tag, "prepared first" and the hand-back: the skill's
  § Diagnose only. A hand-back goes to the top of the stage it came from.
- A new item goes to stage B unless it moves a figure the plans tune against or edits lines a
  kept patch touches.

### Stage A: before the plans

The rolling moment (A2, A3) holds `handbrake_fade.md`; A2 to A7 hold `realism_gaps.md`. A1 (the
gather) and the hand-back's diagnosis are done: `sessions/2026-11-16-gather-rolling-moment.md`,
`sessions/2026-11-16-rolling-moment-diagnosis.md`; A2's gather and diagnosis:
`sessions/2026-11-16-standing-alternation.md`, `sessions/2026-11-16-contact-reading-steps.md`;
A2's fix, done 2026-11-16: `sessions/2026-11-16-contact-fix.md`; A3, the rolling moment landed as
a stage before the TC hold, done 2026-11-16: `sessions/2026-11-16-rolling-moment-stage.md`.

A4, the three accelerations raw, done 2026-11-16 (b76f263): `sessions/2026-11-16-accel-raw.md`.
A4b, the trailers' lift tables on the raw sensor, done 2026-11-16 (65cfd41):
`sessions/2026-11-16-trailer-lift-tables.md`.

A5, `CORNER_SMOOTH_S`, done 2026-11-16 (1b4c144): `sessions/2026-11-16-corner-smooth.md`. The lag
stays (`sedan` 0.023 g apart: a real yaw swing, not a tick alternation) and carries its reason now.
A6, `brake_settled_spin` relabelled a design choice, done 2026-11-16 (3c9c2fb):
`sessions/2026-11-16-brake-settled-spin.md`.

A8, the gather for A9, done 2026-11-16: `sessions/2026-11-16-race-strip-gather.md` (both leave, with
and without `--fixed-fps 60`; the speed across grows smoothly from about 1e-5 m/s, no step).
A7, the standing rig's rest gates, done 2026-11-16 (a16a944): `sessions/2026-11-16-rest-gates.md`.
`REST_FLIPS_S` 3 /s, `REST_STEP_KG` 1 kg (held above the towing item's (c); tighten to about 0.1 kg
when (c) lands).
A9, the race bodies' yaw divergence diagnosed, done 2026-11-17: `sessions/2026-11-17-race-yaw-mode.md`
(the side force 0.60 m ahead of the COM, and the rear tyre's stiffness flat at its peak load under
downforce; brief and lever table there).

Stage A is done.

### The pause: the user's plans

The review stops here. A session that finds stage A done for its model takes no review item: its
report names the next plan phase with the effort, mode and model the plan file gives it, and
ends. A plan runs from its own file (never as `/review-continue`), its `State:` line is its
record, and it changes only with the user's OK. The pause is over when both plans read
`Status: done` or the user says so; this section then goes.

1. `docs/plans/handbrake_fade.md` (2 phases, Opus, medium): from A3 landed or dropped. Its
   phase 1 edits `WheelDrive.tick`'s brake loop and `towed_body.gd:173-190`, lines the kept patch
   sits on (`towed_body.gd:193`); its cited lines predate the wheel fix: re-read them.
2. `docs/plans/realism_gaps.md` (5 phases): from A2 to A7 done, so its targets are judged on
   `doc=` tables that no review item is about to move. Phase 1's "investigate" is a ledger of
   power from the fuel to the wheels at 70 km/h, on Opus; phase 4's
   `race` bullet works from A9's brief (`sessions/2026-11-17-race-yaw-mode.md` § Brief: lever (a),
   ends in a proposal). `doc=grade`'s `suv` cell is under
   diagnosis (stage B's first line): phases 2 and 4 do not tune against it.

### Stage B: after the plans

- The `suv`'s asphalt climb fell 79.0 -> 71.3 % with the wheel fix (`doc=grade`, 7a7cd9f; every
  other body within a bisect step or up). Its bisect is not monotonic after the fix
  (`measure_grade -- suv verbose`: 35.16 deg climbs, 35.86 fails sliding back at 10.5 m/s with
  `sum f_long` 3940 N, 36.56 fails standing; `sessions/2026-11-15-wheel-fix-landed.md` § The
  `suv`'s climb, with the run to make). A cause and a brief; fix nothing; a fix ends in a
  proposal. [high, auto, Opus]
- (after `realism_gaps.md` phase 4) The rear tyre's cornering-stiffness peak load ignores
  `rear_lat_grip`: every corner's `reference_load` is `mass / 4 * g` and `cornering_peak_load`
  one figure, so a wider rear (1.15 on the race bodies) saturates in stiffness at the front's load
  (`sessions/2026-11-17-race-yaw-mode.md` § Cause 2, lever (b)). Source whether a tyre's
  peak-stiffness load scales with its width; if so, a `wheel.gd` model change on every body with
  `rear_lat_grip` != 1, `doc=cornering` and the skid pad re-run. Ends in a proposal.
  [high, plan, Opus]
- One-tick caps that do not see the coupling's other force (`tow_host.gd`, `towed_body.gd`,
  `articulation.gd` read whole: unit 5's findings go in the session file; (c)'s logging run
  first).
  (a) A standing rig's steady 0.04 to 0.2 mm/s drift (`sessions/2026-11-13-f1-rest-guard.md`):
  read it again once A3 has landed; still there, it is (c)'s. The laden roll-back that was (a) is
  explained and fixed by A3.
  (b) `Articulation.YAW_CAP_SHARE` (cover sweep 6; `articulation.gd:9-12`, `yaw_friction_torque`,
  `tow_host.gd:369-376`): half of the one-tick stop, a guess, because the towed tyres' lateral
  caps stop the same relative yaw in the same tick. With the share at 1.0 read
  `test_a_coupled_rig_standing_still_stays_mirror_symmetric`'s peak rate per kind; at 0.5 log the
  relative yaw rate per tick after a yaw kick on a standing `semi` + `box`, and on a slow
  full-lock turn how often the cap binds under the declared `friction_nm`.
  (c) (when it lands, tighten `REST_STEP_KG`) The laden `semi`'s `axle_load` steps 0.6 to 0.95 kg a tick standing in D with no speed sign
  change (`measure_vehicles -- semi 20 rest`, "springs: rear axle"), with or without the wheel's
  ring: not the wheel's. Log per tick what alternates on the tractor unit's rear axle with the
  box coupled and not bobtail (the coupling's force on the kingpin, the yaw cap of (b), the rear
  wheels' `suspension_force`).
  Write the cause and one brief per case (in which order `TowHost` and the towed wheels tick, and
  what each one-tick stop knows of the other); fix nothing. The fixes change a force: each line
  ends in a proposal. Where the logs do not explain a case, queue a `diagnose` line for that case
  with them. [high, auto, Opus]
- A swinging front axle's roll takes the weight on the wrong lever
  (`sessions/2026-11-15-unit4-derivations.md` finding 1: the derivation, the forms, the figures;
  read first). `BalanceModel._roll_state` (`balance_model.gd:146-194`): inside the stop the body
  rolls about the line from the rear's ground centre to the pivot; the side force is taken on that
  lever (`moment - pivot_m`) and the rolled body's weight on the full `h` (`- weight_h`). The
  tractors' predicted roll reads 2.7 % high, their front transfer 4 % low, the rear's first lift
  0.635 g for 0.652. The forms to write, the tests that change, the runs and the stop condition:
  the same file, § Finding 1's brief. Prediction only (two rows of `doc=cornering` may move): no
  proposal. [high, auto, Opus]
- `tractor-kenney`'s raw `acc_lat` reads 10.5 g on one tick as the body tips on `corner` (t=6.700,
  8.5 g the tick before, 3.2 m/s, slip 0.45 inside the gate); the pass's "path 1.77 g at most" is
  that spike under `CORNER_SMOOTH_S` (`sessions/2026-11-16-corner-smooth.md`). Trace what
  produces it (a contact impact as the tractor tips, or a velocity step in
  `base_vehicle.gd:280`'s `accel`), say whether it is real; a brief, no filter on the signal or
  the display. A fix that changes the signal ends in a proposal. [high, auto, Opus]
- The cover sweep's other findings, one session each. What each cover is, and its proving run
  (take the cover out, measure, undo): `sessions/2026-11-14-cover-sweep.md` § Covers and
  § Proving runs, numbered as here. Never a new filter, on a reading or a signal.
  - (3) done: A5, above.
  - (1) `VehicleMath.RESIST_EPS` (`vehicle_math.gd:138`, `:200`): "stops jitter" with nothing
    named; probably dead. [high, auto, Opus]
  - (2) `measure_vehicles._sample_gates`' two-tick means (`:1812-1833`): their source went with
    the wheel fix. [medium, auto, Sonnet]
  - (4) `MeasureRig.ESC_CHATTER_EPS` (`tools/measure_rig.gd:272`): trace which ESC input alternates on `van`'s held touch; a brief, no fix.
    [high, auto, Opus]
  - (5) `TractorTelemetry.SLIP_FLOOR_KMH` (`tractor_telemetry.gd:21`; after A3, which moves
    `wheel_slip`): a contract signal snapped to 0. Ends in a proposal. [high, auto, Opus]
  - (6) `Articulation.YAW_CAP_SHARE`: the towing item's (b), above.
- `scrape onebody`'s `firetruck` FR peaks at 501 N across where the two-body run reads 217 N, the
  same wall at +0 mm, 100 % contact (`sessions/2026-11-14-deck-start-test.md` § Measured). f7bac55
  left it byte-equal, so the skipped body is not its cause. Trace which contact the sweep by contact
  reads on the grazing ticks with the wall a shape of the strip's body against a body of its own,
  and why that doubles the force across; write the cause and the brief, fix nothing. [high, auto,
  Opus]
- The engine law's three inversions (`sessions/2026-11-12-shared-law-audit.md`, finding 9;
  `realism_gaps.md` phase 1 works in the same functions: after it). `Drivetrain.fuel_to_land`,
  `Drivetrain.drag_fuel` and `PedalMap._row_fuel` each compute `(net - motoring) / span`; one
  "fuel for a net crank torque" function serves all three. They differ where `span <= 0`
  (`drag_fuel` gives 0, the others 1 above the motoring law): pick one answer, show no shipped
  curve reaches it, keep the results the same to the bit elsewhere (`test_drivetrain`,
  `test_telemetry`'s idle case). [high, auto, Opus]
- `docs/vehicles.md` § Contact's "Cost, `semi` + `box`: the cast costs an order of magnitude over
  the ray, natively and on web" cites a `kerb` cost readout no tool prints
  (`sessions/2026-11-14-deck-start-test.md` finding 2). Find where the figure came from
  (`git log -S "order of magnitude" -- docs/vehicles.md`); with a run behind it, cite that run;
  with none, cut the claim (the docs are at their character cap, so cutting helps). A native
  figure for the cast alone is in the session file. [medium, auto, Sonnet]
- (after units 3 and 4 are reviewed: it touches both) Rigid crank's dead outputs (read
  `2026-11-11-drivetrain-2a.md` finding 2 and `2026-11-12-drivetrain-2b.md` § Deferred with
  `git show 31ec0bf:.claude/review_journal/sessions/<file>`). On a body where
  `Drivetrain.drives_wheels` is false, `process`'s returned axle torque reaches no wheel and
  `drive_wheel_omega` is always 0, so the branch's limiter, `crank_forward` and overrun do
  nothing. Remove them, `WheelDrive.tick`'s `axle_torque` path and the tests that pin them; keep
  the free-rev rpm, `applied_throttle` and the gearbox. Also check the branch's `esc_cap` line
  (untested, maybe dead) and reword the one test comment that describes `crank_forward`.
  [high, plan, Opus]

### To consider (user, 2026-11-14: not now; no session picks these)

- The measure tool's 80 m kerb and 6 km strip are past Jolt's switch to sharp shapes: 1 to 3 mm
  of contact noise in kerb-run figures that level geometry does not have. Options and what moves:
  `sessions/2026-11-14-sweep-rest-disagree.md` § To consider. Decide with the user first, and
  re-measure after A2's fix: part of that noise is A2's (a), whole stops under a leaned wheel.
  [high, plan, Opus]
- A kept contact probe behind a `measure_vehicles` flag (same section). A tool feature: propose
  it (`proposals.md`) before building. [high, plan, Opus]
- `tools/measure_vehicles.gd` is 6256 lines in one file, and `tools/CLAUDE.md` ("a new
  measurement is a scenario in an existing tool") keeps it growing. Unit 16's review splits the
  unit in the map first; it then says whether passes move to files of their own (`kerb`, `scrape`,
  `side` are self-contained: `_start_kerb` to `_report_kerb_run`) and whether the rule changes. No
  split before that review. [high, plan, Opus]

## Please verify (user, by driving)

The rolling moment (A3, 2026-11-16):
- A full stop from 100 km/h is about 1 % longer (`sedan` 40.6 -> 41.0 m).
- A tractor cruising in a field with no implement reads `wheel_slip` near 1 % (was near 3 %).
- A laden `semi` crawling up a steep grade stops sooner when the pedal is lifted; on 25 % with
  the hold it pulls away later (9.5 s, was 4.3).
- A `sedan` in D with no pedal slides back on a 6 to 7 % grade (it held about 7 % before; the
  creep table now reads 5.7 %).

The raw accelerations (A4, 2026-11-16):
- `accLat` and `accLong` on FULL show shift and kerb jolts at full size.
- `car_corner_budget` ("Perfect turns"): a kerb or shift jolt near 4.0 m/s² can fail the run a
  tick sooner. Is the limit still fair?

The trailers' lift tables (A4b, 2026-11-16):
- A laden box rig's trailer roll-over control brakes from a slightly lower g (0.342, was 0.355):
  on a hard step at speed it brakes for longer (6.2 s, was 3.4 s), with no trailer over.

Known and queued, not a verify item: a laden `semi`'s AXLE number still moves by 1 kg (3 at most)
on some ticks (stage B, the towing item's (c)).

## Unit map

Sizes are GDScript lines at 716bf06, rounded. A unit's tests and `docs/` pages go with it.

| # | Unit | Paths | Size | Reviewed at | Result |
|---|------|-------|------|-------------|--------|
| 1 | COMPROMISE triage | every `COMPROMISE` in `src/`, `kit/`, `tools/`, `tests/`, `docs/` | 72 mentions | c6686e0 | 18 mentions relabelled (design choices, an estimate, an engine limit, a code debt); 54 real ones stay; 1 fix queued |
| 2a | Drivetrain: the class | `src/vehicles/base/drivetrain.gd` | 1.6k | ab672ce | 4 wrong comments on the rigid crank fixed; no dead symbol; both `COMPROMISE` labels real; 1 fix queued (the rigid branch's dead outputs) |
| 2b | Drivetrain: its tests and doc | `tests/test_drivetrain.gd`, `docs/drivetrain.md` | 2.8k tests + 0.4k doc | 1f85257 | 1 hollow test case and 1 duplicate test removed, 3 wrong test comments and 5 wrong doc figures fixed (heavy vans' inertia, reserve and motoring; the tractor's governed upshift; anti-stall); the doc's measured figures not re-run |
| 2c | Drivetrain: the small files | `differential.gd`, `torque_converter.gd`, `shift_policy.gd`, `pedal_map.gd` in `src/vehicles/base/`; `tests/test_differential.gd`, `test_shift_policy.gd`, `test_torque_converter.gd` | 1.0k + 1.2k tests | dd8dd5e | `start_gear` put on the one engine law (it read the drive without the motoring share; the semis' part-pedal start gear moves); 1 duplicate test and 3 dead fixture lines removed, 3 history-worded test comments fixed; no dead symbol, no wrong comment, the one `COMPROMISE` real |
| 3a | Wheels: the wheel | `src/vehicles/base/wheel.gd` | 1.1k | 8294fee | 6 wrong or misplaced comments fixed, 1 misnamed parameter renamed (`surface_drag_force`'s `mass`); no dead symbol; the 3 `COMPROMISE` labels real; notes for its next read: `sessions/2026-11-15-wheel-leftovers.md` and `sessions/2026-11-16-contact-reading-steps.md`, § For unit 3a's next read |
| 3b | Wheels: the owner | `src/vehicles/base/wheel_drive.gd` | 1.1k | | not reviewed; Fable's findings to start from: `sessions/2026-11-15-wheel-fix-landed.md` § Unit 3b |
| 3c | Wheels: the tests | `tests/test_wheel_spin.gd` | 2.8k tests | | |
| 4 | Vehicle base, rest | `src/vehicles/base/` minus units 2, 3, 5; `src/vehicles/tyres/`; `docs/vehicles.md`, `docs/handling.md` | about 4k | | not reviewed; the derivations of `balance_model.gd` and `stability_control.gd` are checked (1 fix queued, the swinging axle's lever) and Fable's notes to start from: `sessions/2026-11-15-unit4-derivations.md` § For unit 4's review |
| 5 | Towing | `tow_host`, `towed_body`, `articulation`, `coupling_profile` in `src/vehicles/base/`; `tests/test_trailer.gd`, `test_tow_host.gd`, `test_drawbar_trailer.gd` | 3.2k tests | | |
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
| 16 | Measure tools | `tools/measure_*.gd`, `tests/test_measure_*.gd`, `docs/vehicle_measurements.md` | over 9k | | |
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
