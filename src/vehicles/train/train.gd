class_name TrainVehicle
extends BaseVehicle
## Electric consist on a rail spline. Loco is kinematic (gravity off); wagons are AnimatableBody3D
## followers. TrainSim handles consist forces; coupler/brake clamps are 60 Hz stable — don't
## weaken them. Reverser rides the gear byte (N/D/R). Rail Curve3D is duck-typed so the same
## code drives RailTrack and authoring RoadPath.

## Rail ribs stand this far above the centreline the curve traces (rail_profile rail_height),
## so the consist is lifted by it to rest the modelled wheels on the railhead.
const RAIL_TOP_LIFT := 0.12

# Per-car geometry, measured from the Kenney bullet GLBs at world scale 2.4 (index 0 = loco).
# Plain Array consts (a PackedFloat64Array literal is not a constant expression in GDScript).
const CAR_LENGTHS := [6.72, 6.24, 6.24, 6.24, 6.24]
const BOGIE_HALF := [1.2, 1.32, 1.32, 1.32, 1.32]
const COUPLER_GAP := 0.3   ## m of slack air between adjacent car bodies at rest

const GRADE_EPS := 1.0      ## m along the curve for the finite-difference grade sample
const DOOR_SPEED_EPS := 0.3 ## m/s below which a door-open request is honored

# Aux-model tuning (honest models, clearly labelled — no real electrical/pneumatic circuit).
const AMPS_PER_NEWTON := 1.0 / 320.0  ## 320 kN tractive -> ~1000 A
const MAX_MOTOR_CURRENT := 1500.0
const CATENARY_SAG_PER_AMP := 2.0     ## V of line sag per amp (1000 A -> 2 kV droop)
const PIPE_APPLY_RANGE := 3.0         ## bar the pipe drops at full brake (5 -> 2, below the 2.5 warn)
const PIPE_DROP_RATE := 6.0           ## bar/s venting on application
const PIPE_CHARGE_RATE := 1.5         ## bar/s recharging on release

@export var loco_mass := 50000.0   ## kg (the powered head)
@export var wagon_mass := 34000.0  ## kg per trailer

var _sim: TrainSim
var _has_rail := false
var _curve: Curve3D
var _rail_xform := Transform3D.IDENTITY
var _rail_closed := false
var _rail_length := 0.0
var _wagons: Array[Node3D] = []
var _prev_heading := 0.0
var _brake_pipe := TrainTelemetry.BRAKE_PIPE_CHARGED


func _make_telemetry() -> VehicleTelemetry:
	return TrainTelemetry.new()


## Whole consist excluded from the chase camera's occlusion ray, so a rear/overhead view
## isn't yanked into the trailing wagons.
func get_camera_exclude_bodies() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	for w in _wagons:
		if w is PhysicsBody3D:
			out.append((w as PhysicsBody3D).get_rid())
	return out


## Loco is 6.7 m long, 3.9 m tall, with four wagons behind it: pull the chase view back and
## up to clear the consist, widen the overhead/iso frames.
func get_camera_framing() -> Dictionary:
	return {"distance": 16.0, "height": 9.0, "look_height": 2.5, "top_height": 60.0, "iso_size": 64.0}


func _ready() -> void:
	super._ready()
	gravity_scale = 0.0  # the sim owns vertical position; no free fall
	for child in get_children():
		if String(child.name).begins_with("Wagon") and child is Node3D:
			_wagons.append(child as Node3D)
	var rail := _find_rail()
	if rail != null:
		_curve = rail.call("get_rail_curve")
		_rail_xform = rail.call("rail_to_world")
		_rail_closed = bool(rail.call("is_rail_closed"))
		_rail_length = _curve.get_baked_length()
		_has_rail = _curve != null and _rail_length > 0.0
	if _has_rail:
		_build_sim()
		_place_consist()


## Reset the consist onto its loop at s = 0 with zeroed motion.
func respawn() -> void:
	super.respawn()
	_brake_pipe = TrainTelemetry.BRAKE_PIPE_CHARGED
	if _has_rail:
		_place_consist()


