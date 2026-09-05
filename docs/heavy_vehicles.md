# Heavy vehicles — truck, trailer & tractor

Truck, trailer and tractor each publish a second machine's state on a second network: J1939 (truck
chassis + CANopen body network across a gateway), ISO 11992 (trailer bus), ISOBUS/ISO 11783
(implement bus). The other four families are in `docs/vehicles.md`; the shared framework is there
too, plumbing in `docs/systems.md`. Rules this code must not break: `src/vehicles/truck/CLAUDE.md`,
`src/vehicles/tractor/CLAUDE.md`.

## Truck & J1939

The truck family covers a J1939 chassis, a CANopen body network across a gateway, a thin
truck/trailer bus, and (on one variant) no trailer bus at all.

- The truck family is a chassis class, not a job: `garbage-truck`, `firetruck` and the two
  hand-built tractor units (`semi`, `semi-conventional`) only. Ordinary heavy vans (delivery,
  delivery-flat, ambulance) are `car`-family — they run proprietary CAN, not J1939. J1939 is the
  parent of both ISOBUS and NMEA 2000.
- `TruckVehicle extends BaseVehicle` (`src/vehicles/truck/truck.gd`) owns air reservoirs, PTO,
  refuse body network and the ISO 11992 trailer bus in `_tick_extras`. `TruckTelemetry extends
  VehicleTelemetry` adds chassis, body-network and trailer-bus "out" fields.

### The signal set

- **Eight J1939 chassis signals, all `flavor: "j1939"`.** In (4): `retarder`, plus J1939-73 DM1
  lamp bits `red_stop` / `amber_warn` / `protect_lamp`. Out (4): `air_primary`, `air_secondary`,
  `retarder_state`, `axle_load`. All are in the published FMS set — the J1939-71 subset six
  European manufacturers agreed to expose in 2002, since the internal bus is proprietary.
- Four more signals are reused, not duplicated (rule 4): `engine_load`, `engine_hours`, `pto`,
  `pto_state` list `truck` alongside `tractor`, `flavor: "isobus"`. ISO 11783 is built on J1939:
  `engine_load` = SPN 92, `engine_hours` = SPN 247. `diff_lock` / `diff_lock_state` are not
  extended to the truck.

### Air, retarder, axle load

- Air pressure gates the brakes. Two reservoirs (SPN 1087/1088) charge while the engine runs, draw
  down under braking; circuit 2 is smaller so the pair diverges. Below
  `TruckTelemetry.AIR_SPRING_BRAKE_BAR` (**3 bar**) on either circuit, spring brakes apply and the
  truck cannot move. `warn` (**5 bar**) is a band to stop in before immobile. The gate reads the
  minimum of the two circuits. Draw is pedal position only, not handbrake, speed, or load; the
  gate has no ramp. Losing air while rolling locks the rear axle in one tick, matching a real
  spring brake.
- The retarder is a real driveline torque, not an indicator bit: an auxiliary brake on the driven
  axle, fading to nothing at walking pace. It follows the diff-lock pattern: math on `Drivetrain`,
  `WheelDrive` adds torque to driven wheels' brake torque, `RayWheel` integrates it,
  `GroundDriveSpec.retarder_equipped` gates it to truck specs only. It cannot skid the axle:
  `RETARDER_SLIP_TARGET` caps the one-tick spin change at 0.10 slip. That is a slip limit, not a
  force limit — a cap at μ·N·r would bound only the saturated road torque a locked wheel already
  makes. Rated at `RETARDER_MAX_FRAC` **0.20** of per-wheel `brake_torque`: `frac * brake_torque *
  rear_wheels / (wheel_radius * mass)`. `test_truck` asserts brake > retarder and a **0.9-1.6 m/s²**
  band on every shipped truck spec (0.93 grip-derived Kenney trucks, 1.46 hand-built semis).
  `retarder_state` reports torque actually applied, not the request. J1939 SPN 520 reports it
  negative; the contract publishes the magnitude so the RET bar doesn't fill backwards.
