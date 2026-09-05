extends Node3D
## Dev utility: flies the drone off a flat strip and reports hover, climb/descend, lean/
## translate, endurance and one-motor-out figures read off published telemetry. Occasional
## dev tool, not a CI gate: always exits 0. Registers as a local input source
## (`InputRouter.set_touch_source`) rather than pressing Input actions, since arming/
## node-failure are per-frame edges and autoloads tick before scene nodes.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")

## The strip: a rangefinder floor, a collision floor, enough width for the translate pass.
const Layers := preload("res://src/physics/collision_layers.gd")

const STRIP_SIZE := Vector3(1200.0, 2.0, 4000.0)
## Spawn, and therefore HOME: high enough for a descent pass, low enough for GEOFENCE_CEILING.
const SPAWN := Vector3(0.0, 80.0, 1400.0)

## Seconds arming/spooling centred before each pass's own stick goes in; also covers motor spool.
const ARM_S := 2.5
## Seconds at the end of a pass averaged into the reported figure.
const AVG_WINDOW := 2.0

const HOVER_S := 6.0        ## hover: collective, pack current, endurance
const CLIMB_S := 10.0       ## full up stick; terminal is climb_force / vertical_drag
const DESCEND_S := 9.0      ## full down stick; ends well above the strip from SPAWN.y
## Full forward stick, capped inside GEOFENCE_RADIUS (a breach latches RTL).
const TRANSLATE_S := 13.0
const MOTOR_OUT_S := 6.0    ## hover, then ESC1 off the bus

## Fraction of settled value "time to" figures are called at; the approach is asymptotic.
const REACH_FRAC := 0.9

enum Pass { HOVER, CLIMB, DESCEND, TRANSLATE, MOTOR_OUT, DONE }

## Seconds into the arm window the arm switch is raised (goes down at the top of every pass).
const ARM_EDGE_S := 0.5
## Seconds after the motor drops at which yaw divergence is sampled.
const YAW_MARKS: Array[float] = [1.0, 2.0, 3.0]
## Seconds of settled hover before ESC1 is dropped, so the craft isn't still spooling.
const FAIL_AT_S := 1.0
## Degrees of yaw the motor-out pass times to (a quarter turn; no control meaning).
const YAW_TARGET_DEG := 90.0


## The tool's own input source; levels are held, edges report once and clear on read.
class StickSource extends RefCounted:
	var climb := 0.0      ## -1..1, + = up
	var throttle := 0.0   ## 0..1 forward lean (accel); the drone never needs the brake axis
	var _edges: Dictionary[StringName, bool] = {}

	func press(edge: StringName) -> void:
		_edges[edge] = true

	func poll() -> Dictionary[StringName, Variant]:
		var out: Dictionary[StringName, Variant] = {
			&"accel": clampf(throttle, 0.0, 1.0),
			&"climb": clampf(climb, -1.0, 1.0),
		}
		for edge: StringName in _edges:
			out[edge] = true
		_edges.clear()
		return out


var _drone: DroneVehicle
var _source := StickSource.new()
var _pass: int = Pass.HOVER
var _t := 0.0
## Seconds per physics tick, read off Engine: get_physics_process_delta_time() in _ready returns 0 before the first tick.
var _step := 1.0 / float(Engine.physics_ticks_per_second)

# --- per-pass accumulators -------------------------------------------------
var _avg_n := 0
var _avg_collective := 0.0
var _avg_pack_a := 0.0
var _avg_esc_a := 0.0
var _avg_volts := 0.0
var _avg_vspeed := 0.0
var _soc_at_window := -1.0   ## soc when the averaging window opened, for the drain rate
var _tilt_reach := -1.0      ## s to REACH_FRAC of max_tilt_deg
var _speeds := PackedFloat32Array()   ## ground speed each tick since the stick went in
var _arm_switch := false     ## our own mirror of InputRouter's arm LATCH (the key is a toggle)
## Yaw is integrated off the published `yaw` rate, not differenced off `heading` (wraps on a tumbling craft).
var _yaw_int := 0.0          ## deg of yaw accumulated since the motor dropped
var _yaw_peak := 0.0         ## peak |yaw rate| (deg/s) over the same stretch
var _yaw_at := PackedFloat32Array()       ## yaw rate (deg/s) at each YAW_MARKS entry
var _yaw_sum_at := PackedFloat32Array()   ## accumulated yaw (deg) at the same marks
var _yaw_reach := -1.0       ## s to YAW_TARGET_DEG of accumulated yaw
var _fail_alt := 0.0         ## altitude when ESC1 dropped
var _fail_mode := -1         ## mode_actual at the end of the motor-out pass
var _failed := false         ## the ESC1 edge has been sent this pass