func _tick_extras(input: VehicleInput, delta: float) -> void:
	if not _has_rail:
		return
	var t := telemetry as TrainTelemetry

	# Traction is live only with the key in Ignition and the pantograph raised.
	var powered := input.key == InputRouter.KEY_IGNITION and input.pantograph
	var throttle := input.throttle if powered else 0.0

	# Per-car grade from the curve tangent, then advance the consist.
	var grades := PackedFloat64Array()
	grades.resize(_sim.s.size())
	for i in _sim.s.size():
		grades[i] = _grade_at(_sim.s[i])
	_sim.step(delta, throttle, input.brake, input.handbrake, grades)

	# Drive the loco body kinematically from the sim, then pose the wagons.
	var pose := TrainPlacement.car_pose(_curve, _rail_xform, _sim.s[0], BOGIE_HALF[0],
			_rail_closed, _rail_length, RAIL_TOP_LIFT)
	global_transform = pose
	var forward := -pose.basis.z
	linear_velocity = forward * _sim.v[0]
	var heading := atan2(forward.x, forward.z)
	angular_velocity = Vector3.UP * (wrapf(heading - _prev_heading, -PI, PI) / delta)
	_prev_heading = heading
	_pose_wagons()

	# Aux models, honest and labelled: current from traction, line sag from current, brake
	# pipe venting on application; grade/coupler read straight from the sim.
	var traction := TrainSim.tractive_effort(_sim.v[0], throttle, _sim.base_speed,
			_sim.max_tractive, _sim.max_power)
	t.motor_current = TrainTelemetry.motor_current_amps(traction, AMPS_PER_NEWTON, MAX_MOTOR_CURRENT)
	t.catenary_volts = TrainTelemetry.catenary_volts_model(t.motor_current,
			TrainTelemetry.NOMINAL_CATENARY if powered else 0.0, CATENARY_SAG_PER_AMP)
	_brake_pipe = TrainTelemetry.brake_pipe_step(_brake_pipe, input.brake, delta,
			PIPE_DROP_RATE, PIPE_CHARGE_RATE, PIPE_APPLY_RANGE)
	t.brake_pipe = _brake_pipe
	t.grade = clampi(roundi(grades[0] * 100.0), -10, 10)  # contract i8 %-grade range
	t.coupler_force = _sim.head_coupler_force / 1000.0  # N -> kN (contract unit)
	t.pantograph_state = powered
	t.doors_state = input.doors and absf(telemetry.speed) < DOOR_SPEED_EPS


# --- consist setup / placement ---------------------------------------------------------------


func _build_sim() -> void:
	_sim = TrainSim.new()
	var n := CAR_LENGTHS.size()
	var m := PackedFloat64Array()
	var gaps := PackedFloat64Array()
	m.resize(n)
	for i in n:
		m[i] = loco_mass if i == 0 else wagon_mass
		if i < n - 1:
			gaps.append((CAR_LENGTHS[i] + CAR_LENGTHS[i + 1]) * 0.5 + COUPLER_GAP)
	_sim.setup(m, gaps, _rail_length, _rail_closed, 0.0)


## Re-lay the consist at s = 0 with zeroed motion, then snap every car onto its arc position
## (spawn / respawn). Re-runs the sim layout so respawn returns to the loop start rather
## than halting where it had drifted to.
func _place_consist() -> void:
	_sim.setup(_sim.masses, _sim.rest_gaps, _rail_length, _rail_closed, 0.0)
	var pose := TrainPlacement.car_pose(_curve, _rail_xform, _sim.s[0], BOGIE_HALF[0],
			_rail_closed, _rail_length, RAIL_TOP_LIFT)
	global_transform = pose
	spawn_transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_heading = atan2((-pose.basis.z).x, (-pose.basis.z).z)
	_pose_wagons()
	reset_physics_interpolation()


func _pose_wagons() -> void:
	for w in _wagons.size():
		var car := w + 1  # sim index 0 is the loco
		if car >= _sim.s.size():
			break
		_wagons[w].global_transform = TrainPlacement.car_pose(_curve, _rail_xform,
				_sim.s[car], BOGIE_HALF[car], _rail_closed, _rail_length, RAIL_TOP_LIFT)


## Track slope (rise/run) at arc position `s`, finite-differenced along the curve.
func _grade_at(s: float) -> float:
	var a := _rail_xform * _curve.sample_baked(_wrap(s - GRADE_EPS))
	var b := _rail_xform * _curve.sample_baked(_wrap(s + GRADE_EPS))
	var horiz := Vector2(b.x - a.x, b.z - a.z).length()
	return (b.y - a.y) / horiz if horiz > 0.0 else 0.0


func _wrap(s: float) -> float:
	if _rail_closed and _rail_length > 0.0:
		return fposmod(s, _rail_length)
	return s


# --- rail discovery (duck-typed, per the kit contract — never a class_name check) -----------


## The closed rail loop under this vehicle's level, or null. Requires a CLOSED loop — the same
## rule Level enforces before it spawns the train (RailTrack.find_closed_rail is that one shared
## walk); an open rail is never accepted, so the two code paths can't disagree. Works on the
## baked RailTrack and the unbaked authoring RoadPath alike.
func _find_rail() -> Node:
	return RailTrack.find_closed_rail(_level_root())
