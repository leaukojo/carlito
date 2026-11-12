# 2026-11-10: Queue item 1, the RoadPath fold

Started at de876c1, in the same conversation as unit 1 (the user's call).

## Finding (from unit 1)

`kit/helpers/road_path.gd` `_conform_terrain` and `_paint_splat` repeated
`tools/road_gen.gd` `footprint` / `conform` / `paint`: the sampling at
`RoadBuilder.adaptive_offsets`, the deck strip, and the terrain-local normalisation
(`(y - epsilon - origin_y) / height`, clamped). Two copies of one rule; a change to the
footprint had to land twice or an editor Conform would stop replaying a generated road.

## Fix

- New `kit/helpers/road_terrain.gd`: `footprint` (with the curve's world frame),
  `height_norm`, `leaves_height_range`, `conform`, `paint`. Kit cannot load `tools/`, so the
  core lives in kit.
- `road_path.gd`: both buttons call the core. Kept as they were: the per-terrain span
  (`_grid_dims() - 1` for Conform, `terrain_size` for Paint), the warnings, `_commit_generated`.
- `tools/road_gen.gd`: thin wrappers at RoadPath's export defaults on a square terrain at the
  origin; the three generators' call sites are untouched.
- `tests/test_road_terrain.gd`: six cases. Mutation check: dropping `- origin.x` in
  `_terrain_local` fails `test_conform_reads_the_road_in_the_terrains_frame` (break undone).
- Not folded: `tools/paint_road_asphalt.gd` paints a different footprint (0.5 m centreline
  steps, full width) and `check_bakes` dry-runs it; `gen_car_arena.gd` 756-777 paints its own
  strips. Neither is this duplicate.

## Proof

- `rebuild_level.ps1` on `level_5`, `car_arena`, `level_6` (the three `road_gen` callers): no
  PNG moved, so Conform and Paint write the same bytes. The replay's `.tscn` churn (random
  `unique_id`s, dropped `uid=`) is the generators' own and was restored with `git checkout`.
- Re-bake of every level: six `.bake.json` (the levels with a RoadPath) move `input_hash`
  only, every `output_hash` unchanged. `check_bakes`: 7 fresh, 0 stale.
- Editor parse (`--editor --quit-after 30`) clean; full suite 2423 cases, 0 failures;
  `preflight.ps1` passed.
- Not provable headless: RoadPath's two editor buttons (they need `EditorUndoRedoManager`).
  Listed under "Please verify".

## Commits

- ebea62a: the fold, its tests and the six bake records.

## Seen, outside the item

- A replay is not byte-identical on `.tscn` (`level_5.tscn` loses its `uid=` fields, every
  packed scene gets new `unique_id`s), against `tools/CLAUDE.md` "a refactor's replay must be
  byte-identical". For unit 17 (Generators).
