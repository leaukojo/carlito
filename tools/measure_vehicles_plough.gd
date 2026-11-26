extends RefCounted
## `measure_vehicles`' draft pass (`plough`, instead of every other pass; `course` and `governor`
## are its variants): the tool spawns each body and hands it here (`start`, then `tick` every
## physics tick).

const MeasureRig := preload("res://tools/measure_rig.gd")
const Hitch := preload("res://tools/measure_vehicles_hitch.gd")

## The strip answers as level 1's field (`FieldStrip`), so draft acts. Per draft-relevant implement
## (`trailer=` names one; else each), lowered at rest for HITCH_WAIT_S, then each of PLOUGH_HOLDS
## held on the circle's PI pedal for PLOUGH_SETTLE_S and averaged over PLOUGH_AVG_S: the draft (N,
## `TractorVehicle.draft_applied`; the `draft_force` dial beside it) against its D497 figure at the speed held, `engine_load`,
## `wheel_slip`, `axle_load`, the front share, gear and rpm, and each rear tyre on the last tick
## (`_rear_contacts`). Then braked to a stop, held
## PLOUGH_STOP_S, and floored from rest for PLOUGH_START_S with the implement down: every shift as
## it lands, a trace line every PLOUGH_TRACE_S, and the hunting gate. With `trace[=n]` the start's
## first `trace_s=` seconds print a line every n ticks instead (`_plough_trace_line`).
## Per hold, km/h and the rear diff lock (1 in): a ploughing driver locks it. The open pair first:
## pushed from 3 to 7 on a saturated pedal, the lighter right rear (the plough's mass sits left)
## peels past the grip peak; an open diff already under the peak at 7 holds there.
const PLOUGH_HOLDS: Array[Vector2] = [Vector2(3.0, 0.0), Vector2(7.0, 0.0), Vector2(3.0, 1.0),
		Vector2(7.0, 1.0), Vector2(10.0, 1.0)]
const PLOUGH_SETTLE_S := 8.0
const PLOUGH_AVG_S := 3.0
const PLOUGH_STOP_S := 2.0
const PLOUGH_START_S := 15.0
const PLOUGH_TRACE_S := 0.5
## `plough course`: the strip answers as tractor_plough's course instead (`FieldStrip`), measured
## off the course scene and `gen_farm_playground.gd` by distance ahead of the course's Spawn: its
## light bands mix Field with Sand at LIGHT_SOIL_MIX. Per COURSE_RUNS entry (km/h, `hitch_pos`):
## respawned, the plough set at rest for HITCH_WAIT_S, then the PI pedal on a setpoint ramped at
## COURSE_RAMP to the run's speed, through the Row to its Exit: `engine_load` and the
## `draft_force` dial, mean, least and most inside the Row on full soil and on a band (the soil at
## the hitch point; telemetry lags it a tick), each extreme's distance into the Row, gear and rpm;
## every shift in the Row.
## `plough governor`: the all-speed governor's hold (`PedalMap.Kind.ALL_SPEED`), per implement: the
## hand throttle at the PTO preset (`TractorTelemetry.pto_hand_throttle`), the PTO engaged in 540,
## the bridge's manual box. Parked in N for HITCH_WAIT_S raised, then lowered (the PTO's onset at
## rest); then in GOV_GEAR (`gear=` another) on the foot pedal's go request GOV_GO_PEDAL, under the
## hand: raised for GOV_RAISED_S, then lowered for GOV_LOWERED_S, the draft and the PTO's power
## coming on together. A line every GOV_LINE_S over the onset's first GOV_FINE_S, then every second:
## km/h, rpm against the setting and the droop under it, `pto_rpm`, `engine_load`, the dial. The
## last GOV_AVG_S averaged, with the `droop` gate: the shaft at or over its named speed less the
## spec's droop (`540 / (1 + droop)`).
const GOV_GEAR := 2                ## D2: ~8 km/h at the 540 preset, a harrow's working speed
const GOV_GO_PEDAL := 0.05
## A CVT's working speed under the governor (its pedal commands ground speed): D2's at the preset.
const GOV_CVT_KMH := 8.0
const GOV_RAISED_S := 10.0
const GOV_LOWERED_S := 15.0
const GOV_FINE_S := 3.0
const GOV_LINE_S := 0.25
const GOV_AVG_S := 3.0
const COURSE_SCENE := "res://src/levels/island/level_1/courses/tractor_plough_course.tscn"
const FarmPlayground := preload("res://tools/gen_farm_playground.gd")
const COURSE_RUNS: Array[Vector2] = [Vector2(3.0, 0.0), Vector2(5.0, 0.0), Vector2(7.0, 0.0),
		Vector2(9.0, 0.0), Vector2(7.0, 100.0), Vector2(16.0, 100.0)]
