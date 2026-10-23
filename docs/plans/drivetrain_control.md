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
4, 4b, 4c, 4d, 5, 6, 6b and 7 pending; 6c has none); phases 6d, 7b and 8-11 not started. A done
phase keeps only what it found and its pending drive check; its lasting content is distilled by
phase 11.

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

- **One gear byte, no side signal.** The brief's route (a J1939 ETC2 gear signal beside a capped
  RAMN byte) existed only because RAMN stopped at 6. With RAMN raised, the one `gear` byte carries
  the real gear; sloppyCAN already maps it onto TC1 / ETC2 (`../sloppycan/j1939-flavor.js`).

- **`fuel_rate` rides no `0x52x` frame.** It is `nmea2000`-flavored, so its coverage is that
  packer's (127489, now gated to a boat on the link), and `0x520`-`0x528` is a frozen layout. A truck
  or tractor sends LFE1 from `../sloppycan/isobus.js` beside EEC2; a car's burn is on no bus.

- **A laden semi skips too** (phase 4, measured): with the 24 t box, D2 and D3 are traction-bound
  and rev out inside the 1.5 s dwell, so the full-pedal skip takes D1>D4>D6 and steps singly from
  D6 (8 AMT cuts to D12, not eleven). The front-axle gate's failures are the six-speed's, at the
  same size (`docs/handling.md` § Pitch).

- **A laden launch locks under its downshift point** (phase 4c, measured): the drive tyres hold
  ~10 % slip, so the semi's D3 locked at 773 road rpm against the 780 point and stepped D3>D2. The
  lock starts the dwell's clock (`Drivetrain._start_gear_step`). Holding the launch's floor until
  the road speed cleared the point instead left the floored `plough` spinning in D7 for good: its
  crank sits on the governor, so it never reads as lugging.



## Recommended order

| Phase | Item | Contract | Needs | Status |
| --- | --- | --- | --- | --- |
| 1 | Compass and true wind on the land dashboards (from TODO) | `twd`/`tws` on land | — | done |
| 2 | A progressive pedal map (16.4) | — | — | done |
| 3 | Fuel and fuel rate from delivered power (16.5) | `fuel_rate` | 2 | done |
| 4 | Gear counts: semis 12, tractor 16, bus D1-D24 (16.1) | `gear` enum | 2 | done |
| 4b | The front-axle gate on the tractor's launches and shifts (found in phase 4) | — | 4 | done |
| 4c | The gearbox's picture of the rig: grip and dead time in `time_to_upshift`, a mass-aware start gear (found in phase 4) | — | 4, 4b | done |
| 4d | The bobtail semis' front-axle gate: a one-tick contact spike, a launch at the bar (found in 4c) | — | 4c | done |
| 5 | The PTO's power on the crank (found while planning) | — | — | done |
| 6 | All-speed governor and hand throttle (16.2) | `hand_throttle` | 4, 5 | done |
| 6b | The garbage truck's PTO engine-speed control (found in phase 6) | — | 6 | done |
| 6c | `measure_grade`'s slip-limited driver on a governed tractor (found in phase 7) | — | 6 | done |
| 6d | `TcPedal` on a governed tractor: `measure_vehicles` / `measure_rough` (found in 6c) | — | 6c | |
| 7 | The CVT tractor (16.3) | `gear_ratio` | 6 | done |
| 7b | The CVT's engine-speed management and its unwind rate (found in phase 7) | — | 7 | |
| 8 | Handling: `measure_rough` probes and the primary sources (from TODO) | — | — | |
| 9 | Handling: truck roll understeer; the compliance-steer brief (from TODO) | — | 8 | |
| 10 | Handling: the corner pass in `BalanceModel` (from TODO) | — | 8 | |
| 11 | Distill and close | — | all | |

