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
  `converter_free_rpm`.

Locked, the crank reflects `J G²` onto the driven wheels: +41 % on the `sedan`'s gear-1 mass
factor, +28 % on `garbage-truck`'s (`docs/sources.md`). A lifted driven pair spins up at
`G eta T / (n I_w + eta J G²)`, not `G eta T / (n I_w)`. The crank's own step is semi-implicit in
its curve's slope (`crank_compliance`): `race`'s 6600-6800 rpm droop gains ~3 a tick explicitly.
The key off runs it down to 0 on the motoring law's friction, in about a second from idle;
Ignition puts it back on idle.

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
- **Car petrol:** 0.10 / 0.12. The 0.10 is an estimate : a
  1.6-2.0 L petrol's friction (~1 bar FMEP at low speed) plus closed-throttle pumping. No primary
  figure was found. Secondary FMEP figures put the redline motoring at about 0.3-0.4. **Open:** the
  shipped 0.12 stays until a primary figure is found (the user's call).

On the `sedan` a blip falls steadily to idle, and the key off stops an idling crank within about a
second. At idle the controller burns the fuel that nets the friction out (~16 % on the
`sedan`), so `engine_load` reads that fuel there.

**Converter.** A converter body (`coupling` CONVERTER: the cars, the vans, `garbage-truck` and
`firetruck`) slips through `TorqueConverter`'s law, solved with both sides' end-of-tick speeds
inside the wheels' solve (`TorqueConverter.solve`):
- **Capacity.** The impeller takes `coef * omega_p^2 * shape(SR)`, SR the speed ratio. The shape
  is the MathWorks Powertrain Blockset's default capacity factor (K 12.3 at stall, 14.6 at 0.8,
  16.3 at 0.87, 22.1 at 0.94, 50 at 0.97), so it falls to nothing at one speed. `coef` puts full
  fuel against a held turbine on the stall speed (`Drivetrain.stall_rpm`, STALL_RPM_FRAC 0.25 of
  idle to redline: 2375 rpm on the cars, 1250 on the Kenney trucks, inside a car's typical
  1800-2800). At part pedal the free rev follows the N² load (`converter_free_rpm`), never under
  idle. In overrun the turbine pumps at OVERRUN_CAPACITY 0.5 of drive, an estimate: no coast figure
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
- fuel, coolant and battery read `applied_throttle` alone.

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
  solved with the crank's coupling, where a lock of the gearbox output is solved before it.
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
| AMT (both semis) | 1500 / 700 | past 0.95 | `shift_dwell_s` | yes | the D13's 1250-1500 rpm cruise band [38]; I-Shift's kickdown switch past full travel [36, 37] |
| Powershift (`TRACTOR_BASE`) | 1500 / 1000 (the full pair's) | none | `shift_dwell_s` | yes | AutoDrive Eco's 1500 [39]; the sourced 1200 downshift [40] sits over the full pair's 1000 |
| Sequential (`race`, `race-future`) | the full pair | none | none | no | full-pedal shifting kept (the user's call) |

- **The Malibu map** [34, Fig. 11]: a 2013 Malibu's 6T40 (2.5 L I4), upshifts driven on level road
  at fixed pedal, read off the figure (±2-3 km/h); crank rpm computed through the 6T40's ratios
  [35]. At ~20 % pedal it upshifts at 1720-1910 rpm and lands 1130-1310; at ~40 %, 2080-3480; its
  coast downshifts sit at 1120-1190 rpm (3rd to 6th). Each light upshift lands 1.07-1.12x over the
  next coast downshift, the landing floor's 1.1. Its kickdown lines climb at 59-100 % pedal.
- **Landings, computed:** the floor raises the light D1>D2 to 1961 rpm on the cars (lands 1265),
  1958 on the vans (1100) and 1857 on the Kenney trucks (990). The semis' 1.5-1.76 steps cannot land
  a light upshift in the D13's band (it would fire at 1925-2640 rpm, past the 1690 point), so their
  map only shifts sooner, landing 854-1125. A semi skip-shift needs a light upshift at 2310 rpm or
  more, past the 2080 redline: it never fires on this six-speed (brief 16, `docs/plans/mechanical_update/16_drivetrain_control.md`).
- **Kickdown:** one shift to the lowest gear under `ShiftPolicy.kickdown_ceiling_rpm`: EPA ALPHA's
  default ceiling, 85 % of the gear's maximum speed (the redline) [34], never within the 1.1 landing
  margin of `shift_up_rpm`. The cap binds on every body and lets a kickdown reach the rpm where the
  engine makes its power (the vans' rated 3000 rpm under their 3300 upshift). The gear must also hold
  `shift_dwell_s` at full pedal before its forced upshift (`ShiftPolicy.time_to_upshift` on the road load and
  the rig's mass; EPA ALPHA's minimum time after a downshift [34]): `sedan-sports` at moderate speed
  would land D2 too high and rev out of it inside the dwell, so it takes D3. None on the tractor: no powershift
  kickdown is sourced.

*The shift's handover.* During an upshift's inertia phase the oncoming clutch's capacity sets the
output torque, a little over the driver's demanded torque, the surplus taking out the crank's
inertia [42]; the phase lasts ~0.15-0.5 s on a converter automatic [41], and its TCU holds the
engine's torque reduced through it [44]. The controller lands the crank on the new gear at an even
rate over `shift_handover_s` (`Drivetrain.handover_rate`), never past the rating:
- **Converter automatic** (cars, vans, Kenney trucks; `shift_handover_s` mid of [41], an estimate): the engine
  is fuelled down so the clutch passes the driver's demand, the engine's torque at the pedal's fuel
  (`Drivetrain.handover_fuel`), and the crank's inertia goes into the reduction. No fixed cut
  (`shift_cut_s` 0): an Allison-class or car automatic shifts clutch to clutch, with no torque
  interruption. A lift upshift, with nothing to reduce, takes the surplus on the clutch.
- **AMT** (the semis; `shift_handover_s` within its `shift_cut_s`, an estimate) and **powershift** (the tractor;
  `shift_handover_s` at [43]'s overlap baseline): the clutch carries the delivered torque plus `J Δω / t`. The AMT's cut is
  its interruption; its fuel returns over `shift_torque_ramp_s` (an estimate; a step rings).
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

*At a held part pedal* the box upshifts low and the engine law is the delivered fuel times the
curve, so the same pedal makes less power: the `doc=accel` benchmark at pedal 0.3 (`-- <variant> 90 pedal=0.3`): the
`sedan` takes several times its floored time (light upshifts at ~2315 rpm, landing 1.17x over the
downshift point; far less at pedal 0.6); `delivery`, `garbage-truck` and `semi` + 24 t take longer
still. A progressive pedal map is brief
16 (`docs/plans/mechanical_update/16_drivetrain_control.md`).

*Kickdown and the keyboard* (`cruise kickdown pulse`): a stab kicks the `sedan` down a gear or two
at every cruise speed, and the `ambulance` and `delivery` likewise, the vans slower to gain speed.
The `garbage-truck` kicks one gear, then its governor binds; the semi never finds a gear under its
ceiling. A key held on and off (the pulse) kicks down on each press and lifts up on each release,
paced by `shift_dwell_s`: 30-40 shifts a minute on the cars, the vans and `garbage-truck`
(hunting gate PASS on every body, no two opposite shifts inside the dwell), and the `sedan` swings
a few km/h around its set speed. The semis and the tractor do not cycle.

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
- **The start gear** (`ShiftPolicy.start_gear`, the tractor's `start_gear_max` 3): the highest gear
  whose launch drive beats the standing load twice, at the driver's pedal, held through the launch
  until the coupling locks (`docs/heavy_vehicles.md` § Tractor, implement & ISOBUS).

Climbs from rest in automatic D at a held pedal (`measure_grade -- <variant> climb grade=<%>
pedal=<p>`, a fixed run or the ramp's top):

| Climb | Result |
| --- | --- |
| `semi` + 24 t, 8 %, pedal 0.6 | holds D2: 185 m |
| `garbage-truck`, 15 %, 0.6 / 0.7 | 0.6 rolls back once the hold lets go: the converter passes less than the grade asks at that fuel; 0.7 holds D1 up the run: 203 m |
| `tractor-kenney` + tipper, 8 %, 0.6 | D1 start (its pedal's), D3 held: 128 m |
| `sedan`, 10 %, 0.5 | D2 held; 336 m |
| `semi` + 24 t, 4 %, 0.6 | D3>D4, a few seconds into the climb |

Floored climbs (`garbage-truck` 8 / 15 %, `semi` 8 %) keep every shift.

**Limiter at launch.** The limiter judges the crank, and auto-shift road speed. With the crank's
inertia reflected onto a spinning pair and the curve's droop below the redline, no floored launch
reaches the limiter, even with traction control off (`notc`: 0 ticks on `sedan-sports`, `race`,
`garbage-truck`, `semi` and the tractor's D1 launch). `race notc` spins its rears from the lock up
to 6784 rpm over 12 ticks. The equipment beside the limiter stands on its own merit:
- The semis' ASR keeps the drive tyres near the peak while the AMT's clutch slips. Without it the
  tyres spin past the slip peak for seconds, under the limiter, and the `doc=accel` benchmark comes a
  fraction of a second later (`trace`).
- The Kenney trucks' ASR does not act on dry asphalt, where gear 1 at converter stall pushes
  less than the rear tyres' grip (`garbage-truck` `notc` reaches the benchmark in the same time). It
  is kept as the EBS equipment it is, for low grip.
- The tractor's launch ramp (`launch_engage_s`) is the powershift's modulation: with the
  whole rating on the first tick its rears flash to high slip and the front axle unloads far more
  than with the ramp. It pulls away in D1 (`docs/heavy_vehicles.md` § Tractor,
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
