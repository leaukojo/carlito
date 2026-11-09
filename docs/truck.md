# Truck & trailers

The truck family publishes a second machine's state on a second network: J1939 (the chassis, plus a
CANopen body network across a gateway) and ISO 11992 (the trailer bus). The tractor, whose drawbar
shares the towing code: `docs/tractor.md`; the framework and the other families: `docs/vehicles.md`;
shared plumbing: `docs/systems.md`. Rules: `src/vehicles/truck/CLAUDE.md` — this doc is the tour
and the derivations.

## Truck & J1939

A chassis class, not a job: `garbage-truck`, `firetruck`, and the hand-built tractor units
(`semi`, `semi-conventional`) only; heavy vans are `car`-family, proprietary CAN. J1939 is the
parent of ISOBUS and NMEA 2000.

### The signal set

| Signals | Flavor | Notes |
| --- | --- | --- |
| In (4): `retarder`, `red_stop`/`amber_warn`/`protect_lamp` (J1939-73 DM1 lamp bits) | `j1939` | published FMS set — J1939-71 subset six European makers agreed to expose in 2002 |
| Out (5): `air_primary`, `air_secondary`, `retarder_state`, `axle_load`, `gear_ratio` | `j1939` | sloppyCAN also packs the stability unit's VDC1 (status bits 7-11: lamp, fully operational, brake-light request, YC / ROP) and VDC2 (`yaw`, `accLat`, `accLong`; no hand-wheel angle) from the brake controller, on air-braked bodies only; VDC2 at the telemetry rate, slower than J1939's (`docs/sources.md` § Stability control) |
| `engine_load`, `pto`, `pto_state` | `isobus` | reused, not duplicated — listed on `truck` alongside `tractor` (ISO 11783 is built on J1939: `engine_load` is SPN 513-like); `engine_hours` (SPN 247) rides unflavored |

`diff_lock`/`diff_lock_state` are not extended to the truck.

### Air, retarder, axle load

- Air gates the brakes: two reservoirs (SPN 1087/1088) charge while the engine runs, draw
  down on the rise of the service level applied (`WheelDrive.service_level`: pedal plus ESC;
  **0.70 / 0.55 bar** a full one; held, nothing more); circuit 2 is smaller so the pair diverges. Below
  `TruckTelemetry.AIR_SPRING_BRAKE_BAR` (**3 bar**) on either circuit, spring brakes apply
  from the next tick: `handbrake_torque` on the rears through the spin step
  (`WheelDrive.spring_brake`), a parking brake no stronger than the service brake on its drum
  (6.5 kNm a wheel on `garbage-truck`, 7 on `firetruck`, 12 on the semis), and the box drops to N
  (`Drivetrain.drive_inhibit`, an Allison-class park-brake auto-neutral), so the truck can't
  drive away; `warn` (**5 bar**) is a band to stop in first. Gate reads the
  minimum of the two circuits; losing air has no ramp.
- A coupled trailer's spring brakes apply on the same event: the towing unit hands
  `TowHost.tick_towing` its parking brake (`parking01`, the lever or the air gate,
  `WheelDrive.parking_application`), on the gate tick. The auto-neutral engages at any speed
  (COMPROMISE in `drivetrain.gd`). `tools/measure_air_loss.tscn -- all strict` (CI) drives it live.
  Its three passes per body, their floors and the honest drain: the tool's header. Every body holds
  within a millimetre or two and stops in roughly 10-14 m; a semi with its trailer left unbraked fails both.
