# Heavy vehicles — truck, trailer & tractor

Truck, trailer and tractor each publish a second machine's state on a second network: J1939
(truck chassis + CANopen body network across a gateway), ISO 11992 (trailer bus), ISOBUS/ISO
11783 (implement bus). The framework and the other families: `docs/vehicles.md`; shared
framework/plumbing: `docs/systems.md`. Rules: `src/vehicles/truck/CLAUDE.md`,
`src/vehicles/tractor/CLAUDE.md` — this doc is the tour and the derivations.

## Truck & J1939

A chassis class, not a job: `garbage-truck`, `firetruck`, and the hand-built tractor units
(`semi`, `semi-conventional`) only; heavy vans are `car`-family, proprietary CAN. J1939 is the
parent of ISOBUS and NMEA 2000.

`TruckVehicle extends BaseVehicle` (`src/vehicles/truck/truck.gd`) owns air reservoirs, PTO,
refuse body network and the ISO 11992 trailer bus in `_tick_extras`. `TruckTelemetry extends
VehicleTelemetry` adds chassis, body-network and trailer-bus "out" fields.

### The signal set

| Signals | Flavor | Notes |
| --- | --- | --- |
| In (4): `retarder`, `red_stop`/`amber_warn`/`protect_lamp` (J1939-73 DM1 lamp bits) | `j1939` | published FMS set — J1939-71 subset six European makers agreed to expose in 2002 |
| Out (4): `air_primary`, `air_secondary`, `retarder_state`, `axle_load` | `j1939` | — |
| `engine_load`, `engine_hours`, `pto`, `pto_state` | `isobus` | reused, not duplicated — listed on `truck` alongside `tractor` (ISO 11783 is built on J1939: `engine_load` = SPN 92, `engine_hours` = SPN 247) |

`diff_lock`/`diff_lock_state` are not extended to the truck.

### Air, retarder, axle load

- Air gates the brakes: two reservoirs (SPN 1087/1088) charge while the engine runs, draw
  down per brake press (**0.70 / 0.55 bar** a full press; a held pedal draws nothing more, so
  pumping drains and holding does not); circuit 2 is smaller so the pair diverges. Below
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
  Per body, three passes: parked on 18 % with the air drained and no lever (`PARK_HOLD_S`), floored in D with the
  air drained (drive goes to gear N, no creep), and the air cut while rolling (`ROLL_SPEED_MS`)
  with the pedal floored. Every body holds within a millimetre or two and stops in roughly 10-14 m.

  Floors: `FLOOR_MAX_M` held, `ROLL_MIN_DECEL` (UN R13 secondary braking, goods vehicles). With
  the trailer left unbraked the semi settles about 2 cm onto the tractor's rears before they hold
  it (a 1.2 margin, `box_spec.tres`) and stops well under the decel floor: both fail. `park` and `floor` drain
  honestly (key off, brake pumped); `roll` writes `air_primary = 0` (a burst line, the model has
  no leak).
- Retarder is real driveline torque, not an indicator bit: math on `Drivetrain`,
  `WheelDrive` adds it to driven wheels' brake torque, `RayWheel` integrates it,
  `GroundDriveSpec.retarder_equipped` gates it to truck specs only. Can't skid the axle
  (`RETARDER_SLIP_TARGET` caps the one-tick spin change at 0.10 slip). Rated by its own
  hardware, `retarder_rating_nm` at the gearbox output, reaching each driven wheel through
  `final_drive` (`Drivetrain.retarder_rating`): flat-road retardation at the body's own mass is
  `rating * final_drive / r / m`.

  | Body | Rating at the output | Per driven wheel | Retardation |
  | --- | --- | --- | --- |
  | `garbage-truck` / `firetruck` (8 / 7.5 t) | 600 Nm, medium-duty output retarder | 1203 Nm | 0.84 / 0.89 m/s² |
  | `semi` / `semi-conventional` bobtail (8 t) | 1450 Nm, low end of the hydraulic class | 2120 Nm | 1.47 m/s² (0.81 coupled to the 24 t box, its trailer braking its share) |

  `test_truck` pins a **0.7-1.6 m/s²** band per shipped spec at its own mass (past ~1.6 an
  auxiliary brake stands in for the foot brake) and the retarder under its axle's service brake.
  A trailer is asked for the same share of its brakes (`Drivetrain.retarder_fraction`, the
  retarder's torque over the tractor's whole foot brake, 0.068 on the semis); every trailer's
  service brake is apportioned to its tractor (`box_spec.tres`), so at that shared fraction both
  ends decelerate alike. `retarder_state`
  reports torque applied, not the request (J1939 SPN 520 is negative; the contract publishes the
  magnitude).
