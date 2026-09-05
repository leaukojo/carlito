# CLAUDE.md

## What this is

**Carlito** — a browser-based CAN-bus driving sandbox: drive vehicles (car / truck /
tractor / boat / drone / plane / train) while exchanging live CAN signals with the
sloppyCAN/RAMN simulator over a postMessage bridge. Web-first. Levels are **signal
playgrounds** — no missions; content exists to make contract signals visibly perform
(grades for `engine_load`, fields for hitch/PTO, water for pitch/roll).

Docs: `overview.md` (architecture map) · `HUMAN_EXPLANATIONS.md` · `systems.md` (contract,
input, telemetry/dashboard, bridge, lamps, shell, levels) · `vehicles.md` (framework, boat /
plane / drone / train) · `heavy_vehicles.md` (truck, trailer, tractor — J1939, ISO 11992,
ISOBUS) · `level_kit.md` (authoring kit, bake pipeline) · `making_a_level.md` ·
`deploying.md` (the two channels, the promote ritual) · `TODO.md`.

Autoloads (the whole set): `Contract`, `Bridge`, `InputRouter`, `GameState`. ALL input
arbitration lives in `src/input/`. The Godot 3-era generation is a backup outside the
project — a behavior/layout reference, never a source; a Godot 3 idiom arriving here is a
bug, not a shortcut.

## Working style (global CLAUDE.md covers the rest)

- **Act as a senior Godot dev, no workarounds.** Use the engine's real tools (GridMap/
  palette for tiling, never hand-placed piles of nodes). Measure asset footprints against
  the 1.8 m car before placing — never guess scale/orientation.
- The user verifies **by driving**: any demo/verification scene must be a real Level with
  a VehicleSpawn (F6-runnable, unregistered), never camera-only. Visual bar: crisp
  high-contrast splat borders (low-poly style), plateaued buildable terrain, coasts made
  circular by water at sea level — never the square map edge.
- "Quickly / do not verify" = skip ceremony, make the small change, stop.
- **Before ending any authoring/kit/level change: re-bake + `check_bakes`.** After contract
  edits: `node tools/gen_js_contract.mjs`. Sweep new GDScript warnings (shadowed
  `load`/`basis`/`range`, integer division).
- Keep docs/memory present-state only (no phase history). **A finished plan is DELETED, not
  filed** — so distil its durable conclusions into the relevant `CLAUDE.md` first, or they are
  lost outside git history. The same goes for a finished TODO item, and for a COMPROMISE:
  `docs/` is rationale-first, so a knowingly-imperfect decision described only where it is
  justified reads as settled — state what is true and what undoing it would cost, beside the
  code it constrains.
