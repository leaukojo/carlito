[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Glossary

<p class="lead">This page explains every technical word the guide uses, in alphabetical
order.</p>

The first sentence or two under each word is its short explanation (it also appears when you
hold the pointer over a dotted link). Anything after that adds detail (for example, the signal that carries it).

Units are at the end: [Units](#units).

## A

### ABS
Anti-lock brakes. When a hard brake would stop a wheel turning while the vehicle still moves, ABS
lets the brake off just enough to keep the wheel turning, because a turning tyre grips better than
a skidding one and can still steer.

A real system does this by releasing and applying the brake many times a second. ABS does not add
grip; it keeps each tyre near the best part of its grip curve. It is standard on road cars and
trucks, but racing cars and tractors often have none. See
[ABS, traction and stability control](driver-aids.md).

### Accelerator
The pedal that asks the engine for more power. It is also called the throttle pedal.

In sloppyCAN it is the `accel` signal, from 0 to 100 %.

### Accelerometer
A sensor that measures how hard the vehicle is pushed, along it and across it. A small mass on
springs inside it is pushed back as the vehicle speeds up, so a still accelerometer reads 1 g (the
ground holding it up against gravity) and a falling one reads 0.

See [Position, heading and distance](position.md).

### Ackermann steering
A way of angling the two front wheels so that the inside wheel turns more sharply than the
outside one in a corner. Both wheels then roll round the same centre point instead of fighting
each other.

See [Steering and Ackermann](steering.md).

### Active standstill
A way for a tractor with a stepless gearbox ([CVT](#cvt)) to stand still on a slope without its
brakes. The gearbox sets its ratio to zero, so the wheels cannot turn although the engine runs.

### Aerodynamic drag
The push of the air against a moving vehicle, pointing backwards. It grows with the square of the
speed, so twice as fast means four times the drag.

Wind changes it, because what matters is the speed through the air, not over the ground. See
[Air and rolling resistance](resistance.md).

### Air brakes
Brakes worked by compressed air instead of brake fluid, used on heavy trucks. Air gives a lot of
force, and a trailer can be joined to it with a simple hose.

A truck usually has two air circuits, with tanks that an engine-driven compressor fills. If either
tank falls too low, the [spring brakes](#spring-brake) come on by themselves.

### Air reservoir
A tank of compressed air on a truck, which feeds the air brakes. Each press of the brake pedal
uses some air; holding the pedal down uses no more.

The pressures of the two circuits are sent as `air_primary` and `air_secondary`, in bar.

### All-speed governor
A way of controlling a diesel engine in which the pedal (or the hand throttle) chooses an engine
speed, and the engine adds or takes away fuel to hold that speed as the load changes. Tractors
work this way.

Under load the speed sags a little, by a few percent, which is called [droop](#droop).

### Alternator
The small generator the engine turns, through a belt, to charge the battery and power the
electrics while the engine runs.

While it charges, a car's battery reads about 14 volts; with the engine off it rests at about
12.6 volts.

### AMT
Short for automated manual transmission, a gearbox built like a manual one, with a friction
clutch, in which a computer works the clutch and picks the gears. Each change cuts the drive for a
moment.

They are common on semi trucks. See [Kinds of gearbox](gearbox-kinds.md#the-automated-manual).

### Anti-dive
Suspension geometry that keeps the nose of a car from dipping as much when it brakes. Links that
slope up from the wheel to the body push the body up a little as the brakes drag the wheels back.

The weight still moves forward; only the springs squash less. See
[Suspension](suspension.md#links-that-resist-dive-and-squat).

### Anti-roll bar
A springy bar joining the left and right wheels of one axle. When the body leans in a corner, the
bar twists and resists the lean.

A stiffer bar at one end makes that end lose grip sooner, which is one way designers tune
[understeer](#understeer) and [oversteer](#oversteer).

### Anti-squat
Suspension geometry that keeps the tail of a car from sinking as much when it accelerates. It works
like [anti-dive](#anti-dive), with sloping links at the rear.

### Articulation
The angle between a towing vehicle and its trailer, seen from above. It is zero when the two are
in a straight line.

Too much articulation is a [jackknife](#jackknife). See [Towing](towing.md).

### Articulated steering
Steering by bending the whole vehicle in the middle, as some large tractors and loaders do.

### ASR
Anti-slip regulation, the usual name for [traction control](#traction-control) on trucks.

### Auto hold
A feature that keeps the foot brake on whenever the vehicle stops, until the accelerator is
pressed, so the driver can take their foot off the brake in a queue.

See [Holding still](holding.md#auto-hold).

### Automatic gearbox
A gearbox that changes gear by itself, built from [planetary gear sets](#planetary-gear-set) whose
parts are held or released by clutches worked by oil pressure. It changes clutch to clutch, so the
drive never stops.

Cars, vans, refuse trucks and fire trucks often have one. See
[Kinds of gearbox](gearbox-kinds.md).

### Axle
A pair of wheels across the vehicle, one on each side, front or rear, with the shaft or beam that
carries them.

Most road vehicles have two; semi-trailers often have three, close together, called a
[bogie](#bogie).

### Axle load
How much weight one axle carries, in kilograms. It changes as weight moves between the axles.

Trucks and tractors send their rear axle's load as `axle_load`.

## B

### Ballast
Extra weight added to a tractor so that its tyres can push harder before they spin. More weight on
a tyre gives it more grip, though not quite in proportion (see
[load sensitivity](#load-sensitivity)).

### Bar
A unit of pressure, about the pressure of the air around us at sea level. A truck's air tanks hold
around ten times that.
<!-- truck_telemetry.gd AIR_MAX_BAR 12 -->

### Battery
The vehicle's store of electricity. It starts the engine and powers the lights and electronics
when the engine is not running.

Its voltage is sent as `battery`.

### Bias ratio
How unevenly a limited-slip or Torsen-type differential may split its torque. The slower wheel may
take up to this many times the faster wheel's torque, and a ratio of 1 is an open differential.

### Bicycle angle
A single steering angle that stands for the angles of the two front wheels. Picture the car as a
bicycle with one front wheel in the middle: that wheel's angle is the bicycle angle.

It is also called the mean steer angle. See
[Steering and Ackermann](steering.md#one-angle-the-bicycle-model).

### Bobtail
A semi tractor unit driving with no trailer.

### Bogie
A group of axles close together that share the load, like the three rear axles of a semi-trailer.

### Brake bias
How the braking is shared between the front and rear wheels. Vehicles brake harder at the front,
because braking moves weight onto the front tyres.

See [Brakes](brakes.md#front-and-rear).

### Brake fade
Brakes getting weaker as they get very hot. Past a temperature that depends on the kind of brake,
the same pedal gives less braking.

The handbrake fades too when it works the same brakes. A faded brake recovers once it cools. See
[Brakes](brakes.md#heat-and-fade).

### Brake temperature
How hot a vehicle's brakes are. Braking heats them, and the air cools them.

The hottest brake is sent as `brake_temp`, in degrees Celsius.

## C

### CAN bus
A two-wire network that the electronic parts of a vehicle use to send each other short messages.
CAN stands for Controller Area Network.

Different industries use different message sets on it, such as [J1939](#j1939) for trucks and
[ISOBUS](#isobus) for farm machines.

### CANopen
A message set for CAN used in machines and vehicle bodies.

For example, a garbage truck's body can use CANopen on its own network, which reaches the truck's
main network through a gateway.

### Centre differential
A [differential](#differential) between the front and rear axles of a four-wheel-drive vehicle. It
lets the two axles turn at slightly different speeds in a corner, where the front wheels travel
farther.

### Centre of mass
The balance point of a vehicle, where all its weight seems to act. A high centre of mass makes a
vehicle lean more and tip over sooner.

### Clutch
Two friction plates that join the engine to the gearbox. Pressed together, they turn as one;
slipping, they pass some torque while turning at different speeds, which lets a vehicle pull away
smoothly.

It is worked by a pedal, or by a controller in automated gearboxes. See
[Clutch and torque converter](coupling.md).

### Coefficient of friction
A number saying how grippy two surfaces are together. It is the most force they can pass along
their contact, divided by the force pressing them together.

It is written μ ([mu](#mu)). For a tyre, it belongs to the tyre and the ground together. See
[Tyres and grip](tyres.md#the-coefficient-of-friction).

### Combined slip
A tyre doing two things at once, pushing along the road (driving or braking) and pushing sideways
(cornering). It has one budget of grip to share between the two, so hard braking leaves less grip
for turning.

See [Slip and the grip curve](slip.md#sharing-grip-between-braking-and-turning).

### Compliance steer
A small change in a wheel's angle caused by the rubber bushes in the suspension bending under
sideways force. Designers can use it to steady the car.

See [Steering and Ackermann](steering.md#the-suspension-steers-a-little-too).

### Contact patch
The small area where a tyre touches the road, about the size of a hand on a car. Every force
between the vehicle and the ground passes through the contact patches.

### Contract
The single list of every signal Carlito and sloppyCAN exchange, with each signal's name, direction,
unit and range. Both programs read it, so they always agree on what a message means.

### Coolant
The liquid that carries heat away from an engine to the radiator. Once the engine is warm it runs
at about 90 °C, and warmer under load.

Its temperature is sent as `coolant`, in degrees Celsius.

### Cornering stiffness
How much sideways force a tyre makes for each degree of [slip angle](#slip-angle), while it is
still well below its peak. A heavier load gives more force, but less per kilogram of load.

### Crank
The engine's crankshaft, the main shaft the pistons turn. Its speed is the engine speed, in
[rpm](#rpm), and it is heavy, so it takes time to speed up and slow down.

### Creep
The slow forward movement of a car with an automatic gearbox when the brake is released and the
accelerator is not pressed. The [torque converter](#torque-converter) passes a little of the
idling engine's torque to the wheels.

See [Clutch and torque converter](coupling.md#creep).

### Crosswind
Wind blowing across a vehicle's path. It pushes the vehicle sideways and usually turns its nose a
little away from the wind.

See [Air and rolling resistance](resistance.md#side-force-and-crosswind).

### CVT
A continuously variable transmission, a gearbox with no fixed gears whose ratio changes smoothly.
The engine can then stay at the speed that suits it while the vehicle speeds up.

On a tractor with one, the driver's pedal asks for a ground speed and the gearbox finds the ratio.
See [Kinds of gearbox](gearbox-kinds.md#the-cvt-no-steps-at-all).

## D

### Damper
The part of the suspension that slows the springs down, so the body does not keep bouncing. It is
also called a shock absorber.

### Dead reckoning
Working out where a vehicle is from where it last was, how far it has travelled and each change
of direction since. Small errors add up, so the position drifts until a fix (such as GPS)
corrects it.

### Diff lock
A lock that joins both wheels of an axle so they must turn at the same speed. It stops one wheel
spinning uselessly in mud while the other stands still, but it scrubs the tyres in a turn.

Tractors have one on their rear axle (`diff_lock`). See
[Differentials and four-wheel drive](differentials.md#the-tractors-diff-lock-and-front-wheel-drive).

### Differential
The gears in the middle of an axle that let the left and right wheels turn at different speeds.
In a corner the outside wheel travels farther than the inside one, so it must turn faster.

See [Differentials and four-wheel drive](differentials.md).

### Dog clutch
A collar that slides along a shaft, with stubby teeth on its side (the dogs). Slid against a gear,
its dogs lock that gear to the shaft.

See [Kinds of gearbox](gearbox-kinds.md).

### Downforce
Air pushing a car down onto the road, made by wings and the shape of the body. It grows with the
square of the speed and gives the tyres more grip.

It is mostly used on racing cars. See [Air and rolling resistance](resistance.md#downforce-on-racing-cars).

### Draft
The pull needed to drag a plough or harrow through the soil. It depends on the depth, the soil and
the speed.

A tractor sends it as `draft_force`.

### Drag area
One number for how much air drag a vehicle makes: the size of its front multiplied by its drag
coefficient (how easily the air flows round it).

For example, about 0.65 m² for a saloon. A truck's is several times larger.
<!-- sedan_spec.tres drag_area 0.65 -->

### Drawbar
A rigid bar on the front of a trailer, ending in an eye that drops over a pin low on the back of a
tractor. The trailer pivots on that one pin.

It carries much less of the trailer's weight than a truck's [fifth wheel](#fifth-wheel). See
[Towing](towing.md).

### Drive slip
Slip while driving, when the tyre's surface turns a little faster than the ground passes under it.

### Drivetrain
Everything between the engine and the wheels: the clutch or converter, the gearbox, the
differentials and the shafts.

### Droop
How much a governed engine's speed falls below its setting under full load, as a share of the
setting. On a tractor it is a few percent.

### Dual-clutch gearbox
Two gearboxes in one case, one for the odd gears and one for the even gears, each with its own
clutch. The next gear waits ready on the other half, so a change is one clutch opening as the other
closes.

See [Kinds of gearbox](gearbox-kinds.md#the-dual-clutch-gearbox).

## E

### Engine braking
The slowing force of the engine when the driver lifts off the accelerator in gear. The wheels turn
the engine, and its friction (and, on a petrol engine, sucking air past the closed throttle) holds
them back.

See [The engine](engine.md#friction-and-engine-braking).

### Engine load
How hard the engine is working. It is the torque the engine is giving, as a percentage of the most
it can give at any speed.

Trucks and tractors send it as `engine_load`.

### ESC
Electronic stability control, the usual name for [stability control](#stability-control) on cars.

## F

### Fifth wheel
The large, flat coupling plate on the back of a truck's tractor unit. The semi-trailer's
[kingpin](#kingpin) locks into it, and a large share of the trailer's weight rests on it.

See [Towing](towing.md).

### Final drive
The last fixed set of gears before the wheels, in the axle. Together with the gearbox's ratio it
sets how many times the engine turns for each turn of the wheels.

### Friction ellipse
The limit on a tyre's total force, drawn as an oval with the push along the road on one axis and
the push sideways on the other. A tyre can use all its grip for braking, all for turning, or a mix,
but the mix never goes outside the oval.

See [Slip and the grip curve](slip.md#sharing-grip-between-braking-and-turning).

### Fuel rate
How fast the engine burns fuel, in litres per hour. It grows with the engine's torque and speed.

It is sent as `fuel_rate`.

## G

### Gear
A wheel with teeth around its edge. Two gears whose teeth fit together turn each other, and a
small one turns a big one more slowly but with more [torque](#torque).

See [Gearbox and shifting](gearbox.md#two-gears-trading-speed-for-strength).

### Gear ratio
How many times the engine turns for each turn of the gearbox's output. A low gear has a large
ratio, so the engine turns fast, the wheels slowly, and the pull is strong.

See [Gearbox and shifting](gearbox.md#what-a-gear-does).

### Gear byte
The number sloppyCAN uses to choose a gear. 0 is neutral, 1 to 24 are the drive gears, 254 is park
and 255 is reverse.

### Governor
A control that limits a speed by cutting the fuel. A road-speed governor (on trucks and many vans)
fades the fuel as the vehicle nears its set speed; an engine governor holds an engine speed.

See [all-speed governor](#all-speed-governor) and
[The engine](engine.md#limits-the-rev-limiter-and-the-speed-governor).

### GPS
Satellite positioning. A receiver works out where it is (its latitude and longitude) from the
signals of several satellites.

It is sent as `lat` and `lon`.

### Grade
How steep a slope is, as a percentage, the height it climbs divided by the distance along the
flat. A 10 % grade climbs 10 m for every 100 m along the flat.

### Grip
How much force a tyre can pass to the ground before it slides, in newtons. It is the
[coefficient of friction](#coefficient-of-friction) times the force pressing the tyre down, so it
depends on the tyre, the ground and the load.

See [Tyres and grip](tyres.md#the-coefficient-of-friction).

### Grip curve
A graph of how much force a tyre makes at each amount of [slip](#slip), as a share of its
[grip](#grip). The force rises quickly to a peak at a small slip, then falls a little as the tyre
slides more.

See [Slip and the grip curve](slip.md#the-grip-curve).

### Ground speed
The vehicle's true speed over the ground, whatever the wheels are doing.

Tractors send it as `ground_speed`, beside the wheel-based [wheel speed](#wheel-speed).

### Gust
A short rise in the wind's speed.

### Gyroscope
A sensor that measures how fast the vehicle turns. Vehicles use it to sense the
[yaw rate](#yaw) and, between GPS fixes, to keep track of the heading.

## H

### Handbrake
The parking brake, worked by a lever or a button. It usually brakes only the rear wheels, and can
lock them, which is what lets a car swing its rear round in a handbrake turn.

It often works the same rear brakes as the pedal, so when they are hot it fades with them. See
[Brakes](brakes.md#the-handbrake).

### Hand throttle
A lever that sets an engine speed and stays where it is put, so the driver's foot is free.
Tractors have one.

It is sent as `hand_throttle`. See [The engine](engine.md#the-tractors-governor).

### Heading
The compass direction the vehicle's nose points, in degrees: 0 is north, 90 east, 180 south and
270 west.

It is sent as `heading`.

### Hill-start assist
A brake hold that stops a car rolling back while the driver moves a foot from the brake to the
accelerator on a slope. It lets go as soon as the engine pulls hard enough to hold the car, or
after a short time.

See [Holding still](holding.md).

### Hitch
The coupling at the back of a tractor. The three-point hitch carries implements on two lower arms
and one top link, and can raise and lower them.

Its position is sent as `hitch_pos`.

### Hour meter
A counter of how long the engine has run, in hours. Machines that work standing still, like
tractors, are serviced by hours rather than by distance.

It is sent as `engine_hours`.

### Hydraulic remote
A tractor outlet that sends oil under pressure to a trailer or implement, to work a ram (for
example, to open a spreader's gate or tip a farm trailer). It is also called an SCV, for selective
control valve.

Its flow is sent as `scv_flow`.

### Hydrostatic drive
A drive through oil, in which a pump turned by the engine pushes oil to a motor that turns the
output. Its speed can be set to anything, including zero and backwards.

A tractor's [CVT](#cvt) uses one for part of its power. See
[Kinds of gearbox](gearbox-kinds.md#the-tractors-power-split-cvt).

## I

### Idle
The slowest speed an engine runs at by itself, with no pedal pressed.

### Implement
A machine a tractor carries or pulls, such as a plough, a harrow, a mower or a spreader.

See [Implements and the PTO](implements.md).

### Inertia
An object's resistance to changing how it moves. A heavy vehicle takes more force to speed up,
slow down or turn, and spinning parts, like wheels and the engine's crank, resist changing their
spin.

### ISO 11992
The message set for the data link between a truck and its trailer, carried on two pins of the
trailer's electrical connector. It covers the brakes and running gear only.

### ISOBUS
The message set farm tractors and implements use to talk to each other (ISO 11783). It is built
on [J1939](#j1939).

## J

### J1939
The message set heavy trucks use on their CAN bus. Parts of a tractor's network use it too.

### Jackknife
A towing vehicle and its trailer folding towards each other until they touch, like a pocket knife
closing.

See [Towing](towing.md#jackknife).

## K

### Kickdown
Pressing the accelerator most of the way down in an automatic, which makes the gearbox drop to a
lower gear at once for more pull.

### Kingpin
The steel pin under the front of a semi-trailer that locks into the tractor unit's
[fifth wheel](#fifth-wheel).

## L

### Lateral acceleration
How hard a vehicle is being pushed sideways, usually in a corner, in metres per second squared.
9.8 of them is one g, the pull of gravity.

It is sent as `accLat`.

### Limited-slip differential
A differential that lets the two wheels turn at different speeds, but sends more torque to the
slower wheel when one starts to spin. A Torsen is one kind.

See [Differentials and four-wheel drive](differentials.md#limited-slip-and-torsen-type-differentials).

### Load sensitivity
The way a tyre's grip, for each kilogram it carries, falls as it carries more. A tyre pressed twice
as hard grips more in total, but not twice as much.

See [Slip and the grip curve](slip.md#a-tyre-pressed-harder-grips-more-but-not-in-proportion).

### Lock
How far the steering can turn the wheels, in degrees. Full lock is as far as it goes.

### Lock-up clutch
A clutch inside a torque converter that joins its two halves solidly once the car is moving, so
no power is lost to the oil's slip.

## M

### Manual gearbox
A gearbox whose gears the driver chooses with a lever and a clutch pedal.

See [Kinds of gearbox](gearbox-kinds.md#the-manual-gearbox).

### MFWD
Mechanical front-wheel drive, a tractor's switchable drive to its front axle. With it engaged, all
four wheels pull.

It is requested with `fwd_drive`. See
[Differentials and four-wheel drive](differentials.md#the-tractors-diff-lock-and-front-wheel-drive).

### Motoring
An engine being turned by the wheels instead of turning them, with no fuel. Its friction then
slows the vehicle, which is [engine braking](#engine-braking).

### Mu
The Greek letter μ, the usual symbol for the [coefficient of friction](#coefficient-of-friction),
how much grip a tyre and the ground give together for each newton pressing the tyre down. Dry
asphalt gives a car tyre about 1, and ice about a tenth of that.
<!-- GroundDriveSpec mu_long default 1.05; surface.gd REF_GRIP Ice 0.12 -->

## N

### Newton
The unit of force. One newton is about the weight of a small apple, and a thousand newtons is a
kilonewton (kN).

## O

### Odometer
The distance counter, in kilometres. It adds up the distance driven and never counts down.

It is sent as `odo`. See [Position, heading and distance](position.md).

### Off-tracking
How far a turning vehicle's rear wheels, or its trailer's, run inside the path of its front
wheels. The longer the vehicle, the more they cut inside.

See [Towing](towing.md#the-trailer-cuts-inside-a-turn).

### Open differential
A plain [differential](#differential) that always gives the two wheels the same torque. If one
wheel loses grip, the other gets no more than the slipping one, so the vehicle can be stuck with
one wheel spinning.

### Overrun
The engine being driven by the wheels, as when coasting downhill in gear.

### Oversteer
A car turning more sharply than the driver asked, because the rear tyres slide first. The back
swings out.

[Understeer and oversteer](understeer.md) explains it.

## P

### Park pawl
A steel tooth inside an automatic gearbox that locks its output in P. It only drops in at walking
pace or slower; faster, it clicks over the teeth.

See [Holding still](holding.md#the-park-pawl).

### Pedal map
The rule that turns the accelerator's position into an amount of fuel, a torque request or an
engine speed. Petrol cars, diesel trucks and tractors often use different rules.

See [The engine](engine.md#the-throttle-and-the-pedal-map).

### Pitch
The nose of a vehicle tipping up or down. A car pitches forward when it brakes.

### Planetary gear set
A sun gear in the middle, planet gears around it on a carrier, and a ring gear around the outside
with its teeth facing inwards. Holding one part still and driving another gives a different ratio
for each choice.

Automatic gearboxes are built from them. See
[Kinds of gearbox](gearbox-kinds.md#the-automatic-gearbox).

### Power
How fast work is done, in watts (W) or kilowatts (kW). An engine's power is its torque times how
fast it turns, so the same torque gives more power at a higher rpm.

See [The engine](engine.md#torque-and-rpm).

### Powershift
A tractor gearbox that changes gear under load, clutch to clutch, without the driver pressing a
clutch, so the tractor keeps pulling through the change.

Sixteen forward gears is not unusual. See [Kinds of gearbox](gearbox-kinds.md#the-powershift).

### PTO
Power take-off, a spinning shaft at the back of a tractor that drives an implement's moving parts.
It runs at a standard speed, often 540 or 1000 turns a minute, and its power is a load on the
engine.

It is sent as `pto`, `pto_mode` and `pto_rpm`. See [Implements and the PTO](implements.md).
<!-- contract pto_mode enum 540 / 1000 -->

## R

### Redline
The highest safe engine speed. The [rev limiter](#rev-limiter) stops the engine going past it.

### Retarder
An extra brake inside a truck's driveline that slows it without using the wheel brakes, so they
stay cool on long descents. It is weak at low speed, so it cannot stop the truck.

Many trucks have one (`retarder`, `retarder_state`). See [Brakes](brakes.md#the-retarder).

### Rev limiter
A control that cuts the fuel when the engine reaches its redline, so its moving parts are not
pulled hard enough to break.

### Ride frequency
How many times a second a vehicle's body bounces up and down on its springs after a bump. Softer
springs or a heavier body give a lower frequency and a gentler ride.

For example, a saloon might bounce about 1.4 times a second. See
[Suspension](suspension.md#how-stiff-and-how-soft).
<!-- simulation.md Suspension: about 1.4 Hz for a saloon -->

### Roll
A vehicle leaning to one side about its length, as a car body leans outwards in a corner.

### Roll steer
A small change in the wheels' angle caused by the body leaning in a corner, from the shape of the
suspension links. On road cars it is usually designed to steady the car.

See [Steering and Ackermann](steering.md#the-suspension-steers-a-little-too).

### Rolling resistance
The small force that slows a rolling tyre, from the rubber squashing and springing back and from
soft ground giving way. It grows in proportion to the load on the tyre.

On a hard road it is about 1 % of a car tyre's load; soft ground like mud or sand adds much more.
See [Air and rolling resistance](resistance.md#rolling-resistance).

### Roll stability control
The part of stability control that brakes a truck and its trailer before the sideways force could
tip them over.

Semi-trailers can have their own, which brakes the trailer by itself using its own sensors.

### Rollover threshold
The sideways acceleration at which a vehicle tips over rather than sliding. A tall, narrow
vehicle tips sooner.

See [Weight transfer and rollover](weight-transfer.md).

### Rpm
Revolutions per minute, how many full turns a shaft makes in a minute. A car engine idles at
about 900 rpm, for example.

## S

### Semi-trailer
A trailer with wheels only at the back. Its front rests on the tractor unit's
[fifth wheel](#fifth-wheel).

### Sequential gearbox
A racing gearbox whose gears can only be taken in order, one up or one down. Each change is very
quick, often with a short ignition cut.

See [Kinds of gearbox](gearbox-kinds.md#the-sequential-gearbox).

### Shift policy
The rules an automatic gearbox uses to decide when to change gear, from the road speed, the pedal
and whether the vehicle is climbing.

See [Gearbox and shifting](gearbox.md#how-the-automatic-chooses-a-gear).

### Signal
One named value passed between Carlito and sloppyCAN, such as the engine speed `rpm` or the brake
pedal `brake`.

"Out" signals go from the simulator to sloppyCAN; "in" signals come the other way.

### Slip
The small difference between how a tyre moves over the ground and how it turns. A tyre needs a
little slip to make any force at all, so slip does not mean the tyre is skidding.

See [slip ratio](#slip-ratio), [slip angle](#slip-angle) and
[Slip and the grip curve](slip.md).

### Slip angle
The angle between where a tyre points and where it actually travels. A cornering tyre always
travels a little wide of where it points, and that small angle is what makes its sideways push.

See [Slip and the grip curve](slip.md#slip-angle-across-the-wheel).

### Slip ratio
How much faster or slower a tyre's surface turns than the vehicle moves, as a share of the
vehicle's speed. It is 0 when rolling freely, above 0 when driving (a lot when spinning) and below
0 when braking, down to −1 for a locked wheel.

See [Slip and the grip curve](slip.md#slip-ratio-along-the-wheel).

### sloppyCAN
The companion program Carlito talks to, a CAN bus simulator and analysis tool that runs in a web
browser. It turns most of the simulator's signals into CAN traffic and can send commands back.

### Spoiler
A lip or small flap at the back of a car's body that spoils the airflow there, to cancel the
slight lift a body makes at speed. It is often confused with a wing, which pushes the car down.

See [Air and rolling resistance](resistance.md#downforce-on-racing-cars).

### Spring brake
A truck's parking brake, applied by a strong spring and held off by air pressure. If the air runs
out, the spring puts the brake on by itself, so a truck that loses its air stops.

See [Brakes](brakes.md#air-and-spring-brakes).

### Stability control
A system that brakes one wheel by itself to stop a vehicle spinning or sliding wide. It compares
how fast the vehicle turns with how fast the steering asks it to turn.

It is often called ESC. On trucks it also brakes the whole rig before it would tip over. See
[ABS, traction and stability control](driver-aids.md).

### Stall
An engine stalls when a load slows it until it stops, for example when a clutch is let out too
fast in too high a gear.

### Stall speed
The engine speed a car with a [torque converter](#torque-converter) reaches when it is held still
on the brakes with the accelerator fully pressed. It is about 2,400 rpm on a saloon, for example.

Nothing stalls: the oil in the converter simply holds the engine back at that speed. See
[Clutch and torque converter](coupling.md#the-torque-converter).
<!-- Drivetrain.stall_rpm: 2375 on the sedan -->

### Static friction
The grip that holds a still tyre in place before it starts to slide. A parked car is held by the
small springy give of the rubber in each tyre's contact patch.

### Steering taper
A simplification used in driving simulators, in which the steering lock gets smaller as the speed
rises, so that full steering at motorway speed does not throw the car off the road. A real
steering wheel has no such limit.

See [Steering and Ackermann](steering.md).

### Surface
The kind of ground under a tyre, such as asphalt, gravel, grass, mud, snow or ice. Each gives a
different grip and a different rolling resistance.

The simulator has twelve: asphalt, wet road, airfield pad, gravel, dirt, grass, sand, rock, mud,
field soil, snow and ice. See [Ground and tyre types](surfaces.md).

### Suspension
The springs, dampers and links between the wheels and the body. They let the wheels follow bumps
and keep the tyres pressed onto the road.

See [Suspension](suspension.md).

### Swinging front axle
A front axle built as one beam on a single pivot in the middle, so one wheel can rise as the other
drops and both keep touching the ground. Farm tractors use it, with a stop on each side to limit
the swing.

See [Suspension](suspension.md#the-tractor-tyres-as-springs-and-a-swinging-axle).

### Synchroniser
A small cone on each collar of a manual gearbox that rubs on the gear first, like a brake, until
gear and shaft turn at the same speed. The [dog clutch](#dog-clutch) can then slide in without a
crunch.

See [Kinds of gearbox](gearbox-kinds.md#the-manual-gearbox).

## T

### Telemetry
Measurements a vehicle sends out about itself, such as its speed, its engine speed and its
temperatures. Every "out" signal is telemetry.

### Terrain
The painted ground of an island level, a surface shaped by a height map and painted in colours
that each stand for a kind of ground. Anything that is not painted terrain counts as dry asphalt.

### Thermostat
A valve that keeps the coolant inside the engine until it is warm, then lets it through to the
radiator. A pellet of wax inside it melts and expands as it heats, which opens the valve.

See [Fuel, coolant, battery and air](auxiliary.md).

### Torque
Turning force, how hard something twists, in newton-metres. An engine makes torque; a brake
resists it.

See [The engine](engine.md#torque-and-rpm).

### Torque converter
A fluid coupling between an engine and an automatic gearbox, in which oil thrown by one half turns
the other half. The car can sit still in gear with the engine running, and at low speed the
converter also multiplies the engine's torque.

See [Clutch and torque converter](coupling.md#the-torque-converter).

### Torque curve
A graph of the most torque an engine can give at each engine speed, with the accelerator pressed
all the way down.

See [The engine](engine.md#the-torque-curve).

### Torsen
A kind of [limited-slip differential](#limited-slip-differential) that uses worm gears. It can send
the slower side up to a fixed multiple of the faster side's torque, but only while torque goes
through it.

### Track
The distance between the left and right wheels of one axle.

### Traction control
A system that stops the driven wheels spinning when the driver presses too hard, by holding back
the engine or braking the spinning wheel.

It is called TC on cars and ASR on trucks. See
[ABS, traction and stability control](driver-aids.md).

### Trailer bus
The data link between a truck and its trailer.

See [ISO 11992](#iso-11992).

### Tread
The thick outer layer of rubber that touches the road, moulded into blocks separated by grooves.

See [Tyres and grip](tyres.md#the-contact-patch).

### Turning circle
The smallest circle a vehicle can drive at full lock.

### Tyre class
A kind of tyre made for one kind of use, such as all-season, summer, winter, studded winter or mud.
Each grips differently on each kind of ground.

See [Ground and tyre types](surfaces.md#tyre-classes).

## U

### Understeer
A car turning less sharply than the driver asked, because the front tyres slide first. The car
runs wide. Most road cars are built to understeer a little, because the natural reaction (slowing
down) cures it.

[Understeer and oversteer](understeer.md) explains it.

## V

### Variant
One vehicle model within a family in the simulator. The `sedan` and the `taxi` are variants of the
car family.

## W

### Weight transfer
Weight moving from one set of wheels to another as a vehicle speeds up, brakes or corners. The
total stays the same: braking moves weight onto the front wheels, and cornering onto the outside
ones.

See [Weight transfer and rollover](weight-transfer.md).

### Wheel speed
The speed the wheels would be doing if they rolled perfectly, their spin times their radius. When
the wheels spin, it reads higher than the [ground speed](#ground-speed).

On the tractor, `wheel_speed` is read from the rear axle.

### Wheel slip
How far the [wheel speed](#wheel-speed) runs ahead of the [ground speed](#ground-speed), as a
percentage. A tractor pulling a plough works with some slip; too much means it is digging in.

The tractor sends it as `wheel_slip`.

### Wheelbase
The distance between the front and rear axles.

## Y

### Yaw
A vehicle turning about its upright axis, as seen from above. The yaw rate is how fast it turns, in
radians per second.

It is sent as `yaw`.

## Units

| Unit | Means | Example |
| --- | --- | --- |
| m/s | metres per second | 10 m/s is 36 km/h |
| km/h | kilometres per hour | town speed is about 50 km/h |
| m/s² (shown `m/s^2`) | metres per second, per second: acceleration | 9.8 m/s² is 1 g |
| g | the pull of gravity, used as a unit of acceleration | a hard stop on a dry road is about 1 g |
| N, kN | newtons, kilonewtons: force | a 1.15 tonne car weighs about 11 kN |
| N·m | newton-metres: torque | 10 N pushed on a spanner 1 m long makes 10 N·m |
| rev/min (rpm) | revolutions per minute | a car idles at about 900 rpm |
| rad/s | radians per second: turning speed; 1 rad/s is about 57 degrees a second | |
| deg | degrees of angle | a right angle is 90 deg |
| bar, kPa | pressure; 1 bar is 100 kPa | a truck's air tank might hold 12 bar <!-- AIR_MAX_BAR --> |
| % | percent | pedal positions, loads and levels |
| ratio | a plain number with no unit | slip is shown as a ratio |
| 1/km | one over a distance: curvature, the tighter the turn the bigger | 100 1/km is a 10 m radius |
| degC | degrees Celsius | water boils at 100 degC |
| V, A | volts, amperes | a resting battery reads about 12.6 V <!-- BATTERY_RESTING --> |
| L/h | litres per hour: fuel use | |
| kg | kilograms: mass, also used for axle loads | |
| h | hours | engine hours |
