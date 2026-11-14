# 2026-11-14: F2's remainder, a wall that is a shape of the ground's own body

Item: the Queue's top line. Plan approved by the user in plan mode (it stands for the proposal:
the fix changes a contact).

## What the engine does (Godot 4.7.1 source, opened this session)

`modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp`:

- `_cast_motion_impl`: `if (p_ignore_overlaps && collides(*other_jolt_body, 0.0f)) { continue; }`,
  then per body a bisection, `step_count = CLAMP(int(std::log(1000.0f * motion_length) /
  (float)Math::LN2), 4, 16)`.
- `collide_shape` writes, per hit, manifold point pairs:
  `r_results[point_count++] = base_offset + to_godot(contact_points1[j]) + margin_offset;`
  `r_results[point_count++] = base_offset + to_godot(contact_points2[j]);` with
  `margin_offset = penetration_axis * (float)p_parameters.margin`. Derived from that, to prove by
  test: at a query margin `m` a pair's difference lies along the penetration axis, `depth + m`
  long, so every contact's normal and signed depth can be read, not only the deepest one's.

## Survey: which shipped levels have it

Static (plan mode):

- `LevelBaker._collect_gridmap` welds every GridMap cell into the level-wide `Drivable` body.
- `level_3` has `RoadsBarrierTiles`, 30 cells of `roads_barrier.meshlib` over its road tiles.
  `kit/raw/roads/road-straight-barrier.glb`'s position accessor: `"max":[0.5,0.08,0.5]`, x 12 =
  0.96 m. The tile is rails only. So the barrier and its deck are one body: case C, shipped.

Headless (a throwaway tool scene, deleted after the run: each registered level's `.baked.scn`
`Drivable` faces binned by metre, a steep face's top against the lowest carried face in the 3 x 3
bins around it; each heightmap's triangles by slope):

| Level | `Drivable`: bins with a steep face rising > 0.5 m | Heightmap faces over 70 degrees |
|---|---|---|
| level_1 | 0 (kerbs, worst 0.24 m) | 16570 |
| level_2 | 0 | 51845 |
| level_3 | 763: 269 at about 1.0 to 1.25 m (the barriers), the rest stacked decks | 4847 |
| level_4 | 586 at about 3 m: the bridge ribbon's own 3 m skirt (`base_depth`), no wall | 481 |
| level_5 | 0 | 16626 |
| level_6 | 105: the bridge skirt again, and the slipway's sides (0.5 to 2.25 m) | 36873 |
| car_arena | 0 | 22736 |
| rough_ground | no bake | 0 (steepest 35.7) |

So: level_3's barriers are the one welded wall, and every island level's heightmap has cliff faces
past `LYING_DEG`, each a wall of the ground's own body for a wheel driven along its foot. The tool
does not say which cliffs have drivable ground at their foot; the count says the case is not rare.

The tool's winding was Godot's reversed, so its "carried" faces were the tiles' undersides: a
rise is a steep face's top over the tile's base (kerb top 0.24 m, barrier top about 1 m), which
sorts kerbs from barriers as well.

## Findings

1. **The pairs carry each contact's normal and depth** (a throwaway probe: the test cylinder
   against a flat with a wall as a second shape, and a 30 degree slope, at the origin and at
   (300, 20, -250)). At margin 0.05, tread 2 mm into the flat and side 3 cm into the wall: 4 pairs
   `len 0.079987 depth 0.029987 n (-1, 0, 0)` and 2 pairs `len 0.052000 depth 0.002000 n (0, 1, 0)`;
   the rest test at the same pose names the wall only. Tread 2 cm clear: the flat's pair is still
   there, `depth -0.019999`. On the slope at (300, ...): `n (-0.499969, 0.866043, 0)` at margin
   0.05, `(-0.500698, 0.865622, 0)` at margin 0 (3.8 mm of lever), the rest test's `(-0.5, 0.866025, 0)`.
2. **Case C on HEAD, as asserts** (`test_a_wall_of_the_grounds_own_body_leaves_the_tread_on_the_ground`):
   compression `0.000000` where the flat's is 0.06, the wall a second box shape and the wall
   welded to its deck in one trimesh alike.
3. **The silent form is real** (`test_ground_under_a_deck_the_sweep_left_out_is_not_the_wheels`,
   a second flat 5 cm under the deck): `contact true compression 0.0108 normal (0, 1, 0)`, the
   collider the deck's. The sweep left the deck out with its wall and stopped on the flat under
   it; the rest test there names the deck (5 cm deep, the wall 3), a contact the spring carries,
   so nothing asks again and `settled_drop`'s clamp to `safe_drop` takes the 5 cm away without a
   word. The wheel rides 5 cm low with the deck's normal.
4. **The fix** (`RayWheel._carried_sweep`, in place of the exclude-and-ask-again loop): where the
   rest test names a contact the spring cannot carry, the wheel sweeps again by contact: probes from
   full bump down, each reading every contact within `PAIR_MARGIN` off `collide_shape`'s pairs
   (`first_carried`) and moving to where the first carried one touches, at most a margin a probe.
   What went: `_off_body`'s RID, `left_out`, the `while`, the `exclude` swaps, the `COMPROMISE`.
   Not a bisection, as the plan had it: a carried contact's axis is only reliable shallow (a box
   20 cm into the tyre can give its side for the shortest way out), so the sweep never reads a
   deep one; it sees a contact coming through the margin instead.
