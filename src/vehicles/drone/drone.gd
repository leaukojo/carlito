class_name DroneVehicle
extends BaseVehicle
## Quadcopter drone. A real BaseVehicle subclass (like the boat) because it owns a
## flight locomotion module the wheeled base has no concept of. It never forks
## _physics_process — it plugs into the two base seams (_make_telemetry, _tick_extras).
##
## Locomotion (arcade, self-levelling): rotor thrust along the body up axis hovers the
## craft (gravity feedforward) with a climb axis for vertical rate; an attitude controller
## chases the commanded tilt (throttle = forward/back lean, steer = yaw rate) and levels
## roll; air drag limits translation. There is no manual acro — the body always returns to
## level. Rotors spin only when armed AND the key is at Ignition; disarmed, the craft is an
## inert rigid body that simply falls.
##
## Every force term is a pure static fn carrying the RayWheel/boat one-tick clamp
## discipline (60 Hz locked tick): a damper may at most zero the velocity it opposes in one
## tick (never reverse it), and totals are hard-capped. Unit-tested in tests/test_drone.gd.
## DO NOT remove or weaken any clamp; DO NOT raise the tick.
##
## Flight tuning lives here as node knobs (like the boat's buoyancy/propulsion knobs);
## body tuning (mass, gear ratios kept for the zero-wheel drivetrain) is drone_spec.tres.

const ROTOR_IDLE_RPM := 2600   ## mean rotor speed at hover-idle (armed, no lift demand floor)
const ROTOR_MAX_RPM := 12000   ## contract 'rotor_rpm' range max (full thrust)
## Visual rotor spin: blade rad/s per rotor rpm — a cosmetic ratio far below the real rev
## rate (which would alias to a shimmer at 60 fps); the honest number stays the published
## rotor_rpm, the spinning blades are its readable stand-in (the tractor rotor precedent).
const ROTOR_VISUAL_SPIN := 0.005

@export_group("Lift")
@export var max_thrust := 150.0      ## N total rotor thrust cap (hard cap, like max_suspension_force)
@export var climb_force := 45.0      ## N added/removed at full climb stick (< m*g so full-down still descends gently)
@export var vertical_drag := 6.0     ## N per m/s of vertical speed (sets terminal climb/descent rate)

@export_group("Attitude")
@export var max_tilt_deg := 32.0             ## forward/back lean at full throttle
@export var attitude_stiffness := 14.0       ## N*m per unit leveling error (~sin of the attitude error)
@export var attitude_damping := 3.0          ## N*m per rad/s of off-axis (non-yaw) angular velocity
@export var max_attitude_torque := 20.0      ## N*m cap on the leveling torque
@export var max_yaw_rate := 2.2              ## rad/s commanded at full steer
@export var yaw_gain := 4.0                  ## N*m per rad/s of yaw-rate error
@export var max_yaw_torque := 6.0            ## N*m cap on the yaw torque

@export_group("Translation")
@export var horizontal_drag := 0.5   ## N per m/s of horizontal speed (air resistance, sets top forward speed)

## Body footprint (m), used only to derive the representative moment of inertia the
## one-tick torque clamps need — the same role the boat's probe span plays for its yaw cap.
@export var body_extents := Vector3(1.1, 0.2, 1.1)

var _gravity := 9.8
var _inertia := 0.6   ## representative moment (kg*m^2) for the one-tick torque clamps

@onready var _rotors_cw: Array[Node3D] = [$RotorFL, $RotorRR]   ## counter-rotating pairs,
@onready var _rotors_ccw: Array[Node3D] = [$RotorFR, $RotorRL]  ## like a real quad


## Cosmetic only: spin the rotor blades from the published rotor_rpm (visuals in
## _process, physics untouched — the tractor implement's rotor pattern).
func _process(delta: float) -> void:
	var t := telemetry as DroneTelemetry
	if t == null:
		return
	var step := t.rotor_rpm * ROTOR_VISUAL_SPIN * delta
	for r in _rotors_cw:
		r.rotate_y(step)
	for r in _rotors_ccw:
		r.rotate_y(-step)


func _make_telemetry() -> VehicleTelemetry:
	return DroneTelemetry.new()


