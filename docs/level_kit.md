# Level kit — authoring tools & bake pipeline

Asset kits, editor tools, terrain, scatter, roads, and the bake that turns authoring content
into what ships. Runtime systems: `docs/systems.md` (vehicles: `docs/vehicles.md` /
`docs/heavy_vehicles.md`); level-author walkthrough: `docs/making_a_level.md`.

Authoring nodes are deterministic (seeded) so bakes and CI hashes stay reproducible, and must
expand without the editor (game-mode tool scenes bake in CI — no `EditorInterface` anywhere
the
baker touches). Editor UX lives in `addons/carlito_kit/`; data + runtime-safe logic in `kit/`
(`@tool` scripts, pure unit-tested cores).

## Kit assets & recipes

- **Layout:** `kit/raw/<kit>/` CC0 Kenney GLBs (7 kits: racing / roads / suburban / commercial
  /
  industrial / watercraft / nature), `kit/import/<kit>.json` recipes, `kit/palettes/*.meshlib`
  +
  `kit/prefabs/<kit>/*.tscn` **generated** by `tools/gen_kit_assets.gd` (`--script`; re-run
  after
  recipe/kit edits; meshlib item ids persist across regens).
- **Recipes are families-driven:** one ordered `families` list per recipe — `{name, label,
  match:[regex], pipeline:"palette"|"prefab"|"exclude", collision_mode?, reason?(exclude),
  assets:{<name>:{overrides}}}`, first match wins, classifies every GLB; drives dock grouping
  +
  pipeline + collision in one pass. Logic in `kit/helpers/kit_recipe.gd`
  (`tests/test_kit_gen.gd`).
  **Coverage gate:** every GLB must match a family or the generator fails, listing the
  unaccounted; excludes need a `reason`.
- **`{"manual": true}`** on a family asset opts a prefab out of regen (still counts for
  coverage):
  `roads/sign-highway{,-wide,-detailed}`, `commercial/building-{a,c}`.
- **Generated files keep their existing `uid://`** (`gen_kit_assets._keep_uid`) — re-minting
  one
  breaks every level `.tscn` referencing it by uid.
### Scales and thumbnails

- **Scale is lane-fit derived:** road-bearing kits target ~12 m two-lane (~6 m/lane vs the 1.8
  m
  car); per-kit scale + derivation live in each recipe. Palette lattices: roads `(12, 3, 12)`;
  racing cubic `(12, 12, 12)` corner-anchor (bridge y-offset: corners lift 0.393 native to
  span
  deck — re-verify on a large racing layout). Suburban is prefab-only. All palette GridMaps
  need
  `cell_center_y = false`. `road-curve` is a 2×2 sweeping curve; `road-bend` the tight 1×1
  corner.
- **Thumbnails:** `tools/gen_thumbs.tscn` (windowed only) frames every non-excluded GLB,
  writes
  `kit/thumbs/<kit>/<name>.png` (128², lossless); `gen_kit_assets.gd` embeds each palette
  tile's
  thumb as a MeshLibrary preview. Flow: `gen_thumbs.tscn` → `--import` → `gen_kit_assets.gd`.
  Never CI. `kit/thumbs/*` is export-excluded; a new thumb re-stales dependent bakes.

## Authoring model

Hybrid: **GridMap palettes** for road/tile kits only; everything else is a **`KitPiece`
prefab**
(`kit/helpers/kit_piece.gd`) whose `collision_mode`
(`none|box|footprint|hull|multiconvex|weld`)
rides the prefab root; its `DevCollision` body makes unbaked levels playable. `footprint`
measures the XZ area in the piece's bottom 8% of height, extrudes to full height, picks box or
cylinder by tighter cross-section (trees/posts stay solid at trunk only). All authoring lives
under one **`AuthoringRoot`** (`kit/helpers/authoring_root.gd`, `chunk_size` knob + editor
Bake
button). Placed prefabs group into per-kit **`<Kit>Props`** folders (plain `Node3D`s the baker
recurses through); GridMaps / RoadPaths / scatter stay direct children. **Tidy authoring**
(palette toolbar → `placement_tool.tidy_authoring`) sorts a flat AuthoringRoot into those
folders
in one undo step. Detection is SceneTree groups (`carlito_authoring` / `carlito_kit_piece` /
`carlito_scatter` / `carlito_road`, `src/levels/base/carlito_groups.gd`), never `class_name`.
**Each class joins its group in `_init`, not `_enter_tree`** — the baker walks scenes that
never
enter a tree.