func _ready() -> void:
	_build_strip()
	_drone = load(Catalog.VARIANTS["drone"]["scene"]).instantiate()
	add_child(_drone)
	_drone.global_transform = Transform3D(Basis.IDENTITY, SPAWN)
	_drone.spawn_transform = _drone.global_transform
	_drone.reset_physics_interpolation()
	InputRouter.set_touch_source(_source)
	var spec: VehicleSpec = _drone.spec
	print("strip: %.0f x %.0f m flat, still air, STABILIZE, %.1f s of centred-stick arming per pass"
			% [STRIP_SIZE.x, STRIP_SIZE.z, ARM_S])
	print("=== drone: %.1f kg, %.0f N max thrust, %.0f N climb authority, %dS %.1f Ah pack ===\n"
			% [spec.mass, _drone.max_thrust, _drone.climb_force,
			DronePower.CELLS, DronePower.PACK_CAPACITY_AH])
	_enter_pass(Pass.HOVER)


func _exit_tree() -> void:
	InputRouter.clear_touch_source(_source)


func _build_strip() -> void:
	var shape := BoxShape3D.new()
	shape.size = STRIP_SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var box := BoxMesh.new()
	box.size = shape.size
	var visual := MeshInstance3D.new()
	visual.mesh = box
	var ground := StaticBody3D.new()
	ground.name = "Strip"
	# TERRAIN: every gameplay ray masks Layers.SOLID; engine default would drop the craft through.
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = Layers.DYNAMIC
	ground.position = Vector3(0.0, -STRIP_SIZE.y * 0.5, 0.0)  # top face at y = 0
	ground.add_child(collision)
	ground.add_child(visual)
	add_child(ground)


func _enter_pass(which: int) -> void:
	_pass = which
	_t = 0.0
	_avg_n = 0
	_avg_collective = 0.0
	_avg_pack_a = 0.0
	_avg_esc_a = 0.0
	_avg_volts = 0.0
	_avg_vspeed = 0.0
	_soc_at_window = -1.0
	_tilt_reach = -1.0
	_speeds = PackedFloat32Array()
	_yaw_int = 0.0
	_yaw_peak = 0.0
	_yaw_at = PackedFloat32Array()
	_yaw_sum_at = PackedFloat32Array()
	_yaw_reach = -1.0
	_failed = false
	_fail_alt = 0.0
	_fail_mode = -1
	_source.climb = 0.0
	_source.throttle = 0.0
	if which == Pass.DONE:
		print("done — dev tool, nothing here fails a build")
		get_tree().quit(0)
		return
	# Arm switch goes down here, back up ARM_EDGE_S later: a switch left up across the respawn spends its edge on a tick where PA_STICK still refuses.
	_set_arm(false)
	# Fresh aircraft every pass, or endurance would measure a battery the climb pass emptied.
	_drone.respawn()


## The arm key is a toggle owned by InputRouter; this mirrors the latch locally.
func _set_arm(want: bool) -> void:
	if want == _arm_switch:
		return
	_arm_switch = want
	_source.press(&"arm_toggle")


func _pass_seconds() -> float:
	match _pass:
		Pass.HOVER:
			return HOVER_S
		Pass.CLIMB:
			return CLIMB_S
		Pass.DESCEND:
			return DESCEND_S
		Pass.TRANSLATE:
			return TRANSLATE_S
	return MOTOR_OUT_S


## Do not speed up with Engine.time_scale: it enlarges the physics step (measured damage: measure_vehicles.gd).
func _physics_process(delta: float) -> void:
	if _pass == Pass.DONE:
		return
	_t += delta
	if _t < ARM_S:
		if _t >= ARM_EDGE_S:
			_set_arm(true)
		return   # arming and spooling, sticks centred
	var t := _drone.telemetry as DroneTelemetry
	var flown := _t - ARM_S
	_apply_stick(t, flown)
	_sample(t, flown, delta)
	if flown >= _pass_seconds():
		_report(t)
		_enter_pass(_pass + 1)


