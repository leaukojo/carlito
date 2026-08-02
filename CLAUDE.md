# CLAUDE.md

Guidance for Claude Code sessions in this repository.

## What this is

**Carlito** — a browser-based CAN-bus driving sandbox: drive vehicles (car / truck /
tractor / boat / bike / drone / plane / train) while exchanging live CAN signals with the
sloppyCAN/RAMN simulator over a postMessage bridge. Godot 4.7, web-first. Levels are
**signal playgrounds** — no missions; content exists to make contract signals visibly
perform (grades for `engine_load`, hairpins for slip, fields for hitch/PTO, water for
pitch/roll).

Docs: `overview.md` (architecture map) · `HUMAN_EXPLANATIONS.md` (plain-language intro) ·
`systems.md` (runtime systems detail) · `level_kit.md` (authoring kit, terrain/scatter/
roads, bake pipeline) · `making_a_level.md` (author walkthrough) · `deploying.md` (the two
channels, the promote ritual) · `TODO.md` (remaining work).

The previous generation (Godot 3-era layout) survives only as a backup outside the project,
at `../CARLITO_SLOPPYCAN_V1_BACKUP/carlito/`. **Never read or copy v1 code** — it is a
behavior/layout reference only.

## Working style (learned the hard way — global CLAUDE.md covers the rest)

- **Act as a senior Godot dev, no workarounds.** Use the engine's real tools (GridMap/
  palette for tiling, never hand-placed piles of nodes; if headless blocks the right
  approach, script it correctly). Measure asset footprints against the 1.8 m car before
  placing — never guess scale/orientation.
- The user verifies **by driving**: any demo/verification scene must be a real Level with
  a VehicleSpawn (F6-runnable, unregistered), never camera-only. Visual bar: crisp
  high-contrast splat borders (low-poly style), plateaued buildable terrain, coasts made
  circular by water at sea level — never the square map edge.
- "Quickly / do not verify" = skip ceremony, make the small change, stop.
- **Before ending any authoring/kit/level change: re-bake + `check_bakes`** — stale bakes
  are the #1 repeat CI failure. After contract edits: `node tools/gen_js_contract.mjs`.
  Always sweep new GDScript warnings (shadowed identifiers like `load`/`basis`/`range`,
  integer division).
- Keep docs/memory present-state only (no phase history).

## Layout

Autoloads (keep this the whole set): `Contract`, `Bridge`, `InputRouter`, `GameState`.
ALL input arbitration lives in `src/input/`.

## Standing rules (permanent — numbering is referenced from `docs/` and `plans/`)

1. Static world geometry ships **baked per chunk** (merged meshes, one collision body per
   chunk); GridMaps are authoring-only. A drivable structure is never split across chunks —
   all drivable geometry welds into one level-wide body. Bakes are hash-stamped; CI fails
   on stale bakes.
2. Ground = heightmap/plane collision; drivable structures get dedicated welded collision
   meshes; props get boxes/hulls. **Trimesh is the exception, never the default.**
3. Telemetry is read out of the sim that produced the motion — no derived fictions (RPM
   comes from the drivetrain). Aux systems (fuel/coolant/battery, engine_load, trim) are
   simple *honest models*, clearly labelled.
4. One contract file; everything else generated from or validated against it. Never
   hand-duplicate signal lists.
5. Vehicles consume one normalized `VehicleInput` from `InputRouter`; arbitration
   (bridge-active/gear-owns-direction, brake > accel > handbrake) lives **only** there.
6. Levels, vehicles, and UI are independent scenes composed by the shell — no giant
   main.tscn.
7. CI does the export; deploys are cache-busted. No manual deploy.
8. Pure logic (drivetrain math, contract encode/decode, arbitration, GPS/odometer,
   buoyancy, terrain/scatter/road/bake math) gets gdUnit4 tests.
9. `.web` project-setting overrides + perf budget: msaa_3d.web=0, soft shadows off on web;
   do **not** set `scaling_3d/scale.web` below 1 (it adds an upscale pass on
   gl_compatibility and measures worse). Physics: **60 Hz + interpolation, locked** — the
   suspension tuning is rate-dependent; changing the tick means re-tuning every vehicle.
