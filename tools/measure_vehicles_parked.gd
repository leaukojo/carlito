extends RefCounted
## `measure_vehicles`' standing and handbrake probes (`stall`, `freerev`, `rest[=n|brake|handbrake]`,
## `handbrake`, instead of every other pass): the tool spawns each body and hands it here (`start`,
## then `tick` every physics tick). One `Kind` a run; the four share the `_probe_*` state.

const MeasureRig := preload("res://tools/measure_rig.gd")

enum Kind { STALL, FREEREV, REST, HANDBRAKE }

## --- both pedals at stall (`stall`, instead of every other pass) ---
## Settles on the full foot brake, then floors the throttle against it in manual D1 (the worst gear;
## the automatic box would start the tractor in D3) with traction control off (the ideal TC takes
## the drive back at a standstill, so it would measure the TC, not the brake), and reports how far
## the body moved, its peak speed and the driven wheels' peak spin. `InputRouter.brake_override`
## latches only past BRAKE_OVERRIDE_SPEED, so a body that holds never reaches it: a latch is
## reported as a failure to hold, never hidden.
const STALL_SETTLE_S := 1.5
const STALL_HOLD_S := 10.0
## --- free crank (`freerev`, instead of every other pass) ---
## Parked in N on the full foot brake, the pedal stepped through FREEREV_PEDALS, each held
## FREEREV_HOLD_S: the mean rpm over its last FREEREV_AVG_S, the applied throttle, and whether the
## limiter cut in that window. A map whose free crank runs away reads the limiter on a light pedal.
const FREEREV_PEDALS: Array[float] = [0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0]
const FREEREV_SETTLE_S := 1.5
const FREEREV_HOLD_S := 4.0
const FREEREV_AVG_S := 1.0
## --- standing still (`rest[=n|brake|handbrake]`, instead of every other pass) ---
## Stood on the strip for REST_SETTLE_S in D with the pedals up (`rest`), in N, on a REST_BRAKE_PCT
## foot brake or on the handbrake, the last REST_SAMPLE_S read per tick: how often the body's speed
## changes sign, its swing and drift, the rear springs' swing, and per axle whether the wheel's rim
## lands on the road's speed while the contact lands on the rim's (wheel and body swapping speeds),
## the tyre force against its one-tick cap and how often the rolling drag flips. `crr=<x>` sets
## every wheel's rolling resistance for the pass, the coupled trailer's too.
const REST_SETTLE_S := 10.0
const REST_SAMPLE_S := 3.0
const REST_BRAKE_PCT := 30.0
## --- handbrake turn (`handbrake`, instead of every other pass) ---
## Up to HB_SPEED on the strip, then a HB_STEER step with the throttle lifted, held HB_HOLD_S and
## released straight for HB_AFTER_S: once with the steer alone, once with the handbrake pulled
## over the same window. Reports the rear wheels' locked time, peak yaw rate and heading change.
const HB_SPEED := 16.67            ## m/s (60 km/h)
const HB_STEER := 30.0             ## % of lock, + = right
const HB_HOLD_S := 1.0
const HB_AFTER_S := 1.5

var _kind: int                        ## a `Kind`
var _start_z := 0.0                   ## the strip's spawn line (`respawn` in the handbrake pair)
var _seconds := 0.0                   ## the tool's cap per pass (the handbrake's run-up)
var _lock_slip := 0.0                 ## slip past which a rear wheel counts as locked
var _trailer := ""                    ## `trailer=`, named in the rest line
var _rest_state := ""                 ## "" (D, pedals up), "n", "brake" or "handbrake"
var _rest_crr := NAN                  ## `crr=`: every wheel's rolling resistance for the pass
var _restart: Callable                ## the tool's pass reset
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _current := {}                    ## the tool's report entry for this body
var _t := 0.0                         ## s into the pass
var _freerev_step := 0        ## index into FREEREV_PEDALS; -1 while settling
var _freerev_rpm := 0.0       ## rpm summed over the step's averaging window
var _freerev_ticks := 0
var _freerev_cut := false     ## the limiter cut inside the step's averaging window
var _freerev_rows: Array[Dictionary] = []
var _rest_rows: Array[Dictionary] = []          ## one per tick of the sampled window
var _rest_steps := PackedFloat64Array()         ## mean |speed step| a tick, per second of the pass
var _rest_step_sum := 0.0
var _rest_step_n := 0
var _rest_prev_v := NAN
var _probe_on := false        ## past the settle / run-up, into the measured window
var _probe_t := 0.0
var _probe_x0 := Vector3.ZERO
## Heading change (deg) integrated off the yaw rate, so a spin past 180 reads as one (a wrapped
## heading difference cannot tell a J-turn from a full rotation).
var _probe_turned := 0.0
var _probe_v_peak := 0.0
var _probe_spin_peak := 0.0
var _probe_yaw_peak := 0.0
var _probe_lock_t := 0.0
var _probe_override := false
var _hb_pulled := false       ## this handbrake run pulls the lever (the second of the pair)