const COURSE_RAMP := 0.5           ## m/s², the tractor's CRUISE_SETS ramp
const COURSE_TIMEOUT_S := 120.0

## Where a `plough` run is (`tick`).
enum Plough { LOWER, HOLD, STOP, START, COURSE_SET, COURSE_RUN, GOV_PARK_RAISED, GOV_PARK_LOWERED,
		GOV_RAISED, GOV_LOWERED }


## The strip as level 1's field for the `plough` pass, on what `BaseVehicle._collect_grip_terrains`
## and `TractorVehicle.soil_under` duck-type: `Surface.FIELD` at full weight everywhere. With `bands`
## (`plough course`), Field at `field` weight and Sand over the rest inside each band, by distance
## ahead of strip z `start_z` (the body faces -Z).
class FieldStrip extends Node:
	var start_z := 0.0
	var bands: Array[Vector2] = []
	var field := 1.0

	func ahead(p: Vector3) -> float:
		return start_z - p.z

	func field_at(p: Vector3) -> float:
		var s := ahead(p)
		for b in bands:
			if s >= b.x and s <= b.y:
				return field
		return 1.0

	func contains_xz(_p: Vector3) -> bool:
		return true

	func height_at(_p: Vector3) -> float:
		return 0.0

	func grip_at(p: Vector3, response: PackedFloat32Array) -> float:
		return lerpf(Surface.grip_in(response, Surface.SAND), Surface.grip_in(response, Surface.FIELD),
				field_at(p))

	func drag_at(p: Vector3) -> float:
		return lerpf(Surface.drag(Surface.SAND), Surface.drag(Surface.FIELD), field_at(p))

	func surface_weight_at(p: Vector3, surface: int) -> float:
		return field_at(p) if surface == Surface.FIELD else 0.0

var _start_z := 0.0                   ## the strip's spawn z
var _trailer := ""                    ## `trailer=`: the one implement to run, else each draft-relevant one
var _held_gear := 0                   ## `gear=`, or 0
var _trace := false                   ## the start's per-tick lines (`trace`)
var _trace_every := 1                 ## ticks between them
var _trace_s := 0.0                   ## s of them
var _restart: Callable                ## the tool's pass reset
var _finish: Callable                 ## the tool's end of this body
var _gate: Callable                   ## the tool's `_gate_line`
var _hunting: Callable                ## the tool's `_hunting_gate`
var _fail: Callable                   ## counts a FAIL in the tool's exit code
var _car: BaseVehicle
var _current := {}                    ## the tool's report entry for this body
var _t := 0.0                         ## s into the stage
var _pl_ids: Array[String] = []       ## draft implements still to run, this body
var _pl_stage := Plough.LOWER
var _pl_speed := 0                    ## index into PLOUGH_HOLDS
var _pl_hold: MeasureRig.PiHold       ## the PI pedal
var _pl_sums := {}                    ## the hold's figures summed (`tick`)
var _pl_rating := 0.0                 ## N, the implement's `draft_rating()`
var _pl_shape := Vector4.ZERO         ## its `draft_shape()`
var _pl_shifts: Array = []            ## the standing start's shifts (`MeasureRig.shift_record`)
var _pl_gear := -1                    ## gear byte at the last tick, to catch a shift
var _pl_trace_t := 0.0                ## s of the start at the next trace line
var _pl_moving_t := -1.0              ## s into the start the body first passed 0.5 km/h
var _pl_ticks := 0                    ## ticks into the start, for `trace=n`
var _pl_peak_slip := 0.0              ## the grip curve's peak slip, every hold and trace (`_rear_contacts`)
## `plough pto`: the PTO engaged throughout, in the 1000 mode the harrow trials ran; the parked
## line and each hold print its load on the crank (`Drivetrain.accessory_torque`).
var _pto := false
## `plough diff` / `plough mfwd`: the rear diff lock / MFWD engaged throughout (`_plough_extra`).
var _diff_lock := false
var _mfwd := false
## `plough course`: run the course instead of the held speeds and the start.
var _course := false
## `plough governor`: run the governor's hold instead of the held speeds and the start.
var _governor := false
var _gv_line_t := 0.0                 ## s into the stage at the next printed line
var _gv_sums := {}                    ## the lowered hold's last GOV_AVG_S, summed
var _co_strip: FieldStrip
var _co_row := Vector2.ZERO           ## the Row, m ahead of the course's Spawn
var _co_id := ""                      ## the implement the course runs
var _co_runs: Array[Vector2] = []     ## COURSE_RUNS still to run, this body
var _co_run := Vector2.ZERO           ## this run's km/h and `hitch_pos`
var _co_set := 0.0                    ## the ramped setpoint, m/s
var _co_ext := {}                     ## "<signal>, <soil> soil" -> [least, at, most, at, sum, ticks]
var _co_shifts: Array[String] = []    ## shifts inside the Row
var _co_gear := -1


