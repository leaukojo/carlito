# The trucks

<p class="lead">The truck family is two rigid trucks and two semi tractor units, the cab-over
`semi` and the American-style `semi-conventional`, which pull four kinds of semi-trailer. They
add air brakes, a retarder, heavy loads and, on the garbage truck, a working body with its own
network.</p>

## The family

| Vehicle | What it is | Weight, about | Gearbox | Governed to |
| --- | --- | --- | --- | --- |
| `garbage-truck` | Refuse truck with a front-loading arm | 8 t | 6-speed automatic | 85 km/h |
| `firetruck` | Fire engine | 7.5 t | 6-speed automatic | 110 km/h |
| `semi` | Cab-over tractor unit with a trailer data link | 8 t | 12-speed AMT | 90 km/h |
| `semi-conventional` | Bonneted tractor unit, no trailer data link | 8 t | 12-speed AMT | 105 km/h |
<!-- garbage-truck_spec.tres mass 8000, speed_limit_kmh 85; firetruck_spec.tres 7500, 110; semi_spec.tres 8000, 90; conventional_spec.tres 8000, 105; gear_ratios 6 / 12 -->

All four drive their rear wheels through an open differential.

## What each truck has

- [Tyres](tyres.md) with an M+S drive tread, or winter or mud tyres ([Ground and tyre
  types](surfaces.md)).
- [Steering](steering.md) and stiff [suspension](suspension.md); the rigid trucks have
  anti-squat links.
- A diesel [engine](engine.md) with a road-speed governor, and the automatic or AMT
  [gearbox](gearbox.md) above, with a [torque converter](coupling.md) on the rigid trucks and an
  automated clutch on the semis.
- [Air brakes with spring parking brakes](brakes.md#air-and-spring-brakes), and a
  [retarder](brakes.md#the-retarder).
- [ABS, traction control (ASR) and stability control](driver-aids.md); the semis add
  [roll stability](driver-aids.md#roll-stability-on-the-semis).
- [Hill-start assist](holding.md#hill-start-assist); no park pawl.
- [Air drag and rolling resistance](resistance.md), the [aux models](aux.md) including the two
  air tanks, and [position and distance](position.md).

## The semis and their trailers

The semis tow the box, tipper, tanker and flatbed semi-trailers on a fifth wheel; with none, they
drive as a bobtail. [Towing](towing.md) covers the joint, the trailer brakes, the tanker's surge
and the tipper.

## The garbage truck's body

The garbage truck's front arm lifts bins over the cab and empties them into its hopper. It is
worked through a separate network from the truck's own, as on real refuse trucks: the body
speaks CANopen, a different message set, and a gateway passes messages between it and the
truck's J1939 network.
<!-- docs/truck.md The refuse body: CiA 422 "CleANopen" body network, CiA 413 truck gateway -->

- Press **P** for the PTO, which powers the body's pump, then **X** to step the body through
  idle, lift, dump and lower; sloppyCAN sends `body_cmd`.
- The body only works with the truck parked: the PTO in, the parking brake on, and at most a
  walking pace. Otherwise the gateway sets an interlock and the arm freezes.
- While the arm rises, the pump loads the engine through the PTO, so the engine load and the fuel
  burn rise with each lift. With the truck parked, the engine holds the pump's set speed.
- Each emptied load adds real weight to the hopper, which the axle load and engine load then
  show. The only way to empty the hopper is to respawn.
<!-- docs/truck.md: body_cmd (Idle/Lift/Dump/Lower, X key); body_inhibit computed chassis-side (road speed, PTO state, parking brake); RefuseBody.PUMP_KW; VehicleSpec.pto_mode_rpm 1300; "hopper_load adds real mass to the chassis"; "respawn is the only way to empty the hopper" -->

## Where to drive them

Trucks are allowed on every level but Open Sea and Car Arena. **Level 2 - Mountain** has the long
grades that load the engine and heat the brakes.
<!-- *_info.tres allowed_vehicles; level_registry level_2 desc -->

## What you see in sloppyCAN

The trucks speak J1939, the standard of heavy vehicles. Beyond the shared signals they publish
`engine_load`, `axle_load`, `gear_ratio`, `speed_limit`, `retarder_state`, `air_primary`,
`air_secondary`, `pto_state` and `engine_hours`, the semi's trailer signals, and the garbage
truck's body signals: `body_state`, `body_pos`, `body_inhibit`, `body_bus` and `hopper_load`.
<!-- contract/carlito_contract.json truck signals (flavors j1939, iso11992, cleanopen) -->

## Related

- [Towing](towing.md), [Brakes](brakes.md), [Implements and the PTO](implements.md#on-the-trucks).
- [Glossary](glossary.md): every term on this page.
