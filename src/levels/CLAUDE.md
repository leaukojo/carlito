# Levels & water — gotchas & hard-won rules

- `HeightmapTerrain`: one cell = one world unit so mesh/collision coincide; heightmap +
  splat PNGs must import **lossless / no mipmaps** so runtime `get_image()` works.
  Generated PNGs also need `detect_3d/compress_to=0` and `process/fix_alpha_border=false` —
  `TerrainGen.ensure_import_settings` writes these.
- **Level 1's splat channel 4 is "Field"** — the ploughable soil, and the only honest "in
  soil" predicate for the tractor's `draft_force`. Not Dirt (ch 1): Auto-splat paints Dirt
  on every slope. Channel 4 lives in `splatmap2`, which Auto-splat **zeroes on purpose**
  (it reclassifies 0..3 from scratch, so a surviving 4..7 weight would double-count against
  the fresh base — `heightmap_terrain.gd:_auto_splat`). So pressing it on level 1 wipes
  Field/Mud/Gravel AND the road asphalt, and the recovery is to replay the level's chain.
- **A level's generator chain is a committed manifest**, `src/levels/**/<id>_gen.json`: the
  ordered tools, args, stages and `--import` passes. It is the ONE copy; a generator edit moves
  it in the same commit. Replay: `powershell -File tools/rebuild_level.ps1 -Level <id>`
  (snapshots into `tmp/<id>_before/`, hence the committed `tmp/.gdignore`, then diffs per file).
  `"replayable": false` (levels 2-4: `gen_islands.gd` would delete hand-added spawns) refuses
  without `-Force`. Not a CI gate: a replay takes minutes and rewrites committed content.
- **Level 1's replay is not bit-exact, and that is accepted**: its splats reproduce byte-exactly,
  but `_flatten`/`_smooth` move ~150-250 heightmap pixels by 1-3 steps each run. So
  `rebuild_level.ps1` CLASSIFIES a changed PNG (`tools/png_drift.gd` against the manifest's
  `sculpt_drift` map; no entry = byte equality). COMPROMISE: bit-equality would cost ~184 KB of
  baseline PNG to buy a guarantee nothing consumes.
- **Re-run `paint_road_asphalt` after any road or road-profile edit.** A stale paint is
  invisible — nothing in the bake, the tests or CI notices that the committed splat2 has
  stopped matching the road profile.
- **Level 2's mountain road is steeper than most bodies pull away on** (the curve's Y values,
  not the paint; figures: `docs/vehicles.md` § Gradeability). Nothing gates road grade:
  `measure_grade -- level=<id>` is a dev report. Reopened: `docs/to_investigate.md`.
- **Never run `paint_road_asphalt` on `car_arena`**: its scaffold paints its own roads at the inset
  paved width, then splat channel 4, **Ice**, under the ice road's bend only. The tool's full-width
  stamp would bury the ice, and nothing would notice.
- Water: `get_height()` is flat; shader waves are visual-only and **must never feed
  physics**. The kill volume is an axis-aligned rect — don't rotate the node. Water and
  terrain are direct children of the level, never under `Authoring`.
- **The water column is `Sea.y` over a pan `island_falloff` clamps to 0**, so the shared y=1
  makes every level 1 m deep and a depth reading a constant. Level 6's sea is at y=6 (ceiling
  6.6, where `gen_skyport.gd`'s canyon repaint walk starts); `depth` and `sand_height` move with
  it or they read wrong silently. Level 6's boat playground — the sandbar, the buoyed channel and
  the measured leg — is likewise stated as offsets from `SEA_Y`, and the marks are floated at it
  by `_place_afloat` because the watercraft kit aligns buoys `raw` (their origin IS the
  waterline), not on a measured base like every other piece.
- `Level` owns **two** environment fields — `wind` (`WindField`) and `current` (`CurrentField`) —
  both null-by-default `.tres` side-cars, both sampled off one `_env_time`, both naming the
  heading the flow goes **TOWARD**. `CurrentField` is a SIBLING of `WindField`, not a subclass:
  they share `base_vector` and the convention, and nothing else. The pause-menu CONDITIONS page's
  override (`Level.set_conditions`, `src/levels/base/world_conditions.gd`) replaces `wind`/
  `current` at runtime; its LEVEL preset restores the authored side-cars captured in `_ready`.
- **The endless levels' surfaces follow the camera**, so `water.gdshader` and
  `ground_grid.gdshader` must stay WORLD-space: a model-space pattern slides with every re-centre.
- Day/night is a Level concern (N key), not a bridge signal.
- **Everything under `island/` ships in a level pack, not the main `.pck`** (`LevelPacks`): a new
  island needs a `Web <id>` export preset, and `tests/test_export_filter.gd` names the exact one.
- **Level-select cards**: the screenshot camera is a side-car `<level>_shot.tres`
  (`LevelShot`), never a node (the level `.tscn` is a bake input). The PNG goes to
  `src/ui/level_thumbs/` (`kit/thumbs/*` and `tools/*` are export-excluded). The shot runs the
  BAKED level: bake first.