## Lays the strip under `tool` (the course's, with `course`) before the first body ticks: its wheels
## find the painted terrains once. `flags` are the run line's after the variants and the seconds.
func _init(tool: Node3D, flags: PackedStringArray, start_z: float, trailer: String, held_gear: int,
		trace: bool, trace_every: int, trace_s: float, hold: MeasureRig.PiHold, restart: Callable,
		finish: Callable, gate_line: Callable, hunting_gate: Callable, fail: Callable) -> void:
	_start_z = start_z
	_trailer = trailer
	_held_gear = held_gear
	_trace = trace
	_trace_every = trace_every
	_trace_s = trace_s
	_pl_hold = hold
	_restart = restart
	_finish = finish
	_gate = gate_line
	_hunting = hunting_gate
	_fail = fail
	_course = flags.has("course")
	_governor = flags.has("governor")
	_pto = flags.has("pto") or _governor
	_diff_lock = flags.has("diff")
	_mfwd = flags.has("mfwd")
	var strip := FieldStrip.new()
	if _course:
		_co_strip = strip
		_load_course(strip)
	tool.add_child(strip)


## The draft pass on `car`, headed `title` ("<variant> (<drive>)"): each draft-relevant implement in turn.
func start(car: BaseVehicle, title: String, current: Dictionary) -> void:
	_car = car
	_current = current
	_restart.call()
	_t = 0.0
	_pl_ids = []
	if not _car is TractorVehicle:
		print("=== %s: no three-point linkage, plough skipped ===" % String(_current["variant"]))
		_finish.call()
		return
	for id: String in _car.call(&"attachment_ids"):
		if not ImplementCatalog.is_attached(id) or ImplementCatalog.is_towed(id):
			continue
		var node := (load(id) as PackedScene).instantiate() as ImplementBase
		var draft := node.draft_relevant()
		node.free()
		if draft and (_trailer == "" or id.get_file().get_basename() == _trailer):
			_pl_ids.append(id)
	_pl_peak_slip = 0.0
	var peak := 0.0
	for pt in _car.spec.ground_drive.grip_curve:
		if pt.y > peak:
			peak = pt.y
			_pl_peak_slip = pt.x
	print("=== %s, draft on the field, dial 100 %% = %.2f kN ===" % [title,
			(_car as TractorVehicle).draft_max_force / 1000.0])
	_next_plough_implement()


## Respawn with the next implement on and lower it at rest, or finish the body.
func _next_plough_implement() -> void:
	if _pl_ids.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish.call()
		return
	var id: String = _pl_ids.pop_front()
	if _course:
		_co_id = id
		_co_runs = COURSE_RUNS.duplicate()
		_next_course_run()
		return
	if _governor:
		_start_governor_run(id)
		return
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), _start_z))
	_car.respawn()
	_car.call(&"set_attachment", id)
	var node := (load(id) as PackedScene).instantiate() as ImplementBase
	_pl_rating = node.draft_rating()
	_pl_shape = node.draft_shape()
	node.free()
	print("  %s: rated %.2f kN at %.0f km/h, D497 shape (%.0f, %.0f, %.1f) held above %.0f km/h;"
			% [id.get_file().get_basename(), _pl_rating / 1000.0, TractorTelemetry.DRAFT_S_REF_KMH,
			_pl_shape.x, _pl_shape.y, _pl_shape.z, _pl_shape.w]
			+ " g(0) %.2f" % TractorTelemetry.draft_speed01(0.0, _pl_shape))
	_pl_stage = Plough.LOWER
	_pl_speed = 0
	_pl_hold.integral = 0.0
	_t = 0.0
	_plough_drive(0.0, 100.0, true)


## A held speed's sums, zeroed (`tick`).
static func _plough_sums() -> Dictionary:
	var sums := {"gear": 0}
	for k: String in ["ticks", "v", "draft", "dial", "load", "slip", "axle", "front", "total", "rpm",
			"pedal", "pto"]:
		sums[k] = 0.0
	return sums


