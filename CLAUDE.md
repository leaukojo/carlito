# CLAUDE.md

## What this is

**Carlito** — a browser-based CAN-bus driving sandbox: drive vehicles (car / truck /
tractor / boat / drone / plane / train) while exchanging live CAN signals with the
sloppyCAN/RAMN simulator over a postMessage bridge. Web-first. Levels are **signal
playgrounds**: content exists to make contract signals visibly perform
(grades for `engine_load`, fields for hitch/PTO, water for pitch/roll). **Challenges** are the
goal-driven, bridge-only exception that teaches CAN — the defs in `src/challenges/defs/` are the list.

Docs: `overview.md` (architecture map) · `HUMAN_EXPLANATIONS.md` · `systems.md` · `vehicles.md` ·
`heavy_vehicles.md` · `level_kit.md` · `making_a_level.md` · `deploying.md` · `TODO.md` ·
`to_investigate.md`.

Autoloads (the whole set): `Contract`, `Bridge`, `InputRouter`, `GameState`. The Godot 3-era
generation is a backup outside the project — a behavior/layout reference, never a source; a
Godot 3 idiom arriving here is a bug, not a shortcut.

## Working style (global CLAUDE.md covers the rest)

- **Act as a senior Godot dev, no workarounds.** Use the engine's real tools (GridMap/
  palette for tiling, never hand-placed piles of nodes). Measure asset footprints against
  the 1.8 m car before placing — never guess scale/orientation.
- The user verifies **by driving**: any demo/verification scene must be a real Level with
  a VehicleSpawn (F6-runnable, unregistered), never camera-only. Visual bar: crisp
  high-contrast splat borders (low-poly style), plateaued buildable terrain, coasts made
  circular by water at sea level — never the square map edge.
- "Quickly / do not verify" = skip ceremony, make the small change, stop.
- **Rituals are skills** (`.claude/skills/`): `contract-edit`, `level-edit` (ends on re-bake +
  `check_bakes`), `vehicle-feel` (recipe → regen → re-measure). Run the matching one.