func _init(kind: int, start_z: float, seconds: float, lock_slip: float, trailer: String,
		rest_state: String, rest_crr: float, restart: Callable, finish: Callable) -> void:
	_kind = kind
	_start_z = start_z
	_seconds = seconds
	_lock_slip = lock_slip
	_trailer = trailer
	_rest_state = rest_state
	_rest_crr = rest_crr
	_restart = restart
	_finish = finish


## This probe on `car`.
func start(car: BaseVehicle, _title: String, current: Dictionary) -> void:
	_car = car
	_current = current
	match _kind:
		Kind.STALL:
			_start_stall()
		Kind.FREEREV:
			_start_freerev()
		Kind.REST:
			_start_rest()
		Kind.HANDBRAKE:
			_hb_pulled = false
			_start_handbrake_run()


## One physics tick.
func tick(delta: float, _host_t: float) -> void:
	_t += delta
	match _kind:
		Kind.STALL:
			_tick_stall(delta)
		Kind.FREEREV:
			_tick_freerev()
		Kind.REST:
			_tick_rest(delta)
		Kind.HANDBRAKE:
			_tick_handbrake(delta)


func _reset_probe() -> void:
	_probe_on = false
	_probe_t = 0.0
	_probe_v_peak = 0.0
	_probe_spin_peak = 0.0
	_probe_yaw_peak = 0.0
	_probe_turned = 0.0
	_probe_lock_t = 0.0
	_probe_override = false


func _start_stall() -> void:
	_restart.call()
	_t = 0.0
	_reset_probe()
	InputRouter.set_manual_gearbox(true)
	MeasureRig.drive(0.0, 100.0, 0.0, false, 1, true)


func _tick_stall(delta: float) -> void:
	if not _probe_on:
		if _t >= STALL_SETTLE_S:
			_probe_on = true
			_probe_x0 = _car.global_position
			MeasureRig.drive(100.0, 100.0, 0.0, false, 1, true)
		return
	_probe_t += delta
	_probe_v_peak = maxf(_probe_v_peak, absf(_car.telemetry.speed))
	for w in _car.wheels:
		if w.driven:
			_probe_spin_peak = maxf(_probe_spin_peak, absf(w.omega))
	_probe_override = _probe_override or bool(InputRouter.get("_brake_override"))
	if _probe_t < STALL_HOLD_S:
		return
	var moved := (_car.global_position - _probe_x0).length()
	var held := not _probe_override and moved < 0.05
	print(("  %-13s : %s  moved %.3f m in %.0f s, peak %.3f m/s, driven spin peak %.2f rad/s%s;"
			+ " gear %d, %.0f rpm, applied throttle %.2f")
			% ["stall", "HOLDS" if held else "CREEPS", moved, STALL_HOLD_S, _probe_v_peak,
			_probe_spin_peak, ", brake_override latched" if _probe_override else "",
			_car.drivetrain.gear_byte, _car.drivetrain.rpm, _car.drivetrain.applied_throttle])
	InputRouter.set_manual_gearbox(false)
	MeasureRig.drive(100.0, 0.0)
	_finish.call()


func _start_freerev() -> void:
	_restart.call()
	_t = 0.0
	_freerev_step = -1
	_freerev_rows = []
	# Manual: on the automatic a 0 byte with the pedal down reads as D (`arbitrate_bridge`).
	InputRouter.set_manual_gearbox(true)
	MeasureRig.drive(0.0, 100.0, 0.0, false, InputRouter.GEAR_N)