- `axle_load` is read out of the sim: summed `RayWheel.suspension_force` on the rear axle in
  kg (SPN 582, `WheelDrive.rear_suspension_force`), never a mass lookup. `warn` **11500** is the
  EU 11.5 t drive-axle limit, `warn_side: high`. The tractor publishes it too (its rear is the
  drive axle), where it never reaches the warn.

### Lamps and the cluster

- DM1 lamps (`red_stop`/`amber_warn`/`protect_lamp`, the J1939-73 diagnostic lamp status
  byte) are mirrored verbatim, no timer; `checkEngine` is DM1's MIL. Firetruck is the
  control case: same chassis class, identical generated cluster, no body network — DIN
  14700/14704 (firefighting CAN) would be the right profile and is not built.
- One generated cluster for the family: 11 bars (FUEL, COOLANT, LOAD, AIR1, AIR2, RET, AXLE,
  ARM, HOPPER, TRLR, TBRK), 18 tell-tales, 4 state chips (KEY, LIGHTS, BODY CMD in; BODY
  out). Absent functions publish real zeros, never gaps. `engine_hours` is range-less, on
  the readout line beside ODO.
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
  `axle_load`/`engine_load` report the payload from their own measurements.
- The interlock is a real refusal: while `body_inhibit` is set, the arm freezes and
  `body_cmd` is ignored. `Idle`/`Lower` and an unknown command byte all stow. `body_pos` is
  written onto the arm and read back off it (the `ball_lift()` discipline).
- No `arm` mesh means no body unit — geometry is the declaration. Firetruck, semi and
  conventional publish honest zeros on all five body signals. A front loader (no tailgate,
  no packer cycle); respawn is the only way to empty the hopper.

## The towed body: tractor unit, fifth wheel, semi-trailer

The truck family's last two variants are hand-built tractor units — cab-over (`semi`) and
North American conventional (`semi-conventional`) — each pulling one of four semi-trailers
on a real joint between two RigidBody3Ds. The cab-over carries the ISO 11992 trailer bus;
the conventional carries none. No trailer of the four adds a signal to either.

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
  `measure_semi_launch`'s). Gate: CI runs
  `tools/measure_semi_launch.tscn -- <unit> strict` on both units.
- Gearing: gears 1-5 span the 600-2080 rpm range; 6th is a 0.69 overdrive, so the governor, not
  the redline, sets top speed. Coupled to the box (`measure_vehicles -- <unit> 120 coast`; top
  speeds: `docs/drivetrain.md` § Engine braking under a fuel cut): cab-over at 1317 rpm, conventional
  at 1539 rpm, coast-down 0.140 / 0.161 m/s^2. Upshift 1690 lands 6th at 972 rpm, clear of the
  780 downshift.
- Aero: the coupled cab-over + box declares 2.78 m^2 on a drawn silhouette of ~5.0 m^2 (1.92 m wide,
  box roof ~2.6 m over the road), a whole-rig Cd of 0.55 against 0.48-0.54 measured on EU
  tractor-trailers at zero yaw (ICCT 2019), and 1.27x its bobtail against ~1.2-1.4x real. A real
  rig's ~5 m^2 is the half-scale body, not the trailer's wake figure.
