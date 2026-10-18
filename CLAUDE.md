# CLAUDE.md

## What this is

**Carlito** — a browser-based CAN-bus driving sandbox: drive vehicles (car / truck /
tractor / boat / drone / plane / train) while exchanging live CAN signals with the
sloppyCAN/RAMN simulator over a postMessage bridge. Web-first. Levels are **signal
playgrounds**: content exists to make contract signals visibly perform
(grades for `engine_load`, fields for hitch/PTO, water for pitch/roll). **Challenges** are the
goal-driven, bridge-only exception that teaches CAN — `ChallengeRegistry.DEFS` is the list.

Docs map: `docs/overview.md`. The Godot 3 generation is an outside backup: a reference, not a source.

## Working style (global CLAUDE.md covers the rest)

- **Act as a senior Godot dev, no workarounds.** Use the engine's real tools (GridMap/palette for
  tiling, never hand-placed piles of nodes). Measure asset footprints against the 1.8 m car.
- The user verifies **by driving**: any demo/verification scene is a real Level with a
  VehicleSpawn (F6-runnable, unregistered), never camera-only. Visual bar: crisp high-contrast
  splat borders, plateaued buildable terrain, coasts circular by water at sea level, no square edge.
- "Quickly / do not verify" = skip ceremony, make the small change, stop.
- **Where things go:**
  - **CLAUDE.md** = the constraint, a ≤1-line why, and its guard; only what binds work in its
    directory, is not readable from the code or a guard's message, and still matches the code
    (budget: `tools/check_docs.mjs`). **Exit rule:** delete a line once a guard enforces it with a
    clear message before commit (test, hook, preflight); keep it if the guard fires only in CI or late.
  - **Code comment** = the constraint at its site. A COMPROMISE is stated there: what is true,
    and what undoing it costs.
  - **`docs/`** = derivations, tours (measured figures: `check_docs`, pre-commit). A
    finished plan (or TODO item) is distilled here, plus at most one CLAUDE.md line, then deleted.
  - Everywhere: present tense, no history ("used to", "replaces", "Phase N adds"), no restating code.
  - "Never" is only for a constraint a guard enforces; "ALL" / "every" in docs states intent, not
    a verified invariant: check before quoting one.

## Standing rules (permanent — numbering is referenced from `docs/`)

1. Static world geometry ships **baked per chunk** (merged meshes, one collision body per chunk);
   GridMaps are authoring-only; all drivable geometry welds into one level-wide body. The
   `.baked.scn` is gitignored CI build output; the `.bake.json` is the committed hash record (CI
   fails stale bakes). **Run `tools/bake_levels.tscn` once after cloning** (else dev collision).
2. Ground = heightmap/plane collision; drivable structures get welded collision meshes;
   props get boxes/hulls. **Trimesh is the exception, never the default.**
3. Telemetry is read out of the sim that produced the motion — no derived fictions. Aux
   systems (fuel/coolant/battery, engine_load, trim) are simple *honest models*, labelled.
4. One contract file; everything else generated from or validated against it.
5. Vehicles consume one normalized `VehicleInput` from `InputRouter` (lamp and ISOBUS state
   included, never a side channel); arbitration lives **only** in `src/input/`.
6. Levels, vehicles, and UI are independent scenes composed by the shell.
7. CI does the export; deploys are cache-busted, no manual deploy: `dev` publishes on every push,
   stable moves only on the *Promote dev → stable* workflow (`docs/deploying.md`).
8. Pure logic (drivetrain math, contract encode/decode, arbitration, GPS/odometer,
   buoyancy, terrain/scatter/road/bake math) gets gdUnit4 tests.
9. `.web` overrides + perf budget: msaa_3d.web=0, positional shadows hard on web, the sun at soft
   quality 1 (hard shimmers); `scaling_3d/scale.web` stays ≥ 1 (below adds an upscale pass).
   Physics: interpolation on; suspension tuning is rate-dependent.