func _tick_freerev() -> void:
	if _freerev_step < 0:
		if _t >= FREEREV_SETTLE_S:
			_next_freerev_step()
		return
	if _t > FREEREV_HOLD_S - FREEREV_AVG_S:
		_freerev_rpm += _car.drivetrain.rpm
		_freerev_ticks += 1
		_freerev_cut = _freerev_cut or _car.drivetrain.on_limiter
	if _t < FREEREV_HOLD_S:
		return
	var pedal := FREEREV_PEDALS[_freerev_step]
	var mean := _freerev_rpm / maxi(_freerev_ticks, 1)
	print("  %-13s : %s pedal %.2f  %5.0f rpm, limiter line %.0f, applied throttle %.3f, gear %d%s"
			% ["freerev", String(_current["variant"]), pedal, mean,
			Drivetrain.limiter_line(_car.spec, Drivetrain.GEAR_N),
			_car.drivetrain.applied_throttle, _car.drivetrain.gear_byte,
			", limiter cut" if _freerev_cut else ""])
	_freerev_rows.append({"pedal": pedal, "rpm": mean, "cut": _freerev_cut})
	if _freerev_step + 1 < FREEREV_PEDALS.size():
		_next_freerev_step()
		return
	_current["freerev"] = _freerev_rows
	_current["freerev_map"] = PedalMap.Kind.keys()[_car.spec.pedal_map]
	_current["freerev_line"] = Drivetrain.limiter_line(_car.spec, Drivetrain.GEAR_N)
	InputRouter.set_manual_gearbox(false)
	MeasureRig.drive(100.0, 0.0)
	_finish.call()


func _next_freerev_step() -> void:
	_freerev_step += 1
	_t = 0.0
	_freerev_rpm = 0.0
	_freerev_ticks = 0
	_freerev_cut = false
	MeasureRig.drive(FREEREV_PEDALS[_freerev_step] * 100.0, 100.0, 0.0, false, InputRouter.GEAR_N)


func _start_rest() -> void:
	_restart.call()
	_t = 0.0
	_rest_rows = []
	_rest_steps = PackedFloat64Array()
	_rest_step_sum = 0.0
	_rest_step_n = 0
	_rest_prev_v = NAN
	InputRouter.set_manual_gearbox(_rest_state == "n")
	MeasureRig.drive(0.0, REST_BRAKE_PCT if _rest_state == "brake" else 0.0, 0.0,
			_rest_state == "handbrake", InputRouter.GEAR_N if _rest_state == "n" else 1)


## Sampled BEFORE the body's own tick (a parent ticks first): the rim and contact speeds a row holds
## are the pair that tick is about to read; its forces are the tick before's.
func _tick_rest(delta: float) -> void:
	var towed := MeasureRig.towed(_car)
	if not is_nan(_rest_crr):
		for w in _car.wheels:
			w.rolling_crr = _rest_crr
		if towed != null:
			for w in towed.wheels:
				w.rolling_crr = _rest_crr
	var forward := -_car.global_basis.z
	var v := _car.linear_velocity.dot(forward)
	if not is_nan(_rest_prev_v):
		_rest_step_sum += absf(v - _rest_prev_v)
		_rest_step_n += 1
	_rest_prev_v = v
	if _rest_step_n >= Engine.physics_ticks_per_second:
		_rest_steps.append(_rest_step_sum / _rest_step_n)
		_rest_step_sum = 0.0
		_rest_step_n = 0
	if _t >= REST_SETTLE_S - REST_SAMPLE_S:
		var rim := PackedFloat64Array()
		var road := PackedFloat64Array()
		var force := PackedFloat64Array()
		var cap := PackedFloat64Array()
		var roll := PackedFloat64Array()
		var held := 0
		for w in _car.wheels:
			rim.append(w.omega * w.wheel_radius)
			road.append(VehicleMath.point_velocity(_car, w.contact_point).dot(forward)
					if w.in_contact else NAN)
			force.append(w.force_long)
			cap.append(w.long_cap)
			roll.append(w.force_roll)
			if w._spin_held:
				held += 1
		_rest_rows.append({"v": v, "acc": _car.telemetry.acc_long, "held": held,
				"rear_kg": VehicleTelemetry.axle_load_kg(_car.drive.rear_suspension_force()),
				"towed_kg": VehicleTelemetry.axle_load_kg(towed.bogie_suspension_force())
						if towed != null else 0.0,
				"rim": rim, "road": road, "force": force, "cap": cap, "roll": roll})
	if _t < REST_SETTLE_S:
		return
	_print_rest(delta, towed != null)
	InputRouter.set_manual_gearbox(false)
	MeasureRig.drive(100.0, 0.0)
	_finish.call()


