class_name PlaneVehicle
extends BaseVehicle
## Light aircraft (CANaerospace flavor). Propulsion is prop thrust with rpm chasing throttle;
## lift rides forward speed squared times an angle-of-attack factor and fades below stall
## speed; a weathervane moment on angle of attack and sideslip keeps the nose on the velocity
## vector so the aircraft trims itself; drag is body-frame anisotropic (lateral/vertical far
## stiffer than forward) so the velocity follows the nose; control authority scales with
## airspeed. Force terms are
## one-tick clamped; don't weaken any clamp or raise the tick. Single-speed by construction
## (shift_up_rpm 6000 above redline 5400) — don't "fix" the shift point. Wheel visuals: 0=nose,
## 1=left main, 2=right main.

@export_group("Propulsion")
@export var max_thrust := 9000.0        ## N at redline prop rpm (hard cap by construction)
@export var reverse_thrust_frac := 0.25 ## reverse (beta) thrust fraction for taxiing back
@export var prop_spool_rate := 3500.0   ## rpm/s the prop chases the throttle target (spool lag)

@export_group("Aero")
@export var lift_coeff := 13.0          ## N per (m/s)^2 of forward airspeed, flaps retracted
@export var lift_cap := 16000.0         ## N hard cap on total lift (~2 g)
## Lift factor slope per rad of angle of attack (nose above the velocity vector): ~+1 per 10 deg,
## so the elevator changes lift at cruise instead of only rotating the lift vector.
@export var aoa_lift_slope := 5.7
@export var aoa_lift_max := 1.8         ## cap on the angle-of-attack lift factor (the stall fade is separate)
@export var stall_speed := 13.0         ## m/s below which lift is fully gone
@export var full_lift_speed := 20.0     ## m/s at which the lift fraction reaches 1
## N per m/s of forward speed. Includes the removed default_linear_damp (mass * 0.1 = 80 N/m/s)
## folded in so the number is declared. With max_thrust it sets top speed (~26 m/s), sized to sit
## just above the zero-AoA trim speed (~25 m/s) so full throttle does not balloon.
@export var drag_coeff := 350.0
## N per m/s sideways / vertical through the air (fuselage side area, wing planform): far stiffer
## than forward, so the velocity vector follows the nose within a fraction of a second.
@export var drag_lat := 1600.0
@export var drag_vert := 1600.0
@export var flap_lift_bonus := 4.0      ## extra lift_coeff at full flaps
@export var flap_drag_bonus := 40.0     ## extra drag_coeff at full flaps
@export var flap_slew_rate := 0.4       ## flap travel fraction per second (contract flaps_actual)

@export_group("Control")
@export var authority_speed_ref := 15.0 ## m/s of airflow that gives full control authority
@export var pitch_gain := 12000.0       ## N*m at full elevator + full authority
@export var pitch_damping := 16000.0    ## N*m per rad/s of pitch rate (gain/damping = max pitch rate, ~43 deg/s)
## Weathervane: N*m per rad of angle of attack per (m/s)^2 of forward speed, nose toward the
## velocity vector. At cruise full elevator holds ~10 deg of AoA against it.
@export var aoa_stiffness := 110.0
@export var sideslip_stiffness := 60.0  ## same, per rad of sideslip about body up
@export var max_pitch_torque := 12000.0 ## N*m cap on the total pitch torque
@export var max_bank_deg := 45.0        ## bank angle commanded at full steer
@export var roll_stiffness := 9000.0    ## N*m per rad of bank error
@export var roll_damping := 3000.0      ## N*m per rad/s of roll rate
@export var max_roll_torque := 9000.0   ## N*m cap on the total roll torque
@export var max_yaw_rate := 0.5         ## rad/s commanded at full steer + full authority
@export var yaw_gain := 6000.0          ## N*m per rad/s of yaw-rate error
@export var max_yaw_torque := 7000.0    ## N*m cap on the yaw torque
@export var stall_pitch_gain := 6000.0  ## N*m of nose-down torque at full stall (airborne)

@export_group("Surface visuals")
@export var elevator_deflect_deg := 20.0 ## elevator travel at full command
@export var rudder_deflect_deg := 25.0   ## rudder travel at full steer
@export var aileron_deflect_deg := 18.0  ## aileron travel at full steer (differential)
@export var flap_deflect_deg := 30.0     ## flap travel at full extension (down only)
@export var elevator_slew_rate := 3.0    ## visual elevator travel per second
## Prop rpm above which the blades swap for the translucent disc (readable at 60 fps).
@export var prop_disc_rpm := 4000.0