## The one stick each pass is about, applied once the craft is armed and hovering.
func _apply_stick(t: DroneTelemetry, flown: float) -> void:
	match _pass:
		Pass.CLIMB:
			_source.climb = 1.0
		Pass.DESCEND:
			_source.climb = -1.0
		Pass.TRANSLATE:
			_source.throttle = 1.0
		Pass.MOTOR_OUT:
			# One Y-key edge takes roster index 0 (ESC1) off the bus, first stop on InputRouter.cycle_node_fail.
			if not _failed and flown >= FAIL_AT_S:
				_failed = true
				_source.press(&"node_fail_cycle")
				_fail_alt = t.altitude


func _sample(t: DroneTelemetry, flown: float, delta: float) -> void:
	match _pass:
		Pass.TRANSLATE:
			_speeds.append(Vector2(_drone.linear_velocity.x, _drone.linear_velocity.z).length())
			if _tilt_reach < 0.0 and absf(t.pitch) >= REACH_FRAC * _drone.max_tilt_deg:
				_tilt_reach = flown
		Pass.MOTOR_OUT:
			if _failed:
				_sample_yaw(t, flown - FAIL_AT_S, delta)
	if flown < _pass_seconds() - AVG_WINDOW:
		return
	if _soc_at_window < 0.0:
		_soc_at_window = t.soc
	_avg_n += 1
	_avg_collective += _collective_frac(t)
	_avg_pack_a += t.pack_current
	_avg_esc_a += _mean(t.esc_current)
	_avg_volts += t.battery
	_avg_vspeed += t.vspeed


func _sample_yaw(t: DroneTelemetry, since: float, delta: float) -> void:
	var rate := rad_to_deg(t.yaw)
	_yaw_int += rate * delta
	_yaw_peak = maxf(_yaw_peak, absf(rate))
	while _yaw_at.size() < YAW_MARKS.size() and since >= YAW_MARKS[_yaw_at.size()]:
		_yaw_at.append(rate)
		_yaw_sum_at.append(_yaw_int)
	if _yaw_reach < 0.0 and absf(_yaw_int) >= YAW_TARGET_DEG:
		_yaw_reach = since
	_fail_mode = t.mode_actual


## Collective as a fraction of max_thrust, reconstructed from published esc_rpm via `thrust ~ w^2`.
func _collective_frac(t: DroneTelemetry) -> float:
	var total := 0.0
	for rpm: int in t.esc_rpm:
		var w := float(rpm) / float(DroneProp.ROTOR_MAX_RPM)
		total += w * w
	return total / maxf(float(t.esc_rpm.size()), 1.0)


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


