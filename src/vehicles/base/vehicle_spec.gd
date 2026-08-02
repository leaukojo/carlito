class_name VehicleSpec
extends Resource
## All tuning for one vehicle: new vehicle = new spec + model scene.
##
## Data-only; consumed by BaseVehicle / RayWheel / Drivetrain. Curves are point
## arrays with linear interpolation (sample_curve) instead of Curve resources so
## tuning is deterministic and directly assertable in unit tests.
## Lamp PLACEMENT stays scene-authored: the spec only declares which scene
## nodes are which lamp (the *_paths below), never their transforms.

@export_group("Body")
@export var mass := 1200.0                         ## kg, applied to the RigidBody3D
@export var center_of_mass := Vector3(0, -0.3, 0)  ## body-space; low COM keeps the car flat
## Angular damping applied to the RigidBody (0 = engine default, the case for every wheeled
## car/truck/tractor). The bikes raise it: the narrow-track trick gives them a tiny yaw
## inertia, so a stability-assist yaw bleed is what stops a light bike spinning out.
@export var angular_damping := 0.0

@export_group("Wheels")
## Hub anchors in body space, order FL, FR, RL, RR (front = -Z, right = +X).
@export var wheel_positions := PackedVector3Array([
	Vector3(-0.78, -0.1, -1.25), Vector3(0.78, -0.1, -1.25),
	Vector3(-0.78, -0.1, 1.25), Vector3(0.78, -0.1, 1.25),
])
@export var wheel_radius := 0.32
@export var wheel_inertia := 1.2   ## kg*m^2 around the axle
## Optional wheel visual scene, instanced under WheelFL..RR when the vehicle scene has no
## authored wheel mesh (the Kenney wheel wrapper). RayWheel drives its transform each tick;
## radius is still spec.wheel_radius (visual only). Absent = wheels come from the scene.
## Wheel scenes are authored radius-NORMALIZED (model scaled to radius 1.0); BaseVehicle
## scales each instance to the visual radius below.
@export var wheel_scene: PackedScene
## Optional separate rear-axle visual (the tractor's big rears); null = wheel_scene.
@export var wheel_scene_rear: PackedScene
## Rendered wheel radius in m; 0 = wheel_radius. VISUAL ONLY — RayWheel stays single-radius,
## so physics keeps using wheel_radius for every corner. A visual bigger/smaller than the
## physics radius is lifted/dropped so it still meets the ground.
@export var wheel_visual_radius := 0.0
## Rendered rear-axle radius in m; 0 = wheel_visual_radius. Visual only, as above.
@export var wheel_visual_radius_rear := 0.0
@export var driven_front := false
@export var driven_rear := true
## The rear axle can be rigidly coupled at runtime (the tractor's differential lock). Off
## everywhere else, so no other vehicle's driveline can be changed by the diff_lock input bit.
@export var rear_diff_lockable := false
## The front axle is engaged/disengaged at runtime (the tractor's MFWD) instead of being fixed
## by driven_front at spawn. Off everywhere else, same reason as above.
@export var front_axle_engageable := false
## The driveline carries an auxiliary retarder (the truck's J1939 SPN 520 brake, acting on the
## driven axle). Off everywhere else, so no other vehicle's driveline can be changed by the
## 'retarder' input bit — the same "other vehicles ignore it" contract as the two flags above.
@export var retarder_equipped := false
## The tractor unit's ISO 7638 connector carries the ISO 11992 data pair (pins 6 and 7), so a
## coupled trailer can claim on the trailer bus. Off everywhere else — and deliberately off, not
## missing, on a unit that tows: North America puts trailer ABS on the POWER line (SAE J2497) and
## has no data pair to run a bus on. With this false a physically coupled trailer publishes
## trailer_connected FALSE and honest zeros behind it — attached steel and bus silence, the third
## state the tractor's implement_connected teaches.
@export var trailer_bus_equipped := false

@export_group("Suspension")
@export var rest_length := 0.25     ## m of free ray travel below the hub anchor
@export var spring_rate := 22000.0  ## N/m (~1.3 Hz natural frequency at 300 kg/corner — 60 Hz-safe)
@export var damper_bump := 1800.0   ## N*s/m
@export var damper_rebound := 2400.0
@export var max_suspension_force := 30000.0  ## N; clamp against deep-penetration catapults