- Retarder is real driveline torque, not an indicator bit: math on `Drivetrain`, `WheelDrive` adds
  it to driven wheels' brake torque, `RayWheel` integrates it, `GroundDriveSpec.retarder_equipped`
  gates it to truck specs only. Can't skid the axle (`RETARDER_SLIP_TARGET` caps the one-tick spin
  change at 0.10 slip). Rated by its own hardware, `retarder_rating_nm` at the gearbox output,
  reaching each driven wheel through `final_drive` (`Drivetrain.retarder_rating`): flat-road
  retardation at the body's own mass is `rating * final_drive / r / m`.

  | Body | Rating at the output | Per driven wheel | Retardation |
  | --- | --- | --- | --- |
  | `garbage-truck` / `firetruck` (8 / 7.5 t) | 600 Nm, medium-duty output retarder | 1203 Nm | 0.84 / 0.89 m/s² |
  | `semi` / `semi-conventional` bobtail (8 t) | 1450 Nm, low end of the hydraulic class | 2120 Nm | 1.47 m/s² (0.37 coupled to the 24 t box, which it leaves unbraked) |

  `test_truck` pins a **0.7-1.6 m/s²** band per shipped spec at its own mass (past ~1.6 an
  auxiliary brake stands in for the foot brake) and the retarder under its axle's service brake.
  The trailer is asked for nothing (`TruckTelemetry.ebs11_demand`): an endurance brake operates no
  trailer service brake and its coupling force goes uncompensated (R13 5.2.1.21, 5.2.1.28.6;
  `docs/sources.md` § The retarder and the trailer's brake). The pushed rig holds straight on snow;
  ice jackknifes it on the foot brake alike (`docs/vehicle_measurements.md` § Brake heat: the
  kingpin column). `retarder_state` is torque applied (SPN 520's magnitude).
- `axle_load` is read out of the sim: summed `RayWheel.suspension_force` on the rear axle in
  kg (SPN 582, `WheelDrive.rear_suspension_force`), never a mass lookup. `warn` **11500** is the
  EU 11.5 t drive-axle limit, `warn_side: high`. The tractor publishes it too (its rear is the
  drive axle), where it never reaches the warn.

### Lamps and the cluster

- DM1 lamps (`red_stop`/`amber_warn`/`protect_lamp`, the J1939-73 diagnostic lamp status
  byte) are mirrored verbatim, no timer; `checkEngine` is DM1's MIL. Firetruck is the
  control case: same chassis class, identical generated cluster, no body network — DIN
  14700/14704 (firefighting CAN) would be the right profile and is not built.
- One generated cluster for the family. Absent functions publish real zeros, never gaps.
  `engine_hours` is range-less, on the readout line beside ODO.
- INHIB doesn't simply show its signal: `body_inhibit` is true whenever the body network is
  down; `is_inhibited` takes `bus_up` so the interlock never claims an unpowered body may
  swing its arm. Dashboard suppresses INHIB while BODY BUS is dark.

### The refuse body: a second network across a gateway

The garbage truck carries a **CiA 422 "CleANopen"** body control network (EN 16815:2019),
reaching the J1939 chassis across a **CiA 413** truck gateway (413-6: J1939↔CANopen; 413-8:
generic I/O for a body to use the truck's own HMI). ISO 25200 is the protocol-agnostic
umbrella over this and the tipper trailer, named as a reference only.

Six signals, all `flavor: "cleanopen"`. In (1): `body_cmd` (Idle/Lift/Dump/Lower, `X` key).
Out (5): `body_state`, `body_pos`, `body_inhibit`, `body_bus`, `hopper_load`.

- The gateway is the content: `body_inhibit` is computed chassis-side (road speed, PTO
  state, parking brake), published on the body network; `body_bus` goes down when the body
  network loses power. `hopper_load` adds real mass to the chassis, so
  `axle_load`/`engine_load` report the payload from their own measurements. The chassis PTO
  drives the body pump: while the arm rises it loads the crank (`RefuseBody.PUMP_KW` at
  `PUMP_RATED_ENGINE_RPM`, `docs/sources.md` § PTO power), so `engine_load` and the fuel rise
  with each lift; holding and lowering, the pump stands by. Its flow, so the arm's rise, follows
  the pump's speed (`RefuseBody.pump_flow`), capped at the rated; the arm lowers on its own weight
  at the rated rate.
- **The ECM's PTO mode** holds the pump's rated speed parked (`VehicleSpec.pto_mode_rpm` 1300 on
  `garbage-truck`, a Cummins-style remote PTO preset). Its interlocks: the PTO in, the park brake
  on, at most 2 mph (`TruckTelemetry.pto_mode_engaged`), and the box in N or P
  (`Drivetrain.pto_set_rpm`, read on the gear engaged that tick, so selecting D drops it before any
  fuel reaches the wheels). It governs on the all-speed governor's law (`PedalMap.governor_fuel`)
  isochronously; the pedal raises the speed over the set speed, never under it (J1939's
  accelerator override). `measure_vehicles -- garbage-truck 60 arm` prints the cycle: the crank
  lands on the set speed without overshoot and holds it through the lift, so the arm keeps its
  rated `ARM_TRAVEL_SEC`; out of the mode it lifts on the idle's share of the flow.
- The interlock is a real refusal: while `body_inhibit` is set, the arm freezes and
  `body_cmd` is ignored. `Idle`/`Lower` and an unknown command byte all stow. `body_pos` is
  written onto the arm and read back off it (the `ball_lift()` discipline).
- No `arm` mesh means no body unit — geometry is the declaration. A front loader (no tailgate,
  no packer cycle); respawn is the only way to empty the hopper.

## The towed body: tractor unit, fifth wheel, semi-trailer

The truck family's last two variants are hand-built tractor units — cab-over (`semi`) and
North American conventional (`semi-conventional`) — each pulling one of four semi-trailers
on a real joint between two RigidBody3Ds. The cab-over carries the ISO 11992 trailer bus;
the conventional carries none.

### The joint and the trailer's wheels

- Fifth wheel = `Generic6DOFJoint3D` at the scene's `Kingpin` marker
  (`TowHost._build_joint`, `FifthWheel` profile): linear axes locked, yaw free to `YAW_LIMIT_DEG`
  jackknife stop (`FifthWheel.YAW_LIMIT_DEG`), pitch `PITCH_LIMIT_DEG`, roll `ROLL_LIMIT_DEG`. A 25% grade
  break swings the pitch within the limit (the swing is in `fifth_wheel.gd`'s comment); the rig meets one rolling or with speed, since from rest the box rig
  pulls away on 16 % at most (`docs/vehicle_measurements.md` § Gradeability).
- Yaw limit models trailer-against-cab contact, not a fifth-wheel property (plate and nose
  overlap while coupled, so collision can't arbitrate it). `Articulation.JACKKNIFE_MAX_DEG`
  is the joint's stop. Guards: `tests/test_tow_host.gd`; sizing: § Truck sizing.
- Trailer carries its own unmodified `RayWheel`s — undriven, braked, six on a tri-axle
  bogie, making `trailer_axle_load`/`trailer_abs` real numbers, ticked from
  `TowHost.tick_towing`.

### Truck sizing (derivations)

- Wheelbase is sized by the launch: the trailer pulls at the 1.05 m kingpin, a lever on the steer
  axle. A 2.10 m wheelbase lifts both steer wheels for about a second of a gear-1 launch; the shipped
  3.60 m (cab-over) and 4.40 m (conventional) keep `STEER_FLOOR_N` on each steer wheel, coupled to the
  box (P2 and P6, with ASR holding the drive axle at full grip; the floor and the figures are
  `measure_semi_launch`'s). Gate: CI runs `tools/measure_semi_launch.tscn -- <unit> strict` on both.
- Gearing: twelve ratios, the I-Shift ATO2612's steps fitted over D1 6.5 to the 0.69 overdrive
  (`docs/sources.md` § Gearing), so the governor, not the redline, sets top speed. Coupled to the
  box (`measure_vehicles -- <unit> 120 coast`; top speeds: `docs/drivetrain.md` § Engine braking
  under a fuel cut): cab-over at 1317 rpm, conventional at 1539 rpm, coast-down 0.140 / 0.161
  m/s^2. Each 1690 upshift lands at 1359-1392 rpm, clear of the 780 downshift; a floored bobtail
  skips (`docs/drivetrain.md` § The shift policy).
- Aero: the coupled cab-over + box declares 2.78 m^2 on a drawn silhouette of ~5.0 m^2 (1.92 m wide,
  box roof ~2.6 m over the road), a whole-rig Cd of 0.55 against 0.48-0.54 measured on EU
  tractor-trailers at zero yaw (ICCT 2019), and 1.27x its bobtail against ~1.2-1.4x real. A real
  rig's ~5 m^2 is the half-scale body, not the trailer's wake figure.
- Plate share: `center_of_mass.z` 3.798 puts 27 % of each trailer on the fifth wheel (a real van
  trailer: 25-30 %), ~90 % of it on the single driven axle: the 4x2's traction budget. Below the
  band the rig is grip-limited, not power-limited. Gear 1 asks ~1.5x that budget; the rig's ASR
  (`tcs_equipped`, standard beside EBS) holds the drive tyres near the grip peak while the AMT's
  clutch slips on its target (its 0-50 and standing-start grade: `docs/vehicle_measurements.md` § Launches,
  § Gradeability; without it: `docs/drivetrain.md` § Limiter at launch). These tyres carry the plate load on a
  `corner_mass` sized for the unit alone, so near a standstill their slip ratio reads over a raised
  floor, where the one-tick force cap passes their full grip at the peak (`RayWheel.slip_floor_for`).
- Front damper: `damper_bump` / `damper_rebound` 13500 / 17900 hold zeta 0.30 / 0.40 on the
  bobtail steer corner (~2.1 t), the road band's ends (`docs/handling.md` § Pitch), and 0.27 / 0.36
  coupled to the box (~2.5 t). The nose's rise at a floored take-up is the rebound's to damp.
- Rear damper: `damper_bump_rear` / `damper_rebound_rear` 24700 / 28800 hold
  zeta = c / (2 sqrt(k_rear * m)) at 0.30 (box) to 0.40 (flatbed) on the coupled rear corner
  (3.5-4.7 t) and 0.47-0.55 at the bobtail corner (1.9 t); the `GroundDriveSpec` fallback preserves
  the front's ratio at the bobtail mass instead. Laden band pinned in `test_trailer`.
- Rollover: `rollover_g = half_track / com_height_over_road`, half-track 0.72 m (the tractor's
  drive axle 0.62), is the rigid-body ceiling; a body rolls before it slides when that is under
  `mu_lat` 0.75. Springs let the body lean, which carries the COM outboard and lifts a wheel
  earlier; the anti-roll bars (`anti_roll_rate`) hold the lean. Every trailer axle carries one at
  its own spring rate (`test_trailer`), each tractor unit 480 kN/m, twice its front spring: a
  softer tractor out-leans its trailer, and past the plate's roll stop (`ROLL_LIMIT_DEG`) it twists the trailer
  over (at half that rate the flatbed's trailer lifted well below its own ceiling). A full-lock step
  (the rack reaches full lock in a fraction of a second) overshoots the roll. Measured with
  `measure_semi_launch -- semi trailer=<body>` (P7, `docs/vehicle_measurements.md` § Measure-tool
  run lines; the conventional's slow tips agree between runs to a few hundredths of a g). COM over
  road → `rollover_g`: box 1.60 m → 0.45, tanker 1.50 → 0.48, tipper 1.30 (parked) → 0.55,
  flatbed 0.90 → 0.80, tractor unit (bobtail) 1.10 (1.03 coupled) → 0.65.

  The measured tip points follow the same order. The tall bodies (box, tanker, tipper) lift a
  trailer wheel below their `rollover_g`: the lean is the trailer's, and the plate's roll stop
  hands it to the tractor. The flatbed's tractor and trailer lift together on the slow wind-on,
  and the rig rolls under its ceiling (the track, below), as the bobtail does. A held step
  (`measure_vehicles -- semi step`) stands under the trailer's slow-tip lift (P7 `ramp`) and rolls
  over it at a constant g: the inner bogie unloads, then the tractor's inner wheels, and the rig
  goes within seconds. A raised tipper puts its load about 2.8 m over the road, so a body off its
  rest caps the rig at `TowHost.BODY_UP_CAP_KMH` (`TowHost.speed_cap_kmh` into
  `Drivetrain.speed_cap_kmh`, a notice on the edge), where full lock makes almost no lateral g.

  The 1.44 m track is the compromise (a real artic runs ~2.0 m, so every ceiling reads ~25 % low);
  widening it moves every wheel station and authored wheel visual. `BaseVehicle.is_overturned()`
  and the F3 overlay report a rollover; there is no auto-reset.

### TowHost, cycling and mass

- `TowHost` (`src/vehicles/base/tow_host.gd`) is one class for truck and tractor; a
  `CouplingProfile` distinguishes fifth wheel (`FifthWheel`) from drawbar (`Drawbar`,
  `docs/tractor.md` § The drawbar). Towed half is shared too: `TowedBody` and `Articulation`,
  neither truck-specific; the tractor's drawbar and `FarmTipper` use them directly.
- Mass ratio: 8 t : 24 t shipped (3:1, the box), verified at 8 t : 25 t; `test_trailer` pins
  suspension travel per case.

### ISO 11992: brakes and running gear only

Part 2 is the application layer for brakes and running gear only, riding pins 6/7 of the
**ISO 7638** connector. All `flavor: "iso11992"` — the one signal group in the contract that is
bidirectional by design.

| Signal | Dir | What it is |
| --- | --- | --- |
| `trailer_ebs_fault` | in | Injected trailer EBS fault. Mirrored verbatim like DM1; nothing in the game ever sets it |
| `trailer_connected` | out | The coupling claim — see below |
| `trailer_axle_load` | out | SPN 582 on the towed unit. Read out of the sim: trailer's own bogie suspension force |
| `trailer_brake_demand`, `trailer_brake_applied` | out | Demand: EBS11, towing→towed, what the tractor sends this tick (`TruckTelemetry.ebs11_demand`). Applied: towed→towing, read out of the sim, the trailer's rate-limited application (`TowedBody.brake_applied`) trailing it, the least its wheels brake with |
| `trailer_abs` | out | EBS22 byte 1 bits 1-2 (R13 Annex 16 2.4.2), towed→towing. Read out of the sim: the trailer's own ABS holding a wheel at `RayWheel.ABS_SLIP` this tick |
| `trailer_vdc` | out | EBS21 byte 2 bits 1-2, VDC active. Read out of the sim: the semi-trailer's own roll-over control (`TowedBody.vdc_active`) in its full application this tick, never its test pulse; `esc_off` does not reach it. Tell-tale VDC (R13 Annex 21 2.1.6); SPN 5624 mirrors it |

- `trailer_connected` is a claim, not "something is on the fifth wheel": needs the trailer
  coupled and `VehicleSpec.trailer_bus_equipped`. False with a trailer physically attached
  is a real state — the third state `implement_connected` distinguishes: attached steel, bus
  silence.
- No `trailer_type`: ISO 11992 publishes no body type. Which trailer is on the back shows
  through mass and which tractor-side signals it moves; the tractor has `implement_type`
  because ISO 11783 carries a real device class.
- A coupled trailer draws air through the chassis' reservoir model (AIR1/AIR2 dip ~3 bar).

### SAE J2497: the North American variant

`semi-conventional` (hood ahead of cab, sleeper behind; 6.10 m long against the cab-over's 5.45 m)
is a variant of the cab-over: same `SemiTractor` script, fifth wheel, wheels, coupling plane,
drivetrain and brakes. Its content is a subtraction.

- No trailer bus, via a `VehicleSpec` flag defaulting off (`trailer_bus_equipped`, the
  `rear_diff_lockable` pattern): true on the cab-over, false here (Europe puts a CAN pair on
  pins 6/7 of ISO 7638; North America has no data pair on the connector at all).
- With a trailer coupled, `trailer_connected` reads FALSE and the other ISO 11992 outputs read
  honest zeros (the third state, above). It still tows and brakes the trailer (the pneumatic
  lines aren't the data pair); only publishing goes dark.
- `trailer_abs_lamp` (in, bool, `flavor: "j2497"`, tell-tale TRLR ABS) is the entire North
  American trailer protocol: SAE J2497/PLC4TRUCKS modulates trailer ABS status onto the
  power line — LAMP ON/OFF, mirrored verbatim.

### Four trailers, and not one new signal

| Trailer | Mass | Consumes | What it teaches |
| --- | --- | --- | --- |
| Box / curtainside | 24 000 kg | nothing | on the trailer bus it *is* the flatbed |
| Tipper / dump | 19 000 kg | chassis PTO + proportional valve | a real interlock, and a load that walks |
| Tanker | 21 000 kg | nothing | a labelled model of a shifting centre of mass |
| Flatbed | 14 000 kg | nothing | the lightest, baseline for the rest |

- What a trailer consumes is declared in code (`TowedBody.consumers()`, the `ImplementBase`
  rule); gating lives in `TowHost.tick_towing`, never the subclass.
- Every trailer control has a keyboard key and touch button: `E`/ATTACH cycles the
  combination (box → tipper → tanker → flatbed → bobtail, `TrailerCatalog`), `P`/PTO the chassis PTO (tipping pump), `I`/TIP the raise/lower valve (`H`
  horn, `Space`/HAND parking brake). Offered by capability, not family:
  `SemiTractor.attachment_controls()` reads `TowedBody.consumers()`; hides while the bridge
  drives.

#### Coupling, refusal, spawn countdown

- Coupling refuses on one thing, the rig moving (a hitch, never a drop); the fit check, spawn
  countdown and showroom freeze: `tow_host.gd`'s constants and `set_display_frozen`.
- Tipper's interlock: `TowedBody.body_raise_allowed`. Naming reference, not implemented: ISO
  25200 / CiA 408.
- Both load models move a real centre of mass and nothing else. The tipper moves it UP as well as back (the load rides the floor it is sitting on), which is
  why a raised body caps the rig at `TowHost.BODY_UP_CAP_KMH` (§ Truck sizing).
  Tanker's surge: a labelled model chasing longitudinal acceleration with a lag (travel a baffled
  tank's, lag an estimate; roll stability reads the parked load); fluid physics is a non-goal. Guards for § Coupling and
  § Four trailers: `tests/test_trailer.gd`, `tests/test_tow_host.gd`.

