# Level kit — authoring tools & bake pipeline

Everything used to build a level: asset kits, editor tools, terrain, scatter, roads, and
the bake that turns authoring content into what ships. Runtime systems are in
`docs/systems.md`; the walkthrough for level authors is `docs/making_a_level.md`.

**The bake is the compiler; every authoring tool is a source-code editor.** Authoring
nodes must be deterministic (seeded) so bakes and CI hashes stay reproducible, and they
must expand without the editor (game-mode tool scenes bake in CI — no `EditorInterface`
in anything the baker touches). Editor UX lives in `addons/carlito_kit/`; data +
runtime-safe logic lives in `kit/` (plain `@tool` scripts with pure, unit-tested cores).

## Kit assets & recipes

- **Layout:** `kit/raw/<kit>/` CC0 Kenney GLBs (7 kits: racing / roads / suburban /
  commercial / industrial / watercraft / nature; keep `Textures/` beside the glbs —
  relative refs; nature glbs carry materials internally, no `Textures/`),
  `kit/import/<kit>.json` recipes, `kit/palettes/*.meshlib` + `kit/prefabs/<kit>/*.tscn`
  **generated** by `tools/gen_kit_assets.gd` (`--script` mode; re-run only after
  recipe/kit edits; meshlib item ids are preserved across regens so painted GridMaps
  never break).
- **Recipes are families-driven (single source of truth):** each recipe has one ordered
  `families` list — `{name, label, match:[regex], pipeline:"palette"|"prefab"|"exclude",
  collision_mode?, reason?(exclude), assets:{<name>:{overrides}}}` — that *alone*
  classifies every GLB (first match wins; ordering resolves overlaps so patterns stay
  simple prefixes). It drives dock grouping + pipeline + collision in one pass; the
  pure/tested classify+id logic lives in `kit/helpers/kit_recipe.gd`
  (`tests/test_kit_gen.gd`). **Coverage gate:** every GLB must match one family or the
  generator *fails* listing the unaccounted; excludes need a `reason`; per-family member
  counts print (catch-alls tagged) so an oversized "box everything else" bucket is
  visible.
- **Hand-edited prefabs opt out with `{"manual": true}`** in the family's `assets` block:
  the generator leaves that `.tscn` completely alone (it still counts for the coverage
  gate, and the regen prints a `manual (hand-edited, not regenerated)` line per kit). That
  is how you hand-tune a piece's collision in the editor without the next regen wiping it
  — say *why* in the recipe's `_notes`. Currently manual: `roads/sign-highway`,
  `sign-highway-wide`, `sign-highway-detailed`, `commercial/building-a`, `building-c`.
- **Generated files keep their existing `uid://`** (`gen_kit_assets._keep_uid` re-binds the
  id before each save). Re-minting one silently breaks every level `.tscn` that references
  the file by uid — it degrades to "invalid UID: … using text path instead" warnings on
  level load.
- **Scales are derived from measurement (lane-fit rule):** road-bearing kits target a
  ~12 m two-lane road (~6 m/lane vs the 1.8 m car). Per-kit scale and the derivation
  note live in each recipe (`kit/import/<kit>.json`) — the recipe is the source of
  truth. Palette lattices: **roads** cell `(12, 3, 12)`; **racing** cubic cell
  `(12, 12, 12)` on a corner-anchor lattice (bridge y-offsets measured from AABBs —
  corners lift 0.393 native to the span deck; re-verify when building a large racing
  layout). Suburban is prefab-only (no palette). All palette GridMaps need
  `cell_center_y = false`. NB roads: `road-curve` is a 2×2 sweeping curve; `road-bend`
  is the tight 1×1 corner — use the latter for one-cell corners.
