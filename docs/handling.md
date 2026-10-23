# Handling

The body on its wheels: inertia, pitch, steering geometry, the understeer balance, aero balance
and crosswind. The wheel, tyre and brake models underneath: `docs/vehicles.md`; the measured
tables: `docs/vehicle_measurements.md` (§ Cornering, § Step steer, § Wind); sources:
`docs/sources.md` (§ Roll steer, § Linear understeer, § Aero balance, § Crosswind). Rules:
`src/vehicles/CLAUDE.md` § Physics.

## Anti-roll latch

Wheels tick in array order; a live read gave the first wheel of each pair a
partner one tick staler than the second's, a phantom damper of `rate / 60` N·s/m on the left
wheels only, which the open split turned into drift past the grip peak (1.07 m over 200 m on
`hatchback-sports`). With the shared latch every bar-carrying body tracks 0.000 m, the semis 0.05 m. Ruled out
as tracking causes: the COM heights, `mu_lat` and the axle pairing; body
asymmetry; `load_scaled_mu`; a bar-driven load-transfer loop.

## Inertia

Moving a sedan's `com_y` traces a parabola in the roll and pitch moments, with its
minimum at the hull's own mass centroid, while yaw barely stirs: the parallel-axis shift. The
tensor also scales exactly with a runtime `mass` write. Roll and pitch stay Jolt's, computed from
the shapes about the COM. Yaw is declared (`yaw_dynamic_index`, `Iyy = index · m · a · b`, a and b
the COM-to-axle distances; Jolt's per-axis override keeps the other two computed), because the
toy-length hull's uniform-density boxes read ~1.42 on the `sedan`, over every measured car. The
index is the min-max band of NHTSA's measured vehicles (SAE 1999-01-1336; driver only, no
outriggers, IPMD v5 / VIMF): cars 0.93-1.20, median 1.03 (n 35), shipped on `CAR_BASE`; SUVs
0.91-1.19 (44); vans 1.5-2.5 t 0.84-1.17 (29), `VAN_BASE` 0.91 (an estimate off the E-series vans);
pickups 0.85-1.02, median 0.94 (36), shipped on `pickup*`. No measured open-wheeler, heavy truck or
tractor was found, so those stay computed: `race` 1.00, `garbage-truck` 1.64, `firetruck` 1.56, the
tractor 0.96.
A carried implement reaches the tensor only through the COM it moves (`M d'²` about the shapes,
not its own lever `m_t m_i / M · D²`), a COMPROMISE at `TractorVehicle._apply_implement_mass`:
raised, Jolt carries 57-86 % of the composite's yaw (plough 57, mower 72, harrow 79, spreader 86),
60-82 % of its pitch and 92-118 % of its roll (`measure_vehicles -- tractor-kenney 20 hitch`).
Guards: `test_body_inertia`, and `test_kenney_variants` holds every declared index inside its band.
A body with its COM off z 0 reads its yaw ~5 % apart over 1 m of COM height in the principal frame
(the `I_yz` product), parallel axis, not an engine effect.

## Resistance balance

Resistance applies what `0.5*rho*Cd*A*v^2 + crr*N` owes to within a
newton, and summed tyre force matches `axle_torque / r` to within two. The `balance` line in
`measure_vehicles` (`tyres - resistance + rake`) closes on the measured acceleration to a newton
or two; a gap means a new force is unaccounted for. `Wheel.contact_normal` is diagnostic only;
`Wheel.force_long` feeds only the next tick's link force (§ Pitch). `rake` reads ~0 only on the
flat.

## Pitch

The Kenney wheelbases are toy-scale (1.58 m on `suv`, ~2.8 m on a real one) under real
masses and COM heights, and pitch goes as `m a h / (k L²)`, so pitch is judged per g against the
body's own `h / L` and the springs-and-links prediction (the launch trace's `pitch` line: measured
beside predicted), never a full-size degree figure. Two honest models carry it:
- springs sized to a ride frequency per axle (`ride_hz`, `_derive_springs`), so every car and van
  stands level at one sag (0.128 m car, 0.152 m van) instead of a heavy axle sitting in its bump
  travel;
