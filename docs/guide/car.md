# The cars

<p class="lead">The car family is fifteen vehicles: thirteen for the road, from a light hatchback
to a five-tonne ambulance, and two racing cars. They share one set of physics; what changes
between them is the hardware each one carries.</p>

## The family

| Vehicle | What it is | Weight, about | Driven wheels |
| --- | --- | --- | --- |
| `sedan` | Family saloon | 1.2 t | front |
| `taxi` | Saloon taxi | 1.3 t | front |
| `hatchback-sports` | Hot hatchback, limited-slip front diff | 1.0 t | front |
| `sedan-sports` | Sports saloon | 1.1 t | rear |
| `police` | Police saloon | 1.3 t | rear |
| `suv` | SUV, Torsen-type centre diff | 1.5 t | all four |
| `suv-luxury` | Luxury SUV, Torsen-type centre diff | 1.6 t | all four |
| `van` | Full-size van, governed to 180 km/h | 1.6 t | rear |
| `pickup`, `pickup-flat` | Pickups, governed to 180 km/h | 1.5 t | rear |
| `delivery`, `delivery-flat` | 3.5 to 5 t delivery vans, twin rear tyres | 4 t | rear |
| `ambulance` | 5 t ambulance, twin rear tyres, governed to 150 km/h | 4.8 t | rear |
| `race` | Open-wheel racing car: slicks, wings, limited-slip rear | 0.9 t | rear |
| `race-future` | Futuristic racer: slicks, wings, all-wheel drive, no traction control | 0.85 t | all four |
<!-- *_spec.tres mass, driven_front / driven_rear (GroundDriveSpec default rear), speed_limit_kmh, diff biases; GroundDriveSpec.rear_twin_tyres on delivery, delivery-flat, ambulance -->

Pick one in the GARAGE (**G**), or press **V** to step through the bodies.

## What each car has

Every car has:

- [Tyres and slip](tyres.md) on four wheels, and a choice of [tyre class](surfaces.md#tyre-classes)
  for most of them.
- [Steering](steering.md) with a speed taper and full Ackermann.
- [Suspension](suspension.md) with anti-roll bars and anti-dive and anti-squat links, which shape
  its [weight transfer](weight-transfer.md).
- A petrol [engine](engine.md) on the cars and a diesel on the vans, a six-speed automatic
  [gearbox](gearbox.md) with a [torque converter](coupling.md), and
  [differentials](differentials.md).
- [Brakes](brakes.md) sized from a real car of its class, with a handbrake and a park pawl.
- [ABS, traction control and stability control](driver-aids.md), and
  [hill-start assist](holding.md#hill-start-assist).
- [Air drag and rolling resistance](resistance.md), and a crosswind from the
  [conditions](conditions.md).
- The [fuel, coolant and battery models](aux.md), and [position and distance](position.md).

### The exceptions

- **The racing cars** have a clutch and a sequential gearbox, no ABS and no stability control,
  no park pawl, slick tyres only, and [downforce](resistance.md#downforce-on-the-racing-cars). The
  `race` has traction control; the `race-future` has none.
- **The heavy vans** (`delivery`, `delivery-flat`, `ambulance`) have twin rear tyres and van
  brakes.
<!-- race_spec.tres / race-future_spec.tres: coupling CLUTCH, abs_equipped false, esc_equipped false, park_pawl_torque 0, tyre slick; race tcs_equipped true -->

## Where to drive them

Cars are allowed on every level but Open Sea. **Car Arena** is theirs alone: a plateau with a
straight, corners, a wet bend and a tyre pad of dry, wet and snow strips.
<!-- *_info.tres allowed_vehicles; level_registry car_arena desc -->

## What you see in sloppyCAN

A car uses the shared driving signals (pedals, steering, gear, key, lamps) and the shared
telemetry (speed, rpm, accelerations, slip, brake temperature, fuel and coolant). Its own extras
are `tcs_off` and `esc_off`. Each idea page lists its signals.

## Related

- [Glossary](glossary.md): every term on this page.
