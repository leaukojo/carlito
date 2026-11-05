# Review: duplication and dead code in `tools/`

Scope: `tools/` (the `gen_*` and `measure_*` scripts, the bake and check scripts, the `.mjs` and
`.ps1` helpers) and `tools/CLAUDE.md`. This is a findings file only: nothing in the repo is
changed. Line numbers are against `claude/busy-cori-bmamdo` at `5ec328a`.

How bake staleness works here (`kit/bake/level_baker.gd`): `gather_bake_inputs` hashes the level
scene, its transitive dependencies and `BAKE_CODE_INPUTS`. `is_bake_input` keeps every dependency
under `res://kit/`, including `.gd` files, plus every non-`.gd` dependency outside `addons/`. As a
result:

- Code under `tools/` is never hashed, and neither is `src/**.gd` except the three `src/` files
  listed in `BAKE_CODE_INPUTS` (`carlito_groups.gd`, `rail_track.gd`, `collision_layers.gd`).
  No finding below edits those three, so a pure refactor of the code it names re-stales nothing.
- Generator *output* (PNGs, `.tscn`, `.tres`) is hashed. A refactor of a level generator keeps
  bakes fresh only if a replay is byte-identical. Check it with `rebuild_level.ps1 -Level <id>`
  (its diff report), then `check_bakes.tscn`.
- `kit/helpers/road_builder.gd` is in `BAKE_CODE_INPUTS`, so editing it re-stales every level.
- `kit/helpers/road_path.gd` is a `res://kit/` script dependency of every level with a RoadPath,
  so editing it re-stales levels 1, 2, 4, 5, 6 and car_arena.

Each finding's **Bake** line says which of these cases applies.

Priority follows the brief: `measure_vehicles.gd` and `gen_kenney_vehicles.gd` come first. Most
of the `measure_*` overlap lands in `tools/measure_rig.gd`, which `tools/CLAUDE.md` already names
as the home for shared measure setup.

---

## Summary

| # | What | Shared function (home) | Sites | Bake |
|---|---|---|---|---|
| M1 | spawn a body on the slab | `MeasureRig.spawn`, `free_body`, `slope_pose` | 5 tools | none |
| M2 | in-memory spec overrides | `MeasureRig.own_ground_drive` | 13 blocks | none |
| M3 | PI speed hold | `MeasureRig.pi_hold`, `pi_pedal` | 10 | none |
| M4 | trailer-roll doc table | `MeasureRig.TRAILER_ROLL_CONFIGS`, `TrailerWatch.summary`/`cell`, `chatter_runs` | 2 tools | none |
| M5 | drive / diff / wheel / gear labels | `MeasureRig.diff_label`, `layout_label`, `wheel_label`, `gear_label` | 3 tools | none |
| M6 | variant lists, spec reads | `MeasureRig.wheel_driven_variants`; `VehicleCatalog.spec_of` (src) | 7 + 3 tests | none |
| M7 | rig bodies, coupled mass | `MeasureRig.rig_bodies`, `towed_mass` | 5 | none |
| M8 | CLI flag parsing | `MeasureRig.flag`, `float_flag`, `gear_flag`, `common_flags`, `variants_arg` | 5 tools | none |
| M9 | shift record and label | `MeasureRig.shift_record`, `shifts_label` | 2 tools | none |
| M10 | challenge course and spawn lookup | `VehicleSpawn.first_under` (src) | 5 | none (src `.gd`) |
| M11 | tyre grip budget re-derived; gravity as a literal | `RayWheel.long_budget` / `lat_budget` (src); `BrakeSizing.G` | 3 (+2 in src) + 38 literals | none |
| K1 | Kenney / boat scene assembly | new `tools/vehicle_gen_io.gd` | 10 pairs | none (see K1) |
| K2 | `_axles` re-derives `BrakeSizing.axle_geometry` | `BrakeSizing.axle_geometry` | 3 callers | none |
| L1 | world ↔ pixel mapping | new `tools/terrain_grid.gd` | 3 generators | output must stay byte-identical |
| L2 | flatten, merged AABB, apron GridMap, prop place | `LevelGenIO.*` | 2 generators | output must stay byte-identical |
| L3 | road conform and paint footprint | new `tools/road_gen.gd` | 5 in 3 generators + 2 in RoadPath | output must stay byte-identical; RoadPath re-stales 6 |
| L4 | PNG write with the uid guard | `LevelGenIO.write_png(..., expected_dir)` | 2 | none (same bytes written) |
| T1 | thumbnail fog and save tail | `ShotStage.thin_fog`, `save_card` | 3 | none |
| T2 | kit recipe loading | `KitRecipe.recipe_paths`, `load_recipe` | 2 | none (see T2) |
| H1 | **PARTLY DONE** Godot binary resolution; runs that bypass `godot_run.mjs` | `godot_run.mjs` for every run | 4 + 4 | n/a |
| H2 | gate patterns repeated in CI, hook and preflight | `check_gd_text.mjs`; new `godot_verdict.mjs` | 3–5 each | n/a |
| H3 | **PARTLY DONE** contract-sync block | `gen_js_contract.mjs --check` | 3 | n/a |
| X | dead state, keys, args, functions | delete or document | 6 | none |