- **Thumbnails:** `tools/gen_thumbs.tscn` (game-mode tool, run **windowed** — headless
  can't render) frames every non-excluded prefab/palette GLB in a SubViewport on a
  neutral backdrop and writes `kit/thumbs/<kit>/<name>.png` (128², imported lossless).
  `gen_kit_assets.gd` then embeds each palette tile's thumb as a MeshLibrary item
  **preview** (the built-in GridMap palette shows pictures; the dock reads the PNGs).
  Full local flow: `gen_thumbs.tscn` → `--import` → `gen_kit_assets.gd`. Never CI.
  `kit/thumbs/*` is export-excluded (only the ~4 KB reference table lands in the
  meshlib, not image data); embedding a new thumb re-stales dependent bakes (re-bake
  after regen).

## Authoring model

Hybrid: **GridMap palettes** for road/tile kits only; everything else is a **`KitPiece`
prefab** (`kit/helpers/kit_piece.gd`) whose `collision_mode`
(`none|box|footprint|hull|multiconvex|weld`) rides the prefab root; its `DevCollision` body
makes unbaked levels playable. `footprint` measures the XZ area in the piece's bottom 8% of
height and extrudes it to full height, picking box or cylinder by whichever cross-section is
tighter — trees, posts, flags and street lights are solid at the trunk/pole only, not across
their canopy or overhanging arm. All authoring lives under one **`AuthoringRoot`** node
(`kit/helpers/authoring_root.gd`, `chunk_size` knob + editor **Bake** button). Placed
prefabs are grouped into per-kit **`<Kit>Props`** folders (plain identity `Node3D`s the
baker recurses straight through — `_collect` accumulates transforms); GridMaps / RoadPaths
/ scatter stay direct children. **Tidy authoring** (palette toolbar → `placement_tool.tidy_authoring`)
sorts an existing flat AuthoringRoot into those folders in one undo step. Detection
everywhere is duck-typed marker methods (`is_carlito_authoring` / `is_carlito_kit_piece`
/ `is_carlito_scatter` / `is_carlito_road`), never class_name.

## Bake (`kit/bake/level_baker.gd`)

- Merges render meshes per XZ chunk (one MeshInstance3D per chunk, one surface per
  deduped material, verts chunk-local), harvests prefab shapes into **one StaticBody3D
  per chunk**, and welds ALL drivable geometry (every palette cell + `weld` prefabs +
  road ribbons) into **one level-wide ConcavePolygonShape3D body** — vertices snapped to
  1 mm so tile borders are internal edges, never body seams.
- Outputs `<level>.baked.scn` + `<level>.bake.json` (input-hash manifest,
  timestamp-free). Pure fns (weld, chunking, hashing, spawn validation, accumulator) are
  unit-tested in `tests/test_bake.gd`. Spawn validation is a bake gate; so is the
  stale-scatter guard (below).
- **Scatter:** items with ≥ `SCATTER_MULTIMESH_THRESHOLD` (64, per-item override)
  instances bake as one MultiMeshInstance3D per chunk × item under `Scatter/` — the
  merged item mesh is stored ONCE, materials deduped like chunk merges; below the
  threshold every instance routes through the normal merge path. Collision harvest is
  identical either way (prefab shapes per instance into chunk bodies); collision-off
  items add zero physics; **weld-mode prefabs in scatter are a bake error**.
- **Roads:** the baker duck-calls `ribbon_surfaces()` once (it depends only on the
  serialized Path child + profile, so it works on the baker's untreed instance) and
  derives the weld soup from those same arrays. Render is chunk-bucketed by triangle
  centroid (`split_arrays_by_chunk`, render-only — collision never splits) through
  `BakeContext.add_render_arrays`; every ribbon triangle joins the level-wide welded
  Drivable body via `add_weld_faces` (the same 1 mm merge as weld prefabs).
- **Nested pieces keep their own `collision_mode`:** a `KitPiece` inside another
  re-enters the piece collector rather than inheriting the ancestor's mode (inheriting
  welded a `hull` railing into the drivable body, and hid a `weld` ramp from it).
- **Mirroring is winding-safe:** a negative-determinant transform (scale −1 on an axis)
  reverses triangle order in `SurfaceAccumulator`, the weld pool, and
  `transform_surface_arrays`, so a mirrored piece is neither inside-out on screen nor
  one-way in collision.
- Stats report chunks/surfaces/vertices/drivable triangles plus `scatter_instances`,
  `scatter_multimeshes`, and `roads`. Bake-adjacent CODE (`level_baker.gd`,
  `road_builder.gd`, `scatter_base.gd`) reaches the hash through
  `LevelBaker.BAKE_CODE_INPUTS` — GDScript reports no dependencies, so no resource edge
  finds it. Editing one re-stales every level by itself; `BAKER_VERSION` stays the knob
  for semantic changes that must re-stale even when no file moved.
- **Runtime seam:** `Level._setup_baked()` loads `<level>.baked.scn` by convention and
  frees the authoring subtree; unbaked levels play authoring content directly (dev).
- **Export never ships authoring:** `addons/carlito_kit/` (enabled EditorPlugin)
  registers an EditorExportPlugin whose `_customize_scene` strips AuthoringRoot from
  exported scenes; `export_presets.cfg` excludes kit glbs/palettes/prefabs/thumbs/tools
  (colormap + racing banner PNGs ship — baked materials reference them). Verified by
  byte-scanning the pck (an excluded imported texture leaves only a benign uid-cache
  path string, never its `.ctex` data).
- **CI gate:** `tools/check_bakes.tscn` recomputes each registered level's input hash
  (level .tscn + every transitive resource dep that can shape the bake — anywhere, not
  just `res://kit/**`; runtime scripts outside the kit and `res://addons/` are excluded,
  see `LevelBaker.is_bake_input` — plus `BAKE_CODE_INPUTS` and `.import` sidecars,
  CRLF-normalized text hashing) vs the manifest, and checks the manifest's `output_hash`
  against the `.baked.scn` on disk so an edited or truncated bake cannot read fresh;
  ci.yml fails on missing/stale. The baked-level headless
  smoke (`CARLITO_LEVEL` env picks a registry id) runs against **`level_1`**. A level
  whose `AuthoringRoot` is still empty (a freshly scaffolded canvas) is skipped, not
  reported missing — the first thing painted into it re-arms the check.

## Palette dock & click-to-place

- `plugin.gd` registers the export stripper, the bottom-panel dock, the viewport tools,
  and calls `set_input_event_forwarding_always_enabled()` so `_forward_3d_gui_input`
  receives every viewport event (placement is selection-independent). Viewport input is
  forwarded **terrain brush → scatter brush → road draw → gridmap paint → placement
  tool**; each is inert until its target + mode are set, so the tools never fight normal
  editor navigation. Nothing in the addon ships — it is editor-only.
- **One "Kit" bottom panel** hosts everything as a `TabContainer`: **Palette / Terrain /
  Scatter / Roads / Polish** tabs (tab title = each panel's node name; the four tool panels
  ride their own `ScrollContainer`). So tile-city work (Palette tab → roads kit) and spline
  work (Roads tab) are one click apart, and selecting a `HeightmapTerrain` /
  `ScatterCanvas` / `RoadPath` pops the panel and jumps to its tool tab. The
  deprecated `add_control_to_dock` breaks 3D viewport nav in 4.6, so this rides the
  bottom panel.
- **Level card (Polish tab)** — the screenshot on the level-select button. Fly the 3D
  viewport to the shot you want, press **Set thumbnail view** (writes
  `<level>_shot.tres` — a `LevelShot` holding the camera transform + FOV, side-car by
  design: the level `.tscn` is a bake input, so a camera *node* would re-stale the bake on
  every re-frame), then **Shoot thumbnail** (writes
  `src/ui/level_thumbs/<registry id>.png`). Work code: `level_shot_tool.gd` +
  `kit/helpers/level_shot.gd`. Shooting runs `tools/gen_level_thumbs.tscn` in a **second
  Godot process** — the picture must show the baked, running level (baked swap, real
  lighting, water), which the editor's own world cannot give: so **bake before you shoot**,
  and expect the editor to block for a few seconds. With no saved view it frames an
  overview of the terrain (never the sea/skyline ring — that would put the camera 2 km out)
  and thins the fog to suit the shot distance, so an unvisited level still gets a usable
  card. Same tool, all levels at once:
  `godot --path . res://tools/gen_level_thumbs.tscn` — **windowed only**, headless cannot
  render.
- **`palette_dock.gd`** (`@tool VBoxContainer`, UI only): reads all `kit/import/*.json`
  recipes, gathers each kit's emitted prefab basenames + palette meshlib item names,
  buckets them by **family via `KitRecipe.classify`** (`label` per section, `exclude`
  families skipped), and shows kit tabs → family sections → thumbnail grid from
  `kit/thumbs/<kit>/<name>.png` (basename is 1:1 across prefab/tile/thumb/GLB).
  **Search is global across all kits** (a non-empty query flattens the tabs into one
  result flow, each tile badged `<kit>/<name>`). Toolbar: Random yaw / Snap toggles +
  snap-step SpinBox.
- **`placement_tool.gd`** (`RefCounted`, holds all editor API): `arm(kit, name)`
  instances the prefab as a **non-saved ghost** (unowned, collision bodies zeroed to
  `collision_layer = 0` and excluded from the ray) that follows the ground-snapped
  cursor; left-click **commits** a real owned copy under the level's `AuthoringRoot` via
  `EditorUndoRedoManager` (add_child + set_owner + local transform, undoable);
  **sticky** (stays armed); right-click / Escape disarms. Refuses to arm with a clear
  warning when the scene has no AuthoringRoot.
- **Ground raycast fallback chain** (`addons/carlito_kit/ground_snap.gd`, shared by
  placement and road drawing — a click never dead-drops): edited-scene physics
  `intersect_ray` → miss → the level's `HeightmapTerrain.height_at(world_pos)` bilinear
  sample (runtime-safe, unit-tested in `tests/test_heightmap_terrain.gd`) → miss → the
  Y=0 plane. Editor physics isn't always populated, so the terrain/plane branches carry
  the feature.
- **Palette tiles route to the built-in GridMap workflow** (never reimplemented):
  `select_tile` finds — or creates (undoable, `cell_size` + `cell_center_y = false` from
  the recipe) — the AuthoringRoot GridMap using that kit's meshlib and selects/edits it
  so the built-in palette (with thumbnails) opens.
  `GridMapEditorPlugin.set_selected_palette_item` has no public handle to the built-in
  instance, so the exact paint item is a best-effort print of the item id — the author
  clicks the thumbnailed tile in the built-in palette.
- **Auto-floor paint** (`gridmap_paint_tool.gd`, `RefCounted`; palette-toolbar
  "Auto-floor" toggle): a terrain-aware replacement paint mode. The built-in GridMap
  editor paints on a **manual** floor plane and exposes no script hook to drive it, so
  when the toggle is on, a tile pick arms this tool on the selected GridMap: each click
  raycasts the ground via the shared `ground_snap.gd` chain and `local_to_map` derives
  the cell **Y from the hit height**, then commits one undoable `set_cell_item` with the
  palette's item + a `[`/`]` Y-rotation (`get_orthogonal_index_from_basis`). Left-click
  paints (drag streaks one cell per undo step), Ctrl-click erases, right-click/Escape
  exits; a wire-box ghost shows the target cell. Mode-exclusive with the brushes and road
  draw (owns the viewport), and follows its GridMap — selecting away drops it. Cost/
  benefit: the built-in editor already covers plateaued pads where one floor level spans
  the whole city; this earns its keep on multi-level terrain.

## Terrain generation & splat ground

- **`HeightmapTerrain`'s render mesh is chunked**: one MeshInstance3D per `chunk_cells`
  tile (default 64) under an unowned `Chunks` node — the frustum-cull unit for
  island-scale maps (culling granularity, **not** LOD). Collision stays **one**
  `HeightMapShape3D`. Normals are analytic from the height grid
  (`TerrainGen.grid_normal`) because per-chunk `generate_normals()` seams chunk borders;
  UVs stay global 0..1 so the splat never seams. Brush strokes rebuild only touched
  tiles via `_build_chunk`.
- **Generator:** `TerrainGen` (`kit/terrain/terrain_gen.gd`, static pure fns, tested in
  `tests/test_terrain_gen.gd`). Preset = character (fractal type, relative amplitude,
  island radial falloff); knobs = `gen_seed` / `feature_scale` (m per feature) /
  `gen_octaves` / falloff band / **`coast_roughness`** (island only, 0 = perfectly round,
  1 = ragged bays and headlands — perturbs the falloff radius with a derived-seed coast
  noise; a hard unperturbed guard past r=0.92 keeps the map border at sea level, and
  `coast_roughness == 0` is byte-identical to the pre-roughness output) / **terrace
  plateaus** (`terrace_levels` — band height in 3 m road-grid cells — + `terrace_flat`,
  applied last so island coasts step into concentric rings — the buildable flats
  villages/farms need; band centres are preserved so relief is unchanged). **World
  amplitude is the `height` export** — generated pixels stay normalized [0,1] (8-bit
  greyscale PNG). Two buttons: **Generate terrain (from seed)** (editor-only,
  destructive-by-button, never per-frame) writes the current texture's source PNG, else
  `<scene>_<node>_height.png` beside the scene; **Generate new random terrain** rolls a
  fresh seed into `gen_seed` (still reproducible). Both are one `EditorUndoRedoManager` action
  snapshotting the prior image + any property change (seed, material swap) — a stray
  click must not destroy sculpt work.
- **Splat ground:** `kit/terrain/terrain_splat.gdshader` (ships — `kit/terrain/` is not
  export-excluded): **8** albedo colors blended by **two** RGBA weight maps, sampled raw
  (no `source_color` — sRGB would bend weights), gl_compatibility-safe. `blend_sharpness`
  pow-sharpens + renormalizes across all 8 weights (default 8 — crisp low-poly borders,
  not soft fades). The **Auto-splat** button classifies from slope + height
  (`sand_height`, `dirt_slope_deg`, `rock_slope_deg`), swapping in a splat ShaderMaterial
  when needed (same undo action); the node pushes both maps into the material params on
  rebuild. The below-sea ring splats sand out to the square map edge by design — a level's
  `WaterSurface` at sea level is what makes the beach read as a circular coast.
- **The 8 channels are per-level data.** Index 0..3 = `splatmap`.RGBA (**R=grass G=dirt
  B=sand A=rock** — TerrainGen's order), 4..7 = `splatmap2`.RGBA. `splatmap2` is
  **optional**: absent, the shader samples it transparent (`hint_default_transparent`, NOT
  `_black` — the engine's default black is *opaque*, which would give every terrain a
  full-weight channel 8), so a 4-channel terrain is byte-for-byte unchanged. A channel's
  **color** is its shader param (`HeightmapTerrain.CHANNEL_PARAMS` maps index → param:
  `grass_color`…`rock_color`, then `color5`…`color8` defaulting to snow/mud/asphalt/gravel)
  — edit the material to repaint a level's palette; its **name** is the node's
  `channel_names`; its **tire grip** is `channel_grip` (PackedFloat32Array, default all
  1.0 = no effect — the runtime multiplier wheels sample via `grip_at`, see
  `docs/systems.md`; paint Ice/Mud strips or Asphalt under conformed roads to change
  surface feel without touching collision). Painting Asphalt under roads is automated:
  each RoadPath has a **Paint splat under road** button (centerline + deck strip at the
  paved half-width minus a 1 m inset) and the palette toolbar a **Paint splat under
  tiles** button (each cell's actual mesh faces projected to XZ — a curve paints only the
  curve — eroded one splat pixel); both are destructive-by-button and paint at full
  strength with a hard edge — the RoadPath button writes the **profile's**
  `splat_channel` (asphalt/city presets 6, gravel preset 7; swapping a profile does NOT
  repaint, and repainting never erases the old strip's excess — recovery is Auto-splat +
  repaint), the tiles button channel 6 — biased to **undercover so the paint stays
  hidden under the deck** (pure math in `kit/helpers/splat_paint.gd`, tested), one undo
  step per terrain. Without them a conformed road/tile street inherits the grip of the
  splat painted beneath it — usually grass, 0.8 — because the wheels sample the terrain
  splat through the deck. Name and color are read by the brush panel (`channel_color()` falls back to the
  shader's own default via `RenderingServer.shader_get_parameter_default`, since an unset
  param reads back null). Auto-splat classifies only the base 4, so it **zeroes `splatmap2`
  in the same undo action** — stale extra weights would otherwise double-count against the
  fresh base ones.
- **Generated-PNG import gotcha:** `TerrainGen.ensure_import_settings` writes/patches
  the `.import` sidecar — lossless, no mipmaps, **`detect_3d/compress_to=0`** (the
  splatmap is sampled by a 3D shader; the default detect_3d would silently reimport it
  VRAM-compressed and break `get_image()`) and **`process/fix_alpha_border=false`** (it
  rewrites RGB wherever alpha == 0, corrupting grass/dirt/sand weights where rock == 0).
- Demo: `src/levels/island/level_1/level_1.tscn`: a generated 512 m terraced island
  (seed 499399) with its auto-splat, a car spawn on the central plateau, a boat spawn in
  the surrounding `WaterSurface` sea (G swaps), drown-respawn included. Its free centre is
  the **ISOBUS farm playground** — field / mud wallow / haul ramp / implement yard, one per
  tractor signal — authored end to end by `tools/gen_farm_playground.tscn` (two stages,
  `build` then `resnap`; see the header there and "Levels & water" in the root CLAUDE.md
  for the channel-4 soil contract). The heightmap PNG therefore no longer regenerates from
  the recorded generator knobs: Generate would wipe the sculpt. Levels 2-4
  (`src/levels/island/level_<n>/`) are the same shape with different seeds, scaffolded by
  `tools/gen_islands.gd`. Level 4 is the **racing circuit**: a `RoadPath` ribbon with
  `RacingProps` (pit garages, grandstand awnings, barriers, banner towers), `ParkedProps`
  and `WatercraftProps` under its `AuthoringRoot` — it is also where the semi's fifth-wheel
  joint was proved, being wide, smooth and long. Level 5 is the railway, owned end to end by
  `tools/gen_rail_level.gd`.

## Terrain brushes

- **Reusable brush chassis** (`addons/carlito_kit/brush_chassis.gd`, `RefCounted`,
  shared by the terrain and scatter brushes): owns the radius/strength/falloff params,
  the ground cursor (an `ImmediateMesh`, unowned child of the target, no-depth-test so it's
  always visible), and the input loop (LMB press → stroke,
  motion → **spacing-throttled** samples at `radius * 0.35`, release → stroke end,
  `[`/`]` resize). Brush-specific work is delegated to virtuals (`_target_valid`,
  `_project`, `_cursor_parent/_points/_strips/_color`, `_stroke_begin/apply/end`,
  `_click_mode/_click`); the chassis is inert (returns false, doesn't touch the viewport)
  until a subclass reports a valid target. Three seams the terrain brush needs and the
  scatter brush ignores (they are inert by default): live `ctrl_pressed`/`shift_pressed`
  recorded off every `InputEventWithModifiers`; **click mode**, where a press is a discrete
  `_click` instead of opening a drag (a press consumed this way **latches**, so its release
  is swallowed too — a one-shot click disarms itself, and letting the release through would
  hand it to the editor, which selects on release and would change the selection out from
  under the brush); and `_cursor_strips`, which draws the cursor as *several* line strips
  (one `LINE_STRIP` could not hold a detached second marker without a stray joining chord).
- **`terrain_brush.gd`**: sculpt **raise/lower/smooth/flatten**, cut a **ramp**, and
  **paint** any of the 8 splat channels. The pure per-pixel stamp math lives in
  `kit/helpers/brush_ops.gd` (radial `weight` curve, the `brush_dist` metric,
  `sculpt_value`, `stamp_height`/`stamp_splat`/`stamp_ramp`/`fill_splat` returning the
  dirty Rect2i) — editor-free, unit-tested in `tests/test_brush_ops.gd`. Paint is a lerp
  toward the unit 8-vector, **split across both
  weight images**: each takes the same kernel with its `BrushOps.unit_slice(channel,
  image_index)` — all-zero for the image the channel doesn't live in, which is exactly the
  fade the other seven channels need, so sums stay normalized with no cross-image
  bookkeeping. Every paint stroke therefore stamps, previews, dirties, undoes and flushes
  **both** images (same kernel ⇒ same dirty rect). A terrain with no `splatmap2` gets an
  all-zero one created lazily on the first channel ≥ 4 stroke, written to
  `png_path_for("splat2")` on save. Ground under the cursor is found by **iterating
  ray-vs-heightfield** (no physics — editor space isn't reliably populated, and we want
  the terrain surface, not a placed prop), sampling the **live working image** so the
  cursor tracks in-progress sculpting.
- **Brush tools beyond the basic stroke.** All of them reuse the stroke path's
  snapshot → dirty-rect → region-undo machinery, so each lands as one undoable action:
  - **Ctrl inverts, Shift smooths.** `_effective_mode()` folds the modifiers in: Shift ⇒
    SMOOTH from any sculpt mode, Ctrl swaps RAISE↔LOWER (paint and ramp pass through).
    It is **frozen into `_eff_mode` at `_stroke_begin`**, so releasing a key mid-drag can't
    switch tools under the author; the cursor tint reads the live value while idle and the
    frozen one while stroking.
  - **Flatten to a height.** `flatten_fixed` + `flatten_height` (world Y) level to a typed
    height instead of the drag's start; the **eyedropper** (`arm_pick()`) makes the next
    click sample `_surface_y` into that field rather than edit. `snap_step` quantizes the
    target — in **world metres**, for both the typed and the drag-sampled height, so
    "level to the nearest 3 m" means the same thing either way. 8-bit heightmaps still
    quantize the result to `height / 255`.
  - **Ramp** — a two-click tool (`_click_mode`), not a drag: the first click stores A plus
    its normalized height and shows a marker ring, the second lays the whole ramp in one
    `stamp_ramp`. Esc cancels and is consumed; **right-click cancels but is deliberately
    NOT consumed**, so the editor keeps it for freelook. `stamp_ramp` works in "brush
    units" (pixel offset ÷ per-axis half-width) — that is the world metric scaled uniformly
    by 1/radius, so projecting onto the segment and measuring across is metrically honest
    even on a non-square terrain, where a world-circular brush is an image-space ellipse.
    Projection clamps to the **segment** (t ∈ [0,1]), giving round caps; A == B degenerates
    to a flatten disk rather than dividing by zero.
  - **Fill bucket** (`fill_terrain()`): floods both weight images with the channel's
    `unit_slice`, dirty rect = the whole image. Strength/falloff have no say.
  - **Square brush** (`square`): swaps `brush_dist` from Euclidean to **Chebyshev**,
    axis-aligned in image space (= world axes for our unrotated terrains). Sculpt and paint
    honour it; the ramp has its own swept shape. The square passes `inclusive = true` to
    `weight`, so its **exact rim (t == 1.0) is stamped** (round + ramp keep the rim excluded)
    — without it two abutting 12 m pads each dropped their shared boundary column and left a
    one-pixel seam. Rim inclusion only reaches the edge at **hard falloff** (edge softness 0);
    a soft square still fades, so flush GridMap pads want edge softness 0.
  - **Snap to grid** (`grid_snap`): locks the brush centre onto the road GridMap's cell
    **centres** in `_project` (so cursor, drag, ramp endpoints and eyedropper all snap alike),
    via `BrushOps.snap_to_grid`. Reads the found GridMap's `cell_size`/origin/`cell_center_*`
    when the plugin hands one over (`set_grid`), else a **12 m centre-true lattice at world
    origin** (what a `RoadsTiles` node would use) so pads can be sculpted before tiles exist.
    The **half-cell offset matters**: a `(12,3,12)` centre-true GridMap centres cell 0 at
    local 6, not 0, so `_snap_center` adds `cell_size*0.5` per centre-true axis to the lattice
    origin (snapping to plain multiples of 12 would sit half a cell off the tiles). The plugin
    finds the GridMap by the `RoadsTiles` name (else the first `GridMap`) on selection. Turning
    it on also pushes the GridMap's vertical cell size (3 m default, `grid_cell_y()`) into
    Flatten's `snap_step`; the **"12 m (GridMap cell)" preset** ticks it and drops edge
    softness to 0 (flush pads in one click).
- **Editor-only; PNGs stay the sole artifact.** A brush never swaps the terrain's
  exported `heightmap`/`splatmap` Texture2D, so the scene always serializes the PNG
  reference (sole exception: the lazily created `splatmap2`, which has no PNG to point at
  until its first flush). Live feedback: height remeshes only the touched chunks straight off the
  in-memory working image via `HeightmapTerrain.rebuild_region_world(img, min_x, max_x,
  min_z, max_z)` (collision deferred to stroke end via `rebuild_collision_from_image` —
  HeightMapShape3D has no partial update); paint drives temporary `splatmap` + `splatmap2`
  shader-param overrides from throwaway `ImageTexture`s (the preview material dupe must
  carry BOTH, or a channel ≥ 4 stroke would be invisible). Edits accumulate in per-terrain
  sessions and are written to the PNGs + reimported **only on scene save**
  (`EditorPlugin._save_external_data` → `TerrainBrush.flush_all`), never per stroke.
- **Cached working images must be dropped when a button replaces a PNG.** Generate,
  Auto-splat, road Conform, an inspector assignment and the undo of any of them all land
  through `HeightmapTerrain`'s property setters, which emit
  **`source_image_replaced(kind)`**; the brush subscribes per session and nulls that
  image. Without it the session keeps the pre-button pixels and the next stroke flushes
  them back — Auto-splat visibly comes undone on the next paint (and only a Godot restart,
  which clears sessions, "fixes" it). A brush-side identity check is **not** a substitute:
  `_apply_generated` reloads with `CACHE_MODE_REPLACE`, so the Texture2D instance is
  unchanged and only its contents differ.
  `HeightmapTerrain.png_path_for(kind)` provides the PNG paths.
- **Undo** snapshots only the touched image region (before/after sub-images via
  `get_region`, `commit_action(false)` since edits are already live); `_apply_region`
  blits back and refreshes the visual, robust to the terrain no longer being selected
  (re-derives the session).
- **Panel** (`addons/carlito_kit/brush_panel.gd`, the "Terrain" tab of the Kit bottom panel):
  mode buttons (**index-matched to the brush enum**, 0 = Off … 5 = Ramp, 6 = Paint — adding
  a mode shifts every index after it, so the panel names the ones it tests: `MODE_OFF`,
  `MODE_FLATTEN`, `MODE_RAMP`, `MODE_PAINT`), radius/strength/edge-softness spinners
  (labeled "Edge softness" in the UI; the param stays `falloff` in code), and a Shape
  picker + "12 m (GridMap cell)" preset (12 m square = one roads-palette cell, which is
  12×3×12). Mode-specific controls live in rows `_show_rows()` reveals only in their mode,
  which is what keeps the panel scannable: the flatten target box, the ramp hint, and the
  channel picker (8 entries, refilled per selection from the terrain's `channel_names` +
  a color swatch per channel; the selection survives the refill) + fill button. Shape is
  the exception — it shows in every stamping mode (all but Off and Ramp), and the Snap-to-
  grid checkbox shows in every mode but Off. The plugin tracks
  `selection_changed` → sets the brush target to any selected `HeightmapTerrain`; picking a
  mode disarms the placement ghost. Terrain needs **no AuthoringRoot** for brushing (unlike
  prop placement).

## Scatter

- **Stored-transform contract (non-negotiable):** expansion happens exactly once, in the
  editor — pure seeded placement → ground-snap by raycast against the live edited scene
  (physics ray → `HeightmapTerrain.height_at` fallback; **no Y=0 fallback** —
  un-snappable points are *dropped*) → slope filter → **region-local transforms stored
  in the level .tscn** (`stored_transforms`, one packed array per item, stride 5:
  x, y, z, yaw, scale — `@export_storage`, one undoable action). The baker and dev-play
  only ever consume stored transforms — no expansion, no raycast, no physics outside the
  editor path — so editor and bake can never diverge and CI hashing is just the .tscn.
  (HungryProton's ProtonScatter was evaluated: its non-destructive runtime modifier
  stack is the model this design rejects; no code adopted.)
- **`ScatterBase`** (`kit/helpers/scatter_base.gd`) is the shared core of both
  front-ends: the `items` / `stored_transforms` / `stored_ground_hash` state, the
  MultiMesh preview + dev-collision subtree, the stale guard, and the pure statics the
  baker duck-calls (`stored_transform`, `stored_count`, `build_item_mesh`,
  `shape_entries`, `ground_hash`, `snap_ground`, `find_terrains_under`). GDScript
  inherits statics, so they resolve on either subclass; the baker treats a region and a
  canvas identically (both `is_carlito_scatter()`).
- **`ScatterRegion`** (`kit/helpers/scatter_region.gd`, under `Authoring`): box/polygon
  footprint (box unifies into the polygon sampling path), density / placement_seed knobs
  plus shared min_spacing / yaw+scale jitter / max_slope, `items: Array[ScatterItem]`
  (`kit/helpers/scatter_item.gd`: prefab **PackedScene** — so `gather_bake_inputs`
  tracks it — weight, collision on/off, per-item threshold override). The editor
  **Regenerate** button is the region's one expansion site. Placement statics
  (`generate_placements` — rejection sampling with a spatial-hash spacing guarantee,
  deterministic per seed — `polygon_area`) are unit-tested in `tests/test_scatter.gd`.
- **`ScatterCanvas`** (`kit/helpers/scatter_canvas.gd`, under `Authoring`): the
  hand-painted front-end — same contract, preview, dev collision, bake path and stale
  guard, but instances are **painted in** (no footprint, no Regenerate button — the
  footprint gizmo keys on `footprint_polygon`, which only the region has) plus one
  `paint_density` / `paint_pattern` (random/grid) / `grid_step` knobs and the pure/tested
  `erase_within` static.
- **Scatter brush** (`addons/carlito_kit/scatter_brush.gd`, on the shared chassis;
  panel `scatter_panel.gd`, Off/Paint/Erase/Rect + radius): one placement path
  (`_fill_polygon`) serves every mode. It samples candidates over a world-XZ polygon —
  the square bounding the brush disc (**Paint**) or the two-click rectangle (**Rect**) —
  drops the ones outside the disc/rect, ground-snaps (`ScatterBase.snap_ground`, a
  straight-down ray, so an area fills at whatever height its ground is), slope-filters,
  and rejects duplicates. **Erase** calls `ScatterCanvas.erase_within`. Reuses the canvas
  node's jitter/spacing/slope exports.
  - `paint_pattern = "random"`: `ScatterRegion.generate_placements` + min_spacing against
    a running world-XZ spatial hash (prior dabs + existing instances, so density is even
    regardless of stroke speed).
  - `paint_pattern = "grid"`: `ScatterRegion.generate_grid_placements` — one instance per
    lattice cell centre, **anchored to the world origin** and seeded per cell, so Paint
    dabs and Rect fills continue ONE lattice with no seam and no double row (occupancy is
    a taken-cell set instead of the spacing hash). For corn rows, orchards and neat grass
    patches; `grid_step` replaces density + min_spacing there.
  - **Rect** rides the chassis's `_click_mode()`/`_click()` two-point path (like the
    terrain ramp): first click stores a corner, the cursor draws the pending rectangle,
    the second click lays the whole fill as one undoable action. Esc cancels (consumed);
    right-click cancels but is passed through so freelook still works.
  Strokes mutate `stored_transforms` live for feedback and commit **one** undoable
  whole-array swap (+ the ground hash) at stroke end — editor-only; no runtime or baker
  code.
- **Preview/dev-play:** unowned children rebuilt from stored data (never serialized —
  the same discipline as the terrain `Chunks` node): one MultiMeshInstance3D per item;
  **dev collision bodies only outside the editor** (unbaked play is drivable; editor
  raycasts never hit our own instances).
- **Stale-scatter guard** (warning + bake gate + CI): Regenerate/paint stores
  `ground_hash` (sha256 of every terrain heightmap image + name/position/size/height).
  On mismatch the node shows a configuration warning (3 s editor poll), **`bake()`
  fails** (like spawn validation), and **`check_level_file` reports stale** — the
  input hash now covers the terrain PNGs too, but only the ground *hash* proves the
  stored transforms were snapped against the terrain as it stands — a re-bake alone does
  not re-snap, so this stays the gate that ships no floating or buried props.
  Regenerate (which re-snaps) clears it, as does the **Re-snap to ground** button on
  `ScatterBase` (re-snaps stored Ys in place, keeps XZ/yaw/scale, drops groundless
  instances, refreshes the hash — the recovery path for a canvas, which cannot
  Regenerate, after a road Conform or sculpt). Regions with zero stored instances never
  gate.

## Spline roads

- **`RoadPath`** (`kit/helpers/road_path.gd`, under `Authoring`): owns a **serialized
  `Path3D` child "Path"** (edit with the built-in path gizmo or the addon's Draw mode;
  the curve is the bake input) and extrudes a low-poly ribbon from a **`RoadProfile`**
  (`kit/helpers/road_profile.gd`; presets `kit/roads/city_profile.tres` — flat colors
  sampled from the roads-GridMap tiles' colormap swatches so spline roads match
  tile-city streets — `asphalt_profile.tres` — painted edge line —
  `gravel_profile.tres`, and `bridge_profile.tres` — see Bridges below; flat-color
  materials as inline SubResources so
  a color edit re-stales bakes through the one .tres hash). The ribbon derives from the
  **curve + profile alone** (never reads the terrain), so bake output depends only on
  the scene file. Preview is unowned; the **dev trimesh exists only outside the editor**
  (unbaked play drivable; editor rays never hit our own ribbon). Profile default: editor
  `_ready` assigns the city preset via a **plain property set** so it serializes as
  an ExtResource the input hash sees — never a preload export default (equal-to-default
  is omitted from the .tscn, a hash hole); the baker errors on a null profile.
- **Pure math is `RoadBuilder`** (`kit/helpers/road_builder.gd`, tested in
  `tests/test_road.gd`): curvature-adaptive offsets **anchored at every interior control
  point's arc offset** (the corner miter: a kink gets a ring exactly AT the corner whose
  central-difference tangent is the angle bisector, else the edge notches even at small
  angles; then uniform coarse split + bisection while tangents disagree, incl. a
  midpoint check for S-inflections; MIN_SEG 0.5 floor), a **custom frame** (right =
  tangent×UP stays horizontal, roll ONLY from explicit curve tilt when `banking` is on —
  deliberately NOT `sample_baked_with_rotation`, whose parallel transport accumulates
  roll on climbing turns), per-strip extrusion (strips never share verts — crisp hard
  edges; U = lateral m, V = arc-length m; winding CW-from-above and invariant under
  curve reversal), and the conform flatten mask.
- **Bridges ride the same pieces** (no bridge class or tool): `RoadProfile.base_depth`
  > 0 makes `cross_section()` append a solid underside — two vertical walls + a bottom
  strip `base_depth` below the road's outer edge, drawn in `base_material` — so the
  extruder, baker and conform need zero changes (0 = no base, the default; every
  non-bridge profile stays byte-identical). `kit/roads/bridge_profile.tres` is the
  preset (deep enough to reach below sea level for water spans). Road-to-road joins:
  every OTHER RoadPath's first/last curve point + outward end tangent joins the
  Draw-mode snap-candidate list as a port (`_enumerate_road_ends`; same
  radii/handle-lock/ghost markers as tile ports), so a bridge span meets its approach
  roads with collinear tangents = seamless deck. Profile `.tres` + `road_profile.gd`
  are hash-tracked, so bridge edits self-detect stale bakes.
- **Rails ride the same pieces too** (no rail class or tool): a **`RailProfile`**
  (`kit/helpers/rail_profile.gd`, extends `RoadProfile`) whose `cross_section()` is a
  ballast trapezoid + two raised rail ribs at ±gauge/2 (standard gauge 1.44 m = the Kenney
  train kit at scale 2.4); preset `kit/roads/rail_profile.tres`. The Roads panel's **Rail
  checkbox** swaps the selected RoadPath's profile between the rail preset and the city
  default (one undoable action, checkbox state read back from the profile's
  `is_carlito_rail_profile()` marker). Because a rail is just a RoadPath with a different
  profile, **Draw / Drape / Smooth / Conform and the whole bake path work on it unchanged**
  (`paved_half_width`/`full_half_width` stay meaningful so the fold guard and conform behave;
  its vertical rib walls make it drop degenerate strips on both axes, not just laterally).
  What differs is runtime: a baked level frees `AuthoringRoot`, so the baker also emits a
  `RailTrack` node (`src/levels/base/rail_track.gd`) per rail road, carrying the duplicated
  curve + gauge + closed flag — that is the spline the train rides. The train runs **only on
  a closed loop** (`RailTrack.find_closed_rail`, the one shared closed-loop walk); an open
  rail bakes and drives fine but no train spawns on it. `tools/gen_rail_level.gd` builds
  level 5's loop end to end (survey-follow-contour routing, grade-budgeted profile, conform)
  and overwrites the level on every run.
- **Draw mode + Drape:** `addons/carlito_kit/road_draw_tool.gd` + `road_panel.gd`
  (the "Roads" tab of the Kit bottom panel, Off/Draw; RoadPath-selection-gated like the
  brushes). Each viewport click
  ground-snaps via the shared `ground_snap.gd` chain, lifts by the node's
  `draw_clearance` (0.3), and commits ONE undoable action; the first click replaces
  the untouched 2-point default stub; RMB/Escape exits. **Draw shapes** (panel radio,
  all emit plain Curve3D points+handles — the extruder/bake pipeline never knows):
  - *Free*: the historical flow — each click **auto-smooths the previous point with
    Catmull-Rom handles** (`RoadBuilder.smooth_handles`, pure/tested; the panel's
    Smooth corners checkbox, Free-only, turns it off for an exact polyline).
  - *Straight*: exact zero-handle chords — the new point lands with zero handles and
    the previous point's out-handle is zeroed in the same action. Shallow joints
    render as clean miters; a corner tighter than the fold limit is refused (the kink
    would pinch the inside edge into a slit) — draw those corners as arcs.
  - *Arc*: 3-click circular arc — start, tangent direction, end (the Cities: Skylines
    pattern; `RoadBuilder.arc_points`, pure/tested: XZ circle from tangent + chord,
    split into <= 90° sub-arcs, each a cubic with handle length 4/3·tan(θ/4)·r; height
    lerps along arc length with the slope in the handles). The committed end point
    keeps its out-handle, so the NEXT arc reuses it as its tangent — chained arcs are
    tangent-continuous with one click each; right-click re-picks a pending tangent
    (with none pending it exits as usual). A ~collinear end degrades to a straight.
    Arc END clicks ignore ports (start + tangent + end already fix the end tangent);
    starting a fresh arc road ON a port still works and locks the first tangent.
  - **Angle snap** (panel option, Off/45°/15°): snaps Straight chords and Arc
    tangent/chord directions to the heading grid (`RoadBuilder.snap_direction`).
  The **ghost previews the candidate as the actual tessellated ribbon edges** (same
  adaptive sampling + frames as the extruder, at the profile's full half-width),
  tinted red — with a live min-radius readout on the panel — when the candidate turns
  tighter than the fold limit. The panel's **Close loop** button appends a point ON
  the first point with Catmull-Rom seam tangents on both sides (C1 through the seam —
  the duplicated ring welds at bake) and exits Draw. The panel's **Reverse direction**
  button (also on the RoadPath inspector) reverses the curve's point order — per point
  the in/out handles swap, tilts ride along, the ribbon is direction-invariant — so
  Draw appends from the other end. RoadPath buttons: **Drape curve
  onto terrain** (re-snaps every existing point's Y to terrain + clearance; points
  over no terrain keep their Y) and **Smooth curve (Catmull-Rom)** (handles for every
  interior point — the rescue for hand-kinked curves); each is one undoable action.
  Corners still self-overlap when the local turn radius drops below the ribbon
  half-width (~6 m asphalt) — that is geometric; the draw tool REFUSES clicks whose
  new/reshaped/created segments would cross that floor (`RoadBuilder.min_turn_radius`
  / the arc's analytic radius, panel status line + warning). **Ghost, readout, and
  refusal all measure the SAME candidate curve** (one `_click_sim` per click,
  including the smoothing rewrite of the previous point and the corner a polyline
  click forms there), so a red ghost always means a refused click; only the changed
  segments are checked, so a pre-existing tight corner never blocks drawing. Only
  gizmo-made kinks bypass the guard — those still get extrude's fold-clamp pinch,
  and the RoadPath raises a configuration warning whenever the whole curve's
  min turn radius sits under the half-width, so the slit never goes unnoticed.
- **Ports (tile ↔ spline sockets):** a *port* is the edge-center of an occupied
  roads-GridMap cell face that the tile actually carries road across AND whose neighbor
  cell is empty. Ports are fully computable from the lattice + a per-tile table —
  top-level `"ports"` in `kit/import/roads.json`: `surface_y` (asphalt deck height above
  the cell base, measured 0.12) plus ordered first-match-wins entries
  `{ "match": [name regexes], "ports": [{ "cell": [x,z], "face": "+x|-x|+z|-z" }] }` in
  the item's local pre-rotation frame (`cell` is the anchor-relative offset for
  multi-cell tiles like the 3×3 roundabout). Discovery is pure/baker-safe
  (`kit/helpers/road_ports.gd`, tested in `tests/test_road_ports.gd`): rotate offset +
  face by the cell's 24-orientation basis, skip faces whose neighbor cell is occupied.
  **Excluded for now:** `road-curve` (2×2) and `road-split` are XZ-centered, so their
  ends sit on half-cell planes — off-lattice; use `road-bend` / crossroad instead.
  Openness is judged by cell occupancy only (an unpainted cell under another tile's
  overhang counts as open).
- **Port snapping (Draw mode, Free/Straight; Arc end clicks ignore ports):** with the
  panel's **Snap to ports** toggle on (default),
  a click within 3 m (XZ) of a port commits the point exactly AT the port — deck height,
  **no draw_clearance**, so the ribbon meets the tile flush — with the end tangent
  locked 4 m along the outward face normal; arriving at a port **exits Draw** (the road
  ends there, and no later click can rewrite the locked tangent). The ghost shows
  diamond markers on nearby ports (blue) and the snap candidate (green). The built-in
  Path3D gizmo can't be intercepted, so dragged ends are fixed up with the panel's
  **Snap ends to ports** button (destructive-by-button): snaps the road's first/last
  points to their nearest ports within 6 m + locks tangents, one undo step.
  **Height agreement:** put port cells on a flattened pad — either the terrain-brush
  grid-snap 12 m flatten, or the palette toolbar's **Conform terrain** button
  (`addons/carlito_kit/tile_conform.gd` + `RoadBuilder.conform_rects`, tested):
  `conform_all` flattens every overlapping terrain to the **base plane** of **every**
  painted tile GridMap under Authoring (meshlib not in `CONFORM_EXCLUDE_MESHLIBS`) **plus**
  every placed prefab building whose recipe family is in `CONFORM_PREFAB_FAMILIES` (both
  easy-to-edit lists at the top of the file; prefab footprint = merged world AABB of its
  mesh descendants grown by the toolbar's **apron** spinbox — flat ground kept past the
  walls before the falloff drop, target = the piece's world origin Y, round-quantized).
  Tile footprints come from the item mesh AABB in the painted orientation (so 2×2 / 3×3
  overhang cells are covered), 4 m falloff beyond the union; tile targets are
  **FLOOR-quantized at base + the toolbar's lift spinbox** (terrain meets the highest
  8-bit step at or below base + lift — never above, so a tall island's coarse steps
  can't poke terrain through the 0.24 m road deck; raise the lift to close the
  terrain-to-tile gap), one undo per terrain. Grid-aligned plateaus (terrain `terrace_levels`, plateau bands in whole 3 m
  roads-GridMap cells, flats snapped to the nearest 8-bit value — byte-exact at
  `height = 51`) mean painted road pads usually sit flush already, so Conform becomes a
  touch-up rather than a required step. Road Conform's plateau meets the tile at road − ε and `edge_drop`
  absorbs the quantization as usual. **Width:** the tiles' measured deck runs curb-to-curb ±4.8
  (9.6 m) with the white curb line AT ±4.8, so `asphalt_profile.tres` sets
  `lane_width = 4.8` — the ribbon's asphalt spans the full 9.6 m deck and its white
  edge line sits at ±4.8 flush with the tile's; line + shoulder extend outside like the
  curb strip (`road_profile.gd` script defaults are unchanged — 7 m surface /
  8.5 m paved). **Seam squareness:** extrude gives open-end rings the EXACT endpoint
  handle tangent (BAKER_VERSION v6) — the finite difference bends with immediate
  curvature and yawed port-snapped ends against the tile face. Bounded by
  `END_TANGENT_MAX_DEV_DEG`: a handle dragged further than that off the curve's own end
  direction is authoring noise, not a road direction, and falls back to the finite
  difference (unbounded, a 2 cm sideways handle yawed the end ring ~90° and the fold
  clamp pinched the road's first ring into a bowtie).
- **Bridge profiles cap their ends:** a cross-section whose polyline closes (what
  `base_depth > 0` emits) is triangulated onto the first and last ring, so the box is a
  solid, not an open tube you can see into — and drive into, since its walls and floor
  are welded into the drivable body.
- **Near-closed loops warn:** extrude only shares a seam frame when the end control
  points coincide, so a loop closed by eye leaves the end rings that far apart — past the
  1 mm weld, a real hole in the drivable collision. `RoadPath` flags an endpoint gap
  smaller than the ribbon's half-width.
- **Conform terrain is destructive-by-button** (the same discipline as terrain
  Generate): samples the curve at the **extrusion's `adaptive_offsets` rings**
  (deterministic — curve + the two segment params; NOT a fixed fine step, which would
  target the analytic curve where it rides above the ribbon's chords over a crest and
  poke terrain through right where roads tip into a descent), flattens every
  overlapping `HeightmapTerrain`
  to road height − `conform_epsilon`. Where a pixel lies under the deck, its target
  comes from **rasterizing the actual deck triangles** (a full-width strip extruded on
  the ribbon's own frames, incl. seam/end tangents, fold clamp and banking) — the
  centerline XZ-projection alone mis-heights the deck edges of segments that are both
  steep and yawing (the ruled surface shifts along-slope by up to
  half-width × sin(swing/2) × grade — tens of cm at authoring extremes; regression-
  tested against the real ribbon surface). Beyond the deck (the falloff ring) the
  target is lerped at the projection onto the nearest centerline segment (never the
  nearest point sample — off by up to half the sample spacing × the grade). The flatten plateau is the **full
  ribbon half-width incl. the drop skirt** (`full_half_width()`), so terrain under the
  skirt sits at a predictable road − ε and always crosses the skirt on its slope;
  `conform_falloff` smoothsteps out beyond the ribbon. Targets are **floor-quantized to
  the 8-bit grid** so the PNG can never store terrain above the ribbon — any ε > 0 is
  z-fight-safe, but the profile's `edge_drop` must absorb **ε + height/255** (conform
  warns per terrain when it can't). One `_commit_generated` undo action per terrain
  (PNG write + reimport, same pipeline as Generate/Auto-splat). Conforming changes
  heightmap bytes, so earlier scatter **trips its stale guard by design** — authoring
  order: terrain → roads + conform → splat → scatter, with the ScatterBase **Re-snap to
  ground** button recovering out-of-order edits.
- **Non-goals (permanent):** no junctions (cross two roads over a flat GridMap pad or a
  painted plaza), no lane-marking system, no traffic data.

## Global non-goals

No runtime/procedural world streaming, no in-game level editor, no texture-layer terrain
(color splat only), no LOD system (bake + draw-call budget cover web perf), no automatic
road junctions, and no replacement of the GridMap workflow for city grids — it remains
the right tool there.
