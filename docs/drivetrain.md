# Drivetrain

Engine, coupling and gearbox on a wheel-driving body: the crank, the clutch or converter, creep
and the holds, the shift policy, the limiter and the governor. The identifiers: `docs/vehicles.md`
§ Drivetrain, wheels, drag — the identifiers; graded figures (crank inertia, converter and clutch,
the heavy vans' and Kenney trucks' drivetrains) and the `[n]` references: `docs/sources.md`; the
measured tables: `docs/vehicle_measurements.md`.

**Crank and coupling.** On every wheel-driving body the crank is a rotating mass
(`engine_inertia`, kg·m² at the crank: 0.20 on the cars, 0.18 on the sports pair, 0.06 on the
open-wheelers, 1.5 on the vans, trucks and tractor, 3.0 on the semis; sourced per class in
`docs/sources.md`). It meets the driven wheels through one
coupling (`coupling`: a converter on the cars, vans and Kenney trucks, a friction clutch on the
open-wheelers, the semis' AMT and the tractor's powershift), rated `clutch_reserve` times the
curve's peak (1.5 on cars, 2.0 elsewhere) and solved as one more output of the wheels' spin solve
(`Drivetrain.couple`). The transmission controller (`coupling_step`):
- opens a clutch with the key off, in N or P, under ABS on a driven wheel, on a direction change
  and with the pedal up once the wheel side is under idle; a converter opens only with the key
  off, in N or P and on a direction change (at a stop it slips: creep, § Converter);
