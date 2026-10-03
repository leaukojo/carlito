# Kit, bake & editor tools — rules

Authoring tour: `docs/level_kit.md`. Bake freshness, `BAKE_CODE_INPUTS`, scene tags and the
headless gotchas are in the root `CLAUDE.md`. A level edit ends with the `level-edit` skill.

- **A runtime-loaded `@tool` script never types an editor-only class** (annotations resolve at
  parse time whatever `Engine.is_editor_hint()` says, so the script silently fails to load in
  an export). Fetch editor singletons via `Engine.get_singleton(&"EditorInterface")` into
  **untyped** vars. Only `addons/carlito_kit/` may type editor APIs. Guard: pre-commit gate 1.
- Regenerate palettes/prefabs (`gen_kit_assets.gd`) only after recipe/kit edits; meshlib item
  ids survive regens so painted GridMaps never break. Every GLB must match a recipe family or
  the generator fails; an exclude needs a `reason`. Embedding a new thumbnail re-stales the
  bakes that use it.
- Per-kit scales live in the recipe, `kit/import/<kit>.json` (lane-fit: ~12 m two-lane vs the
  1.8 m car). Roads palette cell `(12,3,12)`; racing `(12,12,12)` corner-anchor. **Every palette
  GridMap needs `cell_center_y = false`** (bake error).
- AuthoringRoot holds only GridMaps, KitPieces, scatter, roads and script-less Node3D groups —
  it is freed at runtime, so anything else is a bake error.
- The convex-decomposition helper is `create_multiple_convex_collisions` (plural).
- `SurfaceTool.append_from` leaves scaled normals unnormalized: the baker's
  `SurfaceAccumulator` merges at array level instead.
- Terrain render mesh is chunked for frustum culling (not LOD); collision stays ONE
  `HeightMapShape3D`. Normals are analytic (per-chunk `generate_normals()` seams borders); UVs
  global. The splatmap is sampled raw (no `source_color`: sRGB bends weights).
- Scatter: the stored transforms in the `.tscn` are the only artifact (no expansion at
  bake/runtime). Ground snap drops un-snappable points (no Y=0 fallback). A terrain edit trips
  the stale-scatter guard (config warning + bake gate + CI); **Re-snap to ground** recovers.
  Weld-mode prefabs in scatter are a bake error.
- Roads: the ribbon derives from curve + profile alone (never reads terrain), on a custom frame
  (never `sample_baked_with_rotation`: parallel transport accumulates roll). The profile default
  is set in editor `_ready`, never as a preload export default (a default-equal value is omitted
  from the `.tscn`, an input-hash hole). Conform flattens the **full half-width incl. skirt**,
  projects onto the nearest centerline **segment** (nearest sample is wrong on grades) and
  floor-quantizes to 8-bit, so `edge_drop` must absorb ε + height/255 (conform warns).
- Rails are a `RoadPath` carrying `RailProfile`; every road tool applies unchanged. Its rib walls
  are vertical, so its cross-section drops degenerate strips on **both** axes. The baker emits a
  `RailTrack` per rail road (the runtime curve); `RailTrack.find_closed_rail` is the one walk
  that finds a loop, so the train never runs where the level refuses to spawn it.
- Authoring order: terrain → roads + conform → splat → scatter (conform trips the scatter guard
  by design). A generator that owns a level overwrites it, hand edits included; its chain and
  stages are the level's `<id>_gen.json` (`src/levels/CLAUDE.md`).
- `bake_levels` rewrites every `.baked.scn`'s raw bytes on each save (`PackedScene.pack()` stamps
  fresh random ids), so the manifest's `output_hash` is a canonicalized re-serialization
  (`LevelBaker.canonical_output_hash`). Bake one level with `-- src/levels/<level>.tscn`.
- COMPROMISE: colormap `451b163d` ships three byte-identical times (garage, parked, kenney
  vehicles). Deleting a copy silently reverts (each `.glb` re-resolves its sibling `Textures/` on
  every import); undoing it costs GLB surgery or content-hash dedup in the baker.