- **Where things go** (one policy; `docs/overview.md` points here):
  - **CLAUDE.md** = the constraint, a ≤1-line why, and its guard (test / tool / hook). Only what
    binds work in its directory and is not obvious from the code.
  - **Code comment** = the constraint at its site. A COMPROMISE is stated there: what is true,
    and what undoing it costs.
  - **`docs/`** = derivations, dated figure tables, tours. A finished plan (or TODO item) is
    distilled here, plus at most one CLAUDE.md line, then deleted.
  - Everywhere: present tense, no history ("used to", "replaces", "Phase N adds"), no restating
    the code. "The old X" naming a RUNTIME value (last tick's fix) is present-state and stays.
  - "ALL" / "every" / "never" in docs states intent, not a verified invariant: check before
    quoting one.

## Standing rules (permanent — numbering is referenced from `docs/`)

1. Static world geometry ships **baked per chunk** (merged meshes, one collision body per
   chunk); GridMaps are authoring-only. A drivable structure is never split across chunks —
   all drivable geometry welds into one level-wide body. Bakes are hash-stamped; CI fails
   on stale bakes. The `.baked.scn` is **gitignored build output that CI bakes**; the
   `.bake.json` manifest beside it is the committed hash record — so **run
   `tools/bake_levels.tscn` once after cloning** (unbaked levels play on dev collision,
   `Level._setup_baked` warns, local perf means nothing, and the suite's bake-weight assertion
   fails).
2. Ground = heightmap/plane collision; drivable structures get welded collision meshes;
   props get boxes/hulls. **Trimesh is the exception, never the default.**
3. Telemetry is read out of the sim that produced the motion — no derived fictions. Aux
   systems (fuel/coolant/battery, engine_load, trim) are simple *honest models*, labelled.
4. One contract file; everything else generated from or validated against it.
5. Vehicles consume one normalized `VehicleInput` from `InputRouter` (lamp and ISOBUS state
   included, never a side channel); arbitration
   (bridge-active/gear-owns-direction, brake > accel > handbrake) lives **only** in `src/input/`.
6. Levels, vehicles, and UI are independent scenes composed by the shell.
7. CI does the export; deploys are cache-busted. No manual deploy.
8. Pure logic (drivetrain math, contract encode/decode, arbitration, GPS/odometer,
   buoyancy, terrain/scatter/road/bake math) gets gdUnit4 tests.
9. `.web` overrides + perf budget: msaa_3d.web=0, positional shadows hard on web, the sun at
   soft quality 1 (hard = one tap, edges shimmer as the camera moves); do **not** set
   `scaling_3d/scale.web` below 1 (adds an upscale pass on gl_compatibility, measures
   worse). Physics: **60 Hz + interpolation, locked** — suspension tuning is rate-dependent.
   The editor drops a setting equal to its default on any UI save, so the pin is asserted
   against the TEXT of `project.godot` (`tests/test_project_settings.gd`; `ProjectSettings`
   cannot tell pinned from missing) and restored by the pre-commit hook. Pin any future
   settings invariant the same way.
10. **No emoji anywhere in UI** — the web font has no emoji glyphs; plain text + color only.

Perf target: 60 fps in the worst view, measured on the DEPLOYED web build (F3 overlay); draw
calls are the first diagnostic to read there, not a budget to design against (nothing is
profiled on a real target device yet; download size: `docs/deploying.md` § Download size).
Editor UX lives in `addons/carlito_kit/` only; data + runtime-safe logic in `kit/` — nothing the
baker touches may use editor APIs (CI bakes headless). Authoring tools are deterministic
(seeded) and destructive-by-button, never per-frame.

Non-goals: multiplayer, in-game level editor, walk-around character, crop/farm simulation,
real wave physics, mobile app stores, world streaming, texture-layer terrain, LOD, spline-road
junctions, lane markings, traffic, third-party level sharing (a `.tscn` can embed scripts).

## Gotchas & hard-won rules

Nested rules load with their directory: `src/vehicles/` (+ `truck/`, `tractor/`, `drone/`,
`train/`, `kenney/`), `src/input/`, `src/ui/`, `src/bridge/`, `src/physics/`, `src/levels/`,
`contract/`, `kit/`, `tools/`.

- **Who drives** is `InputRouter.bridge_drives()`, never `Bridge.is_active()`.
- **Every gameplay ray masks `Layers.SOLID`**, which omits `WorldBounds`; the seven layer bits
  are FROZEN (`src/physics/CLAUDE.md`).
- **Scene tags** — `src/levels/base/carlito_groups.gd` declares the six SceneTree groups that say
  what a node IS (`carlito_authoring`, `carlito_kit_piece`, `carlito_road`, `carlito_scatter`,
  `carlito_level`, `carlito_payload`) and owns the one copy of each authoring walk. `preload`ed,
  never `class_name`d. **Every class joins its group in `_init`, not `_enter_tree`** — the baker
  walks level scenes that never enter a tree and instantiates scatter templates loose, so only
  `is_in_group()` works there. `get_tree().get_nodes_in_group()` is correct ONLY in the running
  game (in the editor `get_tree()` holds every open scene); discovery in kit/addons/tools code
  is a walk scoped to a named root. `has_method()` is still right for genuine CAPABILITY
  probes (`set_vehicle`, `grip_at`, `cycle_implement`, `set_attachment`, `accepts`).
- **A copy of an imported asset anywhere inside the project hijacks the original** (the
  `.import` sidecar carries the same `uid://`) — a tool then sculpts the copy while every
  step reports success. Keep backups outside the repo or drop a `.gdignore` (`docs/img/`).
- **Bake-adjacent CODE is hashed explicitly** via `LevelBaker.BAKE_CODE_INPUTS` (it reaches no
  resource dependency edge): editing a listed file re-stales every level (comments included), a
  new bake-adjacent file means a new entry, and `BAKER_VERSION` bumps only for a change no
  hashed file carries.

## Running / testing / exporting

Godot **4.7.1-stable**, resolved `$env:GODOT_BIN` → `git config carlito.godotbin` → `godot`
on `PATH`. **Set the git-config one once per clone** — it is the one form the pre-commit
hook sees from every commit path, shell, IDE or GUI ("Godot not found" on commit means this).
Use the **`_console.exe`** build for ALL CLI/headless runs (it streams print/push_error back);
the plain exe is for visually running the game. Generators and measure tools: `tools/CLAUDE.md`.

```powershell
git config carlito.godotbin 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'
git config core.hooksPath tools/git-hooks          # once per clone, or no pre-commit hook runs
$GODOT = $env:GODOT_BIN

# import cache (one-time / after adding assets)
& $GODOT --headless --path . --import

# gdUnit4 suite (runtest.sh omits --headless and dies on a display-less runner)
$env:GODOT_BIN = $GODOT; .\addons\gdUnit4\runtest.cmd -a tests
# ...one suite: -a tests/test_truck.gd

# headless smoke (boots boot.tscn; --quit-after counts frames)
& $GODOT --headless --path . --quit-after 120
# ...straight into a challenge (debug builds; CARLITO_CHALLENGE for F6; add --challenge-keys to drive it)
& $GODOT --headless --path . --quit-after 300 -- --challenge=dev_box_stop

# bake all registered levels / stale-bake check (game-mode tool scenes, NOT --script);
# check_bakes reads "unbuilt" (passes) when the .baked.scn is absent
& $GODOT --headless --path . res://tools/bake_levels.tscn
& $GODOT --headless --path . res://tools/check_bakes.tscn

node tools/check_orphans.mjs                      # public src/kit functions with no caller
node tools/check_docs.mjs                         # dangling paths/tests/plans/members in docs
& $GODOT --headless --path . --export-release "Web" build/web/index.html   # CI does the real one
# ...plus one --export-patch per island, or islands fall back to flatland: docs/deploying.md § Level packs
powershell -File tools/preflight.ps1              # "am I safe to push?" — most CI gates
```

A pre-commit hook (`tools/git-hooks/`) blocks editor-type annotations, stale contract copies,
head-include drift and stale bakes, and restores the 60 Hz pin. The recurring GDScript warning
classes are **errors** in project.godot — intentional integer division needs
`@warning_ignore("integer_division")`.

- A fresh git worktree has no `.godot/` import cache and no `.baked.scn`: `--import` and bake
  it before trusting a test result there. Never run two headless Godots on one checkout at once.
- Headless with no `--level=` / `CARLITO_LEVEL` boots `boot.gd`'s `DEFAULT_LEVEL`
  (`flatland`), not the first registry entry (the garage).
- **Judge a headless run by its output, never its exit code.** Ending with only
  `ERROR: N resources still in use at exit` is clean, as is `~130 ObjectDB instances leaked at
  exit` in any run that `load()`s an island level scene.
- `--headless --script` runs only `extends SceneTree` scripts, and autoload identifiers do not
  compile there, so nothing that loads a vehicle or level scene can be a `--script` tool: it is a
  game-mode tool scene (`bake_levels.tscn`). EditorScripts need File ▸ Run in the editor.
- A **freed node compares equal to null** — read results before `free()`.
- Vector2/3 component math is **float32**: exact-boundary tests need a ~1e-5 tolerance, and
  gdUnit4 `is_equal` on a `FORMAT_RF`/`RGBAF` pixel holds only for binary-exact values (0.25,
  0.5); else `is_equal_approx`.
- **Parse-checking `addons/` code**: `& $GODOT --headless --path . --editor --quit-after 30`
  prints real `SCRIPT ERROR: Parse Error` lines (it misses integer division between two
  *constants*). It — and any `--import` that actually re-imports — re-saves `project.godot` and
  drops the 60 Hz pin: `git checkout -- project.godot` after.
- **`export_presets.cfg` traps only fail in an exported build**: read `docs/deploying.md` § The
  web export before editing it.

## CI / deploy

Two channels: **dev** (<https://leaukojo.github.io/carlito/dev/>, republished by CI on every
push to `dev`, the default branch) and **stable** (<https://leaukojo.github.io/carlito/>,
moved only by the manual *Promote dev → stable* workflow). Never deploy by hand:
`docs/deploying.md`.
