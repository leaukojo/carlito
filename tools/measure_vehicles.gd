extends Node3D
## Dev utility: drive a vehicle down a long flat full-grip strip and report what the sim
## actually produces — acceleration, top speed, and whether it tracks straight. Occasional
## dev tool, NOT a CI gate: it always exits 0, and a FAIL line is something to go look at
## rather than something that blocks a push.
##
## Game-mode tool scene (like bake_levels/check_bakes), because it needs the autoloads and
## a running physics step — `--script` mode has neither:
##   godot --headless --path . res://tools/measure_vehicles.tscn -- [variant|all] [seconds]
##
## `variant` is a VehicleCatalog id (default "sedan-sports", the car family's first body);
## `all` walks every wheel-driven variant. Only wheel-driven chassis are drivable here —
## the boat/drone/plane need water and air, not a strip.
##
## The strip is a plain StaticBody3D, which means surface_grip 1.0 (RayWheel only drops
## below 1.0 on painted terrain), i.e. the sim's asphalt-equivalent surface. Steering input
## is never touched, so the tracking pass below is a true zero-steer run.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")

const STRIP_LENGTH := 6000.0
const STRIP_WIDTH := 40.0
const START_Z := 2800.0      ## spawn near one end; the body faces -Z, so it runs the length
const DEFAULT_SECONDS := 90.0

## Top speed is called once the run stops gaining meaningfully over SETTLE_WINDOW. The
## threshold is RELATIVE because the approach to terminal speed is asymptotic: the last
## 1 km/h can take a minute and tells you nothing, and waiting for it made an `all` run
## take longer than ten minutes. So the reported top speed is a settled value within about
## SETTLE_REL of true terminal, not the exact asymptote — fine for the question this tool
## answers, and the reason it prints "top speed (settled)".
const SETTLE_REL := 0.002     ## fraction of current speed gained over the window
const SETTLE_ABS := 0.02      ## m/s floor, so a near-stationary vehicle still terminates
const SETTLE_WINDOW := 3.0    ## s

# --- tracking pass ---------------------------------------------------------
## Measured from a latched origin once the vehicle is up to speed, so the launch transient
## (wheelspin, squat, the first-tick suspension settle) is not counted as drift.
const TRACK_START_SPEED := 16.7   ## m/s (~60 km/h) before the origin is latched
const TRACK_DISTANCE := 200.0     ## m of straight running measured after that
## Thresholds. A perfectly symmetric chassis drifts by float noise; these are set well
## above what the vehicles actually do (see docs/systems.md) so a FAIL means a real
## asymmetry — a mistyped wheel_positions x, a one-sided torque split, uneven brakes.
const MAX_LATERAL_DRIFT := 1.0    ## m off the latched forward axis over TRACK_DISTANCE
const MAX_HEADING_DRIFT := 1.0    ## deg of heading change over the same stretch

enum Phase { ACCEL, TRACKING, DONE }

var _queue: Array[String] = []
var _seconds := DEFAULT_SECONDS
var _car: BaseVehicle
var _variant := ""
var _phase := Phase.ACCEL
var _failures := 0

# accel pass
var _t := 0.0
var _peak := 0.0
var _dist := 0.0
var _marks := {}
var _settle_t := 0.0
var _settle_v := 0.0

# tracking pass
var _latched := false
var _track_origin := Vector3.ZERO
var _track_right := Vector3.ZERO
var _track_forward := Vector3.ZERO
var _track_heading := 0.0
var _track_dist := 0.0
var _drift_peak := 0.0
var _drift_final := 0.0
var _heading_peak := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "sedan-sports"
	if args.size() > 1:
		_seconds = maxf(5.0, float(args[1]))
	# DO NOT try to speed this up with Engine.time_scale. It is tempting (an `all` run is
	# minutes of wall clock, paced to real time) and it is WRONG: Godot scales the delta
	# handed to _physics_process rather than running more iterations, so it enlarges the
	# step instead of the rate. Measured, the default car's 0-100 went 5.30 s -> 6.40 s at
	# time_scale 8 — that is the locked-60-Hz rule being broken, and the numbers this tool
	# exists to report becoming fiction. Run `all` in the background instead.
	_build_strip()
	if which == "all":
		_queue.assign(_wheel_driven_variants())
	elif Catalog.VARIANTS.has(which):
		_queue = [which]
	else:
		printerr("unknown variant '%s' — expected 'all' or one of: %s" %
				[which, ", ".join(_wheel_driven_variants())])
		get_tree().quit(1)
		return
	print("strip: %.0f x %.0f m flat, surface_grip 1.0, zero steer input, %.0f s cap per pass\n" %
			[STRIP_WIDTH, STRIP_LENGTH, _seconds])
	Input.action_press("accel")
	_next_vehicle()


## Every catalog variant with a driven axle. The boat/drone/plane/train have none, which is
## the same discriminator BaseVehicle uses for its road-drag stand-in.
func _wheel_driven_variants() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.VARIANTS:
		var scene: PackedScene = load(Catalog.VARIANTS[id]["scene"])
		var body := scene.instantiate()
		if body is BaseVehicle:
			var spec: VehicleSpec = (body as BaseVehicle).spec
			if spec != null and (spec.driven_front or spec.driven_rear):
				out.append(id)
		body.free()
	return out


