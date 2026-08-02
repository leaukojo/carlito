# Making a level

A start-to-finish walkthrough for authoring one Carlito level. This is the author's
narrative; the tool reference (every button, every gotcha) is `docs/level_kit.md`, and the
runtime systems a level plugs into are `docs/systems.md`. Two small worked examples ship in
the tree: `src/levels/island/level_1/level_1.tscn` (a dressed, generated splat island with
car + boat spawns) and levels 2-5 beside it (the same island scaffolding, empty and
waiting to be authored).

A level is a **signal playground**, not a mission: build terrain and content that make
contract signals visibly perform — grades for `engine_load`, hairpins for slip, fields for
hitch/PTO, water for pitch/roll. Everything below is done **in the Godot editor**; the
addon's tools live in the **"Kit" bottom panel** (Palette / Terrain / Scatter / Roads tabs).

## 0. New scene + LevelInfo

1. Duplicate `src/levels/base/level.tscn` into `src/levels/<yourlevel>/`. It ships the
   pieces every level needs and nothing else: `WorldEnvironment`, `Sun`, `ChaseCamera`, and
   one `Spawn` marker.
2. Create a `LevelInfo` `.tres` (`src/levels/base/level_info.gd`) and assign it to the root
   `Level` node's **`info`** property. Set `display_name`, `allowed_vehicles` (contract
   vehicle tags — `car` / `truck` / `tractor` / `boat`; empty = allow all), and
   `default_vehicle` (must be in the allow-list). The garage roster and level-select label
   read this without loading the scene.

## 1. Ground

Two options:

- **Flat level:** a plain box `StaticBody3D` for ground is enough.
- **Terrain:** add a `HeightmapTerrain`. Selecting it jumps the Kit panel to the **Terrain**
  tab. Pick a preset (character: fractal + island falloff), set `gen_seed` /
  `feature_scale` / `gen_octaves` / falloff band / `coast_roughness` / `terrace_levels`
  (plateau band height in 3 m road-grid cells, so flats take painted road tiles flush), set
  **`height`** (world amplitude in metres; 51 stores the 3 m levels byte-exactly), then
  **Generate terrain**. **Generate new random
  terrain** rolls a fresh seed. Terrain needs **no AuthoringRoot** to sculpt.

**Generating in sync with the road GridMap** — so plateaus take painted tiles flush with
no Conform pass:

1. Keep the terrain node's **Y on the 3 m lattice** (normally 0; Generate warns if not).
2. Pick a **`height` that stores 3 m levels byte-exactly**: the 8-bit heightmap steps by
   `height/255` m, so 3 m is exact whenever `765 / height` is a whole number — i.e.
   `height = 765 / n`: **25.5, 30.6, 38.25, 42.5, 45, 51, 63.75, 76.5, 85, 153** …
   Any other height leaves up to ~`height/510` m of residual, hidden by the tile deck.
3. Pick **`terrace_levels`** for plateau size: bands are `n × 3 m` (3 = 9 m bands), always
   grid-aligned; 0 turns terracing off.
4. **Generate** (alignment is baked in at generation — changing `height` or moving the
   terrain afterwards rescales/shifts it, so regenerate after such edits).
5. Paint roads on plateau **interiors**; the ramps *between* plateaus are not
   grid-aligned — roads crossing them still need **Conform terrain**.

Sculpt with the terrain brushes (raise/lower/smooth/flatten, ramp): `[`/`]` resize, Shift
smooths, Ctrl inverts, the eyedropper samples a flatten height. Plateau the pads your
buildings and city grids will sit on — the **"12 m (GridMap cell)" preset** (12 m square,
edge softness 0, grid-snap) makes flush pads for the roads palette in one click.

Water, if any, is a **`WaterSurface`** sibling of the terrain (both direct children of the
level, never under Authoring). Put it at sea level — the below-sea sand ring reads as a
**circular coast** only because water covers the square map edge. Add its kill volume
(axis-aligned rect, never rotated) for drown-respawn.

## 2. AuthoringRoot

Add one **`AuthoringRoot`** node named "Authoring". **Everything the bake processes goes
under it** — GridMaps, prefabs, roads, scatter. Terrain and water stay outside it. Placement
tools refuse to arm without an AuthoringRoot. Placed prefabs land in per-kit **`<Kit>Props`**
folders (plain identity `Node3D`s the bake sees straight through); GridMaps / RoadPaths /
scatter stay top-level. **Tidy authoring** (palette toolbar) reorganizes an existing flat
AuthoringRoot into those folders in one undo step.

## 3. Roads

- **Organic routes:** add a `RoadPath` (under Authoring), select it → **Roads** tab → **Draw**
  mode. Click to lay points (Free auto-smooths, Straight for exact chords, Arc for 3-click
  circular arcs); a red ghost = a refused too-tight corner. **Close loop** / **Reverse
  direction** / **Drape curve onto terrain** as needed. The ribbon comes from curve + profile
  alone (`city` / `asphalt` / `gravel` presets) — it never reads terrain, so flatten the
  terrain under it with **Conform terrain** (destructive-by-button).
- **City grids:** use the **Palette** tab → roads kit → paint the built-in GridMap. Cell is
  `(12,3,12)`; `road-curve` is the 2×2 sweep, `road-bend` the 1×1 corner. **Conform terrain**
  (palette toolbar) flattens the pad under *every* painted tile GridMap **and** every placed
  prefab building (Commercial/Industrial/Suburban/Racing structures) to its base plane in one
  pass. Where tiles meet splines, use **ports** (Snap to ports on in Draw, or **Snap ends to
  ports** after gizmo edits).
