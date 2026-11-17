[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Brakes

<p class="lead">Brakes turn a vehicle's speed into heat. Each vehicle in the game has its own
brake hardware, sized from a real vehicle of its kind, and the brakes warm up, cool down and
lose strength when they get too hot.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Disc brakes on every wheel, a handbrake on the rear">Car</span>
<span class="badge yes" title="Air brakes with spring parking brakes, plus a retarder; the trailers brake too">Truck</span>
<span class="badge yes" title="Wet disc brakes in the rear axle's oil">Tractor</span>
<span class="badge some" title="Wheel brakes and a parking brake on its three landing wheels">Plane</span>
<span class="badge no" title="It slows by reversing its propeller">Boat</span>
<span class="badge no" title="It slows by changing its rotor speeds">Drone</span>
<span class="badge some" title="A train air brake, on the trains page">Train</span>
</div>

## Brake hardware

A car's brake squeezes a pad against a disc that turns with the wheel. The rubbing slows the
wheel, and the tyre then slows the car. How hard a brake can squeeze is its torque, in newton-
metres, just like an engine's.

Each vehicle in the game has brakes copied from a real vehicle of its class: a family car's
discs, a sports car's bigger ones, a van's, a 26-tonne truck's air-operated brakes, a farm
tractor's oil-bathed discs. They are never made bigger to suit the game. Every one of them is
strong enough to lock its wheels on dry asphalt: the brakes can always ask for more than the tyres
can give.
<!-- docs/vehicles.md Brake hardware: declared hardware per class; BrakeSizing: "the foot brake is at least 1.15x the stock tyre, so it can lock" -->

| Class | Vehicles | Full brake, about |
| --- | --- | --- |
| Saloon discs | `sedan`, `taxi`, `hatchback-sports` | 1.3 to 1.6 g |
| Performance | `sedan-sports`, `police` | 1.6 to 1.9 g |
| SUV and light commercial | `suv`, `suv-luxury`, `van`, the pickups | 1.4 to 2.6 g |
| Racing | `race`, `race-future` | 2.5 to 2.7 g |
| Heavy van | `delivery`, `delivery-flat`, `ambulance` | 1.2 to 1.5 g |
| Truck air brakes | `garbage-truck`, `firetruck`, the semis | about 2.2 g unladen, 1.5 g on the laden `firetruck` |
| Tractor wet discs | `tractor-kenney` | about 1.4 g |
<!-- docs/vehicles.md Brake hardware table: foot brake as g at the body's mass -->

A [g](glossary.md#units) here is the braking the hardware could give if the tyres had unlimited grip,
as a share of the pull of gravity. No tyre on a road gives much more than 1 g, so in practice
the tyres set the limit: the brakes lock the wheels, or ABS holds them just short of locking.

### Front and rear

When a car brakes, weight moves onto its front wheels, so they can take more braking. The game
divides each car's braking between front and rear in proportion to the grip each axle has in a
hard stop. That split is the [brake bias](glossary.md#brake-bias). It is fixed: real cars adjust it
with valves, the game does not.
<!-- GroundDriveSpec.brake_bias_front; gen_kenney_vehicles _front_brake_share proportions it by each axle's load-scaled grip in a tyre-limited stop -->

### The pedal

A brake pedal that applied a racing car's full hardware at half travel would be impossible to use
gently. So the game shapes the pedal the same way on every vehicle: half the pedal asks for about
half a g of braking, whatever the hardware, and the full pedal asks for everything the hardware
has.
<!-- WheelDrive.brake_application, BRAKE_HALF_PEDAL_G 0.5; contract brake: "half pedal asks about 0.5 g whatever its capacity" -->

## The handbrake

The [handbrake](glossary.md#handbrake) works the rear wheels only, and ABS does not control it.
It is meant to park the vehicle: with its brakes cold, every vehicle's handbrake holds it on the
slope the law requires, and more. Pulled while moving, it locks the rear wheels. A locked
tyre has no sideways grip, so the back of the car swings round. Pulled hard at speed with a turn
of the wheel, it spins the car about half a turn: a handbrake turn.
<!-- GroundDriveSpec.handbrake_torque; BrakeSizing: parks the laden body on 20 % (R13-H) or 18 % (R13); docs/vehicles.md Handbrake turn: "the body turns about a half turn" -->

It is a brake, not a lock. A strong enough engine can drag the vehicle through it, most easily on
a front-wheel-drive car, whose driven wheels it does not hold.
<!-- contract handbrake: "a strong enough drive pulls through it (most easily on a front-driven car...)" -->

On the trucks the handbrake is their spring brakes, explained below. The keyboard's handbrake is
**Space**.

## One brake, two ways to apply it

On many cars the handbrake has no brake of its own. The pedal and the lever reach the same rear
brakes by two routes. The pedal pushes brake fluid down a pipe, and the fluid pushes a piston that
presses the pads onto the disc. The lever pulls a steel cable, and the cable works a small
mechanism in the same caliper that pushes the same piston. A truck does the same with air and a
spring: the pedal lets air into the brake chamber, and the parking spring pushes the same rod to
the same shoes.

![A rear disc brake seen edge on. The disc turns with the wheel hub; a caliper straddles its rim with a pad on each side. A brake fluid pipe from the pedal and a steel cable from the handbrake lever both end at the caliper's one piston, which presses the same pads. The pads carry one temperature and one fade for both.](img/brake-two-ways.svg "One brake, two routes. The pedal's fluid and the lever's cable press the same pads on the same disc.")
<!-- Drawn by hand; WheelDrive.tick and TowedBody.tick_towed -->

So the two share everything that rubs and heats: the pads or shoes, and the disc or drum under
them. If the pedal has made that metal hot, the lever finds it hot too.

The game does the same. Each rear wheel has one brake torque made of both: the foot brake's share
plus the handbrake's, or a truck's spring brakes. That sum goes through the wheel's one
temperature and one fade factor, so a hot brake loses the same share of both. A trailer's brakes
work the same way. The plane's brakes have no heat model, so its park brake never fades.
<!-- WheelDrive.tick: parking_torque(...) * w.brake_fade() on the rears; TowedBody.tick_towed: (service + parking) * w.brake_fade(); RayWheel.brake_fade; plane_spec.tres sets no brake_heat_capacity (0: factor 1) -->

## Heat and fade

![A graph of braking force left against brake temperature for four kinds of brake. Drums start to lose force at about 180 °C and are down to half at about 480 °C. Pads on discs hold full force to 400 °C, then fall to half by 750 °C. Racing pads hold to 650 °C. A tractor's wet discs, read off the oil, fade from 90 °C.](img/brake-fade.svg "Fade. Past a temperature that depends on its kind, a hot brake gives less force for the same pedal.")
<!-- BrakeThermal PAD, RACE, DRUM, WET curves -->

Every stop turns the vehicle's movement into heat in the brakes. The game models each friction
brake as one lump of metal with one temperature. Braking heats it by exactly the work it does on
the wheel; the air cools it, faster the faster the vehicle moves. It is a simple model, and the
game labels it as one.
<!-- BrakeThermal: one lumped temperature, FHWA's GSRS brake model plus disc radiation; RayWheel.heat_brake (a locked wheel heats nothing) -->

![A flow diagram. A moving vehicle sends energy through a braked wheel that is still turning into the brake, one lump of metal with one temperature. From the brake it goes to the air, faster the faster the vehicle moves, and a hot disc also glows heat away. Two dashed paths lead elsewhere: a locked wheel, where the tyre skids and the brake stays cool, and the retarder and engine braking, which slow the vehicle and heat no brake.](img/brake-heat-path.svg "Where a stop's energy goes. Only a friction brake on a turning wheel heats, whether the pedal or the handbrake applies it.")
<!-- RayWheel.heat_brake: reacted torque x friction share x settled spin; BrakeThermal.loss_w: convection rising with road speed, plus radiation on the discs -->

Inside the game the heat a brake takes each moment is its braking torque times how fast its wheel
turns. The air takes heat away in proportion to how much hotter than the air the brake is, more
the faster the vehicle moves; a disc also radiates heat, which counts most when it is very hot.
<!-- RayWheel.heat_brake; BrakeThermal.loss_w: (g0 + g1 * speed) * (T - ambient) + emissivity * sigma * A_r * (T^4 - ambient^4); drums: emissivity 0 -->

When a brake gets hot enough, its lining grips less and the brake
[fades](glossary.md#brake-fade): the same pedal gives less braking, so you have to press harder.
Where that begins depends on the hardware:

- **Drums**, on the rigid trucks: from about 180 °C.
- **Pads on discs**, on the cars and the semis: from about 400 °C.
- **Racing pads**: from about 650 °C.
- **Wet discs**, on the tractor: they sit in the axle's oil, and the game reads the oil's
  temperature. They fade from about 90 °C.

A locked wheel does not heat its brake at all: the brake is not turning, so it does no work. The
tyre is doing the slowing then. The retarder and engine braking heat nothing. The handbrake
presses the same pads or shoes as the pedal, so it heats and fades with them. A trailer's brakes
heat and fade too, but their temperature is not published.
<!-- docs/vehicles.md Heat and fade -->

This is why long downhill runs are hard on brakes, and why trucks have a retarder.

### The handbrake on a hot brake

After a long descent on the foot brake, the handbrake is no way out: it is as tired as the pedal.
Two examples, with the brakes at 480 °C:

| | `sedan` | `garbage-truck` |
| --- | --- | --- |
| Brake | pads on discs | drums |
| Handbrake, one rear wheel, cold | about 1400 Nm | about 6500 Nm |
| Force left at 480 °C | 86 % | 50 % |
| Handbrake, one rear wheel, at 480 °C | about 1200 Nm | about 3250 Nm |
| Locks the rear wheels at speed | yes, cold and hot | cold only |
| Steepest slope it parks on | about 32 %, cold and hot | about 32 % cold, 24 % hot |
<!-- sedan_spec.tres / garbage-truck_spec.tres handbrake_torque 1400 / 6500, brake_fade_curve_rear PAD / DRUM; BrakeThermal.PAD (465, 0.86)-(615, 0.86) and DRUM (480, 0.5); BrakeSizing.rear_lock_ratio 1.59 -> 1.37 and 1.08 -> 0.54, BrakeSizing.park_grade with handbrake_torque x factor, run 2026-11-17 -->

The sedan's pads are still in their first, gentle step of fade, and its handbrake is strong
enough that its rear tyres, not its brakes, set how hard it holds: it still locks the rears and
parks as before. The truck's drums have lost half their force. Its handbrake no longer locks the
rears at speed, and it parks on a gentler slope than when cold, though still steeper than the
18 % the law asks of a truck. On anything steeper the truck can creep until the drums cool. The
trucks have no P position to fall back on; the road cars, vans and tractors do, and the
gearbox's parking lock does not fade.
<!-- BrakeSizing.PARK_GRADE_HEAVY 0.18; Drivetrain.has_park_pawl: park_pawl_torque set on the road cars, vans and tractors, not on race, race-future, garbage-truck or firetruck -->

The game's parking figures elsewhere, such as the slope the law requires, are for cold brakes.

## The retarder

A [retarder](glossary.md#retarder) is an extra brake inside a truck's driveline, a kind of
paddle wheel in oil that slows the drive shaft without touching the wheel brakes. It makes no
heat in the brakes, so it can hold a truck back down a long hill without fading them.

The garbage truck, the fire truck and the semis have one. It slows a bare truck by about a tenth
of a g. It acts only on the driven wheels, fades away at walking pace, and is capped so it can
never lock a wheel. On a semi it brakes only the tractor unit: a heavy trailer pushes on, so the
whole rig slows much less. sloppyCAN works it with the `retarder` signal; there is no key for it.
<!-- docs/truck.md Air, retarder, axle load: 0.84-0.89 m/s² on the Kenney trucks, 1.47 on the bobtail semis (0.37 coupled to the 24 t box); RETARDER_SLIP_TARGET; contract retarder: "No local key" -->

## Air and spring brakes

Big trucks brake with air pressure. A compressor driven by the engine fills tanks, and the brake
pedal lets that air into the brakes. The game models two tanks, one for each brake circuit. They
fill while the engine runs, and each full press of the pedal draws some air out. Holding the
pedal down costs nothing more; pumping it drains the tanks. Stability control's own braking
draws air in the same way.
<!-- docs/truck.md: two reservoirs, 0.70 / 0.55 bar a full application, a held one draws nothing more; WheelDrive.service_level -->

A truck's parking brakes are [spring brakes](glossary.md#spring-brake): strong springs that put
the brakes on, held off by air. If the air runs out, the springs win. That makes them fail-safe:
a truck that loses its air stops. In the game:

- Below 5 bar in either tank, the low-air warning is due.
- Below 3 bar, the spring brakes apply on the rear wheels, and the gearbox drops to neutral so the
  truck cannot drive away. A coupled trailer's spring brakes apply too.
<!-- contract air_primary warn 5.0; TruckTelemetry.AIR_SPRING_BRAKE_BAR 3 bar; Drivetrain.drive_inhibit -->

The game keeps it simple: there are no pipes, valves or leaks, only two tanks that fill and
empty.

## What the game leaves out

- **No adjustable brake bias**, and no proportioning valve that changes the split with load.
- **No brake wear or failure** apart from the air running out on a truck.
- **No exhaust brake.** The trucks' auxiliary brake is the retarder.
- **No smoke or glowing discs**: brake heat shows only in the numbers.
- **No fluid fade.** On a real car, brake fluid can boil on a long descent, and the pedal goes
  soft while a cable handbrake still works. The game has no brake fluid, so there is no soft
  pedal, and the handbrake never outlasts the foot brake.
- **No separate handbrake shoes.** Some cars with rear discs park on a small drum brake inside the
  disc's hub, with its own lining that the foot brake does not heat. In the game the handbrake
  always shares the foot brake's lining.
- **No shrinking disc.** A disc clamped while hot shrinks as it cools, which can loosen a parked
  caliper's grip. The game does not model it.

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `brake` | in | % | The foot brake. Half pedal is about half a g; full pedal is the whole hardware. |
| `handbrake` | in | flag | The parking brake: the rear wheels, or a truck's spring brakes, or the plane's park brake. It fades with its brake. |
| `brake_temp` | out | °C | The hottest friction brake on the vehicle, from the heat model. Car, truck, tractor. Its warning, 260 °C, is late for a drum and early for a disc. |
| `retarder` | in | % | Truck: the retarder request. |
| `retarder_state` | out | % | Truck: the retarder's torque as actually applied, after it fades at low speed. |
| `air_primary`, `air_secondary` | out | bar | Truck: the two brake tanks. Warning at 5 bar; the spring brakes apply below 3. |
| `brakeLamp` | in | flag | Car, truck, tractor: the stop lamps, set by sloppyCAN. |
| `status` | out | bitfield | Bit 5 is the handbrake. |
<!-- contract/carlito_contract.json: brake, handbrake, brake_temp (warn 260), retarder, retarder_state, air_primary / air_secondary (warn 5.0), brakeLamp, status bit 5 -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: cook the brakes</p>

1. Pick the `garbage-truck` and drive down the long grades of **Level 2 - Mountain**. Press **F2**
   until the dashboard shows FULL, whose bars include the brake temperature.
2. Ride the foot brake all the way down. The temperature climbs past 180 °C, and the same pedal
   slows the truck less and less: the drums are fading.
3. Cook the drums again on the foot brake, then pull the handbrake (**Space**) at speed. The
   rear wheels no longer lock, and the truck slows less than it would with cold brakes. Stop on
   the grade with the handbrake alone: on a steep enough slope it creeps until the drums cool.
4. Stop and let them cool. Now go down again with sloppyCAN holding the `retarder` on. The brake
   temperature stays low.
5. In the `sedan` on **Flatland**, pull the handbrake (**Space**) at about 40 km/h with the
   steering turned: the rear swings round.

</div>

## Related

- [Tyres and slip](tyres.md): why the tyre, not the brake, usually sets the stopping distance.
- [Glossary](glossary.md): every term on this page.
