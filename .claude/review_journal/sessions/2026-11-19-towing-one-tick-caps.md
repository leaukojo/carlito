# 2026-11-19: one-tick caps that do not see the coupling's other force (Opus, diagnose)

Item: the Queue's top line, parts (a), (b), (c). Diagnose only: no fix, the journal only.
HEAD at start: dfb54a2.

Outcome: (c) is gone at HEAD (c42ac3d fixed it on 2026-11-16; the item's figures predate it);
(b) is a cover with nothing behind it, proposed for removal (`proposals.md`, "The fifth-wheel
plate takes its whole one-tick stop"); (a) is float32 at the strip's 2.8 km on a jointed pair, no
force, added to the "To consider" strip line. Queue: the tighten-the-rest-gate line (Sonnet) and
the plate's whole stop (Opus, after the proposal). No `diagnose` line: every case is explained,
(a)'s solver step by inference (Jolt not instrumented).

## Tick order (read off the code)

One physics frame of a coupled `semi` (`BaseVehicle._physics_process`, `semi.gd:_tick_extras`,
`TowHost.tick_towing`): the chassis' `WheelDrive.tick` (its `size_cap_masses` off the chassis'
tensor alone, then every chassis wheel's spring, tyre and spin step), telemetry, then
`_tick_extras` -> `tick_towing` -> `TowedBody.tick_towed` (the bogie's `size_cap_masses` off the
trailer's tensor alone, its wheels) -> `_apply_yaw_friction` (the plate's pair, off the two tensors
in series). Every force goes in through `apply_force` / `apply_torque` on the frame's starting
velocities; Jolt then integrates all of them and solves the joint in its step. So no stop sees
another's force: each tyre cap and the plate's cap are sized as if each alone took the relative
motion to zero this tick. `contact_masses`' comment says the tyre caps are free-body figures,
which a joint can only make tighter (a coupled body's real effective mass is larger); the plate's
pair is the one stop sized on the coupled pair's moment, and it acts on the trailer's yaw that its
tyres' lateral caps also act on.

## (c) the laden `semi`'s `axle_load` step at rest

**Gone at HEAD; the item's figure is stale.** Run at dfb54a2:

| run | rear axle | towed bogie | speed |
| --- | --- | --- | --- |
| `measure_vehicles -- semi 20 rest` (box) | p-p 0.1 kg, 0.0 kg a tick | p-p 0.3 kg, 0.0 kg a tick | 0.0 flips /s, mean +0.03 mm/s |
| `measure_vehicles -- semi 20 rest trailer=bobtail` | p-p 1.4 kg, 0.0 kg a tick | | 0.3 flips /s, p-p 0.13 mm/s |
| `measure_semi_launch -- semi steady strict` | 0.01 kg a tick (gate 1) | | 0.0 /s (gate 3): PASS |
| `measure_semi_launch -- semi-conventional steady strict` | 0.00 kg a tick | | 0.0 /s: PASS |

What took it: c42ac3d (2026-11-16, "the contact query is posed level about its axle (no float32
grid off a long box)"). Its session (`git show 44495c5:.claude/review_journal/sessions/2026-11-16-contact-fix.md`,
§ After-runs) records `semi 20 rest`: "rear axle 0.6 -> 0.0 kg a tick, p-p 2.2 -> 0.0 kg; contact
speed 0.13 -> 0.02 mm/s". So the source was the contact's reading stepping on the measure strip's
6 km box (a float32 grid in the query's frame on a raked body), read through the springs and the
dampers into `suspension_force`: neither the coupling nor the yaw cap. The Queue line was written
before that landed and was not updated. Nothing to log per tick: the value does not step.

Left of (c): the rest gate's tightening it named (`REST_STEP_KG` 1 -> about 0.1 kg, worst read
0.03 kg on 2026-11-16, 0.01 / 0.00 laden today; bobtail reads below). And the contact-fix
session's own limit: on a heightmap or trimesh grade the reading still steps by ulp of the hub's
WORLD height (3.81 um at 48-50 m, 15.3 um at 150 m), which no frame removes. That is where the
summary's "AXLE number still moves by 1 kg (3 at most)" could still come from in a level; it is
not measured in a level (below).

Bobtail at HEAD (`measure_semi_launch -- <unit> trailer=bobtail steady strict`): `semi` 0.3 /s,
0.02 kg a tick; `semi-conventional` 1.0 /s, 0.03 kg a tick: the 2026-11-16 table to the digit.
So the gate's worst read is 0.03 kg; 0.1 kg is 3x it (`REST_FLIPS_S`'s margin) and 80x under the
fault (8.2 kg). The print's `against %.0f` would show 0.1 as "0": the brief changes it to `%.2f`.

In a level (temporary print in `semi.gd:_tick_extras`, reverted; `--level=<id> --vehicle=semi`,
the default box, ticks 301 to ~420, no input): `level_3` and `flatland` stand still (speed 0.00000
to 0.00001 m/s) and `axle_load` does not move to the third decimal (p-p 0.000 kg, 9425.9 / 9425.7
kg), so the AXLE number is steady there. `level_1`'s spawn is not a stand: the rig rolls at 0.145
-> 0.164 m/s in gear byte 0 (N) on the spawn's grade (body y 37.7 m), and `axle_load` steps 1.9 kg
a tick (7.6 max, whole-kg changes on 95 of 121 ticks): a moving rig on a heightmap, not (c)'s case.
Seen, not traced: a laden `semi` spawned on `level_1` rolls away in N with no input at 5 to 7 s
(the shell's spawn state, not a towing question).

So the summary's "Known and queued: a laden `semi`'s AXLE number still moves by 1 kg (3 at most)"
is from 2026-11-13 and no longer reads on the strip or on a level's flat stand: it goes.

## (b) `Articulation.YAW_CAP_SHARE`

**The cover has nothing behind it any more.** History: the share and the first
`lateral_cap_mass` landed together in 885a5a1 (2026-10-03), when the towed tyres' caps were sized
on `corner_mass`; the towed bogie's `size_cap_masses` (its own tensor) came in 18d9f10
(2026-10-16) and the row-sum `contact_masses` in c63daa8. The share's comment names only the
symptom of that day's pair ("a whole share makes a standing rig buzz").

Why it cannot overshoot now (derived, then measured): both stops are free-body figures. The
plate's `yaw_pair_moment` is the two solver tensors about their COMs in series (19 530 to 19 561
kg m^2 on `semi` + box, logged); the tyres' caps are each body's own `contact_masses`. The joint
locks the kingpin, so a relative yaw also swings the trailer's COM sideways on the kingpin's
lever: the moment the relative yaw really meets is far larger than either figure, so each stop,
and on the logs their sum, takes only part of the relative rate in a tick. Logged at share 0.999
(a 1 mrad/s kick, below the cap's crossing): the plate applies `0.999 * 19 560 * rate / dt` (116
N m at 99 urad/s) and the rate goes 380 -> 99 -> 73 -> 73 -> 69 -> 64 urad/s, never reversing on a
tick: the combined stop removes about a quarter of it, not twice it.

Runs (temporary prints in `tests/test_tow_host.gd`, share edited in `articulation.gd`; both
reverted; `node tools/godot_run.mjs --tests -- -a tests/test_tow_host.gd`; at exactly 1.0 the
unit test `test_one_tick_may_at_most_stop_part_of_the_relative_yaw` fails by its letter, so the
whole share ran as 0.999):

| | share 0.5 (HEAD) | share 0.999 |
| --- | --- | --- |
| `test_a_coupled_rig_standing_still_stays_mirror_symmetric`, `semi` peak relative yaw (limit 100 urad/s) | 0.057 urad/s, angle 0.001 urad | 0.126 urad/s, angle 0.0007 urad |
| same, `tractor` (drawbar, `yaw_friction_nm` 0: the share never runs) | 6.29 urad/s | 6.29 urad/s |
| standing `semi`, sign flips of the rate, ticks 30-89 | 25 of 59, mean 0.016 urad/s | 35 of 59, mean 0.019 urad/s (float noise both: the buzz the comment names read ~3e-3 rad/s) |
| 1 mrad/s kick on the trailer, rate ticks 30..33 | 851, 387, 178, 102 urad/s | 380, 99, 73, 73 |
| same, slow swing back (the patch springs' yaw mode, ~0.9 s) | first sign change tick 42, peak -169 urad/s | tick 43, peak -93 |
| 10 mrad/s kick (above the crossing: plate at its 2000 N m both) | 11614, 8462, 5184, 2258, 585, -22 | 11614, 8462, 5184, 2258, 43, -163 |
| same, swing back peak | -1908 urad/s | -1324 |
| `measure_vehicles -- semi 30 circle trailer=box`: cap binds | 2 of 708 ticks (the coupling's first two, before pull-away); rate 0.011 rad/s still at 11 s; circle R 8.60 m | figures identical to the digit |
| `measure_vehicles -- semi 45 track strict trailer=box` | PASS, drift 0.011 m | PASS, drift 0.023 m (the tracking drift is a float-seeded slow mode: noise) |
| `measure_vehicles -- semi 20 rest` (box) | rear p-p 0.1 kg, 0.0 a tick | rear p-p 0.2 kg, 0.0 a tick |
| `measure_semi_launch -- semi steady strict` rest gate | 0.0 /s, 0.01 kg a tick | 0.0 /s, 0.03 kg a tick (the bobtail's reading; under a 0.1 kg gate) |

Reading: no tick-rate alternation at the whole share, standing or kicked. What the half does
today: below the crossing rate (`friction * dt / (share * moment)` = 3.4 mrad/s at 0.5, 1.7 at
1.0) it halves the plate's stop, so a kicked trailer's relative yaw takes about twice as long to
fall and swings back 1.4 to 1.8x as far. On a slow full-lock turn the cap never binds (the rig
articulates at over 11 mrad/s the whole 12 s), so the "turning rig's plate friction cut to half"
of the cover sweep does not happen there; it binds standing, straight, and through each sway's
reversal.

What each stop knows of the other: nothing (tick order, above), and today neither needs to,
since both are under-deadbeat on a jointed pair. The fault d849de9 fixed (two forces on one
contact each sized to stop it, `taken`) is not this one: the plate and the tyres stop the same
relative yaw only through the joint, whose coupled moment neither figure sees.

Fix (a proposal: it changes the plate's force below 3.4 mrad/s): remove `YAW_CAP_SHARE`
(the cap becomes the whole free-body stop, `moment * |rate| / delta`), reword the comments at
`articulation.gd:10-12` and `:34-36` and `test_one_tick_may_at_most_stop_part_of_the_relative_yaw`
(its "the two together taking more reverse it" is the measured-false claim), and keep the standing
test as the guard on the buzz itself (it reads 0.126 against 100 urad/s at the whole share).

## (a) the standing rig's drift

**Still there, and neither (c)'s nor a towing force: float32 world positions 2.8 km out (the
measure strip's `START_Z` 2800 m), on a jointed pair.** The velocity the `rest` pass reads is one
the rig does not move at.

At HEAD, `measure_vehicles -- <unit> 20 rest[=brake|=handbrake]`, the window's mean speed:

| rig | D, pedals up | foot brake 30 % | handbrake |
| --- | --- | --- | --- |
| `semi` + box | +0.03 mm/s | -0.20 (4 of 4 wheels held) | -0.20 (2 of 4 held) |
| `semi-conventional` + box | +0.20 | -0.11 | |
| `semi` bobtail | -0.00 | +0.01 | |

Each laden figure is steady: speed p-p 0.00 mm/s and raw accel p-p 0.000 over the 3 s window,
the per-second speed step 0.00 from 3 s on. A constant velocity under zero acceleration.

Per-tick log (temporary print in `measure_vehicles._tick_rest`, reverted), `semi 20 rest=brake`,
t 4 to 9 s:
- Tractor body frame: forward -0.20 mm/s, up +0.77 mm/s, pitch rate +0.202 mrad/s; the trailer
  pitches with it (+0.196 mrad/s). The contacts' road speed reads 0.005 to 0.014 mm/s: no slide.
- But the body does not move at that velocity. Its origin's world z holds at 2799994.87305 mm
  to the print for 5 s (1 mm of travel would be 4 ulps: float32 at 2.8 km is 0.244 mm). Its pitch
  goes 3719.56 -> 3691.35 urad in 4 s, -7 urad/s against the +202 urad/s the state carries.
  Front compression moves 0.057 mm in 5 s, where 0.2 mrad/s over 1.9 m would move it 1.9 mm.
- The kingpin's two anchors (the chassis' `KINGPIN_LOCAL` against the trailer's origin) read
  -488.28 um apart along z = 2 ulps at 2.8 km, every tick (GDScript float32, so the gap is read at
  the same precision). Relative velocity at the kingpin: 0.00003 mm/s (the joint's velocity
  solve is met).

Moved to the origin (`START_Z` 2800 -> 0, temporary, reverted), the same four rows:

| rig | D | foot brake |
| --- | --- | --- |
| `semi` + box | -0.02 mm/s | -0.01 (pitch rate 0.008 mrad/s; anchor gap 1 um) |
| `semi-conventional` + box | +0.03 | -0.02 |

So the drift is 10 to 20x smaller at the origin and absent without the joint at 2.8 km. Reading
(inferred; Jolt's solver was not instrumented): at 2.8 km the joint's anchors cannot meet closer
than about an ulp along z, its position step corrects that gap every tick, partly as a turn of
each body about its COM (the kingpin sits 0.15 m over and 1.37 m behind the tractor's COM), and
the springs hold the rig against the correction, leaving a standing velocity that the position
step cancels each tick. The dampers and the tyres' caps do not see it: the compression hardly
changes and the contacts do not move. Bobtail has no joint: no drift.

Not a towing fault and not a force any one-tick cap owns. Player-visible: nothing measured (0.2
mm/s is 0.0007 km/h; `level_3` and `flatland` stand at 0.00000 m/s with the box). No Queue line:
the figure is a measure-tool reading no gate or `doc=` table uses, and the strip's size is the
user's "To consider" item (2026-11-14, not now); its line gains this effect. A level 500 m out
has ulp 61 um, so a quarter of this at most there (derived, not measured).

## Unit 5 findings (seen reading `tow_host.gd`, `towed_body.gd`, `articulation.gd` whole)

For unit 5's review; nothing fixed here.

1. Wrong comment, `towed_body.gd:104`: "What SemiTractor's fit check reads (body_is_colliding)".
   The fit check is `TowHost._watch_fresh_coupling` (`tow_host.gd:393-397`, the one caller); the
   drawbar's couplings run it too.
2. Wrong comment, `towed_body.gd:308-309` (`body_pos01`): "How far the payload has slid back from
   the spec's centre of mass, 0..1". The one body whose payload slides, the tanker, returns 0
   ("the surge is not a position", `tanker.gd:36-38`); the tippers return their body's raise
   (`tipper.gd:105-107`, `farm_tipper.gd:120`). And TowHost reads it for `body_up` and the tip
   notice as well as the interlock's clamp. Same misattribution in unit 6's `tipper.gd:105`
   ("SemiTractor reads it": TowHost does).
3. Simpler, `towed_body.gd:_sense_lateral`: `var raw := ...; accel_lat = raw` is a temporary
   left from the removed smoothing (b76f263): one line goes, bit-identical.
4. `articulation.gd:3`: "pure math for a tractor unit and one semi-trailer". `coupled_pose`,
   `articulation_angle`, `yaw_friction_torque` and `pair_moment` serve every TowHost, the drawbar
   included; only `kingpin_share` and `JACKKNIFE_MAX_DEG` are the fifth wheel's.
5. `articulation.gd:10-12` and `:34-36`, and `test_tow_host.gd`'s
   `test_one_tick_may_at_most_stop_part_of_the_relative_yaw` comment ("the two together taking
   more reverse it, so the rig buzzes"): measured false at HEAD (§ (b)). They go with (b)'s
   proposal.
6. Unit 6's, seen in passing: `fifth_wheel.gd` `YAW_FRICTION_NM` 2000 "mid of a greased plate's
   1-3 kN*m" cites no page.

## Runs

All `--fixed-fps 60` (measure tools) and wrapped in `timeout 600`; logs in the session's
scratchpad, not kept.

- `node tools/godot_run.mjs --fixed-fps 60 -- --headless --path . res://tools/measure_vehicles.tscn -- semi 20 rest` (and `trailer=bobtail`, `rest=brake`, `rest=handbrake`, `semi-conventional 20 rest`, `semi-conventional 20 rest=brake`, `semi 20 rest=brake trailer=bobtail`)
- `node tools/godot_run.mjs --fixed-fps 60 -- --headless --path . res://tools/measure_semi_launch.tscn -- <semi|semi-conventional> [trailer=bobtail] steady strict`
- `node tools/godot_run.mjs --fixed-fps 60 -- --headless --path . --quit-after 900 -- --level=<level_1|level_3|flatland> --vehicle=semi` (temporary print in `semi.gd`)
- `node tools/godot_run.mjs --tests -- -a tests/test_tow_host.gd` (temporary prints and a kick
  fixture in the test file; `YAW_CAP_SHARE` 0.5 and 0.999)
- `node tools/godot_run.mjs --fixed-fps 60 -- --headless --path . res://tools/measure_vehicles.tscn -- semi 30 circle trailer=box` and `-- semi 45 track strict trailer=box` (temporary print in `TowHost._apply_yaw_friction` for the circle; shares 0.5 and 0.999)

The kick fixture, for the proposal's after-run (it was a temporary test in `test_tow_host.gd`):
`_standing_rig(SEMI, x)`, 30 ticks, then `trailer.angular_velocity += up * kick` once (kick 1e-3
and 1e-2 rad/s), logging per tick `(trailer.angular_velocity - chassis.angular_velocity).dot(up)`
for 30 ticks.
