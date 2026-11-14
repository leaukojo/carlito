# 2026-11-14: "ground under a deck", step 2: the gap made exact, then the trigger

Item: the Queue's top Opus line. Plan approved by the user in plan mode (it stands for the
proposal: the fix changes a contact). User's choice, asked: model the rounded rim in
`cylinder_support`, not a sharp (margin 0) cylinder. Ended at the plan's step 3 stop rule:
the trigger (step 4) is not built.

## Source (opened this session, `godotengine/godot` at `4.7.1-stable`, raw files)

- `modules/jolt_physics/shapes/jolt_cylinder_shape_3d.cpp` `_build()`:
  `const float actual_margin = MIN(margin, min_half_extent * JoltProjectSettings::collision_margin_fraction);`
  with `min_half_extent = MIN(half_height, radius)`, passed as `CylinderShapeSettings(half_height, radius, actual_margin)`.
- `modules/jolt_physics/jolt_project_settings.cpp`: `collision_margin_fraction`, default `0.08f`
  (`project.godot` does not set it).
- `thirdparty/jolt_physics/Jolt/Physics/Collision/Shape/CylinderShape.cpp` `GetSupportFunction`:
  `case ESupportMode::ExcludeConvexRadius: return new (&inBuffer) Cylinder(scaled_half_height - scaled_convex_radius, scaled_radius - scaled_convex_radius, scaled_convex_radius);`
  so the collided shape is a cylinder shrunk by `cr` and rounded by a sphere of `cr`: support
  `cr + (r - cr) sqrt(1 - a^2) + (w - cr) a`, `a = |n . axle|`.

## Findings

1. **The fixture fails at HEAD at both gaps** (step 1). `_wheel_on_a_rolled_body` (wall at x 0.07,
   one body, two-shape and welded) plus a box `Vector3(4, 0.5, 20)` at `y = -under - 0.25`, the
   anchor at `0.66 - c` (r 0.36, travel 0.3, so `c` into the travel on the deck):
   `c 0.06, under 0.05` reads `0.010840`; `c 0.24, under 0.18` reads `0.191016`, both bodies alike.
   Ground `under` m below the deck is in reach only when the wheel is compressed more than `under`
   on it: level_3's 0.18 m cells need a wheel 0.18 into its travel. The test (assert compression
   `c` to 2e-3, normal UP, for both welded flags and both cases) is not committed; its body:

   ```gdscript
   for welded: bool in [false, true]:
       for c: Array in [[0.06, 0.05], [0.24, 0.18]]:
           var w: WheelScript = await _wheel_on_a_rolled_body(0.0, Vector3(0.0, 0.66 - c[0], 0.0),
                   0.07, true, welded, c[1])   # helper's 6th arg `under`: the box above, a body of its own
   ```

2. **The engine detects contact on the rounded rim and reports its points on the sharp one**
   (a probe, the wheel's own query cylinder on a flat box, cr 0.008 for r 0.36, half 0.1):
   at margin 0, rolled 10 the rest test is empty 0.5 mm inside the sharp support and touches at
   2 mm; rolled 30 / 45 / 60 empty at 2 mm, touching at 4 mm (the rounded over-read is 1.27, 2.9,
   3.3, 2.9 mm). Upright and on the end face it touches at 0.5 mm. Where it touches, the pairs'
   length reads the sharp depth (`0.002000` at 2 mm in, `0.004000` at 4 mm): Jolt's manifold lies on
   the supporting faces (sharp). So a depth test off the pairs cannot see the rounding (it passed
   at HEAD), and `first_carried`'s pairs keep the sharp support (cr 0, unchanged).
3. **The fix** (6964c1e): `cylinder_support(..., convex_radius := 0.0)` the rounded support,
   `jolt_convex_radius(cylinder)` Godot's `_build()` line, `_convex_radius` set once in
   `apply_suspension`, used by `_contact_pass`'s gap. Guard
   `test_the_cylinder_support_is_where_the_engine_touches_across_the_axle` (rest test touches 0.2 mm
   inside, empty 0.2 mm outside, rolls 0 to 90): with cr 0 it fails at rolls 10, 30, 45, 60
   (`-0.0002 off`), passes with the wheel's. `test_a_wheel_on_a_leaning_body_still_carries_on_its_tread`
   tightened from 0.01 to 1e-4 against the rounded support (its 0.01 absorbed the 4.7 mm the sharp
   formula was off by at 45 degrees). Full suite 2506 cases, 0 failures.
4. **The deep-gap trigger's count on `sedan,semi 45 kerb`: 889 -> 24** (306 + 583 at af471cd's
   probe; this session's probe after the fix). What is left:
   - 22 ticks on the 20 cm kerb, `gap -0.16 to -0.20`, `n.up 0.80 to 1.0`, `n.axle 0`: the tyre is
     inside the kerb at full bump (the sweep left the kerb out, started inside it, and stopped on the
     strip; the rest test names the kerb's top). Real, the deck case's class: these are the 8 ticks
     that went to full bump under af471cd's trigger.
   - 2 ticks (3 in a second run) at a square edge, `gap -0.00208 step 0.00109 n.up 0.870`,
     `-0.00269 step 0.00125 n.up 0.852`, `n.axle 0`, on the kerb box. **Unexplained.** Hypothesis
     traced: the kerb box's own convex radius (`BoxShape3D` margin, 4.8 / 8 mm for the 12 / 20 cm
     kerbs) rounding its edge while the point lies on the sharp one. Refuted: with the kerb's shape
     margin set to 0 in `MeasureRig.add_box` (probe, undone) the class stays
     (`-0.00211 n.up 0.806`, `-0.00391 n.up 0.980`, `-0.00227 n.up 0.828`).
5. **The sweep's last free stop is not free to the rest test** (a probe, undone, for an alternative
   trigger: "a rest test at `safe_drop` finds something the sweep skipped"). On the same kerb run,
   126 ticks have a rest contact at `safe_drop`, most on the flat `Strip` (`safe 0.1313 f0 0.4688
   n.up 0.996`), some on the kerb. So Godot's `cast_motion` bisection and `get_rest_info` disagree on
   touching by more than a sweep step on plain flat ground. Not traced: what `_cast_motion_impl`'s
   `collides()` asks of Jolt (its tolerance, `CollideShapeSettings`) against what `get_rest_info`
   asks. This also bears on finding 4's unexplained class (a safe stop already in contact makes
   `safe - step` the wrong bound).

