# Plan — truck model hygiene: per-axle springs, spring-brake notice, honest tests and tools

Goal: fix what the semi launch investigation exposed. The rig's permanent nose-up and the Kenney
trucks sitting on their rear bump stops share one cause (one spring rate for two very different
axle loads); the spring-brake gate locks the rear axle with nothing on screen saying why; two
tests pin the wrong relationship (one truck's looks against the other's, and copied geometry
literals); the launch tool reports a "static pose" that is still bouncing; and spec headers carry
derived numbers that go stale on every geometry edit. Each phase stands alone and is verified by
the tools before the next starts. Delete this file when done; distil each phase's conclusion into
the CLAUDE.md named in it.

Written 2026-09-17. Status: **not started.** Phases 3-4 are prerequisites for
`heavy_vehicle_feel.md` and `centre_of_mass_heights.md` (every feel number there is measured
against the static pose this plan fixes).

Read first, every phase: root `CLAUDE.md`, `src/vehicles/CLAUDE.md` § Wheels and § Measuring,
`src/vehicles/truck/CLAUDE.md` § Brakes/retarder/air and § The fifth wheel. Measure, never tune
by feel; nothing ships without before/after numbers from `tools/measure_semi_launch.tscn`,
`tools/measure_vehicles.tscn` and the suite.

## Phase 1 — tests and tools tell the truth

Effort **low**. Mode: accept-edits. One Sonnet sub-agent.

1. `tools/measure_semi_launch.gd`: the "P1 static pose" block is sampled 2 s after the spawn drop
   while the rig is still settling (reads ~0.4° and ~10 % of travel high). Report the static pose
   off the LAST tick of P5 (the quiet standstill) and label it so; keep the P1 block as "post-drop"
   or drop it. Re-run `-- semi` and `-- semi-conventional`; the standstill numbers must match the
   ones in `truck/CLAUDE.md` § The fifth wheel (1.5° / 0.7°, 60 % / 32 %).
2. `tests/test_truck.gd` `test_the_conventional_leaves_the_trailers_the_same_room_to_swing`: it
   pins the conventional's kingpin-to-sleeper gap against the cab-over's kingpin-to-cab gap, which
   ties one unit's silhouette to the other's. The physical requirement is that EACH unit's gap
   clears the trailers' worst forward swing. `tests/test_trailer.gd` already computes that swing
   (`_worst_forward_swing`, 1.50 m today). Make both units assert `gap ≥ worst swing + margin`
   against that figure and drop the unit-vs-unit comparison; keep the "conventional has the longer
   wheelbase" assertion (that one is physics). Then the conventional's sleeper may be authored to
   whatever length looks right (it is 1.13 m now only to satisfy the old test) — leave the scene
   alone in this phase, note it in the report.
3. `tests/test_trailer.gd` ~236-241: the `rear_axle_share` literal block copies the semi's axle and
   kingpin z. Read them off `semi_spec.tres` and `FifthWheel.KINGPIN_LOCAL` instead, and assert the
   plate-share band from the same numbers. `test_the_probes_sit_where_the_trailer_does_and_clear_the_road`
   already reads the gap; check no other test carries a copied station.
4. Verify: `runtest.cmd -a tests/test_trailer.gd -a tests/test_truck.gd`, both launch runs. Distil
   into `src/vehicles/CLAUDE.md` § Measuring (one line: a static reading is a standstill phase, never
   the spawn settle) and `truck/CLAUDE.md` § Tractor-unit variants (the gap rule is against the
   trailers' swing, per unit).

## Phase 2 — the spring brakes say so

Effort **medium**. Mode: accept-edits. One Sonnet sub-agent.

`TruckVehicle._apply_spring_brakes` pins the rear axle with no cue; after an E-recouple plus a
brake application the gate fires seconds later, mid-throttle (measured: conventional at 4.7 m/s,
AIR1 2.97 bar). Add a screen notice on the EDGE of the gate applying, through the existing
`GameState.notice.emit` path the body interlock and tow host use (`BODY_INTERLOCK_NOTICE` shape):
text like `SPRING BRAKES APPLIED - AIR LOW`, dwell a few seconds, fired once per application (a
latch on the gate state, cleared when it releases), never per tick. No lamp, no contract change,
no local timer beyond the dwell the notice API already takes — the lamp rule in root `CLAUDE.md`
stays intact. Test: a pure test on the latch (fires on false→true, silent while held, re-arms on
release) in `tests/test_truck.gd`. Verify by the launch tool's P6 on `semi-conventional` (the
run that trips it) and by driving: recouple, brake 3 s, floor it. Distil into `truck/CLAUDE.md`
§ Brakes/retarder/air beside the measured margin.

