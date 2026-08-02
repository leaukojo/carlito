class_name PlaneVehicle
extends BaseVehicle
## Light aircraft (CANaerospace flavor). A real BaseVehicle subclass (like the boat and
## drone) because it owns the prop/lift/control-surface locomotion module the wheeled
## base has no concept of. It never forks _physics_process — it plugs into the two base
## seams (_make_telemetry, _tick_extras). The three RayWheels (steered nose wheel, two
## mains) come straight from the spec, so ground roll, runway takeoff and wheel braking
## are the base's own physics; the wheels are UNDRIVEN — all propulsion is prop thrust.
##
## Locomotion (arcade): prop thrust from a modeled prop rpm that chases throttle (spool
## lag; the published rpm IS the number the thrust is computed from — rule 3); speed-
## squared lift along body up that fades below stall speed (simplified stall: lift dies,
## the nose drops — no spin model); air drag; control torques whose authority scales
## with airspeed (no authority at standstill, the boat's rudder rule). Steer is a
## coordinated roll+yaw blend: it commands a bank angle the roll spring chases (wings
## self-level on release) plus a yaw rate. R/F = elevator, B toggles flaps.
##
## Every force term is a pure static fn carrying the RayWheel/boat one-tick clamp
## discipline (60 Hz locked tick): a damper may at most zero the velocity it opposes in
## one tick (never reverse it), and totals are hard-capped. Unit-tested in
## tests/test_plane.gd. DO NOT remove or weaken any clamp; DO NOT raise the tick.
##
## Flight tuning lives here as node knobs (boat/drone precedent); body tuning (mass,
## wheels, brakes, the rpm band the prop model runs in) is plane_spec.tres.
## Wheel visuals bind by SPEC ORDER to WHEEL_VISUAL_NAMES: index 0 = nose = "WheelFL",
## 1 = left main = "WheelFR", 2 = right main = "WheelRL" (the base's car naming, reused).

@export_group("Propulsion")
@export var max_thrust := 9000.0        ## N at redline prop rpm (hard cap by construction)
@export var reverse_thrust_frac := 0.25 ## reverse (beta) thrust fraction for taxiing back
@export var prop_spool_rate := 3500.0   ## rpm/s the prop chases the throttle target (spool lag)

@export_group("Aero")
@export var lift_coeff := 13.0          ## N per (m/s)^2 of forward airspeed, flaps retracted
@export var lift_cap := 16000.0         ## N hard cap on total lift (~2 g)
@export var stall_speed := 13.0         ## m/s below which lift is fully gone
@export var full_lift_speed := 20.0     ## m/s at which the lift fraction reaches 1
@export var drag_coeff := 200.0         ## N per m/s of speed (sets top speed vs thrust)
@export var flap_lift_bonus := 4.0      ## extra lift_coeff at full flaps
@export var flap_drag_bonus := 40.0     ## extra drag_coeff at full flaps
@export var flap_slew_rate := 0.4       ## flap travel fraction per second (contract flaps_actual)

@export_group("Control")
@export var authority_speed_ref := 15.0 ## m/s of airflow that gives full control authority
@export var pitch_gain := 12000.0       ## N*m at full elevator + full authority
@export var pitch_damping := 9000.0     ## N*m per rad/s of pitch rate (gain/damping = max pitch rate)
@export var max_pitch_torque := 12000.0 ## N*m cap on the total pitch torque
@export var max_bank_deg := 45.0        ## bank angle commanded at full steer
@export var roll_stiffness := 9000.0    ## N*m per rad of bank error
@export var roll_damping := 3000.0      ## N*m per rad/s of roll rate
@export var max_roll_torque := 9000.0   ## N*m cap on the total roll torque
@export var max_yaw_rate := 0.9         ## rad/s commanded at full steer + full authority
@export var yaw_gain := 6000.0          ## N*m per rad/s of yaw-rate error
@export var max_yaw_torque := 7000.0    ## N*m cap on the yaw torque
@export var stall_pitch_gain := 6000.0  ## N*m of nose-down torque at full stall (airborne)

@export_group("Surface visuals")
@export var elevator_deflect_deg := 20.0 ## elevator travel at full command
@export var rudder_deflect_deg := 25.0   ## rudder travel at full steer
@export var aileron_deflect_deg := 18.0  ## aileron travel at full steer (differential)
@export var flap_deflect_deg := 30.0     ## flap travel at full extension (down only)
@export var elevator_slew_rate := 3.0    ## visual elevator travel per second
## Prop rpm above which the two blades are swapped for the translucent disc — the classic
## readable cheat for a prop turning far faster than 60 fps can show. Below it the blades
## stay, and their contrasting AccentMat tips carry the spin.
@export var prop_disc_rpm := 4000.0