## Body footprint (m); derives the moment of inertia for the torque clamps.
@export var body_extents := Vector3(7.0, 1.5, 5.5)

## Shaft rad/s per prop rpm. Cosmetic, far below the real rev rate; published rpm stays honest.
const PROP_VISUAL_SPIN := 0.012

var _prop_rpm := 0.0   ## modeled prop rpm the thrust is computed from (published as rpm)
var _flap_pos := 0.0   ## 0..1 actual flap extension, slewed toward the request
var _inertia := 5000.0       ## yaw moment (kg*m^2), about body up, for the yaw torque clamp
var _inertia_pitch := 5000.0 ## pitch moment (kg*m^2), about body right, for the pitch torque clamp
var _inertia_roll := 5000.0  ## roll moment (kg*m^2), about body forward, for the roll torque clamp
var _elevator_cmd := 0.0 ## VISUAL mirror of the pitch command (physics reads input directly)
var _elevator_pos := 0.0 ## slewed elevator deflection the surface is drawn at

@onready var _prop: Node3D = $Prop
@onready var _prop_blades: Node3D = $Prop/Blades
@onready var _prop_disc: Node3D = $Prop/Disc
@onready var _elevator_l: Node3D = $ElevatorL
@onready var _elevator_r: Node3D = $ElevatorR
@onready var _rudder: Node3D = $Rudder
@onready var _aileron_l: Node3D = $WingL/AileronL
@onready var _aileron_r: Node3D = $WingR/AileronR
@onready var _flap_l: Node3D = $WingL/FlapL
@onready var _flap_r: Node3D = $WingR/FlapR


## Cosmetic only: mirrors the flight model's already-computed rpm and commands into prop
## spin and surface deflection; never feeds back into a force or torque.
## Each pivot is a bare Node3D on the hinge line, mesh child offset behind it. Local -Z is
## forward: +X rotation drives the trailing edge down, +Y drives it right. Assignment is
## absolute — rotate_* would accumulate and drift.
func _process(delta: float) -> void:
	_prop.rotate_z(_prop_rpm * PROP_VISUAL_SPIN * delta)
	# Past disc rpm the blades swap for the disc; the spinner keeps turning either way.
	var disc := _prop_rpm >= prop_disc_rpm
	_prop_blades.visible = not disc
	_prop_disc.visible = disc

	# The elevator is the one command with no upstream rate limit (_steer is slewed by
	# spec.steer_speed, _flap_pos by flap_slew), so it eases here or it snaps.
	_elevator_pos = move_toward(_elevator_pos, _elevator_cmd, elevator_slew_rate * delta)

	# Nose up = trailing edge up.
	var elevator := deflect_rad(-_elevator_pos, elevator_deflect_deg)
	_elevator_l.rotation.x = elevator
	_elevator_r.rotation.x = elevator
	# Steer right = trailing edge right (yaws the nose right).
	_rudder.rotation.y = deflect_rad(_steer, rudder_deflect_deg)
	# Differential: rolling right drops the left trailing edge and lifts the right.
	_aileron_l.rotation.x = deflect_rad(_steer, aileron_deflect_deg)
	_aileron_r.rotation.x = deflect_rad(-_steer, aileron_deflect_deg)
	# Flaps travel one way only, off the already-slewed actual position.
	var flap := deflect_rad(_flap_pos, flap_deflect_deg)
	_flap_l.rotation.x = flap
	_flap_r.rotation.x = flap


func _make_telemetry() -> VehicleTelemetry:
	return PlaneTelemetry.new()


