[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Glossary

<p class="lead">This page explains every technical word the guide uses, in alphabetical
order.</p>

The first sentence or two under each word is its short explanation (it also appears when you
hold the pointer over a dotted link). Anything after that adds detail (for example, the signal that carries it).

Units are at the end: [Units](#units).

## A

### ABS
Anti-lock brakes. When a hard brake would stop a wheel turning while the car still moves, ABS
lets the brake off just enough to keep the wheel turning. A turning tyre grips better than a
skidding one, and it can still steer.

A real system does this by releasing and applying the brake many times a second. It is standard on
road cars and trucks, but racing cars and tractors often have none. See
[ABS, traction and stability control](driver-aids.md).

### Accelerator
The pedal that asks the engine for more power. Also called the throttle pedal. In sloppyCAN it is
the `accel` signal, from 0 to 100 %.

### Ackermann steering
A way of angling the two front wheels so that the inside wheel turns more sharply than the
outside one in a corner. Both wheels then roll around the same centre point instead of fighting
each other. See [Steering and Ackermann](steering.md).

### Active standstill
A CVT tractor's way of holding still: its gearbox holds the wheels at a ratio of zero, so it
needs no brake to stay put on a slope.

### Aerodynamic drag
The push of the air against a moving vehicle, pointing backwards. It grows with the square of the
speed: twice as fast means four times the drag. Wind changes it, because what matters is the
speed through the air, not over the ground. See [Air and rolling resistance](resistance.md).

### Air brakes
Brakes worked by compressed air instead of oil, used on heavy trucks. A truck usually has two
air circuits, with tanks that an engine-driven compressor fills. If either tank falls too low, the
spring brakes come on by themselves.

### Air reservoir
A tank of compressed air on a truck. The pressure of the two circuits is sent as `air_primary` and
`air_secondary`, in bar. Each brake press uses some air; holding the pedal down
uses no more.

### All-speed governor
A way of controlling a diesel engine where the pedal (or hand throttle) chooses an engine speed,
and the engine adds or takes away fuel to hold that speed as the load changes. Tractors work
this way. Under load the speed sags a little, a few percent, which is called droop.

### Alternator
The generator the engine turns to charge the battery. While the engine runs, a car's battery
reads about 14 volts; with the engine off it reads its resting voltage, about 12.6 volts.

### AMT
Automated manual transmission. A gearbox built like a manual one, with a friction clutch, where a
computer works the clutch and picks the gears. They are common on semi trucks. Each shift
cuts the drive for a moment.

### Anti-dive
Suspension geometry that keeps the front of a car from dipping as much when it brakes. The angled
links push the body up in proportion to the braking force at the front tyres. The weight
still moves forward; only the springs squash less.

### Anti-roll bar
A springy bar joining the left and right wheels of one axle. When the body leans in a corner, the
bar twists and resists the lean. Stiffer bars at one end make that end lose grip sooner, which is
one way designers tune [understeer](#understeer) and [oversteer](#oversteer).

### Anti-squat
Suspension geometry that keeps the back of a car from sinking as much when it accelerates. It is
anti-dive's twin, at the driven rear wheels.

### Articulation
The angle between a towing vehicle and its trailer, seen from above. Zero when they are in a
straight line. Too much articulation is a [jackknife](#jackknife). See [Towing](towing.md).

### Articulated steering
Steering by bending the whole vehicle in the middle, as some large tractors and loaders do.

### ASR
Anti-slip regulation, the name for [traction control](#traction-control) on trucks.

### Auto hold
A setting that keeps the foot brake on whenever the vehicle stops in gear, until the accelerator
is pressed. See [Holding still](holding.md#auto-hold).

### Automatic gearbox
A gearbox that changes gear by itself, built from [planetary gear sets](#planetary-gear-set)
whose parts are held or released by clutches worked by oil pressure. It changes clutch to clutch,
so the drive never stops. Cars, vans, refuse trucks and fire trucks often
have one. See [Kinds of gearbox](gearbox-kinds.md).

### Axle
A pair of wheels across the vehicle, front or rear. Most road vehicles have two;
semi-trailers often have three, close together, called a [bogie](#bogie).

### Axle load
How much weight one axle carries, in kilograms. It changes as weight moves. Trucks and
tractors send their rear axle load as `axle_load`.

## B

### Ballast
Extra weight added to a tractor so its tyres can push harder before they spin. More weight on a
tyre means more grip.

### Bar
A unit of pressure, about the pressure of the air around us at sea level. The air tanks of a truck
hold around ten times that.
<!-- truck_telemetry.gd AIR_MAX_BAR 12 -->

### Battery
The vehicle's electrical store. Its voltage is sent as `battery`.

### Bias ratio
How unevenly a limited-slip or Torsen-type differential may split its torque: the slower wheel
may take up to this many times the faster one's. 1 is an open differential.

### Bicycle angle
A single steering angle that stands for the angles of the two front wheels.
Imagine the car as a bicycle with one front wheel in the middle: that wheel's angle is the bicycle
angle. Also called the mean steer angle.

### Bobtail
A semi tractor unit driving with no trailer.

### Bogie
A group of axles close together that share the load, like the three rear axles of a semi-trailer.

### Brake bias
How the braking force is shared between the front and rear wheels. Cars brake harder at the
front, because braking moves weight forward onto the front tyres.

### Brake fade
Brakes getting weaker as they get very hot. Past a temperature that
depends on the brake type, the same pedal gives less braking, and so does the handbrake when it
works the same brakes. See [Brakes](brakes.md).

### Brake temperature
How hot a vehicle's brakes are: braking heats them and the air cools them. The hottest brake is
sent as `brake_temp`, in degrees Celsius.

## C

### CAN bus
A two-wire network that the electronic parts of a vehicle use to send each other short messages.
CAN stands for Controller Area Network. Different industries use different message sets on it,
such as [J1939](#j1939) for trucks and [ISOBUS](#isobus) for farm machines.

### CANopen
A message set for CAN used in machines and vehicle bodies. For example, a garbage truck's body can use
CANopen on its own network, which reaches the truck's main network through a gateway.

### Centre differential
A [differential](#differential) between the front and rear axles of a four-wheel-drive vehicle,
so the two axles can turn at slightly different speeds in a corner.

### Centre of mass
The balance point of a vehicle, where all its weight seems to act. A high centre of mass makes a
vehicle lean more and tip over sooner.

### Clutch
A pair of friction plates that connect the engine to the gearbox. Pressed together, they turn
together. Slipping, they pass some turning force while turning at different speeds, which lets a
vehicle pull away smoothly. It is worked by a pedal, or by a controller in automated gearboxes. See
[Clutch and torque converter](coupling.md).

### Coefficient of friction
A number saying how grippy two surfaces are together: the most force they can pass along their
contact, divided by the force pressing them together. Written μ ([mu](#mu)).

### Combined slip
A tyre doing two things at once: pushing along the road (driving or braking) and pushing sideways
(cornering). Its grip has to be shared between the two, so hard braking leaves less grip for
turning. See [Slip and the grip curve](slip.md#sharing-grip-between-braking-and-turning).

### Compliance steer
A small change in a wheel's angle caused by the rubber bushes in the suspension bending under
sideways force. Designers can use it to steady the car.

### Contact patch
The small area where a tyre touches the road, about the size of a hand on a car. Every force
between the vehicle and the ground passes through the contact patches.

### Contract
The single list of every signal Carlito and sloppyCAN exchange: each signal's name, direction,
unit and range. Both programs read it, so they always agree on what a message means.

### Coolant
The liquid that carries heat away from an engine. Its temperature is sent as
`coolant`, in degrees Celsius: about 90 °C once the engine is warm, and warmer under load.

### Cornering stiffness
How much sideways force a tyre makes for each degree of slip angle, before it reaches its peak.
A heavier load makes more force, but less per kilogram of load.

### Crank
The engine's crankshaft, the part that turns. Its speed is the engine speed, in
[rpm](#rpm). It is heavy, so it takes
time to speed up and slow down.

### Creep
The slow forward movement of a car with an automatic gearbox when the brake is released and the
accelerator is not pressed. The [torque converter](#torque-converter) passes a little of the
idling engine's turning force to the wheels.

### Crosswind
Wind blowing across a vehicle's path. It pushes the vehicle sideways and turns its nose a little.

### CVT
Continuously variable transmission: a gearbox with no fixed gears, whose ratio changes smoothly.
On a tractor with one, the driver's pedal asks for a ground speed and the gearbox finds the
ratio.

## D

### Damper
The part of the suspension that slows the springs down so the body does not keep bouncing. Also
called a shock absorber.

### Diff lock
A switch that ties both wheels of an axle together so they must turn at the same speed. It stops
one wheel spinning uselessly on mud while the other stands still. Tractors have one on their rear
axle (`diff_lock`).

### Differential
The gears in the middle of an axle that let the left and right wheels turn at different speeds.
In a corner the outside wheel travels further than the inside one, so it must turn faster. See
[Differentials and four-wheel drive](differentials.md).

### Dog clutch
A collar that slides along a shaft, with stubby teeth on its side (the dogs). Slid against a gear,
its dogs lock the gear to the shaft. See [Kinds of gearbox](gearbox-kinds.md).

### Downforce
Air pushing a car down onto the road, made by wings and the body's shape. It grows with speed
squared and gives the tyres more grip. It is mostly used by racing cars.

### Draft
The pull needed to drag a plough or harrow through the soil. It depends on depth, soil and
speed. A tractor sends it as `draft_force`.

### Drag area
One number for how much air drag a vehicle makes: the area of its front times how smoothly the
air flows round it (its drag coefficient). For example, 0.65 m² for a saloon.

### Drawbar
A rigid bar on the front of a trailer, whose eye drops over a single pin at the back of a
tractor. It can only pull; it carries little of the trailer's weight.

### Drive slip
Slip while driving: the tyre's surface turns faster than the ground passes under it.

### Drivetrain
Everything between the engine and the wheels: clutch or converter, gearbox, differentials and
shafts.

### Droop
How much a governed engine's speed falls below its setting under full load, as a share of the
setting. On a tractor, it is a few percent.

### Dual-clutch gearbox
Two gearboxes in one case, one for the odd gears and one for the even gears, each with its own
clutch. The next gear waits on the other half, so a change is one clutch opening as the other
closes. See [Kinds of gearbox](gearbox-kinds.md).

## E

### Engine braking
The slowing force of the engine when the driver lifts off the accelerator in gear. The engine's
own friction turns against the wheels.

### Engine load
How hard the engine is working: the torque it is giving, as a percentage of the most it can give
at any speed. Trucks and tractors send it as `engine_load`.

### ESC
Electronic stability control: see [stability control](#stability-control).

## F

### Fifth wheel
The large, flat coupling plate on the back of a truck tractor unit. The semi-trailer's
[kingpin](#kingpin) locks into it. A good share of the trailer's weight rests on it.

### Final drive
The last gear reduction before the wheels, in the axle. Together with the gearbox ratio it sets
how many times the engine turns for each turn of the wheels.

### Friction ellipse
The limit on a tyre's total force, drawn as an oval: along the road on one axis, sideways on the
other. A tyre can use all its grip for braking, or all for turning, or a mix, but the mix never
goes outside the oval.

### Fuel rate
How fast the engine burns fuel, in litres per hour (`fuel_rate`). It depends on
the engine's turning force and speed.

## G

### Gear
A wheel with teeth around its edge. Two gears whose teeth fit together turn each other; a small
one turns a big one more slowly but with more [torque](#torque). See
[Gearbox and shifting](gearbox.md#two-gears-trading-speed-for-strength).

### Gear ratio
How many times the engine turns for each turn of the gearbox output. A low gear has a large
ratio: the engine turns fast and the wheels slowly, with strong pull.

### Gear byte
The number sloppyCAN uses to choose a gear: 0 is neutral, 1 to 24 are drive gears, 254 is park and
255 is reverse.

### Governor
A control that limits speed. A road-speed governor (vans, trucks) fades the fuel as the vehicle
nears its set speed. An engine governor holds an engine speed; see
[all-speed governor](#all-speed-governor).

### GPS
Satellite positioning. A receiver works out its latitude and longitude (`lat`, `lon`) from
satellite signals.

### Grade
How steep a slope is, as a percentage: rise over distance. A 10 % grade climbs 10 m for every
100 m along the flat.

### Grip
How much force a tyre can pass to the road before it slides, in newtons: the
[coefficient of friction](#coefficient-of-friction) × the force pressing the tyre down. It depends
on the tyre, the ground and how hard the tyre is pressed down.

### Grip curve
A graph of how much force a tyre makes at each amount of [slip](#slip), as a share of its
[grip](#grip). The force rises quickly to a peak at a small slip, then falls a little as the tyre
slides more.

### Ground speed
The vehicle's true speed over the ground, whatever the wheels are doing. Tractors send it
as `ground_speed`, beside the wheel-based [wheel speed](#wheel-speed).

### Gust
A short rise in the wind's strength.

## H

### Handbrake
The parking brake, worked by a lever. It usually brakes only the rear wheels, and can
lock them, which is what lets a car slide its rear round in a handbrake turn. It often works the
same rear brakes as the pedal, so when they are hot it fades with them.

### Hand throttle
A lever that sets an engine speed and stays where it is put, so the driver's foot is free. Tractors
have one (`hand_throttle`). See [The engine](engine.md).

### Heading
The compass direction the vehicle's nose points: 0 is north, 90 east, 180 south, 270 west
(`heading`).

### Hill-start assist
A brake hold that stops a car rolling back when the driver moves a foot from the brake to the
accelerator on a slope. It lets go as soon as the engine pulls hard enough to hold the car, or
after a short time. See [Holding still](holding.md).

### Hitch
The coupling at the back of a tractor. The three-point hitch carries implements on two lower arms
and one top link and can raise and lower them (`hitch_pos`).

### Hour meter
A counter of how long the engine has run, in hours (`engine_hours`). Machines that work standing
still, like tractors, are serviced by hours rather than distance.

### Hydraulic remote
A tractor outlet that sends oil under pressure to a trailer or implement, to work a ram. Also
called an SCV (selective control valve). For example, it can open a spreader's hopper gate or
tip a farm trailer (`scv_flow`).

### Hydrostatic drive
A drive through oil: a pump turned by the engine pushes oil to a motor that turns the output. Its
speed can be set to anything, including zero and backwards. A tractor's
[CVT](#cvt) uses one for part of its power. See [Kinds of gearbox](gearbox-kinds.md).

## I

### Idle
The slowest speed an engine runs at by itself, with no pedal pressed.

### Implement
A machine a tractor carries or pulls: a plough, a harrow, a mower, a spreader.

### Inertia
An object's resistance to changing how it moves. A heavy vehicle takes more force to speed up,
slow down or turn. Spinning parts, like wheels and the engine's crank, also have inertia.

### ISO 11992
The message set for the data link between a truck and its trailer, carried on two pins of the
trailer's electrical connector. It covers brakes and running gear only.

### ISOBUS
The message set farm tractors and implements use to talk to each other (ISO 11783). It is built
on [J1939](#j1939).

## J

### J1939
The message set heavy trucks use on their CAN bus. Parts of a tractor's network
use it too.

### Jackknife
A towing vehicle and its trailer folding towards each other until they touch, like a pocket knife
closing. See [Towing](towing.md#jackknife).

## K

### Kickdown
Pressing the accelerator most of the way down in an automatic, which makes the gearbox drop to a
lower gear at once for more pull.

### Kingpin
The steel pin under the front of a semi-trailer that locks into the tractor unit's
[fifth wheel](#fifth-wheel).

## L

### Lateral acceleration
How hard a vehicle is being pushed sideways, usually in a corner (`accLat`). Measured in metres
per second squared; 9.8 of them is one g, the pull of gravity.

### Limited-slip differential
A differential that lets the two wheels turn at different speeds, but sends more turning force to
the slower wheel when one starts to spin. A Torsen is one kind.

### Load sensitivity
The way a tyre's grip, per kilogram it carries, falls as it carries more. A tyre pressed twice as
hard grips more in total, but not twice as much.

### Lock
How far the steering can turn the wheels, in degrees. Full lock is as far as it goes.

### Lock-up clutch
A clutch inside a torque converter that joins its two halves solidly once the car is moving, so
no power is lost to slip.

## M

### Manual gearbox
A gearbox whose gears the driver chooses with a lever and a clutch pedal. See
[Kinds of gearbox](gearbox-kinds.md).

### MFWD
Mechanical front-wheel drive: a tractor's switchable drive to its front axle (`fwd_drive`). With
it on, all four wheels pull.

### Motoring
An engine being turned by the wheels instead of turning them, with no fuel. Its friction then
slows the vehicle: this is [engine braking](#engine-braking).

### Mu
The Greek letter μ, the usual symbol for the [coefficient of friction](#coefficient-of-friction):
how much grip a surface gives for each newton pressing down. Dry asphalt gives a car tyre about
1; ice about a tenth of that.
<!-- GroundDriveSpec mu_long default 1.05; surface.gd REF_GRIP Ice 0.12 -->

## N

### Newton
The unit of force. One newton is about the weight of a small apple. A thousand newtons is a
kilonewton (kN).

## O

### Odometer
The distance counter, in kilometres (`odo`). It adds up distance driven in either direction and
never counts down.

### Open differential
A plain [differential](#differential) that always splits the turning force equally. If one wheel
loses grip, the other gets no more than the slipping one, so the vehicle can be stuck with one
wheel spinning.

### Overrun
The engine being driven by the wheels, as when coasting downhill in gear.

### Oversteer
A car turning more sharply than the driver asked, because the rear tyres slide first. The back
swings out.

[Understeer and oversteer](understeer.md) explains it.

## P

### Park pawl
A small catch inside an automatic gearbox that locks it in P. It only drops in below walking pace.

### Pedal map
The rule that turns the accelerator's position into an amount of fuel or a turning-force request.
Petrol cars, diesel trucks and tractors often use different rules.

### Pitch
The nose of a vehicle tipping up or down. A car pitches forward when it brakes.

### Planetary gear set
A sun gear in the middle, planet gears around it on a carrier, and a ring gear around the outside
with its teeth facing inwards. Holding one part still and driving another gives a different ratio
for each choice. Automatic gearboxes are built from them. See [Kinds of gearbox](gearbox-kinds.md).

### Power
How fast work is done, in watts (W) or kilowatts (kW). An engine's power is its torque times how
fast it turns, so the same torque gives more power at a higher rpm. See [The engine](engine.md).

### Powershift
A tractor gearbox that changes gear under load without the driver pressing a clutch, using
several clutches inside. Sixteen forward gears is not unusual.

### PTO
Power take-off: a spinning shaft at the back of a tractor that drives an implement's moving parts.
It runs at 540 or 1000 turns a minute (`pto`, `pto_mode`, `pto_rpm`). Its power is a
load on the engine.
<!-- contract pto_mode enum 540 / 1000 -->

## R

### Redline
The highest safe engine speed. The [rev limiter](#rev-limiter) stops the engine going past it.

### Retarder
An extra brake inside a truck's driveline that slows it without wearing the wheel brakes. Useful
on long descents. Many trucks have one (`retarder`, `retarder_state`).

### Rev limiter
A control that cuts the fuel when the engine reaches its redline.

### Ride frequency
How many times a second a vehicle's body bounces up and down on its springs after a bump. Softer
springs or a heavier load give a lower frequency and a gentler ride. A saloon might bounce
about 1.4 times a second.

### Roll
A vehicle leaning to one side about its length, as a car body leans outwards in a corner.

### Roll steer
A small change in the wheels' angle caused by the body leaning in a corner, from the shape of the
suspension links. On road cars it is usually designed to give steadier handling
([understeer](#understeer)).

### Rolling resistance
The small force that slows a rolling tyre, from the rubber flexing and the ground giving way. It
is proportional to the load on the tyre. Soft ground like mud or sand adds much more.

### Roll stability control
The part of stability control that brakes a truck and its trailer before the sideways force could
tip them over. Semi-trailers can have their own, which brakes the trailer by itself using its own
sensors.

### Rollover threshold
The sideways acceleration at which a vehicle tips over rather than sliding. A tall, narrow
vehicle tips sooner. See [Weight transfer and rollover](weight-transfer.md).

### Rpm
Revolutions per minute: how many full turns a shaft makes in a minute. A car engine
idles at about 900 rpm.

## S

### Semi-trailer
A trailer with wheels only at the back. Its front rests on the tractor unit's
[fifth wheel](#fifth-wheel).

### Sequential gearbox
A racing gearbox whose gears can only be taken in order, one up or one down. Each change is
very quick, often with a short ignition cut.

### Shift policy
The rules an automatic gearbox uses to decide when to change gear: from the road speed, the
pedal, and whether the vehicle is climbing. See [Gearbox and shifting](gearbox.md).

### Signal
One named value passed between Carlito and sloppyCAN, such as the engine speed `rpm` or the brake
pedal `brake`. "Out" signals go from the simulator to sloppyCAN; "in" signals come the other way.

### Slip
The difference between how a tyre is moving and how it would move if it rolled perfectly. A tyre
needs a little slip to make any force at all. See [slip ratio](#slip-ratio) and
[slip angle](#slip-angle).

### Slip angle
The angle between where a tyre points and where it is actually travelling. A cornering tyre
always travels a little wide of where it points, and that small angle is what makes the sideways
force.

### Slip ratio
How much faster or slower a tyre's surface turns than the ground moves under it, as a fraction of
the road speed. 0 is perfect rolling, a positive value is spinning, a negative value is braking,
and -1 is a locked wheel.

### sloppyCAN
The companion program Carlito talks to: a CAN bus simulator and analysis tool that runs in a web
browser. It turns most of the simulator's signals into CAN traffic and can send commands back.

### Spoiler
A lip or small flap at the back of a car's body that spoils the airflow there, to cancel the
slight lift a body makes at speed. Often confused with a wing, which pushes the car down.

### Spring brake
A truck parking brake held off by air pressure and applied by a strong spring. If the air runs
out, the spring puts the brake on by itself, so a truck that loses its air stops.

### Stability control
A system that brakes one wheel by itself to stop a car spinning or sliding wide. Often called ESC.
On trucks it also brakes the whole rig before it would tip over.

### Stall
An engine stalls when the load slows it until it stops.

### Stall speed
The engine speed a car with a [torque converter](#torque-converter) reaches when it is held still
on the brakes with the accelerator fully pressed. For example, 2400 rpm.

### Static friction
The grip that holds a still tyre in place, before it starts to slide. A parked car is
held by the small springy give of the rubber in each tyre's contact patch.

### Steering taper
A simplification used in driving simulators: the steering lock gets smaller as speed rises, so
that full steering at motorway speed does not throw the car off the road. A real steering wheel
has no such limit.

### Surface
The kind of ground under a tyre: asphalt, wet road, airfield pad, gravel, dirt, grass, sand, rock,
mud, field soil, snow or ice. Each gives a different grip and rolling resistance. See
[Ground and tyre types](surfaces.md).

### Suspension
The springs, dampers and links between the wheels and the body. They let the wheels follow bumps
and keep the tyres pressed onto the road. See [Suspension](suspension.md).

### Swinging front axle
A front axle built as one beam on a single pivot in the middle, so one wheel can rise as the other
drops. Farm tractors use it, with a stop on each side to limit the swing.

### Synchroniser
A small cone on each collar of a manual gearbox that rubs on the gear first, like a brake, until
gear and shaft turn at the same speed, so the [dog clutch](#dog-clutch) can slide in without
crunching. See [Kinds of gearbox](gearbox-kinds.md).

## T

### Telemetry
Measurements a vehicle sends out about itself: speed, engine speed, temperatures. Every "out"
signal is telemetry.

### Terrain
The painted ground of an island level: a surface shaped by a height map, painted in colours that
each stand for a kind of ground. Anything that is not painted terrain counts as dry asphalt.

### Torque
Turning force: how hard something twists, in newton-metres. An engine makes torque; a brake
resists it.

### Torque converter
A fluid coupling between an engine and an automatic gearbox. Oil thrown by one half turns the
other half, so the car can sit still in gear with the engine running. At low speed it also
multiplies the engine's torque. See [Clutch and torque converter](coupling.md).

### Torque curve
A graph of how much torque an engine makes at each engine speed. See [The engine](engine.md).

### Torsen
A kind of [limited-slip differential](#limited-slip-differential) using special gears. It can send
the slower side up to a fixed multiple of the faster side's torque.

### Track
The distance between the left and right wheels of one axle.

### Traction control
A system that stops the driven wheels spinning when the driver presses too hard, by holding back
the drive or braking the spinning wheel. Called TC on cars and ASR on trucks. See
[ABS, traction and stability control](driver-aids.md).

### Trailer bus
The data link between a truck and its trailer. See [ISO 11992](#iso-11992).

### Tread
The thick outer layer of rubber that touches the road, moulded into blocks separated by grooves.
See [Tyres and grip](tyres.md#the-contact-patch).

### Turning circle
The smallest circle a vehicle can drive at full lock.

### Tyre class
A type of tyre tread: all-season, summer, winter, studded winter, mud, and others. Each grips
differently on each surface. See
[Ground and tyre types](surfaces.md).

## U

### Understeer
A car turning less sharply than the driver asked, because the front tyres slide first. The car
runs wide. Most road cars are designed to understeer a little, because it is easier to control.

[Understeer and oversteer](understeer.md) explains it.

## V

### Variant
One vehicle model within a family. The `sedan` and the `taxi` are variants of the car family.

## W

### Weight transfer
Weight moving from one set of wheels to another as a vehicle speeds up, brakes or corners. Braking
moves weight to the front; cornering moves it to the outside wheels. See
[Weight transfer and rollover](weight-transfer.md).

### Wheel speed
The speed the wheels would be doing if they rolled perfectly: their spin times their radius. On
the tractor, `wheel_speed` is read from the rear axle. When the wheels spin, it reads higher than
the [ground speed](#ground-speed).

### Wheel slip
On the tractor, how far the [wheel speed](#wheel-speed) runs ahead of the
[ground speed](#ground-speed), as a percentage (`wheel_slip`). A tractor pulling a plough works
with some slip; too much means it is digging in.

### Wheelbase
The distance between the front and rear axles.

## Y

### Yaw
A vehicle turning about its upright axis, as seen from above. The yaw rate (`yaw`) is how fast it
turns, in radians per second.

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