## Bake (`kit/bake/level_baker.gd`)

- Merges render meshes per XZ chunk (one MeshInstance3D per chunk, one surface per deduped
  material, verts chunk-local), harvests prefab shapes into **one StaticBody3D per chunk**,
  and
  welds ALL drivable geometry (every palette cell + `weld` prefabs + road ribbons) into **one
  level-wide ConcavePolygonShape3D body** — vertices snapped to **1 mm** so tile borders are
  internal edges, never body seams.
- Outputs `<level>.baked.scn` + `<level>.bake.json` (input-hash manifest, timestamp-free).
  Pure
  fns (weld, chunking, hashing, spawn validation, accumulator) are tested in
  `tests/test_bake.gd`.
  Spawn validation and the stale-scatter guard (below) are both bake gates.
- **Scatter:** items with ≥ `SCATTER_MULTIMESH_THRESHOLD` (**64**, per-item override)
  instances
  bake as one MultiMeshInstance3D per chunk × item under `Scatter/` (mesh stored once,
  materials
  deduped); below threshold, instances route through the normal merge path. Collision harvest
  is
  identical either way; collision-off items add zero physics; **weld-mode prefabs in scatter
  are
  a bake error**.
- **Roads:** the baker calls `ribbon_surfaces()` once, derives the weld soup from those
  arrays.
  Render is chunk-bucketed by triangle centroid (collision never splits); every ribbon
  triangle
  joins the level-wide welded Drivable body.
### Nested pieces, mirroring, runtime seam

- **Nested pieces keep their own `collision_mode`** — re-enters the piece collector rather
  than
  inheriting the ancestor's mode.
- **Mirroring is winding-safe:** a negative-determinant transform reverses triangle order
  consistently across accumulator, weld pool, and array transform.
- Stats report chunks/surfaces/vertices/drivable triangles + `scatter_instances`,
  `scatter_multimeshes`, `roads`. **Bake-adjacent CODE** (`level_baker.gd`, `road_builder.gd`,
  `scatter_base.gd`) is hashed explicitly via `LevelBaker.BAKE_CODE_INPUTS` (GDScript reports
  no
  dependency edge for it) — editing one file re-stales every level; a new bake-adjacent file
  needs
  a new entry; `BAKER_VERSION` bumps for a semantic change that must re-stale with no file
  moved.
- **Runtime seam:** `Level._setup_baked()` loads `<level>.baked.scn` by convention and frees
  the
  authoring subtree; unbaked levels play authoring content directly (dev).
- **Export never ships authoring:** `addons/carlito_kit/` (enabled EditorPlugin) registers an
  EditorExportPlugin stripping AuthoringRoot from exported scenes; `export_presets.cfg`
  excludes
  kit glbs/palettes/prefabs/thumbs/tools (colormap + racing banner PNGs ship — baked materials
  reference them).
- **CI gate:** `tools/check_bakes.tscn` recomputes each level's input hash (level .tscn +
  every
  transitive resource dep, `BAKE_CODE_INPUTS`, `.import` sidecars) vs the manifest, and — only
  when a `.baked.scn` is on disk — checks the manifest's `output_hash` against it. **The
  `.baked.scn` is gitignored build output; the `.bake.json` manifest is the committed hash
  record.** A fresh clone and every CI checkout report `unbuilt` and pass — **run
  `tools/bake_levels.tscn` once after cloning**. `ci.yml` fails on missing/stale, bakes right
  after this check. The baked smoke test (`CARLITO_LEVEL` env) runs against `level_1`. A level
  with an empty `AuthoringRoot` (freshly scaffolded) is skipped, not reported missing.

