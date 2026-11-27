[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Holding still

<p class="lead">This page explains the ways a vehicle is held still on a slope, from the tyre
itself to the gearbox's parking lock.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Hill-start assist, auto hold, the park pawl, the handbrake">Car</span>
<span class="badge yes" title="Hill-start assist, auto hold, spring brakes; no park pawl">Truck</span>
<span class="badge yes" title="The powershift's hill hold and park pawl, or the CVT's active standstill">Tractor</span>
</div>

On a slope, gravity constantly pulls a vehicle downhill, so something has to hold it whenever it
stops. What does, and why is it sometimes not enough?

## How hard the slope pulls

On a slope, a vehicle's weight splits into two parts: one pulls it down the slope, the other
presses it onto the road. The steeper the slope, the larger the first and the smaller the second.
In words:

pull down the slope = weight × sin(slope angle)

A road sign gives a slope in percent instead: how many metres it rises for every 100 metres
along the flat. On the gentle slopes of roads, the pull is about that percentage of the weight.
For example, on a 20 % slope (it rises 20 metres over 100 metres, an angle of about 11 degrees), a
car weighing 10,000 newtons is pulled downhill with about 2,000 newtons. Whatever holds the car
must push back with that much.

A 100 % slope is not a wall, as the name might suggest: it rises 100 metres over 100 metres, which
is 45 degrees. A vertical wall would be an endless percentage.

## The tyre holds first

A braked wheel on a slope is not turning, yet its tyre has to make a force. It can, because rubber
bends a little before it slides, like a stiff spring (the same bending that lets a rolling tyre
grip, see [A tyre needs slip to grip](slip.md#a-tyre-needs-slip-to-grip)). A wheel held by its
brake or by the parking pawl (a catch in the gearbox that locks the drive) winds this spring up
and holds the vehicle still. An unbraked wheel does not, so the vehicle rolls down the hill.

The tyre can only hold what the brake holds
([see the forces](forces.md#example-parked-on-a-hill)). If the slope's pull is more than the brake
can take, the wheels turn against it. If it is more than the tyres can take, the vehicle slides
with its wheels locked.

The tyres can push back with at most μ times the part of the weight pressing them onto the road
(see [the coefficient of friction](tyres.md#the-coefficient-of-friction)). So a car with every
wheel held stays put while the slope rises by less than μ metres for every metre along the flat.
The weight does not come into it: a heavier vehicle is pulled downhill harder, but it is also
pressed onto the road harder, by the same share. So a loaded truck slides on an icy slope just as
a small car does.
On dry asphalt, with a μ of about 1, that is a slope of 45 degrees, far steeper than any road, so
there it is the brake that sets the limit, not the tyres. On ice, with a μ of 0.1, the 20 % slope
of the example (which needs a μ of about 0.2) is already too steep. A parking brake usually holds
only two wheels, so only the weight on those two counts, and the steepest slope it can hold is
gentler still.

## Rolling back on a hill start

Pulling away uphill is harder. When the driver moves their foot from the brake to the accelerator,
nothing holds the vehicle until the drive takes up, so it rolls back
([see the forces](forces.md#example-hill-start)). The brake lets go in an instant, but an engine
needs a moment to build up its push (see [the clutch](coupling.md)).

A car with an automatic gearbox is helped by [creep](glossary.md#creep): its torque converter
pulls gently at idle, which can be enough on a gentle slope. On steeper slopes, or with a clutch
(which does not creep), the vehicle rolls back. A clutch gives no hold of its own: it only
passes on the engine's push, so the vehicle stays put only once the engine pushes as hard as the
slope pulls back. The systems below prevent the roll back.

### Hill-start assist

[Hill-start assist](glossary.md#hill-start-assist) keeps the foot brake on for a moment after the
driver releases it. It lets go as soon as the engine's drive is enough to hold the vehicle on the
slope, or when its timer runs out (after a second or a few seconds, depending on the vehicle). The
timer is there so that the brake never stays on for good if the driver does not pull away.

It usually relies on the same hardware as ABS and stability control, which can already brake each
wheel without the driver's foot.

### Auto hold

[Auto hold](glossary.md#auto-hold) goes further. When it is on, a vehicle that has stopped in gear
keeps its brakes on with no pedal pressed, until the driver presses the accelerator. This spares the
driver from holding the pedal down at every traffic light. Cars that have it usually let the driver
switch it on and off, and show it with a lamp.

### The tractor's hill hold

Some tractors with a powershift have their own hill hold. The tractor holds itself whenever it
stands still in gear with the accelerator up. There is no timer: it lets go once the accelerator
is pressed and the clutch has taken up enough to carry the slope.

### Active standstill on a CVT tractor

A tractor with a CVT needs no brake to stand still. Its gearbox can set a ratio of zero, where the
engine runs but the wheels cannot turn. This is called
[active standstill](glossary.md#active-standstill). The gearbox keeps holding the wheels while the
engine runs, so when the driver asks for movement, the ratio simply opens from zero, and there is
no moment at which nothing holds the tractor back (see [Kinds of gearbox](gearbox-kinds.md)).

## Parking

### The park pawl

The P position of an automatic drops a steel tooth (the [park pawl](glossary.md#park-pawl)) into a
toothed wheel on the gearbox's output. The teeth are sloped, like those of a ratchet, so at very
low speed the pawl falls into a gap and locks the wheel. At higher speed it just clicks over the
teeth and holds nothing, which is why a car must be stopped before P is selected.

The pawl locks the gearbox rather than the wheels. The wheels are held through the
[differential](glossary.md#differential), and an open differential gives its two wheels the same
torque, so the pair can hold no more than twice what the weaker wheel can. With one driven wheel
on ice, the other one can roll downhill while the wheel on ice turns backwards over the ice (the
differential lets them turn against each other), so a car parked in P can creep away. A
front-drive car in P also holds only its front wheels, and when it faces uphill they carry less
of its weight than usual, because the slope shifts weight onto the lower, rear wheels. So P alone is not always enough on a steep or slippery slope, although many
drivers think it is, and the parking brake should be used as well.

<!-- photo: a park pawl and the toothed wheel it locks, in a cut-open gearbox -->

### The handbrake and spring brakes

The handbrake holds the rear wheels directly, without the gearbox (see
[Brakes](brakes.md#the-handbrake) for how it works). The law requires it to hold the loaded
vehicle on a steep slope, far steeper than most roads. On trucks, the parking brake uses
[spring brakes](brakes.md#air-and-spring-brakes). This is how a truck parks when its gearbox has
no pawl. A parking brake is a friction brake, so it holds less after a hard descent has heated it
(see [the handbrake on a hot brake](brakes.md#the-handbrake-on-a-hot-brake)), which is a reason to
park in gear or in P as well.

## What Carlito simulates

The parameters the simulator uses for this, and where each is set, are listed in
[How the simulation works](simulation.md#holding-still):

- **Simulation-wide**:
  - [Grip at rest](simulation.md#grip-at-rest) (`STICK_DEFLECTION`, `STICK_SPEED`)
  - [Park pawl speed](simulation.md#park-pawl-speed) (`PAWL_ENGAGE_SPEED`)
- **Per vehicle**:
  - [Hill-start assist](simulation.md#hill-start-assist) (`hill_hold`, `hill_hold_s`)
  - [Park pawl](simulation.md#park-pawl) (`park_pawl_torque`)
  - [Handbrake](simulation.md#handbrake) (`handbrake_torque`)

<details><summary>Simplification list</summary>

- **A simple spring at rest.** The give of a still tyre is a spring of about 2 cm in each patch,
  which fades in below a slow walking pace.
  <!-- wheel.gd STICK_DEFLECTION 0.02 m, STICK_SPEED 0.5 m/s -->
- **Parking brakes sized to one slope.** Each vehicle's parking brake, cold, holds it fully
  loaded on a 20 % slope, or on an 18 % one if it weighs more than 3.5 tonnes.
  <!-- BrakeSizing.PARK_GRADE_LIGHT 0.20, PARK_GRADE_HEAVY 0.18, LIGHT_MASS_KG 3500 (its comments: UN R13-H and UN R13; docs/sources.md records R13-H as not opened) -->
- **No electronic parking brake button**, and no automatic handbrake when the engine stops.
- **No P from local controls.** Only sloppyCAN can select it.
- **No roll-away warning**: a vehicle left in neutral on a hill just rolls.
- **Hill-start assist's slope.** It reads the slope from the ground under the wheels, not the
  body's tilt, so a car squatting under acceleration is not taken for one on a hill. It leaves
  rolling resistance out, so it lets go slightly late, never early.
  <!-- hill_hold.gd: "The grade is the wheels' contact plane, never body pitch"; drive_holds: "Rolling resistance is left out: the hold lets go late, never early" -->
- **The tractor's hill hold uses its brakes.** A real tractor holds inside its gearbox; the
  brakes do the same job.
- **No auto hold over CAN.** It is off while sloppyCAN is connected, which has to implement its
  own.
  <!-- InputRouter.auto_hold; pause_menu.gd AUTO_HOLD_HELP -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `gear` | in | enum | 254 is P: the park pawl, where one is fitted. A truck reads it as N. |
| `gear` | out | enum | P only while a pawl is engaged; N where a P request found none. |
| `handbrake` | in | flag | The parking brake on the rear wheels, or a truck's spring brakes. |
| `status` | out | bitfield | Bit 5 is the handbrake; bit 2 clears when the vehicle stops moving. |
<!-- contract/carlito_contract.json: gear (in, out), handbrake, status bits 2 and 5 -->

Hill-start assist and auto hold have no signal of their own.

## Scenarios

- [Parked on a hill](forces.md#example-parked-on-a-hill): the brakes hold the car.
- [Hill start with both pedals released](forces.md#example-hill-start): the car rolls back.
- [Full truck starting uphill](forces.md#example-truck-uphill): the drive needed to pull away.

## Related

- [Glossary](glossary.md): every term on this page.
- [Clutch and torque converter](coupling.md): creep, and why a clutch does not hold.
- [Brakes](brakes.md): the handbrake and the trucks' spring brakes.
- [Kinds of gearbox](gearbox-kinds.md): the CVT that holds a tractor with a ratio of zero.