- slips a clutch on a pull-away, landing the crank on `launch_target_rpm` (the line from idle to
  the stall speed, or 300 rpm over idle on the semis), and every coupling on a shift (on a
  converter body, the gearbox's own clutch). An upshift's inertia phase brings the crank down to
  the new gear at an even rate over `shift_handover_s` (`Drivetrain.handover_rate`), never past
  the rating: a clutch carries the engine's delivered torque plus `J Δω / t`, and a converter
  automatic's TCU fuels the engine down so its clutch passes the driver's demand (§ The shift
  policy); a downshift's crank is blipped up to the wheels with the clutch open first;
- locks it the tick it carries less than its capacity. A clutch stays locked until a shift; a
  converter's lock-up lets go under the foot brake (`Drivetrain.braking`, as an automatic's TCU
  does, so the brakes never slow the crank, where a clutch body keeps its clutch closed for
  engine braking), under ABS, under `lockup_gear` and when the wheel side falls under
  `converter_free_rpm` at the raw pedal (§ The pedal map's COMPROMISE).

Locked, the crank reflects `J G²` onto the driven wheels: +41 % on the `sedan`'s gear-1 mass
factor, +28 % on `garbage-truck`'s (`docs/sources.md`). A lifted driven pair spins up at
`G eta T / (n I_w + eta J G²)`, not `G eta T / (n I_w)`. The crank's own step is semi-implicit in
its curve's slope (`crank_compliance`): `race`'s 6600-6800 rpm droop gains ~3 a tick explicitly.
A driven PTO is a constant torque in the same step (`Drivetrain.accessory_torque`, its power at
the PTO's rated engine speed: `docs/tractor.md` § Draft, hitch, linkage), which the idle floor, the
rev-match blip, the limiter and drag-torque control fuel as load. The key off runs it down to 0 on the motoring law's friction (the `sedan`'s from idle in about one
and a half seconds); Ignition puts it back on idle.

**The pedal map.** On a wheel-driving crank the pedal reaches the engine law through `PedalMap.fuel`
(`VehicleSpec.pedal_map`): the controller's fuel and the shift policy's "drive at this pedal" read
it, while every shift point stays keyed on the pedal itself. Full pedal is exactly full fuel on
every map (on ALL_SPEED up to its high idle, the redline), so no floored figure depends on it.
COMPROMISE: the converter's lock-up line reads the raw pedal as the fuel (`Drivetrain.lockup_holds`).
On the mapped fuel a third of the pedal would put the line near the stall speed, and the `sedan`'s
pedal-0.3 pull would run D3-D5 on the converter, 400-500 rpm of slip. No lock-up schedule is
sourced.
- **PETROL** (the car family): the pedal is a torque request, as a torque-structured engine
  management reads it. The table is EPA's dynamometer map of a 2016 Honda L15B7 [88, Fig. 2]: brake
  torque against pedal and rpm, its rpm axis taken over rated speed (6000 rpm there [90], the body's
  own power peak here). The request runs near-level in N·m across rpm, and full load clips it at low
  rpm: a third of the pedal asks about two thirds of the peak at 2500-3500 rpm and is wide open
  under 1500. Each row is solved for the fuel that delivers it on `crank_torque`'s law, so under
  full load the crank makes the measured torque. The first 1 % of pedal already nets the motoring
  out (the figure's "discrete transition"). A free crank in N nets the request itself: the 1 % and
  5 % rows dip under zero toward the figure's top column, so a light touch settles there, and past
  it (held flat) a tenth of the pedal still nets positive torque, so it runs a free crank to the
  limiter. The measure tools' speed holds (the PI pedals, `measure_rough`'s crawl) command fuel
  through the map's inverse (`PedalMap.pedal_for`): on the raw pedal that first 1 % limit-cycles
  them.
- **LINEAR** (the vans, the Kenney trucks, the semis): the fuel is the pedal. A road diesel's
  min-max governor leaves the injection pump's control rod to the pedal between idle and maximum
  speed [89]; no electronic road-diesel map was found.
- **ALL_SPEED** (the tractor): an all-speed governor [89]. The demand, the higher of the pedal and
  the hand throttle (`PedalMap.demand`, contract `hand_throttle`), sets an engine speed from idle
  to the high idle (the redline), and the fuel holds it on a droop line: full fuel at
  `setting / (1 + droop)`, no net torque at the setting, the line run on past it to the motoring
  law (`PedalMap.governor_fuel`). `governor_droop` 0.07 is Deere's 6R (rated 2100, fast idle 2250
  [106]). A free crank settles on its setting; a load holds it on the line. While the line governs,
  its slope is the crank's stiffness (`PedalMap.governor_stiffness`), so the step stays
  semi-implicit at any droop (explicit, `k dt / J` is ~0.5 on the tractor at 7 %, ~3.7 at 1 %).
  On a free crank (N or P) a tick's fuel is capped at what lands it on the setting
  (`Drivetrain.fuel_to_land`): full fuel moves it ~90 rpm a tick, past an isochronous line ~1 rpm
  wide, which read at the tick's start it would jump both ways and cycle on. A road truck's PTO mode
  runs the same law at its set speed, isochronously (`docs/truck.md` § The refuse body: a second network across a gateway).
  COMPROMISE: at the top setting the line is the curve's own 2200-2600 tail, an 18 % droop; the
  sourced 7 % puts the high idle near 2350 and takes the top speed down to D16's road speed there
  (`docs/vehicles.md` § Rejected designs, "torque-curve tails"). Full demand is full fuel to the
  redline, so the floored figures (trace, roll-back, gradeability) do not depend on the governor.
  Three consequences on the gearbox:
  - the demand caps the engine at its setting, so a part demand's upshift point is held two droops
    under it (`ShiftPolicy.governed_up_rpm`, `GOVERNED_UPSHIFT_DROOP`, an estimate): on the map's
    own point the tractor at demand 0.5 (setting 1700) would never leave its start gear;
  - the downshift points stay the map's (`ShiftPolicy.down_rpm`), as a box that shifts on engine
    speed keeps them: a setting under the landing floor (the tractor: 1.1 x 1000 x its 1.10 step,
    ~1214 rpm, a demand under ~0.23) holds its gear, and one under the coast line (1000 rpm, a demand
    under ~0.11) steps down to a crawl in D1;
  - the hand throttle never pulls away alone: the start-up ramp and a clutch's opening at rest read
    the pedal (`Drivetrain.hand_throttle`), as a shuttle's release. Moving, a lifted pedal leaves
    the tractor driving in gear at the governed speed.

**Motoring and friction.** Off fuel the crank turns against `motoring_torque`: its friction,
`engine_friction_frac` of the curve's peak at and below idle, rising linearly to
`engine_brake_frac` at redline. The friction is what brings a blipped free crank back to idle and
stops a key-off one. Without it the law reaches 0 at idle, and a lifted crank falls toward idle ever
more slowly. Per class, at idle / at redline, as a share of peak:
- **Medium diesel** (Kenney trucks and vans) and **tractor:** 0.10 / 0.15 and 0.20. The 0.10 is
  sourced. The Volvo Penta TD640VE (5.48 L) publishes its friction power: 17, 20, 23 and 26 kW at
  1800, 2000, 2200 and 2400 rpm. That is 90-104 N·m, FMEP 2.1-2.4 bar, 14-16 % of its 658 N·m. Run
  linearly down to idle, it gives ~66 N·m, 0.10. At redline it gives ~0.16 to 0.19, against the
  shipped 0.15 (trucks) and 0.20 (tractor).