## Palette dock & click-to-place

- `plugin.gd` registers the export stripper, the bottom-panel dock, and viewport tools,
  routing
  events through **terrain brush → scatter brush → road draw → gridmap paint → placement
  tool**;
  each inert until its target + mode are set. Editor-only, nothing ships.
- **One "Kit" bottom panel**, `TabContainer`: Palette / Terrain / Scatter / Roads / Polish.
  Selecting a `HeightmapTerrain` / `ScatterCanvas` / `RoadPath` jumps to its tool tab. Rides
  the
  bottom panel, not `add_control_to_dock` (breaks 3D viewport nav in 4.6).
- **Level card (Polish tab):** fly the viewport to the shot, **Set thumbnail view** (writes
  `<level>_shot.tres`, a `LevelShot` holding camera transform + FOV — side-car by design,
  since
  the level `.tscn` is a bake input and a camera node would re-stale the bake on every
  re-frame),
  then **Shoot thumbnail** (`src/ui/level_thumbs/<registry id>.png`). Shooting runs
  `tools/gen_level_thumbs.tscn` in a second Godot process against the **baked** level — bake
  first. With no saved view it frames a terrain overview (never the sea). All levels at once:
  `godot --path . res://tools/gen_level_thumbs.tscn` (windowed only).
### Dock internals and placement

- **`palette_dock.gd`:** reads `kit/import/*.json`, buckets entries by family
  (`KitRecipe.classify`), kit tabs → family sections → thumbnail grid. Search is global.
  Toolbar:
  Random yaw / Snap toggles + snap-step SpinBox.
- **`placement_tool.gd`:** `arm(kit, name)` instances a non-saved ghost that follows the
  ground-snapped cursor; left-click commits an owned copy under AuthoringRoot (undoable),
  stays
  armed; right-click / Escape disarms. Refuses to arm without an AuthoringRoot.
- **Ground raycast fallback chain** (`ground_snap.gd`, shared by placement and road drawing):
  edited-scene physics ray → miss → `HeightmapTerrain.height_at` bilinear sample
  (`tests/test_heightmap_terrain.gd`) → miss → Y=0 plane.
- **Palette tiles route to the built-in GridMap workflow:** `select_tile` finds or creates
  (undoable, `cell_size` + `cell_center_y = false` from the recipe) the AuthoringRoot GridMap
  for
  that kit and opens the built-in palette on it.
- **Auto-floor paint** (`gridmap_paint_tool.gd`, "Auto-floor" toggle): terrain-aware replace
  paint. Each click raycasts the ground, derives cell **Y from hit height**, commits one
  undoable
  `set_cell_item` with the item + a `[`/`]` Y-rotation. Left-click paints, Ctrl-click erases,
  right-click/Escape exits. Mode-exclusive with brushes and road draw.

## Terrain generation & splat ground

- **`HeightmapTerrain`'s render mesh is chunked:** one MeshInstance3D per `chunk_cells` tile
  (default 64) under an unowned `Chunks` node — a frustum-cull unit for island maps, not LOD.
  Collision stays **one** `HeightMapShape3D`. Normals are analytic (per-chunk
  `generate_normals()`
  would seam borders); UVs stay global 0..1 so the splat never seams. Brush strokes rebuild
  only
  touched tiles.
- **Generator:** `TerrainGen` (`kit/terrain/terrain_gen.gd`, static pure fns,
  `tests/test_terrain_gen.gd`). Preset = character (fractal type, amplitude, island falloff);
  knobs = `gen_seed` / `feature_scale` (m/feature) / `gen_octaves` / falloff band /
  **`coast_roughness`** (island only, 0 = round, 1 = ragged bays — perturbs falloff radius
  with
  derived-seed coast noise; hard unperturbed guard past r=0.92 keeps the border at sea level)
  /
  **terrace plateaus** (`terrace_levels`, band height in 3 m road-grid cells, +
  `terrace_flat`,
  applied last — island coasts step into concentric rings for buildable flats; band centres
  preserved). World amplitude is the `height` export; pixels stay normalized [0,1] (8-bit
  greyscale PNG). **Generate terrain (from seed)** (destructive-by-button) writes the source
  PNG;
  **Generate new random terrain** rolls a fresh `gen_seed` (still reproducible). Both one
  `EditorUndoRedoManager` action.