---

## measure_* tools

### M1. Spawning a body on the slab (5 copies)

The tools repeat the same sequence: free the old body, instantiate the scene, `unfit_esc`, apply
spec overrides, `add_child`, set the pose, `spawn_transform`, `reset_physics_interpolation`.
(`measure_drone` spawns once, so it has no free and no `unfit_esc`.)

- `measure_vehicles.gd:1208-1211` (free) and `:1268-1316` (`_next_vehicle`)
- `measure_grade.gd:408-437` (`_spawn`)
- `measure_semi_launch.gd:158-162` (free in `_next_doc_run`) and `:182-198` (`_spawn`)
- `measure_air_loss.gd:141-152` (`_spawn`, which already takes a pose `Callable`)
- `measure_drone.gd:94-98`

The sloped pose is the same formula twice: `tilt * (0, 0, -up) + tilt.y * rest_ride_height`, at
`measure_grade.gd:432-434` and `measure_air_loss.gd:127-131`.

**Shared:**
- `MeasureRig.spawn(parent, variant, pose: Callable, prep := Callable()) -> Node`. It instantiates
  `VehicleCatalog.scene_of(variant)`, calls `unfit_esc`, then `prep` (the per-tool spec
  overrides, before `add_child` so the wheels build from them), `add_child`, the pose, then
  `spawn_transform` and `reset_physics_interpolation`.
- `MeasureRig.free_body(parent, body)`.
- `MeasureRig.slope_pose(body, angle, up, yaw := 0.0, lift := 0.0) -> Transform3D`.
- `MeasureRig.flat_pose(body, x, z) -> Transform3D`.

**Call sites:** the five above. `measure_rough` respawns through its Level and stays as it is.

**Bake:** none.

### M2. In-memory spec overrides (13 duplicate-and-set blocks)

Each block runs `spec.duplicate()`, then `ground_drive.duplicate()`, then sets one field:

- `measure_vehicles.gd:1270-1297`: six blocks (`j=`, `rear_lat_grip=`, `bar_rear=`,
  `bar_front=`, `cornering_peak=`, `ackermann=`). With all six set, the spec is copied six times.
- `measure_grade.gd:418-425`: two blocks (`nohold`, `cornering_peak=`).
- `measure_semi_launch.gd:243`: one `duplicate(true)` (deep) for its geometry override.
- `measure_rig.gd`: `unfit_esc`, `unfit_trailer_roll`, `apply_roll_steer`, `apply_compliance`, the
  same pattern four more times.

The `cornering_peak=` parse plus its override is identical in vehicles (`:954`, `:1291-1294`) and
grade (`:251`, `:422-425`).

**Shared:**
- `MeasureRig.own_ground_drive(body) -> GroundDriveSpec`. It copies the spec and ground drive
  once, skips the copy when `ground_drive.resource_path` is already empty (an earlier copy), and
  returns the drive to edit.
- `MeasureRig.spec_flag_overrides(args) -> Dictionary` and
  `MeasureRig.apply_spec_overrides(body, overrides)` for the field flags the two tools share.

**Call sites:** the 13 blocks above.

**Check first:** confirm that no shipped body builds its spec in code with an empty
`resource_path` shared across instances. If one does, `own_ground_drive` would edit it in place.

**Bake:** none.

### M3. The PI speed hold (10 copies of one law)

The same law, `i = clampf(i + err*KI*dt, 0, 1); u = clampf(i + err*KP, 0, 1)`, appears at:

- `measure_vehicles.gd:2470` (corner), `:3258` (step), `:3372` (sine), `:4026` (circle), `:4374`
  (course), `:4394` (plough hold), `:4827` (kerb), `:5192` (`_cruise_pi`)
- `measure_grade.gd:1839-1844` (`_decel_pedal`)
- `measure_grade.gd:1383` (`overspeed_hold`): already this exact law as a pure static, tested in
  `tests/test_measure_descent.gd:10-26`

The vehicles sites all use `CORNER_PEDAL_KP/KI`. The name is stale, since eight passes share it.

**Shared:**
- Move `overspeed_hold` to `MeasureRig.pi_hold(integral, err, delta, kp, ki, freeze := false)
  -> Vector2`. `freeze` covers the two sites that hold the integral: corner, until the
  ramp starts (`_corner_ramping`), and cruise, during `shift_cut_active()`.
