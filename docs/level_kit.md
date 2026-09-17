# Level kit — authoring tools & bake pipeline

Asset kits, editor tools, terrain, scatter, roads, and the bake that turns authoring content
into what ships. Runtime systems: `docs/systems.md`, `docs/vehicles.md`,
`docs/heavy_vehicles.md`; walkthrough: `docs/making_a_level.md`; gotchas: `kit/CLAUDE.md`,
`src/levels/CLAUDE.md`. Editor UX: `addons/carlito_kit/`; data + runtime-safe logic: `kit/`
(`@tool` scripts, pure unit-tested cores). No `EditorInterface` where the baker touches —
game-mode tool scenes bake in CI.

## Kit assets & recipes

`kit/raw/<kit>/` (7 kits: racing / roads / suburban / commercial / industrial / watercraft /
nature) + `kit/import/<kit>.json` recipes generate `kit/palettes/*.meshlib` +
`kit/prefabs/<kit>/*.tscn` via `tools/gen_kit_assets.gd` (`--script`; re-run after
recipe/kit edits). Logic: `kit/helpers/kit_recipe.gd` (`tests/test_kit_gen.gd`), one ordered
`families` list per recipe. Coverage gate: every GLB must match a family or the generator
fails; excludes need a `reason`.

| Field | Meaning |
|---|---|
| `name` / `label` | family id / dock section label |
| `match` | list of regex, first match wins |
| `pipeline` | `"palette"` \| `"prefab"` \| `"exclude"` |
| `collision_mode?` | overrides the piece's default collision mode |
| `reason?` | required when `pipeline` is `"exclude"` |
| `assets` | `{<name>:{overrides}}`, per-asset override map |

`{"manual": true}` on a family asset opts a prefab out of regen (still counts for coverage):
`roads/sign-highway{,-wide,-detailed}`, `commercial/building-{a,c}`. Generated files keep
their existing `uid://` (`gen_kit_assets._keep_uid`).

**Scales and thumbnails.** Lane-fit rule and palette cell sizes: `kit/CLAUDE.md`. Racing:
cubic `(12, 12, 12)`, corner-anchor, bridge y-offset **0.393**. `road-curve` is the 2×2
sweeping curve; `road-bend` the tight 1×1 corner. All palette GridMaps need `cell_center_y =
false`. Thumbnails (windowed-only, never CI: `kit/CLAUDE.md`): `tools/gen_thumbs.tscn`
writes `kit/thumbs/<kit>/<name>.png` (128², lossless, export-excluded as `kit/thumbs/*`);
`gen_kit_assets.gd` embeds each as a MeshLibrary preview. Flow: `gen_thumbs.tscn` →
`--import` → `gen_kit_assets.gd`.

## Authoring model

Hybrid: **GridMap palettes** for road/tile kits only; everything else is a **`KitPiece`**
prefab (`kit/helpers/kit_piece.gd`), its `DevCollision` body making unbaked levels playable.

| `collision_mode` | Behavior |
|---|---|
| `none` | no collision |
| `box` | AABB box |
| `footprint` | bottom-8%-height XZ area, extruded; box or cylinder by tighter cross-section |
| `hull` | convex hull |
| `multiconvex` | multiple convex hulls |
| `weld` | joins the level-wide drivable body at bake |

All authoring lives under one **`AuthoringRoot`** (`kit/helpers/authoring_root.gd`,
`chunk_size` knob + editor Bake button). Prefabs group into per-kit **`<Kit>Props`** folders
(plain `Node3D`s the baker recurses through); GridMaps/RoadPaths/scatter stay direct
children. **Tidy authoring** (palette toolbar → `placement_tool.tidy_authoring`) sorts a
flat AuthoringRoot into those folders in one undo step. Detection is SceneTree groups
(`src/levels/base/carlito_groups.gd`), never `class_name`, joined in `_init` not
`_enter_tree` (the baker walks scenes that never enter a tree); scene-tag rules:
`kit/CLAUDE.md` § Scene tags.

## Bake (`kit/bake/level_baker.gd`)

Merges render meshes per XZ chunk into one StaticBody3D per chunk; welds ALL drivable
geometry into **one level-wide ConcavePolygonShape3D body**, vertices snapped to **1 mm**.
Outputs `<level>.baked.scn` + `<level>.bake.json`; pure fns tested in `tests/test_bake.gd`.
`.baked.scn`/`.bake.json` split and the run-once-after-clone rule: `kit/CLAUDE.md`.

- **Scatter:** items ≥ `SCATTER_MULTIMESH_THRESHOLD` (**64**, per-item override) bake as one
  MultiMeshInstance3D per chunk × item under `Scatter/`; below threshold merges into chunk
  meshes. **Weld-mode prefabs in scatter are a bake error.**
