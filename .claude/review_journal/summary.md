# Review journal: summary

Protocol: `.claude/skills/review-continue/SKILL.md`. Launch with "continue reviewing".

`COMPROMISE` mentions at 31ec0bf: 34 in `src kit tools tests` (af471cd removed
`RayWheel._contact_query`'s with its cause), 21 in `docs` (count with
`grep -rI COMPROMISE <dirs> | wc -l`). Goal: only real ones keep the label.

Next session, by model (`/clear` first; the skill's § Diagnose only):
- Fable: "ground under a deck", why the sweep's safe stop and the rest test disagree, diagnose only (high, auto).
- Fable, after it: the towing wheel's `taken`, diagnose only (high, auto).
- Sonnet: `RayWheel.settled_drop`'s `maxf(normal_up, 0.1)` floor (medium, auto).
- Opus: the engine law's three inversions (high, auto).

Tags retagged 2026-11-14 on the user's word: Fable's credits go to finding causes and writing
briefs, never to fixing; no `xhigh` session without the user asking.

"Ground under a deck", step 2, in `sessions/2026-11-14-deck-gap-exact.md` (6964c1e): Jolt rounds
the wheel cylinder's rim by its convex radius (8 mm on a 0.36 x 0.2 tyre) and `cylinder_support`
now does too, so a stop across the axle no longer reads millimetres deep. Stopped at the plan's
step 3 rule on two unexplained readings (Queue, diagnose).

F2's remainder fixed in `sessions/2026-11-14-f2-own-body-wall.md` (af471cd): where the rest test
names a contact the spring cannot carry, the wheel sweeps again by contact
(`RayWheel._carried_sweep`, `collide_shape`'s pairs), so a wall of the ground's own body (level_3's
welded barriers, a cliff of any island heightmap) leaves the tread on the ground. Left: ground
under a deck the engine's sweep left out (Queue).

F2 fixed in `sessions/2026-11-13-f2-wall-contact.md` (22f042d): a contact more than `LYING_DEG`
off a wheel's travel is not the spring's (`RayWheel.carries`).
`measure_vehicles -- <bodies> 45 scrape [steer=<pct>] [onebody]` is its guard run.

F1 closed in `sessions/2026-11-13-f1-rest-guard.md`: `measure_semi_launch -- <unit> steady strict`
fails on a standing rig's rocking (proven against the fix reverted) and CI runs it; the plan's
missing runs done (park, stops, creep, roll-back, the three CI measure gates) and the plan
distilled and deleted. Left: the free wheel's ring (`proposals.md`) and one roll-back that moved
(Queue).

The ui_and_gamepad_fixes plan's commits (d8e5afa..f78f937) were reviewed on the user's request in
`sessions/2026-11-13-ui-gamepad-plan-review.md`: the dashboard bars' display lag removed (it hid
F1 on every bar; `test_no_instrument_smooths_its_value` guards it), `FamilyContent` tested and
its crates put back on a respawn as the plan says, a held stick no longer searching the HUD every
motion event, and the plan's two open findings queued as F1 and F2.

The slip floor's two sites ran in `sessions/2026-11-12-slip-floor-sites.md`: a lifted wheel's ABS
floor and TC ceiling read the body's `slip_floor` (`suv-luxury`'s lone grade run unchanged);
`road_change`'s fade keeps `LOW_SPEED_FLOOR` and its comment, doc and test say so.

