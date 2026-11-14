# 2026-11-14: why the sweep's safe stop and the rest test disagree (diagnose only)

Item: the Queue's top Fable line. Nothing fixed; two temporary probes in `wheel.gd` and
`measure_vehicles.gd` reverted (`git status` clean before this commit).

## Source (opened this session, `godotengine/godot` at `4.7.1-stable`, raw files)

- `modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp`:
  `cast_motion` and `rest_info` build the same `JPH::CollideShapeSettings` (only
  `mMaxSeparationDistance = margin`) and both pass `use_enhanced_internal_edge_removal_for_queries`.
  `_cast_motion_impl`'s `collides(body, fraction)` collides a `JoltCustomMotionShape` with
  `motion_local * p_fraction`; per body: `if (!collides(*other_jolt_body, 1.0f)) continue;`,
  `if (p_ignore_overlaps && collides(*other_jolt_body, 0.0f)) continue;`, then the bisection.
- `modules/jolt_physics/shapes/jolt_custom_motion_shape.cpp`: the hull's support is the inner
  shape's, `if (p_direction.Dot(motion) > 0) support += motion;`, and
  `GetConvexRadius() ... return inner_support->GetConvexRadius();`. So the sweep collides the same
  rounded cylinder as the rest test, and **at fraction 0 the hull is the shape itself: the skip
  test is the rest test at the start pose, same code, same inputs.**
- `thirdparty/jolt_physics/Jolt/Physics/Collision/Shape/ConvexShape.cpp` `sCollideConvexVsConvex`:
  a GJK step on the shapes without their convex radius
  (`GetPenetrationDepthStepGJK(*shape1_excl_cvx_radius, ...GetConvexRadius() + max_separation_distance, ...)`);
  on `EStatus::Indeterminate` it runs EPA on `ESupportMode::IncludeConvexRadius`, the sharp shapes.
- `thirdparty/jolt_physics/Jolt/Geometry/GJKClosestPoint.h` `GetClosestPoints`:
  `// If v is very small compared to the length of y, we also consider this a collision`
  `if (v_len_sq <= FLT_EPSILON * GetMaxYLengthSq())` then `v_len_sq = 0.0f; break;` (which
  `EPAPenetrationDepth.h` returns as `Indeterminate`). `y` are the simplex's Minkowski points:
  a far corner of a box in the wheel's frame.
- `modules/jolt_physics/shapes/jolt_box_shape_3d.cpp`:
  `actual_margin = MIN(margin, min_half_extent * JoltProjectSettings::collision_margin_fraction)`.

## Cause

1. **Jolt picks rounded or sharp shapes per call, by the distance to the box's far corner.**
   Two shapes touch when their cores are `cr_wheel + cr_box` apart. Once the simplex holds a
   corner further than `(cr_wheel + cr_box) / sqrt(FLT_EPSILON)` = 2900 x that sum from the wheel,
   GJK calls that distance "machine precision", and the answer comes from EPA on the sharp
   cylinder and the sharp box. For the 0.36 x 0.2 tyre (cr 8 mm): 139 m on a box 1 m thick or more
   (cr 40 mm), 46 m on a 20 cm kerb (cr 8 mm), 37 m on a 12 cm kerb (cr 4.8 mm). Which corners the
   simplex holds varies call to call near those distances, so the sweep's bisection steps and the
   rest test each take either route: they disagree by the sharp shape's reach over the rounded
   one. That is up to `0.414 cr_wheel` (3.3 mm) for a rim on a face under a leaned wheel, and a
   few mm of drop for a tread on a box's edge (the rounded edge is recessed `0.414 cr_box`).
2. **Float32 of the rest pose far from the world's origin**, smaller: the rest test's pose is
   `ray_from - up * drop` rounded in the world (0.24 mm steps at 2800 m), the sweep moves the hull
   in the query's frame. Under 0.15 mm, only with a tilted `up` or an edge normal.

## Evidence (standalone `extends SceneTree` probes, boxes and the wheel's query cylinder only)

- **The switch, probe 3**: the cylinder rolled 4 degrees over the middle of a square slab 2 m
  thick; the rest test's touching drop (bisected to 1e-6) against the rounded rim's
  (`cylinder_support` with cr 0.008), 200 start heights per slab. "The sharp rim reaches 0.000539
  further than the rounded."

  | Slab side (far corner) | Rest test touches, from the rounded rim's drop | Early / late of 200 |
  |---|---|---|
  | 5 to 60 m (3.5 to 42 m) | 0 to +0.000006 | 0 / 0 |
  | 100 m (70.7 m) | to +0.000083 | 0 / 1 |
  | 150 m (106.1 m) | to +0.000276 | 0 / 2 |
  | 185 m (130.8 m) | to +0.000856 | 0 / 5 |
  | 195 m (137.9 m) | to +0.006382 | 0 / 4 |
  | 200 m (141.4 m) | -0.000540 to +0.002075 | 199 / 1 |
  | 210 m to 4000 m | -0.000540 to -0.000514 | 200 / 0 |

  Predicted 139 m; measured between 137.9 and 141.4 m. Past it the engine collides the sharp rim
  (0.54 mm early at 4 degrees); just under it the rest test misses a contact by up to 6 mm in a
  few samples of 200 (not traced further: EPA on a near-touching pair).