- link geometry (`anti_dive_slope` / `anti_squat_slope`, 40 % / 50 % of `h / L`), a force along the
  contact normal proportional to the tyre's own drive or brake force. The tyre still carries the
  whole transfer, so grip and the brake split do not move; only the springs deflect less.

What stays is front lift: the front links push down only in proportion to the FRONT drive force, so
a rear-driven or rear-biased body lifts its nose on springs alone (the front axle's low and its
gap under predicted transfer: the launch trace's `front axle` gate). The trucks keep hand-tuned springs (no
`ride_hz`) and carry anti-squat only. The front axle unloads fully at `g * front_share * L / h`,
past what the rear tyres push in gear 1 (`garbage-truck`'s threshold on its sourced
`front_weight` sits well above it); where that falls short, the levers are the weight split and the start gear,
not a lower COM. Guard: the tracking pass's front-lift check.

*The front-axle gap* (the launch trace's `front split` line, `_gap_split`). Steady transfer is
counted since parked. A coupled rig settles on the foot brake with its two bodies pushing on the
coupling, a load the parked front already carries (the trace header's `coupled` line prints it;
the farm tipper's drawbar holds about twice the semis' plate). The front
axle's load under what steady transfer `m a h / L` predicts closes, to under a point on every body
without a trailer, as the sum of:
- road resistance at the COM (~1 point);
- the trace's acceleration, a tick late (large only at a take-up's spike);
- heave;
- the body's pitch accelerating (the overshoot);
- **lean**: the loads' moment from their patches sitting off their stations on the pitched body.
  Each patch stays under its hub (`RayWheel.patch_offset`, the hub's disk on the contact's plane), so
  it moves `(h - r) sin θ`.

The lean is a negative pitch stiffness `m g (h - r)` against the springs' pitch rate, which is why
measured pitch per g reads over the springs-and-links prediction: -1 to +10 % on every body without
a trailer, and +5 % on the coupled rigs: `semi` and `semi-conventional` with the box,
`tractor-kenney` with the farm tipper (`-- all 45 trace` prints each body's `pitch` line).

The `front axle` gate judges the overshoot alone (the gap less the other three; a two-tick mean)
per event (the launch, then each shift's settle) against what a body damped at 0.3 of critical,
the road band's low end, overshoots a step of that event's swing (`exp(-ζπ/√(1-ζ²))`, 37 %), never
under 5 points. A launch swings from parked; a shift, the larger of the steady share's rise through
its handover and cut and its fall since. So a short, tall body is not failed for its footprint: the
laden `semi`'s launch swings ~69 points and overshoots 5, `sedan-sports`' 43 and 6.

Every car, van and Kenney truck passes. So do both semis, bobtail and with the box, and the bare
tractor on every event (`-- all 45 trace`; the gates print per body). The tractor's floored skip-shifts pass on the
powershift's torque reduction (`docs/drivetrain.md` § The shift's handover); without it, the
crank's inertia reaches the wheels and D7>D13 overshoots 16 points. The AMT's cut returns over
`shift_torque_ramp_s`, so its drive does not step into the pitch mode.

The bobtail semis are where the gate reads the steer axle's damping and the contact itself:
- The cab-over's launch is the shortest wheelbase's largest swing, and its overshoot is the nose
  rising on the front rebound damper. Its front block (`semi_spec.tres`, shared by
  `semi-conventional`) holds the road band's ends, 0.30 / 0.40 of critical, at the bobtail steer
  corner, and the launch passes (`-- semi 45 trace trailer=bobtail`). At 0.35 rebound it overshoots the allowance;
  the bump side and the rear dampers do not move it.
- A one-tick spike of the steer axle's load at a steady pull (up about ten points of parked, then
  down as far) is the contact query's, not the body's: a sweep stop the rest test reads clear
  (`docs/vehicles.md` § Physics derivations and figures, *Contact*). The trace's `contact` flag prints each wheel's
  load, compression, patch, normal and collider under its lines to find one.