## Body footprint (m), used only to derive the representative moment of inertia the
## one-tick torque clamps need — the drone's clamp basis, the boat's probe-span role.
@export var body_extents := Vector3(7.0, 1.5, 5.5)

## Visual prop spin: shaft rad/s per prop rpm — a cosmetic ratio far below the real rev
## rate (which would alias to a shimmer at 60 fps); the honest number stays the published
## rpm, the spinning blade is just its readable stand-in (the tractor rotor precedent).
const PROP_VISUAL_SPIN := 0.012

var _prop_rpm := 0.0   ## modeled prop rpm the thrust is computed from (published as rpm)
var _flap_pos := 0.0   ## 0..1 actual flap extension, slewed toward the request
var _inertia := 5000.0 ## representative moment (kg*m^2) for the one-tick torque clamps
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


## Cosmetic only: spin the prop blade from the modeled rpm and deflect the control
## surfaces from the commands the flight model already acted on (visuals in _process,
## physics untouched — the tractor implement's rotor pattern). A deflection NEVER feeds
## back into a force or torque: the flight model is the authority on motion and the
## surfaces are its readable stand-in, exactly as the blade is the published rpm's.
##
## Every pivot is a bare Node3D on the hinge line with its mesh child offset behind it,
## so a rotation about the pivot's own axis is the whole animation. Signs: local -Z is
## forward, so the trailing edge sits at +Z; rotating +X drives it DOWN, rotating +Y
## drives it RIGHT. Assignment is absolute — rotate_* would accumulate and drift.
func _process(delta: float) -> void:
	_prop.rotate_z(_prop_rpm * PROP_VISUAL_SPIN * delta)
	# Past disc rpm the blades read as a disc; the spinner keeps turning either way. The
	# disc still rotates with the prop, which costs nothing and keeps the swap invisible.
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


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as PlaneTelemetry
	var body := global_transform.basis
	var fwd := -body.z
	var right := body.x
	var up := body.y

	# Prop: rpm chases the throttle target (0 with the key off — engine stopped), thrust
	# derives FROM that rpm so the published number is the one that produced the motion.
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

	# Lift + drag. Lift rides forward airspeed only (a flat fall generates none) and
	# fades to zero below stall speed; drag opposes the whole velocity, one-tick clamped.
	var v_fwd := linear_velocity.dot(fwd)
	var frac := lift_frac(v_fwd, stall_speed, full_lift_speed)
	apply_central_force(up * lift_force(v_fwd, lift_coeff + flap_lift_bonus * _flap_pos,
			lift_cap, frac))
	apply_central_force(VehicleMath.clamped_damper(linear_velocity,
			drag_coeff + flap_drag_bonus * _flap_pos, spec.mass, delta))

	# Control surfaces: authority scales with airflow (none at standstill).
	var auth := control_authority(v_fwd, authority_speed_ref)
	# Visual-only mirror of the pitch command for _process; the torque below still reads
	# the raw input, so the animation cannot drift the flight model.
	_elevator_cmd = clampf(input.elevator, -1.0, 1.0)
	# Elevator: + = nose up = +torque about body right. Damper on the pitch rate.
	apply_torque(right * pitch_torque(clampf(input.elevator, -1.0, 1.0), pitch_gain, auth,
			angular_velocity.dot(right), pitch_damping, _inertia, delta, max_pitch_torque))
	# Steer -> coordinated bank + yaw. steer + = right; roll + = right side down and
	# +torque about body FORWARD rolls right-side-down, so the spring needs no sign flip.
	# The spring always acts (authority scales it), so wings self-level on release.
	apply_torque(fwd * roll_torque(_steer * max_bank_deg, VehicleMath.roll_deg(body), roll_stiffness,
			auth, angular_velocity.dot(fwd), roll_damping, _inertia, delta, max_roll_torque))
	# Yaw rate toward the commanded rate about body up. steer negative = left; +Y torque
	# yaws left, so the sign flips (the boat's rudder convention).
	apply_torque(up * VehicleMath.yaw_torque(-_steer * max_yaw_rate * auth, angular_velocity.dot(up),
			yaw_gain, _inertia, delta, max_yaw_torque))

	# Simplified stall, airborne only: as lift fades the nose is pushed down, so losing
	# speed reads as the nose dropping (recover by diving), never a spin.
	if _airborne():
		apply_torque(right * stall_torque(frac, stall_pitch_gain))

	# Telemetry: attitude/altitude/vspeed straight from the sim; rpm is the prop model
	# (honest-model latitude, labelled — see PlaneTelemetry); flaps as applied.
	t.rpm = _prop_rpm
	t.pitch = VehicleMath.pitch_deg(body)
	t.roll = VehicleMath.roll_deg(body)
	t.altitude = global_position.y
	t.vspeed = linear_velocity.y
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

