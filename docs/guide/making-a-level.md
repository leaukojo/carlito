[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Making a level

<p class="lead">This page walks through building a level in the Godot editor, in the order the
steps must happen.</p>

A level is a place to drive that makes signals easy to see: a steep hill raises `engine_load`, a
hairpin makes the tyres slip. It is not a mission with a goal.

<div class="box note">

Everything here happens in the Godot editor, mostly in the **Kit** panel at the bottom of the
screen, with five tabs: Palette, Terrain, Scatter, Roads and Polish. Every button and setting is
described in the repository's `docs/level_kit.md`. The worked example is Level 1, in
`src/levels/island/level_1/`. Levels 2 to 4 are dressed by hand on a scaffold that
`tools/gen_islands.gd` generates once; Levels 5 and 6 are made entirely by their own generators, `tools/gen_rail_level.gd` and `tools/gen_skyport.gd`.

</div>

## 1. A new scene and its LevelInfo

1. Duplicate `src/levels/base/level.tscn` into a new folder, `src/levels/<yourlevel>/`. It comes
   with the lighting (`WorldEnvironment`), the sun (`Sun`), the chase camera and one `Spawn`
   marker.
2. Create a `LevelInfo` resource (a `.tres` with the script `src/levels/base/level_info.gd`) and
   assign it to the `info` of the root `Level` node. Set:
   - `display_name`, the name shown in the menus;
   - `allowed_vehicles`, the families that may drive there, such as `car`, `truck` and
     `tractor`; left empty, it allows them all;
   - `default_vehicle`, which must be one of the allowed.

## 2. The ground

- **A flat level** needs only a box: a `StaticBody3D` with a box shape.
- **Hills** need a `HeightmapTerrain`. A heightmap is a greyscale picture whose brightness gives
  the height of the ground at each point. Pick a preset, adjust the settings, then press
  **Generate terrain (from seed)**. The settings are `gen_seed` (the random seed: the same seed
  gives the same island), `feature_scale` (metres per hill), `gen_octaves` (finer detail), the
  falloff band (how softly the island meets the sea), `coast_roughness` (0 a round coast, 1
  ragged bays), `terrace_levels` (flat plateaus) and `height` (the height of the brightest
  pixel). `docs/level_kit.md` § Terrain generation & splat ground has the rest.
- **Matching the road grid.** Road tiles sit on a grid whose steps are 3 m tall, and the ground
  must land on those steps to meet them. A pixel has 256 brightness values, so one brightness
  step is `height` / 255 metres, and 3 m must be a whole number of them: `height` must be 765
  divided by a whole number. Round choices include 25.5, 30.6, 38.25, 42.5, 45, 51, 63.75, 76.5, 85 and
  153 m; at 51 m, one step is exactly 0.2 m. `terrace_levels` then sets the plateau height in
  3 m steps (0 turns plateaus off). Ramps still need **Conform terrain** (step 4).
- **Sculpting by hand** uses the brushes on the Terrain tab (all of them:
  `docs/level_kit.md` § Terrain brushes). The "12 m (GridMap cell)" brush preset flattens a pad
  exactly one road tile wide in one click.
- **Water**, if any, is a `WaterSurface` at sea level, as a direct child of the level (never under
  Authoring, step 3), with a box-shaped kill volume, square to the axes, that respawns a
  vehicle that drives in. Add a `WorldBounds` node too, also a direct child, with its `extent`
  set to the water's `size`; its `ceiling_height` and `floor_depth` can stay as they are.

## 3. The Authoring node

Add one `AuthoringRoot` node named "Authoring". Everything the bake processes goes under it: road
grids, prefabs (ready-made objects such as buildings, each saved as its own scene), roads and
scatter. The terrain and the water stay outside it. A placed prefab lands in a folder for its
asset kit, `<Kit>Props` (a plain `Node3D`); road grids, roads and scatter stay directly under
Authoring. **Tidy authoring**, on the Palette tab's toolbar, sorts a flat Authoring node into
those folders. `docs/level_kit.md` § Authoring model has the detail.

## 4. Roads

- **Winding roads**: add a `RoadPath` under Authoring, then use Draw mode on the Roads tab with a
  road profile (`city`, `asphalt` or `gravel`). Flatten the ground under it with **Conform
  terrain**. Draping a road onto the ground and joining it to city tiles:
  `docs/level_kit.md` § Draw mode and drape.
- **City grids**: on the Palette tab, pick the roads kit and paint road tiles onto its grid (a
  Godot `GridMap`). A cell is 12 m across and 3 m tall; `road-curve` is a wide curve over 2 × 2
  cells, `road-bend` a tight corner in one. **Conform terrain**, on the Palette toolbar, flattens
  the ground under painted tiles and placed buildings.

## 5. Painting the ground

The ground's colour comes from a splat map: up to eight ground types mixed point by point, each
with its own colour. On the Terrain tab, **Auto-splat** picks grass, dirt, sand or rock from each
point's slope and height; then any of the eight can be painted by hand. Each type also sets the
tyres' grip there ([Ground and tyre types](surfaces.md)). Paint after the roads and Conform
terrain, so the paint follows the final heights. The eight types and the blend settings:
`docs/level_kit.md` § Terrain generation & splat ground.

## 6. Scatter

Trees, bushes, rocks and clutter, set onto the ground by a seeded random spread:

- **A large area**: add a `ScatterRegion` under Authoring. Give it a box or polygon outline and a
  list of `items`, each a `ScatterItem` (the prefab, its weight, and whether it collides); set the
  density, `placement_seed`, spacing, jitter and slope limits; then press **Regenerate**.
- **By hand**: add a `ScatterCanvas` and use the scatter brush on the Scatter tab (Paint, Erase or
  Rect). With `paint_pattern` set to `grid` and a `grid_step`, the brush places items on a regular
  lattice fixed to the world.

Scatter comes last: terrain, then roads and Conform terrain, then paint, then scatter. Scatter
remembers the ground it was placed on; after a later edit to the ground, the editor warns and the
bake refuses the level until **Re-snap to ground** (or **Regenerate**) sets the items back onto
the new ground. `docs/level_kit.md` § Scatter explains how.

## 7. Buildings and props

On the Palette tab, pick a kit and a family, click a thumbnail to pick up its prefab, then click
in the 3D view to place it; it lands in its kit's `<Kit>Props` folder under Authoring. Each prefab
has a `collision_mode` that sets its collision shape (the list: `docs/level_kit.md` § Authoring
model). `weld` joins it to the level's one drivable body at bake, for things driven on such as
ramps and bridges; a `weld` prefab inside scatter stops the bake with an error.

## 8. Spawn points

Drop a `VehicleSpawn` marker for every allowed vehicle and set its `vehicle_types`. The bake checks that every allowed vehicle has a spawn point
and stops if one does not.

## 9. Register, drive, bake

1. **Register** the level in `src/shell/level_registry.gd`: `id`, `name`, `scene` and `desc`.
   With `dev: true`, it is hidden from level select but still baked, checked and run by the
   automatic checks.
2. **Drive it before baking.** Open the scene and run it with **Run Current Scene**. Unbaked, the level uses simpler
   stand-in collision (the roads' and scatter's own meshes, each prefab's `DevCollision`), good
   enough to drive on. Driving it is how a level is checked.
3. **Bake**: select the Authoring node and press **Bake level (save scene first)**. It writes
   `<level>.baked.scn`, which the simulator loads, and `<level>.bake.json`, its record. Commit the
   `.bake.json`; the `.baked.scn` is rebuilt by the bake tool and is not committed.
4. **Record the chain**, if a command-line tool generated or changed the level: list its steps in
   `src/levels/<yourlevel>/<id>_gen.json`, with the tools, their arguments, the `--import`
   passes, and a `manual` step for editor work no tool can repeat. If running the chain again
   would destroy work done by hand, set `"replayable": false` with a `blocked` reason.
   `powershell -File tools/rebuild_level.ps1 -Level <id>` replays it; `level_1_gen.json` is the
   worked example.

   Some sculpting steps do not give exactly the same picture twice. Such a step gets a
   `"sculpt_drift"` entry (`{"<source>.png": {"max_px": N, "max_step": N}}`): the replay accepts
   a new picture whose changes stay within it, compared by `tools/png_drift.gd`. Without an
   entry, the pictures must be identical. Level 1's flattening and smoothing passes move about 150
   to 250 pixels by 1 to 3 steps at each run; making them exact would cost about 184 KB of stored
   reference pictures for a guarantee nothing uses.

## 10. Check the frame rate

The target is 60 frames per second in the level's heaviest view, on the published web build, not
in the editor. Open the debug overlay. When the frame rate is low, read the draw calls first:
each is one batch of drawing the graphics card is asked to do.

The bake's statistics predict the base count: the merged chunk surfaces, the scatter's multimeshes
and the terrain chunks. Shadows multiply it. The `Sun` defaults to four shadow maps split by
distance (PSSM), more than a 150 m shadow distance (`directional_shadow_max_distance`) needs.
Cheap fixes:

- Set the Sun's `directional_shadow_mode` to `ORTHOGONAL`, a single shadow map. Level 3,
  Level 6, Car Arena and Rough Ground use it. Over 150 m, each shadow pixel then covers about
  7 cm, which is why the web build keeps the sun's shadows soft (quality 1) rather than hard.
- Do not use `PARALLEL_2_SPLITS`: it makes buildings' shadows disappear while driving through a
  city, for no known reason. Reproduce that first before trying it again.
- Set `ScatterItem.cast_shadow = false` on small plants. Items baked as multimeshes then skip the
  shadow pass entirely.

If a level's base count is high, suspect its bake before changing render settings.

## Before you finish

- **Shoot the level card**, after the bake: move the 3D view to a good angle, then on the Polish
  tab press **Set thumbnail view** and **Shoot thumbnail**. Commit `<level>_shot.tres` and
  `src/ui/level_thumbs/<id>.png`.
- Re-bake, run the bake check and the preflight script; their commands are in the repository's
  `.claude/CLAUDE.md` § Running. With Claude Code, the `level-edit` skill runs these closing
  steps.

## Related

- [How the simulator is built](how-its-built.md): what a level is, and what baking does.
- [Ground and tyre types](surfaces.md): what the painted ground does to the tyres.