5. **An inactive edge's pair lies** (found by the welded test, first try): compression `0.300000`,
   normal `(-0.796049, 0.602228, 0.060237)`. Probed: hub at (0, 0.6, 0), the wall two triangles;
   the pair `p1 (0.120001, 0.958213, 0.035822) p2 (0.070001, 0.99604, 0.039605)`. `p2` is on the
   wall's diagonal, 3.8 cm straight over the tread's top; `p1` is the tread's top moved 5 cm along
   +x, the wall's normal: the engine gives a trimesh's inactive edge its triangle's normal for an
   axis (from memory of Jolt's `ActiveEdges::FixNormal`, not opened; the numbers above are what
   was read), so the pair's line is not the contact's and its length reads as 1.3 cm of overlap.
   `first_carried` now believes a pair that reads as touching only when its ground point is at
   the tyre (inside the cylinder to `PAIR_SEAT`); a pair that reads as clear can only shorten a
   step. `test_a_pair_off_an_inactive_edge_is_no_contact` holds the measured pair.
6. **The tests guard the sweep**: with `_carried_sweep` switched off (undone at once),
   `test_a_wall_in_the_wheels_side_leaves_the_tread_on_the_ground` fails (`'true' but is 'false'`).
   The heightmap test (`test_a_cliff_of_the_heightmap_leaves_the_tread_on_its_foot`, a 71.6 degree
   face in one metre cell) was not run against HEAD's wheel: derived, HEAD leaves the heightmap's
   body out and nothing else is under the tyre.

## Measured

`measure_vehicles -- race,tractor-kenney,firetruck,sedan,suv-luxury,semi 45 scrape [steer=60]
[onebody]`, `--fixed-fps 60`; before = HEAD's wheel at 4857139.

- `onebody`, wheel straight. Before: `race` FR in contact 25 %, RR 63 %, 10.4 degrees of tilt, ends
  at 2.02 m/s; `tractor-kenney` RR 64 %; `firetruck` FR 95 %, RR 93 %. After: every wheel of
  every body 100 %, `race` 1.6 degrees and 37 N across, `tractor-kenney` 1.1 degrees: each line
  the two-body run's.
- `onebody steer=60`. Before: FR about 61 % on `sedan`, `suv-luxury`, `semi`, `firetruck`, 25 % on
  `race`. After: 100 %, and the bodies end where the two-body run leaves them (`sedan` 0.00,
  `suv-luxury` 1.78, `tractor-kenney` 2.07 m/s).
- Two bodies (this path moved from the loop to the sweep, not the same to the bit): contact
  100 % and 0 ticks off the travel as before; the forces across within 60 N (`tractor-kenney` FL
  steered 1101 -> 1158 N). `race` ends at 5.16 m/s for 5.00: its trace runs 4.99 to 5.28 m/s under
  the speed hold with the hull on the wall, the end figure is where that was sampled.
- `sedan,semi 45 side` and `kerb`: the same to the byte as before but the tool's own timing line;
  0 sweeps by contact on both.
- Sweeps by contact per run (`contact: N sweeps by contact`, 31ec0bf): `race` 870, `tractor-kenney`
  336 to 400, the others 230 to 251 steered. Cost, counted and not timed: 5382 probes over 1209
  sweeps wheel straight, 11015 over 2208 steered, so 4.5 to 5.0 `collide_shape` calls a sweep,
  where the loop it replaces was one more cast and rest test.
- Not run: the three CI measure gates and `scrape` with a trailer coupled (the first pass is
  untouched and no wall is in a wheel's side there; `side` and `kerb` confirm it on two bodies).

Full suite at the fix: 2505 cases, 0 failures.

## The second trigger: built, measured, taken out (the user's choice, asked mid-session)

The plan's trigger for finding 3 was "the rest contact lies deeper than the sweep's step"
(`unsafe + gap / n.up < safe - step`). On `sedan 45 kerb` it fired 306 times, on `semi` 583:

- Where the normal has a part along the axle: `gap -0.00572 ... n.up 0.638 n.axle 0.385`,
  `gap -0.00286 n (0, 1, 0) n.up 0.989 n.axle -0.128`; 2 to 6 mm in all. `cylinder_support` is the
  sharp cylinder's (its own comment: exact "but where its convex radius rounds the rim"), so the
  gap over-reads there, and `settled_drop`'s clamp has been absorbing it.
- On a square edge with no axle part: `gap -0.00221 n.up 0.818 n.axle 0.000`, two steps deep.
- 8 ticks of `sedan`'s 20 cm kerb at 30 km/h became cast start overlaps (full bump): not sorted
  into real or false.

The kerb figures moved a little with it (peak 5.9 -> 6.3 kN on one wheel). The plan's stop rule
applied; the user chose to queue it. `stopped_on`, its test and
`test_ground_under_a_deck_the_sweep_left_out_is_not_the_wheels` are not in the commit. The
fixture, for the item: `_wheel_on_a_rolled_body(0.0, Vector3(0.0, 0.6, 0.0), 0.07, true, welded)`
plus `_box(root, Vector3(4.0, 0.5, 20.0), Vector3(0.0, -0.30, 0.0))` (a flat 5 cm under the
deck); wanted: compression 0.06, read 0.0108.

## Commits

- af471cd wheel: `_carried_sweep`, `first_carried`, `_swept_past`; the tests; `docs/vehicles.md` § Contact.
- 31ec0bf measure: `contact: N sweeps by contact` per body.

## Deferred

- Finding 3, the silent form (Queue): the gap made exact for the rounded rim first.
- `settled_drop`'s `maxf(normal_up, 0.1)` (Queue, unchanged: every kept contact is still carried).
- The survey does not say which heightmap cliffs have drivable ground at their foot.