Of the coupled rigs, one event fails: `tractor-kenney` + farm tipper's launch from its D6 start
(its `trace` run's `per event` line).
- The cause is the trailer's brake model, not the tractor's pitch: a one-tick jolt, back then
  forward, as the tipper's service brakes finish venting (`TowedBody.BRAKE_RELEASE_S`) under a
  floored pull-away.
- Vented in three fifths of that time, the launch passes.
- The tipper's shifts pass, and vented faster, too.
- No tractor pitch damping is sourced. `GroundDriveSpec`'s rear fallback keeps the front's ζ at
  the front's corner mass: ≈ 0.31 bump / 0.38 rebound on the 2.17 t rear corner, against the
  front's 0.39 / 0.48. No failure traced here points at it.

## Steering geometry

`max_steer_deg` (the garage's "Max steer"), the speed taper and guidance
(`steer_angle_from_curvature`) set the bicycle (mean) angle `δ`; `WheelDrive.ackermann_angle`
splits it per steered wheel off its lateral offset `x` (+ = right), the wheelbase `L` and the spec's
fraction `f` (`GroundDriveSpec.ackermann`): `tan δ_w = tan δ / (1 + f x tan δ / L)`. At `f = 1` every
steered wheel's axis meets one turn centre (`cot δ_o - cot δ_i = t / L`); at any `f` the two wheels'
cotangent mean is `cot δ`, so the turn centre `δ` asks for is kept, and a reading of "the" steer
angle takes `mean_steer_angle()`, never the wheels' average. The lock limits `δ`, not the inner
wheel: the lock figures are recipe feel numbers, and limiting the inner wheel would widen every
turning circle (`sedan` 2.02 → 2.65 m at the rear axle) or relabel every lock. So the inner wheel
turns past the lock at full lock (`max_steer_deg`; `test_vehicle_catalog` asserts it). The law holds while `tan δ < L / (f |x|)`, past every lock at `f = 1`
(`test_vehicle_catalog`). Each wheel's angle is its split plus its roll steer (§ Balance), which
`mean_steer_angle()` leaves out: guidance, ISOBUS and the step pass read the driver's angle.

Every wheeled family ships `f = 1.0` (`CAR_BASE`, `TRUCK_BASE`, `VAN_BASE`, `TRACTOR_BASE`, both
semis), each an **estimate**: road cars run partial Ackermann (~40-60 %, a patent claim, not a
textbook figure) for the loaded outer tyre at high g; trucks set close to full for steer-tyre wear
(SAE 861975 and 912693, no figure); no ag-tractor figure was found. Here the low-speed scrub is the
point: at road speed the split is second order (a fraction of a degree on `sedan`'s step at road speed). Against
the parallel-steer table the step sweep's `K` rises 0.01-0.04 deg/g on every body (consistent with
the outer, loaded tyre steering less), with no new spin, rollover or lifted wheel. Trailers and the plane
have no steered pair.

Full lock at crawl speed (`circle`), parallel steer → `f = 1`: the radius driven at the rear
axle over `L / tan δ`, and the inner / outer front slip angles (+ = the wheel points further into
the turn than it travels). Parallel, the two fronts fight; at `f = 1` both carry the same small slip
the cornering force needs.

| Body | Radius / law |
| --- | --- |
| `sedan` | 2.39 → 2.13 m / 2.10 |
| `suv` | 2.65 → 2.48 m / 2.43 |
| `tractor-kenney` | 3.24 → 2.97 m / 2.93 |
| `delivery` | 4.33 → 4.23 m / 4.21 |
| `semi` (bobtail) | 9.01 → 8.76 m / 8.50 |

## Balance

Tyre load laws (`load_sensitivity`, `cornering_peak_load`: `GroundDriveSpec`
comments), the bar split's LLTD and roll steer set the balance. `BalanceModel` predicts K, LLTD,
roll and the limit margin (rear capacity over front, less 1; + = front first), printed as `pred`.
Its springs carry the side force's moment plus the rolled COM's weight, `m a h + m g h phi`
(`BalanceModel._roll_state`): ~9 % more roll and transfer than the side force alone at a car's
~5 deg/g. The step pass's roll-steer angles read their `pred` within ~2 % at the held steps below
the limit, and under it near the limit. The corner pass's roll reads its `pred` within 0.1 deg on
every road body but `delivery` (0.5 over). `garbage-truck` reads INF there: just under its
corner-pass peak the model lifts its inner rear too, a tip, where the pass holds on one lifted
wheel (the bump travel that holds it is not in the model). Measured K runs 0.13-0.29 deg/g over
`pred`, 0.03-0.06 deg of steer at the smallest held step: ~1 % of each axle's slip,
second-order steering geometry. `hatchback-sports` runs 0.57 over, because its front LSD adds
0.43 deg/g of its own under the held pedal, which the model omits: K 2.23 at its 2.5 bias against
1.80 with `diff_bias_front` set to 1.0 in its spec (`measure_vehicles -- hatchback-sports 60 step`).
Sources (`c = PKY2 * Fz0 / ref`, `s` = mu lost per doubling): passenger 205/60R15 (Pacejka 2nd
ed. Table A3.1: PKY2 2.13, Fz0 4 kN, 15 %) -> `CAR_BASE` c 2.56, s 0.10; van 185/80R14 (projectchrono `mf_185_80R14.tir`: 1.39, 3.8 kN,
19 %) -> c 1.92 (estimate), s 0.08; truck 315/80R22.5 (projectchrono `CityBus_Pac02Tire.tir`:
3.33, 35 kN, 10 %) -> c 3.33, s 0.08; ag radial has no open set -> c 3.0, s 0.12 (estimates).
Tractor `rear_lat_grip` 1.077 = `1 + s * log2(rated rear / rated front)` (Michelin MultiBib
650/65R38 over 540/65R28).
- **Roll steer.** Each axle steers `roll_steer_front` / `_rear` deg per deg of its own suspension
  roll, `atan((c_right - c_left) / track)` off the bar's shared latch (`RayWheel.roll_steer`),
  never the body's world roll: a banked road or a slope moves no link. + = toward understeer, the
  front out of the turn and the rear into it. It is a wheel angle added after the Ackermann split,
  never a grip, so K gains `(front + rear) * roll gradient` (`roll_steer_gradient`) and `limit`
  does not move. Shipped (`docs/sources.md` § Roll steer): front 0.10 on every road body
  (secondary); rear 0.036 on the FWD saloons' twist beam (sourced), 0.05 multi-link on the rear-
  and all-driven cars and 0.10 leaf on `van`, the pickups and `VAN_BASE` (estimates); 0 on the
  open-wheelers, trucks and tractor. The road bodies read K 1.06-2.23 deg/g at the slowest step
  (`measure_vehicles -- <variant> 60 step`), inside the secondary population band of 0.7-8.2.
- **The 60 Hz loop.** The angle follows roll, and roll the side force it makes: per tick the gain
  is ~`eps C h dt^2 / I_roll`, ~0.007 on a `sedan`, and understeer roll steer sheds side force as
  the body rolls. The step pass counts tick-rate ringing (`chatter_runs`: three consecutive flips,
  each past 1 % of the angle): 0 on every run but two decaying transients (`police` at a step's
  onset; `pickup`, two cycles of 2.6 %, ~0.005 deg, gone at a 100x smaller coefficient). At 10x
  the coefficients (`sedan`) it reads isolated three-flip bursts on 5 of 18 runs, no sustained
  ringing.
- **Angular damping is declared** (`VehicleMath.declare_angular_damp`): every wheeled body and
  trailer REPLACEs the engine's default with `VehicleSpec.angular_damping`, 0 on every one, so
  yaw, roll and pitch bleed through the tyres and dampers alone; the plane, boats, drone and train
  keep the default. The engine's 0.1 /s would add 0.10-0.20 deg/g of K at the slowest step and
  hold `delivery` and `garbage-truck` front-first in the corner pass; without it `police` and
  `suv-luxury` spin the fastest lifted 30 % step (accepted;
  `measure_vehicles -- <variant> 60 step`).
- **The corner pass is not `limit`.** It runs driven, on its speed hold, at 9-23 deg of lock on
  these wheelbases; `limit` is free-rolling at small steer. A driven axle spends ellipse on the
  turn's drive (`delivery`'s rear: front-first on side force alone, rear-first with it); a
  front-driven axle's tilted drive carries side force, so its front makes less than its static
  share; a rear-driven body's front makes a few points more. The pass prints `pred` beside its
  reading: a margin under ~5 % sits inside this (`docs/plans/drivetrain_control.md` phase 10).
- **Stated shortfall: linear K.** Under a real car's 2-4 deg/g: roll camber, compliance steer and
  aligning torque are unmodelled, 1.2, 0.5 and 0.4 of an illustrative 4.1 deg/g budget against
  roll steer's 1.0 (Bundorf & Leffert, SAE 760713; `docs/sources.md` § Linear understeer).
- **COMPROMISE:** `sedan-sports`, `suv`, `pickup`, `pickup-flat` and the semis keep even bars and
  the law off (recipe comment): on the class split, roll steer on, a lifted step at speed spins
  them (1, 4, 1, 1 more cells). `suv-luxury` runs a 27 / 9 split, the law on, equal tyres.

## Aero balance

Downforce acts at the point between the axle stations that puts `downforce_front`
of it on the front (`VehicleMath.downforce_point`), so the split depends on axle geometry and never
on the live COM. The open-wheelers run their centre of pressure just behind the CG: `downforce_front`
a little under `front_weight` (`gen_kenney_vehicles.gd`, `docs/sources.md` § Aero balance), so the
rear gains load faster than the front as speed rises and the limit stays front-first.
`BalanceModel.axles(spec, speed)` carries each axle's share as `aero`: grip, stiffness, sag and the
lift cap read `load + aero`; the side force an axle must make, and every g, stay over the weight.
`test_vehicle_catalog.test_a_winged_body_stays_front_first_at_any_speed` holds the margin from rest
to the top end. Drag at `aero_centre` adds a pitch moment: above the COM it lifts the nose. The
measured balance at speed: `measure_vehicles -- race 90 step speeds=150,200`, its `pred` beside it.

## Crosswind

The wheeled bodies read the level's wind (`WindField.at`, as the boat and the flight
bodies do), so CONDITIONS' LIGHT and STRONG reach car, truck and tractor (`WorldConditions.WIND_FAMILIES`;
the train has no aero term). `level_6` authors its own breeze, so a car there feels it at LEVEL.
`VehicleMath.air_force` reads the air in the body frame: drag on its along-nose part, side force
`Cy*A` on its across part, both scaled by the air speed, so the side term is `q * Cy*A * sin(yaw)`
and one `side_area` is both the broadside figure and the small-yaw slope (`docs/sources.md`
§ Crosswind). A headwind or tailwind moves `engine_load`, fuel and top speed by drag's
`0.5 rho CdA ((v ± w)^2 - v^2)`. A crosswind pushes the body downwind and, acting ahead of the COM,
yaws it downwind too (`docs/vehicle_measurements.md` § Wind). A parked body is pushed as well: the
gate reads the air, and the static hold resists it (`measure_grade -- <v> park=16.7 cross
wind=0:13` holds every `doc=park` body under a millimetre but the `semi`, whose known cross-slope
creep grows). In a slide the across-air part takes `Cy*A` instead of drag's `Cd*A`, about seven
times more on a car, at a point ahead of the COM. That lowers the step pass's steady K (`docs/vehicle_measurements.md` § Step steer) a little in
its fastest row and tips its three largest lift-off overshoots there into spins; with the side term zeroed,
the old table returns to within transient noise.
