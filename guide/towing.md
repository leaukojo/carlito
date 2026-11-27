[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Towing

<p class="lead">This page explains how a trailer moves as a second body on a pivot, why it cuts
inside turns, how it brakes and how a rig jackknifes.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge no" title="The cars tow nothing">Car</span>
<span class="badge some" title="The two semi tractor units, on a fifth wheel; the rigid trucks tow nothing">Truck</span>
<span class="badge yes" title="A farm tipper trailer on a drawbar">Tractor</span>
</div>

A truck pulling a long trailer needs a wider road to turn, takes longer to stop, and can fold in
two on ice, although the truck itself is the same as when it drives alone. Why does a trailer
change so much?

## Two bodies and a joint

<figure>
<img src="img/fifth-wheel-plate.jpg" alt="The back of a semi tractor unit seen from behind: a large round steel plate with a V-shaped slot at its front, mounted over the rear axles">
<figcaption>A fifth wheel plate on a tractor unit. Photo: Acroterion, CC BY-SA 4.0, <a href="https://commons.wikimedia.org/wiki/File:Fifth_wheel_IHC_truck_MD1.jpg">Wikimedia Commons</a>.</figcaption>
</figure>

<!-- photo: a farm trailer's drawbar eye over the tractor's pin -->

A truck with a trailer is no longer one vehicle. A trailer does not move as one block with the
vehicle pulling it: it has its own weight, its own [suspension](suspension.md), its own tyres and
its own brakes. The two bodies meet at one point, a joint that lets the trailer swing from side to
side, tip up and down over a crest, and lean a little. Whatever the truck does, the trailer
answers a moment later and in its own way.

Two common kinds of joint are:

- **The [fifth wheel](glossary.md#fifth-wheel)**, on semi trucks. A heavy greased plate on the back
  of the truck takes a steel pin (the [kingpin](glossary.md#kingpin)) under the front of the
  trailer. The front of the trailer rests on the plate, so the truck carries a large part of the
  trailer's weight. The trailer can swing far to each side, but can barely lean compared to the
  truck.
- **The [drawbar](glossary.md#drawbar)**, on tractors. A bar on the trailer ends in an eye that
  drops over a pin low on the tractor's back. It carries much less of the trailer's weight, and it
  lets the trailer tip and lean more, which suits rough farm tracks.

You might expect the weight on the fifth wheel to be only a burden for the truck. It is useful:
it presses on the truck's driven rear wheels, and a driven wheel that is pressed harder can push
harder before it slips (see
[Slip and the grip curve](slip.md#a-tyre-pressed-harder-grips-more-but-not-in-proportion)). This
is why a truck running with no trailer can have poor traction on a slippery road: its driven axle
carries little weight. A drawbar hands the tractor much less of its trailer's weight, so a
tractor gets less of this help.

## The trailer cuts inside a turn

![A tractor unit seen from above, turned to the right, with a semi-trailer behind it pointing straight back. The two meet at the kingpin on the tractor's fifth wheel. The angle between their centre lines is the articulation angle.](img/articulation.svg "The articulation angle, at the kingpin.")

The angle between the truck and the trailer is called the
[articulation](glossary.md#articulation) angle. In a turn, the trailer does not follow the truck's
path: its wheels run on a smaller circle, inside the path of the cab's front wheels. This is
called [off-tracking](glossary.md#off-tracking).

Why? At low speed, each axle rolls along the direction its wheels point, so every axle runs square
to a line from the one centre the whole rig turns about. A car's rear wheels already cut a little
inside its front wheels for this reason (see
[Steering and Ackermann](steering.md#one-angle-the-bicycle-model)). A trailer adds a second step:
its axles trail behind the joint, and they are always pulled a little towards the inside of the
turn, as a toy pulled on a string round a corner cuts across it. The longer the trailer, the more
it cuts inside.

For example, take a cab whose front wheels follow a circle with a radius of 12 metres, with its
rear axle 4 metres behind them, the joint above the rear axle, and the trailer's axles 8 metres
behind the joint. Each body runs square to the line from its rear axle to the centre, so that
line, the body and the line from the centre to the point ahead on the body make a right-angled
triangle, and each radius follows from Pythagoras:

- the rear axle: √(12² − 4²) = √(144 − 16) = √128, about 11.3 metres;
- the trailer's axles: √(128 − 8²) = √(128 − 64) = √64 = 8 metres.

So the trailer's wheels run 12 − 8 = 4 metres inside the cab's front wheels. That is why a truck
driver swings wide before a tight corner: otherwise the trailer would climb the kerb, or hit
whatever stands on the inside of the corner.

![A truck and trailer turning left, seen from above. Two paths curve round one turning centre: the cab's front wheels on the outer one, the trailer's rear wheels on a clearly smaller one inside it.](img/rig-corner-paths.svg "In a turn, the trailer cuts inside the cab's path.")

<div class="widget" data-widget="off-tracking"></div>

<div class="widget-limits" hidden>

The rigs are the simulator's `semi` with its box trailer and `tractor-kenney` with its farm
tipper, measured off their models; the trailer length is from the joint to the middle of the
trailer's axles. The turn is steady and slow, so the tyres roll where they point; at speed they
slip sideways a little and the trailer runs a little further out. A group of two or three trailer
axles counts as one axle at its middle. The smallest radius is the front wheels' at full lock. The
paths are those of the axles' middles; the inside wheels run a little under a metre further in. The outlines
are drawn to about the bodies' size.
<!-- widgets/off-tracking.js: semi_spec.tres wheel_positions, max_steer_deg 24; fifth_wheel.gd KINGPIN_LOCAL; box_spec.tres bogie; tractor-kenney_spec.tres wheel_positions, max_steer_deg 38; drawbar.gd PIN_LOCAL, SWING_MAX_DEG; farm_tipper_spec.tres bogie; Articulation.JACKKNIFE_MAX_DEG -->

</div>

## The trailers

Common semi-trailers include boxes, tippers, tankers and flatbeds. A loaded trailer can weigh
several times as much as the truck pulling it: for example, three times, for a loaded box trailer
of 24 tonnes behind a tractor unit of 8 tonnes. A semi with no trailer is called a
[bobtail](glossary.md#bobtail).
<!-- box_spec.tres mass 24000; semi_spec.tres mass 8000 -->

### Moving loads

Some loads move while driving, which moves the centre of mass:

- **Tankers.** The liquid keeps moving forward when the rig brakes, as water in a bucket keeps
  going when the bucket stops. It surges forward when the rig brakes and back when it accelerates,
  a little behind the change. A big mass sloshing about shoves the whole rig, so the driver has to
  brake and corner gently.
- **Tippers.** When the body tips up, the load rises and moves back. This puts a heavy mass high
  above the ground, which makes the rig top-heavy (see
  [Weight transfer and rollover](weight-transfer.md#wheel-lift-and-rollover)), so a tipper should
  only be raised when stopped, and only driven very slowly while raised.

<details><summary>Why tankers have walls inside</summary>

A tank that is part full surges badly, because the liquid has room to build up speed. So many
tankers are split into several smaller compartments, or have plates with holes (baffles) inside,
which break up the sloshing. A tank that is completely full does not surge, because the liquid has
nowhere to go.

</details>

## Coupling and uncoupling

To couple a semi-trailer, the truck reverses under the trailer's front. The V-shaped slot at the
back of the fifth wheel guides the kingpin to the middle of the plate, where a jaw locks round it.
The driver then connects the air lines and the electrical cables, and raises the trailer's landing
legs (the trailer's own props, which hold its front up while it is not on a truck). A drawbar
trailer is coupled by dropping its eye over the pin. Both are done with the vehicle stopped.

## Trailer brakes

A trailer must brake itself. Why? When a rig brakes, everything in it wants to carry on forward. A
trailer that weighs twice as much as the truck has twice as much to stop. If only the truck
braked, the trailer would shove it forward from behind through the joint, and on a slippery road
it could fold the rig in two.

- The truck sends the trailer a brake demand when the driver brakes (or when its roll stability
  control does). The trailer's brakes are matched to the truck's, so that neither end pushes the
  other.
- Air brakes take a moment to react (a fraction of a second), because the air has to travel along
  the hose to the trailer and fill the brake chambers.
- Semi-trailers can have their own ABS and roll control
  (see [ABS, traction and stability control](driver-aids.md#roll-stability-on-trucks)).
- When the truck's parking brake goes on, or its air runs low, the trailer's spring brakes apply
  too.

The truck's retarder is an exception: it brakes only the truck, and asks nothing of the trailer
(see [Brakes](brakes.md#the-retarder)). When it is used with a heavy trailer, the trailer pushes on
the truck, and on a slippery road that push can be enough to start a jackknife.

### Jackknife

A [jackknife](glossary.md#jackknife) is a rig folding up, like a pocket knife. The driver sees the
trailer swing into view in the mirror on one side while the cab turns the other way, more and more
quickly, until the two bodies fold together.

Why does it build up so fast? It starts when the truck's rear wheels lose their sideways grip,
most often because they lock while braking on ice or snow (a locked tyre has almost no sideways
grip, see [Slip and the grip curve](slip.md#sharing-grip-between-braking-and-turning)). The back of
the truck starts to slide out. The trailer keeps moving straight on with all its weight and pushes
on the joint, which is now off to one side of the truck's line, so it pushes the back of the truck
further sideways. That swings the truck further, so the push gets more sideways still, and so on,
until the truck meets the trailer. Once it has begun, it is very hard to stop.

So engineers and drivers work on keeping it from beginning. ABS on the truck keeps its rear wheels
turning, so they keep their sideways grip. Trailer brakes that do their share stop the trailer from
pushing. And a driver on a slippery road brakes gently, and early.

A related slide is the trailer swinging out on its own. It happens when the trailer's wheels lock
and lose their sideways grip, so that the trailer slews round behind the truck.

<!-- photo: a jackknifed truck and trailer seen from above (a road-safety training photograph) -->

## The trailer link

European trucks talk to their trailers over a data link on the trailer's electrical connector
(ISO 11992). The truck sends its brake demand, and the trailer reports back its axle load, how hard
its brakes have applied, and whether its ABS or roll control is acting. This lets the truck know
what it is pulling: a trailer's weight changes the braking a lot, and only the trailer's own
sensors know it.

In North America, the connector carries only power. The trailer can still report one thing, an ABS
warning lamp, which is sent along the power line.

## What Carlito simulates

The parameters the simulator uses for this, and where each is set, are listed in
[How the simulation works](simulation.md#towing):

- **Simulation-wide**:
  - [Fifth wheel](simulation.md#fifth-wheel) (`JACKKNIFE_MAX_DEG`)
  - [Drawbar](simulation.md#drawbar) (`SWING_MAX_DEG`, `PITCH_LIMIT_DEG`, `ROLL_LIMIT_DEG`)
  - [Trailer brakes](simulation.md#trailer-brakes) (`BRAKE_APPLY_S`, `BRAKE_RELEASE_S`)
  - [Raised body](simulation.md#raised-body) (`BODY_UP_CAP_KMH`)
- **Per vehicle**:
  - [Trailer link](simulation.md#trailer-link) (`trailer_bus_equipped`)
  - [Each trailer's own settings](simulation.md#each-trailers-own-settings)

<details><summary>Simplification list</summary>

- **No reversing aids**, no steered trailer axles.
- **No coupling by hand**: no landing legs, no air lines or cables to connect. A trailer is
  coupled the moment it is chosen, if the vehicle is stopped and has room behind it.
- **No trailers for the cars**, and no drawbar trailers on the trucks.
- **No real liquid** in the tanker: its surge is a moving centre of mass.
- **A speed limit for a raised body.** The truck is held to 5 km/h while a tipper's body is up, and
  the body only rises with the rig stopped and its parking brake on.
  <!-- TowHost.BODY_UP_CAP_KMH 5; TowedBody.body_raise_allowed -->
- **No cab to hit.** The trailer never touches the cab; instead, the fifth wheel stops it at 75°,
  standing for its front corner meeting the back of the cab. The drawbar stops at 57°, a little
  before the tipper's front corner would meet the tractor's rear tyre.
  <!-- Articulation.JACKKNIFE_MAX_DEG 75 ("a labelled model of trailer-against-cab contact"); drawbar.gd SWING_MAX_DEG 57 (contact at about 61) -->
- **A trailer link on one truck.** The `semi` has the European link. The `semi-conventional` has
  none, so its trailer signals read zero.
  <!-- VehicleSpec.trailer_bus_equipped -->
- **Five trailers only**, each with a fixed load:

| Trailer | Towed by | Weight, about | What is special |
| --- | --- | --- | --- |
| Box | the semis | 24 t | A full load in a tall box: the most side area for a crosswind. |
| Tipper | the semis | 19 t | A body that tips up to empty, worked by the truck's PTO. |
| Tanker | the semis | 21 t | Its liquid surges forward and back as the rig brakes and accelerates. |
| Flatbed | the semis | 14 t | The lightest: an open deck. |
| Farm tipper | the tractors | 10 t | A tipping farm trailer on a drawbar, worked by the tractor's hydraulics. |
<!-- docs/truck.md Four trailers: box 24 000, tipper 19 000, tanker 21 000, flatbed 14 000 kg; docs/tractor.md: farm_tipper "a 10 t towed body" -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `trailer_connected` | out | flag | A trailer is coupled and has answered on the trailer link. False on the `semi-conventional`, which has no link, even with a trailer on (Truck). |
| `trailer_axle_load` | out | kg | The weight on the trailer's axles, from its own springs (Truck). |
| `trailer_brake_demand` | out | % | The brake demand sent to the trailer. Not the retarder (Truck). |
| `trailer_brake_applied` | out | % | How hard the trailer's brakes have actually applied. It trails the demand (Truck). |
| `trailer_abs` | out | flag | The trailer's ABS is holding a wheel (Truck). |
| `trailer_vdc` | out | flag | The trailer's roll control is braking it (Truck). |
| `trailer_ebs_fault` | in | flag | A trailer brake fault set by sloppyCAN, for the dashboard (Truck). |
| `trailer_abs_lamp` | in | flag | The American trailer ABS lamp, set by sloppyCAN (Truck). |
| `air_primary`, `air_secondary` | out | bar | The brake tanks, which a coupled trailer draws on too (Truck). |
<!-- contract/carlito_contract.json: trailer_connected, trailer_axle_load, trailer_brake_demand, trailer_brake_applied, trailer_abs, trailer_vdc, trailer_ebs_fault, trailer_abs_lamp, air_primary, air_secondary -->

The farm tipper on the tractor has no trailer link of its own.

## Related

- [Glossary](glossary.md): every term on this page.
- [Steering and Ackermann](steering.md): why a vehicle's rear wheels cut inside its front wheels.
- [Brakes](brakes.md): the air and spring brakes the trailer shares.
- [ABS, traction and stability control](driver-aids.md): the semis' and trailers' roll control.
- [Weight transfer and rollover](weight-transfer.md): why a high load tips a rig over.