- **Heavy diesel** (the semis): 0.05 / 0.15. The 0.05 is an estimate. The Volvo Penta TAD1641GE
  (16.1 L) publishes 36 / 53 kW at 1500 / 1800 rpm: 229 / 281 N·m, FMEP 1.8 / 2.2 bar. Scaled to
  12 L and to idle (~1.2 bar), that is ~115 N·m. Scaled the same way, the redline figure is about
  0.10, against the shipped 0.15. **Open:** the redline anchor is kept (the user's call).
- **Car petrol:** 0.07 / 0.25, sourced. EPA's Malibu map measures the 2.5 L's closed-throttle
  motoring (friction plus pumping) at 0.069 of its peak at 1000 rpm rising to 0.250 at 6000 [91].
  The linear law, fitted by least squares over 1000-6000 rpm on `CAR_BASE`'s idle and redline,
  lands within 0.025 of peak at every point: over by up to 0.023 mid-range, under by 0.024 at 6000.

On the `sedan` a blip falls steadily to idle, and the key off stops an idling crank within about one
and a half seconds. At idle the controller burns the fuel that nets the friction out (~12 % on the
`sedan`), so `engine_load` reads that fuel there.

**Fuel.** The burn is read off the crank (`VehicleTelemetry.fuel_rate_lph`, a Willans line): the
delivered fuel adds `f * (curve - motoring)` over the motoring law, and that torque's power over an
indicated efficiency per fuel (`VehicleSpec.fuel_type`: PETROL 0.41, DIESEL 0.45) is the fuel's
chemical power. A cut burns nothing. At idle the controller's fuel nets the friction and any creep
load, so idle burns their power, and part load costs more per kWh on its own. Read against its
sources (`docs/sources.md` § Fuel): the `sedan` idles at 0.34 L/h and bottoms at 241 g/kWh, the
`semi` at 1.62 L/h and 201 g/kWh. At one road speed the `sedan` held in D6 burns about half what it
does in D3 (`-- sedan 90 cruise gear=6`, `gear=3`). Coolant chases the burn's share of its rated
figure; battery keeps `applied_throttle`; the rigid crank (boat, plane) keeps a throttle model.
COMPROMISE: `fuel` drains a game-scale tank, `FUEL_TANK_FULL_LOAD_S` at the rated burn.

**Converter.** A converter body (`coupling` CONVERTER: the cars, the vans, `garbage-truck` and
`firetruck`) slips through `TorqueConverter`'s law, solved with both sides' end-of-tick speeds
inside the wheels' solve (`TorqueConverter.solve`):
- **Capacity.** The impeller takes `coef * omega_p^2 * shape(SR)`, SR the speed ratio. The shape
  is the MathWorks Powertrain Blockset's default capacity factor (K 12.3 at stall, 14.6 at 0.8,
  16.3 at 0.87, 22.1 at 0.94, 50 at 0.97), so it falls to nothing at one speed. `coef` puts full
  fuel against a held turbine on the stall speed (`Drivetrain.stall_rpm`, STALL_RPM_FRAC 0.25 of
  idle to redline: 2375 rpm on the cars, 1250 on the Kenney trucks, inside a car's typical
  1800-2800). At part pedal the free rev follows the N² load at the pedal's fuel, never under idle
  (`converter_free_rpm` at a fuel; the lock-up's line reads it at the raw pedal, § The pedal map).
  In overrun the turbine pumps at OVERRUN_CAPACITY 0.5 of drive, an estimate: no coast figure
  was found.
- **Ratio.** The turbine passes `converter_stall_ratio` times the impeller's torque at stall,
  falling to 1.0 at the coupling point (SR 0.9). COMPROMISE: it ships 1.0, a fluid coupling. A
  real converter makes about 2.0 at stall (2.5 on the 1990s four-speeds, 1.98-2.20 on Allison
  3000s), and at 2.0 five more bodies fail the foot brake's static stall hold
  (`BrakeSizing.stall_hold_margin` reads `Drivetrain.stall_axle_torque`) and `police` sits on its
  edge, 1.00: `sedan-sports` 0.94, `hatchback-sports` 0.77, `van` 0.95, `pickup` 0.85, `pickup-flat` 0.84
  (the Kenney trucks hold, 1.40 / 4.31). It waits on a review of their brake classes against
  sourced hardware. The torque ratio is read at the tick's start speed ratio, explicit where the
  capacity is implicit: it varies slowly.
- **Lock-up.** The lock-up clutch (rated `clutch_rating`) closes in parallel once the two sides
  turn within the coupling point of each other, from `lockup_gear`: 1 on the cars and the heavy
  vans (a 6-speed opens its converter only for the launch), 2 on the Allison-class trucks (lock-up
  from 2nd range). So top speeds and governed settles do not move (§ Engine braking): every cruise is
  locked.
- **A shift** slips the gearbox's own clutch (the handover, § The shift policy), never the
  converter: released, the converter would drag the `sedan`'s crank down from the redline with
  a torque several times the rating on the first tick.

Drive reaches the wheels from the first tick of a pull-away (the trace's `H` column and `Tc`). At ratio 1.0 the converter passes no more than the engine makes, so the launches move little (`docs/vehicle_measurements.md` § Launches).

**Creep.** In gear the converter loads the idling crank, `coef * omega_idle^2`: small on the
`sedan`, larger on the heavy vans, largest on the Kenney trucks. The idle controller fuels it, so the
crank holds ~3-4 rpm under idle (~1 on the trucks), and `engine_load` reads 9-10 %: that fuel,
against the converter's load and the engine's friction. Released in D1 with no pedal
(`measure_grade -- all creep`; asphalt):

| Body | Steepest grade held at idle |
| --- | --- |
| `sedan`, `taxi`, `suv`, `suv-luxury`, `police` | 7.0-9.4 % |
| `sedan-sports`, `hatchback-sports` | 11.1-11.9 % |
| `van`, `pickup`, `pickup-flat` | 6.1-7.0 % |
| `delivery`, `delivery-flat`, `ambulance` | 7.4-9.0 % |
| `garbage-truck`, `firetruck` | 10.7-11.5 % |

Every body creeps on the flat at a walking pace, within a few tenths of a km/h of the others.

The Kenney trucks' creep is ~1.3x a car's in g (`(idle / stall)²` 0.31 against the cars' 0.14,
through a 14:1 first); a 30 % pedal out-holds it (`docs/vehicle_measurements.md` § Braking). The heavy vans' 15.6:1 first and 0.23
share creep as a car does. A held wheel's brake holds the patch against its drive with its sign (`RayWheel.held_force_range`), so creep up a grade helps a handbrake hold.
What moves with the converter:
- `engine_load` samples the curve at `Drivetrain.rpm`, so a held truck at full pedal reads 83 %
  where it read 50 % at idle;
- `pto_rpm` follows the rev, being a stub shaft off the crank;
- `fuel_rate` reads the creep load: the idle fuel that nets it out burns its power (§ Fuel).

**Hill hold.** Creep holds the cars and the heavy vans on 6-12 % and the Kenney trucks on 11 %. Past that, a released
brake rolls the body back while the coupling takes up, and a clutch body (nothing creeps there)
rolls back on any grade. Three holds stop it:
- **Hill-start assist** (`hill_hold` ASSIST, on every ABS body). The foot brake's last application
  at rest in a drive gear stays on after the release. It lets go when the drive the coupling passed
  last tick meets gravity's pull along the heading (`HillHold.drive_holds`), or after `hill_hold_s`,
  set per class (Honda on the cars, Volvo VN on the vans, trucks and semis).
  - The grade is read off the wheels' contact plane. The pull is the rig's: a trailer's mass is
    added (`WheelDrive.towed_kg`), and the trailer is sent the held pedal (`foot_pedal`).
  - Rolling resistance is left out, so it lets go a little late. On the flat or downhill it lets
    go on the first tick.
  - On the semis' AMT it is the brake-to-clutch rule: held until the slipping clutch carries the
    grade.
- **The tractor's powershift hill hold** (STANDSTILL, Valtra's HillHold). At rest in gear with the
  drive pedal up, it holds on the foot brake, MFWD engaged, with no timeout. It lets go once the
  pedal is down and the clutch's ramp carries the grade. COMPROMISE (at
  `GroundDriveSpec.hill_hold`): the real one holds in the transmission. The brake is the hold
  solved with the crank's coupling, where a lock of the gearbox output is solved before it. The
  CVT tractor has none: its active standstill is that transmission hold (§ The CVT below).