## Stop (the plan's step 3 rule)

Symptoms: finding 4's square-edge class and finding 5. Hypotheses: (a) the box's convex radius,
refuted; (b) `cast_motion`'s touching test differs from `get_rest_info`'s (finding 5), untested
against the source; (c) float32 far from a large collider's centre: `docs/vehicles.md` § Contact
already says the sweep and the rest test disagree on a stop by micrometres there (`measure_vehicles`'
strip is one 6 km box), the inverse of finding 5; test by the same probe with the strip split, or
the kerb laid near the strip's centre. Tried: the two probes above. Not built: the trigger, its fixture test, the
`docs/vehicles.md` sync for the trigger. `docs/vehicles.md` names neither the convex radius nor
`cylinder_support`'s exactness, so 6964c1e needs no doc change.

## Measured (6964c1e against 7ff0210's wheel, `--fixed-fps 60`)

Run after the commit, not before it as the plan had it (the plan's runs were for the whole change).

- CI gates, after: `all 45 track strict` every PASS (drift 0.000 / 0.031 / 0.015 m as before);
  `measure_semi_launch` both units PASS, steer-wheel floor `semi` P2 13801 N (before within 4 N),
  `steady` rest reading PASS (axle-load step 0.80 kg a tick, before 0.81); `measure_air_loss -- all
  strict` 9 of 9 PASS, byte-equal but the timing line.
- `sedan,semi 45 side`: equal to the byte.
- `kerb`: the 30 km/h 20 cm kerb's peaks 17.7 -> 17.9 kN front, 9.3 -> 9.5 kN rear (2 %), largest
  tick 91 -> 93 mm, lean 23 -> 22 deg; the crawls within 0.1 kN and 2 deg of lean. These contacts
  lean across the axle (the 30 degree oblique pass), where the rounded rim touches up to 3.3 mm
  later: the direction the fix moves them.
- `scrape`, two bodies and `steer=60`: contact 100 % and 0 ticks off the travel on every wheel as
  before; forces across within 30 N (`tractor-kenney` FL steered 1158 -> 1188 N), sweeps by contact
  400 -> 391.
- `scrape onebody`: `firetruck` FR, its rim at the wall's face (`+0 mm past`), peak across
  218 -> 501 N, FL 209 -> 266 N, sweeps by contact 3 -> 26, end speed 4.98 -> 5.11 m/s; every
  other body within 5 N. Not traced: a wheel grazing a wall of its deck's body flips between the
  rest test naming the deck and the wall at the millimetre the fix moves, so its sweep count and
  peak are a threshold's; it is a peak of a few hundred newtons on 100 % contact. Re-read it with
  the diagnosis item (the Queue).

## Commits

- 6964c1e wheel: the contact's support on Jolt's rounded rim (and its tests).
- 36601e3 test: the deck fixture's unused helper argument dropped.
