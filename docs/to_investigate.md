# To investigate

Suspected defects and rules that stand in for a missing guard, noticed during other work. One
entry each, ≤3 lines: where, symptom, evidence. Delete an entry once it is fixed or dismissed.

Entries are grouped into work sessions, each with a suggested model / effort. Sessions run
sequentially or in separate worktrees (never two headless Godots on one checkout; a fresh
worktree needs `--import` + a bake first). 4, 5 and 7 are independent; 1 precedes 8; 2 precedes 3.

## 1. Bake-pipeline guards — Opus, high

`level_baker.gd` is itself in `BAKE_CODE_INPUTS`, so any edit here re-stales all 7 levels: batch
them, then one re-bake + `check_bakes` at the end.

- **Bake inputs are hashed as raw text, comments included** (`LevelBaker.hash_file`): a comment
  edit to any `BAKE_CODE_INPUTS` file (~287 comment lines) or any `kit/` script re-stales all 7
  levels. Hash `.gd` inputs with comment lines stripped.
- **Pre-commit gate 4 and the Stop hook use different path regexes**, neither tied to
  `BAKE_CODE_INPUTS`, and both fire on `.md` edits under `kit/` / `src/levels/`.
- **Nodes under `AuthoringRoot` that the baker does not know vanish silently** (water,
  `WorldBounds`, payloads): `LevelBaker._collect` skips them. A bake error would replace the prose.
- **GridMap `cell_center_y = false` is prose only** (`kit/CLAUDE.md`): the baker uses
  `map_to_local`, so a default GridMap bakes half a cell off with no error.
- **`paint_road_asphalt` is ungated**: stale paint after a road/profile edit is invisible to bake,
  tests and CI, and the tool accepts `car_arena` (`src/levels/CLAUDE.md` says never).

## 2. Truck measurement truth — Opus, xhigh

Fix the instruments before session 3 trusts any figure. Long sweeps are handed to the user.

- **`measure_vehicles` divides force by `spec.mass` only**, so a towed combination reads against
  the bare tractor's mass. Two rules compensate: `ImplementCatalog.first()` must stay three-point
  (`src/vehicles/tractor/CLAUDE.md`), and `-- semi` has no bobtail case (`docs/vehicles.md`).
- **"top (settled)" can be the time cap** in the measure tools' output, same wording. Tool
  should say which.
- **Semi launch steer-axle floor (≥ 8.5 kN) is enforced only by `measure_semi_launch`**, which
  exits 0; a wheelbase edit passes CI.
- **P7 rollover baseline is contested**: a deleted `src/vehicles/truck/CLAUDE.md` note said all four
  roll at 0.84-0.94 g (full-lock step at 40 km/h); an earlier quote said ~1.06 g, no rollover. Bobtail COM 1.09
  vs ~1.03 m.
- **A runtime `mass` write and `set_corner_mass_from` are two statements** (`truck.gd`,
  `base_vehicle.gd`); nothing enforces the pair. One setter would.
- **Trailer brake apportioning is unpinned**: `tests/test_trailer.gd` checks `brake_torque > 0`,
  which is how the tanker/tipper spec headers came to quote figures their values did not match.
- **"The 25 % grade the rig can climb"** (`fifth_wheel.gd` header, `docs/heavy_vehicles.md` §
  The joint) disagrees with the grip budget: ~66 kN coupled drive-axle grip (`semi_spec.tres`) vs
  ~78 kN for 32 t on 25 %. Measure with `measure_grade` or restate as a joint-swing case only.

## 3. Reopened vehicle compromises — Opus, xhigh (max if the plan stalls); plan mode first

After session 2. Track first: it moves every rollover threshold, so taper and tipper limits tuned
before it would be redone. The user verifies by driving.

- **Truck track.** Once accepted as a compromise: 1.44 m track against ~2.0 m real, so every
  rollover threshold reads ~25 % low (`docs/heavy_vehicles.md` § Truck sizing; `src/vehicles/truck/CLAUDE.md` § Rollover).
- **Truck steer taper.** Once accepted as a compromise: not tightened, so full lock at motorway
  speed rolls the rig (`min_steer_frac` 0.21; `src/vehicles/truck/CLAUDE.md` § Rollover).
- **Tipper raised.** Once accepted as a compromise: the interlock allows driving off with the body
  up, which rolls the rig (0.26 g threshold; `docs/heavy_vehicles.md` § Truck sizing).
- **Recouple catch-out.** Once accepted as a compromise: a heavy stop then recouple pins the rears
  ~0.4 s; the margin is 0.1 bar, unpinned, and any stopping-distance change moves it.
- **Delivery van.** Once accepted as a compromise: `delivery` rolls over at 13.0° lean
  (`docs/vehicles.md`).

## 4. Generators and generated scenes — Sonnet, high

