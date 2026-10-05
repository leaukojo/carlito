# 06 — Shift policy, start gear, shift trace

Shared context: `00_README.md`. Root cause 1 (driveline). Size: medium. Recommended after brief 05
(the engine as a rotating mass and the coupling model are the foundation a shift policy gets more
honest on), though the policy itself is pure logic and can be built earlier.

This brief absorbs three former `docs/TODO.md` items ("Shift policy as data", "Measuring it",
"Tractor: launch gear on a steep soft grade"); their full content is below.

## Summary

The automatic shifts at fixed rpm thresholds whatever the pedal. It upshifts only at
`shift_up_rpm` (5900 of a 6800 redline on the cars), so a gently driven car revs close to redline
in every gear and then cruises in a low gear at high rpm. There is no kickdown, and the start gear
is fixed per spec whatever the load or slope.

## What happens

`src/vehicles/base/drivetrain.gd`:
- `auto_shift` (~line 325): up at `>= shift_up_rpm`, down at `<= shift_down_rpm`, one gear per
  tick, judged on **road speed** rather than wheel speed (so wheelspin cannot fake rpm).
- `governed_upshift` only acts on governed bodies near their limit.
- `_launching` holds `spec.launch_gear` through a pull-away while the start-up clutch closes, then
  while the body still gains speed below the downshift point (the tractor starts in D3).
- The bridge's manual mode takes the gear byte exactly and bypasses all of this
  (`InputRouter.set_manual_gearbox`); bridge automatic reads the byte as PRND.

## Symptom (computed, `sedan`)

Radius 0.36 m, final drive 3.9, ratios 4.5 / 2.903 / 1.975 / 1.431 / 1.109 / 0.925, upshift
5900, downshift 2200:
- 1->2 at 46 km/h, 2->3 at 71 km/h, whatever the pedal.
- A sedan eased up to 60 km/h stays in 2nd at ~5000 rpm indefinitely (5000 is between the two
  thresholds). A real car would be in 4th or 5th at ~1800-2200 rpm.
- That `rpm` is what the bus publishes, and `engine_load` (torque at rpm over peak) follows it.
  The same pattern holds on the trucks (upshift 2600 of 3200) and the semi (1690 of 2080).

Adjacent, not in scope unless the planner pulls it in: the fuel model reads only
`applied_throttle` (`VehicleTelemetry.fuel_step`), not rpm or power, so a better shift schedule
does not show in fuel burn.

## Part A — Shift policy as data

Load- and pedal-aware shift maps (upshift rpm rises with pedal), kickdown, minimum dwell,
skip-shifts, lugging detection and grade holding, as a per-spec policy the gearbox consults.
Presets per transmission type: converter automatic, AMT (today's `shift_cut_s`), powershift
(overlapped torque handover over ~0.3 s instead of an instant swap), and later CVT (a `docs/TODO.md`
item of its own). Respect the Rejected entry "splitting `Drivetrain` into gearbox and rpm": this is
a policy the gearbox reads, not a second gearbox.

## Part B — Start gear (tractor)

The D3 launch gear (`launch_gear`) costs the slip-limited mud climb (`measure_grade --
tractor-kenney mud mfwd diff tc`): 21 % against 26 % with a D1 launch (the clutch ramp alone costs
nothing). The hold keeps D3 while the tractor still creeps forward, so a bogged crawl never steps
down.
- Tried: requiring 0.5 m/s² to keep holding (17 %, worse; flat and tipper launches unchanged).
- Hypotheses: D3's weaker pull during the 0.8 s take-up lets the tractor roll back and lose what a
  D1 start keeps; or the step-down lands mid-trial and the bisection reads the transient.
- Likely real fix: a load- and grade-aware start gear (a real AMT or powershift picks it from mass
  and slope), which is part of the policy in Part A. Brief 05 may also change the picture: the D3
  start exists because first gear flashed the tyres to the limiter with no engine inertia.

## Part C — Measuring it

A per-tick launch/shift trace in `measure_vehicles` (gear, rpm, clutch, slip, axle lift) and gates
on what reads as wrong from the seat: shifts per standing start, minimum time in gear, limiter
hits during a launch, an upshift landing within a margin of the downshift point. The front-lift
check starts at the 60 km/h tracking pass, so the 40 km/h tractor is never checked for a launch
wheelie; the trace should cover it. Brief 05 needs the same trace to judge launches, so Part C is
built first: ahead of brief 05 or as its first phase (00_README.md § Recommended order).

## Constraints

- Gear selection stays on road speed.
- The RAMN gear byte caps the box at 6 drive gears (`Drivetrain.TOP_GEAR`). `docs/TODO.md` "Real
  gear counts for trucks and tractors" is a separate item (a contract change), but the trucks'
  1.5-1.76x steps make any schedule lurch, so the two interact.
- Full-pedal shift points are what the launch and top-speed figures are tuned on: the
  `docs/vehicles.md` accel table must not regress (`measure_vehicles -- doc=accel`).
- `governed_upshift` and the launch hold keep working; tests in `test_drivetrain`
  (`test_auto_shift_thresholds`, `test_process_auto_upshifts_at_speed`,
  `test_governed_upshift_*`, `test_a_held_vehicle_does_not_upshift_however_long_it_is_revved`,
  `test_the_auto_box_pulls_away_in_the_launch_gear_and_holds_it_until_engaged`).
- Tractor CLAUDE.md: "A pull-away is a powershift launch (`launch_engage_s`, `launch_gear` D3); D1
  is the bogged-start fallback, never detuned."

## Done

- At light pedal the cars upshift around 2000-2500 rpm and cruise on the flat in a high gear (a
  sedan at 90-100 km/h in 5th or 6th); at full pedal the shift points stay where the launches are
  tuned.
- Kickdown on a pedal stab; no hunting (an upshift lands above the downshift point with margin
  for the pedal map).
- The tractor picks its start gear from load and slope and climbs the mud grade at least as well
  as a D1 start, without flashing its tyres on the flat.
- The policy is pure functions under test; the shift trace and its gates exist and cover the
  tractor.

## Open decisions (user)

- Which presets per vehicle, and whether a sport/eco mode exists (a contract signal if the bridge
  should choose it).

## Related

Brief 05. `docs/TODO.md` items that build on this: CVT, "Diesel governor and hand throttle", "Real
gear counts for trucks and tractors".