func _ready() -> void:
	super._ready()
	_prop_rpm = 0.0
	_inertia = VehicleMath.inertia_of(spec.mass, body_extents.x, body_extents.z)
	_inertia_pitch = VehicleMath.inertia_of(spec.mass, body_extents.y, body_extents.z)
	_inertia_roll = VehicleMath.inertia_of(spec.mass, body_extents.x, body_extents.y)


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as PlaneTelemetry
	var body := global_transform.basis
	var fwd := -body.z
	var right := body.x
	var up := body.y

	# Prop rpm chases the throttle target (0 with the key off); thrust derives from that rpm.
	var running := input.key == InputRouter.KEY_IGNITION
	var target_rpm := 0.0
	if running:
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, clampf(absf(input.throttle), 0.0, 1.0))
	_prop_rpm = prop_rpm_step(_prop_rpm, target_rpm, prop_spool_rate, delta)
	var thrust := prop_thrust(_prop_rpm, spec.idle_rpm, spec.redline_rpm, max_thrust,
			drivetrain.gear_byte, reverse_thrust_frac)
	apply_central_force(fwd * thrust)

	# Flaps: actual position slews toward the request (contract flaps_actual).
	_flap_pos = flap_slew(_flap_pos, clampf(input.flaps, 0.0, 1.0), flap_slew_rate, delta)

	# Lift rides forward airspeed squared times the angle-of-attack factor, fades below stall
	# speed. Drag opposes velocity relative to WindField, split in the BODY frame (not
	# VehicleMath.air_damper, whose axis mask is world-space), each term one-tick clamped. Lift
	# and the flow angles stay on absolute velocity, not relative flow: wind is here to be flown
	# against, not to change the stall speed.
	var wind := WindField.at(self)
	var v_fwd := linear_velocity.dot(fwd)
	var aoa := flow_angle(-linear_velocity.dot(up), v_fwd)
	var sideslip := flow_angle(linear_velocity.dot(right), v_fwd)
	var frac := lift_frac(v_fwd, stall_speed, full_lift_speed)
	var coeff := (lift_coeff + flap_lift_bonus * _flap_pos) \
			* aoa_factor(aoa, aoa_lift_slope, aoa_lift_max)
	apply_central_force(up * lift_force(v_fwd, coeff, lift_cap, frac))
	var air := linear_velocity - wind
	apply_central_force(fwd * VehicleMath.damped_force(air.dot(fwd),
			drag_coeff + flap_drag_bonus * _flap_pos, spec.mass, delta))
	apply_central_force(right * VehicleMath.damped_force(air.dot(right), drag_lat, spec.mass, delta))
	apply_central_force(up * VehicleMath.damped_force(air.dot(up), drag_vert, spec.mass, delta))

	# Weathervane: the tail turns the nose onto the velocity vector (pitch on angle of attack,
	# yaw on sideslip), stiffness rising with speed squared like every aero moment.
	apply_torque(right * weathervane_torque(aoa, v_fwd, aoa_stiffness, max_pitch_torque))
	# + sideslip = air from the right = nose should yaw right = -Y torque.
	apply_torque(up * weathervane_torque(sideslip, v_fwd, sideslip_stiffness, max_yaw_torque))

	# Control authority scales with airflow (none at standstill).
	var auth := control_authority(v_fwd, authority_speed_ref)
	# Visual-only mirror; the torque below reads the raw input directly.
	_elevator_cmd = clampf(input.elevator, -1.0, 1.0)
	# Elevator: + = nose up = +torque about body right.
	apply_torque(right * pitch_torque(clampf(input.elevator, -1.0, 1.0), pitch_gain, auth,
			angular_velocity.dot(right), pitch_damping, _inertia_pitch, delta, max_pitch_torque))
	# Steer -> coordinated bank + yaw. steer + = right; +torque about body forward rolls
	# right-side-down, matching the spring sign. Spring always acts, so wings self-level.
	apply_torque(fwd * roll_torque(_steer * max_bank_deg, VehicleMath.roll_deg(body), roll_stiffness,
			auth, angular_velocity.dot(fwd), roll_damping, _inertia_roll, delta, max_roll_torque))
	# steer negative = left; +Y torque yaws left, so the sign flips.
	apply_torque(up * VehicleMath.yaw_torque(-_steer * max_yaw_rate * auth, angular_velocity.dot(up),
			yaw_gain, _inertia, delta, max_yaw_torque))

	# Airborne only: as lift fades the nose is pushed down (recover by diving, never a spin).
	if _airborne():
		apply_torque(right * stall_torque(frac, stall_pitch_gain))

	# rpm is the prop model (honest-model, labelled in PlaneTelemetry).
	t.rpm = _prop_rpm
	t.flaps_actual = roundi(_flap_pos * 100.0)


func respawn() -> void:
	super.respawn()
	_prop_rpm = 0.0
	_flap_pos = 0.0
	_elevator_cmd = 0.0
	_elevator_pos = 0.0


## True when no wheel touches the ground (the stall nose-drop only acts in the air).
func _airborne() -> bool:
	for w in wheels:
		if w.in_contact:
			return false
	return true


# --- pure flight math (unit-tested, one-tick clamped like RayWheel/boat) -------

## Prop rpm chasing its target at a fixed spool rate (rpm/s).
static func prop_rpm_step(current: float, target: float, rate: float, delta: float) -> float:
	return move_toward(current, target, rate * delta)


## 0..1 thrust fraction of the prop rpm within the engine band: idle = 0, redline = 1.
static func thrust_frac(rpm: float, idle_rpm: float, redline_rpm: float) -> float:
	return clampf((rpm - idle_rpm) / maxf(1.0, redline_rpm - idle_rpm), 0.0, 1.0)