func _build_strip() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(STRIP_WIDTH, 2.0, STRIP_LENGTH)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var ground := StaticBody3D.new()
	ground.name = "Strip"
	ground.position = Vector3(0.0, -1.0, 0.0)  # top face at y = 0
	ground.add_child(collision)
	ground.add_child(visual)
	add_child(ground)


func _next_vehicle() -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	if _queue.is_empty():
		if _failures > 0:
			print("%d vehicle(s) with a tracking FAIL" % _failures)
		else:
			print("all vehicles tracked straight")
		get_tree().quit(0)
		return
	_variant = _queue.pop_front()
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	add_child(_car)
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, START_Z))
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_reset_pass(Phase.ACCEL)


func _reset_pass(phase: Phase) -> void:
	_phase = phase
	_t = 0.0
	_peak = 0.0
	_dist = 0.0
	_marks = {}
	_settle_t = 0.0
	_settle_v = 0.0
	_latched = false
	_track_dist = 0.0
	_drift_peak = 0.0
	_drift_final = 0.0
	_heading_peak = 0.0


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Phase.DONE:
		return
	_t += delta
	if _phase == Phase.ACCEL:
		_tick_accel(delta)
	else:
		_tick_tracking()


func _tick_accel(delta: float) -> void:
	var v: float = _car.telemetry.speed  # signed m/s, read out of the sim
	_dist += absf(v) * delta
	_peak = maxf(_peak, v)
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		if not _marks.has(kmh) and v * 3.6 >= kmh:
			_marks[kmh] = _t
	if not _marks.has("quarter") and _dist >= 402.34:
		_marks["quarter"] = Vector2(_t, v * 3.6)
	# Plateaued? Call it rather than idling at terminal speed for the rest of the budget.
	var settled := _t - _settle_t >= SETTLE_WINDOW
	if settled and _peak - _settle_v < maxf(SETTLE_ABS, _peak * SETTLE_REL):
		_report_accel()
		return
	if settled:
		_settle_t = _t
		_settle_v = _peak
	if _t >= _seconds:
		_report_accel()


func _tick_tracking() -> void:
	var pos := _car.global_position
	if not _latched:
		# Wait until the launch transient is over, then latch this pose as the ideal line.
		if _car.telemetry.speed >= TRACK_START_SPEED:
			_latched = true
			_track_origin = pos
			_track_right = _car.global_transform.basis.x
			_track_forward = -_car.global_transform.basis.z
			_track_heading = _car.telemetry.heading
		elif _t >= _seconds:
			print("  %-13s : never reached %.0f km/h, skipped" % ["tracking", TRACK_START_SPEED * 3.6])
			_report_tracking(true)
		return
	var offset := pos - _track_origin
	_track_dist = offset.dot(_track_forward)
	_drift_final = offset.dot(_track_right)
	_drift_peak = maxf(_drift_peak, absf(_drift_final))
	# Wrapped difference: heading is [0,360), so a run across north must not read as 359 deg.
	var dh := absf(fposmod(_car.telemetry.heading - _track_heading + 180.0, 360.0) - 180.0)
	_heading_peak = maxf(_heading_peak, dh)
	if _track_dist >= TRACK_DISTANCE or _t >= _seconds:
		_report_tracking(false)


func _report_accel() -> void:
	var spec: VehicleSpec = _car.spec
	print("=== %s (%s), %.0f kg, %s ===" % [_variant, Catalog.VARIANTS[_variant]["family"],
			spec.mass, _drive_label(spec)])
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
		print("  %-13s : %s" % [label,
				("%.2f s" % _marks[kmh]) if _marks.has(kmh) else "not reached"])
	if _marks.has("quarter"):
		var q: Vector2 = _marks["quarter"]
		print("  %-13s : %.2f s @ %.1f km/h" % ["quarter mile", q.x, q.y])
	print("  %-13s : %.1f km/h (%.1f mph), gear %d @ %.0f rpm" % ["top (settled)",
			_peak * 3.6, _peak * 2.23694, _car.telemetry.gear_byte, _car.telemetry.rpm])
	# Unreachable ratios are a real tuning smell: the vehicle carries gears it can never use.
	var top_gear: int = _car.telemetry.gear_byte
	if top_gear > 0 and top_gear < spec.gear_ratios.size():
		print("  %-13s : tops out in gear %d of %d — the taller ratios never engage"
				% ["note", top_gear, spec.gear_ratios.size()])
	_car.respawn()
	_reset_pass(Phase.TRACKING)


func _report_tracking(skipped: bool) -> void:
	if not skipped:
		var ok := _drift_peak <= MAX_LATERAL_DRIFT and _heading_peak <= MAX_HEADING_DRIFT
		if not ok:
			_failures += 1
		print("  %-13s : %s  drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg"
				% ["tracking", "PASS" if ok else "FAIL", _drift_peak, _drift_final,
				_track_dist, _heading_peak])
		if not ok:
			print("                 straight-line pull — suspect asymmetric wheel_positions,")
			print("                 a one-sided drive split, or uneven brake torque")
	print("")
	_next_vehicle()


func _drive_label(spec: VehicleSpec) -> String:
	if spec.driven_front and spec.driven_rear:
		return "AWD"
	return "FWD" if spec.driven_front else "RWD"
