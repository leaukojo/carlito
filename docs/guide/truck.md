# The trucks

<p class="lead">This page shows the parts the simulator models in a truck, what each one does, and
the signals it shares with sloppyCAN.</p>

<!-- widgets/anatomy.js: its data block cites the spec or code behind every part and layout -->
<div class="widget an-widget" data-widget="anatomy" data-family="truck"></div>

<!-- Shown behind the widget's warning button (GuideKit.limitsButton). -->
<div class="widget-limits" hidden>

The drawing is a diagram, not a plan of the truck: each part sits where it reads clearly. The simulator
does not place an engine or a tank inside the body; their weight is part of the truck's mass and
its centre of mass.
<!-- VehicleSpec mass, center_of_mass -->

Two layouts stand for four trucks. The fire truck is the garbage truck without the refuse body:
heavier, and governed faster. The `semi-conventional`, a bonneted American
tractor unit, tows the same trailers with no trailer data link: its trailer signals read zero,
and the one thing its trailer can report is the `trailer_abs_lamp` warning lamp, set by sloppyCAN.
<!-- firetruck_spec.tres mass 12000, speed_limit_kmh 110, no `arm` mesh (TruckVehicle._find_rig); conventional_spec.tres trailer_bus_equipped false; contract trailer_abs_lamp (j2497) -->

On a truck, `pto_state`, `trailer_axle_load`, `trailer_brake_applied`, `twd` and `tws` reach
sloppyCAN but travel in no CAN frame. `speed_limit`, `engine_hours` and `axle_load` travel only
when something on the bus asks for them, as on a real J1939 truck.
<!-- sloppycan js/isobus.js ibRpto: "A truck's pto_state therefore rides NO frame"; js/iso11992.js unpackable trailer_axle_load, trailer_brake_applied; js/nmea2000.js: 130306 only with a boat; js/carlito.js CAN_MAP_ON_REQUEST, js/j1939-flavor.js onRequest axle_load -->

</div>

## The controls

<!-- widgets/cockpit.js: its data block cites the signals behind every control -->
<div class="widget an-widget" data-widget="cockpit" data-family="truck"></div>

<div class="widget-limits" hidden>

The simulator has no clutch pedal (it works the clutch for you), and no range or splitter switch.
The retarder, the key and the indicators are only worked by sloppyCAN (when driving locally, the
key stays at Ignition).
<!-- gearbox.md What Carlito simulates; contract retarder: no local key; InputRouter: "local input is always Ignition", turnL / turnR have no local source -->

</div>

## The family

Carlito currently features four diesel trucks (two rigid trucks, two semi tractors), using the same set of physics. The semi trucks can pull semi-trailers.
<!-- fuel_type 1, driven_rear (GroundDriveSpec default), hill_hold 1 in every truck spec; SemiTractor.cycle_implement: box, tipper, tanker, flatbed, bobtail -->

The following semi-trailers are available:

- **Box** (24 t): a full load in a tall box, which catches the most crosswind.
- **Tipper** (19 t): a body that tips up to empty, worked by the truck's PTO.
- **Tanker** (21 t): its liquid surges forward and back when braking and accelerating.
- **Flatbed** (14 t): an open deck, and the lightest trailer.

The semi trucks can also drive without a trailer (this is called a [bobtail](glossary.md#bobtail)).
<!-- TrailerCatalog.TRAILERS and DESC; trailers/*_spec.tres mass -->

<details><summary>Truck list</summary>

| Vehicle | What it is | Weight, about | Gearbox | Governed to |
| --- | --- | --- | --- | --- |
| `garbage-truck` | Refuse truck with a front-loading arm | 8 t | 6-speed automatic | 85 km/h |
| `firetruck` | Fire engine | 12 t | 6-speed automatic | 110 km/h |
| `semi` | Cab-over tractor unit with a trailer data link | 8 t | 12-speed AMT | 90 km/h |
| `semi-conventional` | Bonneted tractor unit, no trailer data link | 8 t | 12-speed AMT | 105 km/h |
<!-- garbage-truck_spec.tres mass 8000, speed_limit_kmh 85; firetruck_spec.tres 12000, 110; semi_spec.tres 8000, 90; conventional_spec.tres 8000, 105; gear_ratios 6 / 12 -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `esc_off` | in | flag | Switches stability control off, and traction control with it (Car and truck). |
| `engine_load` | out | % | Torque given over the most it can give (Truck and tractor). |
| `engine_hours` | out | h | The engine's running time (Truck and tractor). |
| `gear_ratio` | out | ratio | The engaged gear's ratio, without the final drive. 0 in N or P (Truck and tractor). |
| `axle_load` | out | kg | The weight on the rear axle, read off its springs (Truck and tractor). |
| `pto` | in | flag | Engage the PTO (Truck and tractor). |
| `pto_state` | out | flag | The PTO is engaged and the engine is running (Truck and tractor). |
| `retarder` | in | % | The retarder request. |
| `retarder_state` | out | % | The retarder's torque as actually applied, after it fades at low speed. |
| `air_primary`, `air_secondary` | out | bar | The two brake tanks. Warning at 5 bar; the spring brakes apply below 3. |
| `red_stop`, `amber_warn`, `protect_lamp` | in | flag | The fault lamps (stop, warning, and protect for a fluid level, pressure or temperature), set by sloppyCAN. |
| `body_cmd` | in | enum | The refuse body command: Idle, Lift, Dump or Lower (Garbage truck). |
| `body_state` | out | enum | What the body is doing: Stowed, Lifting, Dumping, Lowering or Inhibited (Garbage truck). |
| `body_pos` | out | % | The arm's travel, 0 stowed, 100 raised over the cab (Garbage truck). |
| `body_inhibit` | out | flag | The body is locked out, because the truck is faster than walking pace, the PTO is off or the parking brake is released (Garbage truck). |
| `body_bus` | out | flag | The body's network is powered, which needs the key at Ignition and the PTO engaged (Garbage truck). |
| `hopper_load` | out | % | How full the hopper is. Each dump cycle adds to it, and to the truck's weight (Garbage truck). |
| `trailer_connected` | out | flag | A trailer is coupled and has answered on the trailer link (Semi). |
| `trailer_axle_load` | out | kg | The weight on the trailer's axles, from its own springs (Semi). |
| `trailer_brake_demand` | out | % | The brake demand sent to the trailer. Not the retarder (Semi). |
| `trailer_brake_applied` | out | % | How hard the trailer's brakes have actually applied (Semi). |
| `trailer_abs` | out | flag | The trailer's ABS is holding a wheel (Semi). |
| `trailer_vdc` | out | flag | The trailer's roll control is braking it (Semi). |
| `trailer_ebs_fault` | in | flag | A trailer brake fault set by sloppyCAN, for the dashboard (Semi). |
| `trailer_abs_lamp` | in | flag | The American trailer ABS lamp, set by sloppyCAN (Semi). |
<!-- contract/carlito_contract.json: the truck's signals the car and tractor do not all share (esc_off [car, truck]; pto, pto_state, engine_load, engine_hours, gear_ratio, axle_load [truck, tractor]; the rest [truck]); body_* and hopper_load: RefuseBody (garbage truck); trailer_*: ISO 11992 / J2497 (semis) -->

[See all signals](signals.md)

## Related

- [Towing](towing.md), [Brakes](brakes.md), [Implements and the PTO](implements.md#on-the-trucks).
- [Glossary](glossary.md): every term on this page.
