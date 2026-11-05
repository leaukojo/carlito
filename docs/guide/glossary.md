# Glossary

Every technical word the guide uses, in alphabetical order. The first sentence or two under each
word is its short explanation (it also appears when you hold the pointer over a dotted link).
Anything after that adds detail about how the game uses it.

Units are at the end: [Units](#units).

## A

### ABS
Anti-lock brakes. When a hard brake would stop a wheel turning while the car still moves, ABS
lets the brake off just enough to keep the wheel turning. A turning tyre grips better than a
skidding one, and it can still steer.

In the game ABS is ideal: it knows the true road speed and holds each wheel at the slip where the
tyre brakes hardest, without the pulsing a real system has. Every car, van and truck has it
except the two racing cars, and so do the trailers; the tractor has none. LAB ▸ ANTI-LOCK BRAKES can switch it off.

### Accelerator
The pedal that asks the engine for more power. Also called the throttle pedal. In sloppyCAN it is
the `accel` signal, from 0 to 100 %.

### Ackermann steering
A way of angling the two front wheels so that the inside wheel turns more sharply than the
outside one in a corner. Both wheels then roll around the same centre point instead of fighting
each other. See [Steering and Ackermann](steering.md).

### Active standstill
The CVT tractor's way of holding still: its gearbox holds the wheels at a ratio of zero, so it
needs no brake to stay put on a slope.

### Aerodynamic drag
The push of the air against a moving vehicle, pointing backwards. It grows with the square of the
speed: twice as fast means four times the drag. Wind changes it, because what matters is the
speed through the air, not over the ground.

### Air brakes
Brakes worked by compressed air instead of oil, used on heavy trucks. The game's trucks keep two
air tanks (circuits) that an engine-driven compressor fills. If either tank falls too low, the
spring brakes come on by themselves.

### Air reservoir
A tank of compressed air on a truck. The game publishes the pressure of the two circuits as
`air_primary` and `air_secondary`, in bar. Each brake press uses some air; holding the pedal down
uses no more.

### All-speed governor
A way of controlling a diesel engine where the pedal (or hand throttle) chooses an engine speed,
and the engine adds or takes away fuel to hold that speed as the load changes. The tractor works
this way. Under load the speed sags a little, a few percent, which is called droop.

### Alternator
The generator the engine turns to charge the battery. In the game, while the engine runs, the
battery reads about 14 volts, sagging a little under load; with the engine off it reads its
resting voltage, about 12.6 volts.
<!-- vehicle_telemetry.gd BATTERY_CHARGING 14.2, BATTERY_RESTING 12.6 -->

### AMT
Automated manual transmission. A gearbox built like a manual one, with a friction clutch, where a
computer works the clutch and picks the gears. The two semi tractor units have one. Each shift
cuts the drive for a moment.

### Angle of attack
The angle between a wing and the air flowing past it. A larger angle makes more lift, up to a
point. In the game the plane's lift rises with its angle of attack, up to a cap.

### Anti-dive
Suspension geometry that keeps the front of a car from dipping as much when it brakes. In the game
the links push the body up in proportion to the braking force at the front tyres. The weight
still moves forward; only the springs squash less.

### Anti-roll bar
A springy bar joining the left and right wheels of one axle. When the body leans in a corner, the
bar twists and resists the lean. Stiffer bars at one end make that end lose grip sooner, which is
one way designers tune [understeer](#understeer) and [oversteer](#oversteer).

### Anti-squat
Suspension geometry that keeps the back of a car from sinking as much when it accelerates. It is
anti-dive's twin, at the driven rear wheels.

### Apparent wind
The wind a moving boat feels: the true wind combined with the wind of its own motion. A boat
sailing into a breeze feels more wind than a boat standing still. The boat publishes it as `awa`
(its angle) and `aws` (its speed).

### Arming
Switching a drone's motors on so they can spin. The drone refuses to arm if a pre-arm check fails:
the craft is tilted, the battery is low, a motor or the attitude sensor is missing from the bus,
the climb stick is not centred, a failsafe is active, or the chosen flight mode needs GPS and
there is no fix.

### Articulation
The angle between a towing vehicle and its trailer, seen from above. Zero when they are in a
straight line. Too much articulation is a [jackknife](#jackknife).

### Articulated steering
Steering by bending the whole vehicle in the middle, as some large tractors and loaders do. The
game does not model it: every wheeled vehicle steers with its front wheels.

### ASR
Anti-slip regulation, the name for [traction control](#traction-control) on trucks.

### Autopilot
A controller that steers for the driver. The boat's autopilot holds a compass heading (HEADING
HOLD). Moving the helm takes the rudder back; letting go holds the new heading.

### Axle
A pair of wheels across the vehicle, front or rear. Most of the game's road vehicles have two;
the semi-trailers have three, close together, called a [bogie](#bogie).

### Axle load
How much weight one axle carries, in kilograms. The truck and the tractor publish their rear axle
load as `axle_load`, read off the springs, so it changes as weight moves.

## B

### Ballast
Extra weight added to a tractor so its tyres can push harder before they spin. More weight on a
tyre means more grip.

### Bar
A unit of pressure, about the pressure of the air around us at sea level. The game's truck air
tanks fill up to 12 bar; the train's brake pipe sits at about 5.
<!-- truck_telemetry.gd AIR_MAX_BAR 12; train.gd PIPE_APPLY_RANGE, 5 -> 2 bar -->

### Battery
The vehicle's electrical store. Every vehicle publishes a battery voltage, from a simple labelled
model. The drone has its own model of a flight battery pack, whose voltage falls as it drains and
as it delivers current.

### Bicycle angle
The single steering angle the game works with before splitting it between the two front wheels.
Imagine the car as a bicycle with one front wheel in the middle: that wheel's angle is the bicycle
angle. Also called the mean steer angle.

### Bogie
A group of axles close together that share the load, like the three rear axles of a semi-trailer.

### Brake bias
How the braking force is shared between the front and rear wheels. Cars brake harder at the
front, because braking moves weight forward onto the front tyres.

### Brake fade
Brakes getting weaker as they get very hot. In the game each brake has one temperature; past a
point that depends on the brake type, the same pedal gives less braking.

### Brake pipe
On a train, the air pipe that runs the length of the train and controls every carriage's brakes.
Letting air out of it applies the brakes. The game publishes its pressure as `brake_pipe`, in bar:
about 5 released, falling towards 2 at full brake.
<!-- train.gd PIPE_APPLY_RANGE 3.0, 5 -> 2 bar -->

### Brake temperature
How hot a vehicle's brakes are. The game publishes the hottest brake as `brake_temp`, in degrees
Celsius, from a simple model heated by braking and cooled by the air.

### Buoyancy
The upward push of water on a floating object. A boat floats when the push equals its weight. The
game measures how deep four points of the hull sit in the water and pushes each one up.

## C

### CAN bus
A two-wire network that the electronic parts of a vehicle use to send each other short messages.
CAN stands for Controller Area Network. Different industries use different message sets on it,
such as [J1939](#j1939) for trucks and [ISOBUS](#isobus) for farm machines.

### CANaerospace
A message set for CAN used in aircraft. The plane's own signals (elevator, flaps, altitude,
climb rate) borrow its names.

### CANopen
A message set for CAN used in machines and vehicle bodies. The garbage truck's lifting arm talks
CANopen on its own network, which reaches the truck's main network through a gateway.

### Catenary
The overhead power wire above an electric railway. The train collects power from it through the
[pantograph](#pantograph). The game publishes the wire's voltage as `catenary_volts`; it sags as
the motors draw more current.

### Centre differential
A [differential](#differential) between the front and rear axles of a four-wheel-drive vehicle,
so the two axles can turn at slightly different speeds in a corner.

### Centre of mass
The balance point of a vehicle, where all its weight seems to act. A high centre of mass makes a
vehicle lean more and tip over sooner.

### Clutch
A pair of friction plates that connect the engine to the gearbox. Pressed together, they turn
together. Slipping, they pass some turning force while turning at different speeds, which lets a
vehicle pull away smoothly. In the game a controller works it; there is no clutch pedal. See
[Clutch and torque converter](coupling.md).

### Coefficient of friction
A number saying how grippy two surfaces are together: the most force they can pass along their
contact, divided by the force pressing them together. Written μ ([mu](#mu)).

### Combined slip
A tyre doing two things at once: pushing along the road (driving or braking) and pushing sideways
(cornering). Its grip has to be shared between the two, so hard braking leaves less grip for
turning. See [Tyres and slip](tyres.md).

### Compliance steer
A small change in a wheel's angle caused by the rubber bushes in the suspension bending under
sideways force. In the game only the front-drive saloons' rear axle has it, turning the rear
wheels a fraction of a degree in the direction that steadies the car.

### Contact patch
The small area where a tyre touches the road, about the size of a hand on a car. Every force
between the vehicle and the ground passes through the contact patches.

### Contract
The single list of every signal Carlito and sloppyCAN exchange: each signal's name, direction,
unit and range. Both programs read it, so they always agree on what a message means.

### Coolant
The liquid that carries heat away from an engine. The game publishes its temperature as
`coolant`, in degrees Celsius, from a simple labelled model: cold when the engine is off, about
90 °C running, warmer under load.
<!-- vehicle_telemetry.gd COOLANT_OPERATING 90 -->

### Cornering stiffness
How much sideways force a tyre makes for each degree of slip angle, before it reaches its peak.
A heavier load makes more force, but less per kilogram of load.

### Coupler
The joint between two railway carriages. In the game each coupler is a stiff spring with a little
free play. The train publishes the force in the first one as `coupler_force`, in kilonewtons:
positive when pulling, negative when pushing.

### Crank
The engine's crankshaft, the part that turns. Its speed is the engine speed, in
[rpm](#rpm). In the game the car, truck and tractor engines have a crank with real weight that
speeds up and slows down.

### Creep
The slow forward movement of a car with an automatic gearbox when the brake is released and the
accelerator is not pressed. The [torque converter](#torque-converter) passes a little of the
idling engine's turning force to the wheels.

### Crosswind
Wind blowing across a vehicle's path. It pushes the vehicle sideways and turns its nose a little.
CONDITIONS can set the wind's strength and direction.

### Current
Moving water, such as a tide. A boat in a current moves over the ground differently from how it
moves through the water. In the game only the boat feels it.

### CVT
Continuously variable transmission: a gearbox with no fixed gears, whose ratio changes smoothly.
The `tractor-cvt` has one. The driver's pedal asks for a ground speed and the gearbox finds the
ratio.

## D

### Damper
The part of the suspension that slows the springs down so the body does not keep bouncing. Also
called a shock absorber.

### Davis equation
A railway formula for a train's running resistance: a constant part, a part that grows with speed
(bearings and flanges), and a part that grows with speed squared (air). The game's train uses it.

### Diff lock
A switch that ties both wheels of an axle together so they must turn at the same speed. It stops
one wheel spinning uselessly on mud while the other stands still. The tractor has one on its rear
axle (`diff_lock`).

### Differential
The gears in the middle of an axle that let the left and right wheels turn at different speeds.
In a corner the outside wheel travels further than the inside one, so it must turn faster.

### Downforce
Air pushing a car down onto the road, made by wings and the body's shape. It grows with speed
squared and gives the tyres more grip. Only the two racing cars have it in the game.

### Draft
The pull needed to drag a plough or harrow through the soil. In the game it is a real force at
the tractor's hitch, depending on depth, soil and speed. The tractor publishes it as
`draft_force`.

### Drawbar
A rigid bar at the back of a tractor that a trailer hooks onto with a single pin. It can only
pull; it carries little of the trailer's weight.

### Drive slip
Slip while driving: the tyre's surface turns faster than the ground passes under it.

### Drivetrain
Everything between the engine and the wheels: clutch or converter, gearbox, differentials and
shafts.

### DroneCAN
A message set for CAN used on drones. Each part of the game's drone (each motor controller, the
GPS, the power module, the attitude sensor) is its own node on the bus and sends its own messages.

### Droop
How much a governed engine's speed falls below its setting under full load, as a share of the
setting. The tractor's governor droops about 7 %.
<!-- tractor-kenney_spec.tres governor_droop 0.07 -->

## E

### Electronic speed controller
On a drone, the small controller that drives one motor. The game's drone has four, each reporting
its rpm, current and temperature. Not the same as ESC meaning [stability control](#stability-control).

### Engine braking
The slowing force of the engine when the driver lifts off the accelerator in gear. The engine's
own friction turns against the wheels.

### Engine load
How hard the engine is working: the torque it is giving, as a percentage of the most it can give
at any speed. The truck and tractor publish it as `engine_load`.

### ESC
Two meanings. On cars and trucks: electronic [stability control](#stability-control). On the
drone: an [electronic speed controller](#electronic-speed-controller), one per motor.

## F

### Failsafe
What a drone does by itself when something goes wrong: low battery, lost GPS, crossing its fence,
or a motor failure. The game publishes the active one as `failsafe`.

### Fifth wheel
The large, flat coupling plate on the back of a truck tractor unit. The semi-trailer's
[kingpin](#kingpin) locks into it. A good share of the trailer's weight rests on it.

### Final drive
The last gear reduction before the wheels, in the axle. Together with the gearbox ratio it sets
how many times the engine turns for each turn of the wheels.

### Flaps
Hinged panels on a wing that come down to make more lift at low speed, at the cost of more drag.
The plane's `flaps` signal asks for them; `flaps_actual` reports where they are.

### Friction ellipse
The limit on a tyre's total force, drawn as an oval: along the road on one axis, sideways on the
other. A tyre can use all its grip for braking, or all for turning, or a mix, but the mix never
goes outside the oval.

### Fuel rate
How fast the engine burns fuel, in litres per hour (`fuel_rate`). On the car, truck and tractor
the game works it out from the engine's actual turning force and speed; the boat uses a simpler
labelled model that follows its throttle.
<!-- VehicleTelemetry.fuel_rate_lph on a wheel-driving crank; BoatTelemetry.fuel_rate_model on the boat -->



## G

### Gear ratio
How many times the engine turns for each turn of the gearbox output. A low gear has a large
ratio: the engine turns fast and the wheels slowly, with strong pull.

### Gear byte
The number sloppyCAN uses to choose a gear: 0 is neutral, 1 to 24 are drive gears, 254 is park and
255 is reverse.

### Geofence
An invisible boundary around a drone's home point. The game's drone may fly up to 400 m away and
120 m up; crossing either makes it fly home by itself.
<!-- drone_modes.gd GEOFENCE_RADIUS 400, GEOFENCE_CEILING 120 -->

### Governor
A control that limits speed. A road-speed governor (vans, trucks) fades the fuel as the vehicle
nears its set speed. An engine governor holds an engine speed; see
[all-speed governor](#all-speed-governor).

### GPS
Satellite positioning. The game turns each vehicle's position in the world into a latitude and
longitude (`lat`, `lon`), as if the world sat near Paris. The drone also models how many
satellites it can see.

### Grade
How steep a slope is, as a percentage: rise over distance. A 10 % grade climbs 10 m for every
100 m along the flat. The train publishes the grade under it as `grade`.

### Grip
How much force a tyre can pass to the road before it slides. It depends on the tyre, the ground
and how hard the tyre is pressed down.

### Grip curve
A graph of how much grip a tyre gives at each amount of [slip](#slip). Grip rises quickly to a
peak at a small slip, then falls a little as the tyre slides more.

### Ground speed
The vehicle's true speed over the ground, whatever the wheels are doing. The tractor publishes it
as `ground_speed`, beside the wheel-based [wheel speed](#wheel-speed).

## H

### Handbrake
The parking brake, worked by a lever. In the game it brakes only the rear wheels, hard enough to
lock them, which is what lets a car slide its rear round in a handbrake turn.

### Hand throttle
A lever that sets an engine speed and stays where it is put, so the driver's foot is free. The
tractor has one (keys **-** and **=**, or sloppyCAN's `hand_throttle`). See [The engine](engine.md).

### Heading
The compass direction the vehicle's nose points: 0 is north, 90 east, 180 south, 270 west
(`heading`).

### Heel
A boat leaning to one side, from turning or from wind on its hull or sail.

### Hill-start assist
A brake hold that stops a car rolling back when the driver moves a foot from the brake to the
accelerator on a slope. It lets go as soon as the engine pulls hard enough to hold the car, or
after a short time.

### Hitch
The coupling at the back of a tractor. The three-point hitch carries implements on two lower arms
and one top link and can raise and lower them (`hitch_pos`).

### Hour meter
A counter of how long the engine has run, in hours (`engine_hours`). Machines that work standing
still, like tractors and boats, are serviced by hours rather than distance.

### Hydraulic remote
A tractor outlet that sends oil under pressure to a trailer or implement, to work a ram. Also
called an SCV (selective control valve). In the game it opens the spreader's hopper gate and
tips the farm trailer (`scv_flow`).

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
The message set heavy trucks use on their CAN bus. The game's trucks, and parts of the tractor,
use its signal names.

### Jackknife
A towing vehicle and its trailer folding towards each other until they touch, like a pocket knife
closing. In the game the coupling has a stop at the angle where the trailer would hit the cab.

## K

### Keel
The fin under a sailing boat. It resists the boat sliding sideways, so the sail's push can drive
it forward.

### Kickdown
Pressing the accelerator most of the way down in an automatic, which makes the gearbox drop to a
lower gear at once for more pull. The tractor and the racing cars have none.

### Kingpin
The steel pin under the front of a semi-trailer that locks into the tractor unit's
[fifth wheel](#fifth-wheel).

## L

### Lateral acceleration
How hard a vehicle is being pushed sideways, usually in a corner (`accLat`). Measured in metres
per second squared; 9.8 of them is one g, the pull of gravity.

### Lift
The upward force a wing makes as air flows over it. It grows with the square of the airspeed.

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

### MFWD
Mechanical front-wheel drive: a tractor's switchable drive to its front axle (`fwd_drive`). With
it on, all four wheels pull.

### Mixer
On a drone, the part of the flight controller that turns "climb, tilt forward, tilt sideways,
turn" into four separate motor speeds.

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

### NMEA 2000
The message set boats use on their CAN bus. The boat's signals (speed through water, depth, wind,
rudder) borrow its names.

## O

### Odometer
The distance counter, in kilometres (`odo`). It adds up distance driven in either direction and
never counts down. A respawn hands back the vehicle as new, with the counter at zero.

### Open differential
A plain [differential](#differential) that always splits the turning force equally. If one wheel
loses grip, the other gets no more than the slipping one, so the vehicle can be stuck with one
wheel spinning.

### Overrun
The engine being driven by the wheels, as when coasting downhill in gear.

### Oversteer
A car turning more sharply than the driver asked, because the rear tyres slide first. The back
swings out.

## P

### Pantograph
The folding frame on a train's roof that presses against the overhead wire to collect power
(`pantograph`). With it down, the train has no power.

### Park pawl
A small catch inside an automatic gearbox that locks it in P. It only drops in below walking pace.

### Pedal map
The rule that turns the accelerator's position into an amount of fuel or a turning-force request.
Petrol cars, diesel trucks and the tractor each use a different rule.

### Pitch
The nose of a vehicle tipping up or down. A car pitches forward when it brakes.

### Powershift
A tractor gearbox that changes gear under load without the driver pressing a clutch, using
several clutches inside. The `tractor-kenney` has sixteen forward gears.
<!-- tractor-kenney_spec.tres gear_ratios, 16 entries -->

### Prop wash
The fast stream of water behind a boat's propeller. Over the rudder it lets the boat steer even
when it is barely moving.

### PTO
Power take-off: a spinning shaft at the back of a tractor that drives an implement's moving parts.
It runs at 540 or 1000 turns a minute (`pto`, `pto_mode`, `pto_rpm`). The game counts its power as
load on the engine.
<!-- contract pto_mode enum 540 / 1000 -->

## R

### Redline
The highest safe engine speed. The [rev limiter](#rev-limiter) stops the engine going past it.

### Retarder
An extra brake inside a truck's driveline that slows it without wearing the wheel brakes. Useful
on long descents. The trucks have one (`retarder`, `retarder_state`).

### Rev limiter
A control that cuts the fuel when the engine reaches its redline.

### Reverser
On a train, the switch that chooses direction: forward, neutral or reverse. The game sends it on
the same `gear` signal as a car's gearbox.

### Ride frequency
How many times a second a vehicle's body bounces up and down on its springs after a bump. Softer
springs or a heavier load give a lower frequency and a gentler ride. The game's saloons bounce
about 1.4 times a second.

### Roll
A vehicle leaning to one side about its length, as a car body leans outwards in a corner.

### Roll steer
A small change in the wheels' angle caused by the body leaning in a corner, from the shape of the
suspension links. In the game it always turns the wheels towards steadier handling
([understeer](#understeer)).

### Rolling resistance
The small force that slows a rolling tyre, from the rubber flexing and the ground giving way. It
is proportional to the load on the tyre. Soft ground like mud or sand adds much more.

### Roll stability control
The part of stability control that brakes a truck and its trailer before the sideways force could
tip them over. In the game the semis carry it, and so do their semi-trailers, which brake
themselves off their own sensors.

### Rollover threshold
The sideways acceleration at which a vehicle tips over rather than sliding. A tall, narrow
vehicle tips sooner. See [Weight transfer and rollover](weight-transfer.md).

### Rotor
A drone's spinning propeller. The game's drone has four.

### Rpm
Revolutions per minute: how many full turns a shaft makes in a minute. The game's car engines
idle at 900 rpm.
<!-- gen_kenney_vehicles.gd CAR_BASE idle_rpm 900 -->

### Rudder
A hinged blade at the back of a boat (or the tail of a plane) that turns it. The boat's rudder
works better the faster the water flows past it.

## S

### Semi-trailer
A trailer with wheels only at the back. Its front rests on the tractor unit's
[fifth wheel](#fifth-wheel).

### Sheet
The rope that controls how far a sail can swing out. In the game `sheet` sets a limit; the wind
pushes the sail out to it.

### Shift policy
The rules an automatic gearbox uses to decide when to change gear: from the road speed, the
pedal, and whether the vehicle is climbing. See [Gearbox and shifting](gearbox.md).

### Sequential gearbox
A racing gearbox whose gears can only be taken in order, one up or one down. The game's two
racing cars have one, worked by an automated clutch and a short ignition cut at each change.

### Signal
One named value passed between Carlito and sloppyCAN, such as the engine speed `rpm` or the brake
pedal `brake`. "Out" signals go from the game to sloppyCAN; "in" signals come the other way.

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
The companion program Carlito talks to: a simulator of a vehicle's electronics and its CAN
messages. It can read the game's signals and send commands back.

### Speed through water
A boat's speed relative to the water around it (`stw`), which differs from its
[speed over ground](#speed-over-ground) when there is a current.

### Speed over ground
A boat's true speed over the seabed (`sog`), from its position.

### Spring brake
A truck parking brake held off by air pressure and applied by a strong spring. If the air runs
out, the spring puts the brake on by itself, so a truck that loses its air stops.

### Stability control
A system that brakes one wheel by itself to stop a car spinning or sliding wide. Often called ESC.
On the semis it also brakes the whole rig before it would tip over.

### Stall
Two meanings. A wing stalls when the air stops flowing smoothly over it and its lift collapses,
at too low a speed or too steep an angle. An engine stalls when the load slows it until it stops;
the game's engines never do.

### Stall speed
The engine speed a car with a [torque converter](#torque-converter) reaches when it is held still
on the brakes with the accelerator fully pressed. About 2400 rpm on the game's cars.

### State of charge
How full a battery is, as a percentage (`soc` on the drone).

### Static friction
The grip that holds a still tyre in place, before it starts to slide. In the game a parked car is
held by a small springy give in each tyre's contact patch.

### Steering taper
The steering lock getting smaller as speed rises, so a full turn of the wheel at motorway speed
does not throw the car off the road. The game's cars, vans, trucks and tractors have it.

### Surface
The kind of ground under a tyre: asphalt, wet road, airfield pad, gravel, dirt, grass, sand, rock,
mud, field soil, snow or ice. Each gives a different grip and rolling resistance. See
[Ground and tyre types](surfaces.md).

### Suspension
The springs, dampers and links between the wheels and the body. They let the wheels follow bumps
and keep the tyres pressed onto the road. See [Suspension](suspension.md).

### Swinging front axle
A front axle built as one beam on a single pivot in the middle, so one wheel can rise as the other
drops. Farm tractors use it; in the game it swings up to 10° each way before it meets its stop.

## T

### Telemetry
Measurements a vehicle sends out about itself: speed, engine speed, temperatures. In Carlito every
"out" signal is telemetry, read from the simulation itself.

### Terrain
The painted ground of an island level: a surface shaped by a height map, painted in colours that
each stand for a kind of ground. Anything that is not painted terrain counts as dry asphalt.

### Tide
A current that changes direction and strength over time. Level 6 has one; CONDITIONS can set its
strength and direction.

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
the drive. In the game it is ideal: it holds each driven wheel at the slip where the tyre pulls
hardest. Called TC on cars and ASR on trucks.

### Tractive effort
The pulling force a locomotive makes at the rails. The game's train pulls with a constant force at
low speed and with constant power above that.

### Trailer bus
The data link between a truck and its trailer. See [ISO 11992](#iso-11992).

### Trim
The angle of a boat's outboard drive, which tilts the bow up or down. The game publishes it as
`trim`.

### Turning circle
The smallest circle a vehicle can drive at full lock.

### Tyre class
A type of tyre tread: all-season, summer, winter, studded winter, mud, and others. Each grips
differently on each surface. Cars and trucks can change tyre class in the garage. See
[Ground and tyre types](surfaces.md).

## U

### Understeer
A car turning less sharply than the driver asked, because the front tyres slide first. The car
runs wide. Most road cars are designed to understeer a little, because it is easier to control.

## V

### Variant
One vehicle model within a family. The `sedan` and the `taxi` are variants of the car family.

## W

### Weathervane
A plane's or boat's tendency to swing its nose into the airflow, like a weather vane on a roof.

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

### Windage
The push of the wind on the part of a boat above the water.

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
| N, kN | newtons, kilonewtons: force | the `sedan` weighs about 11 kN <!-- sedan_spec.tres mass 1150 kg --> |
| N·m | newton-metres: torque | 10 N pushed on a spanner 1 m long makes 10 N·m |
| rev/min (rpm) | revolutions per minute | the game's cars idle at 900 rpm <!-- CAR_BASE idle_rpm --> |
| rad/s | radians per second: turning speed; 1 rad/s is about 57 degrees a second | |
| deg | degrees of angle | a right angle is 90 deg |
| bar, kPa | pressure; 1 bar is 100 kPa | the trucks' air tanks fill up to 12 bar <!-- AIR_MAX_BAR --> |
| % | percent | pedal positions, loads and levels |
| ratio | a plain number with no unit | slip is shown as a ratio |
| 1/km | one over a distance: curvature, the tighter the turn the bigger | 100 1/km is a 10 m radius |
| degC | degrees Celsius | water boils at 100 degC |
| V, A | volts, amperes | a resting battery reads about 12.6 V <!-- BATTERY_RESTING --> |
| L/h | litres per hour: fuel use | |
| kg | kilograms: mass, also used for axle loads | |
| h | hours | engine hours |
