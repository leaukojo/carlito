# Vehicle physics review

Scope: `src/vehicles/` (base first: drivetrain, wheel, wheel_drive, stability control, converter,
differential, brakes, hill hold, towing), the families (truck/semi, tractor, boat, plane, drone,
train), `src/water/`, and `docs/drivetrain.md`, `handling.md`, `vehicles.md`, `truck.md`,
`tractor.md`, `boat.md`, `flight.md`, `rail.md`, `sources.md`.

Method: read the code and the docs; no Godot run (this clone has no Godot binary or import
cache). Every finding below was checked against the code it cites. A figure marked *computed*
is hand arithmetic off the shipped specs; *unverified* means the source could not be opened from
this session. The rejected designs in `docs/vehicles.md` § Rejected designs and the frozen areas
in `src/vehicles/CLAUDE.md` are not re-proposed; a finding that touches one says so.

## Summary

| # | Severity | Area | Finding |
| --- | --- | --- | --- |
| 1 | High | train, rule 3 | Traction ignores the reverser: in N (or P) from the bridge the train still pulls |
| 2 | Medium | tyres, all wheeled | Load sensitivity's reference load is the LIVE corner mass, so added load is treated three different ways |
| 3 | Medium | train | No wheel–rail adhesion limit: 320 kN on a 50 t loco is μ 0.65 |
| 4 | Medium | train, rule 3 | The brake acts on the pedal at once; the published `brake_pipe` is a separate lagging model |
| 5 | Medium | semi, rule 3 | `trailer_brake_demand` publishes the trailer's lagged application, not what EBS11 sent |
| 6 | Medium | plane | Lift and the weathervane read ground velocity, drag reads air velocity |
| 7 | Medium | docs vs spec | **DONE** Tractor figures in `vehicles.md` / `sources.md` still use the 0.66 m rear and the old gearing |
| 8 | Low–Med | boat/plane/drone | Damper clamps sized off box-footprint inertia, not the solver's tensor |
| 9 | Low–Med | boat, rule 3 | `fuel` and `fuel_rate` come from two models that disagree; the coolant reads throttle |
| 10 | Low | truck/tractor | `engine_load` is named SPN 92 but computes a percent-of-peak torque |
| 11 | Low | all engined | Battery voltage droops with fuel delivered; the electric train publishes an alternator |
| 12 | Low | truck | Air is drawn only on the driver's pedal rise, not on brakes the unit applies itself |
| 13 | Low | boat, plane | Free-body drag is linear in speed against quadratic lift / sail drive |
| 14 | Low | ABS/TC | `ABS_SLIP` / `TCS_SLIP` restate the grip curve's peak with no guard tying them |
| 15 | Low | shared code | Gravity is written as 9.81 in two places and 9.8 everywhere else |
| 16 | Low | shared code | Lateral-acceleration sensing written three times; rear-wheel counting four times |
| 17 | Low | contract text | `throttle` is described "as applied by the sim" but publishes the arbitrated pedal |

---

## 1. Train traction ignores the reverser (High)

**Where.** `src/vehicles/train/train.gd:103` (`var throttle := input.throttle if powered`),
`train.gd:110` (`_sim.step(delta, throttle, ...)`), `train_sim.gd:116-117` (`tractive_effort`:
"Direction follows the throttle sign (the reverser)"). Compare `src/vehicles/plane/plane.gd:242`
(`prop_thrust` reads `drivetrain.gear_byte`: D forward, R reverse, N none).