func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Representative inertia of a box footprint (m (w^2 + d^2) / 12) — the clamp basis for
	# the attitude/yaw torque dampers, shared with the boat and the plane.
	_inertia = VehicleMath.inertia_of(spec.mass, body_extents.x, body_extents.z)


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as DroneTelemetry
	var body_basis := global_transform.basis
	var up := body_basis.y
	var armed := input.arm and input.key == InputRouter.KEY_IGNITION

	# Horizontal air drag always acts — one-tick clamped. The VERTICAL damper is
	# rotor-borne (it exists to set the armed terminal climb/descent rate), so it only
	# acts while armed: disarmed, the craft is an inert body in near free fall (a 1.2 m
	# quad's real body drag is negligible at these speeds).
	var h_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(VehicleMath.clamped_damper(h_vel, horizontal_drag, spec.mass, delta))

	var thrust := 0.0
	if armed:
		var v_vel := Vector3(0.0, linear_velocity.y, 0.0)
		apply_central_force(VehicleMath.clamped_damper(v_vel, vertical_drag, spec.mass, delta))
		# Rotor thrust along body up: hover feedforward counters gravity, climb stick trims it.
		thrust = lift_thrust(spec.mass, _gravity, clampf(input.climb, -1.0, 1.0), climb_force, max_thrust)
		apply_central_force(up * thrust)

		# Attitude: level roll and chase the commanded forward/back tilt (throttle). The
		# align torque (A x B) is sign-correct by construction; the damper opposes only the
		# off-axis (non-yaw) angular velocity so it never fights the yaw controller.
		# Negated so W (positive throttle) leans the nose FORWARD (fly forward), S back.
		var tilt := -clampf(input.throttle, -1.0, 1.0) * deg_to_rad(max_tilt_deg)
		var target_up := level_target_up(body_basis, tilt)
		var perp := angular_velocity - up * angular_velocity.dot(up)
		var att := (align_torque(up, target_up, attitude_stiffness)
				+ VehicleMath.clamped_damper(perp, attitude_damping, _inertia, delta)).limit_length(max_attitude_torque)
		apply_torque(att)

		# Yaw: drive the yaw rate toward the commanded rate about body up. steer negative =
		# left; +Y torque yaws left, so the sign flips (the boat's rudder convention).
		var yaw_t := VehicleMath.yaw_torque(-_steer * max_yaw_rate, angular_velocity.dot(up),
				yaw_gain, _inertia, delta, max_yaw_torque)
		apply_torque(up * yaw_t)

	# Telemetry: attitude straight from the body basis, altitude/vspeed from the sim,
	# rotor_rpm modeled from thrust demand (honest-model latitude, labelled).
	t.pitch = VehicleMath.pitch_deg(body_basis)
	t.roll = VehicleMath.roll_deg(body_basis)
	t.altitude = global_position.y
	t.vspeed = linear_velocity.y
	t.rotor_rpm = rotor_rpm(thrust, max_thrust, ROTOR_IDLE_RPM, ROTOR_MAX_RPM, armed)
	t.armed = armed


# --- pure flight math (unit-tested, one-tick clamped like RayWheel/boat) -------

## Total rotor thrust (N) along body up. Hover feedforward counters gravity; the climb
## stick adds/removes lift. Non-negative (rotors only push) and hard-capped at max_thrust.
static func lift_thrust(body_mass: float, gravity: float, climb: float,
		climb_gain: float, thrust_cap: float) -> float:
	return clampf(body_mass * gravity + climb * climb_gain, 0.0, thrust_cap)


## Target body-up direction: world up tilted about the current heading's right axis by
## `tilt` rad. Level (tilt 0) = straight up. POSITIVE tilt leans the up-vector backward
## (nose-up, backward flight); NEGATIVE tilt leans it forward (nose-down, forward flight)
## — the caller negates throttle so W yields negative tilt. Yaw is left free.
static func level_target_up(body_basis: Basis, tilt: float) -> Vector3:
	var fwd := -body_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 1e-3:
		# Nose near vertical: fall back to the up-vector's heading so 'forward' stays defined.
		flat = Vector3(body_basis.y.x, 0.0, body_basis.y.z)
	if flat.length() < 1e-3:
		return Vector3.UP
	flat = flat.normalized()
	var right := flat.cross(Vector3.UP).normalized()  # heading's right axis
	return Vector3.UP.rotated(right, tilt)


## Corrective torque rotating `body_up` toward `target_up` (A x B). Direction is correct
## by construction (no trig sign chasing); magnitude ~ sin(error) * stiffness.
static func align_torque(body_up: Vector3, target_up: Vector3, stiffness: float) -> Vector3:
	return body_up.cross(target_up) * stiffness


## Modeled mean rotor rpm (honest-model latitude, like the boat's trim): 0 when disarmed,
## otherwise scaled between a spin idle and max by the thrust fraction. Rounded to an int.
static func rotor_rpm(thrust: float, thrust_cap: float, spin_min: int, spin_max: int, armed: bool) -> int:
	if not armed:
		return 0
	var frac := clampf(thrust / maxf(1.0, thrust_cap), 0.0, 1.0)
	return roundi(lerpf(spin_min, spin_max, frac))