- **Auto hold** (`InputRouter.auto_hold`, keys and touch only). Stopped in D or R with no throttle,
  the whole foot brake stays on until the throttle asks to move; hill-start assist takes the
  handover. A gamepad driver and the bridge get the real creep.

Released after a `SETTLE_S` foot-brake hold and floored `ROLL_DELAY_S` later, on 10 % and 25 %
(`measure_grade -- <variant> rollback`, with and without `nohold`, prints rollback, release time
and time to move forward; asphalt, the tractor on mud with MFWD from its D1 launch). With the
hold, the cars and Kenney trucks roll back a patch spring's worth on
both grades, against hundreds of millimetres on 25 % without it, and the hold lets go inside a
second. The `garbage-truck` is never held on 10 %: its creep carries the grade. The laden semis roll
back far on 25 % with or without the hold, and with `nohold` never pull away. The tractor on mud
(MFWD) rolls back a patch spring's worth on 10 %; with the farm tipper it pulls away much later.

What remains with the hold is the static patch spring (`docs/vehicles.md` § Holding at rest). On 25 % the semis' hold
lets go once the clutch's drive meets the rig's pull, but the drive tyres cannot carry it
(`docs/vehicle_measurements.md` § Gradeability): the hold reads torque, never grip. On 10 % the semis reach 0.1 m a little later
with the hold, because the brakes wait for the clutch to carry the grade. The tipper rig's slow
start is its own pull-away on mud: slow from D1 or D2, quicker from D3.