func _print_rest(delta: float, has_towed: bool) -> void:
	var window := _rest_rows.size() * delta
	var states := {"": "D, pedals up", "n": "N", "brake": "D, foot brake %.0f %%" % REST_BRAKE_PCT,
			"handbrake": "D, handbrake"}
	var held: int = _rest_rows[_rest_rows.size() - 1]["held"]
	print("  %-13s : %s, %s%s%s; clutch %s, gear %d, hill hold %s, %d of %d wheels held" % ["rest",
			String(_current["variant"]), states[_rest_state], ", " + _trailer if _trailer != "" else "",
			"" if is_nan(_rest_crr) else ", crr %.4f" % _rest_crr,
			Drivetrain.CouplingState.keys()[_car.drivetrain.coupling_state],
			_car.drivetrain.gear_byte, "on" if _car.drive.hill_holding else "off", held,
			_car.wheels.size()])
	var speeds := _rest_series("v")
	var speed := _swing(speeds, window)
	var raw := PackedFloat64Array()
	for i in range(1, speeds.size()):
		raw.append((speeds[i] - speeds[i - 1]) / delta)
	print(("  %-13s : speed: sign changes %.1f /s, p-p %.2f mm/s, mean %+.2f mm/s; raw accel p-p"
			+ " %.3f m/s2, accLong as sent p-p %.3f m/s2") % ["", speed["flips"],
			float(speed["pp"]) * 1000.0, float(speed["mean"]) * 1000.0, _swing(raw, window)["pp"],
			_swing(_rest_series("acc"), window)["pp"]])
	var rear := _swing(_rest_series("rear_kg"), window)
	var bogie := _swing(_rest_series("towed_kg"), window)
	print("  %-13s : springs: rear axle p-p %.1f kg, %.1f kg a tick%s" % ["", rear["pp"],
			rear["step"], ("; towed bogie p-p %.1f kg, %.1f kg a tick" % [bogie["pp"], bogie["step"]])
			if has_towed else ""])
	for is_rear: bool in [false, true]:
		print("  %-13s : %s" % ["", _rest_axle(is_rear, window)])
	var steps := PackedStringArray()
	for s in _rest_steps:
		steps.append("%.2f" % (s * 1000.0))
	print("  %-13s : speed step a tick, by second (mm/s): %s" % ["", " ".join(steps)])


## `key`'s value on every row of the sampled window.
func _rest_series(key: String) -> PackedFloat64Array:
	var xs := PackedFloat64Array()
	for row in _rest_rows:
		xs.append(float(row[key]))
	return xs


## A series over `window` s: peak to peak (`pp`), `mean`, sign changes a second (`flips`) and the
## mean change from one tick to the next (`step`).
static func _swing(xs: PackedFloat64Array, window: float) -> Dictionary:
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var flips := 0
	var step := 0.0
	for i in xs.size():
		lo = minf(lo, xs[i])
		hi = maxf(hi, xs[i])
		sum += xs[i]
		if i > 0:
			step += absf(xs[i] - xs[i - 1])
			if signf(xs[i]) != signf(xs[i - 1]):
				flips += 1
	if xs.is_empty():
		return {"pp": 0.0, "mean": 0.0, "flips": 0.0, "step": 0.0}
	return {"pp": hi - lo, "mean": sum / xs.size(), "flips": flips / maxf(window, 1e-9),
			"step": step / maxi(xs.size() - 1, 1)}


