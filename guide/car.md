# The cars

<p class="lead">This page shows the parts the simulator models in a car, what each one does, and
the signals it shares with sloppyCAN.</p>

<!-- widgets/anatomy.js: its data block cites the spec or code behind every part and layout -->
<div class="widget an-widget" data-widget="anatomy" data-family="car"></div>

<!-- Shown behind the widget's warning button (GuideKit.limitsButton). -->
<div class="widget-limits" hidden>

The drawing is a diagram, not a plan of the car: each part sits where it reads clearly. The simulator
does not place an engine or a fuel tank inside the body; their weight is part of the car's mass
and its centre of mass.
<!-- VehicleSpec mass, center_of_mass -->

Four layouts stand for fifteen cars. The others differ in weight, engine, gearing, tyres, brakes
and differentials, not in which parts they have: the `hatchback-sports` has a limited-slip front
differential. The heavy vans (`delivery`, `delivery-flat`, `ambulance`)
burn diesel and carry twin rear tyres, which share each rear corner's load for side grip; the
`race-future` drives all four wheels and has no traction control.
<!-- hatchback-sports_spec.tres diff_bias_front 2.5; delivery, delivery-flat, ambulance _spec.tres: fuel_type 1 (DIESEL), rear_twin_tyres (GroundDriveSpec: lateral only); race-future_spec.tres: tcs_equipped absent (false), driven_front true -->

On a car, `speed_limit`, `twd` and `tws` reach sloppyCAN's dashboard but travel in no CAN frame.
<!-- sloppycan js/carlito.js CAN_MAP_ON_REQUEST: a car's speed_limit rides no frame; contract twd, tws: encoded on the boat only -->

</div>

## The controls

<!-- widgets/cockpit.js: its data block cites the signals behind every control -->
<div class="widget an-widget" data-widget="cockpit"></div>

<div class="widget-limits" hidden>

The simulator has no clutch pedal: it works the clutch for you, also when shifting by hand. The
key and the indicators are only worked by sloppyCAN (when driving locally, the key stays at
Ignition).
<!-- InputRouter: "local input is always Ignition"; turnL / turnR have no local source -->

</div>

## The family

All cars share one set of physics, but with different hardware and properties. Details are shown below.

<details><summary>Car list</summary>

| Vehicle | What it is | Weight, about | Driven wheels |
| --- | --- | --- | --- |
| `sedan` | Family saloon | 1.2 t | front |
| `taxi` | Saloon taxi | 1.3 t | front |
| `hatchback-sports` | Hot hatchback, limited-slip front diff | 1.0 t | front |
| `sedan-sports` | Sports saloon | 1.1 t | rear |
| `police` | Police saloon | 1.3 t | rear |
| `suv` | SUV, Torsen-type centre diff, governed to 180 km/h | 1.5 t | all four |
| `suv-luxury` | Luxury SUV, Torsen-type centre diff | 1.6 t | all four |
| `van` | Full-size van, governed to 180 km/h | 1.6 t | rear |
| `pickup` | Pickup, governed to 180 km/h | 1.5 t | rear |
| `pickup-flat` | Single-cab pickup, governed to 180 km/h | 1.5 t | rear |
| `delivery` | 3.5 to 5 t box truck, twin rear tyres | 4 t | rear |
| `delivery-flat` | 3.5 to 5 t flatbed truck, twin rear tyres | 4 t | rear |
| `ambulance` | 5 t ambulance, twin rear tyres, governed to 150 km/h | 4.8 t | rear |
| `race` | Open-wheel racing car: slicks, wings, limited-slip rear | 0.9 t | rear |
| `race-future` | Futuristic racer: slicks, wings, all-wheel drive, no traction control | 0.85 t | all four |
<!-- *_spec.tres mass, driven_front / driven_rear (GroundDriveSpec default rear), speed_limit_kmh, diff biases; GroundDriveSpec.rear_twin_tyres on delivery, delivery-flat, ambulance -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `tcs_off` | in | flag | Switches traction control off (Car). |
| `esc_off` | in | flag | Switches stability control off, and traction control with it (Car and truck). |
<!-- contract tcs_off vehicles [car], esc_off [car, truck]: the car's signals the truck and tractor do not all share -->

[See all signals](signals.md)


## Related

- [Forces on a vehicle](forces.md): the forces these parts produce, all at once.
- [Glossary](glossary.md): every term on this page.