@export_group("Tires")
## Slip -> grip factor, shared by both axes: x is slip ratio (longitudinal) or slip
## angle in radians (lateral) — both peak around 0.10-0.15 on that scale.
@export var grip_curve := PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.4, 0.9), Vector2(1.0, 0.8),
])
@export var mu_long := 1.05
@export var mu_lat := 0.95
## Rear lateral grip multiplier while the handbrake is pulled (1 = no effect).
## The arcade drift knob: the §6 hierarchy caps handbrake_torque too low to lock the
## rears, so kicking the tail out is done by cutting rear side grip instead.
@export_range(0.0, 1.0) var handbrake_grip := 1.0

@export_group("Drivetrain")
## rpm -> engine Nm at full throttle.
@export var torque_curve := PackedVector2Array([
	Vector2(900, 95), Vector2(2000, 150), Vector2(3200, 180),
	Vector2(4800, 185), Vector2(6000, 165), Vector2(6800, 60),
])
@export var idle_rpm := 900.0
@export var redline_rpm := 6800.0
@export var gear_ratios := PackedFloat32Array([3.5, 2.2, 1.55, 1.18, 0.94, 0.78])
@export var reverse_ratio := 2.2  ## short enough that reverse wheel torque stays under sliding grip (no sustained burnout)
@export var final_drive := 3.9
@export var efficiency := 0.9
@export var shift_up_rpm := 5600.0
@export var shift_down_rpm := 2200.0

@export_group("Brakes")
## §6 hierarchy is encoded in these magnitudes (and asserted in tests):
## foot brake > max drive force > handbrake (holds only below ~30% throttle).
@export var brake_torque := 1300.0     ## Nm per wheel, all four
@export var handbrake_torque := 160.0  ## Nm per rear wheel

@export_group("Steering")
@export var max_steer_deg := 32.0
@export var steer_speed := 2.5  ## normalized steer units/s slewed toward input
## High-speed steering falloff: at/above steer_falloff_speed the usable lock shrinks to
## this fraction of max_steer_deg (linear below it). 1.0 = constant lock, the default for
## every vehicle — only the bikes lower it, to stay controllable past ~80 km/h.
@export_range(0.0, 1.0) var min_steer_frac := 1.0
@export var steer_falloff_speed := 30.0  ## m/s at which min_steer_frac is fully reached

@export_group("Lamps")
## Which ladder the beam lamp climbs as `lights` goes OFF -> CLEARANCE -> LOW -> HIGH.
## ROAD is the car's: parking glow, dipped beam (asymmetric — kerb-side lamp dipped and
## splayed), main beam. AIRCRAFT is the light-aircraft one: the wing lamp stays DARK at
## CLEARANCE because the beacon and nav lights own that step, then lights as a wide, short,
## steeply-aimed TAXI beam, then as a narrow, long, near-level LANDING beam. An aircraft
## lamp never takes the road car's dip/splay — that asymmetry exists for oncoming traffic.
enum LampStyle { ROAD, AIRCRAFT }
@export var lamp_style: LampStyle = LampStyle.ROAD
## NodePaths (relative to the vehicle root) naming the scene-authored lamp nodes
## LampSet drives. Headlights are SpotLight3D nodes (energy/range per
## level); the rest are MeshInstance3D lenses given a private emissive material.
@export var headlight_paths: Array[NodePath] = []
## Head LENS meshes: the visible glow sitting on the model's own headlamp face. Separate
## from headlight_paths because that one is the SpotLight3D that throws the beam.
@export var head_lamp_paths: Array[NodePath] = []
@export var brake_lamp_paths: Array[NodePath] = []
@export var turn_left_paths: Array[NodePath] = []
@export var turn_right_paths: Array[NodePath] = []
## Steady marker lenses (the plane's nav lights today): on with the master switch,
## no tier and no blink. Unlike every group above they carry no canonical colour — each
## lens keeps the emissive material the SCENE authored on it, and LampSet drives only its
## energy, so red/green/white lamps can sit in one group.
@export var steady_lamp_paths: Array[NodePath] = []
## Flashing marker lenses (the aircraft anti-collision beacon). Same scene-authored colour
## as steady_lamp_paths, but pulsed by LampSet — the ONE lamp in this project driven by a
## local clock instead of a mirrored bit. See the exception note in lamp_set.gd.
@export var flash_lamp_paths: Array[NodePath] = []


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