6d and 7b are independent of 8-11. 8-10 are independent of the drivetrain chain, research-led, and
on different tables (step and corner, against the drivetrain's launch, shift and cruise); phase 8
can run any time, also in a worktree, and 9 and 10 wait for its sources. No remaining phase expects
a contract bump; one that finds it needs one makes it a paired change with `../sloppycan` (the
`contract-edit` skill).

## Constraints that bind every phase

- `00_README.md` § Common context for every brief binds: 60 Hz with no clamp weakened; every new torque on a wheel
  or the crank goes inside the semi-implicit step (`RayWheel._integrate_spin`, `crank_compliance`);
  Kenney bodies change in `tools/gen_kenney_vehicles.gd` plus a regen; the semis' and trailers'
  header derivations are rewritten with their numbers; the `vehicle-feel` skill for every feel change.
- **One engine law on the delivered fuel** (`src/vehicles/CLAUDE.md`): the pedal map, the governor
  and the CVT controller all output `applied_throttle`; `ShiftPolicy` keeps reading the driver's
  demand (the pedal, or the higher of pedal and hand throttle on the tractor).
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

## Phases 1-4 (done)

Pending drive checks:
- **1** (`twd` / `tws` on car, truck, tractor; the compass rose on land): a
  crosswind on the straight; the arrow names the side the body drifts away from.
- **2** (the petrol map, EPA's L15B7; the road diesels LINEAR): a gentle pull-away and a held part
  pedal on the `sedan` and `delivery`.
- **4** (semis 12, tractor 16, the bus D1-D24, the full-pedal skip): a semi and the tractor floored
  and at part pedal; the shifts read as steps, not lurches.

Phase 3 (`fuel_rate`, the Willans line) has no drive check.

## Phase 4b — The front-axle gate on the tractor's launches and shifts (done)

Drive check pending: the tractor floored bobtail, and with the tipper on the haul ramp; its nose
settles after each shift without bobbing. Neither failure was pitch damping:
- **Bobtail:** without a reduction, the powershift hands the crank's `J Δω / t` to the wheels
  through the handover (D7>D13 `Tc` ~1200 N·m against ~300) and drops it on the lock tick. Every
  seamless box takes `Drivetrain.handover_fuel` (`docs/drivetrain.md` § The shift's handover, a
  COMPROMISE at `TRACTOR_BASE`).
- **Tipper:** a braked rig settles with a push on its coupling (−23 kN on the drawbar), which the
  parked front already carries. `measure_vehicles` counts transfer since parked. Its launch fails on
  the tipper's brake venting (`docs/handling.md` § Pitch).

## Phase 4c — The gearbox's picture of the rig (done)

Drive check pending: a semi stabbed from a steady 30 and 50 km/h, laden and bobtail; the tractor
pulled away empty and with the tipper on the flat. `ShiftPolicy.time_to_upshift` now caps the drive
at the driven tyres' static grip and adds an AMT shift's dead time; `ShiftPolicy.start_gear` reads
the rig's mass (Eaton's slip-time rule; the semis' `start_gear_max` 6). Measured:
- Starts on the flat: semi bobtail D6 (D6>D8, then singly; 0-50 km/h 4.93 s against 5.88), +24 t D3
  (D3>D5, then singly; 16.13 s against 15.35); tractor D7 bare (unchanged), D6 with the tipper
  (D6>D10>D13>D15>D16), D4 with it on 10 %.
- Kickdown: the semi + 24 t kicks D7>D6 at 30 km/h and D11>D10 at 70, hunting PASS on every body.
  With the hold judged on the rig, the ceiling is 85 % of the redline under `shift_up_rpm`, and the
  landing margin stays only with no estimate. The cars now kick two or three gears where they took
  one or two.
- `measure_vehicles`' cruise windows stop at the strip's end: `semi-conventional`'s 85 km/h pulse
  after a 120 s kickdown ran off it and the gate judged the respawn.

## Phase 4d — The bobtail semis' front-axle gate (done)

Drive check pending: the cab-over floored from rest, bobtail; the nose rises once and settles on its
pull without bobbing back past it. Both bobtail units pass every event. Neither failure was the
gate's reading:
- **`semi-conventional`: the contact query.** At the spike's tick both steer wheels' sweeps stopped
  a step high and the rest test at the touching stop read clear, so `_contact_query` settled on the
  free stop before it: compression 78.11 > 80.00 > 77.82 mm, the wheel 18.76 > 20.56 > 16.61 kN.
  A touching stop the rest test reads clear is a free one, and the bracket moves a step on
  (`docs/vehicles.md` § Physics derivations and figures; `test_wheel_spin`).
- **`semi`: real pitch, on the front rebound damper.** Swept one at a time, only the front rebound
  moves the launch (15800 > 17900: 6.4 > 5.5 points). Both semis' front dampers take the road band's
  ends at the bobtail steer corner, 13500 / 17900 (zeta 0.30 / 0.40; 0.27 / 0.36 coupled to the box).

Measured after: `measure_semi_launch strict` steer floors 11353 / 13782 N, from 10975 / 13514;
`track strict` and the drained-air probe pass; the tractor bare unchanged, the tipper's launch
21.2 of 18.7.

## Phase 5 — The PTO's power on the crank (done)

Drive check pending: the harrow lowered in level 1's field with the PTO in, then out (`engine_load`
and rpm drop with it); the mower lowered and raised with the PTO in; the plough with the PTO in
reads as out; the garbage truck's arm raised, PTO and handbrake on (`engine_load` rises while the
arm climbs). `pto_load` is gone; implements declare `pto_power_kw` and the crank takes it as
`Drivetrain.accessory_torque`. Figures: `docs/tractor.md` § Draft, hitch, linkage; sources:
`docs/sources.md` § PTO power. `tractor_pto_speed` spawns the mower raised, so its free-crank hint is
unchanged; with the deck lowered the band needs more pedal.

## Phase 6 — All-speed governor and hand throttle (done)

