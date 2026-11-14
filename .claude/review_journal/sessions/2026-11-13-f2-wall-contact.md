# 2026-11-13: F2, a wheel reads a wall in its side as its contact

Item: the Queue's top line (F2). Plan approved by the user in plan mode (it stands for the
proposal: the fix changes a contact).

## What the engine does (Godot 4.7.1 source, opened this session)

`modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp`:

- `cast_motion` passes `p_ignore_overlaps = true`, and `_cast_motion_impl` skips a whole body
  the shape touches at the start: `if (p_ignore_overlaps && collides(*other_jolt_body, 0.0f)) {
  continue; }`.
- `rest_info` takes one hit over every body (`JoltQueryCollectorClosest`), its normal
  `-hit.mPenetrationAxis.Normalized()`. That "closest" is the deepest is from memory of Jolt
  (`GetEarlyOutFraction` = `-mPenetrationDepth`), proven by test A below.
- `exclude` is per body RID (`JoltQueryFilter3D::ShouldCollideLocked`:
  `!excluded.has(object->get_rid())`).

So the sweep ignores a wall the wheel's side starts in, and the rest test where the sweep stops
names that wall. Three cases:

- A. Wall and ground two bodies, tread on the ground: the ground's drop, the wall's normal.
- B. Wheel in the air beside the wall: no sweep hit, the start's rest test finds the wall, read
  as full bump along the wall's normal.
- C. Wall and ground one body: the sweep drops the ground with the wall, then B's path.

## Findings

1. **The three cases, proven on HEAD's `wheel.gd` (3d216c4)** with the new tests in
   `tests/test_wheel_spin.gd` (one wheel, r 0.36, 0.3 m of travel, its right face 3 cm into a
   wall, `max_suspension_force` 30 kN):
   - A (`test_a_wall_in_the_wheels_side_leaves_the_tread_on_the_ground`): fails, the normal reads
     `(-1.0, -0.0, 0.0)` where the flat's is `(0, 1, 0)`; the compression is the flat's (0.06).
   - B (`test_a_wall_in_the_side_of_a_wheel_off_the_ground_is_no_bump`), read with a print:
     `contact true compression 0.300 force 30000 normal (-1.0, -0.0, -0.0)`: full bump, the
     whole 30 kN along the wall's normal, with nothing under the tyre.
   - C (`test_a_wall_of_the_grounds_own_body_never_gives_the_wheel_its_normal`), the wall a
     second shape of the flat's body, the tread on the flat and off it: both read
     `contact true compression 0.300 force 30000 normal (-1.0, -0.0, -0.0)`. The sweep drops the
     flat with the wall, so even the grounded wheel reads B.

2. **It shows on shipped bodies** (`measure_vehicles -- <bodies> 45 scrape [steer=60] [onebody]`,
   the new scenario; HEAD's wheel). Wheel straight, wall its own body: `race` FR 32 ticks with
   the wall's normal, 4.3 kN sideways; `tractor-kenney` RR 90 ticks at its 110 kN cap;
   `firetruck` FR 1 tick at 120 kN; `sedan` and `suv-luxury` none (their hull keeps the wheels
   60 mm off the wall). Steered 60 % into the wall: `sedan` 173 cast start overlaps and 9.3 kN,
   `suv-luxury` 177 and 10.6 kN, `semi` FR 146 ticks at 57 kN, `firetruck` 152 at 49 kN, `race`
   4.16 g across.
3. **The plan's test (`off_tread`, a contact in the wheel's side) was not enough**: it cleared
   the straight-wheel runs, but a wheel steered past about 20 degrees meets the wall on its
   tread's corner (`sedan` still 163 start overlaps and 9.1 kN, `suv-luxury` 128 and 10.9 kN).
   A fourth case showed there: a rolled body's travel sweeps the wheel INTO the wall, so the
   wall stops the sweep itself. The user chose the wider test (asked mid-session): a contact
   more than `LYING_DEG` off the wheel's travel is not the spring's (`RayWheel.carries`).
   `off_tread` implies it (`|n.axle| > sin 70` gives `|n.up| < cos 70`), so one dot product
   replaces `off_tread`, `lying_on` and `_lies_on`.
4. **After** (same runs): wheel straight, `race` 37 N, `tractor-kenney` 566 N, `firetruck`
   218 N sideways, no tick off the travel. Steered 60 %: `sedan` 198 N and no start overlap,
   `suv-luxury` 148 N, `race` 0.89 g, `semi` 440 N, `firetruck` 230 N. `side` and `kerb` on
   `sedan` and `semi` print the same to the byte (kerb's steepest contact leans 62 degrees).
   Changed on purpose: the steered `sedan` and `suv-luxury` now grind to a stop nose-in against
   the wall (0.00 and 1.78 m/s at the end, 4.95 before, when the false bumps bounced them along).
5. **Case C is not cured** (`onebody`, after): the wheel reads nothing while its side is in the
   wall, so the corner drops: `race` FR in contact 25 % of ticks, 10.4 degrees of tilt, ends at
   2.49 m/s; `tractor-kenney` RR 64 %; steered, `sedan` / `suv-luxury` / `semi` / `firetruck`
   FR about 61 %. Before it was a shove (`race` 20.5 kN, `tractor-kenney` 110 kN). Labelled
   `COMPROMISE` on `_contact_query` (an engine limit: `cast_motion` skips the body whole) and
   queued.

## Commits

- 22f042d wheel: `carries`, `_contact_pass`, the retry; tests A, B, C; `docs/vehicles.md` § Contact.
- 4857139 measure: `scrape` (`steer=`, `onebody`); its run line.

Full suite at the fix: 2500 cases, 0 failures (the two comment trims the doc guard asked for
came after it).

## Deferred

- Case C (Queue): our own sweep for a body the wheel starts inside.
- `settled_drop`'s `maxf(normal_up, 0.1)` can no longer bind (Queue).
- Not run: `scrape` with a trailer coupled, and the three CI measure gates (the tread path
  takes the same queries as before; `side` and `kerb` confirm it on two bodies).