- **Roads:** the baker calls `ribbon_surfaces()` once; collision never splits across chunks.
- **Bake-adjacent CODE** (`level_baker.gd`, `road_builder.gd`, `scatter_base.gd`) is hashed
  via `LevelBaker.BAKE_CODE_INPUTS`; `BAKER_VERSION` bumps for a change with no file moved.
- **Runtime seam:** `Level._setup_baked()` loads `<level>.baked.scn` by convention.
- **Export never ships authoring:** `addons/carlito_kit/` strips AuthoringRoot;
  `export_presets.cfg` excludes kit glbs/palettes/prefabs/thumbs/tools.
- **CI gate:** `tools/check_bakes.tscn` recomputes each level's input hash vs. the manifest.
  A fresh clone reports `unbuilt` and passes; `ci.yml` fails on missing/stale. Stats:
  chunks/surfaces/vertices/drivable triangles + `scatter_instances`, `scatter_multimeshes`,
  `roads`. Baked smoke test (`CARLITO_LEVEL` env) runs against `level_1`.

## Palette dock & click-to-place

`plugin.gd` registers the export stripper, the bottom-panel dock, and viewport tools,
routing events through **terrain brush → scatter brush → road draw → gridmap paint →
placement tool**. **One "Kit" bottom panel**, `TabContainer` (not `add_control_to_dock`,
breaks 3D nav in 4.6): Palette / Terrain / Scatter / Roads / Polish; selecting a
`HeightmapTerrain` / `ScatterCanvas` / `RoadPath` jumps to its tool tab. **Level card
(Polish tab):** **Set thumbnail view** writes `<level>_shot.tres`; **Shoot thumbnail**
writes `src/ui/level_thumbs/<registry id>.png` via `tools/gen_level_thumbs.tscn` against the
**baked** level (side-car rationale: `src/levels/CLAUDE.md`); all levels at once: `godot
--path . res://tools/gen_level_thumbs.tscn` (windowed only).

- **`palette_dock.gd`:** reads `kit/import/*.json`, buckets by family
  (`KitRecipe.classify`).
- **`placement_tool.gd`:** `arm(kit, name)` instances a ghost following the ground-snapped
  cursor; left-click commits under AuthoringRoot (undoable).
- **Ground raycast fallback** (`ground_snap.gd`): physics ray → `HeightmapTerrain.height_at`
  bilinear sample (`tests/test_heightmap_terrain.gd`) → Y=0 plane.
- **Palette tiles:** `select_tile` finds or creates (`cell_size`/origin/`cell_center_*`) the
  AuthoringRoot GridMap for that kit.
- **Auto-floor paint** (`gridmap_paint_tool.gd`, "Auto-floor" toggle): each click derives
  cell **Y from hit height**, commits `set_cell_item` + a `[`/`]` Y-rotation.

## Terrain generation & splat ground

`HeightmapTerrain` mesh chunking, collision shape, normals and splat-sampling rules:
`kit/CLAUDE.md`. Chunk size: `chunk_cells` (default 64) under an unowned `Chunks` node.

**Generator:** `TerrainGen` (`kit/terrain/terrain_gen.gd`, static pure fns,
`tests/test_terrain_gen.gd`). Preset = character (fractal type, amplitude, island falloff).

| Knob | Meaning |
|---|---|
| `gen_seed` | RNG seed |
| `feature_scale` | metres per feature |
| `gen_octaves` | fractal detail |
| falloff band | island edge softness |
| `coast_roughness` | 0 = round, 1 = ragged bays; unperturbed past r=0.92 |
| `terrace_levels` | plateau band height in 3 m cells, + `terrace_flat` |

World amplitude: `height` export, pixels normalized [0,1] (8-bit greyscale PNG). **Generate
terrain (from seed)** (destructive) writes the source PNG; **Generate new random terrain**
rolls a fresh `gen_seed`. **8 splat channels:**

`kit/terrain/terrain_splat.gdshader`: **8** albedo colors blended by **two** RGBA weight
maps (`splatmap`, `splatmap2`); `blend_sharpness` pow-sharpens + renormalizes (default 8).
Below-sea ring splats sand to the map edge so `WaterSurface` reads a circular coast.
Auto-splat classifies from slope + height (`sand_height`, `dirt_slope_deg`,
`rock_slope_deg`).

| Index | Source | Default color param | Default name |
|---|---|---|---|
| 0 | `splatmap`.R | `grass_color` | grass |
| 1 | `splatmap`.G | `dirt_color` | dirt |
| 2 | `splatmap`.B | `sand_color` | sand |
| 3 | `splatmap`.A | `rock_color` | rock |
| 4 | `splatmap2`.R | `color5` | Field (level 1) |
| 5 | `splatmap2`.G | `color6` | mud |
| 6 | `splatmap2`.B | `color7` | asphalt |
| 7 | `splatmap2`.A | `color8` | gravel |