10. **No emoji anywhere in UI** — the web font has no emoji glyphs; plain text + color only.

Perf guardrail: < ~500 draw calls in the worst view (F3 overlay). Editor UX lives in
`addons/carlito_kit/` only; data + runtime-safe logic in `kit/` — nothing the baker touches
may use editor APIs (CI bakes headless). Authoring tools are deterministic (seeded) and
destructive-by-button, never per-frame. Third-party level sharing is out of scope: a
`.tscn` can embed scripts, so loading a stranger's level is arbitrary code execution.

Non-goals: multiplayer, in-game level editor, walk-around character, crop/farm simulation,
real wave physics, mobile app stores, world streaming, texture-layer terrain, LOD, road
junctions, lane markings, traffic.

## Gotchas & hard-won rules

**Physics & vehicles** — detail in `src/vehicles/CLAUDE.md` (loads when you open a vehicle
file). Always-on: subclasses use only the two seams — never fork `_physics_process`.

**Input, lamps, bridge**

- Lamp and ISOBUS state ride `VehicleInput`, never a side channel. Bridge lamp/warning
  bits are mirrored **verbatim** (sloppyCAN is the sole authority; absent bit = off);
  **there is no local blink timer** — turn lamps blink because the source toggles the bit.
- Toggle owners (`_lights`, `_hitch_up`, `_pto`) live in InputRouter; sources report
  per-frame edges — so keyboard and touch share one owner.
- The `rudder` in-signal overrides `steer` when present; the boat's rudder IS the steer
  channel (no new VehicleInput field).
- The bridge shim rides the web export's **Head Include**, and the export uses a **custom
  HTML shell** (`src/bridge/web/head_include.html`, `src/bridge/web/shell.html`). Both are
  vendored copies that must be kept in sync with `export_presets.cfg` / the Godot export
  template — **read `docs/deploying.md` § The web export before touching either, or before
  a Godot upgrade.**
- Bridge publish walks `Contract.signals_for_vehicle(...)` × `to_bridge_dict()` — never a
  hand-written field list. A `test_telemetry` case fails if `to_bridge_dict()` stops
  covering a ground "out" signal.
- `status` bitfield layout is provisional (named `ST_*` bits) until CAN frame packing is
  finalized with sloppyCAN.
- Respawn zeroes the telemetry accel history so a teleport isn't read as an impact.

**Dashboard & UI**

- The dashboard is contract-informed, not a UI generator: lamps/bars are **generated**
  from contract metadata (bars = range + warn, or `flavor == "isobus"`); the two radial
  gauges are **hand-built** and only read scale/redline from the contract. Do not build a
  from-JSON gauge framework. Gauges are built only when the vehicle declares their signal
  (the boat gets a speedo, no tacho). Gauge text sits in the arc's bottom 90° gap.

**Contract** — `contract/carlito_contract.json` (v19) defines every bridge signal; the
`Contract` autoload loads + validates it at startup and everything (bridge marshaling,
dashboard generation) is driven by it. Full protocol in `docs/systems.md`.

- Signals are unique by **(name, dir)** — `battery` exists in both directions. `warn` is
  the dashboard danger threshold; `SignalDef.warn_is_low()` infers the side **from the
  range midpoint**, so a high-side threshold must sit ABOVE it or the dashboard highlights
  the safe end (`wheel_slip` warns at 60 of 0–100, not 30).
- A flavored "out" signal with a `range` becomes a generated dashboard bar. **Omit the
  range** for one with no meaningful full scale (`engine_hours` — an hour meter is a running
  total) and it lands on the readout line beside ODO instead.
- Edits bump `version` and **must be followed by `node tools/gen_js_contract.mjs`** (the
  synced sloppyCAN copy; the runtime version-mismatch warning — **not CI** — is the drift
  guard).
  **A contract edit is a paired change across two repos** — the bump lands on the `dev`
  branch of both `carlito` and `sloppycan`, and both are promoted to stable together, or a
  live stable pair sits on mismatched versions and signals are misread.

