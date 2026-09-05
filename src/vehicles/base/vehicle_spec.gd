class_name VehicleSpec
extends Resource
## All tuning for one vehicle: a new vehicle is a new spec plus a model scene. Data-only, consumed
## by BaseVehicle, Drivetrain and LampSet. Curves are point arrays sampled by `sample_curve` rather
## than Curve resources, for deterministic tests.
##
## The wheeled ground drive is the `ground_drive` sub-resource, so a boat or drone spec carries no
## wheel field; free bodies tune hull, airframe and aero as `@export`s on the vehicle node. The
## boat is tuned twice over: `boat-*.tscn` overrides ~9 fields `tools/gen_boat_variants.gd` also
## writes, and changing one without the other is undone by the next regen.

## Wheeled ground drive, or null with no running gear (boat, drone, train). Embedded per spec as
## a `[sub_resource]`, never external.
@export var ground_drive: GroundDriveSpec

@export_group("Body")
@export var mass := 1200.0                         ## kg, applied to the RigidBody3D
@export var center_of_mass := Vector3(0, -0.3, 0)  ## body-space; low COM keeps the car flat
@export var angular_damping := 0.0  ## 0 = engine default; raise for a narrow-track, low-yaw-inertia body as a stability-assist yaw bleed

@export_group("Trailer")
## Whether the tow unit's ISO 7638 connector carries the ISO 11992 data pair. False elsewhere by
## design: North America runs trailer ABS on the power line (SAE J2497) with no data pair, so a
## coupled trailer there publishes trailer_connected false with honest zeros behind it.
@export var trailer_bus_equipped := false

@export_group("Drivetrain")
## Whether the showroom describes this machine as having an engine. Decoration only: `Drivetrain`
## runs for every family regardless, since the gear byte is the direction latch
## `InputRouter.arbitrate_local` reads. Not inferred from `ground_drive == null`, because a boat's
## outdrive has forward, neutral and reverse despite no wheels.
@export var has_engine := true
## rpm -> engine Nm at full throttle. It may end nonzero at the redline, since
## `Drivetrain.limiter_cut` is the fuel cut that stops the engine; ending at zero is a droop.
@export var torque_curve := PackedVector2Array([
	Vector2(900, 95), Vector2(2000, 150), Vector2(3200, 180),
	Vector2(4800, 185), Vector2(6000, 165), Vector2(6800, 60),
])
@export var idle_rpm := 900.0
@export var redline_rpm := 6800.0
@export var gear_ratios := PackedFloat32Array([3.5, 2.2, 1.55, 1.18, 0.94, 0.78])
@export var reverse_ratio := 2.2  ## short enough that reverse wheel torque stays under sliding grip
@export var final_drive := 3.9
@export var efficiency := 0.9
@export var shift_up_rpm := 5600.0
@export var shift_down_rpm := 2200.0
@export var speed_limit_kmh := 0.0  ## road-speed governor, km/h; 0 = ungoverned (J1939 SPN 74). Fades throttle over `Drivetrain.GOVERNOR_BAND` so it settles instead of hunting

@export_group("Steering")
@export var steer_speed := 2.5  ## steer-axis slew rate, units/s; also slews the boat's rudder and plane's/drone's yaw. The LOCK lives on GroundDriveSpec

@export_group("Lamps")
## Ladder the beam climbs as `lights` goes OFF -> CLEARANCE -> LOW -> HIGH. ROAD is a parking
## glow, a dipped asymmetric beam, then main beam. AIRCRAFT is dark at CLEARANCE, where the beacon
## and nav lights own that step, then a wide steep taxi beam, then a narrow landing beam.
enum LampStyle { ROAD, AIRCRAFT }
@export var lamp_style: LampStyle = LampStyle.ROAD
@export var headlight_paths: Array[NodePath] = []  ## SpotLight3D nodes LampSet drives (energy/range per level)
@export var head_lamp_paths: Array[NodePath] = []  ## visible head lens meshes, separate from the SpotLight3D beam
@export var brake_lamp_paths: Array[NodePath] = []
@export var turn_left_paths: Array[NodePath] = []
@export var turn_right_paths: Array[NodePath] = []
@export var steady_lamp_paths: Array[NodePath] = []  ## plane nav lights: on with master switch, no blink; each keeps its own scene-authored colour
@export var flash_lamp_paths: Array[NodePath] = []  ## aircraft beacon; lit from the mirrored `beacon` bit, never a local clock
@export var strobe_lamp_paths: Array[NodePath] = []  ## wing-tip strobes; separate group riding its own `strobe` bit
@export var led_lamp_paths: Array[NodePath] = []  ## drone arm tips; colour comes from the bus `led` signal via LampSet.led_color, not scene-authored


## Piecewise-linear sample of a (x, y) point array sorted by x; clamps at both ends.
static func sample_curve(points: PackedVector2Array, x: float) -> float:
	if points.is_empty():
		return 0.0
	if x <= points[0].x:
		return points[0].y
	for i in range(1, points.size()):
		if x <= points[i].x:
			var t := (x - points[i - 1].x) / (points[i].x - points[i - 1].x)
			return lerpf(points[i - 1].y, points[i].y, t)
	return points[points.size() - 1].y