- Move `_pi_pedal` (`measure_vehicles.gd:5204`) to `MeasureRig.pi_pedal(body, u, v_set)`.
- Rename the gains `SPEED_HOLD_KP/KI`.

**Call sites:** the ten above, plus the test's preload.

**Leave alone:** `measure_semi_launch._ramp_step` (`:641`). It uses a signed, unclamped integral
with a brake half, which is a different law.

**Bake:** none.

### M4. The trailer-roll doc table, built twice

- Configs: `measure_semi_launch.gd:33` `DOC_CONFIGS` is the same array as
  `measure_vehicles.gd:413` `DOC_TRAILER_ROLL_CONFIGS`.
- Summary of a `TrailerWatch`: `measure_semi_launch.gd:672-683` (`_record_doc_run`) and
  `measure_vehicles.gd:3961-3971` (`_trailer_summary`). The key names drift: `trailer_chatter`
  in one, `chatter` in the other.
- Cell: `measure_semi_launch.gd:689` `_p7_cell` and `measure_vehicles.gd:3974` `_trailer_cell`
  use the same format. Only the `holds` wording differs.
- `measure_semi_launch.gd:28` preloads all 5.9k lines of `measure_vehicles.gd` just for
  `chatter_runs` and `ESC_CHATTER_EPS`.

**Shared:**
- `MeasureRig.TRAILER_ROLL_CONFIGS`.
- `TrailerWatch.summary(delta) -> Dictionary`, with one key set.
- `TrailerWatch.cell(s, tractor_over, holds := "holds")`.
- Move `chatter_runs` with `CHATTER_FLIPS/EPS/REL` and `ESC_CHATTER_EPS` into `measure_rig.gd`.
  `tests/test_measure_chatter.gd` then preloads the rig.

**Call sites:** the two tools and the test.

**Bake:** none. The two regions' text stays the same if the `holds` wording passes through.

### M5. Label helpers (copies, and a cross-tool reach into a private function)

- `_diff_label`: byte-identical at `measure_vehicles.gd:5366` and `measure_rough.gd:666`.
  `measure_grade.gd:704` calls the vehicles copy as `MeasureVehicles._diff_label`, a private
  function, through a preload of the whole tool (`:78`).
- The AWD/FWD/RWD layout string is built at `measure_vehicles.gd:5356`, `measure_rough.gd:642`
  and `measure_grade.gd:700`. `src/` has two more copies with the MFWD reading:
  `src/levels/garage/garage.gd:71` and `src/ui/vehicle_select.gd:643` (`_drive_text`).
- `_wheel_label`: `measure_vehicles.gd:2355` handles multi-axle bodies (`A1L`…).
  `measure_rough.gd:681` labels by `is_rear` only, so a tandem prints two `R` pairs.
- `_gear_label` (`measure_vehicles.gd:2366`). `measure_grade.gd` prints `"D%d"` inline at
  `:1210`, `:1223`, `:1227`, `:1239` and `:1676`.

**Shared:** `MeasureRig.diff_label(gd)`, `MeasureRig.layout_label(gd)`,
`MeasureRig.wheel_label(body, w)` (the vehicles version) and `MeasureRig.gear_label(byte)`.

**Follow-up in src (out of scope):** a static `GroundDriveSpec.layout_text()` would also merge
the two `src/` `_drive_text` copies.

**Note:** moving rough to the multi-axle `wheel_label` changes its per-wheel lines on three-axle
bodies. `doc=rough` prints no per-wheel labels.

**Bake:** none.

### M6. Variant lists and specs read by instantiating

- `_wheel_driven_variants`: identical at `measure_vehicles.gd:1173` and `measure_grade.gd:340`.
  The grade copy's comment says "same filter measure_vehicles.gd uses".
- Instantiate a scene, read `spec`, free it: `measure_vehicles.gd:1188` (`_tyre_fit`), `:3519`
  (`_sine_variants`), `measure_grade.gd:909` (creep), `:2094` (`_dsc_trailer_t`, which also
  calls `rig_mass` and so instantiates the same body twice), `measure_rig.gd:428`
  (`rig_mass`).
- `Catalog.VARIANTS[v]["scene"]` appears 11 times across the measure tools. `src` already has
  `VehicleCatalog.scene_of(variant)` for this.
- `tests/test_kenney_variants.gd:530`, `test_tyre_class.gd:17` and `test_vehicle_catalog.gd:1094`
  each carry a `_spec_of` that reads the root's `spec` off `PackedScene.get_state()` without
  instantiating.