The shared-law audit ran in `sessions/2026-11-12-shared-law-audit.md`: one tool bug (the descent
ledger's contact velocity on the origin lever) and eight inline copies of a shared predicate,
helper or constant fixed; no site that changes driving, so no proposal; 1 item queued.

Units 1 to 3a were read before the skill asked for simpler implementations: they come back
through the most-commits rule, or sooner on the user's word.

The mechanical sweep ran in `sessions/2026-11-12-sweep-1.md`: one dead test const removed; the
guards (`check_orphans`, `check_docs`) already cover public funcs and citations. Duplicate
tests with different bodies are left to each unit's review.

## Queue (top first)

- Ground under a deck the sweep left out (`sessions/2026-11-14-f2-own-body-wall.md`, finding 3
  and § The second trigger). With a wheel's side in a barrier welded to its deck and other ground
  within the travel under the deck, the engine's sweep skips the deck with its wall and stops on
  the lower ground; the rest test there names the deck, which the spring carries, so
  `_carried_sweep` never runs and `settled_drop`'s clamp to `safe_drop` hides the deck's depth: the
  wheel rides low by the gap (proved: 0.0108 of compression for 0.06 over a 5 cm gap; the fixture
  is in the session file). Step 1 done (`sessions/2026-11-14-level3-deck-gap.md`). Step 2 in
  `sessions/2026-11-14-deck-gap-exact.md`: the rounded rim fixed (6964c1e), the deep-gap count on
  `sedan,semi 45 kerb` 889 -> 24; the 22 ticks inside the 20 cm kerb are real (this class); the
  fixture fails at HEAD at 0.05 and at 0.18 m (its body in the session file). Stopped on two
  unexplained readings: 2 to 3 square-edge ticks 2 to 4 mm deep with no axle part (the kerb box's
  convex radius refuted), and 126 kerb-run ticks whose `safe_drop` pose already has a rest contact,
  mostly on the flat strip. Next: find why Godot's `cast_motion` safe stop and `get_rest_info`
  disagree (`_cast_motion_impl`'s `collides()` against `get_rest_info`'s settings in
  `modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp`; and float32 on the 6 km
  strip, `docs/vehicles.md` § Contact: rerun the probe with the kerb near the strip's centre).
  Write the cause and which trigger it allows (deep gap, or a rest test at `safe_drop`); fix
  nothing. No wider clamp and no tolerance tuned. [diagnose, high, Fable]
- The deck trigger itself, after the diagnosis above: from its brief, the fixture test committed
  once it passes; `kerb`, `side`, `scrape` and the three CI gates before and after. It ends in a
  proposal (a plan the user approves). [high, plan, Opus]
- `RayWheel.settled_drop`'s `maxf(normal_up, 0.1)` (same file, deferred): since 22f042d a kept
  contact has `normal_up >= cos(LYING_DEG)`, so the floor cannot bind in `_contact_query`. Check
  `settled_drop`'s other callers and its tests, then remove the floor (same to the bit) or say
  what still needs it. [medium, auto, Sonnet]
- (user, 2026-11-13) The cover sweep (the skill's § Covers), across every unit at once and not
  waiting for each unit's turn. Search `src kit tools tests` for the section's "where they sit"
  list (`lerp`, `move_toward`, `smooth`, `hyster`, `deadband`, `snapped`, `is_zero_approx`,
  `maxf(…, 1e-`, body or level names in an `if`, widened test tolerances; comments with "avoid",
  "hide", "flicker", "jitter", "workaround", "stability"), sort each hit into model / cover / dead,
  with the reason quoted. This session only sorts: it writes one Queue line per cover found, with
  the source to trace and the proving run (take it out, measure, undo) as that line's first step,
  tagged for Opus or Sonnet; it proves and fixes none. One hit already measured: `BaseVehicle.ACCEL_SMOOTH`, a
  10 /s lag on the contract's `accLong` / `accLat` / `acc_vert`, passed 0.202 of a 2.435 m/s2
  tick-rate alternation on a standing bobtail (`sessions/2026-11-13-f1-standing-rock.md`): sort it
  as a sender's filter with a source, or a cover. [diagnose, high, Fable]
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
- A doc check (same file, finding 4): `docs/drivetrain.md` says "The laden semis roll back far on
  25 % with or without the hold"; `measure_grade -- semi rollback` prints 0.1 mm with the hold.
  Run both units with and without `nohold`, read what the tool's figure covers
  (`tools/measure_grade.gd`), fix the paragraph. [medium, auto, Sonnet]

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
  drop. Known, not fixed: beside a barrier the wall-side wheels can ride a few cm low where other
  ground lies just under the road (Queue).

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
