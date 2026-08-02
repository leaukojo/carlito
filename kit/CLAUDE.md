# Kit, bake & editor tools — gotchas & hard-won rules

Loaded when working under `kit/` (companion file: `addons/carlito_kit/CLAUDE.md`).
Full authoring detail: `docs/level_kit.md`. The bake-freshness rule and the
`BAKE_CODE_INPUTS` rule stay in the root `CLAUDE.md` — they apply everywhere.

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
  via BaseVehicle) don't compile there; bake/check run as **game-mode tool scenes**
  (`godot --headless res://tools/bake_levels.tscn`), and `level.gd` fetches GameState via
  `get_node("/root/GameState")` for the same reason.
- A **freed node compares equal to null** — read results before `free()`.
- Vector2/3 component math is **float32**: `Vector2.angle()` carries ~1e-7 noise against
  float64 `PI`, so exact-boundary tests (`ceil(sweep / (PI/2))` etc.) need a ~1e-5
  tolerance — 1e-9 is not enough (bit the road-arc segment count).
- The convex-decomposition helper is `create_multiple_convex_collisions` (plural; renamed
  in 4.6).
- SurfaceTool.append_from leaves scaled normals unnormalized — the baker's
  SurfaceAccumulator merges at array level instead.
- A runtime-loaded `@tool` script must never use an editor-only class
  (`EditorUndoRedoManager`, `EditorFileSystem`, …) as a **type annotation** — annotations
  resolve at parse time regardless of `Engine.is_editor_hint()` guards, so the script
  silently fails to load in exported builds (the node does nothing). Fetch editor
  singletons via `Engine.get_singleton(&"EditorInterface")` into **untyped** vars.
  Scripts under `addons/carlito_kit/` are editor-only and may type editor APIs freely.
- Duck-typed markers (`is_carlito_authoring` / `is_carlito_kit_piece` /
  `is_carlito_scatter` / `is_carlito_road`) everywhere, never class_name checks.
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
  parent's lateral-only test. The train needs the CURVE at runtime, but a baked level
  frees `AuthoringRoot` at load and export strips it — so the baker emits a `RailTrack`
  (`src/levels/base/rail_track.gd`) per rail road into the baked scene. Rail discovery is
  `has_method("get_rail_curve") and get_rail_curve() != null` (never a marker method —
  `has_method` is static and a road with a city profile must be able to say "not a rail");
  the baker composes `rail_local_xform()`, runtime consumers use `rail_to_world()`.
  `RoadBuilder.is_closed_loop` stays the ONE closed-loop predicate. The train runs ONLY on a
  **closed** loop, and `RailTrack.find_closed_rail(root)` is the ONE walk that finds it —
  `Level._spawn_vehicle` (spawn gate), `TrainVehicle._find_rail` (self-placement) and the
  vehicle selector's gate (`Level.has_closed_rail()`) all call it, so they can't disagree on
  what a rail is (an open-rail fallback in one and not the other is the exact split that let
  the train run on track the level refused to spawn it on). The selector shows the train
  family REFUSED with "no closed rail loop here" rather than dropping it, so a level may list
  "train" in `allowed_vehicles`, play as an ordinary island where the loop is absent, and say
  so. The gate is runtime, not in `LevelInfo`. A level with two closed loops is out of scope
  (see TODO Rail follow-ups).
  Touch: the train hides the steering joystick (rail-guided) and shows PANTO/DOORS toggle
  taps (family-gated + bridge-hidden like ARM/FLAPS).
- `tools/gen_rail_level.gd` owns level 5 end to end (terrain, loop curve, conform, splat,
  scene) and overwrites it on every run; `tools/gen_islands.gd` covers only levels 2-4 and
  **must not be re-run** (levels 2/3 have hand-added PlaneSpawns its template would drop).
- Authoring order: terrain → roads + conform → splat → scatter (conform trips the scatter
  stale guard by design).