- `axle_load` is read out of the sim: summed `RayWheel.suspension_force` on the rear axle in kg
  (SPN 582), never a mass lookup. Braking weight transfer moves it because the springs really
  moved. `warn` **11500** is the real EU 11.5 t drive-axle limit, `warn_side: high`.

### Lamps and the cluster

- DM1 lamps are mirrored verbatim, with no timer. `red_stop` / `amber_warn` / `protect_lamp` are
  the J1939-73 diagnostic lamp status byte; sloppyCAN is sole authority, absent bit = off.
  `checkEngine` already is DM1's MIL. DM1's flash-1Hz / flash-2Hz states are not modelled — a blink
  needs a local clock, which the standing rule forbids.
- The firetruck is the control case: same chassis class, different job, identical generated
  cluster, no body network. DIN 14700/14704 (firefighting CAN) would be the right profile and is
  not built — `firetruck.tscn`'s model is one merged mesh with no separable equipment.
- One generated cluster for the whole family: 11 bars — FUEL, COOLANT, LOAD, AIR1, AIR2, RET, AXLE,
  ARM, HOPPER, TRLR, TBRK — plus 18 tell-tales and 4 state chips (KEY, LIGHTS, BODY CMD in; BODY
  out). Absent functions publish real zeros, never gaps: firetruck/tractor units show ARM/HOPPER
  at zero, garbage truck shows TRLR/TBRK at zero, conventional shows trailer signals at zero with a
  trailer on the back. `engine_hours` is range-less, lands on the readout line beside ODO.
  `retarder_state`/`trailer_brake_demand` keep their `range` (real 0-100% scales).
- INHIB does not simply show its signal. `body_inhibit` is true whenever the body network is down;
  `is_inhibited` takes `bus_up` so the interlock never claims an unpowered body may swing its arm.
  The dashboard suppresses INHIB while BODY BUS is dark.

### The refuse body: a second network across a gateway