- **The same rule binds CODE COMMENTS.** A comment states the live constraint, never the
  edit that produced it: no "used to", no "this replaces", no "Phase 4 adds" — a plan that no
  longer exists cannot be looked up, and its promises go stale silently. Rewrite the history
  as the constraint it explains ("the damper clamp is sized for a 1/60 s step"); delete it if
  it explains only a past decision, since git has that. "The old X" describing a RUNTIME value
  (the previous pads, last tick's fix, a trailer that is no longer there) is present-state and
  stays.

## Standing rules (permanent — numbering is referenced from `docs/`)

1. Static world geometry ships **baked per chunk** (merged meshes, one collision body per
   chunk); GridMaps are authoring-only. A drivable structure is never split across chunks —
   all drivable geometry welds into one level-wide body. Bakes are hash-stamped; CI fails
   on stale bakes. The `.baked.scn` is **gitignored build output that CI bakes**; the
   `.bake.json` manifest beside it is the committed hash record — so **run
   `tools/bake_levels.tscn` once after cloning** (unbaked levels play on dev collision,
   `Level._setup_baked` warns, and the suite's bake-weight assertion needs a real file).
2. Ground = heightmap/plane collision; drivable structures get welded collision meshes;
   props get boxes/hulls. **Trimesh is the exception, never the default.**
3. Telemetry is read out of the sim that produced the motion — no derived fictions. Aux
   systems (fuel/coolant/battery, engine_load, trim) are simple *honest models*, labelled.
4. One contract file; everything else generated from or validated against it.
5. Vehicles consume one normalized `VehicleInput` from `InputRouter`; arbitration
   (bridge-active/gear-owns-direction, brake > accel > handbrake) lives **only** there.
6. Levels, vehicles, and UI are independent scenes composed by the shell.
7. CI does the export; deploys are cache-busted. No manual deploy.
8. Pure logic (drivetrain math, contract encode/decode, arbitration, GPS/odometer,
   buoyancy, terrain/scatter/road/bake math) gets gdUnit4 tests.
9. `.web` overrides + perf budget: msaa_3d.web=0, soft shadows off on web; do **not** set
   `scaling_3d/scale.web` below 1 (adds an upscale pass on gl_compatibility, measures
   worse). Physics: **60 Hz + interpolation, locked** — suspension tuning is rate-dependent;
   pinned in `project.godot` and asserted by `tests/test_project_settings.gd`, because the
   editor drops a setting equal to its default on any UI save.
10. **No emoji anywhere in UI** — the web font has no emoji glyphs; plain text + color only.

Perf target: 60 fps in the worst view, measured on the DEPLOYED web build (F3 overlay); draw
calls are the first diagnostic to read there, not a budget to design against (nothing is
profiled on a real target device yet — `TODO.md` § Perf pass). Editor UX lives in
`addons/carlito_kit/` only; data + runtime-safe logic in `kit/` — nothing the baker touches
may use editor APIs (CI bakes headless). Authoring tools are deterministic (seeded) and
destructive-by-button, never per-frame.

Non-goals: multiplayer, in-game level editor, walk-around character, crop/farm simulation,
real wave physics, mobile app stores, world streaming, texture-layer terrain, LOD, road
junctions, lane markings, traffic, third-party level sharing (a `.tscn` can embed scripts).

## Gotchas & hard-won rules

**Physics & vehicles** — shared rules in `src/vehicles/CLAUDE.md`, family rules nested beside
the code: `truck/` (trailers), `tractor/` (implements), `drone/`, `train/`, `kenney/` (the
generated bodies).

**Scene tags** — `src/levels/base/carlito_groups.gd` declares the six SceneTree groups that say
what a node IS (`carlito_authoring`, `carlito_kit_piece`, `carlito_road`, `carlito_scatter`,
`carlito_level`, `carlito_payload`) and owns the one copy of each authoring walk. `preload`ed,
never `class_name`d. **Every class joins its group in `_init`, not `_enter_tree`** — the baker
walks level scenes that never enter a tree and instantiates scatter templates loose, so only
`is_in_group()` works there. `get_tree().get_nodes_in_group()` is correct ONLY in the running
game (in the editor `get_tree()` holds every open scene); discovery in kit/addons/tools code
stays a walk scoped to a named root. `has_method()` is still right for genuine CAPABILITY
probes (`set_vehicle`, `grip_at`, `cycle_implement`, `set_attachment`, `accepts`).

**Input, lamps, bridge**

- Lamp and ISOBUS state ride `VehicleInput`, never a side channel. Bridge lamp/warning
  bits are mirrored **verbatim** (sloppyCAN is the sole authority; absent bit = off);
  **no local blink timer ANYWHERE** — a lamp flashes because the source toggles its bit,
  J1939-73 DM1 flash-1Hz / flash-2Hz included. `tests/test_lamps.gd` reads
  `src/vehicles/base/lamp_set.gd` and fails if a clock comes back.
- **`LampSet` binds its groups two ways and the accessor differs.** Head/brake/turn/LED share ONE
  canonical material per group on `mesh.material_override` (`_bind`); markers, flash and strobe get
  a PRIVATE duplicate of the mesh's own scene material on `set_surface_override_material(0, …)`
  (`_bind_scene_colored`), which is what lets red, green and white sit in one group. Read a marker
  back through `material_override` and you get `null` for a lens that is lit correctly — both
  `test_tow_host` and `test_trailer` go through a `_marker_mat()` helper that says so.
- **`VehicleInput` is a `class_name` in `src/input/vehicle_input.gd`, not an inner class of
  the autoload** — an inner class makes every vehicle's static types depend on the autoload's
  registered *name*. Its fields are **flat except `lamps`**: the router deliberately knows no
  vehicle family (rule 5), so every group is allocated for every machine. `input.lamps` earns
  its nesting on ONE RULE (the fourteen verbatim-mirrored bits above), not on one family, and
  has exactly two read sites (`BaseVehicle` → LampSet, `Dashboard._update_telltales`).
  `lights` is a level the router cycles, so it stays flat.
- **`get_vehicle_input()` returns the router's own struct, read-only by convention** — there
  is no defensive `copy()`, because a hand-written field mirror is a field that goes missing
  silently. `arbitrate_*` build a fresh struct each tick, so a stashed reference reads stale,
  never live; a caller that needs to keep or change one copies it itself.
- **The raw-intent wire is `Dictionary[StringName, Variant]`** across all four producers
  (`LocalSource`, `TouchControls`, `BridgeSource`, `measure_drone`'s `StickSource`) and
  `merge_local`. **StringName keys catch no typo at parse time** — the guard is two tests:
  `test_every_touch_poll_key_is_merged` (registry `poll_key` ⊆ merge) and
  `test_local_source_and_merge_local_carry_the_same_keys` (set equality). `merge_local` builds
  its dict explicitly, so a key on one side only silently drops the keyboard's edge while a
  touch source is registered. `arbitrate_local` / `arbitrate_bridge` stay plain `Dictionary`
  on purpose: they are the wire's consumers and `test_input_arbitration.gd` is their spec. An
  **untyped dict literal is rejected at the call**, not converted — a test passing one inline
  needs `_intent({...})` or a typed declaration.
- Toggle owners (`_lights`, `_hitch_up`, `_pto`) live in InputRouter so keyboard and touch
  share one owner; sources only report per-frame edges.
- **Cycled-control lengths are declared once in `src/input/subsystem_counts.gd`** (leaf, no
  dependencies, `preload`ed by both the router and the drone) — the router must not depend on a
  vehicle class, so it cannot read `RefuseBody.Cmd` / `DroneBus.NODES` / `DroneModes`. Where the
  length is intrinsic to a structure (an enum, the roster array) that structure stays the thing
  you edit and a test pins it against the constant; grow one without the other and the local key
  silently stops reaching the new position while the bridge can still command it.
- The `rudder` in-signal overrides `steer` when present (no new VehicleInput field).
- Bridge publish walks `Contract.data.signals_for_vehicle(...)` × `to_bridge_dict()`, and
  `to_bridge_dict` walks the telemetry's own property list — every member var of a telemetry
  class IS a wire signal (only the `WIRE_*` tables and the synthesised `slip` are not identity),
  pinned by `test_to_bridge_dict_invents_no_signal`.
- The bridge shim rides the web export's **Head Include**, and the export uses a **custom
  HTML shell** (`src/bridge/web/head_include.html`, `shell.html`). Both are vendored copies
  that must stay in sync with `export_presets.cfg` / the Godot export template — **read
  `docs/deploying.md` § The web export before touching either, or before a Godot upgrade.**
- `status` bitfield layout (`ST_*` in `src/vehicles/base/vehicle_telemetry.gd`) is the wire
  assignment and is **FROZEN**: a new flag APPENDS at bit 7 or above (nine free in the u16),
  an existing bit is **never** renumbered. Adding one bumps `version` and ships as a paired
  promote.
- Respawn zeroes the telemetry accel history so a teleport isn't read as an impact.

**Dashboard & UI** — detail in `src/ui/CLAUDE.md`.

**Contract** — `contract/carlito_contract.json` defines every bridge signal. Authoring rules
in `contract/CLAUDE.md`; full protocol in `docs/systems.md`.

**Collision layers** — `src/physics/collision_layers.gd` is the declaration, `preload`ed (never
`class_name`d: the baker and the measure tools run headless). The seven bits are **FROZEN** like
the `status` bitfield — they are written into `project.godot`'s `[layer_names]`, into every
`.baked.scn`, and into `cargo_payload.tscn`; a new layer APPENDS at bit 8+, none is renumbered.

- `SOLID` (everything but `Containment`) is the mask for EVERY gameplay ray. `Containment` is
  `WorldBounds` — invisible walls a few tens of metres off the coast reaching 1500 m up, so a ray
  that sees them measures the game's boundary instead of the world: the drone loses half its
  satellites over open water, and the chase camera pulls itself in at the beach. Widening a ray
  mask to include `Containment` brings both straight back.
- Moving bodies mask `WORLD`; static bodies mask `DYNAMIC`. Masks are deliberately generous — a
  too-narrow mask drops a body through geometry **silently**. Widen first, diagnose second.
- **The water kill volume is a layer pairing across two files**: `WaterSurface`'s mask names
  `VEHICLE` and `BaseVehicle`'s layer is `VEHICLE`. Break either and drowning stops with nothing
  to see; `tests/test_collision_layers.gd` is the only thing that catches it.
- Bodies take their layer in `_ready`, not in scenes — no `.tscn` hard-codes one. `CargoPayload`
  is the exception, authored in `cargo_payload.tscn`, because `_ready` is where it *remembers*
  the layer to restore on release.
- The authoring/editor ground-snap rays (`scatter_base`, `scatter_brush`, `ground_snap`,
  `flying_check`) stay unmasked on purpose: snapping to whatever is actually there is correct.

**Levels & water** — detail in `src/levels/CLAUDE.md`.

- **A copy of an imported asset anywhere inside the project hijacks the original** (the
  `.import` sidecar carries the same `uid://`) — a tool then sculpts the copy while every
  step reports success. Keep backups outside the repo or drop a `.gdignore` (`docs/img/`).

**Kit, bake & editor tools** — detail in `kit/CLAUDE.md`; walkthrough in
`docs/level_kit.md`. Always-on: bake-adjacent CODE reaches no resource dependency edge, so
it is hashed explicitly via `LevelBaker.BAKE_CODE_INPUTS` — editing one file on that list
re-stales every level, a new bake-adjacent file means a new entry, and a semantic change
still bumps `BAKER_VERSION`.

## Running / testing / exporting

Godot **4.7.1-stable**, resolved `$env:GODOT_BIN` → `git config carlito.godotbin` → `godot`
on `PATH`. **Set the git-config one once per clone** — it is the only form the pre-commit
hook can see ("Godot not found" on commit means this). Use the **`_console.exe`** build for
ALL CLI/headless runs (it streams print/push_error back); the plain exe is for visually
running the game.

```powershell
git config carlito.godotbin 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'
$GODOT = $env:GODOT_BIN

# import cache (one-time / after adding assets)
& $GODOT --headless --path . --import

# gdUnit4 suite (CI calls GdUnitCmdTool directly; runtest.sh omits --headless and dies on
# the display-less runner)
$env:GODOT_BIN = $GODOT; .\addons\gdUnit4\runtest.cmd -a tests

# headless smoke (boots boot.tscn; --quit-after counts frames)
& $GODOT --headless --path . --quit-after 120

# palettes/prefabs (after kit/import recipe edits only)
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# vehicle selector cards (WINDOWED; every variant + implement/trailer, then re-import)
& $GODOT --path . res://tools/gen_vehicle_thumbs.tscn ; & $GODOT --headless --path . --import
# kit thumbnails (WINDOWED; re-import, then regen to embed palette previews)
& $GODOT --path . res://tools/gen_thumbs.tscn ; & $GODOT --headless --path . --import
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd

# bake all registered levels / stale-bake check (game-mode tool scenes, NOT --script)
# the .baked.scn is gitignored; check_bakes reads "unbuilt" (passes) when it is absent
& $GODOT --headless --path . res://tools/bake_levels.tscn
& $GODOT --headless --path . res://tools/check_bakes.tscn

# accel + top speed on a flat full-grip strip: a dev report, exits 0, `all` takes minutes
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- sedan-sports 45
# the tracking half IS the CI `tracking` gate: skips the accel pass, exits 1 on a FAIL
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- all 45 track strict
# drone hover / climb / lean / endurance / one-motor-out (no args, ~1 min)
& $GODOT --headless --path . res://tools/measure_drone.tscn

node tools/gen_js_contract.mjs                    # after ANY contract edit
& $GODOT --headless --path . --export-release "Web" build/web/index.html   # CI does the real one
powershell -File tools/preflight.ps1              # "am I safe to push?" — all CI gates
```

A pre-commit hook (`tools/git-hooks/`, via `core.hooksPath`) blocks editor-type
annotations, stale contract copies, head-include drift, and stale bakes. The recurring
GDScript warning classes are **errors** in project.godot — intentional integer division
needs `@warning_ignore("integer_division")`.

- Headless with no `--level=` / `CARLITO_LEVEL` boots `boot.gd`'s `DEFAULT_LEVEL`
  (`level_1`), not the first registry entry (the garage).
- A headless run ending with only `ERROR: N resources still in use at exit` is **clean**.
- `--headless --script` only runs `extends SceneTree` scripts; EditorScripts need
  File ▸ Run in the editor.
- **Parse-checking `addons/` code**: `& $GODOT --headless --path . --editor --quit-after 30`
  loads enabled plugins and prints real `SCRIPT ERROR: Parse Error` lines. It does **not**
  catch integer division between two *constants* (`48 / 4` folds silently) — eyeball
  division on variables.
- **`ProjectSettings` in tests is not a presence check**: `get_setting(name, default)` falls back
  to the engine's built-in default, and `has_setting()` is true for every built-in setting even
  when `project.godot` never mentions it. A setting whose invariant *equals* its engine default
  (60 Hz *is* Godot's default tick) therefore reads identically pinned and missing, so rule 9
  reads enforced when it is not. `tests/test_project_settings.gd` asserts against the text of
  `res://project.godot`; pin any future settings invariant the same way.
- **gdUnit4 float asserts vs. image formats**: `assert_float(img.get_pixel(..).r).is_equal(0.2)`
  FAILS — `FORMAT_RF`/`RGBAF` store float32, the literal float64. Only binary-exact values
  (0.0, 0.25, 0.5, 0.75) compare with `is_equal`; else `is_equal_approx`.
- **`export_presets.cfg` traps only fail in an exported build, and nothing local reproduces
  them** — the editor rewrites it on any UI export, `variant/thread_support` must stay
  `false`, PWA enabled, and excluding a whole `kit/raw/<pack>/` folder ships untextured
  levels. **Editing it means reading `docs/deploying.md` § The web export first.**

## CI / deploy

Two channels: **dev** (<https://leaukojo.github.io/carlito/dev/>, republished by CI on every
push to `dev`, the default branch) and **stable** (<https://leaukojo.github.io/carlito/>,
moved only by the manual *Promote dev → stable* workflow, which copies the approved dev
bytes rather than rebuilding). Never deploy by hand. Full ritual: `docs/deploying.md`.