**Levels & water**

- `HeightmapTerrain`: one cell = one world unit so mesh/collision coincide; heightmap +
  splat PNGs must import **lossless / no mipmaps** so runtime `get_image()` works.
  Generated PNGs additionally need `detect_3d/compress_to=0` (else silent VRAM
  recompression breaks `get_image()`) and `process/fix_alpha_border=false` (it corrupts
  splat weights where rock == 0) — `TerrainGen.ensure_import_settings` writes these.
- **A copy of an imported asset anywhere inside the project hijacks the original.** The
  copied `.import` sidecar carries the same `uid://`, so the import scan can resolve a
  level's texture to the copy — a tool then sculpts the copy while the real level is
  untouched and every downstream step still reports success. Keep backups outside the repo
  or drop a `.gdignore` in the folder (`tmp/` has one).
- **Level 1's splat channel 4 is "Field"** — the ploughable soil of the ISOBUS farm, and
  the *only* honest "in soil" predicate for the tractor's `draft_force`. Not Dirt (ch 1):
  Auto-splat paints Dirt on every slope on the island, so a draft test keyed on it would
  fire on hillsides. Channel 4 lives in `splatmap2`, which Auto-splat only ever zeroes, so
  it can never appear by accident. Re-running Auto-splat on level 1 wipes Field/Mud/Gravel
  AND the road asphalt — re-run `tools/gen_farm_playground.tscn` + `paint_road_asphalt.tscn`
  after, or don't.
- Water: `get_height()` is flat; shader waves are visual-only and **must never feed
  physics**. The kill volume is an axis-aligned rect — don't rotate the node. Water and
  terrain are direct children of the level, never under `Authoring`.
- Day/night is a Level concern (N key), not a bridge signal.
- **Level-select cards**: the screenshot camera is a side-car `<level>_shot.tres`
  (`LevelShot`), never a node — the level `.tscn` is a bake input, so a camera node would
  re-stale the bake on every re-frame. Cards are shot from the Polish tab (or
  `tools/gen_level_thumbs.tscn`, **windowed only**) and land in `src/ui/level_thumbs/` —
  they must stay under `src/`, since `kit/thumbs/*` and `tools/*` are export-excluded and
  level-select needs them at runtime. The shot runs the BAKED level: bake first or you ship
  stale geometry on the card.