## One axle's wheels over the sampled window: the contact's mean speed; how far the rim lands from
## the road's speed of the tick before, and the contact from the rim's, each over that speed's mean
## size (0 = lands on it: both near 0 is the wheel and the body swapping speeds); the tyre force
## over its one-tick cap; the rolling drag and its sign changes a second.
func _rest_axle(rear: bool, window: float) -> String:
	var road_sum := 0.0
	var rim_sum := 0.0
	var rim_off := 0.0
	var road_off := 0.0
	var force_sum := 0.0
	var cap_sum := 0.0
	var drag_sum := 0.0
	var flips := 0
	var pairs := 0
	var wheels := 0
	for wi in _car.wheels.size():
		if _car.wheels[wi].is_rear != rear:
			continue
		wheels += 1
		for i in _rest_rows.size():
			var force: PackedFloat64Array = _rest_rows[i]["force"]
			var cap: PackedFloat64Array = _rest_rows[i]["cap"]
			var roll: PackedFloat64Array = _rest_rows[i]["roll"]
			force_sum += absf(force[wi])
			cap_sum += cap[wi]
			drag_sum += absf(roll[wi])
			if i == 0:
				continue
			var prev_roll: PackedFloat64Array = _rest_rows[i - 1]["roll"]
			if signf(roll[wi]) != signf(prev_roll[wi]):
				flips += 1
			var prev_road: PackedFloat64Array = _rest_rows[i - 1]["road"]
			var prev_rim: PackedFloat64Array = _rest_rows[i - 1]["rim"]
			var road: PackedFloat64Array = _rest_rows[i]["road"]
			var rim: PackedFloat64Array = _rest_rows[i]["rim"]
			if is_nan(prev_road[wi]) or is_nan(road[wi]):
				continue
			pairs += 1
			road_sum += absf(prev_road[wi])
			rim_sum += absf(prev_rim[wi])
			rim_off += absf(rim[wi] - prev_road[wi])
			road_off += absf(road[wi] - prev_rim[wi])
	if wheels == 0 or pairs == 0:
		return "%s axle: no wheel on the ground" % ("rear" if rear else "front")
	var samples := float(wheels * _rest_rows.size())
	# A ratio over a speed under a micrometre a second says nothing: the wheel or the body is still.
	var still := 1e-6 * pairs
	return ("%s axle: contact speed %.2f mm/s; the rim lands %s off the road's speed, the contact"
			+ " %s off the rim's; tyre force %.2f of its cap; drag %.0f N a wheel, flips %.1f /s") % [
			"rear" if rear else "front", road_sum / pairs * 1000.0,
			"%.2f" % (rim_off / road_sum) if road_sum > still else "- (road still)",
			"%.2f" % (road_off / rim_sum) if rim_sum > still else "- (rim still)",
			force_sum / maxf(cap_sum, 1e-9), drag_sum / samples,
			flips / (wheels * maxf(window, 1e-9))]


func _start_handbrake_run() -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), _start_z))
	_car.respawn()
	_restart.call()
	_t = 0.0
	_reset_probe()
	MeasureRig.drive(100.0, 0.0)


func _tick_handbrake(delta: float) -> void:
	if not _probe_on:
		if _car.telemetry.speed >= HB_SPEED or _t >= _seconds:
			_probe_on = true
			MeasureRig.drive(0.0, 0.0, HB_STEER, _hb_pulled)
		return
	_probe_t += delta
	if _probe_t >= HB_HOLD_S and _probe_t - delta < HB_HOLD_S:
		MeasureRig.drive(0.0, 0.0, 0.0, false)
	_probe_yaw_peak = maxf(_probe_yaw_peak, absf(rad_to_deg(_car.angular_velocity.y)))
	_probe_turned += rad_to_deg(_car.angular_velocity.y) * delta
	if _probe_t <= HB_HOLD_S:
		var locked := false
		for w in _car.wheels:
			if w.is_rear and w.in_contact and w.slip > _lock_slip:
				locked = true
		if locked:
			_probe_lock_t += delta
	if _probe_t < HB_HOLD_S + HB_AFTER_S:
		return
	var turned := absf(_probe_turned)
	var label := "handbrake" if _hb_pulled else "steer only"
	print(("  %-13s : rears locked %.2f of %.1f s, yaw rate peak %.0f deg/s, turned %.0f deg%s,"
			+ " %.0f km/h left") % [label, _probe_lock_t, HB_HOLD_S, _probe_yaw_peak, turned,
			" (spun)" if turned > 180.0 else "", _car.telemetry.speed * 3.6])
	if not _hb_pulled:
		_hb_pulled = true
		_start_handbrake_run()
		return
	MeasureRig.drive(100.0, 0.0)
	_finish.call()