## The bridge stash for the pass: the linkage always at its bottom stop.
func _plough_drive(accel_pct: float, brake_pct: float, handbrake := false) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, handbrake, 1, false, 3, _plough_extra(0.0))


## The pass's ISOBUS requests: the linkage at `hitch_pos`; the rear diff lock under `diff`, on a
## locked PLOUGH_HOLDS entry and on the course (tractor_plough's hint locks it); MFWD under `mfwd`;
## the PTO under `pto` (in 1000, the harrow trials'; under `governor` in 540, with the hand
## throttle at the PTO preset).
func _plough_extra(hitch_pos: float) -> Dictionary:
	var extra := {"hitch_pos": hitch_pos,
			"diff_lock": _diff_lock or _course or _plough_hold_locked(), "fwd_drive": _mfwd}
	if _pto:
		extra.merge({"pto": true, "pto_mode": TractorTelemetry.PTO_MODE_540 if _governor
				else TractorTelemetry.PTO_MODE_1000})
	if _governor:
		extra["hand_throttle"] = TractorTelemetry.pto_hand_throttle(_car.spec) * 100.0
	return extra


## Whether the current PLOUGH_HOLDS entry holds with the rear diff lock in.
func _plough_hold_locked() -> bool:
	return _pl_stage == Plough.HOLD and PLOUGH_HOLDS[_pl_speed].y > 0.0


## One physics tick.
func tick(delta: float, _host_t: float) -> void:
	_t += delta
	var v_long := _car.linear_velocity.dot(-_car.global_transform.basis.z)
	var tel := _car.telemetry as TractorTelemetry
	if _pl_stage >= Plough.GOV_PARK_RAISED:
		_tick_governor(v_long, tel)
		return
	match _pl_stage:
		Plough.COURSE_SET:
			if _t < Hitch.HITCH_WAIT_S:
				return
			_pl_stage = Plough.COURSE_RUN
			_t = 0.0
		Plough.COURSE_RUN:
			_co_set = minf(_co_set + COURSE_RAMP * delta, _co_run.x / 3.6)
			var err := _co_set - v_long
			_course_drive(MeasureRig.pi_pedal(_car, _pl_hold.step(err, delta), _co_set) * 100.0, 0.0)
			var s := _co_strip.ahead(_car.global_position)
			if s > _co_row.y or _t > COURSE_TIMEOUT_S:
				_report_course_run(s)
				_next_course_run()
			elif s >= _co_row.x:
				_course_sample(s - _co_row.x, tel)
		Plough.LOWER:
			if _t < Hitch.HITCH_WAIT_S:
				return
			print("    parked, lowered: engine_load %d %%, %.0f rpm, fuel %.3f; PTO %s, %.1f N·m on the crank"
					% [tel.engine_load, _car.drivetrain.rpm, _car.drivetrain.applied_throttle,
					"%d rpm" % tel.pto_rpm if tel.pto_state else "off",
					_car.drivetrain.accessory_torque])
			_pl_stage = Plough.HOLD
			_t = 0.0
			_pl_sums = _plough_sums()
		Plough.HOLD:
			var err := PLOUGH_HOLDS[_pl_speed].x / 3.6 - v_long
			var pedal := MeasureRig.pi_pedal(_car, _pl_hold.step(err, delta),
					PLOUGH_HOLDS[_pl_speed].x / 3.6)
			_plough_drive(pedal * 100.0, 0.0)
			if _t < PLOUGH_SETTLE_S:
				return
			var axles := Vector2.ZERO
			for w in _car.wheels:
				if w.is_rear:
					axles.y += w.suspension_force
				else:
					axles.x += w.suspension_force
			_pl_sums["ticks"] += 1.0
			_pl_sums["v"] += v_long
			_pl_sums["draft"] += absf((_car as TractorVehicle).draft_applied)
			_pl_sums["dial"] += float(tel.draft_force)
			_pl_sums["load"] += float(tel.engine_load)
			_pl_sums["slip"] += float(tel.wheel_slip)
			_pl_sums["axle"] += tel.axle_load
			_pl_sums["front"] += axles.x
			_pl_sums["total"] += axles.x + axles.y
			_pl_sums["rpm"] += _car.drivetrain.rpm
			_pl_sums["pedal"] += pedal
			_pl_sums["pto"] += _car.drivetrain.accessory_torque
			_pl_sums["gear"] = _car.drivetrain.gear_byte
			if _t < PLOUGH_SETTLE_S + PLOUGH_AVG_S:
				return
			_report_plough_hold()
			_pl_speed += 1
			_t = 0.0
			_pl_sums = _plough_sums()
			if _pl_speed >= PLOUGH_HOLDS.size():
				_pl_stage = Plough.STOP
		Plough.STOP:
			_plough_drive(0.0, 100.0)
			if absf(v_long) > 0.05:
				_t = 0.0
			if _t < PLOUGH_STOP_S:
				return
			_pl_stage = Plough.START
			_t = 0.0
			_pl_shifts = []
			_pl_gear = _car.drivetrain.gear_byte
			_pl_trace_t = 0.0
			_pl_moving_t = -1.0
			_pl_ticks = 0
			print("    standing start, floored, implement down (from %s):" % MeasureRig.gear_label(_pl_gear))
			if _trace:
				print(("      trace: a line every %d tick(s) to %.1f s; c O(pen) S(lipping) L(ocked), ramp"
						+ " the start-up ramp, clutch its commanded capacity, Tc at the crank (N·m); per rear"
						+ " wheel the slip ratio, < / > the grip curve's rising / falling side of its %.2f"
						+ " peak, and Fx / Fz") % [_trace_every, _trace_s, _pl_peak_slip])
		Plough.START:
			_plough_drive(100.0, 0.0)
			var gear: int = _car.drivetrain.gear_byte
			if gear != _pl_gear:
				var s := MeasureRig.shift_record(_car, _t, _pl_gear, gear)
				_pl_shifts.append(s)
				print("      %5.2f s  %s" % [_t, MeasureRig.shifts_label([s])])
				_pl_gear = gear
			if _pl_moving_t < 0.0 and absf(v_long) * 3.6 > 0.5:
				_pl_moving_t = _t
			_pl_ticks += 1
			if _trace and _t < _trace_s:
				if (_pl_ticks - 1) % _trace_every == 0:
					print(_plough_trace_line(v_long))
				_pl_trace_t = _t + PLOUGH_TRACE_S
			elif _t >= _pl_trace_t:
				_pl_trace_t += PLOUGH_TRACE_S
				print("      %5.2f s  %4.1f km/h %s %4.0f rpm, draft %3d %%, wheel_slip %2d %%, engine_load %3d %%"
						% [_t, v_long * 3.6, MeasureRig.gear_label(gear), _car.drivetrain.rpm, tel.draft_force,
						tel.wheel_slip, tel.engine_load])
			if _t < PLOUGH_START_S:
				return
			print("      moving (0.5 km/h) at %s; %s" % ["%.2f s" % _pl_moving_t if _pl_moving_t >= 0.0
					else "never", MeasureRig.shifts_label(_pl_shifts) if not _pl_shifts.is_empty() else "no shift"])
			var hunt: Array = _hunting.call(_pl_shifts)
			_gate.call("hunting", hunt[0], hunt[1])
			_next_plough_implement()