### Splat ground and the 8 channels

- **Splat ground:** `kit/terrain/terrain_splat.gdshader` (ships): **8** albedo colors blended
  by
  **two** RGBA weight maps, sampled raw (no `source_color`). `blend_sharpness` pow-sharpens +
  renormalizes across all 8 (default 8 — crisp low-poly borders). Auto-splat classifies from
  slope
  + height (`sand_height`, `dirt_slope_deg`, `rock_slope_deg`). The below-sea ring splats sand
    to
  the square map edge by design — `WaterSurface` at sea level makes the beach read as
  circular.
- **The 8 channels are per-level data.** 0..3 = `splatmap`.RGBA (**R=grass G=dirt B=sand
  A=rock**), 4..7 = `splatmap2`.RGBA. `splatmap2` is optional: absent, sampled transparent
  (`hint_default_transparent`, not `_black`, whose opaque default would give every terrain a
  full-weight channel 8) — a 4-channel terrain stays byte-identical. Color: `CHANNEL_PARAMS`
  (index → param, `grass_color`…`rock_color`, then `color5`…`color8` defaulting
  snow/mud/asphalt/gravel). Name: `channel_names`. Grip: `channel_grip`
  (PackedFloat32Array, default 1.0 — wheels sample via `grip_at`, `docs/systems.md` § Level
  framework). **Level 1's channel 4 is "Field"** — the ploughable soil, the only honest "in
  soil"
  predicate for `draft_force`. Not Dirt (ch 1): Auto-splat paints Dirt on every slope.
  RoadPath's **Paint splat under road** button (centerline + deck strip at paved half-width
  minus
  1 m) and the palette toolbar's **Paint splat under tiles** (cell mesh faces projected to XZ,
  eroded one pixel) are both destructive-by-button, full strength: RoadPath writes the
  profile's
  `splat_channel` (asphalt/city 6, gravel 7; swapping a profile does NOT repaint), tiles write
  channel 6 biased undercover (`kit/helpers/splat_paint.gd`, tested). Without them a conformed
  road/tile inherits the grip of the splat beneath it (usually grass, 0.8). **Auto-splat
  zeroes
  `splatmap2` in the same undo action** (classifies only the base 4) — stale extra weights
  would
  double-count against the fresh base. So pressing Auto-splat on level 1 wipes
  Field/Mud/Gravel
  AND road asphalt; recover by replaying the level's generator chain.
### Generated-PNG import settings

- **Generated-PNG import gotcha:** `TerrainGen.ensure_import_settings` writes the `.import`
  sidecar — lossless, no mipmaps, **`detect_3d/compress_to=0`** (default would silently
  VRAM-compress the splatmap and break `get_image()`) and **`process/fix_alpha_border=false`**
  (rewrites RGB wherever alpha == 0, corrupting weights where rock == 0).
- Demo: `src/levels/island/level_1/level_1.tscn` — generated 512 m terraced island (seed
  499399),
  auto-splat, car spawn on the central plateau, boat spawn in the sea, drown-respawn. Free
  centre
  is the ISOBUS farm playground (field / mud wallow / haul ramp / implement yard), authored by
  `tools/gen_farm_playground.tscn` (two stages, `build` then `resnap`; channel-4 soil contract
  in
  root CLAUDE.md § Levels & water). Its heightmap no longer regenerates from the recorded
  knobs —
  Generate would wipe the sculpt. Levels 2-4: same shape, different seeds, scaffolded by
  `tools/gen_islands.gd`. Level 4: racing circuit (`RoadPath` ribbon + `RacingProps`,
  `ParkedProps`, `WatercraftProps`). Level 5: railway (`tools/gen_rail_level.gd`). Level 6:
  drone
  playground (`tools/gen_skyport.gd`, `scaffold`/`props`/`probe` stages) — a stepped island
  with a
  tapering canyon cut into the highland so GPS fix degrades as walls close in; only level with
  a
  `WindField` and with `Payloads` (three `CargoPayload` crates as direct children of the LEVEL
  ROOT, not `AuthoringRoot` — that's a bake input, welded into static geometry, so a baked
  crate
  could not be lifted).