Card regen is windowed: the user runs it.

- **`flatbed.tscn` has no `uid=`**, so moving it means hand-editing references. Add a uid. Related:
  `_restore_uids` is copy-pasted in `tools/gen_boat_variants.gd` and `tools/gen_kenney_vehicles.gd`.
- **Generated Kenney scenes**: a new generated child missing from `GENERATED_CHILDREN`, or a hand
  `;` comment, breaks regen idempotence with no test (`src/vehicles/kenney/CLAUDE.md`).
- **Garbage truck: nothing tests the scene yields a `RefuseBody` rig**; a regen that wipes
  `Model/arm` makes `truck.gd`'s `_find_rig` return null and the body publishes zeros.
- **The four semi-trailers' `Wheels/*` roots carry no transform** (`box.tscn` `WheelL1`), so their
  selector/garage cards show every wheel stacked at the kingpin. `farm_tipper.tscn` authors them
  at the hubs; copy that (`src/vehicles/tractor/CLAUDE.md`).

## 5. Cheap static guards — Sonnet, medium

- **Contract version in a test name** (`test_real_contract_is_valid_v<N>`, `tests/test_contract.gd`):
  every bump renames the test. Drop the number from the name.
- **`BaseVehicle`'s layer == VEHICLE is unasserted**: the water kill-volume pairing is tested on
  the `WaterSurface` side only.
- **WorldBounds `extent` == water `size` is untested per level** (`tests/test_world_bounds.gd`
  checks wall geometry only).
- **`tools/gen_car_arena.gd` briefing constants "edit together"** has no test.
- **Rule 10 (no emoji) is guarded only for registry labels and challenge text.**
- **`test_lamps` scans two files** (`lamp_set.gd`, `drone_indicators.gd`) for a clock, and its
  `Timer` substring match also trips on a comment.
- **Lamp-path resolution is pinned only for trailers, drone and Kenney bodies**; semi/conventional,
  boat, plane, train and tractor can lose a lens silently (`LampSet` tolerates a missing path).
- **`check_orphans.mjs` counts comment mentions as callers**: `Articulation.jackknife_step` /
  `pose_at_angle` are test-only but pass because `articulation.gd` names them in a comment.
- **Contract `engine_hours` desc says "Survives respawn, like the odometer"**, but
  `BaseVehicle.reset_session_state` reseeds both to 0. Fix the desc (contract-edit skill).

## 6. Web export — Opus, medium

Read `docs/deploying.md` § The web export first; all three need it.

- **`export_presets.cfg` `thread_support=false` and PWA are unpinned**: they fail only in an
  exported build. Text asserts like `tests/test_project_settings.gd` would catch them.
- **`shell.html` vs the Godot export template drifts unguarded** on an engine upgrade.
- **`head_include.html` accepts `postMessage` from any origin**, relying on an origin check in
  sloppyCAN's carlito.js, outside this repo (the stance is documented in its header). Verify that
  check exists — a two-minute read given the sloppyCAN path.

## 7. preload vs `class_name` — Opus, high (investigation; conversion, if any, Sonnet medium)

- **preload-never-`class_name`** (~42 sites). Headless already uses `class_name` (`VehicleCatalog`
  in `kit/bake/level_baker.gd`, `LevelBaker.SurfaceAccumulator`, `RailTrack`) — but CI imports
  first; test a fresh worktree with no `.godot/` class cache before dropping the rule.

## 8. Level 2 road + a road-grade gate — Opus, high

After session 1. The user verifies by driving; `measure_grade -- level=level_2` reads the ask.

- **Level 2 road.** Once accepted as a compromise: worst grade 86.9 %, nothing can climb the upper
  road, and nothing gates road grade (`src/levels/CLAUDE.md`).

## Decide or close (no session)

- **`tests/test_tow_host.gd` reads `semi.gd` source** to pin its `super` camera-exclusion call: a
  hand-rolled copy is observably identical today, so it guards only a future base change, and
  fails on any rename or restructure. Suggested: delete.
- **`PARALLEL_2_SPLITS` dropped building shadows on level_3** while driving (`docs/making_a_level.md`);
  unexplained, no repro. Suggested: delete until seen again on the deployed build.
- **Bake-cost figures in `kit/CLAUDE.md` disagree** ("~2 s of ~95 s CI job" vs "a full run takes
  minutes"). Time one CI bake job and fix the line.
- **Drone geofence.** Once accepted as a compromise: soft, 400 m / 120 m above home
  (`src/vehicles/drone/drone_modes.gd` `GEOFENCE_*`). Suggested: re-accept unless something concrete reopened it.
- **Rail loops.** Once accepted as a compromise: two closed rail loops in one level is out of
  scope (`kit/CLAUDE.md`). Suggested: re-accept.