- **A flat, probe 1** (1500 random poses per case, the sweep as `_contact_pass` runs it): on the
  tool's 40 x 2 x 6000 strip, upright, the rest test is exact (1e-6) and nothing is flagged, at
  z 2800 and at z 50 alike. Tilted (roll to 4, pitch to 5 degrees): rest touches -0.553 to
  +0.034 mm from the rounded drop at both z, 12 and 3 of 1500 with a rest contact at `safe_drop`
  (their gaps +0.07 to +0.5 mm by the rounded support: touching by the sharp rim), 4 and 5 with
  none at `unsafe_drop`. On a 40 x 2 x 12 slab, tilted, at z 2800 and at z 0: exact, 0 flagged.
  So the strip's size, not its place.
- **A kerb's edge, probe 2** (upright, square on, so the wheel's own rounding plays no part; each
  query's threshold classed against the sharp edge's drop and the rounded edge's):
  kerb 13 m wide, 20 cm: 1423 of 1423 rounded by both, 0 deep. 80 m wide at its middle (corners
  40 to 42 m, under the 46 m): 1391 of 1409 rounded by both, 2 deep. 80 m wide, 30 m off its
  middle (corner 70 m): sharp or mixed, 433 of 1415 deep (to -3.2 mm), 235 with a rest contact at
  `safe_drop`, 75 with none at `unsafe_drop`. 80 m wide, 12 cm, at its middle (over the 37 m):
  1030 of 1723 deep (to -3.1 mm). Kerb 13 m, 12 cm: 0 deep.
  A kerb with shape margin 0 (the last session's refutation) is sharp by both and 0 deep in 2000,
  but 1 of 2000 on the 80 m one reads `n.up -0.998`, gap -0.67: with no convex radius every
  touching query is an EPA one. Margin 0 is no fix, and that run refuted nothing.
- **The tool's own run** (`measure_vehicles -- sedan 45 kerb`, a tally printed from `_contact_pass`,
  22000 passes): per rest collider `[passes, normal off the face, rest empty at unsafe, rest at
  safe, deep, start inside]`, deep meaning `gap < -step * n.up - 1e-4` with nothing at the start:
  `Strip [9088, 855, 0, 21, 0, 0]`, `Kerb 0.12 [6396, 355, 0, 8, 3, 0]`,
  `Kerb 0.20 [6480, 1004, 0, 10, 1, 22]`, no rest contact at unsafe 36.
  The four deep ticks: -1.05 to -1.68 mm on the kerb, far corner 42.3 to 47.6 m.
  **With `KERB_WIDTH` 20 (undone)**: `Strip [9089, 863, 0, 18, 0, 0]`, `Kerb 0.12 [6391, 349, 0,
  3, 0, 0]`, `Kerb 0.20 [6486, 1003, 0, 7, 0, 26]`, none 34. The kerb's deep ticks go (4 -> 0); its
  rest contacts at safe fall 18 -> 10 (the rest is cause 2: probe 1's kerb on small bodies, tilted,
  flags 21 to 26 of 1500 at z 2700, deepest -0.14 mm, and 0 at z -50); the strip's stay.
  Not reconciled: probe 2's rate on the 80 m, 12 cm kerb (60 % of edge poses) against the run's 3
  of 355; the probe is exactly axis-aligned, the run is not.

## The two readings the last session stopped on

- "126 kerb-run ticks whose `safe_drop` pose already has a rest contact, mostly on the flat
  strip": cause 1 on the 6 km strip under a tilted body (always past 139 m), and cause 2. Under
  0.6 mm, no contact missed.
- "2 to 3 square-edge ticks 2 to 4 mm deep with no axle part": cause 1 on the 80 m kerb, whose
  corners sit at the 37 / 46 m switch. A property of the tool's kerb, gone at 20 m.

## Which trigger

Neither candidate. A deep gap reads 1 to 3 mm on sound contacts (cause 1), so it needs a
tolerance; a rest test at `safe_drop` fires on sound contacts (39 of 22000 here).
**The exact one is the rest test at the start pose (drop 0), after a sweep that hit**: it is the
engine's own skip test (`collides(body, 0.0f)`, zero motion, so the hull is the shape), so it is
true exactly when the sweep left a body out. In the run it is true on 22 ticks, the 22 where the
tyre is inside the 20 cm kerb at full bump (the last session's real class), and on none of the
others.

## Also found (no action taken)

- `cylinder_support`'s rounded rim (6964c1e) holds where the engine takes the rounded route. On a
  body past the switch (Flatland's `InfiniteGround`, a 4000 x 20 x 4000 box; the measure strip) a
  leaned wheel is collided on its sharp rim, and the gap reads up to `0.414 cr` high (0.54 mm at
  4 degrees, 2.4 mm at 22). Level geometry (heightmaps, welded meshes: triangles a few metres
  across) is under the switch.
- `docs/vehicles.md` (about line 100, "float32 precision; `measure_vehicles`' strip is one 6 km")
  gives float32 as why the sweep and the rest test disagree on the strip: the cause is the GJK
  exit above, by the box's size, and it is the same at z 50.
- `scrape onebody`'s `firetruck` threshold (the last session's note) not re-read. Expected, not
  run: with the start test a wheel whose side is in a wall at full bump always sweeps by contact,
  so it no longer flips with which contact the rest test names.

## Probe 3, to rebuild (a `--headless --path . --script` SceneTree script)

Boxes `Vector3(side, 2, side)` centred 1 m under y 0, 1500 m apart; a `CylinderShape3D` radius
0.36, height 0.2 in a `PhysicsShapeQueryParameters3D`, `transform = Transform3D(wb * Basis(BACK,
PI / 2), from)` with `wb = Basis(BACK, deg_to_rad(4))`; from the fourth `_physics_process` on,
per start height bisect the least `d` with `get_rest_info` non-empty at `from - wb.y * d`, and
print it less `(from.y - support) / wb.y.y`, `support` the rounded `cylinder_support` along UP.