## Terrain brushes

- **Reusable brush chassis** (`brush_chassis.gd`, shared by terrain and scatter brushes): owns
  radius/strength/falloff, the ground cursor, and the input loop (LMB press → stroke, motion →
  spacing-throttled samples at `radius * 0.35`, release → stroke end, `[`/`]` resize).
  Brush-specific work delegates to virtuals. Click mode's press latches (release also
  swallowed)
  so a one-shot click disarms itself instead of leaking release to editor selection.
- **`terrain_brush.gd`:** sculpt raise/lower/smooth/flatten, cut a ramp, paint any of 8 splat
  channels. Per-pixel math in `kit/helpers/brush_ops.gd` (radial `weight`, `brush_dist`,
  `sculpt_value`, stamp fns), tested in `tests/test_brush_ops.gd`. Paint lerps toward the unit
  8-vector, split across both weight images; every stroke
  stamps/previews/dirties/undoes/flushes
  both. No-`splatmap2` terrain gets one created lazily on the first channel ≥ 4 stroke.
  Cursor:
  ray-vs-heightfield against the live working image (no physics), tracks in-progress
  sculpting.
### Brush tools beyond the basic stroke

- **Modifiers:** Ctrl inverts (swaps RAISE↔LOWER), Shift forces SMOOTH from any mode; frozen
  at
  `_stroke_begin`. **Flatten to a height:** typed height or eyedropper-sampled (`arm_pick()`);
  `snap_step` quantizes in world metres. **Ramp:** two-click — first stores A + normalized
  height, second lays the ramp; Esc cancels (consumed), right-click cancels but passes through
  to
  freelook; projection clamps to [0,1], A == B degenerates to a flatten disk. **Fill bucket:**
  floods both weight images with the channel's unit vector, full-image dirty rect, ignores
  strength/falloff. **Square brush:** Chebyshev distance, axis-aligned; exact rim (t==1.0) is
  stamped (round/ramp exclude it) so abutting 12 m pads don't leave a one-pixel seam, reaching
  the
  edge only at hard falloff. **Snap to grid:** locks brush centre onto the road GridMap's cell
  centres (its `cell_size`/origin/`cell_center_*`, else a 12 m centre-true lattice at world
  origin — a `(12,3,12)` centre-true GridMap centres cell 0 at local 6 not 0, so
  `_snap_center`
  compensates); also pushes the GridMap's vertical cell size (3 m default) into Flatten's
  `snap_step`, and the "12 m (GridMap cell)" preset ticks it and drops edge softness to 0.
### Artifacts, caches and undo

- **Editor-only; PNGs stay the sole artifact.** A brush never swaps the terrain's exported
  Texture2D (exception: lazily created `splatmap2`). Height remeshes only touched chunks off
  the
  in-memory image (collision deferred to stroke end — HeightMapShape3D has no partial update).
  Edits accumulate per-terrain, written to PNGs + reimported only on scene save
  (`TerrainBrush.flush_all`), never per stroke.
- **Cached working images drop when a button replaces a PNG.** Generate, Auto-splat, road
  Conform, an inspector assignment and their undos emit `source_image_replaced(kind)`; the
  brush
  nulls that image — otherwise the session flushes stale pixels back (Auto-splat visibly
  undone
  on the next paint).
