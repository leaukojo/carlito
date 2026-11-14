# 2026-11-13: review of the ui_and_gamepad_fixes plan's commits (user request)

Started at f78f937. Scope: d8e5afa..f78f937 (11 commits, the plan's phases 1 to 12), read as
diffs; no unit read whole, so no `Reviewed at` moves. The plan's two open findings are queued here
as F1 and F2.

## Fixed

1. The FULL dashboard's bars hid a sim fault. fab5e65 gave every `DashBar` a 0.25 s first-order
   lag and a held number, to stop the semi's AXLE / TRLR numbers changing every frame. The cause
   is F1 below, a sim artefact, so the lag was a cover over it on every generated bar (and delayed
   each bar's warn colour). Removed: a bar draws `value` as given again; the two-column layout
   stays. Guard: `test_no_instrument_smooths_its_value` (fails on the lagged `dash_bar.gd`, proven
   by running it against HEAD's copy). The rule sits on `Instrument`'s header. Consequence: a
   parked semi's AXLE / TRLR numbers flicker again until F1 is fixed.
2. `FamilyContent` (Flatland's drone crates, 53caca8) had no test. Added
   `tests/test_family_content.gd`: the crates are in the tree only with a drone, and a drone spawn
   puts a crate dropped elsewhere back at its pose.

3. `tests/test_shell_menus.gd` leaked the challenge lock between tests: a test that ends with an
   attempt running (`test_boot_spawn_point_moves_the_body_and_respawn_returns_there`) left
   `InputRouter`'s `_bridge_only` set, and a driving press from a connected pad then raised the
   lock's notice in `test_boot_sticky_notice_outlasts_a_transient_one` (seen once in a full run:
   the text read `LOCAL DRIVING OFF IN CHALLENGES ...` where `STICKY` was expected). `after_test`
   now clears the lock on `InputRouter` and `Bridge`. That the press came from the pad is inferred
   (the machine's pad is in use for other work), not captured.

Suite after the fixes: 2493 cases, 0 failures.

## F1: a parked truck's axle load alternates every physics tick

Repro (about 1 min each, `--fixed-fps 60` before `--`):
`node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_semi_launch.tscn -- semi steady`
and the same with `trailer=bobtail`. Read at f78f937:

| run | signal | mean kg | p-p kg | mean change per tick kg | mean crossings /s |
| --- | --- | --- | --- | --- | --- |
| box, parked | `axle_load` | 9428 | 9 | 6.6 | 59.7 |
| box, parked | `trailer_axle_load` | 17542 | 13 | 12.7 | 59.7 |
| bobtail, parked | `axle_load` | 3830 | 101 | 98.5 | 59.7 |
| box, 40 km/h | `axle_load` | 9514 | 944 | 2.9 | 1.1 |
| bobtail, 40 km/h | `axle_load` | 3839 | 834 | 1.4 | 0.1 |

59.7 mean crossings a second at 60 Hz is a period of two ticks: the summed rear spring force
steps up one tick and down the next, at a fixed amplitude that does not decay over the 3 s
sampled after a 10 s settle. It is a parked fault: rolling, the per-tick change falls to 1 to 3 kg
and the spread there is slow (the speed hold's pitching), not this.

"Parked" is the tool's P1: standing in D (bridge gear byte 1, automatic), both pedals and the
handbrake released (`MeasureRig.drive(0.0, 0.0)`), engine idling at 600 rpm, `applied_throttle`
0.0714. Not a body on its parking brake, and not in N.

The run's own trace (`reports/semi_launch/semi_bobtail.csv` and `semi.csv`, gitignored, written
by the same runs) shows the suspension is the symptom. Two consecutive ticks at t = 8.0 s:

| run | tick | speed m/s | rear wheel omega rad/s | rear comp. | rear spring N | front spring N | pitch deg |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bobtail (gear 6) | a | +0.0078 | +0.0332 | 0.16325 | 19011 | 20305 | -0.5238 |
| bobtail (gear 6) | b | -0.0124 | -0.0461 | 0.16283 | 18523 | 20567 | -0.5279 |
| box (gear 3) | a | +0.0016 | +0.0042 | 0.40100 | 46177 | 24630 | 0.4077 |
| box (gear 3) | b | -0.0013 | -0.0043 | 0.40103 | 46215 | 24667 | 0.4075 |

(`rear comp.` is the fraction of the 0.32 m travel. The next six ticks repeat the pair: speed,
omega and pitch to the digits shown, the spring forces within a few N.)

What that shows:
- The whole body rocks fore and aft with a period of two ticks: its speed and its drive wheels'
  spin change sign every tick, and the load moves with them. Bobtail, the front and rear springs
  step in antiphase (the cab pitches). Laden, the tractor's two axles step together and the
  trailer's bogie the other way (`trailer_axle_kg` 17548 / 17536 against the drive axle's
  9424 / 9432): the load passes back and forth through the kingpin.
  The axle-load alternation is that motion, read through the springs and dampers.
- It is a longitudinal force that alternates. From the speed column alone: the bobtail's speed
  steps 0.0202 m/s a tick, which on its 8000 kg is about 9.7 kN swinging each tick (1.2 m/s²).
  Not read off `accLong` itself: check what that signal carries at rest.
- The reading is the applied force (`VehicleTelemetry.axle_load_kg` of the summed
  `RayWheel.suspension_force`), so the bridge carries all of it.
- The laden rig's speed steps 0.0029 m/s a tick. Its mass was not read here, so the two forces
  are not compared; a like force on a heavier rig would explain the smaller swing, untested.
- Earlier guesses this rules down: a contact-reading jitter or a damper effect in the spring
  block would not flip the wheels' spin. The semi declares no `anti_squat_slope` (default 0), so
  the one-tick-late link term is not it on this body (`garbage-truck` declares 0.219).

Where to look (none tested): what holds a body still in D with the pedals up, against the idle
creep the driveline sends. Candidates: the standing wheel's static-friction patch spring
(`RayWheel.STICK_TICK_STIFFNESS` and the stick / slip hand-over), the hill hold
(`WheelDrive.hold_step`, `HillHold`), the converter or clutch creep torque changing sign with the
wheel's spin, and any drag or brake term signed by a speed that crosses zero each tick.

First step for the session: on the standing bobtail, log per tick each longitudinal term on a
drive wheel (the drive torque reaching it, brake and hold torque, the patch force `force_long`,
rolling drag, whether the wheel reads held or slipping). Then bisect by state, each a one-line
change to P1's `MeasureRig.drive` call: in N; in D on the foot brake; in D on the handbrake; with
the hill hold off. Then the same on `garbage-truck`, `tractor-kenney` and a car, to learn whether
it is every body or the trucks. A fix sits in the wheel's spin step or the hold, so it needs the
before and after measure runs and probably a proposal. When it is fixed, add a test that a body
standing in D has a steady speed sign and a steady `suspension_force` tick to tick, so the fault
cannot come back unseen.

After the fix: re-run `steady`. If a ripple a real axle-load sender would filter is left while
driving, a sender filter is a separate proposal: a labelled model on the signal with a sourced
time constant, never a display lag (`test_no_instrument_smooths_its_value`).

## F2: a wheel on the ground with its side in a wall reads the wall's normal

`RayWheel._contact_query` takes the normal of `get_rest_info` where the sweep stops, and Jolt's
rest contact is the deepest one. With the tread on the ground and the wheel's side a few
centimetres into a wall, the deepest contact is the wall's, so `_contact_normal` is horizontal:
that tick the whole spring load is applied along it (`body.apply_force(normal * suspension_force,
...)`), pushing the body off the wall, and the corner carries nothing.

Evidence: phase 10 of the plan found it and left it (6cd404f changed only the lying-wheel case).
`test_a_wall_in_the_wheels_side_leaves_its_contact_as_it_reads` (`tests/test_wheel_spin.gd`) pins
`in_contact` and the compression in that pose but asserts no normal, so nothing pins the fault
either way. Not measured here: how many ticks it lasts while scraping a wall, and the size of the
shove on a shipped body.

Where it would show: a car sliding along a barrier, a kerb or a building; a truck beside a dock.

Directions, for the plan to choose between (each changes a contact, so it ends in a proposal):
- ask the space for several contacts at the stop (`collide_shape` / `get_rest_info` with the wall
  excluded and retried) and keep the one the tread can carry (`off_tread` is false);
- keep the deepest contact for the drop but take the tread's normal when the deepest is
  `off_tread` and a tread contact exists;
- a wall in the wheel's side as its own force (a sidewall scrub), which is a new model.
`RayWheel.off_tread` and `lying_on` are the predicates 6cd404f added; reuse them.
First step: a failing test in the pose of the existing wall test that asserts the normal is the
ground's, and a `measure_vehicles` pass that scrapes a wall.

## Second pass (same day, on the user's word): the three items first left as they were

4. A held stick searched the HUD for a button on every motion event. `UiScale._input` takes any
   joypad motion past the deadzone as a navigation press, and with nothing focused (driving) each
   one ran `_focus_target`, a `find_children` over every HUD subtree. Measured natively on the
   booted shell at FULL density, 2000 calls each: 26.9 us on `sedan-sports` (132 nodes under
   `UiScale`), 31.8 us on `semi` (156), 36.8 us on `drone-mk2` (184); it found nothing each time.
   Not measured on the web build. Fix: only the stick's crossing of `STICK_USE` is a press
   (`UiScale._stick_crossed`). `test_ui_scale_takes_a_held_stick_as_one_press` fails without it
   (run against the old file: the second event of a held stick focused the button again).
5. `FamilyContent` put the crates back on a spawn only; the plan's phase 7 says a respawn does
   too, and nothing recorded a change of mind. It now also hears the body's `respawned`: the
   drone's own `respawn` drops a carried crate first, then every crate goes back to its pose.
   `test_a_respawn_puts_the_crates_back` covers a dropped crate, a carried one, and another body's
   respawn bringing nothing back. Level 6's crates are plain level nodes and stay where a respawn
   leaves them, as before: the two levels differ there.
6. `RayWheel.LYING_DEG`'s `COMPROMISE` label (6cd404f) triaged: a real compromise, the label
   stays. It says what is true (no sidewall: an overturned body lies on its hull with a wheel's
   side in the ground) and what undoing it costs (a collision shape per wheel).
7. The guard of fix 1 now also covers `AttitudeIndicator` and `WindRose` (no per-frame step in
   either); `docs/systems.md` and the plan (D9) state the rule.
8. § F1 rewritten from the run's own trace: the first version's hypotheses pointed at the contact
   reading and the dampers, and the trace shows the wheels' spin changing sign every tick.

Left as it is: the parking-brake latch stays set under a driving bridge and returns when the
bridge leaves. It is a local latch (`src/input/CLAUDE.md`), so this is as meant.
