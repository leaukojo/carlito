# 2026-11-16: the contact's two reading steps (Queue A2, Fable, diagnose only)

Started at de3b1b4. Read first: `2026-11-16-standing-alternation.md` (the gather). Nothing fixed.
The probe (a gdUnit file, run from `tests/` and removed), its last output and the log scripts are
in `C:/Users/Ccamy/AppData/Local/Temp/claude/rm-logs/a2/` (`test_a2_probe.gd`,
`a2_probe_last_run.txt`, `band.py`, `band2.py`, `h.py`).

**Both steps are made in `RayWheel._contact_pass` (`wheel.gd:932-982`), neither by the rolling
moment's patch: the patch only moves where a body rests and how often it crosses a step.**

## (a) The 10 % cross cell: `settled_drop`'s clamp cuts a real offset at every sweep stop

The gap subtracts the cylinder's ROUNDED support (`cylinder_support(..., _convex_radius)`,
`wheel.gd:978-980`). On the tool's ramp (30 x 2 x 400 m, the wheel 60 m along: its far corner is
past the engine's switch, `docs/vehicles.md:110`) the sweep and the rest test both answer from
the SHARP cylinder, whose rim reaches `e = convex_radius * (sin a + cos a - 1)` further along the
normal, `a` the axle's lean to the face. So with `T` the drop where the sweep's shape touches:

- the gap puts the touch at `T + e` (the rounded touch), `e` deeper than the sweep's own bracket
  `[safe, unsafe]` can hold when `T` is within `e` under a stop `G`;
- `settled_drop` clamps to `unsafe_drop`: the wheel reads `min(T + e, G)`. A corner sinking
  through `G` reads `T + e` just over it and `G` just under it: a step of `e` in one tick, then a
  dead band `e` wide where the reading does not move at all.

No reading can land in `(G, G + e)`. A corner whose load needs one there chatters across `G`: the
damper's finite difference turns `e` into `damper * e * 60` (the `semi`'s +88 / -115 N).

Evidence:

- The gathered logs, every tick after 5 s, HEAD and patch (`band2.py`): no unit wheel ever reads
  inside the band, and the band's width is `e` computed from that axle's lean
  (`|comp_L - comp_R| / track`, `convex_radius` 0.0168 m = 0.08 x the 0.21 m half width):

  | wheel | least read drop over a stop, HEAD / patch | `e` from the lean, HEAD / patch |
  | --- | --- | --- |
  | FL | 0.1047 / 0.1026 mm | 0.1059 / 0.1044 mm |
  | FR | 0.1027 / 0.0990 mm | 0.0966 / 0.0988 mm |
  | RL | 0.0956 / 0.1001 mm | 0.0963 / 0.0996 mm |
  | RR | 0.1029 / 0.1009 mm | 0.1033 / 0.1027 mm |

  The trailer's six read nothing within 0.255 to 0.294 mm over a stop (its lean is larger; its
  track was not looked up). The gather's 0.107 mm jump is this `e` (0.104 mm at the unit's
  6.21 mrad) plus the tick's own sink.
- The probe, a frozen body leaned 6.21 mrad on a flat slab, the hub lowered 2 um at a time across
  the stop at 166/256 (one slab in the world per case):

  | case | the wheel today, against the sharp touch | worst step in one 2 um move |
  | --- | --- | --- |
  | ramp-sized slab (30 x 2 x 400), 60 m along | +2.0 to +104.1 um | 102.1 um |
  | 8 m slab (engine answers rounded) | +104.0 to +104.1 um | 0.09 um |
  | ramp, lean 2 deg | +2.0 to +578.2 um | 576.1 um |
  | ramp, lean 0.06 rad | +10 to +979 um | 969 um |
  | ramp, lean 0.10 and 0.30 rad (`e` over one stop) | reads only the stops: 4 values in 240 moves | 1230 um |
  | ramp, no lean | -0.10 to +0.05 um | 0.12 um |

  With the clamp's bound moved by `e` the same reading is continuous on every row (0.1 to 0.6 um
  per move, 240 distinct of 240), whichever shape the engine answered from.