**Shared:** `VehicleCatalog.spec_of(variant) -> VehicleSpec` in src, using the `get_state` read
so no orphan sub-scenes are created. Then `MeasureRig.wheel_driven_variants()` builds on it. The
two helpers in `test_tyre_class.gd` and `test_vehicle_catalog.gd` are already byte-identical.
`get_state` returns null when the root scene does not set `spec` itself (a value from an
inherited base scene or a script default), so the helper falls back to instantiating then.

**Call sites:** the seven sites above and the three test helpers.

**Bake:** none (`src/vehicles/vehicle_catalog.gd` is a `.gd` outside `kit/`).

### M7. "The rig": four definitions

- `measure_vehicles.gd:2724` `_rig_bodies`: sibling RigidBody3Ds that have `wheels`.
- `measure_vehicles.gd:2733` `_combination_mass`: every sibling RigidBody3D. This is a different
  filter in the same file, and the doc comment above `_rig_bodies` (`:2722`) describes the mass.
- `measure_grade.gd:672` `_coupled_mass`: reads the private fields `_fifth_wheel` / `_drawbar`
  when `TowHost.towed_mass_kg` is the public API.
- `measure_grade.gd:1870` `_rig_bodies`: built off `_dsc_trailer`.
- `MeasureRig.apply_angdamp` (`measure_rig.gd:310`) already builds `[body, coupled trailer]`
  inline, and `MeasureRig.towed` / `coupled_host` exist.

**Shared:** `MeasureRig.rig_bodies(body) -> Array[RigidBody3D]` (through `coupled_host`) and
`MeasureRig.towed_mass(body)`.

**Call sites:** the four above and `apply_angdamp`.

**Bake:** none.

### M8. Command-line parsing (every tool by hand)

Each tool loops over `begins_with("x=")` and `substr(<magic length>)`:

- `measure_vehicles.gd:931-984` (~25 flags)
- `measure_grade.gd:246-258` and `:285-288`
- `measure_rough.gd:162-169`
- `measure_semi_launch.gd:123-125`, `:236-243` and `:264-285`
- `measure_rig.gd`'s own six `*_flag` functions, each with its own loop

The same `gear=` validation appears at `measure_vehicles.gd:979-984` and `measure_grade.gd:253-258`.
`noesc` is read in all five tools, and `noabs` / `notrsp` / `nosurge` beside it.

The first-argument variant choice (`all`, one variant, a list, or an error) is written five ways:
`measure_vehicles.gd:1114-1150`, `measure_grade.gd:316-325`, `measure_air_loss.gd:94-101`,
`measure_semi_launch.gd:126-129` and `measure_rough.gd:209-216`.

**Shared:**
- `MeasureRig.flag(args, "name=") -> String` (empty when absent).
- `MeasureRig.float_flag(args, "name=", default)`.
- `MeasureRig.gear_flag(args) -> int` (-1 after printing the error).
- `MeasureRig.common_flags(args)` for the four LAB/ESC booleans.
- `MeasureRig.variants_arg(which, all: Array[String]) -> Array[String]` (empty after printing the
  error).

The existing `*_flag` helpers rebase onto `flag`.

**Call sites:** the parse blocks above.

**Bake:** none.

### M9. The shift record, twice, with different semantics

- `measure_vehicles.gd:2058` `_shift_record` writes `{t, from, to, kmh, before, land, pedal}`
  with unclamped crank rpm (`_wheel_rpm`). Its labels and gates are at `:2073` and `:2088-2120`.
- `measure_grade.gd:1198-1205` writes the same record as `landing`, not `land`, and clamps it to
  idle..redline through `Drivetrain.rpm_from_wheel`. Its own label and "falls back" gate are at
  `:1222-1243`.

**Shared:** `MeasureRig.shift_record(body, t, from, to)` and `MeasureRig.shifts_label(shifts)`.
Grade keeps its own falls-back gate, since it asks a different question than hunting, but runs
it on the shared record.

**Note:** unifying on the unclamped rpm changes grade's climb printout wherever a shift lands past
the limits. That is a measured-output change, so name it in the commit.

**Bake:** none.

### M10. Challenge course loading and the spawn lookup

- `measure_rough.gd:240-270` `_load_course` reproduces `ChallengeRunner._build_course`
  (`src/challenges/challenge_runner.gd:153-176`).
- The loop "first VehicleSpawn under a node that accepts the family" appears at
  `challenge_runner.gd:166`, `src/shell/challenge_registry.gd:273`, `measure_rough.gd:254` and
  `gen_challenge_thumbs.gd:59-62`. `Level.spawns_for` (`src/levels/base/level.gd:399`) is the
  instance form for a level's own subtree.

**Shared:** `static VehicleSpawn.first_under(root, family) -> VehicleSpawn` in
`src/levels/base/vehicle_spawn.gd`.

**Call sites:** the four loops; `spawns_for` can build on it.

**Bake:** none. `vehicle_spawn.gd` is a level-scene script dependency, but a `.gd` outside `kit/`
fails `is_bake_input`.

