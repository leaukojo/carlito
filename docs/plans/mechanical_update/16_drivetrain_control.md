# 16 — Drivetrain control: gear counts, governor, CVT, pedal map, fuel

Shared context: `00_README.md`. Root cause: none of the three; the engine and coupling models (05,
06) are in, and what sits between the driver and them (how many ratios, what the pedal commands,
what fuel reads) is still a first cut. Size: large, five separable items.

Builds on `docs/vehicles.md` § Crank and coupling, § Converter, § Hill hold, § The shift policy,
§ Measuring a vehicle. Rule 3: every new state (CVT range, governor droop, fuel rate) is read out of
the sim.

## Why after 10 and 11

- **10** changes every body's radius and re-derives its gearing; item 1 re-derives the trucks' and
  tractor's ratios. Done before 10 it is done twice.
- **11** gives the tractor a real draft load; item 2's governor and hand throttle are judged by
  holding PTO speed through that load change.

## 1. Real gear counts for trucks and tractors

- Trucks and tractor ship 6 forward ratios only because the contract's `gear` byte (RAMN: 1-6 =
  D1-D6) caps `Drivetrain.TOP_GEAR` at 6. Real: heavy truck 12-18 (an automated 12-speed is typical),
  tractor powershift 16-24.
- Squeezed into 6, the trucks step ~1.5-1.76x per gear (real ~1.2-1.3x), the tractor 1.35x (real
  1.10-1.15x): every upshift drops rpm by a third and reads as a lurch. The semis' light map cannot
  land in the D13's cruise band and their skip-shifts never fire (`docs/vehicles.md` § The shift
  policy); a floored empty tractor holds D4 ~0.5 s, under the trace's 1.0 s dwell gate
  (`docs/heavy_vehicles.md`).
- **Route:** keep the RAMN byte as the shared coarse signal (direction and a D range) and add a
  truck/tractor-only J1939 gear signal (ETC2 selected/current gear, SPN 524/523) reporting the real
  gear. Contract change (`contract-edit` skill, sloppyCAN copy); `TOP_GEAR` then bounds only the
  RAMN mapping.
- **Done when** the truck family runs 12 ratios and the tractor ~18 over the same speed span, the
  trace gates pass, and the skip-shifts fire.

## 2. Diesel governor and hand throttle

- On the heavies the pedal sets an engine-speed target and an all-speed governor fuels to hold it,
  with droop under load. The crank's idle controller (`Drivetrain.fuel_to_land`) is that governor at
  one target.
- A hand throttle holds PTO speed (540/1000) through a load change. Needs a contract signal for the
  hand throttle; it enters through `VehicleInput` (root rule 5).
- **Done when** the tractor at 540 PTO holds speed within its droop as 11's draft comes on.

## 3. CVT

- Most tractors over ~150 hp and many cars: ratio varies continuously while the engine holds a
  target rpm (item 2's governor). The gear byte publishes the mechanical range (2-4 on a tractor
  CVT). On the tractor the pedal can command ground speed (a real drive mode).
- A user decision first: which bodies get one (a variant, or replacing a box).

## 4. A progressive pedal map

- The pedal is the delivered fuel fraction (`Drivetrain.crank_torque`), so the same pedal makes
  power in proportion to rpm, and the light-pedal upshifts make a held part pedal slow (`sedan` 0-50
  at pedal 0.3: 40.55 s; `docs/vehicles.md` § The shift policy).
- Source a car and a diesel pedal map; put it between the pedal and the fuel (never in
  `src/input/`, which shapes keys); the shift policy keeps reading the pedal itself. Re-measure the
  part-pedal and cruise probes. Independent of 10 and 11: can go first.

## 5. Fuel from delivered power

- Fuel burn reads `applied_throttle` alone (`VehicleTelemetry.fuel_step`), so the low-rpm cruise
  (`sedan` 60 km/h in D6 at ~1600 rpm) shows in `rpm` and `engine_load` but not fuel.
- Model: crank delivered power (torque at `Drivetrain.rpm` times speed) through a BSFC figure per
  engine class (source a petrol and a diesel map), labelled an honest model. Independent: can go
  first, but read after 4 (the map changes delivered power at part pedal).

## Planning

Planning effort: high (two contract changes, sourced maps, a CVT decision). Phases, likely two
plans: (a) 4 + 5, any time; (b) 1, 2, 3 after 10 and 11, in that order (the CVT needs the
governor).