## Respawn with `id` on, raised, parked in N on both brakes with the PTO in and the hand throttle at
## its preset, in the bridge's manual box (`governor`).
func _start_governor_run(id: String) -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), _start_z))
	_car.respawn()
	_car.call(&"set_attachment", id)
	InputRouter.set_manual_gearbox(true)
	var preset := TractorTelemetry.pto_hand_throttle(_car.spec)
	print("  %s: hand throttle %.1f %% (setting %.0f rpm, the PTO's rated %.0f), PTO 540, droop %.1f %%,"
			% [id.get_file().get_basename(), preset * 100.0, PedalMap.setting_rpm(_car.spec, preset),
			TractorTelemetry.PTO_RATED_RPM, _car.spec.governor_droop * 100.0]
			+ " the shaft's floor %.1f rpm" % _governor_floor())
	_pl_stage = Plough.GOV_PARK_RAISED
	_t = 0.0
	_governor_drive(0.0, 100.0, true, 100.0, 0)


## The shaft speed the `droop` gate holds it at or over: 540 less the spec's droop.
func _governor_floor() -> float:
	return 540.0 / (1.0 + _car.spec.governor_droop)


## The bridge stash for the governor's run: the linkage at `hitch_pos`, in `byte` (N at rest).
func _governor_drive(accel_pct: float, brake_pct: float, handbrake: bool, hitch_pos: float,
		byte: int) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, handbrake, byte, false, 3, _plough_extra(hitch_pos))


## The foot pedal under the hand throttle: the go request GOV_GO_PEDAL, or on a CVT the share of its
## top speed that commands GOV_CVT_KMH.
func _governor_pedal() -> float:
	if Drivetrain.is_cvt(_car.spec):
		return GOV_CVT_KMH / 3.6 / Drivetrain.cvt_top_speed(_car.spec)
	return GOV_GO_PEDAL