`CHANNEL_PARAMS` maps index → param; name: `channel_names`; grip: `channel_grip`
(PackedFloat32Array, default 1.0 — `grip_at`, `docs/systems.md` § Level framework).
`splatmap2` absent samples transparent (`hint_default_transparent`). Channel 4 "Field" and
the Auto-splat-zeroes-`splatmap2` rule: `src/levels/CLAUDE.md`.

RoadPath's **Paint splat under road** (paved half-width minus 1 m) and the palette toolbar's
**Paint splat under tiles** are destructive-by-button: RoadPath writes `splat_channel`
(asphalt/city 6, gravel 7), tiles write channel 6 undercover (`kit/helpers/splat_paint.gd`,
tested).

Generated-PNG import settings (`detect_3d/compress_to=0`, `process/fix_alpha_border=false`),
written by `TerrainGen.ensure_import_settings`; rationale: `src/levels/CLAUDE.md`. Demo:
`src/levels/island/level_1/level_1.tscn`, 512 m terraced island, seed **499399**, ISOBUS
farm playground (`tools/gen_farm_playground.tscn`). Levels 2-4: `tools/gen_islands.gd`.
Level 5: railway (`tools/gen_rail_level.gd`). Level 6: drone playground
(`tools/gen_skyport.gd`), only level with a `WindField`, a `CurrentField`, and `Payloads`
(`CargoPayload` crates as children of the LEVEL ROOT, not `AuthoringRoot` — a bake input
would weld them). Generator stages: `kit/CLAUDE.md`.

## Terrain brushes

**`brush_chassis.gd`** (shared by terrain and scatter brushes): radius/strength/falloff,
ground cursor, input loop (LMB press → stroke, motion → samples at `radius * 0.35`, `[`/`]`
resize). `terrain_brush.gd`: sculpt raise/lower/smooth/flatten, cut a ramp, paint any of 8
splat channels. Per-pixel math (radial `weight`, `brush_dist`, `sculpt_value`, stamp fns):
`kit/helpers/brush_ops.gd` (`tests/test_brush_ops.gd`).

### Brush tools beyond the basic stroke

| Modifier / tool | Effect |
|---|---|
| Ctrl | inverts (swaps RAISE↔LOWER), frozen at `_stroke_begin` |
| Shift | forces SMOOTH from any mode |
| Flatten to a height | typed height or eyedropper (`arm_pick()`); `snap_step` quantizes in metres |
| Ramp | two-click: A + height, then lay the ramp; Esc cancels |
| Fill bucket | floods both weight images with the channel's unit vector |
| Square brush | Chebyshev distance; exact rim (t==1.0) stamped so 12 m pads don't seam |
| Snap to grid | locks brush centre to GridMap cell centres (`_snap_center`); "12 m (GridMap cell)" preset ticks it |

Editor-only; PNGs stay the sole artifact, written only on scene save
(`TerrainBrush.flush_all`), except lazily created `splatmap2`. Generate/Auto-splat/Conform
emit `source_image_replaced(kind)`, nulling the brush's cached image.

**Panel** (`brush_panel.gd`, "Terrain" tab): mode buttons index-matched to the brush enum (0
= Off … 5 = Ramp, 6 = Paint), radius/strength/edge-softness spinners ("Edge softness" in UI,
`falloff` in code), Shape picker + "12 m (GridMap cell)" preset.

## Scatter

Stored-transform contract, ground-snap fallback, and the stale-guard mechanism:
`kit/CLAUDE.md`. Stored in the level `.tscn` (`stored_transforms`, stride 5: x, y, z, yaw,
scale — `@export_storage`).

- **`ScatterBase`** (`scatter_base.gd`): shared core — `items`/`stored_transforms`/
  `stored_ground_hash`, MultiMesh preview + dev-collision; baker treats a region and canvas
  identically (both `carlito_scatter`).
- **`ScatterRegion`** (under Authoring): box/polygon footprint, density / `placement_seed` +
  min_spacing / yaw+scale jitter / max_slope, `items: Array[ScatterItem]` (prefab, weight,
  collision on/off, per-item threshold). **Regenerate** expands it (`generate_placements`,
  `tests/test_scatter.gd`).
- **`ScatterCanvas`** (under Authoring): hand-painted, same contract, no
  footprint/Regenerate, plus `paint_density` / `paint_pattern` (random/grid) / `grid_step`
  and `erase_within`.

**`scatter_brush.gd`** (panel `scatter_panel.gd`, Off/Paint/Erase/Rect + radius):
`_fill_polygon` samples a world-XZ polygon, ground-snaps, slope-filters, rejects duplicates.
`paint_pattern = "random"` uses `generate_placements`; `"grid"` uses
`generate_grid_placements` (`grid_step` replaces density/min_spacing) so dabs and Rect fills
continue one lattice with no seam.

