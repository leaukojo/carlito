# Plan — Drivetrain control, the land wind rose and the handling follow-ups

Close brief 16 (`docs/plans/mechanical_update/16_drivetrain_control.md`) and two backlog items
moved here from `docs/TODO.md` (the land wind rose, phase 1; the handling follow-ups, phases 8-10;
their content is in those phases). Between the driver and the engine: a progressive pedal map, fuel and a fuel rate read
from the power the crank delivers, real gear counts on the semis and the tractor (the bus carries
D1-D24), the PTO's power on the crank, an all-speed governor with a hand throttle, and a CVT tractor.
Around it: a compass and true-wind rose on the land dashboards, and the handling follow-ups that
roll steer left open. Every new state is read out of the sim (root rule 3), and every new signal goes
through the contract (rule 4).

Written 2026-10-19. Status: **phases 1-7, 4b, 4c, 4d, 6b and 6c done** (the drive checks of 1, 2,
4, 4b, 4c, 4d, 5, 6, 6b and 7 pending; 6c has none); phases 6d, 7b and 8-11 not started.

## Decisions (user, 2026-10-19)

- **CVT: a tractor variant.** A second tractor on the same Kenney body (`tractor-cvt`), so the
  powershift tractor stays and V cycles between the two.
- **Wind rose: the contract route.** `twd` / `tws` extend to car, truck and tractor; `heading` is
  already declared for every family.
- **Fuel: a `fuel_rate` signal** (L/h, out, car / truck / tractor) beside the `fuel` gauge, read from
  the same model.
- **Tank: the compressed scale stays.** The burn's shape is real (mass flow from delivered power),
  and the tank it drains is a game scale, sized per class so a full-load tank lasts about as long as
  it does today. A COMPROMISE, stated at its site.
- **Gear bytes: `Drivetrain.TOP_GEAR` 24** (0x18), mine to pick (the user: RAMN will carry more
  gears). That is headroom over the 16 and 12 shipped below, and it covers a 24-speed powershift
  (the MF Dyna-6 class) without a second firmware change. The firmware side is a RAMN TODO
  (`docs/TODO.md` § RAMN firmware); sloppyCAN is changed here.
- **Pedal maps (phase 2, sourced while planning it):** the petrol map is EPA's measured L15B7 map
  (`docs/drivetrain.md` § The pedal map), concave rather than "progressive": a third of the pedal
  asks about two thirds of the peak. Every road diesel stays LINEAR, sourced to Bosch's min-max
  governor; no electronic road-diesel map was found, so the vans, Kenney trucks and semis do not
  move. The converter's lock-up line keeps reading the raw pedal (a COMPROMISE at
  `Drivetrain.lockup_holds`): on the mapped fuel a part-pedal pull would run D3-D5 unlocked.
- **Phase 4 (user, 2026-10-19):** the tractor's sixteen are even 1.103 steps over the shipped span
  (a COMPROMISE at the recipe: the sourced e16 spans 22:1, our span is its gears 8-16), and the
  semis kept a D1 start until phase 4c gave the start gear the rig's mass. A stuck launch steps
  down by ratio (`ShiftPolicy.start_step_down`).
- **Phase 4c (user, 2026-10-20):** the semis take `start_gear_max` 6, the slip-time rule deciding
  (Eaton US 6,953,410: bobtail D6, +24 t D3, D1 on 8 %).
- **Phase 6 (user, 2026-10-20):** the curve's 2200-2600 tail stays (the top setting's 18 % droop, a
  COMPROMISE at `TRACTOR_BASE`); `PTO_RATED_RPM` 2043, sourced; the hand throttle on `-` / `=` / `0`;
  the foot pedal is the go request, the hand throttle never pulls away alone.

## Corrections to the brief, found while planning

- **The Kenney trucks keep six ratios.** `TRUCK_BASE` runs the Allison 3000's own six (3.49 / 1.86
  / 1.41 / 1.00 / 0.75 / 0.65, sourced in `docs/sources.md`), the box a refuse or fire truck really
  carries. The 1.5-1.76 steps the brief quotes are the semis' (6.5 / 3.7 / 2.4 / 1.6 / 1.2 / 0.69).
  Item 1 re-gears the semis and the tractor; the heavy vans (Ford 6R) and the cars stay six too.
- **One gear byte, no side signal.** The brief's route (a J1939 ETC2 gear signal beside a capped
  RAMN byte) existed only because RAMN stopped at 6. With RAMN raised, the one `gear` byte carries
  the real gear; sloppyCAN already maps it onto TC1 / ETC2 (`../sloppycan/j1939-flavor.js`).
- **The PTO absorbs nothing.** `pto_load` 0.35 (`tractor.gd`, `truck.gd`) is added to
  `engine_load` alone: no torque reaches the crank. So item 2's done-when (PTO speed held through a
  load change) would only ever see draft. Phase 5 puts the PTO's power on the crank first and
  retires the parasitic term.