**What.** The train's tractive effort reads only the signed pedal, standing in for the reverser.
The gear byte, which the class header and `docs/rail.md` call the reverser ("Reverser (N/D/R)
rides `gear`"), is never read by the train, and a sign can say D or R but never N. From the
bridge, `InputRouter.arbitrate_bridge` (`src/input/input_router.gd:895-899`)
sets `throttle = accel` for any byte but R; with the manual gearbox a byte 0 is "a real N", and
in either mode a P byte becomes N on a body with no pawl. So `gear` N with `accel` > 0 publishes
`gear` 0, sets `ST_NEUTRAL`, and the consist accelerates at full tractive effort.

**Why it matters.** It is the bridge path (the CAN-teaching core) and the published state
contradicts the motion: a learner selecting N sees the train pull. The plane already does the
right thing with the same input.

**Direction.** Gate the traction on the engaged byte:
`tractive_effort(v, absf(throttle) * Drivetrain.drive_sign(drivetrain.gear_byte), ...)` (and the
same for `motor_current`, which re-derives the force at `train.gd:124`). The local path is
unaffected (it never requests N with the pedal down).

## 2. Load sensitivity's reference follows the live mass (Medium)

**Where.** `src/vehicles/base/wheel.gd:470` (`ref_load := corner_mass * 9.81`, feeding
`load_scaled_mu`, `lateral_peak_slip` and so `cornering_load_shape`);
`wheel_drive.gd:291-295` (`set_corner_mass_from` rewrites `corner_mass` on every `set_live_mass`);
`towed_body.gd:119` (a trailer's `corner_mass` is its whole mass over its wheels);
`wheel.gd` `corner_mass` COMPROMISE (a semi's kingpin load is not folded in).

**What.** One field, `corner_mass`, does two jobs: it sizes the 60 Hz clamps (which must follow
the live mass) and it is the tyre's reference load for the load laws. That reference is meant to
be fixed: `GroundDriveSpec.load_sensitivity` defines it as "the corner's static share", the
cited source's law is against a fixed nominal load (Pacejka's `dfz = (Fz - Fz0) / Fz0`,
`docs/handling.md` § Balance), and `BrakeSizing.wheel_grip` checks against `spec.mass`. Because
the sim's is live, the same physical load reaches the tyre laws three ways:

| Load | Path | Reference | Effect on μ per newton (*computed*, s 0.08) |
| --- | --- | --- | --- |
| `garbage-truck` full hopper (+5 t on 8 t) | `set_live_mass` | rises with it (2.0 → 3.25 t a corner) | none; against the empty reference the laden corner would read ×0.94 |
| tractor's carried implement | `set_live_mass` | rises with it | none |
| semi drive axle under the box's plate (27 % of 24 t, ~90 % on the drive axle) | kingpin, not in `mass` | fixed at 8 t / 4 = 2.0 t | drive wheel ~4.8 t, 2.4× ref: ×0.90 |
| box trailer bogie | its own `corner_mass` = 24 t / 6 | 4.0 t, above its 2.9 t static | ×1.04 at rest |

The semi's row is the physically right one. The hopper and implement rows miss the grip a laden
tyre should lose, and every semi-trailer's stock μ is anchored at a load its bogie never carries
(the kingpin takes the rest).

**Direction.** Split the field: keep `corner_mass` for the clamps; give the load laws a reference
fixed at spawn (the spec's static corner share for a body, the bogie's static share for a towed
body; or a tyre-class rated load). Touches `BrakeSizing` (laden figures), the laden ESC tables
(`esc_laden_k`) and `static_drive_grip`, so it is a plan, not a one-line fix.

## 3. The train has no adhesion limit (Medium)

**Where.** `src/vehicles/train/train_sim.gd:19` (`max_tractive := 320000.0`), `:66` (all of it on
car 0), `train.gd:29-30` (loco 50 t, wagons 34 t).

**What.** `tractive_effort` caps by power only; nothing caps it at wheel–rail adhesion. 320 kN on
the 50 t powered head is an adhesion coefficient of 0.65 (*computed*), about twice dry rail
(roughly 0.3, *unverified*). The consist (50 + 4 × 34 = 186 t) starts at 1.72 m/s² before Davis
resistance (*computed*), against EMU starting accelerations of around 1 m/s² (*unverified*); the
header calls the figures "EMU-inspired honest defaults" and cites no source. The brake (90 kN a
car) asks 0.18 of the loco's weight and 0.27 of a wagon's, plausible.

**Direction.** Cap the head's force at `mu_adh * m_loco * g` (a sourced μ), or spread the
tractive effort over motored cars as an EMU does; either way source the 320 kN / 14 m/s corner.
Wheelslip would then be a real event the bus could show.

## 4. Train brake force bypasses its brake pipe (Medium)

**Where.** `train.gd:110` (the sim brakes on `input.brake` the same tick), `train.gd:129-131`
(`brake_pipe_step` on the same pedal, published), `train.gd:25` (`PIPE_APPLY_RANGE` 3.0).

**What.** The published `brake_pipe` is a lagging model (6 bar/s venting, 1.5 bar/s recharge)
that nothing reads: the train is braked instantly by the pedal while the pipe it reports is still
falling, and released instantly while the pipe is still recharging. Rule 3: the signal is not
read out of the sim that produced the motion. Separately, a full service application takes the
pipe to 2.0 bar. The constant's comment means that ("5 -> 2, below the 2.5 warn"), but the
contract calls the 2.5 warn "the emergency-application threshold", so every full service stop
reads as an emergency.

**Direction.** Drive `TrainSim.step`'s brake demand off the pipe
(`(BRAKE_PIPE_CHARGED - pipe) / PIPE_APPLY_RANGE`), and either keep full service above the warn
or describe the warn as full service in the contract. The truck's air model (finding 12) is the
precedent of a reservoir that does gate.

## 5. `trailer_brake_demand` is not what EBS11 sent (Medium)

**Where.** `src/vehicles/truck/semi.gd:113` publishes `trailer.brake_applied()` (the trailer's
chamber lag, `TowedBody.lagged_brake`: 0.35 s apply, 0.5 s release). The demand actually sent is
`demand01` (`semi.gd:95`, from `TruckTelemetry.ebs11_demand`).

**What.** The contract describes the signal as "The braking demand the towing unit SENDS to the
trailer (ISO 11992-2 EBS11, towing-to-towed)", and `truck_telemetry.gd:46` says "(EBS11, what was
sent)"; `semi.gd:112` says the opposite ("The LAGGED application, not the demand"). The
contract's later sentence ("the number here is read off that") can be read either way. The value
published is the trailer-side response, so a step on the pedal reads as a 0.35 s ramp on a
towing-to-towed message.

**Direction.** Publish `demand01` under this name (what the towing unit sent), and if the
trailer's applied level is wanted, give it its own towed-to-towing signal next to `trailer_abs`.
Either way make the three texts agree.

## 6. Plane lift on ground velocity, drag on air velocity (Medium)

**Where.** `src/vehicles/plane/plane.gd:160-174`: `v_fwd`, `aoa`, `sideslip` and `lift_frac` read
`linear_velocity`; drag reads `linear_velocity - wind`. The comment calls this deliberate ("wind
is here to be flown against, not to change the stall speed").

**What.** Lift, stall and the weathervane are airspeed effects; here they ignore the air the drag
moves through, so the model is not the same plane in a moving air mass:
- a 10 m/s tailwind at 20 m/s over the ground gives full lift at 10 m/s airspeed, under
  `stall_speed` 13;
- a 10 m/s headwind gives no lift until the ground speed passes the stall speed, so the take-off
  run does not shorten;
- in a crosswind `drag_lat` carries the airframe downwind and the weathervane then turns the nose
  onto that ground track, so the nose follows the drift; a real airframe weathervanes onto the
  relative wind (it crabs into the wind) and drifts with the air mass.

**Direction.** Read `v_fwd`, `aoa`, `sideslip` and the authority off `air = linear_velocity - wind`
like the drag. The stall speed is then an airspeed, as on a real aircraft (a choice the user may
want to keep; it is flagged, not assumed).

## 7. Stale tractor figures in the docs (Medium) — **DONE** (269e5a0)

**Where / what.** The shipped tractor (`tractor-kenney_spec.tres`, `gen_kenney_vehicles.gd:520-620`)
runs a 0.537 / 0.805 m front / rear, `final_drive` 12.299, wheel inertias 23 / 134 kg·m², 16
gears in 1.116 steps from 7.0 to 1.357, brakes 19231 / 17889 / 33542 N·m (the same 8600 / 8000 /
15000 N·m at 0.36 m, re-referred ×0.805/0.36). The spec before the 6R regeometry (`801246f^`)
had a 0.44 / 0.66 m front / rear, `final_drive` 10.083 and 1.103 steps from 7.0 to 1.6; the docs
still quote it:

| Doc line | Says | Shipped |
| --- | --- | --- |
| `docs/vehicles.md:85` | "0.44 / 0.66 m on the tractor" | 0.537 / 0.805 m |
| `docs/vehicles.md:261` | brakes 15767 / 14667 / 27500 "at its 0.66 m rear" | 19231 / 17889 / 33542 at 0.805 m (the g column, 1.39, is unchanged) |
| `docs/sources.md:28-38` | mass-factor table at "the tractor's driven 0.66 m rear"; row G1 39.32, wheels' I 180, `m r²` 3049, +76 % | wheels' I 268, `m r²` 4536; D3 is now 5.625 × 12.299 = 69.2, `J G1²` 7180, +158 % (D1 +245 %) (*computed*; the start gear runs to D7) |
| `docs/sources.md:300` | κ row: 367 kg × (0.75 × 0.66)² = 90, 143 kg × (0.75 × 0.44)² = 16 | 134 / 23 (the generator's own comment) |
| `docs/sources.md:494` | "Even 1.103 steps over 7.0 to 1.6" | 1.116 steps to 1.357 |
| `docs/sources.md:502` | CVT ratio tops "through `final_drive` 10.083 and the 0.66 m rear" | 12.299 and 0.805 m (same road speeds: G / r is unchanged) |

The mass-factor row is the one whose figure moves: its G1 of 39.32 matches neither the shipped
gearing nor the one before it (D3 there was 5.75 × 10.083 = 58.0, +165 %), so it predates both.
In the shipped D3 the crank's reflected inertia outweighs the body's own. The other rows are
re-referrals: the road speeds and forces they imply are unchanged.

**Direction.** Re-derive the rows off the shipped spec; `check_docs.mjs` cannot catch a number.

## 8. Free-body damper clamps on a proxy inertia (Low–Medium)

**Where.** `boat.gd:105`, `plane.gd:129-131`, `drone.gd:166`: `VehicleMath.inertia_of(mass, a, b)`
(a uniform box of the probe footprint or `body_extents`) sizes the one-tick clamp of the yaw,
pitch and roll dampers. The wheeled bodies read the solver's tensor (`VehicleMath.inverse_moment`
in `wheel_drive.gd:447` and `tow_host.gd:387`; `size_cap_masses`; `hitch_effective_mass`).

**What.** `src/vehicles/CLAUDE.md` § Physics: "Read the tensor off `PhysicsDirectBodyState3D`".
The clamp exists so a damper never reverses its rate in one tick; it only does that if `moment`
is the moment Jolt actually integrates with. Where Jolt's tensor (computed from the collision
shapes about the custom COM) is smaller than the box proxy, the clamp is looser than the step it
guards; where larger, the damper is over-clamped. Unmeasured here (needs a run).

**Direction.** Read `1 / VehicleMath.inverse_moment(self, axis)` per tick on the free bodies, as
the ESC already does. The drone's payload path then needs no separate `inertia_of` update.

## 9. Boat fuel: two unreconciled models (Low–Medium)

**Where.** `base_vehicle.gd:310` drains the boat's `fuel` by `VehicleTelemetry.fuel_step`
(0.02 + 0.18 × throttle %/s); `boat.gd:204` publishes `fuel_rate` from
`BoatTelemetry.fuel_rate_model` (1.5 + 8.5 × throttle L/h). The model's own comment: "it does not
reconcile with the 'fuel' tank drain". Coolant on the rigid crank reads `applied_throttle`
(`base_vehicle.gd:302`), not the burn.

**What.** Two published signals on one tank say different things (rule 3). The wheel-driving
bodies already have the reconciled form: `fuel_drain(burn_lph, tank_l)` and coolant on the burn's
share of its rated figure.

**Direction.** Give the rigid crank (boat, plane) the wheel-driving bodies' one chain:
`VehicleTelemetry.fuel_rate_lph` on its own `rpm` and `applied_throttle` (it needs only the
spec's curve, which both carry), drained through `fuel_drain` from `tank_litres`, the coolant on
the burn's share of `rated_fuel_rate_lph`. The boat then publishes that burn as `fuel_rate`. It
is only as honest as the free-rev rpm it reads (an accepted COMPROMISE), and the plane would pass
its prop rpm, but fuel, burn and coolant become one law. Not thrust times speed: that burns
nothing at full throttle against a dock. This also retires `FUEL_IDLE_BURN` / `FUEL_LOAD_BURN` and
`BoatTelemetry.fuel_rate_model`.

## 10. `engine_load` is not SPN 92's definition (Low)

**Where.** `vehicle_telemetry.gd:257` (`engine_torque(rpm) × fuel / peak_torque`); contract
`engine_load` ("J1939 SPN 92 flavor ... Normalised against the PEAK").

**What.** As I recall J1939-71 (*unverified*: the search results did not show the text and
`isobus.net` is not reachable from this session), SPN 92 "Engine Percent Load At Current Speed"
is actual torque over the maximum available at the current speed. In this sim that ratio is the
delivered fuel `applied_throttle` (exactly, on indicated torque `f (curve - motoring)`), which is
not "plain throttle" as the contract says: it carries the governor, the limiter, the idle floor
and a PTO's load. The shipped formula, torque over a fixed reference, has the shape of SPN 513
(actual percent torque against the reference torque, SPN 544; also *unverified*). Both are
honest readings; the name and the justification are what disagree.

**Direction.** Confirm against J1939-71 / J1939DA, then either rename the flavor note (SPN 513-like)
or publish `applied_throttle` as SPN 92 and keep the torque reading under its own name.

## 11. Battery voltage droops with fuel (Low)

**Where.** `vehicle_telemetry.gd:241` (`BATTERY_CHARGING - 0.6 × load_frac`), fed
`applied_throttle` at `base_vehicle.gd:313`.

**What.** A regulated alternator holds its set voltage across engine speed and engine load;
terminal voltage sags with electrical load, and the one electrical load the sim knows is its
lamps (`LampSet`). Fuel is a stand-in no electrical load follows: a floored engine reads 13.6 V,
an idling one with every lamp lit about 14.1 V (its idle fuel, ~12 % on the `sedan`). The
electric train (contract `battery` out includes `train`) publishes the same engine-alternator law
off its pedal, pantograph down or not.

**Direction.** Droop on the lamps actually lit, or hold the charging voltage flat; give the train
an auxiliary-supply figure gated on the pantograph.

## 12. Truck air drawn only on the driver's pedal (Low)

**Where.** `truck.gd:80-86`: `air_step` draws `AIR_PRESS_*` on the rise of `input.brake`.

**What.** The brakes the unit applies itself fill its service chambers from zero without drawing
air: the ESC yaw controller's selective braking and roll stability's every-wheel application.
The driver's identical application draws. (The hill hold is not one: it keeps the driver's own
application, already paid for. The trailer's chambers draw nothing on any path; only its charge
is modelled.) Small in volume, but this is the one pneumatic model that gates (spring brakes at
3 bar).

**Direction.** Draw on the rise of the service level actually applied: the pedal's application
raised by `drive.roll_application()`, plus the yaw corners' share of their brake.

## 13. Linear free-body drag (Low)

**Where.** `boat.gd` hull drag (`drag_long` N per m/s, "top speed is roughly
`thrust_force / drag_long`", `gen_boat_variants.gd:40`); `plane.gd` `drag_coeff` N per m/s against
`lift_coeff × v²`.

**What.** Hull resistance and aero drag grow at least with v², and a displacement hull meets a
wave-making wall near its hull speed; a linear law has neither. On the sailboat the drive is
quadratic in apparent wind (`BoatSail.force`) against a linear hull, so nothing stops a hard
breeze driving it past a displacement hull's speed (unmeasured). On the plane the lift-to-drag
ratio rises linearly with speed. Both drags are tuned against their thrust for a top speed, and
`FreeBodyDrive` (sharing a drag shape) is rejected; this is about the law, not sharing.

**Direction.** A `v |v|` term beside the linear one (the linear part keeps the low-speed clamp
behaviour), retuned per hull; at minimum note the missing hull-speed limit in `docs/boat.md`.

## 14. ABS/TC peak slip restated, unguarded (Low)

**Where.** `wheel.gd:25,30` (`ABS_SLIP`, `TCS_SLIP` = 0.12); `BalanceModel.axles` derives
`peak_slip` from the spec's own `grip_curve` (`balance_model.gd:79-84`).

**What.** Every shipped curve peaks at 0.12 today, and a peak-following ABS is a rejected design;
but nothing ties the constant to the data: a spec with a different curve would keep ABS and TC at
0.12 while `BalanceModel` (and the ESC tables built from it) read its own peak. No test asserts
the equality (`tests/` has no such check).

**Direction.** One `test_vehicle_catalog` assertion that every spec's (and trailer's) grip-curve
peak sits at `RayWheel.ABS_SLIP`, so the rejected design's premise is guarded.

## 15. Two gravities (Low)

**Where.** 9.81: `wheel.gd:470`, `wheel_drive.gd:480`. 9.8: `BrakeSizing.G` (and `BalanceModel`,
`StabilityControl` through it), `VehicleTelemetry.GRAVITY`, `TrainSim.GRAVITY`, the project's
`default_gravity`; the bodies also read `get_gravity()` live.

**What.** The sim's reference load is 0.1 % off the one `BrakeSizing` and `BalanceModel` check
against: negligible in force, but the same constant is a literal in six places (`wheel.gd`,
`wheel_drive.gd`, `BrakeSizing.G`, `VehicleTelemetry.GRAVITY`, `TrainSim.GRAVITY` and
`BaseVehicle`'s fallback for the project setting).

**Direction.** One constant (`BrakeSizing.G` or a `VehicleMath.G`), or the live gravity where the
code already has a body.

## 16. Repeated sensing and counting (Low)

- Lateral acceleration "off the velocity change, gravity-free, on the level left axis" is
  computed in `WheelDrive.esc_step` (raw, `wheel_drive.gd:422-441`) and again in
  `TowedBody._sense_lateral` (smoothed at `BaseVehicle.ACCEL_SMOOTH`, `towed_body.gd:196`), with
  `BaseVehicle._update_telemetry` a third (body axes, smoothed). The unit's ESC and the trailer's
  EBS therefore read differently filtered sensors for the same rig. A
  `VehicleMath.level_lateral_accel(v_now, v_prev, basis, gravity, delta)` would be the one home.
- Rear wheels are counted in `Drivetrain._driven_rears`, `TruckVehicle._retarder_rating_total`,
  `GroundDriveSpec.axle_brake_torque` and `BrakeSizing.axle_geometry`; the last is the general one.

## 17. `throttle` contract text (Low)

**Where.** Contract `throttle` out: "Throttle as applied by the sim (signed by direction)";
`base_vehicle.gd:263` publishes `input.throttle`, and the `speed_limit` description relies on it
being the pedal ("a governed truck at its limit publishes a flat pedal").

**Direction.** Reword the contract to "the arbitrated pedal (signed by direction); the delivered
fuel shows in `engine_load` / `fuel_rate`".

---

## Checked and consistent

- The engine law, the fuel burn and coolant read the same delivered fuel (`applied_throttle`);
  the Willans burn adds `f (curve - motoring)` exactly as `crank_torque` does.
- `crank_stiffness` converts the curve's N·m/rpm slope to N·m per rad/s correctly
  (`× RADS_TO_RPM`).
- Overrun losses divide by efficiency on both the rigid crank and the coupled solve.
- The converter's lock-up torque is never multiplied by a torque ratio above 1: it engages only
  past the coupling point, where `torque_ratio` is 1.0.
- `BrakeSizing.brake_force` sums `T / r` per axle correctly for unequal radii.
- ESC brakes the outer front for oversteer and the inner rear for understeer;
  `T = M_z r / half_track` is the moment's wheel torque.
- The fifth wheel's yaw friction is applied as an equal and opposite pair (`tow_host.gd:376-377`).
- The retarder table in `docs/truck.md` re-derives from the specs (600 × 4.01 / 2 = 1203 N·m;
  1450 × 2.925 / 2 = 2120 N·m; 0.84 / 1.47 m/s²).
- The tractor's brakes, pawl, CVT ratio tops and relief re-refer consistently to the 0.805 m rear
  (51 km/h on the top ratio at 2300 rpm; relief 7000 × 9.8 × 0.805 = 55.2 kN·m).
- `BalanceModel`'s `mass g / 4` reference matches the sim's on every ESC body (all four-wheeled).
- The tanker's surge moves the load rearward under acceleration and forward under braking.
- The drone's ESC current uses the same `prop_torque_ratio` as its yaw reaction, so the
  published shaft power is the one the rotors make.

## Noticed outside the scope

- The boat cannot go astern from the bridge: the contract declares no `gear` input for `boat`,
  and `InputRouter.arbitrate_bridge` signs the throttle only from a received R byte
  (`input_router.gd:895`). The local path reverses through `brake_reverse`.
