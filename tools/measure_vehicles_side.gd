extends RefCounted
## `measure_vehicles`' side pass (`side`, instead of every other pass): the tool spawns each body
## and hands it here (`start`, then `tick` every physics tick).
## The body laid at rest off its wheels: at each of SIDE_ROLLS (deg about its nose: its left side,
## its right side, its roof) its hull SIDE_CLEAR over the strip, engine running in D with the pedals
## up. SIDE_SETTLE_S, then SIDE_LOG_S read every tick. Per wheel (a coupled towed body's too, `T<n>`):
## the share of ticks in contact and how often that flips, the contact normal's mean part along its
## body's up and along the axle, the compression's range, the peak spring force and spin. Per rig:
## the unit's tilt, the peak speeds, and how often `hill_holding`, the front axle's `driven`, the ABS
## and TC lamps and the dust flip. `trace` prints the ticks.

const MeasureRig := preload("res://tools/measure_rig.gd")

const SIDE_ROLLS: Array[float] = [90.0, -90.0, 180.0]
const SIDE_CLEAR := 0.02           ## m
const SIDE_SETTLE_S := 2.0
const SIDE_LOG_S := 5.0

var _start_z := 0.0                   ## the strip's spawn z
var _trace := false                   ## print every logged tick
var _restart: Callable                ## the tool's pass reset, after each respawn
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _sd_rolls: Array[float] = []      ## SIDE_ROLLS still to run, this body
var _sd_roll := 0.0                   ## the roll in progress, deg
var _sd_overlaps := 0                 ## `RayWheel.start_overlaps` as the log began
var _sd_ticks := 0                    ## ticks logged
var _sd_wheels: Array[Dictionary] = [] ## per wheel, the log's sums (`_side_wheel`)
var _sd_flags := {}                   ## flag -> [ticks on, flips, last]
var _sd_peak := Vector3.ZERO          ## peak linear (x) and angular (y) speed, tilt summed (z)


func _init(start_z: float, trace: bool, restart: Callable, finish: Callable) -> void:
	_start_z = start_z
	_trace = trace
	_restart = restart
	_finish = finish


## The laid-over holds on `car`, headed `title` ("<variant> (<drive>)").
func start(car: BaseVehicle, title: String, _current: Dictionary) -> void:
	_car = car
	_sd_rolls = SIDE_ROLLS.duplicate()
	print("=== %s, side ===" % title)
	_next_side_roll()


func _next_side_roll() -> void:
	if _sd_rolls.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish.call()
		return
	_sd_roll = _sd_rolls.pop_front()
	var laid := Basis(Vector3.BACK, deg_to_rad(_sd_roll))
	MeasureRig.place(_car, Transform3D(laid,
			Vector3(0.0, SIDE_CLEAR - _hull_lowest(laid), _start_z)))
	_car.respawn()
	_restart.call()
	_sd_ticks = 0
	MeasureRig.drive(0.0, 0.0)


## The lowest point (m, <= 0) of the body's own collision shapes about its origin, turned by `turn`.
func _hull_lowest(turn: Basis) -> float:
	var low := 0.0
	for child in _car.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var box := cs.shape.get_debug_mesh().get_aabb()
		for i in 8:
			low = minf(low, (turn * (cs.transform * box.get_endpoint(i))).y)
	return low


func _side_wheel() -> Dictionary:
	return {"contact": 0, "flips": 0, "last": false, "up": 0.0, "axle": 0.0, "lo": INF, "hi": -INF,
			"force": 0.0, "omega": 0.0, "abs": 0, "tcs": 0}


func _side_flag(flag: String, on: bool) -> void:
	var row: Array = _sd_flags.get(flag, [0, 0, on])
	row[0] += int(on)
	row[1] += int(on != row[2])
	row[2] = on
	_sd_flags[flag] = row