### M11. Re-derived tyre budgets, and g written two ways

- The load-scaled grip budgets from `src/vehicles/base/wheel.gd:470-474` and `wheel_drive.gd:478-481`
  are re-derived in `measure_vehicles.gd`:
  - `:2594` `_long_budget`
  - `:2575-2591` `_axle_saturation` (the lateral budget)
  - `:1665-1672` `_split_deficit` (again)
- Gravity as a literal. `BrakeSizing.G` is 9.8, and so is the project's gravity, since
  `project.godot` sets no `default_gravity`. The tools write `9.81` 38 times (32 in vehicles, 4
  in grade, 2 in semi_launch):
  - 27 are g conversions (`/ 9.81`): 25 in vehicles, 2 in semi_launch. `TrailerWatch` reports
    `lift_g` through `StabilityControl.G` (9.8), so the doc=trailer_roll corner cell prints its
    `peak_g` (9.81) and the trailer's lift g (9.8) side by side.
  - 7 are weights (`mass * 9.81`): vehicles `:2196` (`_kingpin_load`), `:2849` and `:2884`
    (declared rolling drag); grade `:534`, `:640`, `:659` and `:1118`. `_kingpin_load` subtracts
    the trailer's spring forces, which carry 9.8 m/s² of weight, from its mass × 9.81, so it reads
    mass × 0.01 N high (240 N at 24 t).
  - 4 are the wheel's reference load (`corner_mass * 9.81`), the sim's own figure at
    `wheel.gd:470`.
  - `measure_grade._rig_energy` (`:1882`) reads gravity from `ProjectSettings` instead.

**Shared:**
- In src, `RayWheel.long_budget(gd)` / `RayWheel.lat_budget(gd)` instance methods, used by
  `wheel.gd` and `wheel_drive.gd` themselves and by the tool.
- In the tools, `BrakeSizing.G` for every g conversion and weight. The four reference loads go
  through the new methods, so the tools stop restating them.

**Note:** g figures in the doc regions move by about 0.1 % (third decimal) on their next
regeneration. Rule 3 makes "the sim's own g" the right figure.

**Bake:** none.

### Other duplicates inside `measure_vehicles.gd`

- `_front_axle_load` (`:2226-2236`) inlines `_front_z` (`:2164`) instead of calling it.
- `measure_semi_launch.gd:210-211` prints the wheelbase as
  `absf(wheel_positions[2].z - wheel_positions[0].z)`. That depends on array order. Use
  `BrakeSizing.axle_geometry`, which `measure_vehicles._wheelbase` (`:4951`) already uses.
- `_write_report` (`:5810`) hard-codes "zero steer input" in the sweep header. `_ready` builds
  the correct `steer_label` (`:1155-1165`) and drops it. Keep the label in a member and use it
  in both places.

---

## gen_kenney_vehicles.gd and gen_boat_variants.gd

### K1. Body-generator scene assembly (10 pairs)

`gen_boat_variants.gd` is a trimmed copy of the Kenney generator's scene half:

| Kenney | Boat | Difference |
|---|---|---|
| `_scaled_curve` `:1341` | `:135` | identical |
| `_own` `:1433` | `:262` | identical |
| `_add` `:1683` | `:292` | identical |
| `_xform_aabb` `:2017` | `:353` | identical, and Godot's `Transform3D * AABB` already does this; `gen_skyport.gd:1036` and `gen_farm_playground.gd:718` use the operator |
| `_existing_children` `:1455` | `:241` | Kenney adds the `_model_of` fallback scene |
| kept-or-generated collision `:1362-1374` | `:184-196` | verbatim |
| GLB children into `Model` `:1378-1391` | `:198-209` | Kenney skips corner wheels |
| `_ready` save loop `:875-899` | `:81-103` | same spec save, scene save and count |
| convex hull `_body_shape` `:1482` | `:269` | Kenney clamps y to `MIN_CLEARANCE`; box fallbacks differ |
| headlight `_spot` `:1661` | inline `:214-221` | same range 28, angle 38, energy 0 |

**Shared:** a new `tools/vehicle_gen_io.gd`, the body-generator sibling of `level_gen_io.gd`:
- `scaled_curve(flat, mul)`, `own(node, owner)`, `add(owner, parent, child)`
- `existing_children(out_dir, variant, generated, fallback_path := "")`
- `add_collision(root, kept, make_shape: Callable, report: Array)`
- `steal_model(root, glb_path, xform, skip := Callable())`
- `hull_shape(pairs, xform, clamp_y := -INF) -> Dictionary`
- `headlight(name, pos) -> SpotLight3D`
- `write_variant(out_dir, variant, spec, build_scene: Callable) -> bool`

Delete both `_xform_aabb` copies for `xform * aabb`.

