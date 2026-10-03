# Heavy vehicles — truck, trailer & tractor

Truck, trailer and tractor each publish a second machine's state on a second network: J1939
(truck chassis + CANopen body network across a gateway), ISO 11992 (trailer bus), ISOBUS/ISO
11783 (implement bus). The other four families: `docs/vehicles.md`; shared
framework/plumbing: `docs/systems.md`. Rules: `src/vehicles/truck/CLAUDE.md`,
`src/vehicles/tractor/CLAUDE.md` — this doc is the tour and the derivations.

## Truck & J1939

The truck family covers a J1939 chassis, a CANopen body network across a gateway, a thin
truck/trailer bus, and (on one variant) no trailer bus at all. It is a chassis class, not a
job: `garbage-truck`, `firetruck`, and the two hand-built tractor units (`semi`,
`semi-conventional`) only — ordinary heavy vans (delivery, delivery-flat, ambulance) are
`car`-family, proprietary CAN, not J1939. J1939 is the parent of both ISOBUS and NMEA 2000.

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
  and the truck can't move; `warn` (**5 bar**) is a band to stop in first. Gate reads the
  minimum of the two circuits; losing air has no ramp. Rationale:
  `truck/CLAUDE.md` § Brakes, retarder, air.
- Retarder is real driveline torque, not an indicator bit: math on `Drivetrain`,
  `WheelDrive` adds it to driven wheels' brake torque, `RayWheel` integrates it,
  `GroundDriveSpec.retarder_equipped` gates it to truck specs only. Can't skid the axle
  (`RETARDER_SLIP_TARGET` caps the one-tick spin change at 0.10 slip). Rated at
  `RETARDER_MAX_FRAC` **0.20** of per-wheel `brake_torque`. `test_truck` asserts brake >
  retarder and a **0.7-1.6 m/s²** band per shipped spec — the floor tracks the tyre, a retarder
  that is a fraction of a grip-derived brake being worth what the grip is worth: on a
  grip-derived brake mass and radius cancel, so flat-road retardation is
  `RETARDER_MAX_FRAC * BRAKE_GRIP_FRAC * mu_long * g / 2` = 0.745 m/s² at truck-tyre `mu_long`
  0.80. The hand-built units' fixed 10500 Nm brake retards at 1.46 m/s² whatever the mu; the
  1.6 ceiling is what caps their `brake_torque`. `retarder_state`
  reports torque applied, not the request (J1939 SPN 520 is negative; the contract publishes the
  magnitude).
- `axle_load` is read out of the sim: summed `RayWheel.suspension_force` on the rear axle in
  kg (SPN 582), never a mass lookup. `warn` **11500** is the EU 11.5 t drive-axle limit,
  `warn_side: high`.

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
Out (5): `body_state`, `body_pos`, `body_inhibit`, `body_bus`, `hopper_load`. Rationale:
`truck/CLAUDE.md` § Refuse body.

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
  (`TowHost._build_joint`, `FifthWheel` profile): linear axes locked, yaw free to **75°**
  jackknife stop, pitch **±15°**, roll **±1.5°**. A 25% grade break swings it -9.0° to
  +12.8° (15° clears it); the rig meets one rolling or with speed, since from rest the box rig
  pulls away on 16 % at most (`docs/vehicles.md` § Gradeability). Kinematic fallback
  (`Articulation`) is written/tested but not taken — deaf to trailer-side forces.
