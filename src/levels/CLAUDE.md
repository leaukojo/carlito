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
  ordered tools, their args, and where the `--import` passes go. It is the ONE copy —
  generator headers point at it instead of restating it, and a generator edit means editing
  the manifest in the same commit. Replay one with
  `powershell -File tools/rebuild_level.ps1 -Level <id>`; it snapshots into `tmp/<id>_before/`
  (which is why `tmp/.gdignore` is committed — the uid-hijack rule in the root `CLAUDE.md`)
  and ends with a per-file identical/CHANGED diff. A manifest marked `"replayable": false` is
  REFUSED without `-Force` — that is levels 2-4, whose `gen_islands.gd` template would delete
  hand-added spawns and dressing. Not a CI gate: a replay takes minutes and rewrites
  committed content.
- **Level 1's paint chain is a fixed point; its sculpt is not, and that is accepted.**
  Replaying reproduces both splat PNGs byte-exactly, but moves ~150-250 heightmap pixels by
  1-3 of the 8-bit height steps every run, always in the farm's blend rims — `_flatten`
  re-lerps its rim on already-flat ground and `_smooth` is 4 passes over an already-smoothed
  one, and neither can be made idempotent. **So the diff CLASSIFIES a changed PNG instead of
  being made bit-exact**: `tools/png_drift.gd` decodes both copies and `rebuild_level.ps1`
  judges pixels-moved / max-step against the manifest's `sculpt_drift` map (no entry = byte
  equality). COMPROMISE: bit-equality would cost ~184 KB of committed baseline PNG and a
  re-zeroed drift baseline (the pre-farm heightmap is gone), to buy a guarantee nothing
  consumes.
- **Re-run `paint_road_asphalt` after any road or road-profile edit.** A stale paint is
  invisible — nothing in the bake, the tests or CI notices that the committed splat2 has
  stopped matching the road profile.
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
  (`LevelShot`), never a node (the level `.tscn` is a bake input). Shot from the Polish tab
  or `tools/gen_level_thumbs.tscn` (**windowed only**) into `src/ui/level_thumbs/` — it must
  stay under `src/`, since `kit/thumbs/*` and `tools/*` are export-excluded. The shot runs
  the BAKED level: bake first.
