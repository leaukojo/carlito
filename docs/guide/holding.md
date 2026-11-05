# Holding still

<p class="lead">Standing still sounds simple, but a vehicle on a slope, in gear, with its engine
running, is being pulled two ways at once. The game has several ways to hold a vehicle in place,
from the tyre itself to the gearbox's parking lock.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Hill-start assist, auto hold, the park pawl, the handbrake">Car</span>
<span class="badge yes" title="Hill-start assist, auto hold, spring brakes; no park pawl">Truck</span>
<span class="badge yes" title="The powershift's hill hold and park pawl, or the CVT's active standstill">Tractor</span>
<span class="badge some" title="A parking brake on its landing wheels">Plane</span>
<span class="badge no" title="It floats and drifts">Boat</span>
<span class="badge no" title="It hovers or lands">Drone</span>
<span class="badge some" title="A parking brake, on the trains page">Train</span>
</div>

## The tyre holds first

A braked wheel on a slope is not turning, so by the rule in [Tyres and slip](tyres.md) its tyre
should make no force, and the vehicle would creep downhill. Real rubber holds because it can bend
a little before it slides, like a stiff spring. The game models that spring, about 2 cm of give in
each contact patch at walking pace and below. A wheel held by its brake or by the park lock winds
it up and stays put. A wheel that is free to roll does not, so an unbraked vehicle still rolls
down a hill.
<!-- RayWheel stick_step; wheel.gd STICK_DEFLECTION 0.02 m, STICK_SPEED 0.5 m/s; docs/vehicles.md Holding at rest: static friction -->

The spring can only hold what the brake holds. If the slope's pull is more than the brake can
take, the vehicle slides with its wheels still locked.

## Rolling back on a hill start

The harder problem is pulling away uphill. The moment the driver lifts off the brake to press the
accelerator, nothing holds the vehicle until the drive takes up, so it rolls back.

