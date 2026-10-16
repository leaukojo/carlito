class_name VehicleSpec
extends Resource
## All tuning for one vehicle: a new vehicle is a new spec plus a model scene. Curves are point
## arrays (`sample_curve`), not Curve resources, for deterministic tests. Free bodies tune hull,
## airframe and aero as `@export`s on the vehicle node. Boat fields are also written by
## `tools/gen_boat_variants.gd`: edit the recipe, or the next regen undoes it.

## Wheeled ground drive, or null (boat, drone, train). A `[sub_resource]` per spec, never external.
@export var ground_drive: GroundDriveSpec

@export_group("Body")
@export var mass := 1200.0                         ## kg, applied to the RigidBody3D
@export var center_of_mass := Vector3(0, -0.3, 0)  ## body-space; low COM keeps the car flat
@export var angular_damping := 0.0  ## 0 = engine default; raise for a narrow-track, low-yaw-inertia body as a stability-assist yaw bleed
## Yaw dynamic index k² / (a·b), a and b the COM's distances to the front and rear axles: the yaw
## moment is declared as `index * mass * a * b` (`BaseVehicle`). 0 = Jolt's tensor off the
## collision shapes at uniform density, which puts as much mass per metre in the overhangs as
## between the axles. Roll and pitch are always Jolt's.
@export var yaw_dynamic_index := 0.0

@export_group("Trailer")
## Whether the ISO 7638 connector carries the ISO 11992 data pair. False = North American SAE
## J2497 (power-line ABS only): a coupled trailer publishes trailer_connected false, honest zeros.
@export var trailer_bus_equipped := false

@export_group("Drivetrain")
## Showroom decoration only: `Drivetrain` runs for every family (the gear byte is the direction
## latch). Not `ground_drive == null`: a boat's outdrive has gears but no wheels.
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
## Overrun (engine-braking) torque at the crank with the fuel cut AT REDLINE, as a fraction of the
## torque curve's peak; the motoring law runs linearly to it from `engine_friction_frac` at idle,
## and part fuel blends it in by the unfuelled share (`Drivetrain.motoring_torque`).
@export var engine_brake_frac := 0.0
## Motoring torque at and below idle, as a fraction of the curve's peak: friction (and a petrol's
## pumping) that runs a free crank down. 0 = none. Sourced: docs/vehicles.md § Crank and coupling.
@export var engine_friction_frac := 0.0
## Rotating inertia at the crank (kg·m²), on wheel-driving bodies only (`Drivetrain.drives_wheels`).
## Sourced per class: docs/vehicles.md § Crank and coupling.
@export var engine_inertia := 0.0
## Torque converter (an automatic; creeps in gear, lock-up per `Drivetrain.converter_free_rpm`) or
## friction clutch (AMT, sequential, powershift; `Drivetrain.coupling_step`).
enum Coupling { CONVERTER, CLUTCH }
@export var coupling: Coupling = Coupling.CONVERTER
## The coupling's torque rating over the torque curve's peak (`Drivetrain.clutch_rating`): about
## 1.5 on cars and 2.0 on trucks (OE practice). What a clutch or a converter's lock-up carries while
## locked, and the ceiling on a shift's slip (`shift_handover_s`).
@export var clutch_reserve := 1.5
## A converter's torque ratio with the turbine held (`TorqueConverter.torque_ratio`), falling to 1.0
## at the coupling point. COMPROMISE: 1.0 (a fluid coupling) ships; a real ~2.0 fails the foot
## brake's stall hold on seven bodies until their brakes are sourced (docs/vehicles.md § Converter).
@export var converter_stall_ratio := 1.0
## Lowest D gear a converter's lock-up closes in: 1 on a 6-speed car (the converter opens only for
## the launch), 2 on an Allison-class box (lock-up from 2nd range standard).
@export var lockup_gear := 1
## Launch target over idle (rpm) the clutch controller holds the crank at while a pull-away slips:
## a heavy AMT's (~300 over idle). 0 = the stall line (`Drivetrain.launch_target_rpm`).
@export var launch_rpm_over_idle := 0.0
## Seconds of throttle cut after a gear change (an AMT's torque interruption, a sequential's
## ignition cut); 0 = seamless (powershift, or a converter's `Drivetrain.handover_fuel`).
## Bridge-exact byte writes count as shifts; `applied_throttle` reads 0 through the cut.
@export var shift_cut_s := 0.0
## Seconds over which the fuel returns after `shift_cut_s` ends: an AMT ramps the engine's torque
## back once the new gear is engaged, so the drive does not step into the driveline
## (`Drivetrain.torque_restore_step`). 0 = it returns in one tick (a sequential's ignition cut).
@export var shift_torque_ramp_s := 0.0
## Seconds a modulated start-up clutch takes to reach its whole rating on a pull-away (a
## powershift's pressure ramp); 0 = the rating is there on the first tick. See `Drivetrain.ramp`.
@export var launch_engage_s := 0.0
## Seconds an upshift's inertia phase spans: the oncoming clutch carries the engine's delivered
## torque plus the crank's inertia over this time (`Drivetrain.handover_rate`), never past the
## rating. 0 = the clutch closes at the rating, the limit the law approaches as the time shrinks.
@export var shift_handover_s := 0.0
## The full-pedal shift pair, where the launches and top speeds are tuned: the automatic upshifts at
## `shift_up_rpm` and downshifts at `shift_down_rpm` on the road speed's rpm in the engaged gear,
## through `ShiftPolicy`, which blends to the light pair below as the pedal lifts.
@export var shift_up_rpm := 5600.0
@export var shift_down_rpm := 2200.0
## The upshift rpm at a light pedal (`ShiftPolicy.LIGHT_PEDAL` and under), the lift upshift at pedal
## 0; `ShiftPolicy.upshift_rpm` raises it per step until the landing clears the downshift point.
## 0 = `shift_up_rpm`, no light map.
@export var shift_up_light_rpm := 0.0
## The downshift rpm at a light pedal and coasting (the coast downshift); no dwell holds the box
## under it, so a stop steps down to D1. 0 = `shift_down_rpm`.
@export var shift_down_light_rpm := 0.0
## The pedal a stab must cross upward for a kickdown (`ShiftPolicy.kickdown_armed`): one shift to the
## lowest gear under `ShiftPolicy.kickdown_ceiling_rpm`. 0 = no kickdown.
@export var kickdown_pedal := 0.0
## Minimum time in gear (s) before a pedal-dependent shift or a kickdown (`ShiftPolicy.dwelling`);
## never a gear held past `shift_up_rpm` or under the coast downshift. 0 = none.
@export var shift_dwell_s := 0.0
## An upshift goes straight to the gear a sequential box would ripple to (an AMT's or a
## powershift's skip-shift); a full pedal never skips (`ShiftPolicy.upshift_target`).
@export var skip_shifts := false
## The highest gear a pull-away may start in (`ShiftPolicy.start_gear`). 0 or 1 = D1.
@export var start_gear_max := 0
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