**The shift policy** (`ShiftPolicy`). Each transmission type declares a part-pedal map:
a light pair at and under 20 % pedal, blending linearly to the full-pedal pair at pedal 1, where the
launches are tuned. Each upshift is raised until it lands 1.1x over the downshift point at the same
pedal, so no gearing hunts (`test_vehicle_catalog`). The full pair is unchanged on every body.

| Type (bodies) | Light up / coast down (rpm) | Kickdown | Dwell | Skip | Basis |
| --- | --- | --- | --- | --- | --- |
| Converter automatic (`CAR_BASE`) | 1800 / 1150 | past 0.8 | `shift_dwell_s` | no | the Malibu map below [34]; dwell: EPA ALPHA's six-speed hold [34] |
| ... heavy vans (`VAN_BASE`) | 1750 / 1000 | past 0.8 | `shift_dwell_s` | no | the same structure at the diesel's band (plateau from 1750): estimate |
| ... Kenney trucks (`TRUCK_BASE`) | 1600 / 900 | past 0.8 | `shift_dwell_s` | no | the same, under the 1800 peak: estimate |
| AMT (both semis) | 1555 / 700 | past 0.95 | `shift_dwell_s` | yes | the D13's 1250-1500 rpm cruise band [38], every light upshift landing at its bottom; I-Shift's kickdown switch past full travel [36, 37] |
| Powershift (`TRACTOR_BASE`) | 1500 / 1000 (the full pair's) | none | `shift_dwell_s` | yes | AutoDrive Eco's 1500 [39]; the sourced 1200 downshift [40] sits over the full pair's 1000 |
| Sequential (`race`, `race-future`) | the full pair | none | none | no | full-pedal shifting kept (the user's call) |

- **The Malibu map** [34, Fig. 11]: a 2013 Malibu's 6T40 (2.5 L I4), upshifts driven on level road
  at fixed pedal, read off the figure (±2-3 km/h); crank rpm computed through the 6T40's ratios
  [35]. At ~20 % pedal it upshifts at 1720-1910 rpm and lands 1130-1310; at ~40 %, 2080-3480; its
  coast downshifts sit at 1120-1190 rpm (3rd to 6th). Each light upshift lands 1.07-1.12x over the
  next coast downshift, the landing floor's 1.1. Its kickdown lines climb at 59-100 % pedal.
- **Landings, computed:** the floor raises the light D1>D2 to 1961 rpm on the cars (lands 1265),
  1958 on the vans (1100) and 1857 on the Kenney trucks (990). On the semis' 1.21-1.24 steps the
  light 1555 lands every upshift at 1250-1281 rpm, the bottom of the D13's band; a held part pedal
  lands them at 1263-1311 (`-- semi 120 cruise`). The tractor's 1.10 steps land its light 1500 at
  ~1360.
- **Skip-shifts** (`skip_shifts`: the semis' AMT, the tractor's powershift). A lift ripples to the
  gear a sequential box reaches in one shift (`ShiftPolicy.upshift_target`), and a lugged crank's
  coast-line downshift takes the highest lower gear landing over the line, in one shift
  (`ShiftPolicy.forced_downshift`: the plough's floored start, D7>D1). A floored, forced
  upshift passes the gears the rig would not hold `shift_dwell_s` in at full pedal, on the road load
  and its mass (`ShiftPolicy.forced_upshift`), as I-Shift and AutoDrive skip; it never lands under
  1.1x `shift_down_rpm` or in a gear that cannot hold the road load, and with no estimate it steps
  one gear. The hold (`ShiftPolicy.time_to_upshift`) is the box's picture of the rig: never more
  drive than the driven tyres' static grip puts down (`Drivetrain.drive_grip_n`, read off their
  loads at rest, the coupled load and the surface included), plus the shift's own dead time on an
  AMT, its cut and half its torque ramp (`ShiftPolicy.shift_dead_s`, an estimate). Floored
  (`-- <variant> 60 trace`): the bobtail `semi` from its D6 start D6>D8, then singly; with the 24 t
  box from D3, D3>D5, then singly; the bobtail tractor D7>D13>D16, with the tipper from D6,
  D6>D10>D13>D15>D16. Every gear holds past the trace's dwell floor and every landing sits at 1.22x
  its downshift point or more.
- **Kickdown:** one shift to the lowest gear under `ShiftPolicy.kickdown_ceiling_rpm` that holds
  `KICKDOWN_HOLD_S` at full pedal before its forced upshift (`ShiftPolicy.time_to_upshift` on the
  road load, the rig's mass and grip, and the AMT's dead time): EPA ALPHA's default ceiling, 85 % of
  the gear's maximum speed (the redline), and its minimum time after a downshift [34]. The ceiling
  sits under `shift_up_rpm`; the hold keeps a kickdown off its forced upshift, so a light body lands
  lower than a heavy one from the same rpm. With no road-load estimate to judge the hold, the landing
  stays 1.1x under `shift_up_rpm` instead. None on the tractor: no powershift kickdown is sourced.

*The shift's handover.* During an upshift's inertia phase the oncoming clutch's capacity sets the
output torque, a little over the driver's demanded torque, the surplus taking out the crank's
inertia [42]; the phase lasts ~0.15-0.5 s on a converter automatic [41], and its TCU holds the
engine's torque reduced through it [44]. The controller lands the crank on the new gear at an even
rate over `shift_handover_s` (`Drivetrain.handover_rate`), never past the rating:
- **Seamless boxes** (no `shift_cut_s`): the engine is fuelled down so the clutch passes the
  driver's demand, the engine's torque at the pedal's fuel (`Drivetrain.handover_fuel`), and the
  crank's inertia goes into the reduction. A lift upshift, with nothing to reduce, takes the surplus
  on the clutch.
  - **Converter automatic** (cars, vans, Kenney trucks; `shift_handover_s` mid of [41], an
    estimate): an Allison-class or car automatic shifts clutch to clutch, with no torque
    interruption.
  - **Powershift** (the tractor; `shift_handover_s` at [43]'s overlap baseline). COMPROMISE: the
    reduction is the road boxes' [44, 97]; the tractor source found holds or raises the engine's
    torque through the shift instead [98]. The reduction also covers the pull-away's close onto
    turning wheels. Without it, the crank's `J Δω / t` reaches the wheels: a floored skip D7>D13 hands
    over several times the torque it held before and drops it on the lock tick, and the nose rings
    16 points past the `front axle` gate (`docs/handling.md` § Pitch).
- **AMT** (the semis; `shift_handover_s` within its `shift_cut_s`, an estimate): after its cut, the
  clutch carries the delivered torque plus `J Δω / t`. The cut is its interruption; its fuel returns
  over `shift_torque_ramp_s` (an estimate; a step rings).
- **Sequential** (the race pair): its ignition cut (`shift_cut_s`), and the clutch closes at its rating (on
  J 0.06 the drop spans ~2 ticks).

Peak torque at the crank through each floored upshift (`measure_vehicles -- <variant> 60 trace`,
the `each shift` line):

| Body | Peak crank torque | Slip |
| --- | --- | --- |
| `sedan` | the curve's peak | the handover |
| `delivery`, `ambulance` | the curve's peak | the handover |
| `garbage-truck` | the curve near its peak | the handover |
| `semi` + 24 t | over the curve's peak, the closing tick with its fuel back | the cut |
| `tractor-kenney` | near the curve's peak | inside the handover |

- The trace's dwell gate reads `race` D2 under `shift_dwell_s`:
  the policy never holds a full-pedal upshift (it is where the launches are tuned), so on a
  launch the dwell is the gearing's, a report, not a shift-policy fault.

*Cruise*, held by the PI pedal from a standstill: `docs/vehicle_measurements.md` § Cruise.

*At a held part pedal* the pedal map sets the drive (§ The pedal map) and the shift map the gears:
the `doc=accel` benchmark at a part pedal (`-- <variant> 90 pedal=0.3`). On the `sedan` the box
upshifts at the pedal's light points, the lock-up closes after each shift's handover, and the
locked crank carries the map's request less its own `J α`. The diesels keep the linear pedal, so
`delivery`, `garbage-truck` and `semi` + 24 t at pedal 0.3 still take several times their floored
times.

*Kickdown and the keyboard* (`cruise kickdown pulse`): a stab kicks the cars and the light vans
down two or three gears at every cruise speed (`van` and `pickup` four at their second), the
`ambulance` and `delivery` one or two, slower to gain speed. The `garbage-truck` and `firetruck`
kick one gear. The semi + 24 t kicks one gear at its lowest and highest cruise speeds (D7>D6,
D11>D10; each holds once the hold counts the cut and the rig's mass) and none at the middle one,
whose next gear down lands on its upshift; `semi-conventional` at its top speed kicks D12>D11. A key
held on and off (the pulse) kicks down on each press and lifts up on each release, paced by
`shift_dwell_s`: 26-40 shifts a minute on the cars, the vans, the Kenney trucks and the semis at
their highest cruise speed (hunting gate PASS on every body, no two opposite shifts inside the
dwell), and the `sedan` swings a few km/h around its set speed. The tractor does not cycle.

*The load*. The gearbox keeps a road-load estimate (`Drivetrain.road_load`): the
torque the coupling passed less the rig's mass (its live mass plus what it tows, the sim's own)
times its measured acceleration, filtered over `LOAD_FILTER_S` (`shift_policy.gd`), seeded at rest from the load standing on the
grade (the grade's pull plus the tyres' and the soil's rolling resistance), and held under the foot
brake, which would read as load. It reads as a grade once it passes the flat-road load the body
declares (`drag_area`, `rolling_resistance`) by a 2 % grade's pull on the rig (`ShiftPolicy.on_grade`,
a TCU's grade logic; the 2 % is an estimate). The pedal's map then reads it:
- **On a grade** no map upshift lands in a gear that cannot hold the speed at this pedal with
  EPA's 1.1 torque reserve [34] (`ShiftPolicy.holds_grade`); a skip steps back to the tallest gear
  that holds. The forced upshift at `shift_up_rpm` is never held, so no full-pedal figure moves
  (`doc=accel` unchanged).
- **Lugging:** under the pedal's downshift point with less drive than the load, the box steps down
  through the dwell. The landing floor keeps the map from upshifting straight back, and on a grade
  the gear left cannot hold that load.
- **A braked descent** (the load pulling the body along, the foot brake on): no map upshift, and a
  step down for engine braking where the lower gear lands under its own lifted upshift point (so
  releasing the brake never upshifts straight back). A converter's lock-up still lets go under the
  brake.
- **Off a grade** the map is unchanged: the `doc=cruise` table holds.
- **The start gear** (`ShiftPolicy.start_gear`, up to `start_gear_max`: the semis' 6, the
  tractor's 7): the highest gear whose launch drive beats the standing load twice at the driver's
  pedal (the grade's floor) and whose floored launch locks the coupling within `START_SLIP_S`
  on the rig's mass and the driven tyres' static grip (`ShiftPolicy.launch_slip_s`, half a
  powershift's engagement ramp included). That is Eaton's acceleration slip time [99]: an AMT picks
  its start gear from gross weight and grade, the highest whose clutch slips under a reference
  (their example is `START_SLIP_S`'s). On the flat the bobtail `semi` starts in D6 and with the 24 t box in D3
  (D1 on 8 %); the tractor in D7 bare and D6 with the farm tipper (D4 on 10 %). The gear is held
  through the launch until the coupling locks (`docs/tractor.md` § Tractor, implement &
  ISOBUS), and the lock starts the dwell's clock: the drive tyres slipping at their peak lock a
  laden launch under the pedal's downshift point while it gains speed. A launch that has not moved steps down
  by ratio, not index (`ShiftPolicy.start_step_down`, `START_STEP` 1.3), so each step covers the
  same ratio whatever the box's own step.

Climbs from rest in automatic D at a held pedal (`measure_grade -- <variant> climb grade=<%>
pedal=<p>`, a fixed run or the ramp's top):

| Climb | Result |
| --- | --- |
| `semi` + 24 t, 8 %, pedal 0.6 | D1 start, to D4 a gear at a time, then holds D4: 188 m |
| `garbage-truck`, 15 %, 0.6 / 0.7 | 0.6 rolls back once the hold lets go: the converter passes less than the grade asks at that fuel; 0.7 holds D1 up the run: 203 m |
| `tractor-kenney` + tipper, 8 %, 0.6 | D4 start (the box's), then a gear at a time to D14 on the governor's setting, each upshift two droops under it: 192 m |
| `sedan`, 10 %, 0.5 | up to D5 by the top (half pedal is near full fuel on the petrol map); 336 m |
| `semi` + 24 t, 4 %, 0.6 | D2 start, to D7 a gear at a time: 271 m |

Floored climbs (`garbage-truck` 8 / 15 %, `semi` 8 %) keep every shift; the floored `semi` on 8 %
steps D1 to D7 a gear at a time, each gear holding the dwell on the drive axle's grip.

**The CVT.** `tractor-cvt` runs a power-split CVT (`spec.cvt_range_tops`, `Drivetrain.is_cvt`;
the tour, sources and measured figures: `docs/tractor.md` § The CVT tractor). Its ratio is
drivetrain state, moved by its controller before the spin solve and solved in it as the gear, at
the overall speed ratio rather than its inverse, so a ratio of 0 holds: active standstill, the park
pawl's path at the hydrostatic relief (`Drivetrain.standstill_hold`). The engine runs the all-speed
governor's law (§ The pedal map), its demand managed in pedal mode (`cvt_managed_setting`); the
pedal commands ground speed, held until the crank falls to its limit-load speed. No
`ShiftPolicy`, no launch clutch, no shift: the gear byte publishes the mechanical range, which
changes synchronously, and a CVT governs road speed through its ratio, not the fuel.

**Limiter at launch.** The limiter judges the crank, and auto-shift road speed. With the crank's
inertia reflected onto a spinning pair and the curve's droop below the redline, no floored launch
reaches the limiter, even with traction control off (`notc`: 0 ticks on `sedan-sports`, `race`,
`garbage-truck`, `semi` and the tractor's D1 launch). `race notc` spins its rears from the lock up
to 6784 rpm over 12 ticks. The equipment beside the limiter stands on its own merit:
- The semis' ASR keeps the drive tyres near the peak while the AMT's clutch slips in a held D1
  (`trace gear=1`); without it the clutch locks at once and the tyres spin past the slip peak. From
  the laden D3 start the drive is at the grip, and on dry asphalt the ASR does not act (`notc`
  reaches the `doc=accel` benchmark in the same time).
- The Kenney trucks' ASR does not act on dry asphalt, where gear 1 at converter stall pushes
  less than the rear tyres' grip (`garbage-truck` `notc` reaches the benchmark in the same time). It
  is kept as the EBS equipment it is, for low grip.
- The tractor's launch ramp (`launch_engage_s`) is the powershift's modulation: with the
  whole rating on the first tick its rears flash to high slip and the front axle unloads far more
  than with the ramp. It pulls away in D1 (`docs/tractor.md` § Tractor,
  implement & ISOBUS).

**Engine braking under a fuel cut.** The governor fades `f` across `GOVERNOR_BAND`, and the
unfuelled share motors, so a governed body settles where `f * curve + (1 - f) * motoring` meets
the road load, a few km/h under the limit. A top speed reached at full fuel (`f = 1`, set by drag
or by the curve running out at redline) is the curve's alone. Measured
(`measure_vehicles -- <variant> 120`, `top (settled)`; the semis carry the catalog's first trailer):

| Body (limit, km/h) | Settles |
| --- | --- |
| `van` / `pickup` / `pickup-flat` (180) | just under the limit |
| `garbage-truck` (85) | just under the limit |
| `semi` / `semi-conventional` (90 / 105) | under the limit |
| `tractor-kenney` (40) | under the limit |
| `ambulance` (150) | under the limit, in D6 |
| `firetruck` (110) | just under the limit |

A wheel spinning up drags the crank with it, so a peeling open pair is held by the engine's
inertia as well as its grip: the floored 2WD tractor's asphalt climb (`docs/vehicle_measurements.md` § Gradeability) is ~9 points
over what the wheels' inertia alone holds.
