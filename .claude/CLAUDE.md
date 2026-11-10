# CLAUDE.md

**Carlito**: a browser CAN-bus driving sandbox. Drive a car / truck / tractor / boat / drone /
plane / train while exchanging live signals with the sloppyCAN/RAMN simulator over a postMessage
bridge. Web-first. Levels are signal playgrounds (grades for `engine_load`, fields for hitch/PTO,
water for pitch/roll); challenges (`ChallengeRegistry.DEFS`) are the goal-driven, bridge-only
exception that teaches CAN. Docs map: `docs/overview.md`. The Godot 3 generation is an outside
backup: a reference, not a source.

## Working style

- Act as a senior Godot dev, no workarounds: the engine's real tools (GridMap/palette, never
  hand-placed piles of nodes); asset footprints measured against the 1.8 m car.
- The user verifies by driving: a demo or verification scene is a real Level with a VehicleSpawn
  (F6-runnable, unregistered), never camera-only. Visual bar: crisp splat borders, plateaued
  buildable terrain, coasts circular by water at sea level, no square edge.
- Measure headless what headless can; ask the user only for feel and transients (shift jolts,
  roll-back). "Quickly / do not verify" = make the small change and stop.
- **An approved plan changes only with the user's OK.** Follow-up work is a new plan, not TODO
  items; a task the user said to skip stays skipped. A plan file's `State:` line (done / next /
  open findings) is kept current at each step.
- **A sourced figure cites a page actually opened**, never a search summary or memory; a chart
  read by eye says so.
- When compacting, keep: the files modified, the active plan file and its State, pending runs
  and their exact commands, and unresolved review findings.

### Where things go

- CLAUDE.md: the constraint, a ≤1-line why, its guard; only what binds work in its directory and
  is not readable from the code or a guard's message (budgets: `tools/check_docs.mjs`). Exit
  rule: a line goes once a guard enforces it with a clear message before commit.
- Code comment: the constraint at its site. A COMPROMISE states what is true and what undoing it costs.
- `docs/`: derivations and tours. A finished plan is distilled there (plus at most one CLAUDE.md
  line), then deleted.
- Everywhere: present tense, no history ("used to", "Phase N adds"), no restating code. "Never"
  only for a guarded constraint; "every" in docs is intent, not a checked invariant.

## Standing rules (numbers are referenced from `docs/`)

1. Static world geometry ships baked per chunk (merged meshes, one collision body per chunk);
   GridMaps are authoring-only; drivable geometry welds into one level-wide body. `.baked.scn` is
   gitignored build output; the committed `.bake.json` is its hash record (CI fails stale bakes).
2. Ground = heightmap/plane collision; drivable structures get welded meshes; props get
   boxes/hulls. Trimesh is the exception, never the default.
3. Telemetry is read out of the sim that produced the motion, no derived fictions. Aux systems
   (fuel/coolant/battery, engine_load, trim) are simple honest models, labelled.
4. One contract file; everything else is generated from or validated against it.
5. Vehicles consume one normalized `VehicleInput` from `InputRouter` (lamp and ISOBUS state
   included, never a side channel); arbitration lives only in `src/input/`.
6. Levels, vehicles and UI are independent scenes composed by the shell.
7. CI does the export; no manual deploy (`docs/deploying.md`).
8. Pure logic (drivetrain, contract codec, arbitration, GPS/odometer, buoyancy, terrain/scatter/
   road/bake math) gets gdUnit4 tests.
9. Web render overrides and physics interpolation are pinned by `tests/test_project_settings.gd`;
   suspension tuning is rate-dependent.

Perf target: 60 fps in the worst view on the DEPLOYED web build (F3 overlay; draw calls first).
Authoring tools are deterministic (seeded) and destructive-by-button, never per-frame.

Non-goals: multiplayer, in-game level editor, walk-around character, crop growth, yield or farm
economy, real wave physics, app stores, world streaming, texture-layer terrain, LOD, spline-road
junctions, lane markings, traffic, third-party level sharing (a `.tscn` can embed scripts).

## Gotchas

- Who drives is `InputRouter.bridge_drives()`, never `Bridge.is_active()`.
- Gameplay rays mask `Layers.SOLID` (it omits `WorldBounds`); the seven layer bits are frozen.
- Scene tags (`src/levels/base/carlito_groups.gd`): a class joins its group in `_init`, not
  `_enter_tree`; kit/addons/tools discovery walks a named root, never `get_nodes_in_group()`.
- **A copy of an imported asset inside the project hijacks the original** (same `uid://`): keep
  backups outside the repo or `.gdignore` them, or a tool edits the copy and reports success.
- Bake-adjacent code is hashed via `LevelBaker.BAKE_CODE_INPUTS` (whole-line `.gd` comments are
  not): editing one re-stales every level; a new one needs an entry and a
  `tools/git-hooks/bake_paths.txt` prefix; `BAKER_VERSION` bumps only when no hashed file moves.
- A freed node compares equal to null: read results before `free()`.
- Vector2/3 math is float32: exact-boundary tests need ~1e-5; gdUnit4 `is_equal` on a
  `FORMAT_RF`/`RGBAF` pixel holds only for binary-exact values, else `is_equal_approx`.

## Running

Godot 4.7.1-stable; a new machine or clone: `docs/machine_setup.md`. Generators: `tools/CLAUDE.md`.

```powershell
node tools/godot_run.mjs -- --headless --path . --import             # import cache: after adding assets
node tools/godot_run.mjs --tests -- -a tests                         # suite; one: -a tests/test_truck.gd
node tools/godot_run.mjs -- --headless --path . --quit-after 120     # smoke; a challenge: --quit-after 300 -- --challenge=dev_box_stop
node tools/godot_run.mjs -- --headless --path . res://tools/bake_levels.tscn   # bake; stale check: check_bakes.tscn ("unbuilt" passes)
powershell -ExecutionPolicy Bypass -File tools/preflight.ps1         # "am I safe to push?": most CI gates
```

- **Judge a headless run by its output, never its exit code.** Clean leftovers: `ERROR: N
  resources still in use at exit`, and ~130 leaked ObjectDB instances after an island level.
- `--headless --script` runs only `extends SceneTree` scripts and cannot compile autoload
  identifiers: anything loading a vehicle or level scene is a game-mode tool scene.
- A fresh worktree has no `.baked.scn`: bake before trusting a test there.
- Parse-check `addons/` with `--headless --path . --editor --quit-after 30` (it misses integer
  division between two constants; intentional integer division needs `@warning_ignore`).
- `export_presets.cfg` traps fail only in an exported build: `docs/deploying.md` § The web export.
