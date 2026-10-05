# TODO

## Drivetrain: transmission and engine control

These items build on two briefs: the engine as a rotating mass, the coupling model, and creep and
hill hold (`mechanical_update/05_engine_driveline_inertia.md`); the shift policy, start gear and
shift trace (`mechanical_update/06_shift_schedule.md`). Rule 3 applies throughout: every new state
(CVT range, governor droop) is read out of the sim, never a display fiction.

- **CVT.** Most tractors over ~150 hp and many cars: ratio varies continuously while the engine
  holds a target rpm. The gear byte publishes the mechanical range (2-4 on a tractor CVT), which is
  honest. On the tractor the pedal can command ground speed (a real drive mode).
- **Diesel governor and hand throttle.** On the heavies the pedal sets an engine-speed target and an
  all-speed governor fuels to hold it, with droop under load. A hand throttle holds PTO speed
  (540/1000) through a load change, which is what PTO work actually looks like. Needs a contract
  signal for the hand throttle.
- **Real gear counts for trucks and tractors.** Both ship 6 forward ratios only because the
  contract's `gear` byte (RAMN semantics: 1-6 = D1-D6) caps `Drivetrain.TOP_GEAR` at 6. Real
  machines have far more: a heavy truck 12-18 (an automated 12-speed is typical), a tractor
  powershift 16-24. Squeezed into 6, the trucks step ~1.5-1.76x per gear (real ~1.2-1.3x) and
  the tractor 1.35x (real 1.10-1.15x), so every upshift drops rpm by a third and reads as a lurch.
  Target: the truck family on 12 ratios and the tractor on ~18, each re-derived over the same
  speed span. The route: keep the RAMN byte as the shared coarse signal (direction and a D range)
  and add a truck/tractor-only J1939 gear signal (ETC2 selected/current gear, SPN 524/523, which
  carries far more than 6) reporting the real gear. A contract change (`contract-edit` skill,
  sloppyCAN copy); `TOP_GEAR` then stops bounding the gearbox and bounds only the RAMN mapping.
