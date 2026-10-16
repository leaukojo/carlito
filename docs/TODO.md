# TODO

## Drivetrain: transmission and engine control

Builds on `docs/vehicles.md` § Crank and coupling, § Converter, § Hill hold, § The shift policy,
§ Measuring a vehicle. Rule 3: every new state (CVT range, governor droop) is read out of the sim.

- **CVT.** Most tractors over ~150 hp and many cars: ratio varies continuously while the engine
  holds a target rpm. The gear byte publishes the mechanical range (2-4 on a tractor CVT), which is
  honest. On the tractor the pedal can command ground speed (a real drive mode).
- **Diesel governor and hand throttle.** On the heavies the pedal sets an engine-speed target and an
  all-speed governor fuels to hold it, with droop under load. A hand throttle holds PTO speed
  (540/1000) through a load change, which is what PTO work actually looks like. The crank's own
  idle controller (`Drivetrain.fuel_to_land`) is that governor at one target. Needs a contract
  signal for the hand throttle.
- **Real gear counts for trucks and tractors.** Both ship 6 forward ratios only because the
  contract's `gear` byte (RAMN semantics: 1-6 = D1-D6) caps `Drivetrain.TOP_GEAR` at 6. Real
  machines have far more: a heavy truck 12-18 (an automated 12-speed is typical), a tractor
  powershift 16-24. Squeezed into 6, the trucks step ~1.5-1.76x per gear (real ~1.2-1.3x) and
  the tractor 1.35x (real 1.10-1.15x), so every upshift drops rpm by a third and reads as a lurch.
  The shift policy feels it too: the semis' light map cannot land in the D13's cruise band and
  their skip-shifts never fire, and a floored empty tractor holds D4 ~0.5 s, under the trace's
  1.0 s dwell gate.
  Target: the truck family on 12 ratios and the tractor on ~18, each re-derived over the same
  speed span. The route: keep the RAMN byte as the shared coarse signal (direction and a D range)
  and add a truck/tractor-only J1939 gear signal (ETC2 selected/current gear, SPN 524/523, which
  carries far more than 6) reporting the real gear. A contract change (`contract-edit` skill,
  sloppyCAN copy); `TOP_GEAR` then stops bounding the gearbox and bounds only the RAMN mapping.
- **A progressive pedal map.** The pedal is the delivered fuel fraction (`Drivetrain.crank_torque`:
  `f * curve + (1 - f) * motoring`), so the same pedal makes power in proportion to rpm, and the shift
  policy's low light-pedal upshifts make a held part pedal slow (`sedan` 0-50 at pedal 0.3: 40.55 s;
  `docs/vehicles.md` § The shift policy). A drive-by-wire pedal maps to a torque or power demand through a progressive curve, so light pedal
  still pulls at low rpm. Source a car and a diesel pedal map, put the map between the pedal and the
  fuel (never in `src/input/`, which shapes keys), and re-measure the part-pedal and cruise probes;
  the shift policy keeps reading the pedal itself.
- **Fuel from delivered power.** Fuel burn reads `applied_throttle` alone
  (`VehicleTelemetry.fuel_step`: an idle burn plus a load term), so the shift policy's low-rpm
  cruise (`sedan` at 60 km/h in D6 at ~1600 rpm) shows in `rpm` and `engine_load` but not in fuel:
  the same speed held in D2 at ~5000 rpm would burn the same. A rule-3 model reads the crank's
  delivered power (torque at `Drivetrain.rpm` times speed) through a brake-specific fuel consumption figure per engine class
  (source a petrol and a diesel BSFC map), labelled an honest model like the other aux systems.

## Code hygiene

- **~55 run-on `.gd` lines**: a lost `\` continuation left tabs mid-line (e.g. `ground_drive_spec.gd`
  `rear_damper_rebound`). They compile; re-wrap them. Find: `git grep -nP '\S \t{2,}\S' -- '*.gd'`.