- **Undo** snapshots only the touched image region; blit-back on undo/redo.
- **Panel** (`brush_panel.gd`, "Terrain" tab): mode buttons index-matched to the brush enum (0
  =
  Off … 5 = Ramp, 6 = Paint — adding a mode shifts every index after it), radius/strength/
  edge-softness spinners ("Edge softness" in UI, `falloff` in code), Shape picker + "12 m
  (GridMap cell)" preset. Mode-specific rows: flatten target, ramp hint, channel picker (8
  entries) + fill button. No AuthoringRoot needed for brushing.

## Scatter

- **Stored-transform contract (non-negotiable):** expansion happens exactly once, in the
  editor —
  pure seeded placement → ground-snap by raycast against the live edited scene
  (`HeightmapTerrain.height_at` fallback; **no Y=0 fallback**, un-snappable points dropped) →
  slope filter → region-local transforms stored in the level .tscn (`stored_transforms`,
  stride
  5: x, y, z, yaw, scale — `@export_storage`, one undoable action). Baker and dev-play only
  ever
  consume stored transforms — no expansion, no raycast, no physics outside the editor path —
  so
  editor and bake can never diverge and CI hashing is just the .tscn.
- **`ScatterBase`** (`scatter_base.gd`): shared core — `items`/`stored_transforms`/
  `stored_ground_hash`, MultiMesh preview + dev-collision, the stale guard, and pure statics
  the
  baker duck-calls. The baker treats a region and a canvas identically (both
  `carlito_scatter`).
- **`ScatterRegion`** (under Authoring): box/polygon footprint, density / placement_seed +
  shared
  min_spacing / yaw+scale jitter / max_slope, `items: Array[ScatterItem]` (prefab, weight,
  collision on/off, per-item threshold). Editor **Regenerate** is the expansion site.
  `generate_placements` (rejection sampling, spatial-hash spacing, deterministic per seed) is
  tested in `tests/test_scatter.gd`.
- **`ScatterCanvas`** (under Authoring): hand-painted front-end, same contract/preview/
  dev-collision/bake/stale guard, instances painted in (no footprint, no Regenerate) plus
  `paint_density` / `paint_pattern` (random/grid) / `grid_step` and `erase_within`.
### Scatter brush and the stale guard

- **Scatter brush** (`scatter_brush.gd`, shared chassis; panel `scatter_panel.gd`,
  Off/Paint/Erase/Rect + radius): one placement path (`_fill_polygon`) samples candidates over
  a
  world-XZ polygon (disc bound for Paint, two-click rectangle for Rect), drops outside the
  disc/rect, ground-snaps, slope-filters, rejects duplicates. Erase calls
  `ScatterCanvas.erase_within`. `paint_pattern = "random"` uses `generate_placements` +
  min_spacing
  against a running spatial hash; `"grid"` uses `generate_grid_placements` (one instance per
  lattice cell, anchored to world origin and seeded per cell, so dabs and Rect fills continue
  one
  lattice with no seam — `grid_step` replaces density/min_spacing). **Rect:** first click
  stores a
  corner, second lays the whole fill as one undoable action. Strokes mutate
  `stored_transforms`
  live for feedback, commit one undoable whole-array swap (+ ground hash) at stroke end.
- **Preview/dev-play:** unowned children rebuilt from stored data, never serialized: one
  MultiMeshInstance3D per item; dev collision bodies only outside the editor.
- **Stale-scatter guard** (warning + bake gate + CI): Regenerate/paint stores `ground_hash`
  (sha256 of every terrain heightmap image + name/position/size/height). On mismatch: a
  configuration warning (3 s poll), **`bake()` fails**, **`check_level_file` reports stale** —
  the
  ground hash is the only proof stored transforms match current terrain; a re-bake alone does
  not
  re-snap. Regenerate clears it, as does **Re-snap to ground** (re-snaps stored Ys in place,
  keeps
  XZ/yaw/scale, drops groundless instances — the canvas recovery path after a road Conform or
  sculpt). Regions with zero stored instances never gate.

## Spline roads