The garbage truck carries a **CiA 422 "CleANopen"** body control network (EN 16815:2019), reaching
the J1939 chassis across a **CiA 413** truck gateway (413-6: J1939↔CANopen; 413-8: generic I/O for
a body to use the truck's own HMI). ISO 25200 is the protocol-agnostic umbrella over this and the
tipper trailer, named only as a reference.

Six signals, all `flavor: "cleanopen"`. In (1): `body_cmd` (Idle / Lift / Dump / Lower, `X` key).
Out (5): `body_state`, `body_pos`, `body_inhibit`, `body_bus`, `hopper_load`.

- The gateway is the content: `body_inhibit` is computed on the chassis side (road speed, PTO
  state, parking brake) and published on the body network. `body_bus` goes down when the body
  network loses power (key off, chassis PTO disengaged). `hopper_load` adds real mass to the
  chassis, so `axle_load`/`engine_load` report the payload from their own measurements.
- The interlock is a real refusal. While `body_inhibit` is set, the arm freezes where it stands and
  `body_cmd` is ignored — losing the PTO mid-lift leaves the arm up. `Idle`/`Lower` and an unknown
  command byte all stow.
- `body_pos` is written onto the arm and read back off it (the `ball_lift()` discipline). The rig
  is found by name lookup (`Model/arm`, `Model/body/trash`) because
  `tools/gen_kenney_vehicles.gd` rebuilds the whole `Model` subtree on every run.
- The geometry is the declaration: no `arm` mesh means no body unit. Firetruck, semi and
  conventional publish honest zeros on all five body signals.
- The rig is a front loader — no tailgate, no body raise, no packer cycle. Respawn is the only way
  to empty the hopper; cargo goes, meters like `odo`/`engine_hours` stay.

## The towed body: tractor unit, fifth wheel, semi-trailer

The truck family's last two variants are hand-built tractor units — cab-over (`semi`) and North
American conventional (`semi-conventional`) — each pulling one of four semi-trailers on a real
joint between two RigidBody3Ds. The cab-over carries the ISO 11992 trailer bus; the conventional
carries none. No trailer of the four adds a signal to either.

### The joint and the trailer's wheels

- The fifth wheel is a `Generic6DOFJoint3D`, built at the scene's `Kingpin` marker
  (`TowHost._build_joint`, `FifthWheel` profile): three linear axes locked, yaw free to the rig's
  own **75°** jackknife stop, pitch **±15°**, roll **±1.5°** (near-zero rather than zero, so the
  solver settles). Pitch travel must cover the steepest climbable grade. Once on its stop the two
  bodies are rigid, so a level trailer at a break of slope levers the climbing tractor's drive
  axle off the road; the shipped ±8° did exactly that. A 25% grade break swings it -9.0° to
  +12.8°. The kinematic fallback (`Articulation`) is written and tested but not taken — it is deaf
  to trailer-side forces.
- The yaw limit models trailer-against-cab contact, not a fifth-wheel property: plate and nose
  overlap while coupled, so collision cannot arbitrate it. Without a limit, reversing on full lock
  folded the rig to 130° and swung the trailer through the cab. `Articulation.JACKKNIFE_MAX_DEG`
  (**75°**) serves both joint and fallback.
- The trailer carries its own unmodified `RayWheel`s — undriven, braked, six on a tri-axle bogie,
  making `trailer_axle_load`/`trailer_abs` real numbers. Ticked from `TowHost.tick_towing`.

### TowHost, cycling and mass

- `TowHost` (`src/vehicles/base/tow_host.gd`) is one class for both truck and tractor: it owns the
  coupling datum, joint, PTO/valve gates, spawn countdown, couple-at-speed refusal, reactive fit
  check, raise interlock, lamps, respawn, showroom freeze, camera exclusion, teardown. A
  `CouplingProfile` (joint angles, marker path, joint name, driver notices) distinguishes fifth
  wheel (`FifthWheel`) from drawbar (`Drawbar`, § below).
- The towed half is shared too: `TowedBody` (a real RigidBody3D on the joint's end with unmodified
  RayWheels) and `Articulation` (coupled pose, load split, kinematic fallback). Neither is
  truck-specific; the tractor's drawbar and `FarmTipper` use them directly.
- `E` cycles the combination, `V` the body, separate keys: box → tipper → tanker → flatbed →
  bobtail via the same duck-typed `cycle_implement()` the tractor uses; `TrailerCatalog` shaped
  like `ImplementCatalog`, `BOBTAIL` a real entry.
- Coupling is honest about weight: trailer COM sits between kingpin and bogie, so 27% rests on the
  plate (a real van trailer's 25-30%), landing on the tractor's single driven axle — its whole
  traction budget on a 4x2. `axle_load` reports it the moment you couple: summed suspension force,
  nothing added to the signal.
- Mass ratio: 8 t : 24 t shipped (3:1, the box), verified at 8 t : 25 t. A heavier trailer needs a
  re-tune; `test_trailer` pins suspension travel per case.

### ISO 11992: brakes and running gear only

Part 2 is the application layer for brakes and running gear only, riding pins 6/7 of the **ISO
7638** connector: coupling claim, demand out, ABS state back, axle load, one injectable fault. All
`flavor: "iso11992"` — the one signal group in the contract that is bidirectional by design.

| Signal | Dir | What it is |
| --- | --- | --- |
| `trailer_ebs_fault` | in | Injected trailer EBS fault. Mirrored verbatim like DM1; nothing in the game ever sets it |
| `trailer_connected` | out | The coupling claim — see below |
| `trailer_axle_load` | out | SPN 582 on the towed unit. Read out of the sim: trailer's own bogie suspension force |
| `trailer_brake_demand` | out | EBS11, towing→towed. A report of the blend the tractor sent, and what the trailer's wheels really brake with |
| `trailer_abs` | out | EBS21, towed→towing. Read out of the sim: worst wheel slip past `TRAILER_ABS_SLIP` |

- `trailer_connected` is a claim, not "something is on the fifth wheel": it needs the trailer
  coupled and `VehicleSpec.trailer_bus_equipped`. False with a trailer physically attached is a
  real state, the same third state `implement_connected` distinguishes: attached steel, bus
  silence.
- No `trailer_type`: ISO 11992 publishes no body type. Which trailer is on the back shows through
  mass and which tractor-side signals it moves. The tractor has `implement_type` because ISO
  11783 carries a real device class.
- Brake demand blends foot brake with retarder, arithmetically. A driveline brake acts on the
  tractor's driven axle alone, so without a share on the bus the trailer would push 8 t of
  tractor. The retarder at full asks `Drivetrain.RETARDER_MAX_FRAC` of the trailer's brake torque,
  reading `retarder_state` (what ran, not the request), inheriting the speed fade for free.
- A coupled trailer draws air through the chassis' existing reservoir model: its reservoirs charge
  off the tractor's supply, dipping AIR1/AIR2 by ~3 bar, past the low-pressure warn but not the
  spring-brake gate.
- Both read signals are read after the trailer's wheels integrate; publishing before `tick_towed`
  would ship last tick's loads/slip. Bobtail publishes a real 0/false on all four every tick
  (`clear_trailer_bus`), never a gap.

### SAE J2497: the North American variant

`semi-conventional` — hood ahead of cab, sleeper behind, 4.70 m on a 3.00 m wheelbase against the
cab-over's 3.40 m/2.10 m — is a variant of the cab-over: same `SemiTractor` script, frame rails,
fifth wheel, wheels, coupling plane (y = 1.05, which every trailer is authored against and a
variant may not move), drivetrain and brake numbers. Its content is a subtraction.

- No trailer bus, via a `VehicleSpec` flag defaulting off (`trailer_bus_equipped`, the
  `rear_diff_lockable` pattern): true on the cab-over, false here. Europe puts a CAN pair on pins
  6/7 of ISO 7638; North America has no data pair on the connector at all.
- So with a trailer coupled, `trailer_connected` reads FALSE and `trailer_axle_load` /
  `trailer_brake_demand` / `trailer_abs` read honest zeros: attached steel, bus silence, the third
  state now shipped. Drive it towing and TRLR is dark, every trailer bar sits at zero.
- It still tows and brakes the trailer. The pneumatic lines aren't the data pair, so `tick_towed`
  runs either way and the trailer brakes on the same EBS11 blend. Only publishing goes dark.
- `trailer_abs_lamp` (in, bool, `flavor: "j2497"`, tell-tale TRLR ABS) is the entire North American
  trailer protocol: SAE J2497/PLC4TRUCKS modulates trailer ABS status onto the power line,
  essentially LAMP ON / LAMP OFF. Mirrored verbatim, no local timer. Meaningful only on this unit;
  the cab-over reads it false since it says the same thing on `trailer_abs`.
- The refuse body is a whole second bus behind a gateway, ISO 11992 is five messages about brakes,
  J2497 is one bit on a power line: thick, thin and absent side by side on one family.

### Four trailers, and not one new signal

Read the ISO 11992 table from the other side: the bus carries nothing about the body, so mass,
what plugs into the towing unit, and which tractor-side signals move are what tell them apart.

| Trailer | Mass | Consumes | What it teaches |
| --- | --- | --- | --- |
| Box / curtainside | 24 000 kg | nothing | on the trailer bus it *is* the flatbed |
| Tipper / dump | 19 000 kg | chassis PTO + proportional valve | a real interlock, and a load that walks |
| Tanker | 21 000 kg | nothing | a labelled model of a shifting centre of mass |
| Flatbed | 14 000 kg | nothing | the lightest, baseline for the rest |

- What a trailer consumes is declared in code (`TowedBody.consumers()`, the `ImplementBase` rule),
  so a scene edit cannot claim a connection the machine lacks; gating lives in
  `TowHost.tick_towing`, never the subclass. The PTO clause is derived from what the body declares,
  so the road tipper's "no PTO, no flow" and the farm tipper's "flow regardless" are one line of
  code.
- Every trailer control has a keyboard key and a touch button: `E`/ATTACH cycles the combination,
  `P`/PTO engages the chassis PTO driving the tipping pump, `I`/TIP is the raise/lower valve (`H`
  is the horn), parking brake is `Space`/HAND. PTO and TIP are offered by capability, not family:
  `SemiTractor.attachment_controls()` reads `TowedBody.consumers()`, so the buttons appear only
  with a tipper coupled, and hide while the bridge drives (`pto` / `hitch_pos` are contract IN
  signals sloppyCAN owns). `TractorVehicle.attachment_controls()` answers the same hook off
  `ImplementBase.connections()`.

#### Coupling, refusal, spawn countdown

- Coupling refuses on one thing, the rig moving, and the fit check is reactive. For
  `COUPLE_WATCH_TICKS` after coupling, `TowHost._watch_fresh_coupling` asks whether the trailer's
  body is touching anything; if so it's taken away with "NO ROOM FOR A TRAILER - PULL FORWARD". A
  trailer on RayWheels touches nothing in normal towing, and the tractor is excluded by the joint,
  so one body contact means it was laid inside the world.
- The one refusal is about where a body would land, so it applies to a hitch, not a drop. A
  coupling press wants a standstill (`TowHost.COUPLE_SPEED_MS`, same figure as
  `TowedBody.RAISE_SPEED_MS`); a drop press lays nothing and is never refused.
- The spawn coupling is a plain countdown (`SPAWN_COUPLE_TICKS`, **12**), buying the moment the
  chassis has risen on its own suspension. A rig driven off its marker immediately would wait for
  a quiet moment that never comes and run bobtail forever, hence a counter rather than a condition.
  The garage freezes the trailer with the tractor (`set_display_frozen`) so an unfrozen 24 t body
  doesn't swing mid-air; the same flag exempts a display rig from the fit check.
- The tipper's interlock is chassis state, evaluated by the tractor.
  `TowedBody.body_raise_allowed(speed, parking_brake)` wants parking brake set and genuine
  standstill, stricter than the refuse arm's walking pace since a raised body is four metres of
  leverage. It refuses the raise direction only; rolling away with the body up holds it. No PTO
  freezes the body where it stands. Naming reference, not implemented: ISO 25200 / CiA 408.
- Both load models move a real centre of mass and nothing else. `set_load_offset_z` slides the
  body's `center_of_mass`, so the bogie's springs carry more and the plate carries less;
  `trailer_axle_load`/`axle_load` move as consequences. The tanker's surge is a labelled model: one
  number chasing the trailer's own longitudinal acceleration with a lag. Real fluid physics is a
  non-goal, the rule that governs the boat's water too.

## Tractor, implement & ISOBUS

- **Twenty ISOBUS signals, all `flavor: "isobus"`**, the widest cluster in the game. In (7):
  `hitch_pos`, `pto`, `pto_mode` (540/1000), `diff_lock`, `fwd_drive`, `guidance_curvature`,
  `scv_flow`. Out (13): `hitch_pos_actual`, `pto_state`, `pto_rpm`, `engine_load`,
  `implement_connected`, `implement_type`, `diff_lock_state`, `fwd_drive_state`, `wheel_speed`,
  `ground_speed`, `wheel_slip`, `engine_hours`, `draft_force`. Every one is read out of the tractor
  sim or applied to it; `engine_load` and the draft force behind `draft_force` are labelled honest
  models below.
- One body, five swappable attachments, on two different connections. The drivable tractor is a
  single variant (`kenney/tractor-kenney.tscn`); `E` cycles the attachment — spreader → plough →
  power harrow → mower → drawbar tipping trailer → detached. Each teaches a different one of the
  five real tractor↔implement connections (three-point linkage, drawbar, PTO, SCV hydraulic
  remote, ISOBUS data): the plough is linkage-only, the harrow adds the PTO on a horizontal rotor,
  the mower moves the rotor to the vertical axis, the spreader adds the SCV, and the trailer hangs
  off the drawbar instead of the linkage (see below).
- Absent functions publish a real zero, never a gap. With the plough on, `pto_rpm` at the
  implement is 0 and `draft_force` climbs; with the mower on, `draft_force` is 0 and the rotor
  turns. Detached reads `implement_connected` false / `implement_type` 0.
- `TractorVehicle extends BaseVehicle` (`src/vehicles/tractor/tractor.gd`) owns hitch/PTO/
  implement state in `_tick_extras`. Spawn default: raised, PTO off, implement attached; respawn
  re-raises but keeps the implement.
- `TractorTelemetry extends VehicleTelemetry` adds the ISOBUS "out" fields. `engine_load` is a
  modeled honest value (`engine_load_pct` — throttle demand + PTO parasitic term, pure/
  unit-tested); the rest are read straight out of the sim. Detached is a real reading (`false` /
  device class 0) published every tick.

### The signals that change how it drives

- The driveline signals change how the tractor drives, not indicator bits. `diff_lock` locks the
  rear pair onto one shaft speed (`WheelDrive._lock_rear_diff` pulls them onto
  `Drivetrain.locked_axle_omega` after integration, so the gripping wheel makes the bigger force);
  `fwd_drive` is MFWD, rewriting the front wheels' `driven` flag each tick. Both gate on
  `GroundDriveSpec` flags (`rear_diff_lockable`, `front_axle_engageable`), true only on the
  tractor's spec. The two `*_state` outs read back what actually ran, not an echo of the request.
- `wheel_speed` / `ground_speed` / `wheel_slip` are the signature ISO pair and its difference.
  Wheel-based speed is the mean spin of the rear axle × physics tire radius, deliberately not
  "every driven wheel" since MFWD changes that set and the rear axle is what digs in.
  Ground-based is the chassis's own forward velocity, the "radar" reading. `wheel_slip` is how far
  the first runs ahead of the second, unsigned like J1939 SPN 1858, floored below 0.5 km/h.
- `pto_mode` is a gearbox selection, not an engine speed. 540 and 1000 are shaft speeds: the shaft
  follows the engine through the selected mode's ratio off `PTO_RATED_RPM` (**2200**), so revving
  out in 1000 lands at 1182 rev/min, inside the contract's 0-1200 without the clamp biting
  (`test_tractor` pins that). An unknown byte falls back to 540.
- `engine_hours` is an hour meter: real time under the key, climbing only, surviving respawn like
  the odometer. Range-less on purpose; lands on the readout line beside ODO.
- `guidance_curvature` is auto-steer, following the boat's `rudder` precedent: present in the
  bridge values, it overrides `steer`, and that arbitration lives only in
  `InputRouter.arbitrate_bridge`. `bridge_source.gd` maps the contract's ±127 1/km onto the ±1
  steer channel (full lock = tractor's tightest circle), including the key only when sloppyCAN
  actually sent it — 0 is a real held command, not an absence.
- `scv_flow` is a hydraulic remote with two real consumers. It rides `VehicleInput`, reaching the
  spreader's hopper gate ram (`ThreePointHitch.set_scv`) and the tipping trailer's ram
  (`Drawbar.set_scv`). The pump is engine-driven: a stopped engine means no flow however far the
  spool is opened, and either end gates on the machine's own declaration.
  - It has a local key (`Q`) because the SCV is the drawbar trailer's only control. Owner:
    `InputRouter._scv`, the `_pto` pattern. It is binary, not proportional: both consumers slew
    internally (gate over `GATE_TRAVEL_TIME`, body over `TIP_TRAVEL_S`), so a toggle gives the
    same ramp the bridge's percentage does. The truck's `retarder` stays keyless — it refines a
    pedal that already works, where this is a machine's only lever.

### Draft, hitch, linkage

- Draft is a real force. With a draft-relevant implement (plough, power harrow) down in the
  ploughable field, `TractorVehicle._apply_draft` puts a rearward force at the hitch point: rated
  draft × working depth × soil × a speed ramp (`TractorTelemetry.draft_newtons`, pure, unit-
  tested). `engine_load`, rpm sag and `wheel_slip` move because the body was really pulled back;
  there is no draft term anywhere else. Lift comes from the linkage's own solve
  (`ThreePointHitch.ball_lift()`); working depth is the implement's own (`ImplementBase.tool_depth`
  — plough shares 0.055 m, harrow tines 0.02 m). "In soil" is splat channel 4 under the hitch point
  via `HeightmapTerrain.channel_weight_at`, the same nearest-surface rule `RayWheel.terrain_at`
  uses for tire grip. Detached, a mower/spreader, a lifted implement or non-field ground each
  publish a clean 0.
- `ThreePointHitch` (`src/vehicles/tractor/three_point_hitch.{gd,tscn}`) is tractor anatomy: it
  lives on the tractor and stays whole with nothing attached — two lower draft links, rockshaft
  arms, rigid lift rods, top link, PTO stub shaft under its guard. No CollisionShape, no joint
  anywhere.
- The linkage is solved, not animated. `HitchLinkage` (pure math, tested) treats the side view as a
  four-bar: the only free variable is how far the rockshaft swung the lower links, and the
  implement's pitch plus rockshaft arm angle fall out of a circle-circle intersection against the
  rigid top link and lift rods, which is why implements tip back as they lift. `test_
  three_point_hitch` checks the authored scene against the solve, joint by joint, across the whole
  travel.

### What an implement declares

- `ImplementBase` (`implement_base.gd`) declares which of the five connections it uses (three-
  point, drawbar, PTO, SCV, ISOBUS data), its ISO 11783-1 device class, its A-frame
  (`mast_offset`, feeding the four-bar solve), whether it works in soil (`draft_relevant()`, true
  for plough and power harrow) and how far its tools reach lowered (`tool_depth()`). Implements are
  visual only: draft force is applied at the hitch point on the chassis, never by scraping
  colliders.
- The declared connections are load-bearing. `ISOBUS_DATA` decides whether
  `implement_connected`/`implement_type` report anything; `PTO`/`SCV` decide whether the stub
  shaft and remote flow reach the machine. A mechanical-only machine is attached but claims no
  address — steel on the back, silence on the bus, the third state the two signals exist to
  distinguish. The drawbar trailer ships that state; all four implements claim an address.
- Attach/detach is a logical address claim. `ImplementCatalog` holds the cycle order with DETACHED
  as a real entry; attaching instances the scene under the linkage's `Mount`, the whole connection,
  no cable modelled. `E` cycles it: the shell duck-types `cycle_implement()`, so neither `boot.gd`
  nor `VehicleCatalog` knows implements exist.

### The four implements

`src/vehicles/tractor/implements/`, each a different connection set and a device class no other
machine may share (`test_implement_catalog`):

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

Two shared conventions: each is authored in the lowered pose with the origin on the lower pin line
(ground is y = −0.21 in that frame — balls sit 0.21 m up fully lowered, 0.78 m raised), and
geometry lives in the `.tscn` while declarations live in code. The shared A-frame is
`implements/headstock.tscn`. PTO-driven visuals go through `ImplementBase.spin_from_pto`, whose
`ratio` is cosmetic and well under 1: 540 rev/min is nine turns a second, aliasing at 60 fps into a
slow backwards crawl. The published `pto_rpm` stays honest; only the rendering is geared down.
Where the signals perform: level 1's centre is the ISOBUS farm playground — painted field (soil
for `draft_force`), mud wallow (`diff_lock`), haul ramp (`fwd_drive`) and the implement yard. See
`docs/level_kit.md`.

### The drawbar: the connection that only pulls

The fifth cycle entry is not an implement. `farm_tipper.tscn` is a 10 t towed body on a real
`Generic6DOFJoint3D`, standing on its own unmodified `RayWheel`s, the same `TowedBody` the
semi-trailers use. The tractor side is the same `TowHost` the semi's fifth wheel is: `Drawbar`
(`src/vehicles/tractor/drawbar.{gd,tscn}`) is a `TowHost` carrying a drawbar `CouplingProfile` and
the pin's own geometry, nothing else.

- A drawbar only pulls. With the trailer hitched, `I` still raises/lowers the empty three-point
  linkage and `hitch_pos_actual` still reports the whole stroke; the trailer doesn't move for any
  of it. `draft_force` reads a clean zero.
- The two couplings are the same code, not two implementations. `TowHost` owns everything under §
  The towed body above; `CouplingProfile` is the data that differs. What stays on the vehicle is
  only what a tractor and truck genuinely answer differently: the brake demand (semi blends foot
  brake with its own retarder; tractor has none, so plain pedal); the spool source
  (`input.scv_flow` gated on `running` here, `1.0 - input.hitch_request` on the truck, different
  contract IN signals read on the machine that owns them); the attachment catalog and its readers;
  the semi's ISO 11992 publish and trailer air draw (tractor has neither); the camera framing
  values.

#### Pin, datum, profile

- The pin is fixed, not swinging. A swinging bar would move the pin while the joint anchors at a
  chassis-local point, so the visible hole and the physics anchor would disagree — the
  `ball_lift()` discipline. `Drawbar.PIN_LOCAL` is a documented default; runtime reads the `Pin`
  marker off the scene.
- The coupling datum is 0.40 m, not the semi's 1.05. That figure is a fifth-wheel plate height;
  this trailer is authored with its origin at the drawbar eye, ground at y = −0.40, so
  `Articulation.coupled_pose` stays one transform multiply.
- The joint differs from a fifth wheel on three axes. Linear X/Y/Z locked as ever; pitch ±20° (must
  cover the steepest climbable grade, the semi's ±8° lesson); yaw ±90° (a constant of this rig, not
  `Articulation.JACKKNIFE_MAX_DEG` — up to 90° nothing behind the eye reaches forward of the pin's
  z-plane, rear tyres end 0.33 m ahead of it); roll ±25° against the semi's ±1.5°. A plate under a
  locked kingpin holds trailer roll to the tractor's; a pin through an eye does not, so a rut under
  one trailer wheel doesn't lever the tractor over.
- A drawbar carries a nose weight, not a share: 12% against the fifth wheel's 27%. On a 4x2 semi
  the plate load is the traction budget; here the tractor gets much less help gripping.

#### Tipping, collision, refusal

- The tip runs off the SCV, not a PTO. The truck's tipping semi-trailer declares `Consumer.PTO`
  because a truck has no hydraulic remotes; a tractor already carries the pump. Same job, one
  fewer connection. Raise interlock is `TowedBody.body_raise_allowed` unchanged: parking brake set,
  genuine standstill, raise direction only.
- Collision for the raised body is two authored poses and one swap, with hysteresis, as the road
  tipper does it: re-transforming a `CollisionShape3D` at 60 Hz rebuilds the compound and inertia
  tensor on the body that already writes its own centre of mass.
- `E` refuses on one thing, and only for a press that hitches — the tractor moving. An implement
  can be swapped anywhere; dropping the trailer lays nothing. A trailer being hitched has to be
  laid in the world, and at speed would land at a pose the tractor already left. Level 1's tractor
  spawn has scenery close behind it, so the first `E` there is refused; pull forward a length and
  it hitches.
- Uniform wheel radius: RayWheel is single-radius, so the tractor's big-rear/small-front wheels are
  visual only (two cylinder meshes; physics uses the ground drive's one `wheel_radius`).