**Call sites:** the 20 functions and blocks above. `tests/test_kenney_variants.gd` uses `Gen._cvt`,
`Gen._model_of` and `Gen.new()._suspension_recipe`; none of these move.

**Bake:** none, if the regen is byte-identical. `test_kenney_variants` already checks this through
`StableSave.churn_key`. The only level scene that depends on a Kenney body is
`src/levels/dev/flat.tscn` (`sedan.tscn`), and it has no AuthoringRoot, so it never bakes. No
level depends on a watercraft scene.

### K2. `_axles` re-derives `BrakeSizing.axle_geometry`

`gen_kenney_vehicles.gd:1283-1300` (`_axles`) is `BrakeSizing.axle_geometry`
(`src/vehicles/base/brake_sizing.gd:48-60`) plus `_static_front_share` (`:64-71`), without the
clamp. `GRAVITY := 9.8` (`:62`) is `BrakeSizing.G`.

**Shared:**
- `BrakeSizing.axle_geometry(spec)`, plus a public `BrakeSizing.static_front_share(spec, ax)`
  (rename the private one).
- `BrakeSizing.G`.

**Call sites:** the three callers of `_axles`: `_front_brake_share` (`:1253`), `_derive_springs`
(`:1315`) and `_derive_link_slopes` (`:1333`). Between them they read `wheelbase`, `n_front` /
`n_rear` and `static_front`, and each treats an empty result as "no axle pair". So the shared form
returns `axle_geometry` plus the two derived keys, and is empty without a pair. Before
switching, confirm that `spec.ground_drive == gd` at each call (it is assigned at `:929`).

**Bake:** none. The regen must stay byte-identical; a COM between the axles makes the clamp a
no-op.

### K3. `measure_vehicles` → `gen_farm_playground` coupling (keep)

`measure_vehicles.gd:273` preloads a 982-line generator only for `LIGHT_SOIL_MIX` and
`LIGHT_SOIL_BANDS`. That is the right direction, since it reads one source instead of copying
the constants. Moving the two constants to a small `level_1` data script would end the coupling,
but it is optional.

---

## Level generators

### L1. World ↔ pixel mapping (3 copies)

`_norm`, `_px_x`, `_px_z`, `_world_x` and `_world_z` appear at (skyport has no `_world_z`):

- `gen_car_arena.gd:1426-1444`
- `gen_skyport.gd:1327-1341`
- `gen_farm_playground.gd:837-855` (adds a terrain origin and span)

**Shared:** `tools/terrain_grid.gd`, a RefCounted built from size, origin, height and image size,
with `px_x`, `px_z`, `world_x`, `world_z` and `norm`. Car arena and skyport pass a zero origin.

**Bake:** none if output is byte-identical. Verify with `rebuild_level.ps1 -Level car_arena`,
`-Level level_6` and `-Level level_1` (all three manifests are `"replayable": true`), then
`check_bakes`.

### L2. Farm ↔ skyport copies

| Function | Farm | Skyport | Difference |
|---|---|---|---|
| `_flatten` | `:290` | `:390` | identical |
| `_merged_aabb` | `:714` | `:1032` | identical |
| `_build_apron_gridmap` | `:414` | `:875` | constants and log tag |
| `_place` | `:694` | `:993` | log line |

**Shared** (in `LevelGenIO` or a new `tools/level_gen_props.gd`):
- `merged_aabb(node, xform)`
- `flatten(img, grid, rect, y, margin)`, taking L1's grid
- `apron_gridmap(meshlib, tile, centre, y, tag)`
- `place_prefab(parent, path, at, yaw, tag, quiet := false)`

**Bake:** same as L1.

### L3. Road conform and paint footprint (7 copies of one geometry)

The geometry is the centreline samples at the extrusion's ring offsets plus a deck strip
extruded at a half-width. It appears at:

- `gen_car_arena.gd:510` `_conform` and `:531` `_paint_road_splat`
- `gen_skyport.gd:491` and `:512`
- `gen_rail_level.gd:290` `_conform`
- the editor original, `kit/helpers/road_path.gd:417` `_conform_terrain` and `:511`
  `_paint_splat`

The copies already drift: skyport has a `pw <= 0` guard (`:515`) that car_arena lacks.
`gen_skyport._report_road` (`:732-758`) re-scans for the tightest corner after calling
`RoadBuilder.min_turn_radius`, and its steepest-grade scan has a twin in
`measure_grade._report_road` (`:2224`).

**Shared:** `RoadGen.footprint(curve, half_width, banking) -> {samples, deck}`, plus
`RoadGen.conform(heights, curve, profile, falloff, size, norm: Callable)`,
`RoadGen.paint(splat, splat2, curve, profile, size)` and `RoadGen.steepest_grade(curve, step)`.

