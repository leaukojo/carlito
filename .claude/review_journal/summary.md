# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions after unit 3a: 33 in `src kit tools tests`, 21 in `docs` (count with
`grep -rI COMPROMISE <dirs> | wc -l`). Goal: only real ones keep the label.

Next session: the Queue's top item (the mechanical sweep): effort `medium`, auto mode, Sonnet,
after `/clear`.

Units 1 to 3a were read before the skill asked for simpler implementations: they come back
through the most-commits rule, or sooner on the user's word.

## Queue (top first)

- Mechanical sweep of the whole repo: no design judgement, so it runs cheap. Over every `.gd`
  in `src kit addons/carlito_kit tools tests` (never `addons/gdUnit4`):
  1. Unreferenced symbols and files: each `func`, `var`, `const`, `signal` and `class_name`
     grepped as a word across `.gd`, `.tscn`, `.tres`, `project.godot`, `tools`, `.github`;
     list the names with no hit outside their own file and only the definition inside (engine
     virtuals excluded), and the files nothing loads.
  2. Duplicate tests: test functions with the same body, or the same asserts on the same call.
  3. Citations that do not resolve, in comments and `docs/`: `` `Class.member` ``, repo paths,
     `docs/x.md` § sections.
  Each hit is proven as the skill's step 3 says before it is touched (a `has_method` guard or a
  method whose absence is behaviour is not dead: `src/vehicles/CLAUDE.md`). Fix the S ones;
  queue the rest under their unit. If part 3 finds more than a handful, propose the check as a
  guard in `tools/check_docs.mjs` instead of fixing by hand. May take two sessions: the Queue
  line then says which directory to resume at. [medium, auto, Sonnet]
- Shared-law audit (one session, read-only but for S fixes). Both behaviour bugs the review
  found were one call site reading a constant or a second formula where its neighbours read the
  shared one (`ShiftPolicy.start_gear` off the engine law; the airborne wheel off the body's
  slip floor). For each rule in `CLAUDE.md` and `src/vehicles/CLAUDE.md` that names one law, one
  predicate or one accessor (`Drivetrain.applied_throttle`, `InputRouter.bridge_drives()`,
  `RayWheel.is_rear_z`, `Layers.SOLID`, `VehicleMath`'s free-body helpers, `slip_floor`), list
  every site that computes the same thing another way. A site that changes driving when fixed
  is a proposal. [high, auto]
- The slip floor's two sites (`sessions/2026-11-12-wheels-3a.md`, finding 8 and § Decision;
  decided with the user on 2026-11-12, so it is ready). Two parts, one commit each:
  1. Airborne wheel: `RayWheel.tick`'s off-the-ground `_integrate_spin` call passes the body's
     `slip_floor` as `floor_vel` (it takes the default `LOW_SPEED_FLOOR`), with a
     `test_wheel_spin` case that fails without it. Before and after, one lone gradeability run
     on a TC body (`suv-luxury`, the one `docs/vehicles.md` § One-tick caps names); a figure
     that moves goes under "Please verify" and into the doc.
  2. `road_change` keeps the constant: its comment, `docs/vehicles.md` § Following the body and
     the `test_wheel_spin` case's comment say `LOW_SPEED_FLOOR`, not "the slip floor". No code
     change. Reopen only if a run shows a tick-rate ring between 1.5 m/s and a raised floor.
  [high, auto]

Deferred until units 3 and 4 are reviewed (it touches both):

- Rigid crank's dead outputs (`sessions/2026-11-11-drivetrain-2a.md`, finding 2). On a body
  where `Drivetrain.drives_wheels` is false, `process`'s returned axle torque reaches no wheel
  and `drive_wheel_omega` is always 0, so the branch's limiter, `crank_forward` and overrun do
  nothing. Remove them, `WheelDrive.tick`'s `axle_torque` path and the tests that pin them;
  keep the free-rev rpm, `applied_throttle` and the gearbox. Also check the branch's
  `esc_cap` line (untested, maybe dead) and reword the one test comment that describes
  `crank_forward` (`sessions/2026-11-12-drivetrain-2b.md` § Deferred). [high, plan]

## Please verify (user, by driving)

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
