[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Clutch and torque converter

<p class="lead">This page explains the friction clutch and the torque converter, which slip to
get a vehicle moving and then hold tight.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="A torque converter on most cars and vans; a clutch on the two racing cars">Car</span>
<span class="badge yes" title="A converter on the garbage truck and fire truck; an automated clutch on the semis">Truck</span>
<span class="badge yes" title="A wet clutch in the powershift tractor; the CVT tractor needs none">Tractor</span>
</div>

## Why a coupling is needed

What would happen if an engine were bolted straight to the wheels? At a red light the wheels stop,
and so would the engine, which stalls: it cannot hold still, but must keep turning to make its
own push. And to start again, an engine that has to turn at a thousand revolutions a minute would
have to be joined at once to wheels that are not moving, which would be a violent jerk.

On a bicycle with a fixed gear and no freewheel, the pedals always turn with the wheel. A car
engine is like those pedals, except that it cannot stop turning without stalling. So the engine is
connected to the wheels through a coupling that can slip. While it slips, the engine can run
faster than the wheels. Once their speeds match, it locks, and the engine and wheels turn together
through the gears.

## The friction clutch

<figure>
<img src="img/clutch-kit-pressure-plate-disc.jpg" alt="A car clutch kit laid out: a round pressure plate with a cover on the left, and the friction disc with its rough lining and central hub with springs on the right">
<figcaption>A clutch's pressure plate (left) and friction disc (right). Photo: dave_7 from Lethbridge, Canada, CC BY-SA 2.0, <a href="https://commons.wikimedia.org/wiki/File:Clutch_Kit_(553673775).jpg">Wikimedia Commons</a>.</figcaption>
</figure>

A [clutch](glossary.md#clutch) is two plates pressed together by springs. Pressed hard, they grip
and turn as one. When they are eased apart, they rub and slip, and pass less torque. How much
torque they pass depends on how hard they are pressed and on the friction between them, so plates
pressed only lightly pass only part of the engine's torque, and that is what lets the clutch slip
smoothly instead of jerking.

Slipping is not free. Where two plates rub while one is faster than the other, the energy that
would have moved the car turns into heat (rub your hands together fast). A clutch that slips for a
long time gets hot and wears out, which is why drivers do not hold a car on a hill by slipping the
clutch.

In a manual vehicle, the driver works the clutch with a pedal. In an automated gearbox (common on
semi trucks), a controller works it.

- **Pulling away.** The clutch slips while the vehicle comes up to the engine's speed. A car
  pulls away at higher rpm when the driver wants a quick start, because the engine gives more
  push there. A heavy truck pulls away just above idle, because its diesel already twists hard
  at low rpm ([see the engine](engine.md#the-torque-curve)), and a slow, gentle slip saves the
  clutch from the heat of a heavy load.
- **Locked.** Once the clutch carries the torque without slipping, it stays locked until the next
  gear change. It is built to carry more than the engine's best torque.
- **Opened.** The clutch is opened to stop, or to change gear. If it stays locked while the
  vehicle stops, the wheels drag the engine below idle and it stalls.
- **Engine braking.** A locked clutch lets the engine brake the vehicle when you lift off the
  accelerator.

## The torque converter

![A torque converter cut open: a ring-shaped loop of oil. On the left the pump, turned by the engine's shaft; on the right the turbine, joined to the shaft to the gearbox; at the bottom the stator. Arrows show the oil going out through the pump, across to the turbine, in through it and back through the stator.](img/torque-converter-cutaway.svg "A torque converter cut open.")

![A graph: at a speed ratio of 0 the converter doubles the engine's torque; the multiplication falls in a straight line to 1 at a speed ratio of 0.9, the coupling point, past which the lock-up clutch can close.](img/converter.svg "How much a car's converter multiplies the engine's torque.")
<!-- TorqueConverter.torque_ratio; converter_stall_ratio 2.0 on cars and vans; COUPLING_POINT 0.9 -->

Automatic gearboxes usually have a [torque converter](glossary.md#torque-converter) instead of a
clutch. It is a sealed case of oil with two fans facing each other. The engine spins one, which
throws oil at the other, and the other turns the gearbox. This is like two desk fans facing each
other, where the second turns only because the first blows on it. They can turn at different
speeds without anything rubbing. Because nothing rubs, the converter does not wear out like a
clutch, and it never jerks.

Inside the case there is also a third part, a ring of curved vanes called the stator. The oil that
leaves the turbine would, left alone, flow back against the engine's fan and push against it. The
stator turns that returning oil round so that it joins the engine's push instead of working
against it.

- **It multiplies torque.** When the gearbox side turns much slower than the engine side, a
  converter passes on more torque than the engine gives (about twice as much with the wheels held
  still, in the example above). This is the stator's work, and while pulling away it acts like an
  extra low gear. It fades as the two speeds come together, and is gone at the coupling point.
- **It has a stall speed.** When the car is held on the brakes with the accelerator fully pressed,
  the oil is thrown at a turbine that does not move. The faster the engine spins its fan, the
  harder the oil pushes back on it (as a spoon is harder to stir through a pot of honey the
  faster it goes), so the engine reaches a speed where the oil's push back balances its own
  torque and cannot spin faster. This is called the [stall speed](glossary.md#stall-speed). It
  is not a stall in the engine's sense, and nothing is damaged, but all the engine's power then
  turns to heat in the oil, so the car must not be held like this for long.
- **It locks up.** Slipping oil wastes fuel: the two halves turn at different speeds, and the
  difference is lost as heat. For example, if the engine turns at 2,000 rpm and the gearbox side
  at 1,900, about 5 % of the power is lost. So at cruising speed a lock-up clutch inside the
  converter closes and joins the two sides solidly. It opens again when slowing down.
- **It slips more when coasting.** A converter passes less torque back to the engine than it
  passes forward, so a car coasts more freely when the lock-up is open.

### Creep

At idle the engine still spins its fan, and a little oil still reaches the turbine, so a
converter passes a little torque even then. Because of that, an automatic car in drive moves
forward slowly on its own when you release the brake, as if someone were pushing it very gently.
This is called [creep](glossary.md#creep). It is about walking pace on flat ground, and it can be
enough to hold the car on a gentle slope with no pedal pressed. The same weak push is why the
car does not stall at a red light: with the brake on, the wheels are stopped, but the engine
only has to stir the oil lightly.

Pressing the brake and the accelerator fully together holds the vehicle still. Many cars also cut
the throttle if both are pressed while moving (this is called a brake-throttle override).

## Shifting with a clutch

A gear change also involves the coupling. In an automatic, the gearbox's own internal clutches hand
the drive from one gear to the next, and the converter does not open. With a friction clutch, the
clutch opens or slips during the change (see [Gearbox and shifting](gearbox.md)).

## What Carlito simulates

The parameters the simulator uses for this, and where each is set, are listed in
[How the simulation works](simulation.md#clutch-and-torque-converter):

- **Simulation-wide**:
  - [Launch](simulation.md#launch)
- **Per vehicle**:
  - [Coupling](simulation.md#coupling) (`coupling`)
  - [Clutch reserve](simulation.md#clutch-reserve) (`clutch_reserve`)
  - [Launch speed](simulation.md#launch-speed) (`launch_rpm_over_idle`)
  - [Converter stall](simulation.md#converter-stall) (`converter_stall_ratio`)
  - [Lock-up gear](simulation.md#lock-up-gear) (`lockup_gear`)
  - [Launch engagement](simulation.md#launch-engagement) (`launch_engage_s`)

<details><summary>Simplification list</summary>

- **No clutch pedal and no clutch wear.** Even when shifting by hand, the simulation works the
  clutch.
- **No stalling, no slipping clutch from overheating.** The controller opens the clutch before the
  wheels can drag the engine below idle.
  <!-- docs/drivetrain.md Crank and coupling: the transmission controller (Drivetrain.coupling_step) -->
- **No double clutching or rev matching by the driver**: the gearbox does the rev matching on a
  downshift itself.
- **No twin-clutch gearbox.** The `hatchback-sports` stands in for one with a converter that does
  not multiply torque, a plain fluid coupling, so it still creeps as the real car does on its
  clutch.
  <!-- hatchback-sports converter_stall_ratio 1.0 (docs/drivetrain.md Converter, COMPROMISE) -->

</details>

## What you see in sloppyCAN

No signal reports the clutch or converter directly. Their effect shows in:

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `rpm` | out | rev/min | While the coupling slips, the engine runs faster than the wheels' gear would turn it. On a converter car held on the brakes at full pedal, it sits near the stall speed. |
| `engine_load` | out | % | At idle in gear, a converter's creep load shows as a few percent of load (Truck and tractor). |
| `speed` | out | m/s | With no pedal it rises slowly from 0 to a walking pace: creep. |
<!-- contract/carlito_contract.json rpm, engine_load, speed; docs/drivetrain.md Creep: "`engine_load` 7-11 %" -->

## Related

- [The engine](engine.md): the crank on one side of the coupling.
- [Glossary](glossary.md): every term on this page.