## Prop rpm chasing its target at a fixed spool rate (rpm/s) — the boat trim_step
## pattern. The caller picks the target (idle..redline from throttle; 0 with the key off).
static func prop_rpm_step(current: float, target: float, rate: float, delta: float) -> float:
	return move_toward(current, target, rate * delta)


## 0..1 thrust fraction of the prop rpm within the engine band: idle = 0 (no residual
## creep thrust), redline = 1.
static func thrust_frac(rpm: float, idle_rpm: float, redline_rpm: float) -> float:
	return clampf((rpm - idle_rpm) / maxf(1.0, redline_rpm - idle_rpm), 0.0, 1.0)


## Signed prop thrust (N) along body forward. Magnitude comes FROM the modeled rpm
## (rule 3: the published rpm is the number that produced the motion), capped at
## thrust_cap by construction; the gear byte owns direction (D forward, R a weak
## reverse/beta fraction for taxiing, N none — the boat's gear-owns-direction rule).
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


## Cosmetic surface deflection (rad) for a -1..1 command: + = trailing edge down (about a
## pivot's local X) or right (about local Y). Clamped so an out-of-range command can never
## hinge a surface past its authored travel.
static func deflect_rad(cmd: float, max_deg: float) -> float:
	return deg_to_rad(clampf(cmd, -1.0, 1.0) * max_deg)


## 0..1 lift fraction vs forward airspeed: 0 at/below stall speed, 1 at/above
## full_lift_speed, smoothstep between — the simplified stall curve.
static func lift_frac(airspeed: float, stall: float, full_speed: float) -> float:
	var t := clampf((airspeed - stall) / maxf(0.1, full_speed - stall), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Lift (N) along body up: speed-squared on FORWARD airspeed (never backward flight),
## scaled by the stall fraction and hard-capped (the max_suspension_force analogue).
static func lift_force(airspeed: float, coeff: float, cap: float, fraction: float) -> float:
	var v := maxf(airspeed, 0.0)
	return minf(coeff * v * v, cap) * clampf(fraction, 0.0, 1.0)


## Control authority 0..1: no airflow over the surfaces = no control (the boat's
## rudder_authority rule, without prop wash — the tail sits outside the prop stream).
static func control_authority(airspeed: float, speed_ref: float) -> float:
	return clampf(absf(airspeed) / maxf(0.1, speed_ref), 0.0, 1.0)


## Pitch torque: elevator command scaled by authority plus a one-tick-clamped damper on
## the pitch rate; the total is hard-capped. + = nose up (about body right).
static func pitch_torque(elevator: float, gain: float, authority: float, pitch_rate: float,
		damping: float, moment: float, delta: float, max_torque: float) -> float:
	var torque := elevator * gain * clampf(authority, 0.0, 1.0) \
			+ VehicleMath.damped_force(pitch_rate, damping, moment, delta)
	return clampf(torque, -max_torque, max_torque)


## Roll torque: spring toward the commanded bank angle (degrees, + = right side down)
## scaled by authority, plus a one-tick-clamped damper on the roll rate; hard-capped.
## Applied about body FORWARD, where + rolls the right side down — spring sign matches.
static func roll_torque(target_deg: float, current_deg: float, stiffness: float,
		authority: float, roll_rate: float, damping: float, moment: float, delta: float,
		max_torque: float) -> float:
	var torque := deg_to_rad(target_deg - current_deg) * stiffness * clampf(authority, 0.0, 1.0) \
			+ VehicleMath.damped_force(roll_rate, damping, moment, delta)
	return clampf(torque, -max_torque, max_torque)


## Nose-down stall torque (N*m, about body right — negative = nose down): zero with
## full lift, full gain with none. The hard cap is the gain itself by construction.
static func stall_torque(lift_fraction: float, gain: float) -> float:
	return -(1.0 - clampf(lift_fraction, 0.0, 1.0)) * gain
