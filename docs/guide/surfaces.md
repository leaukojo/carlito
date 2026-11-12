# Ground and tyre types

<p class="lead">A tyre grips dry asphalt far better than ice. How far better depends on the tyre:
a winter tyre bites into snow that a summer tyre skates over. The game keeps a table of twelve
kinds of ground and nine kinds of tyre, and every wheel reads the pair it stands on.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Every car and van; most can change tyres in the garage">Car</span>
<span class="badge yes" title="Every truck and trailer; the rigid trucks and semis can change tyres">Truck</span>
<span class="badge yes" title="Both tractors and the farm trailer, on their stock lug tyres">Tractor</span>
<span class="badge some" title="Its wheels feel the ground like any other; it has no tyre choice">Plane</span>
<span class="badge no" title="No wheels: it floats">Boat</span>
<span class="badge no" title="No wheels: it flies">Drone</span>
<span class="badge no" title="Steel wheels on rails, without tyres">Train</span>
</div>

## Two numbers per kind of ground

The game knows twelve kinds of ground, which it calls [surfaces](glossary.md#surface): asphalt,
wet asphalt, pad (the painted concrete of an airfield), gravel, dirt, grass, sand, rock, mud,
field (ploughed soil), snow and ice. Each one carries two numbers.

- **Grip.** How much of a tyre's dry-road grip is left on this ground. It is measured against
  one reference tyre, an ordinary all-season car tyre, which keeps all its grip on dry asphalt
  (1) and about half of it on wet asphalt, grass or mud. On snow it keeps a little under half,
  and on ice only about a tenth.
  <!-- surface.gd REF_GRIP: Asphalt 1, Wet 0.55, Pad 0.95, Gravel 0.71, Dirt 0.8, Grass 0.5, Sand 0.6, Rock 0.7, Mud 0.45, Field 0.5, Snow 0.45, Ice 0.12 -->
- **Drag.** How much harder the ground is to roll over than a hard road. Hard ground (asphalt,
  pad, ice) adds nothing. Gravel and rock add a little. Soft ground adds much more, because the
  tyre sinks in and has to climb out of its own rut all the time: mud adds the most, about ten
  times a car tyre's own rolling resistance on a road.
  <!-- surface.gd DRAG: Asphalt 0, Wet 0, Pad 0, Gravel 0.01, Dirt 0.04, Grass 0.06, Sand 0.05, Rock 0.01, Mud 0.1, Field 0.06, Snow 0.02, Ice 0; MAX_DRAG 0.5; a car tyre's own 0.012 (sedan_spec.tres rolling_resistance) -->

The grip number changes only how high the peak of the [grip curve](glossary.md#grip-curve) is.
The curve keeps its shape on every surface: it still peaks at the same slip, and a sliding tyre
still keeps 0.8 of the peak. [Tyres and slip](tyres.md) explains the curve.

The drag number is a [rolling resistance](glossary.md#rolling-resistance): a force against the
direction of travel, a share of the load on the tyre. On mud a car needs a steady push of about a
tenth of its weight just to keep rolling, as if it were driving up a hill. It does not use any of
the tyre's grip, so it slows the car without making it slide.

## How the game knows what is under a wheel

The ground of an island level is a painted [terrain](glossary.md#terrain). The level's author
paints it with up to eight colours, and the level says which surface each colour is: green for
grass, brown for dirt, and so on. Where two colours blend, the game blends their numbers too, in
the same proportion, so a tyre half on grass and half on dirt gets a grip in between.

Everything that is not painted terrain counts as **dry asphalt**: roads, bridges, ramps, decks,
the flat test ground and any ground the author left unpainted. A bridge more than about a metre
above a painted patch does not pick up the paint below it.
<!-- wheel.gd SURFACE_GRIP_REACH 1.0 m; HeightmapTerrain.grip_at reads Asphalt when unpainted (MIN_SPLAT_TOTAL) -->

The wet road is the one surface you cannot see. In Car Arena, the bend of the wet road is
painted wet but looks like the rest of the road; only the tyres know.
<!-- tools/gen_car_arena.gd: channel 4 is Wet, "invisible there" -->

## Tyre classes

A tyre has two halves in the game. One half belongs to the vehicle: its size, its grip on dry
asphalt, how its grip changes with load, its rolling resistance on a road. The other half is the
tread, which the game calls the [tyre class](glossary.md#tyre-class). A class says only how this
tread differs from the reference all-season tyre, as a factor per surface. That way one winter
class serves a small car and an eight-tonne truck alike.

![A bar chart of peak grip for four car tyres on five kinds of ground. On dry asphalt: all-season 1, summer 1.1, winter 0.97, studded 0.94. On ice: all-season 0.12, summer about 0.09, winter about 0.18, studded about 0.28. On snow: summer about 0.27, all-season 0.45, winter and studded about 0.52.](img/surface-grip.svg "Peak grip of the four car tyres, as a share of the all-season tyre's grip on dry asphalt.")
<!-- TyreClass.grip_response = REF_GRIP x (dry / stock dry) x surface_grip; the four PASSENGER classes -->

The nine classes are:

| Class | Fitted to | What it is good at |
| --- | --- | --- |
| All-season | cars, vans, pickups, SUVs (their stock tyre) | The reference: every factor is 1. |
| Summer | cars, vans | A tenth more grip on dry roads; poor on snow and ice, slightly worse on soft ground. |
| Winter | cars, vans, trucks | A little less on dry roads; about a sixth more on snow, half again on ice. |
| Studded winter | cars, vans | Metal studs: more than twice the all-season's grip on ice, a little less on dry roads. |
| Mud | vans, pickups, SUVs, trucks | Deep open lugs: better in mud, ploughed fields, grass and sand; worse on dry, wet, snow and ice; harder to roll. |
| M+S drive | trucks (their stock tyre) | A truck's mud-and-snow drive tyre: a little better on snow and soft ground. |
| R-1W lug | the tractors only | Deep farm lugs: a quarter more grip in mud, a fifth more in fields. |
| Slick | the two racing cars only | No tread at all: on dry asphalt like the reference, but only half its grip in the wet. |
| Trailer | every trailer | The reference row, unchanged. |
<!-- src/vehicles/tyres/*.tres: fits, dry, surface_grip, crr_factor; docs/vehicles.md Tyres and surfaces, the Fit table -->

A class also changes how hard the tyre is to roll on a road: a summer tyre rolls a little more
easily than the all-season, a mud tyre about a third harder. The ground's own drag, from the
table above, is the same whatever the tread.
<!-- summer.tres crr_factor 0.95, mud.tres 1.3, winter 1.05, studded 1.1; Surface.drag is tyre-blind (a COMPROMISE in surface.gd) -->

### Choosing tyres

In the GARAGE, a vehicle with wheels shows a TYRES row of buttons, its stock tyre first. The game
remembers the choice for that vehicle, and a respawn keeps it. A challenge always uses the stock
tyre. Trailers, the tractors and the racing cars have only one class each, so their row shows
that class shown as chosen.
<!-- VehicleSelect.tyre_choices (empty only with no ground drive); UserSettings.set_tyre; docs/vehicles.md: "the stock in a challenge" -->

Changing the tread changes only the grip numbers and the rolling resistance. The vehicle's brakes,
its ABS and its traction control stay as they were: they still aim for the same point on the
grip curve, which every class shares.

## What the game leaves out

- **No rain.** Wet asphalt is a painted surface, always in the same places. No weather makes the
  road wet or dry, and no surface changes during a drive.
- **No tyre wear, temperature or pressure.** A tyre grips the same on the first lap and the
  hundredth.
- **One drag per surface.** A wide tractor tyre pays the same soil drag as a narrow car tyre,
  although a real wide tyre sinks in less.
- **No sinking.** Mud and sand slow a vehicle and lower its grip, but the wheels do not dig in
  and the vehicle cannot get bogged down to its axles.

## What you see in sloppyCAN

No signal names the surface under a wheel. Its effects show in the signals that come from the
tyres:

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `slip` | out | ratio, two values | The front and rear axles' slip, along the wheels and sideways together. On low grip the same pedal makes much more slip. Car, truck, tractor. |
| `accLong` | out | m/s² | Acceleration along the vehicle. In a full ABS stop it falls in step with the surface's grip. |
| `wheel_slip` | out | % | Tractor only: how far the rear wheels run ahead of the ground. In mud or a field it climbs. |
| `engine_load` | out | % | Truck and tractor: how much of the engine's torque is in use. Soft ground's drag raises it at a steady speed. |
<!-- contract/carlito_contract.json: slip, accLong, wheel_slip, engine_load -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: the same stop on three surfaces</p>

1. Open SETTINGS and set EXTENDED DEBUG LABELS to ON. The overlay in the top right (**F3** shows
   or hides it) now shows a
   `tyre` line (the class fitted), a `surf` line (the surface under each wheel), a `grip` line
   (each wheel's grip on it) and a `drag` line (the ground's added drag).
2. In the GARAGE pick the `sedan` with ALL-SEASON tyres. Open LEVEL, pick **Car Arena**, then
   use SPAWN POINT to start on the tyre pad.
3. Drive along the dry, wet and snow strips at about 50 km/h and brake hard on each. The `grip`
   numbers read about 1, 0.55 and 0.45; the stopping distance grows to match.
4. Go back to the GARAGE, fit WINTER tyres and repeat on the snow strip. `grip` rises to about
   0.52 and the car stops in a shorter distance. On the dry strip it now reads 0.97.

</div>

## Related

- [Tyres and slip](tyres.md): the grip curve that each surface scales.
- [Glossary](glossary.md): every term on this page.
