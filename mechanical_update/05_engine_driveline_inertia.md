# 05 — Engine inertia, coupling, creep

Shared context: `00_README.md`. Root cause 1 (engine as a torque source). Size: large; the three
parts below can be planned as separate phases or plans. Do brief 02 first.

This brief absorbs three former `docs/TODO.md` items ("Engine as a rotating mass", "One coupling
model per driveline type", "Creep and hill hold"); their full content is below.

## Summary

The drivetrain is a torque source behind a rev floor (`converter_free_rpm`), a time-ramped
start-up clutch (`launch_engage_s`) and an rpm-threshold auto-shift. The engine has no rotating
mass: its rpm is a smoothed copy of the speed the wheels impose, and its torque does not depend on
what the wheels do with it. A driven wheel spins up on its own inertia (1.2-6 kg·m²), whereas a
real one in first gear also drags the engine's flywheel, whose inertia appears at the wheel
multiplied by the gear ratio squared. Several tuning choices and one constant exist to tame the
resulting behaviour.

Rule 3 applies throughout: every new state (crank speed, clutch slip, converter ratio) is read out
of the sim, never a display fiction.

## What happens

`src/vehicles/base/drivetrain.gd`, `process`:
- Target rpm = `max(clamp(wheel-imposed rpm), converter_free_rpm(throttle))`; then
  `rpm = lerp(rpm, target, 1 - exp(-RPM_SMOOTH * dt))` with `RPM_SMOOTH = 8` (~line 391).
- The torque curve is sampled at that **smoothed** rpm, so after a shift the torque lags the gear
  by ~125 ms. A display filter sits in the physics path.
- The rev limiter judges the raw wheel-imposed rpm (`wheel_engine_rpm`), because the smoothed one
  never reaches redline (`src/vehicles/CLAUDE.md`).
- The converter is a rev model only: it multiplies no torque (COMPROMISE, `drivetrain.gd`
  § torque converter; `docs/vehicles.md` § Converter) and makes no drag at idle, so nothing creeps.
- The tractor's start-up clutch closes on a timer (`launch_engage_s`), not on slip.

`src/vehicles/base/wheel_drive.gd`: `drive_omega` is the mean driven-wheel spin (it sets rpm); the
axle torque splits equally per driven wheel; `Differential` couplings are solved implicitly through
each wheel's `spin_compliance`, which is equivalent to being inside the spin step (never a
post-tick torque, `src/vehicles/CLAUDE.md`).

Size of the missing term (**computed**, typical values the planner should source per class): a car
engine's crank and flywheel is ~0.15-0.25 kg·m². Through the `sedan`'s first gear (4.5 x 3.9 =
17.6:1) that is ~45-75 kg·m² at the axle, against 2 x 1.2 for the two driven wheels; in top gear
(3.6:1) ~2-3 kg·m². Heavy diesels carry ~1-3 kg·m² at the crank.

## Symptoms and the patches attributed to it

- **Truck ASR.** `TRUCK_BASE` comment in `tools/gen_kenney_vehicles.gd`: "without it a floored
  start spins the drive tyres into the limiter and cycles there (a twitching rpm needle)";
  `semi_spec.tres`: "cycles there at ~8 Hz". The cycle rate is set by wheel inertia. (Trucks do
  carry ASR in reality; the equipment can stay, the justification changes.)
- **Tractor powershift launch.** `TRACTOR_BASE`: `launch_engage_s` 0.8 and `launch_gear` 3
  because "First gear whole on the first tick is ~2x what the rear tyres hold, so a floored start
  flashed them to the limiter." The D3 start then costs mud gradeability (brief 06 Part B).
- **Limiter at launch.** `docs/vehicles.md` § Physics derivations says a car spinning its wheels
  in first holds gear 1 past redline inside the fuel cut, ~1 s lost to 100 km/h on the heavy
  wheel-spinning bodies. That paragraph is marked as not re-measured; the 2026-10-05 accel table
  shows 0.00 s on the limiter for every body, because traction control and ASR hold the slip.
  The symptom shows only with `tcs_off` (or on `race-future`, which has no TC): measure that way,
  and expect no launch gain on the shipped bodies.