## The governor's working gear: `gear=`, else GOV_GEAR (on a CVT, the range it caps).
func _governor_gear() -> int:
	return _held_gear if _held_gear > 0 else GOV_GEAR


## One governor line: road speed, gear, the crank against the governor's setting and its droop,
## the PTO shaft, `engine_load` and the draft dial.
func _governor_line(v_long: float, tel: TractorTelemetry) -> String:
	var dt: Drivetrain = _car.drivetrain
	var setting := PedalMap.setting_rpm(_car.spec, dt.governor_demand)
	return ("%4.1f km/h %s %4.0f rpm (setting %4.0f, droop %4.1f %%), PTO %4d rpm, engine_load %3d %%,"
			+ " draft %3d %%") % [v_long * 3.6, MeasureRig.gear_label(dt.gear_byte), dt.rpm, setting,
			(setting - dt.rpm) / setting * 100.0, tel.pto_rpm, tel.engine_load, tel.draft_force]


func _tick_governor(v_long: float, tel: TractorTelemetry) -> void:
	match _pl_stage:
		Plough.GOV_PARK_RAISED, Plough.GOV_PARK_LOWERED:
			var lowered := _pl_stage == Plough.GOV_PARK_LOWERED
			_governor_drive(0.0, 100.0, true, 0.0 if lowered else 100.0, 0)
			if _t < Hitch.HITCH_WAIT_S:
				return
			print("    parked in N, %s: %s" % ["lowered" if lowered else "raised",
					_governor_line(v_long, tel)])
			_pl_stage = Plough.GOV_RAISED if lowered else Plough.GOV_PARK_LOWERED
			_t = 0.0
		Plough.GOV_RAISED:
			_governor_drive(_governor_pedal() * 100.0, 0.0, false, 100.0, _governor_gear())
			if _t < GOV_RAISED_S:
				return
			print("    working, raised:  %s" % _governor_line(v_long, tel))
			print("    lowered at %.0f s:" % GOV_RAISED_S)
			_pl_stage = Plough.GOV_LOWERED
			_t = 0.0
			_gv_line_t = 0.0
			_gv_sums = {"ticks": 0.0, "v": 0.0, "rpm": 0.0, "setting": 0.0, "pto": 0.0, "load": 0.0,
					"dial": 0.0}
		Plough.GOV_LOWERED:
			_governor_drive(_governor_pedal() * 100.0, 0.0, false, 0.0, _governor_gear())
			if _t >= _gv_line_t:
				print("      %5.2f s  %s" % [_t, _governor_line(v_long, tel)])
				_gv_line_t += GOV_LINE_S if _t < GOV_FINE_S else 1.0
			if _t >= GOV_LOWERED_S - GOV_AVG_S:
				var dt: Drivetrain = _car.drivetrain
				_gv_sums["ticks"] += 1.0
				_gv_sums["v"] += v_long
				_gv_sums["rpm"] += dt.rpm
				_gv_sums["setting"] += PedalMap.setting_rpm(_car.spec, dt.governor_demand)
				_gv_sums["pto"] += float(tel.pto_rpm)
				_gv_sums["load"] += float(tel.engine_load)
				_gv_sums["dial"] += float(tel.draft_force)
			if _t < GOV_LOWERED_S:
				return
			_report_governor()
			InputRouter.set_manual_gearbox(false)
			_next_plough_implement()


## The lowered hold's last GOV_AVG_S against the spec's droop: the `droop` gate.
func _report_governor() -> void:
	var s := _gv_sums
	var n: float = maxf(s["ticks"], 1.0)
	var setting: float = s["setting"] / n
	var rpm: float = s["rpm"] / n
	var pto: float = s["pto"] / n
	print("    held (last %.0f s): %.1f km/h, %.0f rpm, %.1f %% under the %.0f setting; PTO %.1f rpm;"
			% [GOV_AVG_S, s["v"] / n * 3.6, rpm, (setting - rpm) / setting * 100.0, setting, pto]
			+ " engine_load %.0f %%, draft %.0f %%" % [s["load"] / n, s["dial"] / n])
	var ok := pto >= _governor_floor() - 0.5
	if not ok:
		_fail.call()
	_gate.call("droop", ok, "PTO %.1f rpm against %.1f (540 less the %.0f %% droop)"
			% [pto, _governor_floor(), _car.spec.governor_droop * 100.0])
	if not _current.has("governor"):
		_current["governor"] = []
	(_current["governor"] as Array).append({"implement": String(_car.call(&"current_attachment"))
			.get_file().get_basename(), "kmh": s["v"] / n * 3.6, "rpm": rpm, "setting": setting,
			"pto_rpm": pto, "engine_load": s["load"] / n, "draft_pct": s["dial"] / n})