func _report(t: DroneTelemetry) -> void:
	var n := maxf(float(_avg_n), 1.0)
	var collective := _avg_collective / n
	var pack_a := _avg_pack_a / n
	var esc_a := _avg_esc_a / n
	var volts := _avg_volts / n
	var vspeed := _avg_vspeed / n
	var weight: float = _drone.spec.mass * 9.8
	match _pass:
		Pass.HOVER:
			print("  %-13s : collective %.3f of max (%.1f N of thrust against %.1f N of weight)"
					% ["hover", collective, collective * _drone.max_thrust, weight])
			print("  %-13s : %.1f A per ESC, %.1f A at the pack, %.2f V terminal, %.0f%% soc"
					% ["  power", esc_a, pack_a, volts, t.soc])
			# Two endurance figures that must agree: rated capacity over measured draw, and the soc accumulator's own slope.
			var by_capacity := DronePower.PACK_CAPACITY_AH / maxf(pack_a, 1e-6) * 60.0
			var drain := (_soc_at_window - t.soc) / AVG_WINDOW  # %/s
			var by_drain := 100.0 / maxf(drain, 1e-6) / 60.0
			print("  %-13s : %.1f min of level hover (%.1f Ah / %.1f A); soc falls %.4f%%/s = %.1f min"
					% ["  endurance", by_capacity, DronePower.PACK_CAPACITY_AH, pack_a,
					drain, by_drain])
		Pass.CLIMB:
			print("  %-13s : %+.2f m/s settled at full up stick, %.0f m gained, collective %.3f"
					% ["climb", vspeed, t.altitude - SPAWN.y, collective])
			print("  %-13s : %.1f A at the pack (%.1f min at this rate), ESCs at %.0f degC"
					% ["  power", pack_a, DronePower.PACK_CAPACITY_AH / maxf(pack_a, 1e-6) * 60.0,
					_mean(t.esc_temp)])
		Pass.DESCEND:
			print("  %-13s : %+.2f m/s settled at full down stick, %.0f m lost, collective %.3f%s"
					% ["descent", vspeed, t.altitude - SPAWN.y, collective,
					"  <-- ON THE GROUND, the rate is not terminal" if t.ground else ""])
		Pass.TRANSLATE:
			var final_speed := _speeds[_speeds.size() - 1] if not _speeds.is_empty() else 0.0
			print("  %-13s : %.1f deg (%.0f%% of the %.0f deg limit) in %s"
					% ["lean", REACH_FRAC * _drone.max_tilt_deg, REACH_FRAC * 100.0,
					_drone.max_tilt_deg,
					("%.2f s" % _tilt_reach) if _tilt_reach >= 0.0 else "never reached"])
			print("  %-13s : %.1f m/s (%.1f km/h) at the %.0f s cap, %.0f%% of it in %s, %.0f m from home"
					% ["translate", final_speed, final_speed * 3.6, TRANSLATE_S,
					REACH_FRAC * 100.0, _reach_label(final_speed), t.home_dist])
			# The cap is not terminal speed: the pass can't run longer without crossing GEOFENCE_RADIUS.
			print("  %-13s : still gaining %+.2f m/s per second at the cap%s"
					% ["  residual", _last_gain(),
					" — read the figure above as a floor" if _last_gain() > 0.05 else ""])
			print("  %-13s : %+.2f m/s while leaning — STABILIZE holds the collective, so a lean sinks"
					% ["  vspeed", vspeed])
		Pass.MOTOR_OUT:
			print("  %-13s : ESC1 (roster 0) off the bus after %.1f s of hover"
					% ["motor out", FAIL_AT_S])
			for i in _yaw_at.size():
				print("  %-13s : %+7.1f deg/s yaw, %+7.1f deg turned, at t+%.0f s"
						% ["  divergence", _yaw_at[i], _yaw_sum_at[i], YAW_MARKS[i]])
			print("  %-13s : %.0f deg of yaw in %s; peak rate %.1f deg/s"
					% ["  quarter", YAW_TARGET_DEG,
					("%.2f s" % _yaw_reach) if _yaw_reach >= 0.0 else "not reached in the pass",
					_yaw_peak])
			print("  %-13s : %.0f m of altitude lost in the %.0f s after the failure"
					% ["  descent", _fail_alt - t.altitude, MOTOR_OUT_S - FAIL_AT_S])
			print("  %-13s : failsafe %s, mode_actual %s, esc_fault 0x%X, node_online 0x%02X"
					% ["  the bus", _enum_label("failsafe", t.failsafe),
					_enum_label("mode_actual", _fail_mode), t.esc_fault, t.node_online])
	print("")


## An enum ordinal named the way the contract names it; falls back to the bare ordinal if unmapped.
func _enum_label(signal_name: String, value: int) -> String:
	var sig: Contract.SignalDef = Contract.data.get_signal_def(signal_name, "out")
	var label := "" if sig == null else sig.enum_label(value)
	return "%d" % value if label.is_empty() else "%d (%s)" % [value, label]


## Ground speed gained over the last second of the translate pass, m/s per second.
func _last_gain() -> float:
	var last := _speeds.size() - 1
	var back := last - Engine.physics_ticks_per_second
	if back < 0:
		return 0.0
	return _speeds[last] - _speeds[back]


## When the translating craft first passed REACH_FRAC of its final speed (samples are one per tick).
func _reach_label(final_speed: float) -> String:
	var target := REACH_FRAC * final_speed
	for i in _speeds.size():
		if _speeds[i] >= target:
			return "%.2f s" % (float(i) * _step)
	return "never"