## Phase 3 — one spring rate per AXLE

Effort **high**. Mode: **plan-mode first**, then accept-edits. Opus for the physics, Sonnet for
the generator/tests/measure sweep.

Today `GroundDriveSpec.spring_rate` serves every wheel, so a body whose rear carries 2-3× the
front's load (both tractor units coupled, the Kenney garbage truck and firetruck, which sit on
their rear stops at 26.3 kN/wheel against a 20.8 kN spring) rides nose-up on a compromise rate.
Add `spring_rate_rear` (0 = same as `spring_rate`, the `wheel_visual_radius_rear` precedent) and
carry the per-wheel rate on `RayWheel` (set in `WheelDrive._init` off `is_rear`), used by the
spring term in `RayWheel.tick`. Decide in plan mode, with numbers, whether the dampers follow
(`damper_bump`/`damper_rebound` scaled by `sqrt(rate_rear / rate)` keeps the damping ratio, and
the 60 Hz one-tick damper clamp already bounds it) — the honest default is to scale them, so a
stiffer axle is not under-damped. Scaling by the rate alone keeps the BOBTAIL ratio (0.28 on
the semi's rear today); coupled, the plate's 6.47 t lands on that axle and the ratio falls to
~0.17, so the rear damper must be sized for the coupled corner mass as well —
`heavy_vehicle_feel.md` phase T2 does that on top of this phase, in the same spec field. Then:

- Size the rear rates from the load each rear axle actually carries (the semi spec header's own
  arithmetic; the Kenney trucks via `gen_kenney_vehicles.gd`'s recipe so the regen does not wipe
  it, with `tests/test_kenney_variants.gd` re-deriving it). Target the same ~35-45 % static
  travel front and rear coupled to the box.
- Touch every reader of `spring_rate`: `tests/test_trailer.gd` `_travel_used`,
  `tests/test_vehicle_catalog.gd` (the downforce travel budget), `measure_semi_launch`'s
  `spring_rate*rest_length` bottoming line, `docs/vehicles.md` if it names the field.
- Re-measure: `measure_semi_launch` both units (static pitch should approach 0°, launch margin
  must not shrink), `measure_vehicles -- all 45 track strict` (every wheeled body, the CI gate),
  `-- garbage-truck 45 coast` and `-- firetruck 45 coast` (no hull contacts outside the spawn
  window), and the full suite. Rule 9's 60 Hz clamps are not touched.
- Distil into `src/vehicles/CLAUDE.md` § Wheels (the field, the damper rule) and delete the
  "one spring rate per vehicle, so this is a compromise" sentences in `truck/CLAUDE.md`,
  `semi_spec.tres` and `conventional_spec.tres`.

## Phase 4 — spawn at rest height

Effort **low-medium**. Mode: accept-edits. One Sonnet sub-agent.

Every spawn drops the body from the marker (0.6 m in the measure tools) onto its springs: the
rig bottoms its rear, lifts its front and registers chassis contacts for ~0.3 s, which every tool
then has to explain away as "the spawn drop". Give `BaseVehicle` a pure `rest_ride_height()`
(`wheel_radius + rest_length − lowest wheel anchor y`, i.e. wheels just touching, springs
unloaded; 0 for a wheel-less body) and have `Level._spawn_vehicle` and the three measure tools
place the origin that far above the ground under the marker (a `Layers.SOLID` ray, the
`ground_snap` pattern). The trailer needs nothing: it couples 12 ticks later against the settled
tractor. Test the pure function; verify the launch tool's P1 no longer reports chassis contacts
or a front wheel out of contact, and `measure_vehicles -- semi 45 coast` reports no hull contact
at all. Distil into `src/vehicles/CLAUDE.md` § Measuring (one line).

## Phase 5 — headers carry reasoning, tests carry numbers

Effort **low**. Mode: accept-edits. One Sonnet sub-agent, after phase 3.

`semi_spec.tres` and `conventional_spec.tres` headers quote derived figures (drive-axle kg,
travel percentages, plate share) that moved three times during the launch work and were wrong
before it. Keep the reasoning and the formula in the header; move every derived number into a
test that computes it from the spec (`test_trailer`'s travel bands already do this for the
springs; add the plate share and bobtail front share) or into the measured record
`tools/measure_semi_launch` prints. Same sweep over `truck/CLAUDE.md` § The fifth wheel: keep
the measured launch figures (they are the evidence for the wheelbases) and drop numbers a test
now pins. Then delete this plan file.
