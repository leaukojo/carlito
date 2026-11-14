# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions at 31ec0bf: 34 in `src kit tools tests` (af471cd removed
`RayWheel._contact_query`'s with its cause), 21 in `docs` (count with
`grep -rI COMPROMISE <dirs> | wc -l`). Goal: only real ones keep the label.

Past sessions: `sessions/`, each named by its date and item.

Units 1 to 3a were read before the skill asked for simpler implementations: they come back
through the most-commits rule, or sooner on the user's word.

The mechanical sweep ran (its session file pruned): one dead test const removed; the
guards (`check_orphans`, `check_docs`) already cover public funcs and citations. Duplicate
tests with different bodies are left to each unit's review.

## Queue (top first)

- The cover sweep's findings (`sessions/2026-11-14-cover-sweep.md`, numbered as there; its
  § How it was searched lists what the sweep left to each unit's review). Each line starts with
  its proving run (take the cover out, measure, undo). Run lines: `docs/vehicle_measurements.md`
  § Measure-tool run lines. Never a new filter, on a reading or a signal.
  - (1) `VehicleMath.RESIST_EPS`, `air_force`'s `airspeed < RESIST_EPS` gate
    (`vehicle_math.gd:138`, `:200`): "stops jitter" with nothing named, and each axis is already
    one-tick clamped. Prove: gate on `delta <= 0.0` alone, run `test_vehicle_math`,
    `test_tow_host` (the standing-rig test) and `measure_vehicles -- semi 20 rest` plus
    `tractor-kenney 20 rest`, against the same at HEAD. With the rest readings equal to the
    digit printed: delete the constant and its clause (dead). With any reading moved: undo, and
    write what moved in the session file and a Queue line for its source. [high, auto, Opus]
  - (3) `measure_vehicles.CORNER_SMOOTH_S` (`:64`; `:2475`, `:2493`, `:2502`): a 0.25 s lag
    before the cornering peak is taken, no reason given, and `acc_lat` smoothed a second time.
    Prove: beside each smoothed peak keep the raw one (`lat`, `across / mass`, `acc_lat`) and
    print both for `sedan`, `suv`, `semi`, `tractor-kenney` on `corner`. Raw within 0.02 g of
    smoothed on every body: remove the lag and re-run `doc=cornering`. Further apart: do not
    remove; the session file names the tick and what `v * yaw_rate` did on it (a yaw swing past
    saturation is the slip-angle gate's job, a tick-rate alternation is a source to queue).
    [high, auto, Sonnet]
  - (2) `measure_vehicles._sample_gates`' two-tick means (`:1812-1822` `over`, `:1828-1833`
    `xfer_mean`): they average out the take-up's drive force alternating at the tick rate under
    `LOW_SPEED_FLOOR`, whose source is `proposals.md` "The wheel and the body exchange one
    force". Prove: judge on the tick's own value, run the launch pass on `sedan`, `semi`,
    `tractor-kenney`, and record per body the `front axle` gate's overshoot with and without
    the mean. Do not land the removal while that proposal is open (the gate would fail on a
    known fault): add the figures to the proposal's Evidence, and a line to its Cost that the
    means, `docs/handling.md:94` and the report's "(two-tick mean)" go with it.
    [medium, auto, Sonnet]
  - (4) `MeasureRig.ESC_CHATTER_EPS` (`tools/measure_rig.gd:272`,
    `tests/test_measure_chatter.gd:42`): the ESC's moment share flips ±0.0003 a tick on `van`'s
    held touch, called "the sensors' per-tick noise". Prove and trace: on `van`'s step pass log
    per tick, through a held touch, `WheelDrive.esc_step`'s inputs (speed, steer mean,
    `yaw_rate`, `lat_acc`, `_slip_est`) and say which alternates and what writes it (the
    `acc_lat` path is the `ACCEL_SMOOTH` proposal's; `angular_velocity.y` leads to the tyres'
    side caps). Fix nothing in `StabilityControl`: write the source's brief as a Queue line; the
    eps comes down in the fix that removes the source. [high, auto, Opus]
  - (5) `TractorTelemetry.SLIP_FLOOR_KMH` (`tractor_telemetry.gd:21`, `slip_pct`): contract
    `wheel_slip` snapped to 0 under 0.5 km/h of wheel speed because "the ratio is noise". Prove:
    floor at 0 (keep the `wheel_speed_kmh <= 0.0` guard), log `wheel_speed`, `ground_speed` and
    `wheel_slip` per tick on `tractor-kenney` and `tractor-cvt` standing in D, in N, on the hill
    hold, and through a pull-away. Quiet at rest and the only non-zero readings are real spin:
    propose removal (`proposals.md`, a contract signal's behaviour). Non-zero at rest: the
    session file gives its size and the wheel's speed trace; it is the free wheel's ring, so the
    floor stays with a comment naming that proposal. A radar unit's minimum speed, from a page
    opened, would make it a model instead. Ends in a proposal. [high, auto, Opus]
  - (6) `Articulation.YAW_CAP_SHARE` (`articulation.gd:9-12`, `yaw_friction_torque`,
    `TowHost`'s plate friction at `tow_host.gd:369-376`): half of the one-tick stop, because
    the towed tyres' lateral caps stop the same relative yaw in the same tick; a guess where
    d849de9's `taken` is the exact form. Prove: with the share at 1.0 read
    `test_a_coupled_rig_standing_still_stays_mirror_symmetric`'s peak rate per kind, then at 0.5
    log the relative yaw rate per tick after a yaw kick on a standing `semi` + `box` (the
    overshoot's ratio tick to tick), and on a slow full-lock turn how often the cap binds under
    the declared `friction_nm`. Then plan the plate's torque sharing one cap with the bogie's
    side forces (what `taken` would be here, and in which order `TowHost` and the towed wheels
    tick). It changes a force on every coupled rig: ends in a proposal. [high, plan, Opus]
- `BaseVehicle.ACCEL_SMOOTH`: measured, awaiting the user's decision (`proposals.md`, "accLong /
  accLat / acc_vert: raw or a declared sensor filter"; `sessions/2026-11-14-accel-smooth-proof.md`).
- The engine law's three inversions (`sessions/2026-11-12-shared-law-audit.md`, finding 9).
  `Drivetrain.fuel_to_land`, `Drivetrain.drag_fuel` and `PedalMap._row_fuel` each compute
  `(net - motoring) / span`; one "fuel for a net crank torque" function serves all three.
  They differ where `span <= 0` (`drag_fuel` gives 0, the others 1 above the motoring law):
  pick one answer, show no shipped curve reaches it, keep the results the same to the bit
  elsewhere (`test_drivetrain`, `test_telemetry`'s idle case). [high, auto, Opus]
- The shared cap's `taken` on a towing wheel (`sessions/2026-11-13-f1-rest-guard.md`, finding 3).
  Since d849de9 a laden `semi` released on 25 % with the hill hold off rolls back 927 mm, 685
  before (`measure_grade -- semi rollback nohold`, against `wheel.gd` at d849de9~1); every other
  roll-back is within 1 mm. Derived, not measured: `RayWheel.tick` takes gravity's pull on the
  contact's own mass out of `taken`, never the trailer's pull through the coupling, so a drive
  wheel holding a trailer loses its rolling drag under about 0.1 m/s. Trace it (the drag per
  wheel through that roll-back, bobtail against laden) and read the steady 0.04 to 0.2 mm/s
  drift of a standing rig; write the cause and the fix's brief, fix nothing. The fix changes a
  force: its line ends in a proposal. [diagnose, high, Fable]
- (to consider, user 2026-11-14: not now) The measure tool's bodies past Jolt's switch to sharp
  shapes (`sessions/2026-11-14-sweep-rest-disagree.md` § Cause, § Evidence). `measure_vehicles`'
  `KERB_WIDTH` 80 m kerb and its 6 km `Strip` slab put 1 to 3 mm of contact noise into kerb-run
  figures that level geometry does not have; with the kerb 20 m wide its deep ticks went 4 -> 0.
  Options: a kerb narrow enough that its far corner stays under 37 m (check the oblique pass still
  crosses it), the strip laid as slabs under about 190 m (corner under 139 m), or leave both and
  say so beside the kerb figures. Any change moves the committed `doc=` tables: decide with the
  user first, then baseline at HEAD and rerun. Flatland's `InfiniteGround` (4 km box) is in the
  same regime in play, a leaned wheel reading up to about 3 mm off: note only, no fix proposed.
  [high, plan, Opus]
- (user 2026-11-14) A kept contact probe (`sessions/2026-11-14-sweep-rest-disagree.md`, the tally
  in § Evidence). Two sessions each wrote and deleted a probe inside `RayWheel._contact_pass`, and
  their "deep gap" counts cannot be compared. Wanted: the tally per rest collider (passes, rest
  empty at unsafe, rest at `safe_drop`, deep, start inside) behind a `measure_vehicles` flag, read
  from outside `_contact_pass` where it can be, with no cost when off. A tool feature: propose it
  (`proposals.md`) before building. [high, plan, Opus]
- (user 2026-11-14) `tools/measure_vehicles.gd` is 6256 lines in one file, and
  `tools/CLAUDE.md` ("a new measurement is a scenario in an existing tool") keeps it growing.
  Unit 16's review splits the unit in the map first; it then says whether passes move to files
  of their own (`kerb`, `scrape`, `side` are self-contained: `_start_kerb` to `_report_kerb_run`)
  and whether the rule changes. No split before that review. [high, plan, Opus]
- `docs/vehicles.md` § Contact's "Cost, `semi` + `box`: the cast costs an order of magnitude over
  the ray, natively and on web" cites a `kerb` cost readout no tool prints
  (`sessions/2026-11-14-deck-start-test.md` finding 2). Find where the figure came from
  (`git log -S "order of magnitude" -- docs/vehicles.md`); with a run behind it, cite that run;
  with none, cut the claim (the docs are at their character cap, so cutting helps). A native
  figure for the cast alone is in the session file. [medium, auto, Sonnet]
- `scrape onebody`'s `firetruck` FR peaks at 501 N across where the two-body run reads 217 N, the
  same wall at +0 mm, 100 % contact (`sessions/2026-11-14-deck-start-test.md` § Measured). f7bac55
  left it byte-equal, so the skipped body is not its cause. Trace which contact the sweep by contact
  reads on the grazing ticks with the wall a shape of the strip's body against a body of its own,
  and why that doubles the force across; write the cause and the brief, fix nothing. [diagnose,
  high, Fable]

Deferred until units 3 and 4 are reviewed (it touches both):

- Rigid crank's dead outputs (finding 2 of `sessions/2026-11-11-drivetrain-2a.md`, pruned: read
  it and `2026-11-12-drivetrain-2b.md` with `git show 31ec0bf:.claude/review_journal/sessions/<file>`). On a body
  where `Drivetrain.drives_wheels` is false, `process`'s returned axle torque reaches no wheel
  and `drive_wheel_omega` is always 0, so the branch's limiter, `crank_forward` and overrun do
  nothing. Remove them, `WheelDrive.tick`'s `axle_torque` path and the tests that pin them;
  keep the free-rev rpm, `applied_throttle` and the gearbox. Also check the branch's
  `esc_cap` line (untested, maybe dead) and reword the one test comment that describes
  `crank_forward` (`sessions/2026-11-12-drivetrain-2b.md` § Deferred). [high, plan, Opus]

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
  and on the flat comes to rest. Known, not fixed: on the `semi` in D or N the AXLE number's last
  digit still moves by 1 kg (3 at most) on half to three quarters of ticks, the free wheel's ring
  (`proposals.md`). Anything larger, or on TRLR, is a new finding.
- A laden `semi` on a grade near its limit (about 25 %), if the hill hold can be off in play:
  released and floored, it rolls back about a quarter further than before F1's fix (Queue).
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
| 3a | Wheels: the wheel | `src/vehicles/base/wheel.gd` | 1.1k | 8294fee | 6 wrong or misplaced comments fixed, 1 misnamed parameter renamed (`surface_drag_force`'s `mass`); no dead symbol; the 3 `COMPROMISE` labels real; 1 item queued (two readings of "the slip floor") |
| 3b | Wheels: the owner | `src/vehicles/base/wheel_drive.gd` | 1.1k | | |
| 3c | Wheels: the tests | `tests/test_wheel_spin.gd` | 2.8k tests | | |
| 4 | Vehicle base, rest | `src/vehicles/base/` minus units 2, 3, 5; `src/vehicles/tyres/`; `docs/vehicles.md`, `docs/handling.md` | about 4k | | |
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