## Signed prop thrust (N) along body forward, magnitude from the modeled rpm. Gear byte
## owns direction: D forward, R a weak reverse/beta fraction, N none.
static func prop_thrust(rpm: float, idle_rpm: float, redline_rpm: float, thrust_cap: float,
		gear_byte: int, reverse_frac: float) -> float:
	var mag := thrust_frac(rpm, idle_rpm, redline_rpm) * thrust_cap
	if Drivetrain.is_drive(gear_byte):
		return mag
	if Drivetrain.is_reverse(gear_byte):
		return -mag * reverse_frac
	return 0.0


## Flap position slewing toward the request at a fixed travel rate (fraction/s).
static func flap_slew(current: float, target: float, rate: float, delta: float) -> float:
	return move_toward(current, clampf(target, 0.0, 1.0), rate * delta)


## Cosmetic surface deflection (rad) for a -1..1 command: + = trailing edge down (local X)
## or right (local Y). Clamped to the authored travel.
static func deflect_rad(cmd: float, max_deg: float) -> float:
	return deg_to_rad(clampf(cmd, -1.0, 1.0) * max_deg)


## 0..1 lift fraction vs forward airspeed: 0 at/below stall, 1 at/above full_lift_speed,
## smoothstep between.
static func lift_frac(airspeed: float, stall: float, full_speed: float) -> float:
	var t := clampf((airspeed - stall) / maxf(0.1, full_speed - stall), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Lift (N) along body up: speed-squared on forward airspeed only, scaled by stall
## fraction and hard-capped.
static func lift_force(airspeed: float, coeff: float, cap: float, fraction: float) -> float:
	var v := maxf(airspeed, 0.0)
	return minf(coeff * v * v, cap) * clampf(fraction, 0.0, 1.0)


## Flow angle (rad) of a body-frame velocity component against forward speed: angle of attack
## for the (negated) up component, sideslip for the right one. Zero without forward flow so a
## standstill or a tail-slide has no weathervane and no AoA lift.
static func flow_angle(cross: float, forward: float) -> float:
	if forward <= 0.5:
		return 0.0
	return atan2(cross, forward)


## Angle-of-attack lift factor: 1 at zero AoA, linear in the angle, clamped to [0, max]. Negative
## AoA can take the lift to zero, never below (no inverted lift).
static func aoa_factor(aoa: float, slope: float, max_factor: float) -> float:
	return clampf(1.0 + slope * aoa, 0.0, max_factor)


## Weathervane torque (N*m) restoring a flow angle toward zero: -angle * stiffness * speed^2,
## hard-capped. Sign is the restoring one for a torque about the axis the angle is measured
## against (body right for AoA, body up for sideslip).
static func weathervane_torque(angle: float, airspeed: float, stiffness: float,
		max_torque: float) -> float:
	var v := maxf(airspeed, 0.0)
	return clampf(-angle * stiffness * v * v, -max_torque, max_torque)


## Control authority 0..1: no airflow = no control. No prop wash term (tail sits outside
## the prop stream), unlike the boat's rudder_authority.
static func control_authority(airspeed: float, speed_ref: float) -> float:
	return VehicleMath.flow_authority(airspeed, speed_ref)


## Pitch torque: elevator command scaled by authority plus a damper on pitch rate,
## hard-capped. + = nose up (about body right).
static func pitch_torque(elevator: float, gain: float, authority: float, pitch_rate: float,
		damping: float, moment: float, delta: float, max_torque: float) -> float:
	var torque := elevator * gain * clampf(authority, 0.0, 1.0) \
			+ VehicleMath.damped_force(pitch_rate, damping, moment, delta)
	return clampf(torque, -max_torque, max_torque)


## Roll torque: spring toward the commanded bank angle (degrees, + = right side down)
## scaled by authority, plus a damper on roll rate, hard-capped. Applied about body
## forward, where + rolls the right side down.
static func roll_torque(target_deg: float, current_deg: float, stiffness: float,
		authority: float, roll_rate: float, damping: float, moment: float, delta: float,
		max_torque: float) -> float:
	var torque := deg_to_rad(target_deg - current_deg) * stiffness * clampf(authority, 0.0, 1.0) \
			+ VehicleMath.damped_force(roll_rate, damping, moment, delta)
	return clampf(torque, -max_torque, max_torque)


## Nose-down stall torque (N*m, about body right): zero with full lift, full gain with none.
static func stall_torque(lift_fraction: float, gain: float) -> float:
	return -(1.0 - clampf(lift_fraction, 0.0, 1.0)) * gain