- Under `--headless` the shell auto-loads the first registry level (CI smoke can't click).

**Kit, bake & editor tools** — detail in `kit/CLAUDE.md` (also imported by
`addons/carlito_kit/` and `tools/`); authoring walkthrough in `docs/level_kit.md`.
Always-on: bake-adjacent CODE reaches no resource dependency edge — GDScript reports none —
so it is hashed explicitly via `LevelBaker.BAKE_CODE_INPUTS`. Editing one file on that list
re-stales every level on its own; still bump `BAKER_VERSION` for semantic changes, and
re-bake either way. A new bake-adjacent file means a new entry in that list.

## Running / testing / exporting

Godot **4.7.1-stable**. The binary is never hardcoded — the tooling resolves
`$env:GODOT_BIN` → `git config carlito.godotbin` → `godot` on `PATH` → a clear error.
**Set the git-config one once per clone**; it is the only form the pre-commit hook can see
(git runs hooks with a bare environment, so a `$env:GODOT_BIN` from your shell is invisible
there — that is what "Godot not found" on commit means):

```powershell
git config carlito.godotbin 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'
```

**Use `Godot_v4.7.1-stable_win64_console.exe` for ALL CLI/headless runs** — the console
build streams print/push_error back; the plain exe is for visually running the game.

```powershell
$GODOT = $env:GODOT_BIN   # e.g. setx GODOT_BIN "<...>\Godot_v4.7.1-stable_win64_console.exe"

# one-time / after adding assets: build the .godot import cache
& $GODOT --headless --path . --import

# run the gdUnit4 suite (CI can't use runtest.sh — it launches Godot without
# --headless and dies on the display-less runner; ci.yml calls GdUnitCmdTool
# directly with --headless --ignoreHeadlessMode, safe for pure-logic suites)
$env:GODOT_BIN = $GODOT; .\addons\gdUnit4\runtest.cmd -a tests

# headless smoke (boots boot.tscn; --quit-after counts frames)
& $GODOT --headless --path . --quit-after 120

# level kit: regenerate palettes/prefabs (after kit/import recipe edits only)
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# vehicle selector cards (WINDOWED; every variant + every implement/trailer, then re-import)
& $GODOT --path . res://tools/gen_vehicle_thumbs.tscn ; & $GODOT --headless --path . --import
# kit thumbnails (WINDOWED — no --headless; then re-import + regen to embed palette previews)
& $GODOT --path . res://tools/gen_thumbs.tscn ; & $GODOT --headless --path . --import
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# bake all registered levels / CI stale-bake check (game-mode tool scenes, NOT --script)
& $GODOT --headless --path . res://tools/bake_levels.tscn
& $GODOT --headless --path . res://tools/check_bakes.tscn

# vehicle acceleration / top speed / straight-line tracking on a flat full-grip strip
# (dev tool, never CI, always exits 0; `all` is minutes of wall clock — background it)
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- sedan-sports
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- all 45

# regen the sloppyCAN contract copy (after ANY contract edit)
node tools/gen_js_contract.mjs

# local web export (CI does the real one)
& $GODOT --headless --path . --export-release "Web" build/web/index.html

# "am I safe to push?" — all CI gates locally (editor-type gate, import, tests,
# stale-bake check, smoke, head-include sync, contract sync)
powershell -File tools/preflight.ps1
```

A pre-commit hook (`tools/git-hooks/`, installed via `core.hooksPath`) blocks editor-type
annotations, stale contract copies, head-include drift, and stale bakes at commit time. The
recurring GDScript warning classes (shadowing, integer division) are escalated to **errors**
in project.godot — intentional integer division needs `@warning_ignore("integer_division")`.

- A headless run ending with only `ERROR: N resources still in use at exit` is **clean** —
  harmless leak-at-exit noise, not a failure.
- `--headless --script` only runs `extends SceneTree` scripts; EditorScripts need
  File ▸ Run in the editor.
- **Parse-checking `addons/` code**: `& $GODOT --headless --path . --editor --quit-after 30`
  loads the enabled plugins and prints real `SCRIPT ERROR: Parse Error` lines — the only
  cheap gate for editor-only scripts (`--script` mode can't load them, `--import` doesn't
  compile them). Caveat: it does **not** catch integer division between two *constants*
  (`48 / 4` is folded silently), so still eyeball division on variables.
- **gdUnit4 float asserts vs. image formats**: `assert_float(img.get_pixel(..).r).is_equal(0.2)`
  FAILS ("Expecting 0.200000 but was 0.200000") — `FORMAT_RF`/`RGBAF` store float32, the
  literal is float64. Only binary-exact values (0.0, 0.25, 0.5, 0.75) compare with
  `is_equal`; anything else needs `is_equal_approx`.
- **`export_presets.cfg` is full of traps that only fail in an exported build** — the
  editor rewrites it on any UI export, `variant/thread_support` must stay `false` and PWA
  enabled, and excluding a whole `kit/raw/<pack>/` folder ships untextured levels. Nothing
  local reproduces any of it. **Editing that file means reading `docs/deploying.md` § The
  web export first.** Debug web-only breakage on the real build, in devtools.

## CI / deploy

`.github/workflows/ci.yml`: every push runs import → gdUnit4 → stale-bake check → headless
smoke (default boot + a baked-level run with `CARLITO_LEVEL: level_1`) → web export.

Two channels: **dev** (<https://leaukojo.github.io/carlito/dev/>, republished by CI on every
push to `dev`, the default branch) and **stable** (<https://leaukojo.github.io/carlito/>,
moved only by the manual *Promote dev → stable* workflow, which copies the approved dev
bytes rather than rebuilding). Never deploy by hand.

The whole ritual — why the two channels are `gh-pages` siblings, cache-busting, a bad
promote, the paired contract deploy, the web export preset — is `docs/deploying.md`.