A car with an automatic gearbox is helped by [creep](glossary.md#creep): its torque converter
pulls gently at idle, enough on its own to hold most cars on a slope of about 15 %. Past that, or
on any vehicle with a clutch, which does not creep, the vehicle rolls back. Three systems stop it.
<!-- docs/drivetrain.md Hill hold: "Creep holds the cars and the heavy vans on 10-19 % and the Kenney trucks on 22-23 %" -->

### Hill-start assist

[Hill-start assist](glossary.md#hill-start-assist) keeps the foot brake on for a moment after the
driver releases it. It lets go as soon as the engine's drive is enough to hold the vehicle on the
slope, or when its timer runs out: about one second on a car, three on the trucks and semis.
<!-- HillHold Kind.ASSIST; hill_hold_s: sedan_spec.tres 1.0, semi_spec.tres 3.0, garbage-truck_spec.tres 3.0 -->

It reads the slope from the ground under the wheels, not from how the body is tilted, so a car
squatting under acceleration is not mistaken for one on a hill. It counts the weight of a trailer,
and it holds the trailer's brakes too. It ignores rolling resistance, so it lets go slightly late,
never early. On the flat or pointing downhill it lets go at once.
<!-- hill_hold.gd: "The grade is the wheels' contact plane, never body pitch"; drive_holds: "Rolling resistance is left out: the hold lets go late, never early"; docs/drivetrain.md: WheelDrive.towed_kg, foot_pedal -->

Every vehicle with ABS has it. Switching ABS off in the LAB switches it off too.

### Auto hold

[Auto hold](glossary.md#auto-hold) goes further. With it on, a vehicle that has come to a stop in drive or reverse keeps
its whole foot brake on, with no pedal pressed, until the driver presses the accelerator. Then
hill-start assist takes over for the pull-away. It is a setting, SETTINGS ▸ AUTO HOLD, off at
first, and it works only when you drive with the keys or the on-screen pedals: a gamepad and
sloppyCAN get the real creep instead. The dashboard's AUTO HOLD lamp glows dim while it is on and
bright while it is holding.
<!-- InputRouter.auto_hold; pause_menu.gd AUTO_HOLD_HELP; docs/drivetrain.md: "Gamepad and bridge: real creep"; dashboard.gd auto_hold "dim while switched on, lit while holding" -->

### The tractor's hill hold

The powershift tractor has a hold of its own, modelled on a real tractor maker's. Whenever it
stands still in gear with the accelerator up, it holds itself on the foot brake, with front-wheel
drive engaged so all four wheels are held. It has no timer. It lets go once the accelerator is
pressed and the clutch has taken up enough to carry the slope. A real tractor holds inside its
gearbox; the game uses the brakes, which does the same job.
<!-- HillHold Kind.STANDSTILL (Valtra HillHold); tractor-kenney_spec.tres hill_hold 2; COMPROMISE at GroundDriveSpec.hill_hold: "a real tractor holds in the transmission" -->

### Active standstill on the CVT tractor

The `tractor-cvt` needs no brake to stand still. Its stepless gearbox can set a ratio of zero,
at which the engine runs but the wheels cannot turn: [active standstill](glossary.md#active-standstill).
It holds the tractor on a slope until the driver asks to move.
<!-- Drivetrain.standstill_hold; docs/drivetrain.md The CVT: "a ratio of 0 holds (active standstill)" -->

## Parking

### The park pawl

An automatic car's P position drops a steel tooth, the [park pawl](glossary.md#park-pawl), into a
toothed wheel on the gearbox's output. The cars, the vans and the powershift tractor have one. It
only drops in below about walking pace; faster than that it ratchets over the teeth and holds
nothing.
<!-- WheelDrive.PAWL_ENGAGE_SPEED 1 m/s; contract gear: "the gearbox's park pawl where one is fitted (cars, vans, the tractor's powershift)" -->

The pawl locks the gearbox, not the wheels. The wheels are held only through the
[differential](glossary.md#differential), and an open differential still lets its two wheels turn
against each other. So a car parked in P with one driven wheel on ice can slide away. A front-drive
car in P holds only its front wheels.
<!-- docs/vehicles.md P (park): "a car in P with one driven wheel on ice slides away" -->

The keyboard never selects P. A vehicle goes into P when sloppyCAN sends the P gear byte. In a
challenge, where only sloppyCAN may drive, the vehicle also goes into P, with its key at Lock and
its handbrake on, whenever sloppyCAN is not connected or stops sending, so a lost connection
parks it rather than letting it roll.
<!-- InputRouter.locked_idle: key Lock, P, handbrake on: "a lost connection parks it rather than coasting" -->

### The handbrake and spring brakes

The handbrake holds the rear wheels directly, without the gearbox. Every vehicle's handbrake can
park it, laden, on the slope the law requires: 20 % for cars and light vans, 18 % for the
heavier vehicles, and in practice far steeper. On the trucks the handbrake is their spring brakes ([Brakes](brakes.md) explains
them), which is how a truck parks, since its gearbox has no pawl.
<!-- BrakeSizing: parks the laden body on 20 % (UN R13-H, to 3.5 t) or 18 % (R13) -->

## What the game leaves out

- **No electronic parking brake button**, and no automatic handbrake when the engine stops.
- **No P from the keyboard.**
- **No roll-away warning**: a vehicle left in neutral on a hill just rolls.

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `gear` | in | enum | 254 is P: the park pawl, where one is fitted. A truck reads it as N. |
| `gear` | out | enum | P only while a pawl is engaged; N where a P request found none. |
| `handbrake` | in | flag | The parking brake on the rear wheels, or a truck's spring brakes. |
| `status` | out | bitfield | Bit 5 is the handbrake; bit 2 clears when the vehicle stops moving. |
<!-- contract/carlito_contract.json: gear (in, out), handbrake, status bits 2 and 5 -->

Hill-start assist and auto hold have no signal of their own.

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: a hill start</p>

On the keyboard, holding the brake key at a standstill selects reverse
([Gearbox and shifting](gearbox.md#driving-forwards-and-backwards-from-the-keyboard)), so you
cannot sit still on the foot brake. These steps use the handbrake and auto hold instead.
<!-- InputRouter.arbitrate_local: brake_reverse at a standstill (REVERSE_ENGAGE_SPEED 0.5 m/s) with no accel requests R; auto_hold: "the held brake never reads as S at a standstill" -->

1. Find a steep road in **Level 2 - Mountain** with the `race` car. It has a clutch and no
   hill-start assist.
2. Stop facing uphill and hold the handbrake (**Space**). Let it go and press the accelerator: the
   car rolls back a little before it pulls away.
3. Open SETTINGS and set AUTO HOLD on, then do the same in the `sedan` without the handbrake. As
   it stops, the AUTO HOLD lamp lights and the car stays put with your hands off the keys.
4. Press the accelerator. Hill-start assist takes over from the auto hold for a moment, and the
   car pulls away without rolling back.

</div>

## Related

- [Clutch and torque converter](coupling.md): creep, and why a clutch does not hold.
- [Brakes](brakes.md): the handbrake and the trucks' spring brakes.
- [Glossary](glossary.md): every term on this page.