- Plate share: `center_of_mass.z` 3.798 puts 27 % of each trailer on the fifth wheel (a real van
  trailer: 25-30 %), ~90 % of it on the single driven axle: the 4x2's traction budget. Below the
  band the rig is grip-limited, not power-limited. Gear 1 asks ~1.5x that budget; the rig's ASR
  (`tcs_equipped`, standard beside EBS) holds the drive tyres near the grip peak while the AMT's
  clutch slips on its target (its 0-50 and standing-start grade: `docs/vehicle_measurements.md` § Launches,
  § Gradeability; without it: § Limiter at launch). These tyres carry the plate load on a
  `corner_mass` sized for the unit alone, so near a standstill their slip ratio reads over a raised
  floor, where the one-tick force cap passes their full grip at the peak (`RayWheel.slip_floor_for`).
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
  (the rack reaches full lock in a fraction of a second) overshoots the roll. Measured with `measure_semi_launch -- semi
  trailer=<body>` (P7: each body's own lateral g at its first wheel lift; `ramp` holds `TIP_SPEED_MS` and
  winds the lock on over `RAMP_S`, the slow tip point; the default is the step at `TIP_SPEED_MS`; `tip_kmh=`
  for the lowest step speed that rolls the rig; the conventional's slow tips agree between runs to a few hundredths of a g):

  | Body | COM over road | rollover_g |
  | --- | --- | --- |
  | Box | 1.60 m | 0.45 |
  | Tanker | 1.50 m | 0.48 |
  | Tipper | 1.30 m (parked) | 0.55 |
  | Flatbed | 0.90 m | 0.80 |
  | Tractor unit (bobtail) | 1.10 m (1.03 coupled) | 0.65 |

  The measured tip points follow the same order: the tall bodies (box, tanker, tipper) lift a
  wheel below their `rollover_g` and from the lowest step speeds, the flatbed's tractor lifts
  before its low trailer does, and the bobtail rolls on the slow wind-on. Lean is the trailer's
  (the bobtail's own). The flatbed's slow tip is its trailer's, twisted up by the plate's roll
  stop with the tractor's inner wheels following, the rig left upright; on the step its trailer
  wheels stay down and the tractor's lift. A raised tipper puts its load about 2.8 m over the
  road, so a body off its rest caps the rig at `TowHost.BODY_UP_CAP_KMH`
  (`TowHost.speed_cap_kmh` into `Drivetrain.speed_cap_kmh`, a notice on the edge), where full
  lock makes almost no lateral g.

  The 1.44 m track is the compromise (a real artic runs ~2.0 m, so every ceiling reads ~25 % low);
  widening it moves every wheel station and authored wheel visual. `BaseVehicle.is_overturned()`
  and the F3 overlay report a rollover; there is no auto-reset.

### TowHost, cycling and mass

- `TowHost` (`src/vehicles/base/tow_host.gd`) is one class for truck and tractor: coupling
  datum, joint, PTO/valve gates, spawn countdown, couple-at-speed refusal, reactive fit
  check, raise interlock, lamps, respawn, showroom freeze, camera exclusion, teardown. A
  `CouplingProfile` (joint angles, marker path, joint name, driver notices) distinguishes
  fifth wheel (`FifthWheel`) from drawbar (`Drawbar`, § below). Towed half is shared too:
  `TowedBody` (RigidBody3D on the joint's end) and `Articulation` (coupled pose, load split) —
  neither truck-specific; the tractor's drawbar and `FarmTipper` use them directly.
- `E` cycles the combination, `V` the body: box → tipper → tanker → flatbed → bobtail via
  the same duck-typed `cycle_implement()` the tractor uses (`TrailerCatalog`, `BOBTAIL` a
  real entry).
- Coupling is honest about weight (the plate share: § Truck sizing): `axle_load` reports it the
  moment you couple.
- Mass ratio: 8 t : 24 t shipped (3:1, the box), verified at 8 t : 25 t; `test_trailer` pins
  suspension travel per case.

### ISO 11992: brakes and running gear only

Part 2 is the application layer for brakes and running gear only, riding pins 6/7 of the
**ISO 7638** connector: coupling claim, demand out, ABS state back, axle load, one
injectable fault. All `flavor: "iso11992"` — the one signal group in the contract that is
bidirectional by design.

| Signal | Dir | What it is |
| --- | --- | --- |
| `trailer_ebs_fault` | in | Injected trailer EBS fault. Mirrored verbatim like DM1; nothing in the game ever sets it |
| `trailer_connected` | out | The coupling claim — see below |
| `trailer_axle_load` | out | SPN 582 on the towed unit. Read out of the sim: trailer's own bogie suspension force |
| `trailer_brake_demand` | out | EBS11, towing→towed. A report of the blend the tractor sent, and what the trailer's wheels really brake with |
| `trailer_abs` | out | EBS21, towed→towing. Read out of the sim: the trailer's own ABS holding a wheel at `RayWheel.ABS_SLIP` this tick |

- `trailer_connected` is a claim, not "something is on the fifth wheel": needs the trailer
  coupled and `VehicleSpec.trailer_bus_equipped`. False with a trailer physically attached
  is a real state — the third state `implement_connected` distinguishes: attached steel, bus
  silence.
- No `trailer_type`: ISO 11992 publishes no body type. Which trailer is on the back shows
  through mass and which tractor-side signals it moves; the tractor has `implement_type`
  because ISO 11783 carries a real device class.
- Brake demand blends foot brake with retarder arithmetically (a driveline brake acts on the
  tractor's driven axle alone, so without a share on the bus the trailer would push 8 t of
  tractor). A coupled trailer draws air through the chassis' reservoir model, dipping
  AIR1/AIR2 by ~3 bar. Both read signals are read after the trailer's wheels integrate;
  bobtail publishes a real 0/false on all four every tick (`clear_trailer_bus`).

### SAE J2497: the North American variant

`semi-conventional` — hood ahead of cab, sleeper behind, 6.10 m on a 4.40 m wheelbase
against the cab-over's 5.45 m/3.60 m — is a variant of the cab-over: same `SemiTractor`
script, frame rails, fifth wheel, wheels, coupling plane (y = 1.05), drivetrain and brake
numbers. Its content is a subtraction.

- No trailer bus, via a `VehicleSpec` flag defaulting off (`trailer_bus_equipped`, the
  `rear_diff_lockable` pattern): true on the cab-over, false here (Europe puts a CAN pair on
  pins 6/7 of ISO 7638; North America has no data pair on the connector at all).
- With a trailer coupled, `trailer_connected` reads FALSE and `trailer_axle_load`/
  `trailer_brake_demand`/`trailer_abs` read honest zeros — attached steel, bus silence. It
  still tows and brakes the trailer (the pneumatic lines aren't the data pair); only
  publishing goes dark.
- `trailer_abs_lamp` (in, bool, `flavor: "j2497"`, tell-tale TRLR ABS) is the entire North
  American trailer protocol: SAE J2497/PLC4TRUCKS modulates trailer ABS status onto the
  power line — LAMP ON/OFF, mirrored verbatim.

### Four trailers, and not one new signal

Read the ISO 11992 table from the other side: the bus carries nothing about the body, so
mass, what plugs into the towing unit, and which tractor-side signals move are what tell
them apart.

| Trailer | Mass | Consumes | What it teaches |
| --- | --- | --- | --- |
| Box / curtainside | 24 000 kg | nothing | on the trailer bus it *is* the flatbed |
| Tipper / dump | 19 000 kg | chassis PTO + proportional valve | a real interlock, and a load that walks |
| Tanker | 21 000 kg | nothing | a labelled model of a shifting centre of mass |
| Flatbed | 14 000 kg | nothing | the lightest, baseline for the rest |

- What a trailer consumes is declared in code (`TowedBody.consumers()`, the `ImplementBase`
  rule); gating lives in `TowHost.tick_towing`, never the subclass.
- Every trailer control has a keyboard key and touch button: `E`/ATTACH cycles the
  combination, `P`/PTO the chassis PTO (tipping pump), `I`/TIP the raise/lower valve (`H`
  horn, `Space`/HAND parking brake). Offered by capability, not family:
  `SemiTractor.attachment_controls()` reads `TowedBody.consumers()`; hides while the bridge
  drives.

#### Coupling, refusal, spawn countdown

- Coupling refuses on one thing, the rig moving; the fit check is reactive
  (`TowHost._watch_fresh_coupling`, `COUPLE_WATCH_TICKS`): "NO ROOM FOR A TRAILER - PULL
  FORWARD" if the trailer body touches anything. Applies to a hitch, not a drop
  (`TowHost.COUPLE_SPEED_MS` wants a standstill; a drop is never refused).
- Spawn coupling is a plain countdown (`SPAWN_COUPLE_TICKS`, **12**), buying the moment the
  chassis has risen on its own suspension. Garage freezes the trailer with the tractor
  (`set_display_frozen`).
- Tipper's interlock is chassis state, evaluated by the tractor:
  `TowedBody.body_raise_allowed(speed, parking_brake)` wants parking brake set and
  standstill, refuses the raise direction only. Naming reference, not implemented: ISO 25200
  / CiA 408.
- Both load models move a real centre of mass and nothing else. `set_load_offset` moves
  the body's `center_of_mass`; `trailer_axle_load`/`axle_load` move as consequences. The
  tipper moves it UP as well as back (the load rides the floor it is sitting on), which is
  why a raised body caps the rig at `TowHost.BODY_UP_CAP_KMH` (§ Truck sizing).
  Tanker's surge is a labelled model chasing longitudinal acceleration with a lag — real
  fluid physics is a non-goal, the rule that governs the boat's water too. Guards for § Coupling and
  § Four trailers: `tests/test_trailer.gd`, `tests/test_tow_host.gd`.

## Tractor, implement & ISOBUS

**Twenty ISOBUS signals, all `flavor: "isobus"`**, the widest cluster in the game. In (7):
`hitch_pos`, `pto`, `pto_mode` (540/1000), `diff_lock`, `fwd_drive`, `guidance_curvature`,
`scv_flow`. Out (13): `hitch_pos_actual`, `pto_state`, `pto_rpm`, `engine_load`,
`implement_connected`, `implement_type`, `diff_lock_state`, `fwd_drive_state`,
`wheel_speed`, `ground_speed`, `wheel_slip`, `engine_hours`, `draft_force`. It also publishes
the truck's `j1939` `axle_load`: lifting an implement moves its weight onto the rear axle.

- One body, five swappable attachments, on two connections. The drivable tractor is a single
  variant (`kenney/tractor-kenney.tscn`); `E` cycles the attachment — spreader → plough →
  power harrow → mower → drawbar tipping trailer → detached — each teaching one of the five
  real tractor↔implement connections (three-point linkage, drawbar, PTO, SCV hydraulic
  remote, ISOBUS data). Absent functions publish a real zero, never a gap.
- `TractorVehicle extends BaseVehicle` (`src/vehicles/tractor/tractor.gd`) owns hitch/PTO/
  implement state in `_tick_extras`. Spawn: raised, PTO off, implement attached; respawn
  re-raises but keeps the implement. `TractorTelemetry extends VehicleTelemetry` adds the
  ISOBUS "out" fields; `engine_load` is a modeled honest value (`engine_load_pct`), the rest
  read straight out of the sim.

### The signals that change how it drives

- `diff_lock` locks the rear pair onto one shaft speed: an unbounded `Differential` coupling in
  `WheelDrive._couple_differentials`. `fwd_drive` is MFWD: it rewrites the front wheels'
  `driven` flag each tick, and while engaged the spec's `centre_diff_rigid` ties the front axle's
  mean speed to the rear's, a geared transfer with no centre diff. Both requests gate on
  `GroundDriveSpec` flags (`rear_diff_lockable`, `front_axle_engageable`), which are true only on
  the tractor's spec. Both axles stay open inside, so 2WD with the lock off is still the open
  rear diff. The transfer runs the kinematic ratio, `r_rear / r_front` = 1.5 (`WheelDrive`'s shaft
  frame). Rejected: a lead past the kinematic ratio; with exact radii it is straight-line wind-up,
  not feel.
- `wheel_speed`/`ground_speed`/`wheel_slip` are the signature ISO pair and its difference:
  wheel-based is the mean spin of the rear axle × tire radius; ground-based is chassis
  forward velocity; `wheel_slip` is how far the first runs ahead of the second (unsigned,
  J1939 SPN 1858, floored at low speed).
- `pto_mode` is a gearbox selection, not an engine speed: 540/1000 are shaft speeds off
  `PTO_RATED_RPM` (**2200**); an unknown byte falls back to 540. `engine_hours` is an hour
  meter, range-less, on the readout line beside ODO.
- `guidance_curvature` is auto-steer (the boat's `rudder` precedent): present, it overrides
  `steer`, arbitrated only in `InputRouter.arbitrate_bridge`. `bridge_source.gd` maps the
  contract's ±127 1/km onto the ±1 steer channel; 0 is a real held command, not an absence.
- `scv_flow` is a hydraulic remote reaching the spreader's hopper gate ram
  (`ThreePointHitch.set_scv`) and the tipping trailer's ram (`Drawbar.set_scv`);
  engine-driven, so a stopped engine means no flow. Local key `Q` (owner `InputRouter._scv`,
  the `_pto` pattern) — binary, not proportional; the truck's `retarder` stays keyless.

### Draft, hitch, linkage

- Draft is a real force: with a draft-relevant implement (plough, power harrow) down in the
  ploughable field, `TractorVehicle._apply_draft` puts a rearward force at the hitch point
  (`TractorTelemetry.draft_newtons`): the implement's own rating × working depth × soil × ASABE
  D497's speed factor at the hitch's speed (`ImplementBase.draft_rating` / `draft_shape`, held at
  the top of its speed range) × a fade to 0 below `DRAFT_V_CRAWL`. `draft_max_force`, the 100 % end
  of `draft_force`, is the plough's rating. The level's light bands paint soil 0.5; D497's
  coarse-to-medium texture ratio is 0.64.
  `engine_load`, rpm sag and `wheel_slip` move as consequences. Lift comes from
  `ThreePointHitch.ball_lift()`; working depth is the implement's own
  (`ImplementBase.tool_depth` — plough 0.25 m, harrow tines 0.10 m). "In soil" is
  `Surface.FIELD`, in whichever channel a level paints it (`HeightmapTerrain.surface_weight_at`).
- `ThreePointHitch` (`src/vehicles/tractor/three_point_hitch.{gd,tscn}`) is tractor anatomy,
  whole with nothing attached. `HitchLinkage` (pure math, tested) solves the side view as a
  four-bar — implement pitch and rockshaft arm angle fall out of a circle-circle
  intersection, why implements tip back as they lift.
- Draft 60 Hz margin: below `DRAFT_V_CRAWL` the draft is a linear damper on the hitch point's
  speed, which meets the effective mass `m_eff` (the body plus the pitch the hitch's arm turns,
  `TractorVehicle.hitch_effective_mass`), stable while `k*dt/m_eff < 2`
  (`test_the_shipped_draft_keeps_the_60hz_damper_margin_on_the_hitch` holds it under 0.5). The
  one-tick cap behind it, `m_eff · |v_hitch| / dt`, bounds the angular impulse with the linear one.
- Weight: the linkage's carried share of an implement folds into the chassis' live mass and COM
  (`TractorVehicle._apply_implement_mass`, `VehicleMath.carried_com`). At the bottom stop the
  ground carries `ground_share()` (depth wheel, roller, tail wheel), handed to the linkage across
  `support_lift()` (`ImplementBase.carried01`); the spreader never touches, so attaching it, not
  lifting it, moves its load. Raised, the plough and the harrow take the front under John Deere's
  ballasting minimum, ≥ 20 % of total weight on the front axle: reported, not enforced; that is
  what front weights fix. `measure_vehicles -- tractor-kenney 20 hitch`, parked, per-axle kg off the
  springs (computed 2026-10-16; every reading within 1.6 % of the statics `m e / L`):

  | Implement | Front / rear, bottom stop | Front / rear, raised | Front share, raised |
  |---|---|---|---|
  | none | 2655 / 4345 | | 37.9 % |
  | Plough | 1843 / 5742 | 1452 / 6448 | 18.4 % |
  | Power harrow | 2419 / 4891 | 1538 / 7012 | 18.0 % |
  | Rotary mower | 2283 / 5069 | 2027 / 5593 | 26.6 % |
  | Spreader, full | 1987 / 5916 | 2141 / 5761 | 27.1 % |

  Carried full, the spreader barely moves the handling: the full-lock circle and the step-steer yaw
  rates stay within a few percent of bare, the yaw index read off the tensor 1.06 against 0.96. The
  light front shows as no extra understeer in the linear range (`20 circle`, `20 step`, with and
  without `trailer=spreader`).
  Held on full soil (`20 plough`), the measured draft sits on D497 at each speed held, to 0.0 %.
  The harrow holds each of the pass's speeds. The plough holds the slowest at 15 % slip; stepped to
  the reference speed on the open diff, the right rear, lighter under the plough's left-of-centre
  mass, peels past the slip peak and the tractor settles about a third under it, 42 % slip, in D1
  on the governor. Floored from rest it peels the same way (~50 %, then 42 %). Ramped in as a
  driver does (`20 plough course`), the course's reference-speed run reads `engine_load` 62 % on
  full soil and 43 % on the light bands, inside tractor_plough's 25-70 %. The lug's grip in soil
  (0.60 of asphalt, `ag_lug.tres`) is an estimate, and D497's own traction at the slip peak is
  lower still (0.49): an open-diff 2WD tractor ploughing is traction-limited, and the diff lock or
  MFWD is the answer, as a ploughing driver engages it.
  Not modelled: draft control (the Ferguson hitch), a spreader that empties, a composite inertia
  declaration, front ballast as an attachment, a start gear that reads draft, skid drag.
- Ground support is drawn, not simulated: `ThreePointHitch` keeps two poses. Physics (ball lift,
  hitch point, implement COM) reads the commanded solve on flat ground; the drawn pose floats the
  implement up until its `support_points()` meet the ground under them
  (`HitchLinkage.float_pos`, one ray per point while lowered), as a linkage in float does. A float
  moves no weight or draft depth, and a dip under the support leaves the implement on its stop.
  The drawn pose chases that contact through a critically damped follower, stiff into the ground
  and soft out of it (`ThreePointHitch.FLOAT_OMEGA_UP` / `_DOWN`): copied tick by tick, the
  implement jumped every facet of the 8-bit heightmap and landed on its stop dead.
- Ballast: gear-1 wheel force at `Drivetrain.launch_target_rpm` is about 1.5x the rear grip at 7 t /
  `front_weight` 0.38 (about 3.4x unballasted at 4 t 50/50). Top
  speed in 6th is rpm-bound, so ballast moves only acceleration and grade climb.
- Launch: a powershift's, not a car's, in its start gear (`ShiftPolicy.start_gear`, up to
  `start_gear_max` D3). A powershift's start gear is a driver preset, higher for an empty run and
  lower with a load; here the load standing on the grade picks it, as the I-Shift picks its own
  from gross weight and gradient: the highest gear whose launch drive (the curve at the launch line
  on the pedal's fuel) beats the grade's pull plus the rolling and soil resistance on the whole rig
  by `ShiftPolicy.START_RESERVE` (2, an estimate). Picked at full pedal while the tractor stands, it
  steps down through the launch to what the driver's pedal holds (a pedal of 0.6 with the tipper on
  8 % takes D1 at once), and down again if the launch has not moved after the ramp and a dwell
  (the dwell). Computed picks (`test_tractor`): D3 empty on the flat or on flat mud; D2 with the tipper
  on 10 %; D1 with the tipper on mud, and on the 26 % mud climb.
- The pack's capacity ramps to its rating over `launch_engage_s` while the controller slips
  it toward the launch line, which holds a floored start near the grip peak (with the whole rating
  on the first tick the rears flash to heavy slip and the front axle unloads almost entirely); while
  the ramp is short of the engine's torque the crank flares over the line. The
  close onto the wheels is a handover over `shift_handover_s`, never the rating: closed at
  the rating, a held D3 poured the flare into the wheels in a tick (a spike of g, the front axle
  unloaded), and a held D2 flashed its rears into slip.
- Flat strip (`measure_vehicles -- tractor-kenney 12 trace=3 trace_s=2`):
  - bobtail: D3, a clean close at about a second carrying the engine's torque, then D4-D6 in
    quick succession; rear slip low, front axle kept loaded;
  - with the farm tipper: D3, D4-D6 spread over several seconds; rear slip low, front axle kept
    loaded, no gear shorter than about a second.
  - The bobtail's D4 is the shortest gear: at full pedal the policy never holds an upshift, so on the
    1.35 steps the dwell is the gearing's (brief 16, `docs/plans/mechanical_update/16_drivetrain_control.md`).
- Standing starts: `docs/vehicle_measurements.md` § Gradeability, `docs/drivetrain.md` § Hill hold; with the tipper on 10 %
  asphalt it starts in D2 and starts moving within a couple of seconds.
- Reverse is the bus's single R byte, at D3's ratio; its top speed follows from that ratio and the governor.
- Steady draft does not involve COM height: drag at the hitch and tyre reaction at ground form a
  couple of `F × h_hitch`, a few kN off the static front load. The 0.83 m COM (`com_y_frac` 0.32:
  the bare machine's 0.91 m with 1.5 t of liquid and hub ballast at ~0.55 m) matters for
  transients and for rollover: over the 0.85 m mean half-track (1.62 / 1.79 m track, a real
  tractor's) the static threshold is about 1 g, at the lug tyres' slide. Measured at
  speed (`measure_semi_launch`'s tractor runs): the slow wind-on and a full-lock step steer both
  run the fronts wide with only a few degrees of roll; on the 1.31 / 1.49 m track the same two runs
  overturned.
- Body scale 1.35 (2.99 × 2.17 m, 2.12 m wheelbase). It rides on its drawn tyres, 0.44 m front /
  0.66 m rear. Suspension is the tyres: 330 / 420 kN/m, `rest_length` 0.12 m, ~33 / 42 % static sag.
  A side jolt at speed rolls a couple of degrees and rebounds a fraction of it (roll damping ratio
  ~0.37); the narrow track rolls further and rebounds more.

### What an implement declares

`ImplementBase` (`implement_base.gd`) declares which of the five connections it uses, its
ISO 11783-1 device class, its A-frame (`mast_offset`), whether it works in soil
(`draft_relevant()`) and reach lowered (`tool_depth()`), its draft (`draft_rating()` at
`TractorTelemetry.DRAFT_S_REF_KMH`, full depth and soil; `draft_shape()`, D497's A, B, C and the top
of its speed range), and its mass, centre, ground share and the `support_points()` it rests on.
Implements are visual only — no CollisionShape, no joint; their weight reaches the chassis as live
mass and COM (`TractorVehicle._apply_implement_mass`). The declared connections are load-bearing:
`ISOBUS_DATA` decides whether `implement_connected`/ `implement_type` report anything; `PTO`/`SCV`
decide whether
drive/flow reach the machine. Attach/detach is a logical address claim — `ImplementCatalog`
holds the cycle order with DETACHED a real entry; `E` cycles it via duck-typed
`cycle_implement()`.

### The four implements

`src/vehicles/tractor/implements/`, each a different connection set and a device class no
other machine may share (`test_implement_catalog`):

| Implement, drawn class | Connections | `implement_type` | Draft depth | Moving part |
|---|---|---|---|---|
| Plough, 4 × 14" | three-point, bus | 2 tillage | 0.25 m | gauge wheel arm swings on lift |
| Power harrow, 3.0 m | + PTO | 3 secondary tillage | 0.10 m | tine rotor, transverse axis |
| Rotary mower, 7 ft | + PTO | 9 forage | none | rotor, vertical axis |
| Fertilizer spreader, ~800 L | + PTO, SCV | 5 fertilizer | none | disc + `scv_flow` hopper gate |

Their masses, ground shares and draft ratings: `docs/sources.md`.

And the fifth cycle entry, none of the above (§ drawbar below):

| Attachment | Connections | `implement_type` | Draft | Moving part |
|---|---|---|---|---|
| Drawbar tipping trailer | drawbar, SCV | 0 none (no bus claim) | none | tipping body + tailgate on one ram |

Each is authored lowered with the origin on the lower pin line (ground y = −0.21). Shared
A-frame: `implements/headstock.tscn`. PTO-driven visuals go through
`ImplementBase.spin_from_pto`, whose `ratio` is cosmetic (540 rev/min would alias at 60
fps); the published `pto_rpm` stays honest. Level 1's centre is the ISOBUS farm playground:
painted field (soil for `draft_force`, with two light sandy-loam bands at half soil so
`engine_load` moves along a pass), mud wallow (`diff_lock`), haul ramp (`fwd_drive`), implement
yard. See `docs/level_kit.md`.

## The drawbar: the connection that only pulls

The fifth cycle entry is not an implement. `farm_tipper.tscn` is a 10 t towed body on a real
`Generic6DOFJoint3D`, standing on its own unmodified `RayWheel`s, the same `TowedBody` the
semi-trailers use. The tractor side is the same `TowHost` the semi's fifth wheel is:
`Drawbar` (`src/vehicles/tractor/drawbar.{gd,tscn}`) is a `TowHost` carrying a drawbar
`CouplingProfile` and the pin's own geometry, nothing else. Rationale: `tractor/CLAUDE.md`.

- A drawbar only pulls: with the trailer hitched, `I` still raises/lowers the empty
  three-point linkage and `hitch_pos_actual` still reports the whole stroke; `draft_force`
  reads a clean zero.
- The two couplings are the same code, not two implementations. What stays on the vehicle:
  the brake demand (semi blends foot brake with its own retarder; tractor plain pedal); the
  spool source (`input.scv_flow` gated on `running` here, `1.0 - input.hitch_request` on the
  truck); the attachment catalog; the semi's ISO 11992 publish and trailer air draw; camera
  framing.

### Pin, datum, profile

- Pin is fixed, not swinging (`Drawbar.PIN_LOCAL`, runtime reads the `Pin` marker). Coupling
  datum is 0.40 m, not the semi's 1.05 m (a fifth-wheel plate height); trailer origin is at
  the drawbar eye, ground at y = −0.40.
- Joint differs from a fifth wheel on three axes: pitch `Drawbar.PITCH_LIMIT_DEG` (fifth wheel's cover-the-grade
  rule); yaw `Drawbar.SWING_MAX_DEG` (not `Articulation.JACKKNIFE_MAX_DEG` — the
  trailer's front corners meet the rear tyres just past it); roll `Drawbar.ROLL_LIMIT_DEG` against the semi's
  `FifthWheel.ROLL_LIMIT_DEG` (a pin through an eye doesn't lever the tractor over on a rut).
- A drawbar carries a nose weight, not a share: 12% against the fifth wheel's 27%.
- **Laden on 10 % mud the rig is traction-bound.** That is `measure_grade -- tractor-kenney rollback
  grade=10 mud mfwd tipper verbose`: it first moves 0.1 m forward only after several seconds, the same from any
  start gear and with or without the hold.
  - What it asks: the 17 t combination needs the grade pull plus mud's 0.2 drag on the whole
    load (weight x (grade + 0.2)).
  - What it has: the MFWD tractor's 8.2 t (7 t plus the 1.2 t nose) grips less than that at the
    peak. Floored, all four tyres spin at a slip ratio well past the peak and carry less still.
  - The tipper's own brake is off shortly after the start, and its tyres carry nothing. The
    drawbar pulls its grade share plus its share of the drag.
  - The rig crawls instead of standing, because the drag's per-tick cap
    (`RayWheel.surface_drag_force`, a 60 Hz clamp) shrinks with speed.

  A real 7 t tractor with 10 t on a 10 % mud bank sticks too.

### Tipping, collision, refusal

- Tip runs off the SCV, not a PTO (the truck's tipping semi-trailer declares `Consumer.PTO`
  because a truck has no hydraulic remotes; a tractor already carries the pump). Raise
  interlock is `TowedBody.body_raise_allowed` unchanged.
- Collision for the raised body is two authored poses and one swap, with hysteresis
  (re-transforming a `CollisionShape3D` at 60 Hz would rebuild the compound/inertia tensor
  on a body already writing its own centre of mass).
- `E` refuses only for a press that hitches (the tractor moving); dropping the trailer lays
  nothing. Level 1's first `E` at the tractor spawn is refused by the fit check (scenery close
  behind): that is the check working; pull forward.