Stale-scatter guard (config warning + **`bake()` fails** + **`check_level_file` reports
stale**): stores `ground_hash` (sha256 of terrain state); detail: `kit/CLAUDE.md`.
**Re-snap to ground** re-snaps stored Ys in place, keeps XZ/yaw/scale, drops groundless
instances.

## Spline roads

**`RoadPath`** (under Authoring): owns a serialized `Path3D` child "Path", extrudes a
low-poly ribbon from a **`RoadProfile`** (presets `city_profile.tres`,
`asphalt_profile.tres`, `gravel_profile.tres`, `bridge_profile.tres`). Ribbon derives from
curve + profile alone; the baker errors on a null profile.

Pure math is `RoadBuilder` (`tests/test_road.gd`): curvature-adaptive offsets (MIN_SEG 0.5
floor), a custom frame (roll only from curve tilt when `banking` is on), per-strip
extrusion, the conform flatten mask. Frame/roll rule and why it isn't
`sample_baked_with_rotation`: `kit/CLAUDE.md`.

Bridges ride the same pieces (no bridge class): `RoadProfile.base_depth` > 0 makes
`cross_section()` append a solid underside; `bridge_profile.tres` reaches below sea level.
Rails ride the same pieces too: a **`RailProfile`** (extends `RoadProfile`, gauge **1.44
m**, preset `rail_profile.tres`); Roads panel's Rail checkbox swaps profile. A baked level
emits a `RailTrack` node (`src/levels/base/rail_track.gd`) per rail road; the train runs
only on a closed loop (`RailTrack.find_closed_rail`). Rail mechanics: `kit/CLAUDE.md`.
`tools/gen_rail_level.gd` builds level 5's loop.

### Draw mode and drape

`road_draw_tool.gd` + `road_panel.gd`, "Roads" tab, Off/Draw: each click ground-snaps, lifts
by `draw_clearance` (0.3), commits one undoable action.

| Shape | Behavior |
|---|---|
| Free | auto-smooths with Catmull-Rom; Smooth-corners checkbox disables it |
| Straight | zero-handle chords; refuses corners tighter than the fold limit |
| Arc | 3-click: start, tangent, end; chained arcs are tangent-continuous |

**Angle snap** (Off/45°/15°) snaps to the heading grid. **Close loop** exits Draw with a
Catmull-Rom seam. **Reverse direction** reverses point order. RoadPath buttons: **Drape
curve onto terrain**, **Smooth curve (Catmull-Rom)**. Draw refuses clicks under
`RoadBuilder.min_turn_radius` (~6 m asphalt).

**Ports.** A port is the edge-center of an occupied roads-GridMap cell face carrying road
across, with an empty neighbor cell (`"ports"` in `kit/import/roads.json`: `surface_y`
**0.12**, `{match:[regex], ports:[{cell:[x,z], face}]}`; discovery: `road_ports.gd`,
`tests/test_road_ports.gd`). Excluded (off-lattice): `road-curve`, `road-split` — use
`road-bend` / crossroad. "Snap to ports" (default): a click within 3 m (XZ) commits there,
tangent locked 4 m along the outward normal. **Snap ends to ports** fixes gizmo-dragged ends
(within 6 m).

**Conform terrain** (`tile_conform.gd` + `RoadBuilder.conform_rects`, tested): flattens
terrain to the base plane of every painted tile GridMap (not in `CONFORM_EXCLUDE_MESHLIBS`)
and prefab in `CONFORM_PREFAB_FAMILIES`. Tile deck runs curb-to-curb ±4.8 (9.6 m);
`asphalt_profile.tres` sets `lane_width = 4.8`. Open-end ring tangents bound by
`END_TANGENT_MAX_DEV_DEG`.

**Profile edge cases.** A closed cross-section (`base_depth > 0`) triangulates onto the
first/last ring so a bridge is solid, not an open tube. Near-closed loops leave a real
collision hole past the 1 mm weld; `RoadPath` flags a gap smaller than the ribbon's
half-width. Conform samples the curve at `adaptive_offsets` rings, flattens to road height
minus `conform_epsilon`. Conform-terrain mechanics (full half-width flatten incl. skirt,
floor-quantize to 8-bit, `edge_drop` must absorb `ε + height/255`, `conform_falloff`
smoothsteps beyond the plateau): `kit/CLAUDE.md`. Authoring order: terrain → roads + conform
→ splat → scatter (conform trips the scatter stale guard by design).

**Non-goals:** see root CLAUDE.md non-goals (junctions, lane markings, traffic, world
streaming, in-game level editor, texture-layer terrain, LOD).
