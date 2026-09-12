# Kit, bake & editor tools — gotchas & hard-won rules

Loaded when working under `kit/` (companion: `addons/carlito_kit/CLAUDE.md`; full authoring
detail: `docs/level_kit.md`). Bake freshness and `BAKE_CODE_INPUTS` stay in the root
`CLAUDE.md` — they apply everywhere.

- Regenerate palettes/prefabs (`gen_kit_assets.gd`) only after recipe/kit edits; meshlib
  item ids are preserved across regens so painted GridMaps never break. Every GLB must
  match a recipe family or the generator fails; excludes need a reason.
- Per-kit scales live in `kit/import/<kit>.json` (lane-fit rule: ~12 m two-lane vs the
  1.8 m car) — the recipe is the source of truth. Roads palette cell `(12,3,12)`; racing
  `(12,12,12)` corner-anchor. All palette GridMaps need `cell_center_y = false`. Roads:
  `road-curve` is a 2×2 sweep; `road-bend` is the 1×1 corner.
- Thumbnails render **windowed only** (headless can't render); never CI. Embedding a new
  thumb re-stales dependent bakes.
- **`--script`-mode tools cannot load level scenes** — autoload identifiers (InputRouter
  via BaseVehicle) don't compile there. Bake/check run as **game-mode tool scenes**
  (`godot --headless res://tools/bake_levels.tscn`), and `level.gd` reaches GameState via
  `get_node("/root/GameState")` for the same reason.
- A **freed node compares equal to null** — read results before `free()`.
- Vector2/3 component math is **float32**: `Vector2.angle()` carries ~1e-7 noise against
  float64 `PI`, so exact-boundary tests (`ceil(sweep / (PI/2))` etc.) need a ~1e-5
  tolerance — 1e-9 is not enough.
- The convex-decomposition helper is `create_multiple_convex_collisions` (plural).
- SurfaceTool.append_from leaves scaled normals unnormalized — the baker's
  SurfaceAccumulator merges at array level instead.
- A runtime-loaded `@tool` script must never use an editor-only class as a **type
  annotation**: annotations resolve at parse time regardless of `Engine.is_editor_hint()`,
  so the script silently fails to load in exported builds. Fetch editor singletons via
  `Engine.get_singleton(&"EditorInterface")` into **untyped** vars. Scripts under
  `addons/carlito_kit/` are editor-only and may type editor APIs freely.
- **Scene tags are GROUPS** (`carlito_authoring` / `carlito_kit_piece` / `carlito_scatter` /
  `carlito_road`), declared once in `src/levels/base/carlito_groups.gd` and joined in each
  class's **`_init`** — never class_name checks, and never `_enter_tree`: the baker walks a
  level scene that was never added to a tree and instantiates scatter templates loose, so
  `is_in_group()` is the only test that works there. `get_tree().get_nodes_in_group()` is NOT
  a substitute in editor or baker code — out of the tree it finds nothing, and in the editor
  `get_tree()` holds every open scene. Discovery there stays a walk scoped to a named root
  (`CarlitoGroups.find_authoring` / `.authoring_ancestor`, the one copy of each).
- Terrain render mesh is chunked for frustum culling (not LOD); collision stays ONE
  `HeightMapShape3D`. Normals are analytic (per-chunk `generate_normals()` seams
  borders); UVs global. Splatmap sampled raw (no `source_color` — sRGB bends weights).
- Scatter: stored transforms in the .tscn are the only artifact (no expansion at
  bake/runtime). Ground snap drops un-snappable points (no Y=0 fallback). The
  stale-scatter ground-hash guard is a config warning + bake gate + CI check; **Re-snap
  to ground** is the recovery. Weld-mode prefabs in scatter are a bake error.
- Roads: ribbon derives from curve + profile alone (never reads terrain); custom frame
  (NOT `sample_baked_with_rotation` — parallel transport accumulates roll). Profile
  default is a plain property set in editor `_ready`, never a preload export default
  (equal-to-default is omitted from the .tscn = input-hash hole). Conform flattens the
  **full half-width incl. skirt**, projects targets onto the nearest centerline
  **segment** (nearest-sample is wrong on grades), floor-quantizes to 8-bit; `edge_drop`
  must absorb ε + height/255 (conform warns). Tight turns fold-clamp the inside edge
  (never self-overlaps); closed loops share one bisector end frame. Full detail incl. the
  draw panel's "Smooth corners" behavior: `docs/level_kit.md`.
- Rails are a RoadPath carrying `RailProfile` (`kit/roads/rail_profile.tres`, gauge 1.44 m
  = the Kenney train kit at scale 2.4) — Draw/Drape/Smooth/Conform/bake all apply
  unchanged; the Roads panel's **Rail** checkbox swaps the profile. Its rib walls are
  vertical, so its cross-section drops degenerate strips on **both** axes, never the
  parent's lateral-only test. A baked level frees `AuthoringRoot` and export strips it, so
  the baker emits a `RailTrack` (`src/levels/base/rail_track.gd`) per rail road carrying
  the curve the train needs at runtime; the baker composes `rail_local_xform()`, consumers
  use `rail_to_world()`. Rail discovery is `has_method("get_rail_curve") and
  get_rail_curve() != null`, never a marker method — `has_method` is static, and a
  city-profile road must be able to say "not a rail". `RoadBuilder.is_closed_loop` is the
  ONE closed-loop predicate, `RailTrack.find_closed_rail(root)` the ONE walk that finds a
  loop; `Level._spawn_vehicle`, `TrainVehicle._find_rail` and `Level.has_closed_rail()` all
  call it, so no open-rail fallback can let the train run where the level refuses to spawn
  it. The selector shows the train family REFUSED ("no closed rail loop here") rather than
  dropping it; that gate is runtime, not `LevelInfo`. **Decided, don't re-open:** two closed
  loops in one level is out of scope, and `rail_track.gd` stays in `src/levels/base/` beside
  its runtime consumers — which is why a `src/` path sits in `BAKE_CODE_INPUTS` and a
  comment-only edit to it re-stales every level. Touch: the train hides the steering joystick
  and shows PANTO/DOORS taps (family-gated + bridge-hidden like ARM/FLAPS).
- `tools/gen_rail_level.gd` owns level 5 end to end (terrain, loop curve, conform, splat,
  scene) and overwrites it on every run; `tools/gen_skyport.gd` owns level 6 the same way
  (three stages: `scaffold` → `--import` → `props` → `--import` → bake → `probe`, and
  `scaffold` REWRITES the .tscn, so a re-run always needs `props` after it);
  `tools/gen_car_arena.gd` owns the car challenge arena AND its course scenes (`scaffold` →
  `--import` → `courses` → bake; `courses` rewrites every course `.tscn`, hand edits included);
  `tools/gen_islands.gd` covers only levels 2-4 and **must not be re-run** (levels 2/3 have
  hand-added PlaneSpawns its template would drop).
- Authoring order: terrain → roads + conform → splat → scatter (conform trips the scatter
  stale guard by design).
- **The `.baked.scn` is gitignored build output; the `.bake.json` beside it is committed.**
  CI bakes every registered level right after the stale-bake check, so a full bake costs git
  nothing — only the seven manifests move, and on a no-op re-bake only their hashes do. It costs
  CI ~2 s of a ~95 s build job (measured 2026-09-05), which is why the step is not cached.
  `bake_levels` rewrites EVERY level's `.baked.scn` with different bytes even when nothing
  changed (same `input_hash`, new `output_hash`; the pack is not byte-deterministic), which
  is why the manifest `stats` block, not the output bytes, is the comparand that proves a
  refactor changed no output. Bake a single level with `-- src/levels/<level>.tscn`; a full
  run takes minutes. **Run `bake_levels.tscn` once after cloning** — until then levels play
  unbaked (a `push_warning` from `Level._setup_baked` says so), local perf reads nothing like
  the shipped build, and the suite's bake-weight assertion fails.
- COMPROMISE: colormap `451b163d` ships three byte-identical times (garage, parked, kenney
  vehicles; ~700 KB raw). Deleting a copy silently reverts (each `.glb` re-resolves its sibling
  `Textures/` on every bake); undoing it costs GLB surgery or content-hash dedup in the baker.