## One held speed's averages against D497 at the speed held (full depth, full soil).
func _report_plough_hold() -> void:
	var s := _pl_sums
	var n: float = maxf(s["ticks"], 1.0)
	var v: float = s["v"] / n
	var draft_n: float = s["draft"] / n
	var d497 := _pl_rating * TractorTelemetry.draft_speed01(v * 3.6, _pl_shape) \
			* clampf(absf(v) / TractorTelemetry.DRAFT_V_CRAWL, 0.0, 1.0)
	if not _current.has("plough"):
		_current["plough"] = []
	(_current["plough"] as Array).append({"implement": String(_car.call(&"current_attachment"))
			.get_file().get_basename(), "kmh": v * 3.6, "draft_n": draft_n, "d497_n": d497,
			"engine_load": s["load"] / n, "wheel_slip": s["slip"] / n, "axle_load": s["axle"] / n,
			"front_share": s["front"] / maxf(s["total"], 1e-6)})
	print(("    %4.1f km/h %s (held %4.1f): draft %.2f kN (D497 %.2f, %+.1f %%), dial %.0f %%; engine_load"
			+ " %.0f %%, wheel_slip %.1f %%, axle_load %.0f kg, front share %.1f %%; %s %.0f rpm,"
			+ " pedal %.2f%s") % [PLOUGH_HOLDS[_pl_speed].x,
			"locked" if _diff_lock or _plough_hold_locked() else "open  ", v * 3.6, draft_n / 1000.0,
			d497 / 1000.0,
			(draft_n / maxf(d497, 1.0) - 1.0) * 100.0, s["dial"] / n, s["load"] / n, s["slip"] / n,
			s["axle"] / n, s["front"] / maxf(s["total"], 1e-6) * 100.0, MeasureRig.gear_label(int(s["gear"])),
			s["rpm"] / n, s["pedal"] / n,
			"; PTO %.1f N·m on the crank" % (s["pto"] / n) if _pto else ""])
	var fx := 0.0
	for w in _car.wheels:
		fx += w.force_long
	print("      last tick: draft %.2f kN, every tyre's Fx %.2f kN | rears %s" % [
			absf((_car as TractorVehicle).draft_applied) / 1000.0, fx / 1000.0,
			"  ".join(_rear_contacts(true))])


## The course's Row and light bands as distances ahead of its Spawn, laid on `strip`.
func _load_course(strip: FieldStrip) -> void:
	var course := (load(COURSE_SCENE) as PackedScene).instantiate()
	var spawn := (course.get_node("Spawn") as Node3D).transform
	var row := course.get_node("Row") as ChallengeZone
	var row_z := Vector2(row.position.z - row.size.z * 0.5, row.position.z + row.size.z * 0.5)
	course.free()
	# The course runs along world z (its Spawn faces +z or -z); distance ahead of the Spawn.
	var dir := signf(-spawn.basis.z.z)
	var ahead := func(z: float) -> float: return (z - spawn.origin.z) * dir
	var a: float = ahead.call(row_z.x)
	var b: float = ahead.call(row_z.y)
	_co_row = Vector2(minf(a, b), maxf(a, b))
	strip.start_z = _start_z
	strip.field = 1.0 - FarmPlayground.LIGHT_SOIL_MIX
	var bands: Array[String] = []
	for band in FarmPlayground.LIGHT_SOIL_BANDS:
		a = ahead.call(band.x)
		b = ahead.call(band.y)
		strip.bands.append(Vector2(minf(a, b), maxf(a, b)))
		bands.append("%.0f-%.0f m" % [minf(a, b) - _co_row.x, maxf(a, b) - _co_row.x])
	print("course: tractor_plough's Row %.0f-%.0f m ahead of its Spawn; light bands %s into it, Field"
			% [_co_row.x, _co_row.y, ", ".join(bands)] + " %.2f (grip %.2f, drag %.3f), diff locked"
			% [strip.field,
			lerpf(Surface.ref_grip(Surface.SAND), Surface.ref_grip(Surface.FIELD), strip.field),
			lerpf(Surface.drag(Surface.SAND), Surface.drag(Surface.FIELD), strip.field)])