- Under a level axle `e` is 0: the bobtail (b) is not this.

It ships: Flatland's `InfiniteGround` (`src/levels/base/infinite_ground.gd:67`) is one box of
`extent`, past the switch like the tools' strip, ramp and kerb. Heightmaps and welded meshes
answered rounded in `docs/vehicles.md`'s account and in the probe's small slab; not re-measured on
a heightmap here.

## (b) The bobtail: the strip's far corners lose 2^-19 m in the raked query frame

Every compression change in the gather's rest window is a step of 2^-19 m = 1.907 um (`h.py`:
steps of 0.94 to 1.06 or 2 units, 3 to 10 distinct values in 180 ticks per wheel, HEAD and patch
alike; the fronts' 3.4 to 3.9 um are two units). The query cylinder is posed with the body's pitch
in its basis (`wheel.gd:935`, `wheel_basis * Basis(BACK, PI / 2)`). Jolt puts the ground's shape in
that frame; a corner of the 6 km strip then has an up coordinate of `3000 m * sin(0.5255 deg)` =
27.5 m, where float32 holds 2^-19 m. The contact's height comes back on that grid.

Evidence (the probe, a body raked -0.5255 deg, hub lowered 0.24 um at a time, 240 moves):

| case | today | query turned about its axle onto the face's normal |
| --- | --- | --- |
| 6 km strip, 2800 m out | 32 distinct readings, steps 1.85 um | 237 distinct, worst 0.94 um (float32 of z at 2800 m) |
| 6 km strip at its centre, and 700 m out (earlier run) | 26 distinct, steps 1.9 um | 200 of 200 |
| 8 m slab | 240 distinct, 0.09 um | 240, 0.07 um |
| ramp (400 m: `200 * sin` = 1.8 m, grid 2^-23) with lean | 240 distinct (once (a) is out) | 240, 0.06 um |
| ramp pitched 10 %, body with it, lean and rake | 121 distinct, 0.33 um | 120, 0.48 um |
| the same, frame on WORLD up (5.7 deg off the ramp's face) | - | 60 distinct, 1.67 um: `200 * sin(5.7)` = 19.9 m |

So the grid is `ulp(L * sin(t))`, `L` the box's reach along its face from its own origin and `t`
the tilt between the query's frame and the box's axes; the wheel's distance out does not enter (the
strip's centre reads the same grid). The cylinder is a solid of revolution: turning the query
about its axle changes nothing but `t`. Inside the engine this was not traced further (no source
opened); the scaling above is the evidence.

Predicted, NOT measured: a heightmap or welded mesh keeps its vertices in its own frame, so a
wheel `D` m from that body's origin on a grade would read `ulp(D * sin(grade))` with today's
frame (500 m out on 10 %: 3.8 um), and nothing with a frame level about the axle. The fix
measures this first.

## (c) Is each the whole of the patch's alternation?

- Cross cell: yes, on the evidence. The FL is the only unit wheel whose rest lands in a band on
  the patch (on the stop 1715 of 3302 ticks); HEAD rests 0.04 mm past the band (0.10 N), the A2
  law tree 0.015 mm under the stop (0.17 N) although its standing wheels answer harder still. The
  FR's 23 N is the FL's step through the bar (`bar` moves 56 N with it).
- Bobtail: every step seen is a grid step (0.46 N of spring, about 3 N of damper per wheel); the
  patch changes how often a wheel crosses a grid line (RL: 2 crossings in 180 ticks at HEAD, 57
  on the patch), not what a crossing costs. Whether anything is left once the reading is
  continuous is not derivable: the fix's after-run says (stop condition below).

## Brief (Queue A2, the fix)

Both in `_contact_pass`; `wheel.gd` is the kept patch's file, so this lands on HEAD first and A3
applies its patch over it (`git apply -3`).

1. **The bracket's touching side takes `reach`.** After the gap:
   `reach = (cylinder_support(n, axle, r, hw, 0.0) - cylinder_support(n, axle, r, hw, _convex_radius)) / n.dot(up)`
   and the drop is `clampf(unsafe_drop + gap / n_up, safe_drop, unsafe_drop + reach)`.
   `settled_drop` takes `reach` as a new argument: its `unsafe_drop` is both the base and the
   bound, so a widened bound passed in its place shifts the reading (done twice in the probe).
   Same to the bit wherever today's clamp does not bind on that side, so on every heightmap and
   mesh. Why the bound is right: on a face the rest test's point and normal are the same from
   either shape, so the gap always gives the rounded touch, and the sharp sweep's stop is at most
   `reach` short of it. Not the fix: subtracting the sharp support instead (it moves the read
   height of every leaned wheel on every level by `e`, 0.58 mm at 2 deg), a wider tolerance, or
   anything on `compression` or the damper.
   Left as it is, noted: sweep sharp and rest rounded in the same tick (near the switch distance)
   with `e` over one stop (lean over about 0.08 rad) still reads the stop.
2. **The query is posed about its axle on the collider's up.** x = `c_up` less its part on the
   axle, normalised; y = minus the axle as today (`_carried_sweep` reads `basis.y`); z = x cross y.
   `c_up`: the last contact's collider's `global_basis.y`, cached when `contact_collider` changes
   (it is zeroed at the top of `_contact_query`), world up with none or a freed one; today's basis
   when x is degenerate (the wheel on its side). First, the measurement that decides it: a
   heightmap or trimesh fixture 500 m or more from its body's origin on a 10 % grade, hub stepped
   0.24 um: a grid today that the frame removes means build it; no grid there means it is the
   tools' strip and Flatland only, and the plan asks the user whether the frame or a shorter
   strip (`2026-11-14-sweep-rest-disagree.md` § To consider) is wanted. Not to the bit: every
   contact moves at float noise.
3. Comments and docs that follow: `settled_drop`'s "Exact on a face" (`wheel.gd:822`),
   `cylinder_support`'s last sentence (`:801-802`), `_contact_query`'s (`:865-874`),
   `docs/vehicles.md:105-118` (at its character cap: replace, do not add).

Tests that fail now and pass after (fixture below; one slab in the world per case, see the note):

- a wheel leaned 6.21 mrad on a 30 x 2 x 400 slab, 60 m along, hub stepped 2 um across the stop
  at 166/256: no reading moves more than 1 um over its hub's move (today 102 um); the same at
  0.1 rad (today 1230 um);
- a wheel raked -0.5255 deg on a 40 x 2 x 6000 slab at its centre, hub stepped 0.24 um: at least
  200 distinct readings in 240 (today 26 to 32).
- Must stay: the same two on an 8 m slab (today 0.09 um), the ramp pitched 10 % with lean and
  rake (today 0.33 um), `test_the_cast_reads_a_face_with_its_hub_on_a_sweep_stop`.
  `test_the_cylinder_support_is_where_the_engine_touches_across_the_axle` holds on its 4 m slab
  only: its comment says "at every lean" with no word of the slab's size; reword it.

Runs, HEAD then after, `--fixed-fps 60`: `test_wheel_spin`, the suite; `measure_grade --
doc=park park_cell=semi:cross:5.7` with the gather's probe (`probe_head.diff`) and `band2.py` (the
band must be gone: readings land anywhere over a stop); `measure_semi_launch -- semi steady strict
trailer=bobtail` (`rest reading:` 0.11 kg at HEAD); `measure_vehicles -- semi 20 rest`; one `kerb`
and one `scrape` pass (`docs/vehicle_measurements.md` § Measure-tool run lines). A `doc=` table is
re-run only where a figure moved.

