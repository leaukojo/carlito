# The tractors

<p class="lead">This page shows the parts the simulator models in a tractor, what each one does,
and the signals it shares with sloppyCAN.</p>

<!-- widgets/anatomy.js: its data block cites the spec or code behind every part and layout -->
<div class="widget an-widget" data-widget="anatomy" data-family="tractor"></div>

<!-- Shown behind the widget's warning button (GuideKit.limitsButton). -->
<div class="widget-limits" hidden>

The drawing is a diagram, not a plan of the tractor: each part sits where it reads clearly. The
simulator does not place an engine or a fuel tank inside the body; their weight is part of the
tractor's mass and its centre of mass. No tool is drawn on the hitch.
<!-- VehicleSpec mass, center_of_mass -->

The two layouts are the two tractors: one body, with a different gearbox.
<!-- gen_kenney_vehicles.gd: tractor-cvt is tractor-kenney's model with cvt_range_tops -->

On the tractor, `wheel_slip`, `twd` and `tws` reach sloppyCAN but travel in no CAN frame; a
listener works the slip out from the two speeds. `speed_limit`, `engine_hours` and `axle_load`
travel only when something on the bus asks for them.
<!-- sloppycan js/isobus.js unpackable wheel_slip ("both are packed here, so a listener computes the same number"); js/nmea2000.js: 130306 only with a boat; js/carlito.js CAN_MAP_ON_REQUEST, js/j1939-flavor.js onRequest axle_load -->

</div>

## The controls

<!-- widgets/cockpit.js: its data block cites the signals behind every control -->
<div class="widget an-widget" data-widget="cockpit" data-family="tractor"></div>

<div class="widget-limits" hidden>

The simulator has no clutch pedal (the powershift tractor works its clutch itself, and the CVT
needs none) and no range lever. It always brakes both rear wheels together, and the powershift
tractor's hill hold uses those brakes (a real one holds inside its gearbox). The key and the
indicators are only worked by sloppyCAN (when driving locally, the key stays at Ignition).
<!-- tractor-kenney_spec.tres coupling CLUTCH, worked by the simulator, hill_hold 2; contract brake: one value; InputRouter: "local input is always Ignition", turnL / turnR have no local source -->

</div>

## The family

Carlito features two 7-tonne farm tractors, with a different gearbox for each. Both are governed to 40 km/h, and neither has ABS, traction or stability control; instead, they feature a diff lock and front-wheel drive as their traction aids.
<!-- tractor-kenney_spec.tres, tractor-cvt_spec.tres: mass 7000, speed_limit_kmh 40; TRACTOR_BASE: "No TC either: MFWD and the diff lock are a tractor's traction aids"; VehicleCatalog.next_in_family (V); ImplementCatalog.IMPLEMENTS -->

The following implements are available:

- **Fertiliser spreader** (0.9 t): a hopper whose gate is opened by the hydraulics, and a disc spun by the PTO.
- **Plough** (0.9 t): works the soil 25 cm deep, and pulls hard against the tractor.
- **Power harrow** (1.55 t): tines driven by the PTO, working the soil 10 cm deep.
- **Rotary mower** (0.6 t): blades spun by the PTO, carried on the hitch.
- **Farm tipper** (10 t): a tipping trailer on a drawbar, worked by the hydraulics.

The tractors can also drive without an implement.
<!-- ImplementCatalog.IMPLEMENTS and DESC; MASS_KG plough 900, harrow 1550, mower 620; spreader FRAME_KG 150 + HOPPER_M3 0.792 x LOAD_DENSITY 950; farm_tipper_spec.tres mass 10000 -->

<details><summary>Tractor list</summary>

| Vehicle | What it is | Weight, about |
| --- | --- | --- |
| `tractor-kenney` | Farm tractor on a 16-speed powershift, with a park pawl and a hill hold | 7 t |
| `tractor-cvt` | Farm tractor on a stepless CVT, holding itself still at a ratio of zero | 7 t |
<!-- tractor-kenney_spec.tres mass 7000, 16 gear_ratios, hill_hold 2; tractor-cvt_spec.tres mass 7000, cvt_range_tops -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `hand_throttle` | in | % | Sets an engine speed between idle (0) and the top of the range (100). |
| `engine_load` | out | % | Torque given over the most it can give. A plough or PTO raises it (Truck and tractor). |
| `engine_hours` | out | h | The engine's running time (Truck and tractor). |
| `gear_ratio` | out | ratio | The engaged gear's ratio, without the final drive. On the CVT it moves smoothly. 0 in N or P (Truck and tractor). |
| `axle_load` | out | kg | The weight on the rear axle, read off its springs (Truck and tractor). |
| `diff_lock` | in | flag | Asks for the rear diff lock. |
| `diff_lock_state` | out | flag | The rear diff is actually locked, read from the driveline. |
| `fwd_drive` | in | flag | Asks for front-wheel drive. |
| `fwd_drive_state` | out | flag | The front axle is actually driven. Also true while the foot brake is down. |
| `wheel_speed` | out | km/h | The rear wheels' spin times their radius. |
| `ground_speed` | out | km/h | The true speed over the ground. |
| `wheel_slip` | out | % | How far `wheel_speed` runs ahead of `ground_speed`, as a share of `wheel_speed`. Braking slip reads 0. |
| `guidance_curvature` | in | 1/km | Auto-steer: one over the turn radius, −127 to +127, negative curving left. While present it replaces `steer`. |
| `hitch_pos` | in | % | Where to put the hitch, 0 lowered, 100 raised. |
| `hitch_pos_actual` | out | % | Where the hitch is, as it moves towards the request. |
| `draft_force` | out | % | The draft, as a share of the plough's rated draft. A real force, reported. |
| `pto` | in | flag | Engage the PTO (Truck and tractor). |
| `pto_state` | out | flag | The PTO is engaged and the engine is running (Truck and tractor). |
| `pto_mode` | in | enum | 540 or 1000. |
| `pto_rpm` | out | rev/min | The shaft's speed, following the engine's. |
| `scv_flow` | in | % | How far the hydraulic remote is open. |
| `implement_connected` | out | flag | A tool has claimed an address on the implement bus. |
| `implement_type` | out | enum | The tool's device class. |
<!-- contract/carlito_contract.json: the tractor's signals the car and truck do not all share (pto, pto_state, engine_load, engine_hours, gear_ratio, axle_load [truck, tractor]; the rest [tractor]) -->

[See all signals](signals.md)

## Related

- [Implements and the PTO](implements.md): what the tractor is for.
- [Towing](towing.md), [Differentials and four-wheel drive](differentials.md).
- [Glossary](glossary.md): every term on this page.