## The bridge stash for a course run: the linkage held at the run's `hitch_pos`.
func _course_drive(accel_pct: float, brake_pct: float, handbrake := false) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, handbrake, 1, false, 3, _plough_extra(_co_run.y))


## Respawn at the course's Spawn for the next COURSE_RUNS entry, or the next implement.
func _next_course_run() -> void:
	if _co_runs.is_empty():
		_next_plough_implement()
		return
	_co_run = _co_runs.pop_front()
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), _start_z))
	_car.respawn()
	_car.call(&"set_attachment", _co_id)
	_co_ext = {}
	_co_shifts = []
	_co_gear = -1
	_co_set = 0.0
	_pl_hold.integral = 0.0
	_t = 0.0
	_pl_stage = Plough.COURSE_SET
	_course_drive(0.0, 100.0, true)


## One tick inside the Row, `d` m into it: each signal's extremes by the soil at the hitch point.
func _course_sample(d: float, tel: TractorTelemetry) -> void:
	var dt: Drivetrain = _car.drivetrain
	var hitch := _car.get_node((_car as TractorVehicle).hitch_path) as ThreePointHitch
	var soil := "band" if _co_strip.field_at(hitch.hitch_point()) < 1.0 else "full"
	var at := "%4.1f m, %s %4.0f rpm" % [d, MeasureRig.gear_label(dt.gear_byte), dt.rpm]
	for sig: String in ["engine_load", "draft_force"]:
		var v := float(tel.get(sig))
		var key := "%s, %s soil" % [sig, soil]
		if not _co_ext.has(key):
			_co_ext[key] = [v, at, v, at, 0.0, 0]
		var ext: Array = _co_ext[key]
		ext[4] += v
		ext[5] += 1
		if v < ext[0]:
			ext[0] = v
			ext[1] = at
		if v > ext[2]:
			ext[2] = v
			ext[3] = at
	if _co_gear >= 0 and dt.gear_byte != _co_gear:
		_co_shifts.append("%s>%s at %.1f m" % [MeasureRig.gear_label(_co_gear),
				MeasureRig.gear_label(dt.gear_byte), d])
	_co_gear = dt.gear_byte


func _report_course_run(s: float) -> void:
	print("  %s %s, %.0f km/h: %s" % [_co_id.get_file().get_basename(),
			"down" if _co_run.y <= 0.0 else "raised", _co_run.x,
			"through the Row in %.1f s" % _t if s > _co_row.y
			else "TIMEOUT %.1f m into the Row" % (s - _co_row.x)])
	var keys := _co_ext.keys()
	keys.sort()
	for key: String in keys:
		var ext: Array = _co_ext[key]
		print("    %-28s mean %3.0f %%, least %3.0f %% (%s), most %3.0f %% (%s)" % [key,
				ext[4] / maxi(ext[5], 1), ext[0], ext[1], ext[2], ext[3]])
	print("    shifts in the Row: %s" % (", ".join(_co_shifts) if not _co_shifts.is_empty()
			else "none"))


## One `trace` line of the floored start: what the coupling passes, the draft against the
## rears' summed tyre force, and each rear tyre against its grip curve.
func _plough_trace_line(v_long: float) -> String:
	var dt: Drivetrain = _car.drivetrain
	var fx := 0.0
	for w in _car.wheels:
		if w.is_rear:
			fx += w.force_long
	return ("      %6.3f %5.2f km/h %s %4.0f rpm %s ramp %.2f clutch %.2f Tc %5.0f fuel %.2f | draft"
			+ " %5.2f kN, rear Fx %5.2f kN | %s") % [_t, v_long * 3.6, MeasureRig.gear_label(dt.gear_byte),
			dt.rpm, "OSL"[dt.coupling_state], dt.ramp, dt.clutch, dt.coupling_torque,
			dt.applied_throttle, absf((_car as TractorVehicle).draft_applied) / 1000.0, fx / 1000.0,
			"  ".join(_rear_contacts(false))]


## Each rear tyre against the grip curve: the slip ratio, < / > the rising / falling side of its
## `_pl_peak_slip` peak, and Fx / Fz; `with_load` puts Fz in kg ahead of them.
func _rear_contacts(with_load: bool) -> Array[String]:
	var rears: Array[String] = []
	for w in _car.wheels:
		if w.is_rear:
			rears.append("%s %s%.3f %s %+.3f" % [MeasureRig.wheel_label(_car,w),
					"%.0f kg, " % (w.suspension_force / BrakeSizing.G) if with_load else "", w.slip,
					">" if w.slip > _pl_peak_slip else "<",
					w.force_long / maxf(w.suspension_force, 1.0)])
	return rears