Stop and hand back, the change undone, if: a fixture above still steps; a `test_wheel_spin`
contact test fails for anything but its comment; the bobtail's `rest reading:` rises over HEAD's;
or, on A3's patch over this fix, the bobtail still reads over HEAD's 0.11 kg or the cross cell's FL
still alternates over 2 N (then the patch has a source of its own: log `dcomp` again, it is no
longer a grid step).

### Fixture

```gdscript
## A slab whose top face passes through the origin, pitched `grade`; a frozen body leaned `lean`
## and pitched `rake` more; the wheel's sharp tyre over the face's point `on` at 166/256 of the
## travel, the hub lowered `step` at a time. Returns [worst reading move less its hub's move,
## distinct readings]. Free `root` and wait two physics frames before the next case.
func _stepped(slab: Vector3, on: Vector3, grade: float, lean: float, rake: float, step: float) -> Array:
	var root := Node3D.new()
	add_child(root)
	var slope := Basis(Vector3.RIGHT, grade)
	var ground := _box(root, slab, Vector3.ZERO)
	ground.global_transform = Transform3D(slope, slope * Vector3(0.0, -slab.y * 0.5, 0.0))
	var body := RigidBody3D.new()
	body.freeze = true
	body.collision_layer = 0
	root.add_child(body)
	var tilt := Basis(Vector3.RIGHT, grade + rake) * Basis(Vector3.BACK, lean)
	body.global_transform = Transform3D(tilt, slope * on)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gd: GroundDriveSpecScript = GroundDriveSpecScript.new()
	gd.wheel_radius = 0.36
	gd.wheel_inertia = 1.0
	gd.tyre_half_width = 0.21
	gd.rest_length = 0.32
	var w := WheelScript.new(Vector3(0.0, 0.6, 0.0), false, false, null, 300.0)
	w.apply_suspension(gd)
	var terrains: Array[Node] = []
	var space := root.get_world_3d().direct_space_state
	var sharp := WheelScript.cylinder_support(slope.y, tilt.x, 0.36, 0.21, 0.0)
	var worst := 0.0
	var seen := {}
	var last := NAN
	var last_truth := NAN
	for i in 240:
		var want := 0.32 * 166.0 / 256.0 + step * (120 - i)
		w.anchor = tilt.inverse() * (slope.y * sharp + tilt.y * want)
		w.tick(body, gd, space, 0.0, 0.0, TICK, terrains)
		var truth := ((body.global_transform * w.anchor).dot(slope.y) - sharp) / tilt.y.dot(slope.y)
		var read := 0.32 - w.compression
		if not is_nan(last):
			worst = maxf(worst, absf((read - last) - (truth - last_truth)))
		last = read
		last_truth = truth
		seen[snappedf(read, 1e-9)] = true
	remove_child(root)
	root.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [worst, seen.size()]
```

Cases: lean `(30, 2, 400), (0, 0, -60), 0, 0.00621, 0, 2e-6`; rake `(40, 2, 6000), (0.72, 0, 0),
0, 0, deg_to_rad(-0.525532), 2.4e-7`.

A trap that cost this session four runs: a slab left in the world by an earlier case answers the
next case's queries (a ramp under a "small slab" case made it read sharp; a pitched slab gave a
15 mm offset). `auto_free` frees at the test's end, not the case's.

## For unit 3a's next read (seen, not acted on)

- `docs/vehicles.md:112-114` says the two answers "differ by the sharp shape's reach, millimetres
  at most" as a size of error; the code turns that reach into a step at every sweep stop (a).
- `_contact_pass` with `rest` empty after the bracket has moved on reads `safe_drop` and `up`
  for a normal (`wheel.gd:974-975`): the mixed case noted under the brief's item 1.
- "To consider", the 80 m kerb's and the strip's 1 to 3 mm of contact noise: (a) reads whole
  stops (1.25 mm) under a wheel leaned over about 0.08 rad on sharp-mode ground. Re-measure after
  the fix before deciding anything there.

## Commits

The journal's only.