## One physics tick, `t` s into the hold (the tool's pass clock).
func tick(_delta: float, t: float) -> void:
	if t < SIDE_SETTLE_S:
		return
	# The unit's wheels, then a coupled towed body's: each read in its own body's frame.
	var towed := MeasureRig.towed(_car)
	var wheels: Array[RayWheel] = _car.drive.wheels.duplicate()
	var own := wheels.size()
	if towed != null:
		wheels.append_array(towed.wheels)
	if _sd_ticks == 0:
		_sd_overlaps = RayWheel.start_overlaps
		_sd_wheels = []
		for i in wheels.size():
			var fresh := _side_wheel()
			fresh["label"] = MeasureRig.wheel_label(_car, wheels[i]) if i < own else "T%d" % (i - own)
			_sd_wheels.append(fresh)
		_sd_flags = {}
		_sd_peak = Vector3.ZERO
	_sd_ticks += 1
	var b := _car.global_transform.basis
	var any_abs := false
	var any_tcs := false
	var cells := PackedStringArray()
	for i in mini(wheels.size(), _sd_wheels.size()):
		var w := wheels[i]
		var row := _sd_wheels[i]
		var frame := b if i < own else towed.global_transform.basis
		var up := w.contact_normal.dot(frame.y)
		var axle := w.contact_normal.dot(frame.x)
		if _sd_ticks > 1 and w.in_contact != row["last"]:
			row["flips"] += 1
		row["last"] = w.in_contact
		if w.in_contact:
			row["contact"] += 1
			row["up"] += up
			row["axle"] += absf(axle)
		row["lo"] = minf(row["lo"], w.compression)
		row["hi"] = maxf(row["hi"], w.compression)
		row["force"] = maxf(row["force"], w.suspension_force)
		row["omega"] = maxf(row["omega"], absf(w.omega))
		row["abs"] += int(w.abs_active)
		row["tcs"] += int(w.tcs_active)
		any_abs = any_abs or w.abs_active
		any_tcs = any_tcs or w.tcs_active
		cells.append("%s %s" % [row["label"], ("c%.3f F%.0f n.up %+.2f n.ax %+.2f"
				% [w.compression, w.suspension_force, up, axle]) if w.in_contact else "-"])
	var input := InputRouter.get_vehicle_input()
	var front_driven := false
	for w in _car.drive.wheels:
		if not w.is_rear:
			front_driven = w.driven
			break
	var dust: GPUParticles3D = _car.drive.get("_dust")
	_side_flag("hill_holding", _car.drive.hill_holding)
	_side_flag("front driven", front_driven)
	if _car.telemetry is TractorTelemetry:
		_side_flag("fwd_drive_state", (_car.telemetry as TractorTelemetry).fwd_drive_state)
	_side_flag("abs", any_abs)
	_side_flag("tcs", any_tcs)
	_side_flag("dust", dust != null and dust.emitting)
	_side_flag("overturned", _car.is_overturned())
	var tilt := rad_to_deg(b.y.angle_to(Vector3.UP))
	_sd_peak.x = maxf(_sd_peak.x, _car.linear_velocity.length())
	_sd_peak.y = maxf(_sd_peak.y, _car.angular_velocity.length())
	if towed != null:
		_sd_peak.x = maxf(_sd_peak.x, towed.linear_velocity.length())
		_sd_peak.y = maxf(_sd_peak.y, towed.angular_velocity.length())
	_sd_peak.z += tilt
	if _trace:
		print("    t %.3f tilt %.1f v %.3f w %.3f pedal %.2f fd %d | %s" % [t - SIDE_SETTLE_S, tilt,
				_car.linear_velocity.length(), _car.angular_velocity.length(),
				_car.drive.foot_pedal(input), int(front_driven), " | ".join(cells)])
	if t >= SIDE_SETTLE_S + SIDE_LOG_S:
		_report_side()
		_next_side_roll()


func _report_side() -> void:
	var n := float(_sd_ticks)
	print("  roll %+.0f deg: rests at %.1f deg tilt; peak %.3f m/s, %.3f rad/s; %d cast start overlaps"
			% [_sd_roll, _sd_peak.z / n, _sd_peak.x, _sd_peak.y,
			RayWheel.start_overlaps - _sd_overlaps])
	for i in _sd_wheels.size():
		var row := _sd_wheels[i]
		var c := maxf(float(row["contact"]), 1.0)
		print(("    %-3s contact %3.0f %% (%.1f flips/s), n.up %+.2f, |n.axle| %.2f, compression"
				+ " %.3f..%.3f m, peak %.0f N, %.1f rad/s, abs %d tcs %d ticks") % [
				row["label"], 100.0 * row["contact"] / n,
				row["flips"] / SIDE_LOG_S, row["up"] / c, row["axle"] / c, row["lo"], row["hi"],
				row["force"], row["omega"], row["abs"], row["tcs"]])
	var parts := PackedStringArray()
	for flag: String in _sd_flags:
		var row: Array = _sd_flags[flag]
		parts.append("%s %.0f %% (%.1f flips/s)" % [flag, 100.0 * row[0] / n, row[1] / SIDE_LOG_S])
	print("    " + ", ".join(parts))