- **`RoadPath`** (under Authoring): owns a serialized `Path3D` child "Path" (edit via the
  built-in
  gizmo or the addon's Draw mode; the curve is the bake input) and extrudes a low-poly ribbon
  from
  a **`RoadProfile`** (presets `city_profile.tres`, `asphalt_profile.tres` (painted edge
  line),
  `gravel_profile.tres`, `bridge_profile.tres`). Ribbon derives from curve + profile alone
  (never
  reads terrain). Preview unowned; dev trimesh exists only outside the editor. Profile
  default:
  editor `_ready` assigns the city preset via a plain property set so it serializes as an
  ExtResource the input hash sees; the baker errors on a null profile.
- **Pure math is `RoadBuilder`** (`tests/test_road.gd`): curvature-adaptive offsets anchored
  at
  every interior control point's arc offset (a kink gets a ring at the corner whose
  central-difference tangent is the angle bisector; uniform coarse split + bisection while
  tangents disagree; MIN_SEG 0.5 floor), a custom frame (right = tangent×UP stays horizontal,
  roll
  only from explicit curve tilt when `banking` is on — not `sample_baked_with_rotation`, whose
  parallel transport accumulates roll on climbing turns), per-strip extrusion (no shared verts
  —
  crisp hard edges), and the conform flatten mask.
### Bridges and rails

- **Bridges ride the same pieces** (no bridge class): `RoadProfile.base_depth` > 0 makes
  `cross_section()` append a solid underside (two walls + bottom strip `base_depth` below the
  outer edge; 0 = no base). `bridge_profile.tres` reaches below sea level. Road-to-road joins:
  every other RoadPath's end point + outward tangent joins the Draw-mode snap-candidate list
  as a
  port.
- **Rails ride the same pieces too** (no rail class): a **`RailProfile`** (extends
  `RoadProfile`)
  whose `cross_section()` is a ballast trapezoid + two rail ribs at ±gauge/2 (standard gauge
  **1.44 m** = Kenney train kit at scale 2.4); preset `rail_profile.tres`. Roads panel's Rail
  checkbox swaps profile. Draw/Drape/Smooth/Conform and the bake path work unchanged. A baked
  level frees `AuthoringRoot`, so the baker also emits a `RailTrack` node
  (`src/levels/base/rail_track.gd`) per rail road (duplicated curve + gauge + closed flag).
  The
  train runs **only on a closed loop** (`RailTrack.find_closed_rail`); an open rail bakes and
  drives fine but spawns no train. `tools/gen_rail_level.gd` builds level 5's loop,
  overwriting
  the level each run.
### Draw mode and drape

- **Draw mode + Drape** (`road_draw_tool.gd` + `road_panel.gd`, "Roads" tab, Off/Draw): each
  click
  ground-snaps, lifts by `draw_clearance` (0.3), commits one undoable action; first click
  replaces
  the untouched 2-point stub; RMB/Escape exits. Shapes: *Free* (auto-smooths the previous
  point
  with Catmull-Rom; Smooth-corners checkbox disables for exact polyline); *Straight*
  (zero-handle
  chords, refuses corners tighter than the fold limit — draw those as arcs); *Arc* (3-click:
  start,
  tangent, end — XZ circle split ≤ 90° sub-arcs; chained arcs are tangent-continuous). **Angle
  snap** (Off/45°/15°) snaps Straight chords and Arc directions to the heading grid. The ghost
  previews the actual tessellated ribbon, tinted red with a live min-radius readout when too
  tight. **Close loop** appends a Catmull-Rom-seamed point on the first, exits Draw. **Reverse
  direction** reverses point order (ribbon is direction-invariant). RoadPath buttons: **Drape
  curve onto terrain** (re-snaps Y + clearance; points over no terrain keep Y), **Smooth curve
  (Catmull-Rom)**. Corners self-overlap below local turn radius = ribbon half-width (~6 m
  asphalt) — the draw tool refuses clicks whose changed segments cross that floor
  (`RoadBuilder.min_turn_radius`); a pre-existing tight corner never blocks further drawing.
  Only
  gizmo-made kinks bypass the guard; RoadPath raises a configuration warning whenever the
  whole
  curve's min turn radius sits under the half-width.
