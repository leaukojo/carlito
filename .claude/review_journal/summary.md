# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions at c903d45: 34 in `src kit tools tests`, 22 in `docs` (count with
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
- Fable (user, 2026-11-14: its credits are scarce and may not last the review) takes only lines
  tagged `diagnose ... Fable`; what earns the tag, "prepared first" and the hand-back: the skill's
  § Diagnose only. A hand-back goes to the top of the stage it came from.
- A new item goes to stage B unless it moves a figure the plans tune against or edits lines a
  kept patch touches.

### Stage A: before the plans

The rolling moment (A2, A3) holds `handbrake_fade.md`; A2 to A7 hold `realism_gaps.md`. A1 (the
gather) and the hand-back's diagnosis are done: `sessions/2026-11-16-gather-rolling-moment.md`,
`sessions/2026-11-16-rolling-moment-diagnosis.md`.

- **A2** (ready) Standing bodies alternate with the rolling moment's patch on
  (`sessions/2026-11-16-rolling-moment-diagnosis.md` § 4, read first: the bobtail's `rest
  reading:` 0.11 -> 0.34 kg, a 3-tick cycle of ±90 N in the front suspension of a `semi` parked
  across 10 %, what the two share, the hypothesis). In detached worktrees outside the repo
  (`.godot/` copied), HEAD and HEAD with `git apply sessions/2026-11-15-rolling-moment.patch`,
  with the gather's probe (its file's appendix; it adds `park_cell=`) and, per wheel, the terms it
  lacked: `compression`, its difference a tick, the spring, damper, bar and link terms of
  `suspension_force`, `_stick.x`, `_patch_spring.x`, `long_cap`, and `a`, the slip force's slope
  over `m_cap / delta`. Runs, `--fixed-fps 60`: `measure_semi_launch -- semi steady strict
  trailer=bobtail`, ticks 430 to 450; `measure_grade -- doc=park park_cell=semi:cross:5.7`, ticks
  760 to 790. Name the term that steps first in each, and say whether the wheels that alternate
  are those with the lowest `a`. Then the test, on the patch only: in `_slip_force` a wheel with
  `omega == 0.0` takes along the wheel `clampf(m_cap * slip_vel / delta, -budget, budget)` where
  it takes the curve; re-read the bobtail's `rest reading:` and the cross cell's front-left
  `suspension_force`. Both back at HEAD's: write that law into A3's brief (what a standing
  wheel's force along the wheel is and why, its tests, `semi 20 rest`, laden `steady strict` and
  `tractor-kenney 20 rest` re-read, `sedan creep`'s slide unchanged by it). Not back: undo, the
  session file gives the first term to step, and the case goes to Fable with it. Never a filter,
  a lag or a deadband; nothing is fixed at HEAD. [high, auto, Opus]
- **A3** (approved, user 2026-11-15: variant A, the ground's share a moment too; handed back
  2026-11-15; after A2 and the user's answer on the creep, `proposals.md`) The rolling resistance
  is a moment on the wheel, a stage of the settle law before the TC hold. Why, what goes and what
  moves: `sessions/2026-11-15-wheel-leftovers.md` finding 1 (read first). The change as built, its
  tests and its figures: `sessions/2026-11-15-rolling-moment.md` and `.patch` (`git apply`;
  re-read `wheel.gd` if it fails). Do: the patch, then
  `sessions/2026-11-16-rolling-moment-diagnosis.md` § Brief (the stage, `Differential`'s kinks,
  `roll_share` gone, the three tests that fail on the patch), then A2's law where it proved. The
  moment is never part of `hold_torque`. Runs, HEAD
  then after, `--fixed-fps 60`: `test_wheel_spin`, the suite; `doc=park`; `all creep`; `sedan
  rollback [nohold]`, `semi rollback [nohold]`; `sedan 45 brake`; `measure_semi_launch` `steady
  strict` bobtail and laden; `measure_vehicles -- semi 20 rest` and `tractor-kenney 20 rest`;
  `wheel_slip` on FIELD at no draft on `tractor-kenney` (the session file's probe); `all 45 track
  strict`; then the `doc=` tables. Measured on the patch: `sedan` 100 % stop 40.7 -> 41.1 m, FIELD
  `wheel_slip` 2.9 -> 1.0 %. Expected after the stage, and no stop: laden `semi` 25 % `nohold` back
  at HEAD's 887 mm (1578 on the patch as built), the same cell with the hold never forward (it
  sits 18 N under its limit at HEAD), the creep table as the user's answer says. Stop and hand
  back, the change undone, if a standing body's `rest reading:` rises over HEAD's, any held
  wheel's `suspension_force` alternates over 2 N a tick in `doc=park`'s `semi` 10 % cross cell
  after its first 15 s (HEAD: under 1 N), a
  `doc=park` held cell moves over 1 mm along (or across with the cell run alone in both trees:
  the `semi`'s across figure moves about 1 mm with what ran before it), an undriven wheel reads
  `omega == 0` on a rolling body, or cruise and top speed move by more than a digit. The plan
  shows the user the measured moves (stops, roll-backs, creep, `wheel_slip` on FIELD) before the
  commit; "Please verify" gains: full stops about 1 % longer, a tractor's `wheel_slip` in a field
  at no draft near 1 %, a laden `semi` crawling up a steep grade stops sooner when the pedal is
  lifted, the creep as decided. The `COMPROMISE` count stays (one goes, the soil's share comes).
  [high, plan, Opus]
- **A4** (approved, user 2026-11-14: raw; ready, it touches no line of the kept patch)
  `accLong` / `accLat` / `acc_vert` leave the sim unfiltered: `BaseVehicle.ACCEL_SMOOTH` goes,
  `TowedBody._sense_lateral` takes `raw` too, the contract's `acc_vert` `desc` and the guide
  follow. Evidence, the edits by site, the runs, the stop condition (the trailer's roll-over
  control chatters: no filter is added back) and the "Please verify" line:
  `sessions/2026-11-14-accel-smooth-proof.md` § The brief. [medium, plan, Opus]
- **A5** (after A4, which re-runs `doc=cornering`; after A3 too, or re-apply its patch with
  `git apply -3`: both edit `measure_vehicles.gd`) Cover sweep (3),
  `measure_vehicles.CORNER_SMOOTH_S` (`:64`; `:2475`, `:2493`, `:2502`): a 0.25 s lag before the
  cornering peak is taken, no reason given, and `acc_lat` smoothed a second time. Print raw
  beside smoothed on four bodies; within 0.02 g the lag goes and `doc=cornering` is re-run. The
  proving run: `sessions/2026-11-14-cover-sweep.md` § Proving runs (3). [high, auto, Sonnet]
- **A6** (after A3: `wheel.gd` is the patch's file) `brake_settled_spin`'s `COMPROMISE` is a
  design choice (`wheel.gd:141-146`; `sessions/2026-11-15-wheel-leftovers.md` finding 2). Relabel,
  no code: the settled spin is the angle the wheel turns in the tick, so the brake's heat on it is
  the step's own work, and with the tyres' slip read on the same spin the ledger closes to second
  order; the mean over the settle counts the spin the road lent the step (5 % of an ABS stop).
  Keep, as its known edge: a wheel the brake stops off the ground inside one tick heats nothing.
  Run `measure_grade -- sedan stops` once and quote the energy check's residual in the session
  file; `check_docs`; the `COMPROMISE` count drops by 1. [low, auto, Sonnet]
- **A7** (after A3) The standing rig's rest gates. `measure_semi_launch`'s `rest reading:` judges
  sign changes against 20 /s (`REST_FLIPS_S`) and the axle step against 2 kg (`REST_STEP_KG`);
  since the wheel fix a bobtail reads 0.7 /s and 0.11 kg, a laden rig 0.0 /s and 0.95 kg. What
  each limit was sized on and its margin: `sessions/2026-11-13-f1-rest-guard.md`. Size new ones on
  the figures A3 leaves, with the margin the old ones had; keep the laden step's limit above the
  towing item's (c) until that lands; the constants' comment (`measure_semi_launch.gd:75-79`)
  names § One-tick caps' `taken` paragraph, which A3 removes; `test_measure_*` and
  `docs/vehicles.md` § One-tick caps follow. [medium, auto, Sonnet]
- **A8** (gather for A9; ready; holds only `realism_gaps.md` phase 4's first bullet) Reproduce
  `race` and `race-future` leaving the strip (`measure_vehicles -- race,race-future 60`, the
  top-speed pass; `--fixed-fps 60` and without, and say whether both leave). With an uncommitted
  probe in the tool, reverted, log per tick from 240 km/h until the body leaves: speed, heading,
  yaw rate, the centre of mass's speed across, each wheel's `force_lat`, side slip and
  `suspension_force`, the aero side force and the downforce; and once: the yaw inertia off the
  solver, `aero_centre`, `downforce_front`, `rear_lat_grip`, the wheelbase and the centre of mass.
  Name the first tick the speed across passes 1 mm/s and what moved on it. A session file with
  the tables; no cause guessed, no tune. [medium, auto, Sonnet]
- **A9** (needs A8; holds only phase 4's first bullet, which an Opus session takes over from
  A8's file if Fable is out) `race` and `race-future` leave the 40 m strip sideways near
  280-290 km/h with zero steer (`doc=top` prints `left the strip`). From the gathered trace and
  the spec's figures, derive the yaw mode at that speed (each axle's cornering stiffness at its
  load with the downforce on, the aero centre, the yaw inertia), what seeds it and what makes it
  grow. The brief feeds the plan's phase 4: no tune before the cause. [diagnose, high, Fable]

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
   power from the fuel to the wheels at 70 km/h, on Opus (Fable only on a hand-back); phase 4's
   `race` bullet waits on A9, its other bullets do not. `doc=grade`'s `suv` cell is under
   diagnosis (stage B's first line): phases 2 and 4 do not tune against it.

`docs/plans/dashboard_size_toggle.md` waits on the user's drive and is not the review's.

### Stage B: after the plans

- The `suv`'s asphalt climb fell 79.0 -> 71.3 % with the wheel fix (`doc=grade`, 7a7cd9f; every
  other body within a bisect step or up). Its bisect is not monotonic after the fix
  (`measure_grade -- suv verbose`: 35.16 deg climbs, 35.86 fails sliding back at 10.5 m/s with
  `sum f_long` 3940 N, 36.56 fails standing; `sessions/2026-11-15-wheel-fix-landed.md` § The
  `suv`'s climb, with the run to make). A cause and a brief; fix nothing; a fix ends in a
  proposal. [high, auto, Opus]
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
  (c) The laden `semi`'s `axle_load` steps 0.6 to 0.95 kg a tick standing in D with no speed sign
  change (`measure_vehicles -- semi 20 rest`, "springs: rear axle"), with or without the wheel's
  ring: not the wheel's. Log per tick what alternates on the tractor unit's rear axle with the
  box coupled and not bobtail (the coupling's force on the kingpin, the yaw cap of (b), the rear
  wheels' `suspension_force`).
  Write the cause and one brief per case (in which order `TowHost` and the towed wheels tick, and
  what each one-tick stop knows of the other); fix nothing. The fixes change a force: each line
  ends in a proposal. Where the logs do not explain a case, hand that case back to Fable with
  them. [high, auto, Opus]
- A swinging front axle's roll takes the weight on the wrong lever
  (`sessions/2026-11-15-unit4-derivations.md` finding 1: the derivation, the forms, the figures;
  read first). `BalanceModel._roll_state` (`balance_model.gd:146-194`): inside the stop the body
  rolls about the line from the rear's ground centre to the pivot; the side force is taken on that
  lever (`moment - pivot_m`) and the rolled body's weight on the full `h` (`- weight_h`). The
  tractors' predicted roll reads 2.7 % high, their front transfer 4 % low, the rear's first lift
  0.635 g for 0.652. The forms to write, the tests that change, the runs and the stop condition:
  the same file, § Finding 1's brief. Prediction only (two rows of `doc=cornering` may move): no
  proposal. [high, auto, Opus]
- The cover sweep's other findings, one session each. What each cover is, and its proving run
  (take the cover out, measure, undo): `sessions/2026-11-14-cover-sweep.md` § Covers and
  § Proving runs, numbered as here. Never a new filter, on a reading or a signal.
  - (1) `VehicleMath.RESIST_EPS` (`vehicle_math.gd:138`, `:200`): "stops jitter" with nothing
    named; probably dead. [high, auto, Opus]
  - (2) `measure_vehicles._sample_gates`' two-tick means (`:1812-1833`): their source went with
    the wheel fix. [medium, auto, Sonnet]
  - (4) `MeasureRig.ESC_CHATTER_EPS` (`tools/measure_rig.gd:272`; after A4, which changes the
    `acc_lat` input): trace which ESC input alternates on `van`'s held touch; a brief, no fix.
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
  `sessions/2026-11-14-sweep-rest-disagree.md` § To consider. Decide with the user first.
  [high, plan, Opus]
- A kept contact probe behind a `measure_vehicles` flag (same section). A tool feature: propose
  it (`proposals.md`) before building. [high, plan, Opus]
- `tools/measure_vehicles.gd` is 6256 lines in one file, and `tools/CLAUDE.md` ("a new
  measurement is a scenario in an existing tool") keeps it growing. Unit 16's review splits the
  unit in the map first; it then says whether passes move to files of their own (`kerb`, `scrape`,
  `side` are self-contained: `_start_kerb` to `_report_kerb_run`) and whether the rule changes. No
  split before that review. [high, plan, Opus]

## Please verify (user, by driving)

- F2, along a wall: slide a car (`race`, a tractor, the `firetruck`) along a building or barrier
  at a shallow angle, then steer into it. Expected: it scrapes on its hull with no kick off the
  wall; steered hard into the wall it grinds to a stop nose-in where it used to bounce along.
- F2's remainder, a wall that is part of the ground: on Level 3 - City, `race` or a tractor along
  a road barrier, straight and then steered into it; on any island level, the same along the foot
  of a cliff. Expected: it scrapes on its hull and the wall-side corner stays up, where it used to
  drop, and the wall-side wheels ride at the road's height, not a few cm low (f7bac55).
- A `semi` over a high step at speed (f7bac55): about 30 km/h over a 20 cm kerb or step.
  Expected: the rear wheels meet it at full bump and the jolt is softer than before (the `kerb`
  run's peak vertical 4.77 -> 2.89 g); crawling over it is as before.

- The FULL dashboard's bars with no lag: any body, F2 to FULL. Expected: every bar and its number
  follow the value at once. Any number that flickers on a body standing still is a new finding:
  say which.
- F1, a standing body: a parked `semi` (bobtail and laden) on FULL. Expected: the AXLE and TRLR
  bars still in D, in N and on each brake; any body in N on a slight slope rolls off as before,
  and on the flat comes to rest. Known, not fixed: with a trailer the AXLE number's last digit
  still moves by 1 kg (3 at most) on some ticks, a step that is not the wheel's (Queue, the
  towing item). On the bobtail, since the wheel fix (d22b3ee), it should barely move. Anything
  larger, or on TRLR, is a new finding.
- A laden `semi` on a grade near its limit (about 25 %), if the hill hold can be off in play:
  released and floored, it rolls back about 30 % further than before F1's fix (886 mm against 685; Queue).
- The wheel fix (d22b3ee), any body: a standing start pulls away about a quarter of a second
  sooner (`sedan` 0-50 3.47 -> 3.20 s), and full stops are a little shorter. The tractor's
  pull-away no longer rings on `accLong` (FULL). With the hill hold off on a steep grade, a body
  rolls back about half as far again as before (the honest mass); one let roll in N gathers its
  first 5 km/h sooner. Parked bodies hold as before.
- Flatland's crates on a respawn: `drone-mk2` in Flatland, carry one crate away and drop it, pick
  up another, press respawn. Expected: all three are back beside the start, none on the hook.
- The pad's stick in menus after the held-stick change: with the mouse moved (nothing lit), push
  the left stick once on the pause menu, LEVEL and the garage. Expected: the first push lights a
  control, and holding the stick then moves on as before.

- RoadPath's editor buttons after the fold (ebea62a): on a scratch copy of a level, select a
  RoadPath and press "Conform terrain" then "Paint splat under road". Expected: the terrain
  flattens under the road and the road's channel paints, as before, and Ctrl+Z undoes each.
- The semis' part-pedal start gear (dd8dd5e): `semi` or `semi-conventional`, bobtail and with a
  loaded trailer, stopped nose-up on a grade or on soft ground; pull away at a third to half
  pedal. Expected: on some grades it holds one start gear lower than before and pulls away
  without bogging; a floored launch and any launch on flat tarmac are as before.

## Unit map

Sizes are GDScript lines at 716bf06, rounded. A unit's tests and `docs/` pages go with it.

| # | Unit | Paths | Size | Reviewed at | Result |
|---|------|-------|------|-------------|--------|
| 1 | COMPROMISE triage | every `COMPROMISE` in `src/`, `kit/`, `tools/`, `tests/`, `docs/` | 72 mentions | c6686e0 | 18 mentions relabelled (design choices, an estimate, an engine limit, a code debt); 54 real ones stay; 1 fix queued |
| 2a | Drivetrain: the class | `src/vehicles/base/drivetrain.gd` | 1.6k | ab672ce | 4 wrong comments on the rigid crank fixed; no dead symbol; both `COMPROMISE` labels real; 1 fix queued (the rigid branch's dead outputs) |
| 2b | Drivetrain: its tests and doc | `tests/test_drivetrain.gd`, `docs/drivetrain.md` | 2.8k tests + 0.4k doc | 1f85257 | 1 hollow test case and 1 duplicate test removed, 3 wrong test comments and 5 wrong doc figures fixed (heavy vans' inertia, reserve and motoring; the tractor's governed upshift; anti-stall); the doc's measured figures not re-run |
| 2c | Drivetrain: the small files | `differential.gd`, `torque_converter.gd`, `shift_policy.gd`, `pedal_map.gd` in `src/vehicles/base/`; `tests/test_differential.gd`, `test_shift_policy.gd`, `test_torque_converter.gd` | 1.0k + 1.2k tests | dd8dd5e | `start_gear` put on the one engine law (it read the drive without the motoring share; the semis' part-pedal start gear moves); 1 duplicate test and 3 dead fixture lines removed, 3 history-worded test comments fixed; no dead symbol, no wrong comment, the one `COMPROMISE` real |
| 3a | Wheels: the wheel | `src/vehicles/base/wheel.gd` | 1.1k | 8294fee | 6 wrong or misplaced comments fixed, 1 misnamed parameter renamed (`surface_drag_force`'s `mass`); no dead symbol; the 3 `COMPROMISE` labels real; notes for its next read: `sessions/2026-11-15-wheel-leftovers.md` § For unit 3a's next read |
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