- **The all-speed governor is the tractor's.** A road truck's engine runs a min-max governor: the
  pedal is a torque demand (J1939 SPN 512, driver's demand percent torque), which is phase 2's map.
  An all-speed governor is a tractor spec flag (phase 6). A truck's PTO-mode engine-speed control is
  phase 6b.
- **`fuel_rate` rides no `0x52x` frame.** It is `nmea2000`-flavored, so its coverage is that
  packer's (127489, now gated to a boat on the link), and `0x520`-`0x528` is a frozen layout. A truck
  or tractor sends LFE1 from `../sloppycan/isobus.js` beside EEC2; a car's burn is on no bus.
- **One diesel figure.** The tractor reads the OECD-tested 6175R within 5 % on the road diesels'
  efficiency, so `VehicleTelemetry.Fuel` has two members and the tank is derived per body
  (`FUEL_TANK_FULL_LOAD_S` at its rated burn) rather than sized per class.
- **A laden semi skips too** (phase 4, measured): with the 24 t box, D2 and D3 are traction-bound
  and rev out inside the 1.5 s dwell, so the full-pedal skip takes D1>D4>D6 and steps singly from
  D6 (8 AMT cuts to D12, not eleven). The front-axle gate's failures are the six-speed's, at the
  same size (`docs/vehicles.md` § Pitch).
- **The powershift needs the torque reduction too** (phase 4b, measured): without it, the
  tractor's clutch passes the crank's `J Δω / t` and drops it on the lock tick. Every seamless box
  (`shift_cut_s` 0) takes `handover_fuel` (a COMPROMISE at `TRACTOR_BASE`: no tractor source
  reduces it). On a coupled rig the gate counts transfer since parked: a braked rig holds a push on
  its coupling at rest (`measure_vehicles`' `_parked_moment`).
- **The grip the gearbox reads is the sim's** (phase 4c): on a coupled rig the drive axle carries
  the kingpin's share, which `load_mass_kg` and the spec cannot split, so `WheelDrive.hold_step`
  hands the box the driven tyres' grip off their loads at rest (`Drivetrain.drive_grip_n`).
- **A laden launch locks under its downshift point** (phase 4c, measured): the drive tyres hold
  ~10 % slip, so the semi's D3 locked at 773 road rpm against the 780 point and stepped D3>D2. The
  lock starts the dwell's clock (`Drivetrain._start_gear_step`). Holding the launch's floor until
  the road speed cleared the point instead left the floored `plough` spinning in D7 for good: its
  crank sits on the governor, so it never reads as lugging.
- **D497 rates neither PTO machine** (phase 5, sourced): its rotary-power table has no power
  harrow and no single-spindle cutter. The harrow's PTO torque is fitted to Balsari's own trials
  in D497's form, the mower takes D497's disk-mower row (`docs/sources.md` § PTO power).
- **The PTO's rated engine speed** (phase 6): the curve's 2000 is its power peak and 2200 its rated
  speed (the governor's break). The 6175R turns 540 at 0.929 of rated, so `PTO_RATED_RPM` is 2043,
  and the contract's `pto_rpm` range reaches 1300 (the 1000 mode at the 2600 high idle).
- **The governor's spec flag is a pedal-map kind** (phase 6): `PedalMap.Kind.ALL_SPEED` with
  `governor_droop`, since `PedalMap.fuel` is the one place the pedal becomes fuel; every reader (the
  shift policy's drive, the measure tools' PI inverse) inherits it.
- **A governed part demand needs its own upshift point** (phase 6, measured): the map's sits over
  the setting, so the box never left its start gear. Held two droops under the setting
  (`ShiftPolicy.GOVERNED_UPSHIFT_DROOP`); at one half, the tipper's 8 % climb held D4 on 43 % fuel,
  its tyres' ~5 % slip keeping the road speed's rpm under the point.

## Recommended order

| Phase | Item | Contract | Needs |
| --- | --- | --- | --- |
| 1 | Compass and true wind on the land dashboards (from TODO) | `twd`/`tws` on land | — |
| 2 | A progressive pedal map (16.4) | — | — |
| 3 | Fuel and fuel rate from delivered power (16.5) | `fuel_rate` | 2 |
| 4 | Gear counts: semis 12, tractor 16, bus D1-D24 (16.1) | `gear` enum | 2 |
| 4b | The front-axle gate on the tractor's launches and shifts (found in phase 4) | — | 4 |
| 4c | The gearbox's picture of the rig: grip and dead time in `time_to_upshift`, a mass-aware start gear (found in phase 4) | — | 4, 4b |
| 4d | The bobtail semis' front-axle gate: a one-tick contact spike, a launch at the bar (found in 4c) | — | 4c |
| 5 | The PTO's power on the crank (found while planning) | — | — |
| 6 | All-speed governor and hand throttle (16.2) | `hand_throttle` | 4, 5 |
| 6b | The garbage truck's PTO engine-speed control (found in phase 6) | — | 6 |
| 6c | `measure_grade`'s slip-limited driver on a governed tractor (found in phase 7) | — | 6 |
| 6d | `TcPedal` on a governed tractor: `measure_vehicles` / `measure_rough` (found in 6c) | — | 6c |
| 7 | The CVT tractor (16.3) | `gear_ratio` | 6 |
| 7b | The CVT's engine-speed management and its unwind rate (found in phase 7) | — | 7 |
| 8 | Handling: `measure_rough` probes and the primary sources (from TODO) | — | — |
| 9 | Handling: truck roll understeer; the compliance-steer brief (from TODO) | — | 8 |
| 10 | Handling: the corner pass in `BalanceModel` (from TODO) | — | 8 |
| 11 | Distill and close | — | all |

Why this order:
- **1 first:** small, standalone, and every later drive check reads it (a crosswind on the road
  while judging the pedal and the cruise).
- **2 before 3:** the map changes delivered power at part pedal, which is what fuel reads.
- **2 before 4:** gear durations at part pedal come out of the map, and phase 4 re-measures every
  shift once, on the final pedal.
- **4 and 5 before 6:** the governor's done-when holds PTO speed in a gear of the 16-speed, against
  a load that has to exist.
- **6 before 7:** a CVT's controller holds the governor's target rpm.
- **8-10 last:** independent of the drivetrain chain, research-led, and on different tables (step
  and corner, against the drivetrain's launch, shift and cruise). Phase 8 has no dependency and
  can run any time, also in a worktree. 9 and 10 wait for its sources.

Contract bumps land in phases 1, 3, 4, 6 and 7 (6b, 6c, 6d and 7b expect none: the `pto` request
engages 6b, and 6c, 6d and 7b move no signal):
each is a paired change with `../sloppycan` (the `contract-edit` skill). `dev` deploys on each
push, and stable can promote several together.

## Constraints that bind every phase

- `00_README.md` § Common context binds: 60 Hz with no clamp weakened; every new torque on a wheel
  or the crank goes inside the semi-implicit step (`RayWheel._integrate_spin`, `crank_compliance`);
  Kenney bodies change in `tools/gen_kenney_vehicles.gd` plus a regen; the semis' and trailers'
  header derivations are rewritten with their numbers; the `vehicle-feel` skill for every feel change.
- **One engine law on the delivered fuel** (`src/vehicles/CLAUDE.md`): the pedal map, the governor
  and the CVT controller all output `applied_throttle`; `ShiftPolicy` keeps reading the driver's
  demand (the pedal, or the higher of pedal and hand throttle on the tractor).
- **Phase 2 leaves full pedal invariant:** the map is 0 at pedal 0 and the curve at pedal 1, and
  monotone between them. So every floored figure (`doc=accel`, the launch traces, the CI gates)
  stays byte-identical, and that equality is the phase's first check. Later phases move floored
  figures on purpose (phase 4's re-gear and full-pedal skip) and regenerate them.
- **Brakes are hardware** (`src/vehicles/CLAUDE.md`): a re-gear that deepens a first gear must pass
  `BrakeSizing.stall_hold_margin` unchanged, never a bigger brake.
- **Figures:** tables are regenerated by their `doc=<id>` presets, never edited by hand. Long sweeps
  run in the background with `--fixed-fps 60`. The CI gates (`measure_vehicles -- all 45 track
  strict`, `measure_semi_launch -- <unit> strict`) pass at the end of every phase that moves a body.
- **RAMN firmware is out of scope.** Its gear change is the TODO in `docs/TODO.md`, and it flashes
  only after this plan's gear contract reaches stable: an older Carlito reads a manual-mode drive
  byte past 6 as N (`Drivetrain.normalize_byte`).
- The user verifies by driving. A phase's drive check names what to feel, and what is measurable
  is measured headless first.

## Phase 1 — Compass and true wind on the land dashboards

Effort **medium**. Permission **accept-edits**. Contract bump (`contract-edit` skill).

From the crosswind drive check: on a land vehicle you cannot see your heading or where the wind
comes from, so drift under CONDITIONS wind is hard to read. Only the boat has a rose
(`src/ui/wind_rose.gd`), built when the out-signals carry the whole `Dashboard.WIND_ROSE_SIGNALS`
set (`awa`/`aws`/`twd`/`tws`/`cog`/`sog`), which the contract declares for the boat only. This puts
wind on the bus too. The rejected route, a rose fed from the level, would have been the first
dashboard widget the contract does not declare (rule 4).

1. **One conversion, one home.** Move `twd` / `tws` and `true_wind` (the FROM inversion) from
   `BoatTelemetry` up to `VehicleTelemetry`; the boat inherits them. The base already carries
   fields some families do not declare (`rpm`), so nothing new crosses the wire for them that
   `to_bridge_dict` did not already send. Rewrite `twd`'s contract `desc`, which names
   `BoatTelemetry.true_wind` as the one site.
2. **Contract:** add `car`, `truck`, `tractor` to `twd` and `tws` `vehicles`. They keep their
   `nmea2000` flavor (it names PGN 130306's semantics); sloppyCAN's NMEA 2000 module sends
   130306 only with a boat on the link (`nfPack`'s `rudder_actual` gate), so a land body puts no
   N2K frame on the bus.
3. **Telemetry:** `BaseVehicle` fills them each tick for a wheeled body from the same
   `WindField.at` the crosswind force reads (`WorldConditions.WIND_FAMILIES`). Calm reads 0, as on
   the boat.
4. **Dashboard:** `declares_compass_rose(out_names)` beside `declares_wind_rose`: `heading` + `twd` +
   `tws`. `WindRose` draws what it is given, a compass card turning with heading and the true-wind
   arrow plus speed, with no apparent-wind or track needles on land; the boat's rose is unchanged.
   `twd` is already in `WIDGET_SIGNALS` and `tws` has no `range`, so neither grows a bar.
5. **sloppyCAN:** regenerate the copy. The two readouts live only on the boat panel today
   (`../sloppycan/boat.js`); add TWD / TWS beside heading in the Carlito window's IN column
   (`../sloppycan/carlito.js`) for every family that declares them.
6. **Tests:** `test_contract` (version), `test_telemetry` (`true_wind` on the base: a wind blowing
   toward north reads `twd` 180), `test_dashboard` (a land family builds the compass rose, the boat
   still builds the full one, no `twd` bar on land), then the suite.

Done when a car, truck and tractor show the rose under CONDITIONS LIGHT / STRONG and on `level_6`,
the arrow agrees with the drift (`docs/vehicle_measurements.md` § Wind), and the boat is unchanged.
Drive check: a crosswind on the straight; the arrow names the side the body drifts away from.

## Phase 2 — A progressive pedal map

Effort **high**. Permission **plan-mode-first**: the maps must be sourced.

1. **Source** a petrol car map and a road-diesel map: the requested torque against pedal and rpm.
   Candidates:
   - the torque-based structure of drive-by-wire engine management (Bosch, *Gasoline Engine
     Management*: the driver's request torque from pedal and rpm);
   - J1939-71 SPN 91 to SPN 512 (driver's demand percent torque) for the road diesels;
   - EPA ALPHA's driver model [33, 34], already cited.

   Grade each figure; a shape read off a figure is secondary.
2. **Spec:** a `pedal_map` per engine class (`VehicleSpec`; a pedal × rpm table of the requested
   share, or the sourced paper's parametric form, whichever the source gives). The default is
   identity, today's law.
3. **Drivetrain:** in `_process_crank`, the pedal goes through the map before the governor, limiter
   and shift cut (`fuel = pedal_fuel(spec, pedal, rpm) * governor_scale(...)`). Never in
   `src/input/` (it shapes keys) and never on the rigid crank (boat, plane, drone, train). The
   tractor stays identity: its pedal becomes the governor's speed demand in phase 6.
4. **Recipes:** `CAR_BASE` and the sports and open-wheel overrides take the petrol map; `VAN_BASE`,
   `TRUCK_BASE` and both semis take the diesel one (semi header comments rewritten).
5. **Tests** (`test_drivetrain`): 0 at pedal 0, the curve at pedal 1 at every rpm, monotone in pedal,
   identity spec bit-for-bit today's fuel; `test_vehicle_catalog` asserts every wheel-driving spec's
   map passes the same three.
6. **Measure:** first `doc=accel` floored, which must be byte-identical; then the part-pedal
   benchmark (`-- <variant> 90 pedal=0.3`, `pedal=0.6`), `doc=cruise` (the PI's held pedal moves,
   the settle speeds must not), the kickdown and pulse probes (hunting gate PASS), and creep (pedal
   0, unchanged).

Done when the floored figures are unchanged, the `sedan`'s pedal-0.3 run reads the sourced map's
prediction (computed from the map and the shift map, within a stated tolerance), the hunting gate
passes on every body, and `docs/drivetrain.md` § The shift policy's "at a held part pedal" paragraph
is rewritten from the regenerated table. Drive check: a gentle pull-away and a held part pedal on
the `sedan` and `delivery`.

## Phase 3 — Fuel and fuel rate from delivered power

Effort **high**. Permission **normal**. Contract bump. Needs phase 2.

1. **The model (an honest Willans line, labelled modelled):** the fuel adds
   `f * (curve(n) - motoring(n))` to the crank over its motoring torque (`Drivetrain.crank_torque`),
   so the fuel's power is that torque times the crank speed over an indicated efficiency `eta_i`,
   one figure per engine class. At zero fuel the burn is zero (a fuel cut is real). At idle the
   controller's fuel nets the friction out, so idle burn falls out of the friction law, and so do
   the converter's creep load and, after phase 5, the PTO. Brake-specific consumption then rises at
   part load on its own. Read `applied_throttle` after the controller's floors (idle, drag-torque
   control), as `_process_crank` leaves it: that is the fuel the crank got.
2. **Source and check `eta_i`** against a published map's minimum BSFC and idle flow per class:
   - petrol: EPA's benchmark of the 2013 Malibu's 2.5 L [33];
   - road diesel: EPA GEM's heavy-duty engine maps;
   - tractor: a Nebraska / OECD tractor test report (specific consumption at rated PTO power and at
     part load).

   Computed for scale (`eta_i` 0.35 / 0.45, lower heating values 43 / 42.7 MJ/kg): `sedan` idle
   ~0.56 L/h; `semi` idle ~1.6 L/h, under the ~3 L/h commonly quoted for a heavy truck's idle,
   which carries accessories and a raised idle this model omits (say so); the `sedan`'s brake
   efficiency at peak torque ~0.31, ~265 g/kWh.
3. **Signals:** `fuel_rate` (out, f32, L/h, no `range`, so a readout beside ODO; car / truck /
   tractor), the mass flow over the fuel's density. `fuel` % drains the class's compressed tank (the
   COMPROMISE in Decisions, stated at the constant). Coolant's target reads the fuel power's share of
   its rated figure: the heat the cooling system rejects follows fuel energy, not the pedal, so it
   moves with the same model at no extra figure. Battery stays on its own model.
4. **Code:** a pure `VehicleTelemetry.fuel_rate_lph(spec, rpm, fuel, running)` and the per-class
   figures beside `FUEL_*`; `BaseVehicle` reads `drivetrain.applied_throttle` and `drivetrain.rpm`,
   both the sim's. The rigid-crank bodies (boat, plane) keep today's throttle model, labelled.
5. **sloppyCAN:** `fuel_rate` in the Carlito IN panel and telemetry frames (`../sloppycan/carlito.js`
   0x528 block). For the truck and tractor, encode J1939 LFE1 (PGN 65266, SPN 183, 0.05 L/h per bit)
   where the J1939 flavor publishes the engine's PGNs; `../sloppycan/j1939-tables.js` already has
   SPN 183's decode row.
6. **Tests:** `test_telemetry`: zero burn at zero fuel, idle burn equal to friction power over
   `eta_i`, monotone in fuel, and the formula against one computed figure above (a check of the
   arithmetic, not of the sourced `eta_i`). Then `test_contract`, `test_dashboard`, the suite.
7. **Measure:** a `gear=` hold on the cruise probe (today `gear=` holds only the accel pass), so
   one speed reads in two gears, and a `fuel_rate` column on `doc=cruise`.

Done when `fuel_rate` reads the sourced idle and minimum-BSFC figures per class within stated
bands, the `sedan` at 60 km/h held in D6 burns measurably less than in D3, and the "fuel, coolant
and battery read `applied_throttle` alone" line in `docs/drivetrain.md` § Creep is rewritten.

## Phase 4 — Gear counts: semis 12, tractor 16, the bus D1-D24

Effort **high**. Permission **plan-mode-first**. Contract bump plus sloppyCAN. Needs phase 2.

1. **The bus.** `Drivetrain.TOP_GEAR` 24. Contract `gear` in and out: enum `"1-24": "D1-D24"`; the
   `desc` notes that RAMN sends up to its `MAX_GEAR_VALUE` (6 until the RAMN TODO lands) and that a
   byte past a short gearbox selects its top ratio (`ratio_for_byte`, unchanged). Update every
   "1-6" comment and doc string: `drivetrain.gd`, `vehicle_input.gd`, `vehicle_telemetry.gd`,
   `input_router.gd`, `vehicle_select.gd`, the `gear=` flags of `measure_vehicles` /
   `measure_grade`, `docs/systems.md` § Input pipeline (the PRND lever's "D1-D6"), and
   `docs/vehicle_measurements.md`'s three `gear=<1-6>` run-line notes. Tests: `test_contract` (`enum_label(24)` is "D24"), `test_drivetrain` and
   `test_shift_policy` (their `range(1, 7)` loops become `TOP_GEAR`).
2. **sloppyCAN (this plan's, not a TODO).** Read the top gear off the contract copy (the `1-N` key
   of the `gear` enum in `../sloppycan/carlito_contract.js`) instead of a literal 6 (rule 4), at:
   - `../sloppycan/ramn.js`: the 0x077 decode's `<= 6` clamp, `GEAR_SEQ`, the joystick help text, the state
     comments;
   - `../sloppycan/j1939-flavor.js`: `jfGearRaw` / `jfGearFromRaw`'s `min(6, …)`, plus self-tests at 12 and 24;
   - `../sloppycan/carlito.js`: the gear comments;
   - `../sloppycan/.claude/modules.md`: its "1-6".

   Commit in `../sloppycan` with the contract copy.
3. **The semis: 12 ratios** (`semi_spec.tres`, `conventional_spec.tres`, both headers). Source the
   I-Shift 12-speed's ratio list (Volvo AT2612 data, beside [36, 37]). Fit its step pattern over the
   shipped span (D1 6.5 to the 0.69 overdrive, so cruise rpm and top speed do not move); computed,
   that is ~1.23 a step, inside the real 1.2-1.3. If the sourced first gear is deeper, it ships
   only if the stall hold, the launch gates and `measure_semi_launch strict` pass unchanged.
   Re-derive the light map so a light upshift lands in the D13's 1250-1500 rpm cruise band
   (computed: a light upshift at 1533 rpm or more lands at 1250), and the start gear (the I-Shift
   picks its own from gross weight and gradient [36]: set `start_gear_max`).
4. **The tractor: 16 ratios** (`TRACTOR_BASE`). A full powershift of 16 forward speeds (confirm a
   real one and its steps; the John Deere e16 class), over the shipped span (D1 7.0 to D16 1.6):
   computed ~1.10 a step, the brief's real 1.10-1.15. Reverse stays at 3.9, the old D3 ratio, now
   ~D7. The start gear:
   - `start_gear_max` moves from 3 to the gear carrying the old D3's ratio (computed D7), so the
     tallest launch ratio does not move;
   - the picks get finer (the old D2's 5.2 sits at ~D4, and D5 / D6 now exist between), so
     `test_tractor`'s computed picks are re-derived, not renumbered;
   - a launch that has not moved steps down one gear per `launch_engage_s + shift_dwell_s`
     (`Drivetrain._start_gear_step`): one 1.10 step is a third of the old one, so a stuck launch
     would take three times as long to reach the same ratio. It re-picks at the driver's pedal with
     the standing load raised instead, or steps by ratio, not index; the phase picks one and tests
     it.

   COMPROMISE, if the sourced box is a partial powershift (ranges by clutch): it shifts all 16 under
   load. State it at the recipe.
5. **The full-pedal skip** (`ShiftPolicy`). With ~1.1-1.23 steps a floored, lightly loaded rig rips
   through gears faster than the trace's 1.0 s dwell gate, which is what AutoDrive and I-Shift
   skip-shifts exist for. A forced upshift takes the lowest higher gear that holds `shift_dwell_s`
   at full pedal on the road load and the rig's mass (`ShiftPolicy.time_to_upshift`, already used
   by kickdown), never landing under the full map's downshift point times the landing floor. A
   loaded rig steps one at a time; a bobtail skips. Only `skip_shifts` boxes (the semis' AMT, the
   powershift) take it. Tests in `test_shift_policy`: a bobtail skips, a laden rig steps singly, and
   the landing floor holds. Expect the laden semi's `doc=accel` to slow: up to eleven AMT cuts
   (`shift_cut_s`) where it had five, which is the real cost of a 12-speed AMT and is recorded, not
   tuned away.
6. **Measure:** the launch trace on both semis (laden and bobtail) and on the tractor (bobtail,
   tipper), `doc=accel`, `doc=cruise`, the climbs (`docs/drivetrain.md` § The shift policy's climb
   table), kickdown (the semi's "never finds a gear under its ceiling" should go), rollback and
   gradeability, `measure_semi_launch strict`, `track strict`. The semis' high-gear front-axle gate
   failures (`docs/vehicles.md` § Pitch) are re-read: smaller steps swing less.

Done when the semis run 12 and the tractor 16 over the same speed span, every trace gate passes
(dwell, landing, hunting, front axle), skip-shifts fire on the bobtail runs, `doc=accel` and the
climb table are regenerated, and the "never fires on this six-speed" and "D4 is the shortest gear"
notes (`docs/drivetrain.md`, `docs/heavy_vehicles.md`) are rewritten. Drive check: a semi and the
tractor floored and at part pedal; the shifts should read as steps, not lurches.

## Phase 4b — The front-axle gate on the tractor's launches and shifts (done)

Done 2026-10-20; the drive check is pending (the tractor floored bobtail, and with the tipper on the
haul ramp: its nose should settle after each shift without bobbing). Neither failure was pitch
damping:
- **Bobtail:** without a reduction, the powershift hands the crank's `J Δω / t` to the wheels
  through the handover (D7>D13 `Tc` ~1200 N·m against ~300) and drops it on the lock tick. Every
  seamless box takes `Drivetrain.handover_fuel` (`docs/drivetrain.md` § The shift's handover, a COMPROMISE at
  `TRACTOR_BASE`). Every bobtail event passes: launch 5.2 of 13.5, D7>D13 0.7, D13>D16 -0.8 of 5.0.
- **Tipper:** a braked rig settles with a push on its coupling (−23 kN on the drawbar), which the
  parked front already carries. `measure_vehicles` counts transfer since parked, which also passes
  both semis with the box. The
  tipper's shifts pass. Its launch fails on the tipper's brake venting (`docs/vehicles.md` § Pitch).

For phase 4c, which re-measures the same traces:
- Shifts with the reduction: bobtail D7>D13 1.52 s, D13>D16 3.12 s (`Tc` 699 / 662); tipper
  D7>D11 3.30 s, D11>D14 5.22 s, D14>D16 7.98 s.
- The floored `plough` start steps D7>D6, not D7>D5.
- The 8 % climbs keep their shifts, slightly later (bobtail 362.8 m up in 40 s, tipper 214.4 m).

## Phase 4c — The gearbox's picture of the rig (done)

Done 2026-10-20; the drive check is pending (a semi stabbed from a steady 30 and 50 km/h, laden and
bobtail; the tractor pulled away empty and with the tipper on the flat). Measured:
- Starts on the flat: semi bobtail D6 (D6>D8, then singly; 0-50 km/h 4.93 s against 5.88), +24 t D3
  (D3>D5, then singly; 16.13 s against 15.35); tractor D7 bare (unchanged), D6 with the tipper
  (D6>D10>D13>D15>D16), D4 with it on 10 %.
- Kickdown: the semi + 24 t kicks D7>D6 at 30 km/h and D11>D10 at 70, hunting PASS on every body.
  At 70 the next gear down landed over the old ceiling (`shift_up_rpm / LANDING_MARGIN`, 1536 rpm):
  with the hold judged on the rig, the ceiling is 85 % of the redline under `shift_up_rpm`, and the
  margin stays only with no estimate. At 50 the next gear lands on its 1690 upshift, so none. The
  cars now kick two or three gears where they took one or two.
- Every phase-4 trace gate passes on the laden semis and the tractor. The bobtail semis' `front
  axle` gate fails at the bar on one event each: phase 4d.
- `measure_vehicles`' cruise windows stop at the strip's end: `semi-conventional`'s 85 km/h pulse
  after a 120 s kickdown ran off it and the gate judged the respawn.

For phase 6, which re-measures the same launches: the floored `plough` start lugs D7>D4>D1, the
harrow's D7>D6>D11.

Effort **high**. Permission **plan-mode-first**: the start-gear rule must be sourced, and it reopens a
phase 4 decision. Needs phase 4, and 4b (both re-measure the same launch traces). Before phase 6,
whose governor and hand throttle feed the same `ShiftPolicy` demand.

Two estimates the box makes of its own rig read wrong on the close-ratio boxes (phase 4's
measurements, 2026-10-19):

- **`ShiftPolicy.time_to_upshift` reads short.** It drives the rig with the engine's whole torque
  and no gap. The laden semi's D2 and D3 are grip-bound (the trace's `tcs` time), and an AMT shift
  spends `shift_cut_s` with no drive and `shift_torque_ramp_s` rebuilding it. The full-pedal skip
  (`forced_upshift`) and the kickdown hold (`kickdown_target`) both read it, so no semi kicks down
  at the truck family's three lower cruise speeds (`-- semi 120 cruise kickdown pulse`): the next
  gear down lands under the ceiling but revs out of it inside `KICKDOWN_HOLD_S` on paper.
- **`ShiftPolicy.start_gear` cannot tell laden from bobtail on the flat.** It weighs the standing
  load, which there is rolling resistance alone, so a start range would start a 32 t rig as high
  as an 8 t one. That is why the semis keep a D1 start (phase 4's decision) and why the tractor
  starts in D7 laden on the flat as well as bobtail.

1. **Grip in the estimate.** Cap the net drive `time_to_upshift` uses at what the driven axles can
   put down: the fitted tyre's `mu_long` on their static share of the rig's weight, coupled load
   included (the derivation the semi header's "WHAT BOUNDS 2308 Nm IS TRACTION" does by hand). The
   inputs the gearbox already holds (`load_mass_kg`, the spec) suffice; it never reads the wheels'
   live slip (`ShiftPolicy`'s header).
2. **Dead time in the estimate.** Add the shift's own cost to the time a gear must hold: the cut and
   half the torque ramp on an AMT (an estimate), none on a powershift or a converter (`shift_cut_s`
   0). The dwell figure (`shift_dwell_s`) is unchanged.
3. **A mass-aware start gear.** Source how an AMT picks its start gear from gross weight and
   gradient (I-Shift's own documentation [36, 37], an Eaton or ZF TraXon equivalent) and the
   acceleration it launches for. Add the rule beside today's (the reserve on the standing load
   stays: it is the grade's floor); then the user decides whether the semis take a start range
   (`start_gear_max`), with the laden and bobtail picks in front of them.
4. **Tests** (`test_shift_policy`): the grip cap on a toy spec (a heavy rig's time in a low gear
   rises to the grip-bound figure), the dead time on an AMT spec and its absence on a powershift,
   the start rule laden and bobtail on the flat and on a grade. `test_tractor`'s computed picks are
   re-derived, not renumbered.
5. **Measure:** the launch traces (both semis laden and bobtail, the tractor bobtail and with the
   tipper), the part-pedal probes, `doc=accel`, `doc=cruise`, the climbs, rollback and
   gradeability, `measure_semi_launch strict`, `track strict` on the moved bodies, and the
   `plough` pass. The skip-shifts the traces print are recorded, whichever way they move.

Done when a semi kicks down at its lower cruise speeds with the hunting gate PASS, every trace
gate phase 4 passed still passes, a bobtail on the flat picks a higher start gear than the same rig
laden (on whichever bodies the user gives a start range), and `docs/drivetrain.md` § The shift
policy (the skip-shift and kickdown bullets, the start gear) is rewritten from the regenerated
figures. Drive check: a semi stabbed from a steady 50 km/h, laden and bobtail; the tractor pulled
away empty and with the tipper on the flat.

## Phase 4d — The bobtail semis' front-axle gate (done)

Done 2026-10-20; the drive check is pending (the cab-over floored from rest, bobtail: the nose
should rise once and settle on its pull without bobbing back past it). Both bobtail units pass
every event. Neither failure was the gate's reading:
- **`semi-conventional`: the contact query.** At the spike's tick both steer wheels' sweeps stopped
  a step high and the rest test at the touching stop read clear, so `_contact_query` settled on the
  free stop before it: compression 78.11 > 80.00 > 77.82 mm, the wheel 18.76 > 20.56 > 16.61 kN.
  A touching stop the rest test reads clear is a free one, and the bracket moves a step on
  (`docs/vehicles.md` § Physics derivations and figures; `test_wheel_spin`). D8>D9 reads 2.1 of 5.0,
  from 5.3. The trace's `contact` flag prints each wheel's load and contact.
- **`semi`: real pitch, on the front rebound damper.** Swept one at a time, only the front rebound
  moves the launch (15800 > 17900: 6.4 > 5.5 points); the bump side (12000 > 13500: 6.2) and the
  rear dampers do not. Both semis' front dampers take the road band's ends at the bobtail steer
  corner, 13500 / 17900 (zeta 0.30 / 0.40; 0.27 / 0.36 coupled to the box).

Measured after, every trace gate passes on both semis:
- Bobtail: the cab-over's launch 5.4 of 6.4 (shifts at most 3.6), the conventional's 3.5 of 5.0.
- With the box: the launches 4.2 of 18.2 and 6.8 of 14.9, from 3.5 and 5.0 (the rebound damper's
  force comes off a nose rising fast).
- `measure_semi_launch strict`: steer floors 11353 / 13782 N, from 10975 / 13514.
- `track strict` and the drained-air probe pass.
- The tractor bare is unchanged. The tipper's launch reads 21.2 of 18.7, from 21.9 of 18.8 (the
  contact query), and its shifts pass.

## Phase 5 — The PTO's power on the crank (done)

Done 2026-10-20; the drive check is pending (the harrow lowered in level 1's field with the PTO in,
then out: `engine_load` and rpm drop with it; the mower lowered and raised with the PTO in; the
plough with the PTO in reads as out; the garbage truck's arm raised, PTO and handbrake on:
`engine_load` rises while the arm climbs). `pto_load` is gone. Measured
(`docs/heavy_vehicles.md` § Draft, hitch, linkage): the parked harrow 9 % > 23 %, its holds 37 / 35 / 46 % >
51 / 64 / 74 %; `20 plough course` byte-identical with the PTO in and out (the 7 km/h run's 56 % on
full soil, 39 % on the bands, inside tractor_plough's 25-70 %). The figures: `docs/sources.md`
§ PTO power. `tractor_pto_speed` spawns the mower raised, so its free-crank hint is unchanged; with
the deck lowered the band needs more pedal.

For phase 6, which re-measures the same launches: floored from rest with the harrow and its PTO, the
rig is power-bound in D7 at 13.4 km/h, the crank at 2248 rpm on the curve's tail, its road speed's
2107 rpm short of the 2200 upshift point; D8 would land near 2040 rpm, where the curve makes more
power. With the PTO out it takes D7>D6>D11 to 20.2 km/h.

Effort **medium**. Permission **plan-mode-first**: the implements' figures need sourcing.

1. **Source:** ASABE D497's rotary-power parameters (already the draft's source): power per metre
   of width (and its speed and depth terms) for the power harrow and the rotary mower; the
   spreader's disc drive is small (an estimate). The refuse body's packer pump: a figure per cycle,
   or an estimate, labelled.
2. **Implements** declare `pto_power_kw(ground_speed, depth)` (`ImplementBase`, 0 by default; the
   plough and the tipper declare none). The tractor and the truck turn it into a torque at the
   shaft, `P / omega_pto` at the selected mode's rated shaft speed, then onto the crank through the
   PTO ratio (`TractorTelemetry.pto_speed_for_mode` over `PTO_RATED_RPM`). That is a constant torque
   for a given ground speed and depth, never `P / omega` at the live speed, whose falling slope
   would feed back as a negative stiffness.
3. **Drivetrain:** an owner-set `accessory_torque` (N·m at the crank, like `speed_cap_kmh`) enters
   the crank's predictor with its own torque, inside `crank_compliance`, never after the step. The
   idle controller and the fuel see it as load. A PTO engaged with nothing to drive turns a stub
   shaft: 0.
4. **Retire** `pto_load` on both families. `engine_load_pct` loses its parasitic term: the engine's
   delivered torque now carries the PTO (rule 3). The tractor's `CLAUDE.md` line ("never add a
   draft term") gains its PTO twin only if a guard cannot say it.
5. **Tests:** the PTO torque reaches the crank only with PTO on, an implement with a PTO connection
   and the key on; the harrow at its speed and depth reads its D497 power at the shaft.

Done when the harrow's `engine_load` and rpm sag come from its PTO torque on the parked and working
runs, the PTO-on `engine_load` figures in `docs/heavy_vehicles.md` are regenerated, and `pto_load`
is gone. `pto_on` is the request and the key, not the implement (`tractor.gd`), so today a PTO
switched on behind the plough adds 35 points. Re-check the `tractor_plough` challenge's band
(`src/challenges/defs/tractor_plough.tres`) with the PTO off and on.

## Phase 6 — All-speed governor and hand throttle (done)

Done 2026-10-20; the drive check is pending (set 540 with `0`, lower the harrow into level 1's
field with the PTO in, and watch `pto_rpm`: it should settle ~4 % under 540; then a part pedal on the
road should upshift and cruise at the pedal's engine speed). Contract v53 (`hand_throttle`;
`pto_rpm` to 1300), paired with sloppyCAN (the tractor panel's Hand slider, panel-only). Measured:
- Floored, nothing moved: `tractor-kenney 40 trace`, roll-back and gradeability byte-identical.
- `20 plough governor`: lowered at 7 km/h in D2 the harrow settles 3.4 % under the 2043 setting
  (shaft 521 rpm), the plough 3.2 % (522), inside the 7 % droop's 504.7.
- The cruise probes pass every gate; the tractor's cruise row moved (15 km/h in D14 at 1187 rpm).
  The tipper's 8 % climb at 0.6 runs D4 to D14 a gear at a time, 192 m.
- The plough holds the reference speed in D1 at 10 % slip (the governor caps the rears' spin);
  the PI-driven course shifts more at part pedal, no opposite pair inside 1 s.

For phase 7: the CVT's controller holds `PedalMap.setting_rpm` of the demand; the governor's line
and its stiffness (`PedalMap.governor_stiffness`) are the engine side it meets. The measure tools'
PI pedals reach the governor through `PedalMap.pedal_for`, whose setting tracks the crank, so on a
governed box they read as economy driving (high gears, low rpm).

Effort **high**. Permission **plan-mode-first**. Contract bump. Needs phases 4 and 5.

1. **Source** the droop: an electronic tractor engine's selectable droop and a mechanical governor's
   classic figure (ISO 3046-4's governing classes; a tractor maker's operator manual).
2. **The governor** (`GroundDriveSpec`/`VehicleSpec` flag `all_speed_governor`, off by default:
   one machine's behaviour). The speed setting is `lerp(idle, high idle, max(pedal, hand throttle))`.
   The fuel runs the governor line, from the friction's fuel at the setting to full fuel at the
   setting less its droop, bounded by the full-load curve. The idle controller stays the floor. The
   road-speed governor is unchanged.
   - **Stability:** the line's slope joins `crank_stiffness`, so the step stays semi-implicit at
     any droop. Computed on the tractor's crank (1.5 kg·m², ~700 N·m over the line): explicit,
     `k dt / J` is ~0.4 at 8 % droop, but ~3.4 at 1 %, past the 60 Hz limit of 2. An electronic
     governor's near-isochronous setting is the case that needs it.
   - **The curve's tail:** the full-load curve already falls to 0 between 2200 and 2600 rpm, which
     is a governor line at the top setting. The sourced droop either matches that tail or the phase
     states the difference. Reshaping the curve meets § Rejected designs' "torque-curve tails"
     entry (it moves the tuned top speed): that is the user's call.
3. **Hand throttle:** `hand_throttle` (in, u8 %, 0-100, `isobus`, tractor). It enters through
   `VehicleInput`, arbitrated in `InputRouter` only (rule 5), with its `bridge_source.gd` key
   (`contract-edit` step 4). While the bridge drives (`InputRouter.bridge_drives()`) the bridge's
   value is mirrored and absent reads 0; the local latch is never read then (`src/input/CLAUDE.md`).
   Locally, the latch's owner is `_hand_throttle` in `InputRouter`, and the sources report edges:
   two keys to step it, chosen against the input map, plus a preset that sets the PTO's rated
   engine speed for the selected `pto_mode`. Like `_pto`, it persists across a respawn.
   `ShiftPolicy` reads the higher of pedal and hand throttle as the demand.
4. **sloppyCAN:** a hand-throttle control on the tractor panel (`../sloppycan/tractor.js` /
   `../sloppycan/isobus.js`).
5. **Measure:** a new `measure_vehicles` scenario (a scenario in an existing tool): the tractor at
   the 540 preset with the harrow, lowered onto full soil, PTO on; PTO rpm, engine rpm and
   `engine_load` through the draft's and the PTO's onset.

Done when the tractor at 540 PTO holds within its sourced droop as D497's draft and the harrow's
PTO power come on, and `docs/heavy_vehicles.md` § Draft gains the regenerated hold. Drive check:
set 540, lower the harrow into the field, and watch PTO rpm on the dash.

## Phase 6b — The garbage truck's PTO engine-speed control (done)

Done 2026-10-21; the drive check is pending (the garbage truck parked in N, handbrake and PTO on,
the arm raised: the engine note rises to the set speed and holds, the arm lifts at its rated pace;
select D and it drops to idle). Decisions (user): isochronous (droop 0, no truck figure found), and
the arm's flow follows the pump's speed, capped at rated. Found while sourcing and measuring:
- **The interlock is not `drive_inhibit`** (the air-low gate): a Cummins ECM's PTO mode wants the
  park brake, neutral and at most 2 mph (`docs/sources.md` § PTO power). The neutral interlock
  lives in the drivetrain, which holds the gear (`Drivetrain.pto_set_rpm`).
- **An isochronous line is narrower than a tick**: full fuel moves the free crank ~90 rpm a tick
  against a ~1.3 rpm line, so read at the tick's start it jumped the line and cycled on it (1300 to
  1386 rpm, a ~0.13 s period). A free crank's governor now fuels no more than lands it on the
  setting (`Drivetrain.fuel_to_land`). The tractors' traces stay byte-identical. Their parked-in-N
  governor lines lose a hair of overshoot (droop "-0.0 %" now reads "0.0 %"), and a few working
  lines after them move in the last digit. The droop gates are unchanged.

Measured (`measure_vehicles -- garbage-truck 60 arm`): before, 700 rpm through the cycle, 8 % >
30 % `engine_load`, the lift 3.02 s (the arm's constant rate); with flow scaling and no mode the
lift is 5.57 s at 700 rpm; with the mode, 1300 rpm from 0.18 s after the PTO went in, held through
the lift (least 1300), `engine_load` 10 % > 33 %, the lift 3.02 s, lowering 3.0 s either way.

Effort **medium**. Permission **plan-mode-first**: the mode's engagement and set speed must be
sourced. Needs phase 6. Independent of 7-11.

A road truck runs a min-max governor (LINEAR), so the refuse body's pump turns at whatever the pedal
gives: parked with the PTO in and the arm raising, the crank sits at idle and the pump's torque
(`RefuseBody.PUMP_KW` over `PUMP_RATED_ENGINE_RPM`) loads an idling engine. A real truck ECU has a
PTO mode that holds a set engine speed while the body works (J1939's PTO governor; its SPNs are
confirmed while sourcing).

1. **Source** the PTO mode: how it engages (PTO switch plus park brake and neutral, the common
   interlock), its set speed or speeds, and its governing (droop or isochronous). A refuse body's
   pump is rated at an engine speed (`PUMP_RATED_ENGINE_RPM` 1300, already sourced); the mode's set
   speed should land on it.
2. **Spec:** a truck-side flag, off by default (one machine's behaviour): `pto_mode_rpm` (0 = none)
   on `TRUCK_BASE` or the garbage truck's variant only. While the PTO is engaged and the drive is
   inhibited (spring brakes on, `Drivetrain.drive_inhibit`), the demand is the higher of the pedal
   and the setting's demand, run through phase 6's governor law (`PedalMap.governor_fuel`) at the
   sourced droop. Out of the mode, LINEAR as today. The law and its stiffness are reused, never a
   second copy: the mode picks the governor, it does not reimplement it.
3. **Honest pump flow:** if the arm's rate is a constant today, decide whether it scales with engine
   speed over `PUMP_RATED_ENGINE_RPM` (flow is the pump's displacement times its speed); measured
   before and after.
4. **Tests:** the mode engages only with PTO in and the drive inhibited; parked it holds the set
   speed within its droop under the pump's load; out of the mode the fuel is bit-for-bit LINEAR.
5. **Measure:** a parked arm cycle (the PTO in, the arm raised) printing rpm, `engine_load` and the
   cycle time, before and after; the truck family's `doc=accel` and `doc=cruise` rows unchanged.

Done when the garbage truck parked with the PTO in holds the sourced set speed through an arm cycle,
`docs/heavy_vehicles.md`'s refuse-body section states the mode, and no driving figure moves. Drive
check: the garbage truck parked, PTO on, the arm raised; the engine note rises to the set speed and
holds.

## Phase 6c — `measure_grade`'s slip-limited driver on a governed tractor (done)

Done 2026-10-21, tool-only (no vehicle moves, no drive check). Decision (user): the loop runs on
the fuel, sent through `PedalMap.pedal_for`, the measure tools' PI convention. Bisected
(`measure_grade -- tractor-kenney asphalt mud mfwd diff tc`): 80.0 / 42.1 % at phases 4d and 5,
70.4 / 26.4 % at phase 6, so the governor's pedal-as-setting was the cause. After: 78.0 / 42.1 %,
against the floored diff-lock row's 78.0 / 31.7; every other `doc=grade` row byte-identical.

Effort **medium**. Permission **plan-mode-first**: the driver model is the user's call. Needs
phase 6. Independent of 7-11.

`measure_grade`'s `tc` flag is the tool's driver, not the vehicle's traction control (the tractor
ships `tcs_equipped` false): it feathers the pedal to hold the rear slip at the grip peak and to
keep the front axle loaded, so its row measures the tyre, not a floored driver. It now measures
less than the floored pedal it is meant to beat: `tractor-kenney` with MFWD and the diff lock climbs
70.4 % on asphalt and 26.4 % in mud under `tc`, against 78.0 / 31.7 % floored (deterministic,
`measure_grade -- tractor-kenney mud mfwd diff tc`). The committed table read 80.0 / 42.1 % from
phase 2 until phase 7 regenerated it, so no commit pins the phase that moved it; phase 7's stepped
paths are identical (checked in its review).

Suspects, both phase 6's all-speed governor, where the pedal is a speed setting:
- **The setting:** a feathered pedal lowers the setting, and the governor line cuts fuel at the
  crank speed the climb lugs at, so easing off costs far more torque than it would on a linear map.
- **The loop gain:** `TC_GAIN` and `TC_LIFT_GAIN` integrate the pedal at a rate tuned on the linear
  map; through the governor's slope (`PedalMap.governor_stiffness`) the same step moves the torque
  far more, and the integrator may limit-cycle around the slip target.

1. **Bisect:** re-measure the `tc` row (asphalt and mud) at the phase 4d, 5 and 6 commits in a
   worktree (`--import` first), and print the trace of the pedal, the setting, crank rpm and the
   rear slip at the phase that moves it.
2. **The driver** (in `tools/measure_grade.gd` if the bisect lands on the governor): decide with the
   user what a driver holding the slip does on a governed tractor (hand throttle at the rated
   speed with the pedal trimming above it, or the loop acting on the pedal through
   `PedalMap.pedal_for`), then fix it there. A vehicle-side cause instead goes back to its phase.
3. **Measure:** `doc=grade`; every row but `tc` byte-identical. Correct `docs/vehicle_measurements.md`
   § the gradeability prose if what it says about `tc` no longer holds.

Done when the `tc` row climbs at least the floored diff-lock row on both surfaces, or the table's
prose states the measured reason it cannot. No drive check if the fix stays in the tool: no vehicle
moves.

## Phase 6d — `TcPedal` on a governed tractor

Effort **medium**. Permission **plan-mode-first**: the fix moves the petrol bodies' `tc` figures
too, which is the user's call. Needs phase 6c (its fuel-space decision). Independent of 7-11.

`tools/tc_pedal.gd` is the other measure tools' slip-limiting driver (`measure_vehicles`' `tc`
launches and the `doc=accel` / `doc=tyres` `tc` columns, `measure_rough`'s `tc` crawls). Like
`measure_grade`'s loop before 6c, it integrates the PEDAL (a log integral, `TcPedal.step`), so on
an ALL_SPEED tractor (`tractor-kenney`, `tractor-cvt`) it feathers the governor's speed setting.
Phase 6 checked only the floored figures, so the tractors' `tc` rows may have moved unseen.

1. **Bisect:** the tractors' `tc` figures (`measure_vehicles -- tractor-kenney 60 tc`, the
   `measure_rough` `tc` rows on both tractors) at phase 5 (`b32d5a7`) and phase 6 (`ab86496`) in a
   worktree outside the repo (`--import` first). No move → close the phase with that finding.
2. **The driver:** `TcPedal.step` integrates the delivered fuel and the callers send
   `PedalMap.pedal_for(spec, fuel, rpm)`, 6c's convention. `bite_pending` reads the pedal it sends
   (`Drivetrain.launch_target_rpm` takes the pedal), not the fuel. Decide with the user whether every
   map takes it (the petrol bodies' `tc` rows move with the concave map) or ALL_SPEED only.
3. **Measure:** `doc=accel`, `doc=tyres`, `doc=rough`; the floored figures byte-identical, the LINEAR
   bodies' `tc` figures byte-identical, the moved rows recorded and their prose re-read.

Done when the tractors' `tc` figures are at least their phase-5 values or the prose states the
measured reason, and no floored figure moves. No drive check: no vehicle moves.

## Phase 7 — The CVT tractor (done)

Done 2026-10-20; the drive check is pending (the two tractors back to back on the haul ramp and in
level 1's field: the CVT pulls away with no step, holds on the ramp with the pedal up, and its rpm
holds while the harrow's draft slows it). Decisions (user): the ZF Eccom / AutoPowr class, four
ranges changing as it drives; the ratio's rate in JCB's high band, 1.5 m/s². Contract v54
(`gear_ratio`, SPN 526; `gear`'s desc names the range), paired with sloppyCAN (ETC2 in the J1939
flavor, SPN 526 decoded, the Carlito panel's ratio row). The tour, sources and figures:
`docs/heavy_vehicles.md` § The CVT tractor, `docs/sources.md` § CVT. Found while measuring:
- **A CVT governs road speed through its ratio**: its ratio held the ground speed off the crank,
  so the road-speed governor's fuel fade read as overload and pulled the box down to its limit
  speed (38.5 km/h at 2000 rpm). It takes no fuel fade; the speed command is capped instead.
- **Active standstill takes the pawl's path**: the coupling's hold at ratio 0 let the tyres creep
  (34-148 mm of roll-back); the wheels' lock with its stiction holds 2-7 mm bare, 20-31 mm with the
  tipper. The STANDSTILL compromise is retired on this variant.
- **A pressure cut-off**: against wheels that do not follow, the ratio wound up and the relief
  limit-cycled with the lock (4 s period); it now never grows a step past the wheels' own.
- The stepped bodies are byte-identical (`tractor-kenney`, `sedan`, `semi` traces, before and after).

Measured (for phase 11's distillation; the tour states them without figures):
- Floored from rest, bobtail: 0.15-0.18 g, no step; D1>D2 at 6.7 km/h (1.63 s), D2>D3 13.7 (2.98 s),
  D3>D4 26.0 (5.53 s); the crank 2176-2600 rpm after 1 s (limit speed 2000); front axle launch 0.5 of
  6.7 points. Peaks 40.7 km/h as the governor lifts the unloaded crank faster than the ratio unwinds,
  settles 39.8 km/h at 2545 rpm.
- Roll-back (released, floored 0.5 s later): 2.0 / 7.1 mm on 10 / 25 %, 20.1 / 31.3 mm with the tipper
  (the powershift's brake hold 0.4 / 1.6 and 0.2 / 0.8).
- `20 plough governor`, 8 km/h commanded in range 2: the harrow settles 3.5 % under 2043 (shaft 520 rpm)
  at 7.5 km/h, the plough 3.5 % (521) at 7.2 (7.8 raised); the powershift's 3.4 / 3.2 %.

Effort **high**. Permission **plan-mode-first**. Contract bump. Needs phase 6.

1. **Source** a power-split CVT: its range count and how ranges change (an automatically-ranging
   box such as Deere's IVT / AutoPowr class shows its range on the byte as it drives; a Fendt-style
   two-range box changes at rest), its efficiency against ratio (the hydrostatic share costs
   efficiency), its ratio-change rate, and active standstill.
2. **Spec:** a CVT flag on `VehicleSpec` (the ranges' spans; empty = stepped, today's bodies). The
   ratio is drivetrain state, rate-limited, entering the spin solve as the gear `G`: the reflected
   `J G²` moves with it, and the torque a ratio change takes from the crank's inertia is solved in
   the step, never applied after it.
3. **Controller:** the engine-speed control holds the governor's target rpm, choosing the ratio
   for the commanded ground speed. Drive modes: the pedal commands ground speed (pedal mode), or
   the hand throttle sets engine speed and the pedal ground speed. No `ShiftPolicy`; `gear` out
   publishes the range; in manual bridge mode the byte selects it. Active standstill holds at a
   ratio of zero. Whether it retires the STANDSTILL hill-hold COMPROMISE on this variant is decided
   on measurement.
4. **Variant:** `tractor-cvt` in `gen_kenney_vehicles.gd` (a `TRACTOR_BASE` override plus a regen),
   `VehicleCatalog`, the levels whose `LevelInfo` allow the tractor, and a selector card (the user
   runs `gen_vehicle_thumbs.tscn`, windowed).
5. **Signal:** `gear_ratio` (out, f32, J1939 SPN 526 Actual Gear Ratio; truck and tractor, `j1939`).
   That is the CVT's own state on the bus, and it reads the stepped boxes' ratio honestly too.
   sloppyCAN: ETC2's bytes 2-3 (0.001 per bit) in the J1939 flavor.
6. **Gates:** the new body joins every catalog test, the tracking pass, gradeability, rollback,
   park and the implements' runs. The shift trace's gates (dwell, landing, hunting) do not apply to
   a box with no shifts; the trace reports ratio and crank rpm instead. `BrakeSizing` reads gear 1
   at stall (`Drivetrain.stall_axle_torque`): on a CVT that means the deepest ratio the controller
   launches at, defined in the phase. The brakes stay the powershift tractor's hardware.

Done when `tractor-cvt` drives every scenario the powershift tractor does, holds its target rpm
through a launch and a draft onset, and publishes range and ratio; and `docs/heavy_vehicles.md` has
its section. Drive check: the two tractors back to back on the haul ramp and in the field.

## Phase 7b — The CVT's engine-speed management and its unwind rate

Effort **high**. Permission **plan-mode-first**: the strategy and the rates must be sourced. Needs
phase 7. Independent of 8-11.

Two things phase 7's measurements showed, both the controller's, neither the box's:

- **No economy at part speed.** In pedal mode the setting rises with the pedal
  (`PedalMap.setting_rpm` of the demand), so a light cruise runs the engine high on its governor
  line: `doc=cruise` reads `tractor-cvt` at 15 km/h on 1469 rpm and 4.9 L/h against the powershift's
  1187 rpm and 3.7 L/h. A real CVT's engine-speed management (Fendt's TMS, Deere's Efficiency
  Manager) drives the engine at the lowest speed that delivers the power asked, which is the point
  of the box: the opposite reading.
- **An overshoot at the top.** Floored, it peaks at 40.7 km/h and settles at 39.8: as the load
  comes off, the governor lifts the crank faster than the ratio may unwind at the one symmetric
  `cvt_accel_ms2`. JCB's patents run the ratio faster toward underdrive than toward overdrive.

1. **Source** an automatic engine-speed management strategy for a CVT tractor in its pedal mode
   (Renius & Resch's Table 3, "combined open loop control of engine and transmission (transports)";
   Fendt TMS and Deere Efficiency Manager documentation; patents on engine-speed setpoint from
   power demand), and the underdrive-ward ratio rate (US 11,994,210 and its family; a published
   CVT tractor acceleration trace, Renius & Resch Fig. 37).
2. **The setting in pedal mode** (`Drivetrain._process_cvt`): with the hand throttle off, the
   governor's demand is the setting that carries the power asked at the sourced margin (the road
   load the box already reads, plus the commanded acceleration), floored at a sourced minimum and
   never past the pedal's own setting; with the hand throttle on, unchanged (it pins engine speed,
   PTO work). Never in `src/input/`, and the engine law stays the governor's.
3. **Two rates:** `cvt_accel_ms2` toward overdrive, a sourced faster one toward underdrive (or a
   factor on it), so the ratio follows a crank the governor lifts.
4. **Tests** (`test_drivetrain`): the pedal-mode setting falls with the load at a held speed and
   rises with it, never past the pedal's; the hand throttle overrides it; the unwind rate.
5. **Measure:** `doc=cruise` (the CVT's rpm and burn at 15 / 25 / 34 km/h, against the powershift),
   the trace (peak against settled top speed), `20 plough governor` unchanged (the hand throttle's
   path), the roll-back and the CI gates.

Done when `tractor-cvt` cruises at part speed under the powershift's rpm and burn, the floored peak
is within the road-speed governor's band of its settled top, and the governor's hold is unchanged.
Drive check: a light cruise on the road (the engine note low, then rising when the pedal goes down).

## Phase 8 — Handling: probes and primary sources (no body moves)

Effort **high** (research; the probes alone are low). Permission **normal**.

1. **`measure_rough` probes:** `rollsteer=<front>,<rear>` and `angdamp=<1/s>`, as
   `measure_vehicles` has them. Attributing a rough-ground cell takes a hand edit of the body's
   `.tres` today. The override's application moves into `measure_rig.gd`, shared by both tools
   (`tools/CLAUDE.md`: shared setup lives there), never a copy.
2. **Primary sources** (`docs/sources.md` § Roll steer, § Linear understeer):
   - Gillespie ch. 6;
   - SAE 1999-01-1323;
   - NHTSA's SPMD / VRTC measurements.

   Upgrade the multi-link and leaf estimates, confirm the rear band's sign, and replace the
   population K band (0.7-8.2 deg/g, US vehicles at 0.15 g) with class bands. Find a sourced
   leaf-axle roll-steer figure (phase 9) and a compliance-steer figure per class (the brief in
   phase 9). A source that cannot be opened stays graded as what was read (an abstract is
   secondary).

Done when every row of the roll-steer table carries its new grade, and the class K bands are in
(or each class with no band found is stated).

## Phase 9 — Handling: truck roll understeer and the compliance-steer brief

Effort **high**. Permission **plan-mode-first**. Needs phase 8.

1. **Truck understeer.** With no angular damping the Kenney trucks read neutral to slightly
   oversteer at the slowest step (`garbage-truck` K -0.01 deg/g), where a real truck understeers.
   - Fit the sourced leaf-sprung roll understeer to `TRUCK_BASE`'s rear, and to the semis' drive
     axle if the source covers a tandem.
   - Tune it with the `vehicle-feel` skill against the step pass at the slowest step.
     `garbage-truck` must read understeer (K > 0) with no new spun or tipped cell.
   - The semis' COMPROMISE (`docs/vehicles.md` § Balance: even bars, the load law off) is retired
     with it if they then hold the class split and the law on. That is decided on measurement.
2. **The compliance-steer brief.** Write brief 17 in `docs/plans/mechanical_update/`, in the brief
   format (`00_README.md`):
   - the subject: rear toe-in under side force, the classic cure for lift-off oversteer;
   - what it may retire: the lift-off cases, i.e. the `rear_lat_grip` 1.08 that the COMPROMISE
     bodies carry (`docs/vehicles.md` § Balance) and the `police` / `suv-luxury` lifted spins;
   - the size: its linear-K share is small (compliance steer 0.5 of Bundorf's illustrative 4.1
     deg/g, side-force 0.4 of it; roll camber, 1.2, is the larger share left).

   Add it to the README's order table. Implementing it is its own plan.

Done when the trucks understeer at the slowest step (inside their class band where phase 8 found
one), and brief 17 exists.

## Phase 10 — Handling: the corner pass in `BalanceModel`

Effort **high**. Permission **plan-mode-first**. Needs phase 8.

The pass runs driven, on its speed hold, at 9-23 deg of lock. There:
- the turn's drive spends a driven axle's friction ellipse;
- a front-driven axle's tilted drive carries side force;
- a rear-driven body's front makes a few points over its static share.

`BalanceModel.limit` is free-rolling at small steer and models none of it. The drive term alone
makes the calls worse (it flips `firetruck` and the tractor), so the pass's geometry is modelled
whole, the parts landing together. Calibrate on every body against the pass's printed `pred`, then
judge `delivery` (rear-first there). `limit` stays as it is; the pass gets its own prediction beside
it.

Done when the corner pass's `pred` calls the measured first-saturating axle on every body, including
`delivery`, and § Balance's "The corner pass is not `limit`" paragraph is rewritten.

## Phase 11 — Distill and close

Effort **low**. Permission **accept-edits**.

- Distill brief 16's lasting content into `docs/drivetrain.md`, `docs/heavy_vehicles.md` and
  `docs/sources.md`; mark row 16 landed in `00_README.md` and delete the brief. In the same change,
  repoint its backticked citations (`docs/drivetrain.md` twice, `docs/heavy_vehicles.md` once) and
  grep code comments for "brief 16".
- Re-read `docs/TODO.md` against the result. The RAMN item stays until the firmware lands.
- Delete this plan, repointing what cites it in the same change (`check_docs` fails a link to a
  deleted plan): `docs/vehicles.md` § Balance, `00_README.md` rows 15 and 16, and `docs/TODO.md`'s
  RAMN item. Then `node tools/check_docs.mjs` and `tools/preflight.ps1` must be clean.