- Yaw limit models trailer-against-cab contact, not a fifth-wheel property (plate and nose
  overlap while coupled, so collision can't arbitrate it). `Articulation.JACKKNIFE_MAX_DEG`
  (**75°**) serves both joint and fallback. Rules: `truck/CLAUDE.md` § Fifth wheel, mass,
  axle loads; sizing: § Truck sizing.
- Trailer carries its own unmodified `RayWheel`s — undriven, braked, six on a tri-axle
  bogie, making `trailer_axle_load`/`trailer_abs` real numbers, ticked from
  `TowHost.tick_towing`.

### Truck sizing (derivations)

- Wheelbase is sized by the launch: the trailer pulls at the 1.05 m kingpin, a lever on the steer
  axle. A 2.10 m wheelbase lifts both steer wheels for ~1 s of a gear-1 launch; the shipped
  3.60 m (cab-over) and 4.40 m (conventional) keep >= 8.5 kN on each steer wheel (9.0 and
  12.7 kN coupled to the box, P2 and P6, 2026-10-02). Gate: CI runs
  `tools/measure_semi_launch.tscn -- <unit> strict` on both units.
- Gearing: gears 1-5 span the 600-2080 rpm range; 6th is a 0.69 overdrive, so the governor, not
  the redline, sets top speed. Coupled to the box, measured 2026-10-02 (`measure_vehicles -- <unit>
  coast`): cab-over 88.4 km/h at 1323 rpm, conventional 103.1 km/h at 1544 rpm, coast-down 0.129 /
  0.153 m/s^2. Upshift 1690 lands 6th at 972 rpm, clear of the 780 downshift.
- Aero: the coupled cab-over + box declares 2.78 m^2 on a drawn silhouette of ~5.0 m^2 (1.92 m wide,
  box roof ~2.6 m over the road), a whole-rig Cd of 0.55 against 0.48-0.54 measured on EU
  tractor-trailers at zero yaw (ICCT 2019), and 1.27x its bobtail against ~1.2-1.4x real. A real
  rig's ~5 m^2 is the half-scale body, not the trailer's wake figure (checked 2026-10-03).
- Plate share: `center_of_mass.z` 3.798 puts 27 % of each trailer on the fifth wheel (a real van
  trailer: 25-30 %), ~90 % of it on the single driven axle: the 4x2's traction budget. Below the
  band the rig is grip-limited, not power-limited.
- Rear damper: `damper_bump_rear` / `damper_rebound_rear` 24700 / 28800 hold
  zeta = c / (2 sqrt(k_rear * m)) at 0.30 (box) to 0.40 (flatbed) on the coupled rear corner
  (3.5-4.7 t) and 0.47-0.55 at the bobtail corner (1.9 t); the `GroundDriveSpec` fallback preserves
  the front's ratio at the bobtail mass instead. Laden band pinned in `test_trailer`.
- Rollover: `rollover_g = half_track / com_height_over_road`, half-track 0.72 m (the tractor's
  drive axle 0.62), is the rigid-body ceiling; a body rolls before it slides when that is under
  `mu_lat` 0.75. Springs let the body lean, which carries the COM outboard and lifts a wheel
  earlier; the anti-roll bars (`anti_roll_rate`) hold the lean. Every trailer axle carries one at
  its own spring rate (`test_trailer`), each tractor unit 480 kN/m, twice its front spring: a
  softer tractor out-leans its trailer, and past the plate's ±1.5° roll stop it twists the trailer
  over (at 240 kN/m the flatbed's trailer lifted at 0.42 g). A full-lock step (the rack reaches
  full lock in 0.56 s) overshoots the roll. Measured 2026-10-02 with `measure_semi_launch -- semi
  trailer=<body>` (P7: each body's own lateral g at its first wheel lift; `ramp` holds 40 km/h and
  winds the lock on over 20 s, the slow tip point; the default is the step at 40 km/h; `tip_kmh=`
  for the lowest step speed that rolls the rig; the conventional's slow tips read within 0.03 g):

  | Body | COM over road | rollover_g | slow tip | lean at 0.2 g | step at 40 km/h lifts at | full-lock step rolls from |
  | --- | --- | --- | --- | --- | --- | --- |
  | Box | 1.60 m | 0.45 | 0.35 g | 1.7° | 0.38 g | 25 km/h |
  | Tanker | 1.50 m | 0.48 | 0.38 g | 1.6° | 0.41 g | 30 km/h (lifts at 25) |
  | Tipper | 1.30 m (parked) | 0.55 | 0.45 g | 1.3° | 0.41 g | 30 km/h (lifts at 25) |
  | Flatbed | 0.90 m | 0.80 | 0.50 g | 0.8° | 0.53 g | 60 km/h (lifts at 25) |
  | Tractor unit (bobtail) | 1.10 m (1.03 coupled) | 0.65 | slides at ~0.55 g | 0.5° | 0.69 g | 35 km/h |

  Lean is the trailer's (the bobtail's own). The flatbed's slow tip is its trailer's, with the
  tractor's inner wheels following at 0.53 g. A raised tipper puts its load 2.80 m over the road
  (~0.26 g), so a body off its rest caps the rig at 5 km/h (`TowHost.speed_cap_kmh` into
  `Drivetrain.speed_cap_kmh`, a notice on the edge), where full lock makes ~0.03 g.

  The 1.44 m track is the compromise (a real artic runs ~2.0 m, so every ceiling reads ~25 % low);
  widening it moves every wheel station and authored wheel visual. `BaseVehicle.is_overturned()`
  and the F3 overlay report a rollover; there is no auto-reset.

### TowHost, cycling and mass

- `TowHost` (`src/vehicles/base/tow_host.gd`) is one class for truck and tractor: coupling
  datum, joint, PTO/valve gates, spawn countdown, couple-at-speed refusal, reactive fit
  check, raise interlock, lamps, respawn, showroom freeze, camera exclusion, teardown. A
  `CouplingProfile` (joint angles, marker path, joint name, driver notices) distinguishes
  fifth wheel (`FifthWheel`) from drawbar (`Drawbar`, § below). Towed half is shared too:
  `TowedBody` (RigidBody3D on the joint's end) and `Articulation` (coupled pose, load split,
  kinematic fallback) — neither truck-specific; the tractor's drawbar and `FarmTipper` use
  them directly.
- `E` cycles the combination, `V` the body: box → tipper → tanker → flatbed → bobtail via
  the same duck-typed `cycle_implement()` the tractor uses (`TrailerCatalog`, `BOBTAIL` a
  real entry).
- Coupling is honest about weight: trailer COM sits between kingpin and bogie, 27% rests on
  the plate (a real van trailer's 25-30%), landing on the tractor's single driven axle.
  `axle_load` reports it the moment you couple.
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
  why a raised body caps the rig at 5 km/h (§ Truck sizing).
  Tanker's surge is a labelled model chasing longitudinal acceleration with a lag — real
  fluid physics is a non-goal, the rule that governs the boat's water too. Rationale for all
  of § Coupling and § Four trailers: `truck/CLAUDE.md` §§ ISO 11992 trailer bus / Four
  trailers.

## Tractor, implement & ISOBUS

**Twenty ISOBUS signals, all `flavor: "isobus"`**, the widest cluster in the game. In (7):
`hitch_pos`, `pto`, `pto_mode` (540/1000), `diff_lock`, `fwd_drive`, `guidance_curvature`,
`scv_flow`. Out (13): `hitch_pos_actual`, `pto_state`, `pto_rpm`, `engine_load`,
`implement_connected`, `implement_type`, `diff_lock_state`, `fwd_drive_state`,
`wheel_speed`, `ground_speed`, `wheel_slip`, `engine_hours`, `draft_force`.

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
  rear diff.
- `wheel_speed`/`ground_speed`/`wheel_slip` are the signature ISO pair and its difference:
  wheel-based is the mean spin of the rear axle × tire radius; ground-based is chassis
  forward velocity; `wheel_slip` is how far the first runs ahead of the second (unsigned,
  J1939 SPN 1858, floored below 0.5 km/h).
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
  (rated draft × working depth × soil × speed ramp, `TractorTelemetry.draft_newtons`).
  `engine_load`, rpm sag and `wheel_slip` move as consequences. Lift comes from
  `ThreePointHitch.ball_lift()`; working depth is the implement's own
  (`ImplementBase.tool_depth` — plough 0.055 m, harrow tines 0.02 m). "In soil" is splat
  channel 4 via `HeightmapTerrain.channel_weight_at`.
- `ThreePointHitch` (`src/vehicles/tractor/three_point_hitch.{gd,tscn}`) is tractor anatomy,
  whole with nothing attached. `HitchLinkage` (pure math, tested) solves the side view as a
  four-bar — implement pitch and rockshaft arm angle fall out of a circle-circle
  intersection, why implements tip back as they lift.
- Draft 60 Hz margin: below `DRAFT_SPEED_REF` the draft is a linear damper, `k = rated /
  DRAFT_SPEED_REF`, stable while `k*dt/m < 2`; 12 kN on 5.5 t gives 0.018
  (`test_the_shipped_rating_keeps_the_60hz_damper_margin` holds it under 0.5). The one-tick
  `damped_force` cap behind it is unreachable below ~480 kN and bounds only the linear impulse.
- Ballast: gear-1 wheel force at `converter_free_rpm` (1250 rpm, ~682 Nm) is ~65.7 kN against
  33 kN of rear grip at 5.5 t / `front_weight` 0.38 (~2.0x; 3.4x at the unballasted 4 t 50/50).
  Top speed in 6th is rpm-bound, so ballast moves only acceleration and grade climb.
- Steady draft does not involve COM height: drag at the hitch and tyre reaction at ground form a
  couple of `F × h_hitch`, a few kN off a ~20 kN static front. The 0.91 m COM (`com_y_frac` 0.35)
  matters for transients and for the ~0.78 g side-slope rollover (0.70 m mean half-track, lug mu
  1.0): the tractor tips before it slides.
- Body scale 1.35 (2.99 × 2.17 m, 2.12 m wheelbase). Visual radii 0.44 front / 0.66 rear over a
  0.36 physics radius, so the rear tyre stands 0.30 m proud of its contact and clips a kerb first.
  Suspension is the tyres: 260 / 300 kN/m, `rest_length` 0.12 m, ~31 % static sag.

### What an implement declares

`ImplementBase` (`implement_base.gd`) declares which of the five connections it uses, its
ISO 11783-1 device class, its A-frame (`mast_offset`), whether it works in soil
(`draft_relevant()`) and reach lowered (`tool_depth()`). Implements are visual only — no
CollisionShape, no joint. The declared connections are load-bearing: `ISOBUS_DATA` decides
whether `implement_connected`/ `implement_type` report anything; `PTO`/`SCV` decide whether
drive/flow reach the machine. Attach/detach is a logical address claim — `ImplementCatalog`
holds the cycle order with DETACHED a real entry; `E` cycles it via duck-typed
`cycle_implement()`.

### The four implements

`src/vehicles/tractor/implements/`, each a different connection set and a device class no
other machine may share (`test_implement_catalog`):

| Implement | Connections | `implement_type` | Draft | Moving part |
|---|---|---|---|---|
| Plough | three-point, bus | 2 tillage | 0.055 m | gauge wheel arm swings on lift |
| Power harrow | + PTO | 3 secondary tillage | 0.02 m | tine rotor, transverse axis |
| Rotary mower | + PTO | 9 forage | none | rotor, vertical axis |
| Fertilizer spreader | + PTO, SCV | 5 fertilizer | none | disc + `scv_flow` hopper gate |

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
- Joint differs from a fifth wheel on three axes: pitch ±20° (fifth wheel's cover-the-grade
  rule); yaw ±90° (`Drawbar.SWING_MAX_DEG`, not `Articulation.JACKKNIFE_MAX_DEG` — up to 90°
  nothing behind the eye reaches forward of the pin's z-plane); roll ±25° against the semi's
  ±1.5° (a pin through an eye doesn't lever the tractor over on a rut).
- A drawbar carries a nose weight, not a share: 12% against the fifth wheel's 27%.

### Tipping, collision, refusal

- Tip runs off the SCV, not a PTO (the truck's tipping semi-trailer declares `Consumer.PTO`
  because a truck has no hydraulic remotes; a tractor already carries the pump). Raise
  interlock is `TowedBody.body_raise_allowed` unchanged.
- Collision for the raised body is two authored poses and one swap, with hysteresis
  (re-transforming a `CollisionShape3D` at 60 Hz would rebuild the compound/inertia tensor
  on a body already writing its own centre of mass).
- `E` refuses only for a press that hitches (the tractor moving); dropping the trailer lays
  nothing. Uniform wheel radius: RayWheel is single-radius, so the tractor's
  big-rear/small-front wheels are visual only.