- **Open differential.** With an ideal torque source, the gripping wheel keeps its full half-share
  while its partner spins; the textbook open-diff limit (twice the weak wheel's grip) appears only
  as rpm rises (down the falling end of the curve, steeply on the diesels whose curves reach 0 at
  redline) and into the limiter. With engine inertia, the spinning wheel must drag the engine up,
  which is what limits the pair in reality. `docs/vehicles.md` § Open-diff peel describes today's
  behaviour; `measure_rough` and `measure_grade` show it.
- **Per-wheel traction control on an open diff** is a documented COMPROMISE
  (`RayWheel._integrate_spin`, ~line 415): revisitable once the engine side is real.
- `RayWheel.FREE_SPIN_DECAY`: partly brief 02.
- Absent: a physical rev drop on a shift (today's drop is the ~125 ms lerp), rev-matching, a
  readable stall.

## Part A — Engine as a rotating mass

Integrate crank speed from a torque balance (net engine torque from brief 02, minus what the
coupling carries) instead of lerping toward a target rpm. In gear, the crank's inertia reflects
through the ratio squared onto the driven wheels, which is the real reason a low gear cannot flash
a tyre to the limiter: today a driven wheel spins up on its own inertia alone (`docs/vehicles.md`
§ Spin step). It gives natural rev drops on a shift, rev-matching and a readable stall. It must
enter the semi-implicit spin step as added compliance (`src/vehicles/CLAUDE.md` § The 60 Hz tick),
never as a post-tick correction; the driven wheels and the crank become one coupled system through
the gearbox and diffs, and the existing `spin_compliance` / `Differential.coupling_torque`
machinery is the natural place.

## Part B — One coupling model per driveline type

A friction clutch (torque capacity, slip, lock-up when the two sides meet) for manuals, AMTs and
powershifts; a torque converter (multiplication falling to 1.0 at the coupling point, lock-up
clutch) for automatics. The time-ramped clutch and the converter rev floor become two cases of it,
and clutch engagement ends on slip, not a timer. With a crank state, a standstill needs at least
this much: something has to slip between a turning engine and stopped wheels.

Re-check the brake > drive > handbrake hierarchy: converter multiplication is what the § Converter
COMPROMISE in `drivetrain.gd` gave up for it (brief 04 re-sizes brakes from hardware, which should
leave room for it).

## Part C — Creep and hill hold

Converter drag at idle (a car creeps on a released brake), and a hill-hold or brake-to-clutch rule
so a pull-away on a grade does not roll back while the coupling takes up. Distinct from brief 03's
creep (a held tyre sliding on a grade).

## Constraints

- Rejected entry (`src/vehicles/CLAUDE.md`): "Splitting `Drivetrain` into gearbox and rpm: the
  gearbox is load-bearing on every family. COMPROMISE: the wheel-less bodies run an engine model
  nothing observes." Boat, drone and train run `Drivetrain` with no wheels, and the plane has
  undriven wheels and no converter (`Drivetrain.has_converter`); they must keep working.
- Rejected entries that bind the open-diff work: "Open-diff friction (the open diff is an ideal
  1.0): bodies that should fight one-wheel peel declare an LSD", and "Fixing the floored 2WD
  tractor in mud: it is the open diff's peel … MFWD and the diff lock are the answer". Engine
  inertia may change the peel figures; do not add diff friction or tune toward the 2WD mud figure.
- `rpm` is a contract signal; the limiter rule ("judges `wheel_engine_rpm` (raw), never
  `Drivetrain.rpm`") changes once the published rpm is the integrated crank speed.
- `src/vehicles/CLAUDE.md`: "`converter_free_rpm` is a floor under the wheels, never a ceiling, and
  the converter multiplies no torque (COMPROMISE)"; Rejected: "Converter torque multiplication to
  speed launches: under 0.1 s on any body behind its reference". Part B adds multiplication for
  realism, not launch speed; that distinction is the user's call against the Rejected entry.
- Tractor CLAUDE.md: "A pull-away is a powershift launch (`launch_engage_s`, `launch_gear` D3); D1
  is the bogged-start fallback, never detuned." Part B replaces the timer with slip.
- Tests: `test_wheel_spin`; launch and converter tests in `test_drivetrain`
  (`test_the_launch_clutch_builds_drive_over_the_declared_time`,
  `test_the_auto_box_pulls_away_in_the_launch_gear_and_holds_it_until_engaged`,
  `test_a_held_wheel_revs_the_engine_to_stall_and_makes_more_torque_for_it`,
  `test_converter_free_rpm_runs_idle_to_stall_across_the_pedal`, …).
- Re-measure everything launch-shaped: `measure_vehicles -- doc=accel` and `doc=braking`,
  `measure_grade -- doc=grade`, `measure_rough -- doc=rough`, both CI gates. The per-tick shift
  trace in brief 06 Part C is the tool for judging launches: build it first (00_README.md § Recommended
  order).

## Done

- Crank speed is a state integrated from a torque balance; the published rpm is that state, with
  no display lerp in the torque path.
- In gear, the engine's inertia reflects onto the driven wheels: a floored low-gear start no
  longer flashes a tyre to the limiter in a few ticks, and a limiter hit cycles at an
  engine-plausible rate.
- Engine and wheels meet through a coupling (clutch or converter) whose slip is a state;
  engagement ends on slip.
- A converter automatic creeps on a released brake; a pull-away on a grade does not roll back.
- Truck ASR, the tractor launch clutch and launch gear, and `FREE_SPIN_DECAY` are each kept on
  their real-world merits or removed.
- `docs/vehicles.md` (§ Converter, § Limiter at launch, § Launches, § Open-diff peel) regenerated
  or rewritten.

## Open decisions (user)

- Which parts ship together.
- Inertia values per class; converter multiplication (against the Rejected entry).
- Whether the bridge's manual mode gets a clutch (and a stall), which may need a contract signal.

## Related

Brief 02 (net engine torque), 04 (hierarchy), 06 (shift policy, start gear, shift trace). The
`docs/TODO.md` items CVT, "Diesel governor and hand throttle" and "Real gear counts" build on this.