- **Rails:** a rail is just a `RoadPath` with the **Rail** checkbox (Roads tab) ticked — it
  swaps the profile to the track (ballast + two ribs) and everything else (Draw, Close loop,
  Drape, Conform) works the same. Draw it as a **closed loop** (Close loop) if you want a
  train: the train self-places on the loop and the garage offers "train" only when one
  exists. Add `"train"` to the level's `allowed_vehicles`; the default spawn can stay a car.
  Level 5 is the worked example, generated by `tools/gen_rail_level.gd`.

## 4. Splat (terrain color)

Back on the **Terrain** tab: **Auto-splat** classifies grass/dirt/sand/rock from slope +
height (`sand_height` / `dirt_slope_deg` / `rock_slope_deg`), then hand-paint any of the 8
channels with the paint brush (fill bucket for a base coat). `blend_sharpness` keeps borders
crisp (low-poly look, not soft fades). Channel colors are the splat material's params; names
are the node's `channel_names`. Splat **after** roads/conform so conform's height edits are
reflected.

## 5. Scatter

Vegetation and clutter, ground-snapped and seeded:

- **Mass fill:** `ScatterRegion` (under Authoring) — box/polygon footprint, `items` (each a
  `ScatterItem` with a prefab PackedScene + weight + collision toggle), density /
  `placement_seed` / spacing / jitter / slope knobs → **Regenerate**.
- **Hand-dressing:** `ScatterCanvas` + the scatter brush (Paint / Erase / Rect) on the
  **Scatter** tab. **Rect** = click two corners to fill that XZ area at whatever height the
  ground under it is (Esc or right-click cancels). Set the canvas's `paint_pattern` to
  `grid` + a `grid_step` for lattice placement (corn rows, orchards, neat grass patches) —
  the lattice is world-anchored, so Paint and Rect extend the same grid seamlessly.

Scatter comes **last** (terrain → roads + conform → splat → scatter). Any later terrain or
road-conform edit trips scatter's **stale-ground guard** (config warning + bake gate + CI) —
recover with **Re-snap to ground** on the scatter node, or Regenerate.

## 6. Prefab dressing

Buildings and props: **Palette** tab → pick a kit/family → click a thumbnail to arm, then
click-to-place (sticky; right-click/Escape disarms) — each drop lands in its kit's
`<Kit>Props` folder under Authoring. Random-yaw / snap
toggles on the toolbar. Each prefab's `collision_mode` (`none|box|footprint|hull|multiconvex|weld`)
rides its root; `weld` prefabs join the level-wide drivable body at bake (never use `weld`
inside scatter — bake error).

## 7. Spawns

Drop a **`VehicleSpawn`** marker for every allowed vehicle. Set its `vehicle_types` filter;
set **`is_water = true`** for boat spawns (gizmo turns blue). Spawn validation is a bake gate
— a level whose allowed vehicles have no matching spawn fails the bake.

## 8. Register, playtest, bake

1. Add an entry to `src/shell/level_registry.gd` (`id` / `name` / `scene` / `desc` — the one
   line shown under the level-select card on hover; `dev: true` hides it from level-select
   but keeps CI bake/check + smoke coverage).
2. **Playtest unbaked** — F6 the scene; authoring content plays directly on dev collision
   (RoadPath/scatter trimesh + prefab `DevCollision`). The user verifies **by driving**, so
   confirm the level is actually drivable here.
3. **Bake** (button on the AuthoringRoot). This merges render meshes per chunk, welds all
   drivable geometry into one level-wide body, and writes `<level>.baked.scn` +
   `<level>.bake.json`. Commit the `.tscn`, `.baked.scn`, and `.bake.json` together.

## 9. Draw-call budget

Check the **F3 overlay** in the worst view (usually flying, where nothing is frustum-culled)
against the **< ~500 draw call** budget. The bake stats predict the base count: chunk
surfaces + scatter multimeshes + terrain chunks (`terrain_size / chunk_cells`, squared).
The multiplier on top is the **shadow pass** — every caster is re-drawn per shadow cascade,
and the `Sun` defaults to 4-split PSSM, which is overkill for a 150 m
`directional_shadow_max_distance`. Cheap levers, in order:

1. **Sun `directional_shadow_mode`** — `ORTHOGONAL` (single cascade, level 3 uses this) or
   `PARALLEL_2_SPLITS`. If near shadows get blocky, lower
   `directional_shadow_max_distance` before adding cascades back.
2. **`ScatterItem.cast_shadow = false`** on small vegetation (bushes, plants) whose shadow
   is barely visible — the baked MultiMeshes then skip the shadow pass entirely. MultiMesh
   path only: below-threshold items merge into chunk meshes, which always cast.

If a level is heavy on the *base* count, suspect its bake (chunk count / material dedup)
before touching renderer settings — see the perf-pass notes in `TODO.md`.

## Before you finish

- **Shoot the level-select card** (after baking — the shot runs the baked level): fly the 3D
  viewport to a flattering view, then Polish tab ▸ **Set thumbnail view** ▸ **Shoot
  thumbnail**. Commit `<level>_shot.tres` + `src/ui/level_thumbs/<id>.png`.
- **Re-bake + `check_bakes`** — stale bakes are the #1 repeat CI failure:
  ```
  & $GODOT --headless --path . res://tools/bake_levels.tscn
  & $GODOT --headless --path . res://tools/check_bakes.tscn
  ```
- Sweep new GDScript warnings; run `powershell -File tools/preflight.ps1` for the full local
  CI gate.
- Never commit or push unless explicitly asked.
