# Making a level

Tool reference (every button, every gotcha): `docs/level_kit.md`. Runtime systems a level
plugs into: `docs/systems.md`. Worked example: `src/levels/island/level_1/`; levels 2-4 are
the same scaffolding with different seeds; levels 5-6 (railway, drone skyport) are each owned
end to end by their own generator (`tools/gen_rail_level.gd`, `tools/gen_skyport.gd`).

A level is a **signal playground**, not a mission — grades for `engine_load`, hairpins for
slip. Everything below happens in the Godot editor's **"Kit" bottom panel** (Palette /
Terrain / Scatter / Roads tabs).

## 0. New scene + LevelInfo

1. Duplicate `src/levels/base/level.tscn` into `src/levels/<yourlevel>/`: ships
   `WorldEnvironment`, `Sun`, `ChaseCamera`, one `Spawn` marker.
2. Create a `LevelInfo` `.tres` (`src/levels/base/level_info.gd`), assign to the root
   `Level` node's `info`: `display_name`, `allowed_vehicles` (contract vehicle tags —
   `car`/`truck`/`tractor`/`boat`/`drone`/`plane`/`train`; empty = allow all),
   `default_vehicle` (must be in the allow-list).

## 1. Ground

- **Flat level:** a plain box `StaticBody3D` for ground is enough.
- **Terrain:** add a `HeightmapTerrain`, pick a preset, set
  `gen_seed`/`feature_scale`/`gen_octaves`/falloff band/`coast_roughness`/`terrace_levels`/
  `height` (51 stores 3 m levels byte-exactly), **Generate terrain**. Knob detail:
  `level_kit.md` § Terrain generation & splat ground.
- **Sync to the road GridMap:** terrain Y on the 3 m lattice; `height = 765 / n` — 25.5,
  30.6, 38.25, 42.5, 45, 51, 63.75, 76.5, 85, 153; `terrace_levels` sets plateau size
  (`n × 3 m`, 0 = off); ramps still need **Conform terrain**. Sculpt with the terrain
  brushes (full set: `level_kit.md` § Terrain brushes); "12 m (GridMap cell)" preset makes
  flush pads in one click.
- Water, if any: a `WaterSurface` sibling of the terrain (direct child, never under
  Authoring), at sea level, with an axis-aligned kill volume for drown-respawn. Add a
  `WorldBounds` node too (direct child): set `extent` to the water `size`;
  `ceiling_height`/`floor_depth` defaults are fine.

## 2. AuthoringRoot

Add one `AuthoringRoot` node named "Authoring" — everything the bake processes goes under it
(GridMaps, prefabs, roads, scatter); terrain and water stay outside it. Prefabs land in
per-kit `<Kit>Props` folders (plain identity `Node3D`s); GridMaps/RoadPaths/scatter stay
top-level. **Tidy authoring** (palette toolbar) sorts a flat AuthoringRoot into those
folders. Detail: `level_kit.md` § Authoring model.

## 3. Roads

- **Organic routes:** add a `RoadPath` (under Authoring) → Roads tab → Draw mode
  (`city`/`asphalt`/`gravel` presets); flatten under it with Conform terrain. Detail:
  `level_kit.md` § Draw mode and drape, § Ports and port snapping.
- **City grids:** Palette tab → roads kit → paint the built-in GridMap. Cell `(12,3,12)`;
  `road-curve` = 2×2 sweep, `road-bend` = 1×1 corner. Conform terrain (palette toolbar)
  flattens the pad under painted tiles and prefab buildings.
- **Rails:** Rail checkbox (Roads tab) swaps the `RoadPath` profile to track. Close the loop
  for a train; add `"train"` to `allowed_vehicles`. Level 5 (`tools/gen_rail_level.gd`) is
  the worked example.

## 4. Splat (terrain color)

Terrain tab: Auto-splat classifies grass/dirt/sand/rock from slope + height, then hand-paint
any of the 8 channels. Channel table, `channel_names`, `blend_sharpness`: `level_kit.md`
§ Terrain generation & splat ground. Splat after roads/conform, so conform's height edits
are reflected.

## 5. Scatter

Vegetation and clutter, ground-snapped and seeded:

- **Mass fill:** `ScatterRegion` (under Authoring) — box/polygon footprint, `items` (each a
  `ScatterItem` with prefab PackedScene + weight + collision toggle), density/
  `placement_seed`/spacing/jitter/slope knobs → Regenerate.
- **Hand-dressing:** `ScatterCanvas` + the scatter brush (Paint/Erase/Rect) on the Scatter
  tab. `paint_pattern` = `grid` + `grid_step` gives world-anchored lattice placement.

Scatter comes last (terrain → roads + conform → splat → scatter): a later edit trips the
stale-ground guard — recover with **Re-snap to ground** or Regenerate; mechanism:
`level_kit.md` § Scatter.

## 6. Prefab dressing

Buildings and props: Palette tab → pick a kit/family → click a thumbnail to arm, then
click-to-place into its kit's `<Kit>Props` folder under Authoring. `weld` prefabs join the
level-wide drivable body at bake — never inside scatter (bake error). Full `collision_mode`
set: `level_kit.md` § Authoring model.

## 7. Spawns

Drop a `VehicleSpawn` marker for every allowed vehicle. Set its `vehicle_types` filter; set
`is_water = true` for boat spawns (gizmo turns blue). Spawn validation is a bake gate.

## 8. Register, playtest, bake

1. Add an entry to `src/shell/level_registry.gd` (`id`/`name`/`scene`/`desc`; `dev: true`
   hides it from level-select but keeps CI bake/check + smoke coverage).
2. **Playtest unbaked** — F6 the scene; authoring content plays on dev collision
   (RoadPath/scatter trimesh + prefab `DevCollision`). The user verifies by driving.
3. **Bake** (button on the AuthoringRoot): writes `<level>.baked.scn` + `<level>.bake.json`;
   commit the manifest, `.baked.scn` is gitignored build output CI rebuilds.
4. **Record the chain** in `src/levels/<yourlevel>/<id>_gen.json` if any CLI tool touched the
   level: tools, args, `--import` passes, and a `manual` step for editor work no tool
   reproduces. Set `"replayable": false` with a `blocked` reason if a re-run would delete
   hand work. Replay: `powershell -File tools/rebuild_level.ps1 -Level <id>`
   (`level_1_gen.json` is the worked example). A non-idempotent sculpt step moves a few
   pixels per replay, so a changed PNG is classified, not flagged: `tools/png_drift.gd`
   reports e.g. "187 px moved of 263169, max 2 step(s)" against an optional
   `"sculpt_drift"` map (`{"<source>.png": {"max_px": N, "max_step": N}}`); no entry = byte
   equality.

## 9. Perf check

Check the F3 overlay in the worst view — deployed web build's frame rate, not the editor's;
draw calls are the first thing to read when it's low. Bake stats predict the base count
(chunk surfaces + scatter multimeshes + terrain chunks); the multiplier is the shadow pass —
`Sun` defaults to 4-split PSSM, overkill for a 150 m `directional_shadow_max_distance`. Cheap
levers: Sun `directional_shadow_mode = ORTHOGONAL` (single cascade, the islands; ~7 cm texels
over 150 m, which is why rule 9 keeps the web sun at soft quality 1 rather than hard).
`PARALLEL_2_SPLITS` looked finer but dropped building shadows while driving through a city —
unexplained, do not reuse without a repro. `ScatterItem.cast_shadow = false` on small vegetation (baked MultiMeshes
skip the shadow pass entirely, MultiMesh path only). If a level is heavy on the base count,
suspect its bake before touching renderer settings.

## Before you finish

- **Shoot the level-select card** (after baking): fly the 3D viewport to a flattering view,
  then Polish tab ▸ Set thumbnail view ▸ Shoot thumbnail. Commit `<level>_shot.tres` +
  `src/ui/level_thumbs/<id>.png`.
- **Re-bake + `check_bakes`** — stale bakes are the #1 repeat CI failure:
  ```
  & $GODOT --headless --path . res://tools/bake_levels.tscn
  & $GODOT --headless --path . res://tools/check_bakes.tscn
  ```
- Sweep new GDScript warnings; run `powershell -File tools/preflight.ps1` for the full local
  CI gate.
- Never commit or push unless explicitly asked.