Drive check pending: set 540 with `0`, lower the harrow into level 1's field with the PTO in, and
watch `pto_rpm` (it settles ~4 % under 540); then a part pedal on the road upshifts and cruises at
the pedal's engine speed. Contract v53 (`hand_throttle`; `pto_rpm` to 1300), paired with sloppyCAN
(the tractor panel's Hand slider, panel-only). Measured:
- Floored, nothing moved: `tractor-kenney 40 trace`, roll-back and gradeability byte-identical.
- `20 plough governor`: lowered at 7 km/h in D2 the harrow settles 3.4 % under the 2043 setting
  (shaft 521 rpm), the plough 3.2 % (522), inside the 7 % droop's 504.7.
- The cruise probes pass every gate; the tractor's cruise row moved (15 km/h in D14 at 1187 rpm).
  The tipper's 8 % climb at 0.6 runs D4 to D14 a gear at a time, 192 m.

The measure tools' PI pedals reach the governor through `PedalMap.pedal_for`, whose setting tracks
the crank, so on a governed box they read as economy driving (high gears, low rpm).

## Phase 6b — The garbage truck's PTO engine-speed control (done)

Drive check pending: the garbage truck parked in N, handbrake and PTO on, the arm raised; the
engine note rises to the set speed and holds, the arm lifts at its rated pace; select D and it drops
to idle. Decisions (user): isochronous (droop 0, no truck figure found), and the arm's flow follows
the pump's speed, capped at rated. Found while sourcing and measuring:
- **The interlock is not `drive_inhibit`** (the air-low gate): a Cummins ECM's PTO mode wants the
  park brake, neutral and at most 2 mph (`docs/sources.md` § PTO power). The neutral interlock
  lives in the drivetrain, which holds the gear (`Drivetrain.pto_set_rpm`).
- **An isochronous line is narrower than a tick**: full fuel moves the free crank ~90 rpm a tick
  against a ~1.3 rpm line, so read at the tick's start it jumped the line and cycled on it (1300 to
  1386 rpm, a ~0.13 s period). A free crank's governor now fuels no more than lands it on the
  setting (`Drivetrain.fuel_to_land`). The tractors' traces stay byte-identical; the droop gates
  are unchanged.

Measured (`measure_vehicles -- garbage-truck 60 arm`): before, 700 rpm through the cycle, 8 % >
30 % `engine_load`, the lift 3.02 s (the arm's constant rate); with flow scaling and no mode the
lift is 5.57 s at 700 rpm; with the mode, 1300 rpm from 0.18 s after the PTO went in, held through
the lift (least 1300), `engine_load` 10 % > 33 %, the lift 3.02 s, lowering 3.0 s either way.

## Phase 6c — `measure_grade`'s slip-limited driver on a governed tractor (done)

Tool-only (no vehicle moves, no drive check). Decision (user): the loop runs on the fuel, sent
through `PedalMap.pedal_for`, the measure tools' PI convention. Bisected
(`measure_grade -- tractor-kenney asphalt mud mfwd diff tc`): 80.0 / 42.1 % at phases 4d and 5,
70.4 / 26.4 % at phase 6, so the governor's pedal-as-setting was the cause. After: 78.0 / 42.1 %,
against the floored diff-lock row's 78.0 / 31.7; every other `doc=grade` row byte-identical.

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

Drive check pending: the two tractors back to back on the haul ramp and in level 1's field; the CVT
pulls away with no step, holds on the ramp with the pedal up, and its rpm holds while the harrow's
draft slows it. Decisions (user): the ZF Eccom / AutoPowr class, four ranges changing as it drives;
the ratio's rate in JCB's high band, 1.5 m/s². Contract v54 (`gear_ratio`, SPN 526; `gear`'s desc
names the range), paired with sloppyCAN (ETC2 in the J1939 flavor, SPN 526 decoded, the Carlito
panel's ratio row). The tour, sources and figures: `docs/tractor.md` § The CVT tractor,
`docs/sources.md` § CVT. Found while measuring:
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
   - The semis' COMPROMISE (`docs/handling.md` § Balance: even bars, the load law off) is retired
     with it if they then hold the class split and the law on. That is decided on measurement.
2. **The compliance-steer brief.** Write brief 17 in `docs/plans/mechanical_update/`, in the brief
   format (`00_README.md`):
   - the subject: rear toe-in under side force, the classic cure for lift-off oversteer;
   - what it may retire: the lift-off cases, i.e. the `rear_lat_grip` 1.08 that the COMPROMISE
     bodies carry (`docs/handling.md` § Balance) and the `police` / `suv-luxury` lifted spins;
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
`delivery`, and `docs/handling.md` § Balance's "The corner pass is not `limit`" paragraph is rewritten.

## Phase 11 — Distill and close

Effort **low**. Permission **accept-edits**.

- Distill brief 16's lasting content into `docs/drivetrain.md`, `docs/tractor.md`, `docs/truck.md`
  and `docs/sources.md`; drop row 16 from `00_README.md` and delete the brief. In the same change,
  repoint what cites it (`git grep 16_drivetrain_control`; "brief 16" in code comments).
- Re-read `docs/TODO.md` against the result. The RAMN item stays until the firmware lands.
- Delete this plan, repointing what cites it in the same change (`check_docs` fails a link to a
  deleted plan): `docs/handling.md` § Balance, `00_README.md` row 16, and `docs/TODO.md`'s
  RAMN item. Then `node tools/check_docs.mjs` and `tools/preflight.ps1` must be clean.