**Home and bake:**
- In `kit/helpers/road_builder.gd`: it is in `BAKE_CODE_INPUTS`, so every level re-stales.
- In `road_path.gd`: levels 1, 2, 4, 5, 6 and car_arena re-stale.
- In a new `tools/road_gen.gd`: no code bake input moves; the generators' output must still
  replay byte-identical, as in L1.

Recommend `tools/road_gen.gd` now, used by the three generators. Fold RoadPath onto it in a
commit that rebakes anyway.

### L4. PNG write with the uid-hijack guard

- `gen_farm_playground.gd:803` `_write` is `LevelGenIO.write_png` plus the guard from the root
  CLAUDE.md gotcha (the path must resolve inside the level's directory).
- `paint_road_asphalt.gd:169-176` saves and calls `ensure_import_settings` inline, without the
  guard.

**Shared:** `LevelGenIO.write_png(img, path, tag, expected_dir := "")`.

**Call sites:** farm and `paint_road_asphalt`. The other generators can opt in by passing their
level directory.

**Bake:** none.

### L5. Hand-templated level `.tscn` text (not recommended)

`_scene_text` appears in `gen_car_arena.gd:1242`, `gen_islands.gd:92`, `gen_rail_level.gd:367`,
`gen_rough_ground.gd:140` and `gen_skyport.gd:1152`. All five template the same
`level.gd` / terrain / sea boilerplate.

The scene is a bake input, so any byte change re-stales that level. `gen_islands` cannot even be
replayed to verify (levels 2, 3 and 4 are `"replayable": false`). The payoff is low; leave it.

---

## Thumbnails and the kit

### T1. Thumbnail generators

- `_thin_fog` and `FOG_HAZE` are identical at `gen_challenge_thumbs.gd:89` / `:13` and
  `gen_level_thumbs.gd:95` / `:15`.
- The save tail is repeated in three files (`gen_challenge_thumbs.gd:74-82`,
  `gen_level_thumbs.gd:80-89`, `gen_vehicle_thumbs.gd:77-84`): `save_capture`, then
  `CardImport.ensure_import_settings`, then the print.
- `shot_stage.gd`'s header lists its users but leaves out `gen_challenge_thumbs.gd`.

**Shared:** `ShotStage.thin_fog(level, dist)` and `ShotStage.save_card(vp, out, tag) -> bool`.

**Call sites:** the three generators.

**Bake:** none.

### T2. Kit recipe loading

- The recipe directory listing is identical at `gen_kit_assets.gd:21-34` and `gen_thumbs.gd:19-37`.
- The `_run_recipe` head is duplicated at `gen_kit_assets.gd:37-88` and `gen_thumbs.gd:66-90`:
  parse, kit name, source, GLB names, `classify`, `fam_by_name`.
- `gen_thumbs` skips `validate_families` and the coverage gate, so a broken recipe renders
  thumbs anyway.

**Shared:** `KitRecipe.recipe_paths(dir, only)` and `KitRecipe.load_recipe(path) -> Dictionary`
in `kit/helpers/kit_recipe.gd`, with the validation inside.

**Bake:** none. The file is under `res://kit/`, but no level scene depends on it; only
`addons/carlito_kit`, `tests/test_kit_gen.gd` and these two tools load it.

---

## .mjs and .ps1 helpers

### H1. Godot resolution, and runs that bypass the wrapper — **PARTLY DONE** (50d482f: one Node resolver, `resolveGodot` in `godot_lock.mjs`; the .ps1 copy, pre-commit and the bypassing runs are open)

The binary is resolved four times:
- `godot_bin.ps1` `Resolve-GodotBin`
- `godot_run.mjs:55` `resolveGodot`, the only one with the Windows `_console` check
- `git-hooks/pre-commit:10` `resolve_godot`
- `claude_hooks/session_check.mjs:19`

Four Godot runs skip `godot_run.mjs` (its lock, timeout and parse-kill):
- `pre-commit:77`
- `stop_freshness_hook.ps1:67`
- `rebuild_level.ps1:92` and `:131`

pre-commit and the Stop hook check the lock first and then run Godot without taking it, so a run
can start in between.

**Shared:**
- Every run goes through `node tools/godot_run.mjs -- …`; `rebuild_level` passes `--timeout=`
  for long steps.
- `resolveGodot` moves to `godot_lock.mjs` (already the shared module) for `session_check.mjs`
  to import.

After that, `godot_bin.ps1` has no callers and goes.

**Behaviour to keep:**
- `godot_run.mjs` refuses when the lock is held. Each caller keeps its own reaction to that
  refusal: pre-commit fails the commit (as now), and the Stop hook allows the stop (as now,
  `stop_freshness_hook.ps1:64`). So the hook matches the `[godot_run] refused` line rather than
  treating every nonzero exit as stale.
- It passes through the child's exit code, which `rebuild_level`'s `-ByExitCode` steps rely on.

### H2. Gate patterns repeated across CI, the hook and preflight

**Editor-type annotation regex:** `ci.yml:43`, `pre-commit:34` and `preflight.ps1:23`.

**Fix:** fold it into `check_gd_text.mjs`. That script already runs at `ci.yml:63`, in
pre-commit gate 1b on the same staged set, and in preflight. Three copies become one.

**Check-bakes verdict** (the regex plus the completion sentinel): `ci.yml:83-87`,
`pre-commit:79-86`, `preflight.ps1:42-44` and `stop_freshness_hook.ps1:69-76`.

**Leak-noise filter:** `ci.yml:136`, `:157` and `:200`, `preflight.ps1:51` and
`rebuild_level.ps1:95`.

**Fix:** a new `tools/godot_verdict.mjs --bakes|--errors` that reads a log on stdin and exits
0 or 1.

### H3. The contract-sync block, three times — **PARTLY DONE** (c4aa587, a391990: `gen_js_contract.mjs --check` exists; the three callers, pre-commit, `preflight.ps1` and the Stop hook, are not switched to it)

`preflight.ps1:71-83`, `stop_freshness_hook.ps1:40-49` and `pre-commit:45-56` each run
`gen_js_contract.mjs` and compare hashes.

They already disagree when the sibling `sloppycan` checkout is missing:
- preflight and the Stop hook skip the check.
- pre-commit runs under `set -e`, so the generator's exit 1 aborts the commit.

**Shared:** `node tools/gen_js_contract.mjs --check`, which exits 1 when it changed the copy and
has one decided rule for a missing sibling.

---

## Dead code and arguments

- `measure_vehicles.gd:569` `_sn_a`: written at `:3330` and `:3386`, never read. `A` goes into
  `_current["sine"]["a"]`.
- `measure_vehicles.gd:946` `j=` (engine inertia): not in any run line in
  `docs/vehicle_measurements.md`. Its `_current["engine_inertia"]` (`:1274`) is never read.
  Document it in the run-line block or delete it.
- Sweep keys written but read by no table and not by `_report_lines`:
  - `_current["speed_now_kmh"]` (`:2824`)
  - `_current["stall"]` (`:3072`)
  - `_current["handbrake_pulled"]` / `["handbrake_steer"]` (`:3160`)

  These passes print to stdout only. Either delete the writes or let `_report_lines` print them.
- `tools/rough_ground_layout.gd:96` `lane_index`: no caller. `patch_index` (`:103`) has only a
  test caller. `measure_rough.gd:217-222` filters lanes and patches by name inline. Use the two
  functions there, or delete `lane_index`.
- `tools/check_orphans.mjs` finds orphan functions under `src/` and `kit/` only, so `lane_index`
  is invisible to it. Widening `DEFINITION_DIRS` to `tools/` would flag `lane_index` (delete it)
  and `patch_index` (test-only: an `orphans_allow.txt` entry, or the `measure_rough` call above).
- `measure_grade.gd:78` preloads `measure_vehicles.gd` for one private function (M5) and
  `measure_semi_launch.gd:28` for two symbols (M4). Both go once M4 and M5 land.

## Kept on purpose (not findings)

- The per-pass `_drive*` wrappers (`measure_vehicles.gd:1364`, `:4335`, `:4498`, `:4651`,
  `:5105`; `measure_grade.gd:442`, `:1561`; `measure_rough.gd:355`): a line or two each,
  carrying pass state into `MeasureRig.drive`'s `extra`.
- `KNOWN_TRACKING_FAILS` (`measure_vehicles.gd:47`): empty today by design. The ratchet and its
  "stale allowance" note are the mechanism, and CI documents it (`ci.yml:227`).
- `measure_semi_launch._ramp_step` (M3): a different control law.
- `gen_islands.gd`: not replayable. Leave it until its levels are.

## Suggested order

1. M1, M2, M3, M4, M5, M6 and M7 in `measure_rig.gd` (M6's `spec_of` in `VehicleCatalog`).
   These are pure tools/src refactors with no bake risk. Check by re-running each `doc=` preset:
   the regions should stay the same.
2. K1 and K2. Check with a regen; `test_kenney_variants` and `test_boat_variants` stay green and
   the shipped bodies show no git diff.
3. H1, H2 and H3 (helpers, no Godot output).
4. L1, L2 and L4, each checked by a replay diff and `check_bakes`.
5. L3 in tools only. RoadPath waits for a rebake.
6. M8, M9 and M10, then the dead-code list.
7. M11 on its own commit, since it moves measured figures. Regenerate the `doc=` regions it
   touches in the same commit.