### Ports and port snapping

- **Ports (tile ↔ spline sockets):** a port is the edge-center of an occupied roads-GridMap
  cell
  face the tile carries road across, with an empty neighbor cell. Computed from lattice + a
  per-tile table — `"ports"` in `kit/import/roads.json`: `surface_y` (deck height above cell
  base,
  **0.12**) plus first-match-wins entries `{match:[regex], ports:[{cell:[x,z], face}]}` in
  local
  pre-rotation frame. Discovery is pure (`road_ports.gd`, `tests/test_road_ports.gd`): rotate
  by
  the cell's 24-orientation basis, skip faces whose neighbor is occupied. **Excluded:**
  `road-curve` (2×2) and `road-split` are XZ-centered, off-lattice — use `road-bend` /
  crossroad.
  Snapping: with "Snap to ports" on (default), a click within 3 m (XZ) of a port commits
  exactly
  at the port (deck height, no clearance) with the end tangent locked 4 m along the outward
  face
  normal; arriving at a port exits Draw. The Path3D gizmo can't be intercepted, so dragged
  ends
  are fixed with **Snap ends to ports** (nearest within 6 m + locks tangents).
  **Height agreement:** put port cells on a flattened pad — terrain-brush grid-snap 12 m
  flatten,
  or the palette toolbar's **Conform terrain** (`tile_conform.gd` +
  `RoadBuilder.conform_rects`,
  tested): flattens every overlapping terrain to the base plane of every painted tile GridMap
  (not in `CONFORM_EXCLUDE_MESHLIBS`) plus placed prefab buildings in
  `CONFORM_PREFAB_FAMILIES` (footprint = merged world AABB grown by the apron spinbox). Tile
  footprints come from item mesh AABB, 4 m falloff beyond the union; targets are
  floor-quantized
  at base + lift spinbox (terrain meets the highest 8-bit step at or below base + lift, never
  above — a coarse island step can't poke terrain through the 0.24 m road deck). **Width:**
  tile
  deck runs curb-to-curb ±4.8 (9.6 m) with the white curb line at ±4.8, so
  `asphalt_profile.tres`
  sets `lane_width = 4.8`. **Seam squareness:** extrude gives open-end rings the exact
  endpoint
  handle tangent rather than finite-difference, bounded by `END_TANGENT_MAX_DEV_DEG`.
### Profile edge cases, conforming terrain

- **Bridge profiles cap their ends:** a closed cross-section (`base_depth > 0`) triangulates
  onto
  the first/last ring, so the box is solid, not an open tube — walls and floor weld into the
  drivable body.
- **Near-closed loops warn:** extrude only shares a seam frame when end control points
  coincide,
  so a loop closed by eye leaves the end rings apart — past the 1 mm weld, a real hole in
  collision. `RoadPath` flags an endpoint gap smaller than the ribbon's half-width.
- **Conform terrain is destructive-by-button:** samples the curve at the extrusion's
  `adaptive_offsets` rings (not a fixed step, which would poke terrain through descending
  segments), flattens overlapping terrain to road height − `conform_epsilon`. Under the deck,
  target comes from rasterizing the actual deck triangles (centerline projection alone
  mis-heights
  edges on steep+yawing segments). Flatten plateau is the full ribbon half-width incl. drop
  skirt;
  `conform_falloff` smoothsteps beyond it. Targets are floor-quantized to the 8-bit grid — the
  profile's `edge_drop` must absorb `ε + height/255` (conform warns per terrain when it
  can't).
  Conforming changes heightmap bytes, so earlier scatter trips its stale guard by design —
  authoring order: terrain → roads + conform → splat → scatter, `ScatterBase`'s **Re-snap to
  ground** recovers out-of-order edits.
- **Non-goals:** see root CLAUDE.md non-goals (junctions, lane markings, traffic, world
  streaming,
  in-game level editor, texture-layer terrain, LOD). The GridMap workflow remains right for
  city
  grids.