Perf target: 60 fps in the worst view on the DEPLOYED web build (F3 overlay; draw calls first).
Authoring tools are deterministic (seeded) and destructive-by-button, never per-frame.

Non-goals: multiplayer, in-game level editor, walk-around character, crop growth, yield or farm
economy, real wave physics, mobile app stores, world streaming, texture-layer terrain, LOD,
spline-road junctions, lane markings, traffic, third-party level sharing (a `.tscn` can embed scripts).

## Gotchas & hard-won rules

- **Who drives** is `InputRouter.bridge_drives()`, never `Bridge.is_active()`.
- **Gameplay rays mask `Layers.SOLID`** (it omits `WorldBounds`); the seven layer bits are FROZEN.
- **Scene tags** (`src/levels/base/carlito_groups.gd`): every class joins its group in `_init`,
  not `_enter_tree`; kit/addons/tools discovery is a walk scoped to a named root, never
  `get_nodes_in_group()`. `has_method()` stays right for genuine capability probes.
- **A copy of an imported asset inside the project hijacks the original** (same `uid://`): keep
  backups outside the repo or `.gdignore` them; otherwise a tool edits the copy and reports success.
- **Bake-adjacent CODE is hashed explicitly** via `LevelBaker.BAKE_CODE_INPUTS`: editing a listed
  file re-stales every level (whole-line `.gd` comments are not hashed); a new one needs an entry
  and a `tools/git-hooks/bake_paths.txt` prefix; `BAKER_VERSION` bumps only when no hashed file moves.

## Running / testing / exporting

Godot **4.7.1-stable**, resolved `$env:GODOT_BIN` → `git config carlito.godotbin` → `godot` on
`PATH` (set the git-config one once per clone: the pre-commit hook sees it from every shell).
Use the **`_console.exe`** build for ALL CLI/headless runs. Generators: `tools/CLAUDE.md`.

```powershell
git config carlito.godotbin 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'; git config core.hooksPath tools/git-hooks  # once per clone
& $GODOT --headless --path . --import                       # import cache: once, and after adding assets
$env:GODOT_BIN = $GODOT; .\addons\gdUnit4\runtest.cmd -a tests   # suite; one: -a tests/test_truck.gd
& $GODOT --headless --path . --quit-after 120               # smoke; a challenge: --quit-after 300 -- --challenge=dev_box_stop
& $GODOT --headless --path . res://tools/bake_levels.tscn   # bake; stale check: check_bakes.tscn ("unbuilt" passes)
node tools/check_docs.mjs                                   # dangling refs + CLAUDE.md budgets
powershell -File tools/preflight.ps1                        # "am I safe to push?" — most CI gates
```

- Shadowing and integer-division warnings are **errors** (`project.godot` [debug]); intentional
  integer division needs `@warning_ignore`.
- A fresh worktree has no `.godot/` cache or `.baked.scn`: `--import` and bake before trusting a
  test there. Never run two headless Godots on one checkout at once.
- **Judge a headless run by its output, never its exit code.** Only `ERROR: N resources still in
  use at exit` is clean, as is `~130 ObjectDB instances leaked` after loading an island level.
- `--headless --script` runs only `extends SceneTree` scripts, and autoload identifiers do not
  compile there: anything loading a vehicle or level scene is a game-mode tool scene.
- A **freed node compares equal to null** — read results before `free()`.
- Vector2/3 math is **float32**: exact-boundary tests need ~1e-5 tolerance; gdUnit4 `is_equal` on
  a `FORMAT_RF`/`RGBAF` pixel holds only for binary-exact values, else `is_equal_approx`.
- **Parse-check `addons/`** with `--headless --path . --editor --quit-after 30` (it misses
  integer division between two *constants*).
- **`export_presets.cfg` traps fail only in an exported build**: `docs/deploying.md` § The web export.
