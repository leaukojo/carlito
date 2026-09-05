extends Node3D
## Drives a vehicle down a flat full-grip strip and reports acceleration, top speed and
## straight-line tracking. Game-mode tool scene (needs autoloads + a physics step).
## `track strict` is the CI gate and exits nonzero on a FAIL; the accel/top-speed report
## always exits 0.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")

const STRIP_LENGTH := 6000.0
const Layers := preload("res://src/physics/collision_layers.gd")

const STRIP_WIDTH := 40.0
const START_Z := 2800.0      ## spawn near one end; the body faces -Z, so it runs the length
## Metres of strip ahead of the spawn; using all of it means the run ran out of road.
const RUN_LENGTH := START_Z + STRIP_LENGTH * 0.5
const DEFAULT_SECONDS := 90.0

## Top speed is called once gains stop meaningfully over SETTLE_WINDOW; relative threshold
## since the approach to terminal speed is asymptotic.
const SETTLE_REL := 0.002     ## fraction of current speed gained over the window
const SETTLE_ABS := 0.02      ## m/s floor, so a near-stationary vehicle still terminates
const SETTLE_WINDOW := 3.0    ## s

# --- tracking pass ---------------------------------------------------------
## Measured from a latched origin once up to speed, so the launch transient is not counted as drift.
const TRACK_START_SPEED := 16.7   ## m/s (~60 km/h) before the origin is latched
const TRACK_DISTANCE := 200.0     ## m of straight running measured after that
## Set well above what shipped vehicles do; a FAIL means a real asymmetry (docs/vehicles.md).
const MAX_LATERAL_DRIFT := 1.0    ## m off the latched forward axis over TRACK_DISTANCE
const MAX_HEADING_DRIFT := 1.0    ## deg of heading change over the same stretch

# --- coast-down pass (opt-in: pass the `coast` flag) ----------------------
## Cuts throttle at settled top speed and measures deceleration under resistance alone.
## Declared model: `0.5 * 1.225 * drag_area * v^2 + rolling_resistance * m * g`.
## Also reports chassis contacts: RayWheel is a raycast, so any contact is the hull scraping.
const COAST_SECONDS := 5.0

const REFERENCE_SPECS_PATH := "res://tools/vehicle_reference_specs.json"
const REPORT_DIR := "res://reports/specs_sweep/"

enum Phase { ACCEL, COAST, TRACKING, DONE }

var _queue: Array[String] = []
var _seconds := DEFAULT_SECONDS
var _car: BaseVehicle
var _variant := ""
var _phase := Phase.ACCEL
var _failures := 0
var _coast := false
## `track`: skip the accel/top-speed pass — CI only needs the tracking gate.
var _track_only := false
## `strict`: exit nonzero on a tracking FAIL. Off by default so dev invocation stays a report.
var _strict := false

# coast pass
var _coast_v0 := 0.0
var _contact_peak := 0
var _contact_t0 := -1.0
var _contact_t1 := -1.0

# accel pass
var _t := 0.0
var _peak := 0.0
var _dist := 0.0
var _marks := {}
var _settle_t := 0.0
var _settle_v := 0.0
var _prev_v := 0.0
var _inst_a := 0.0   ## body's own acceleration last tick, for the balance audit

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

# sweep report: per-vehicle measured figures, buffered as each pass reports, plus the
# real-world comparison figures loaded once from REFERENCE_SPECS_PATH.
var _reference := {}
var _sweep: Array[Dictionary] = []
var _current := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "sedan-sports"
	if args.size() > 1:
		_seconds = maxf(5.0, float(args[1]))
	var flags := args.slice(2)
	_coast = flags.has("coast")
	_track_only = flags.has("track")
	_strict = flags.has("strict")
	var ref_file := FileAccess.open(REFERENCE_SPECS_PATH, FileAccess.READ)
	_reference = JSON.parse_string(ref_file.get_as_text())
	# Do not speed up with Engine.time_scale: it enlarges the physics step and breaks the
	# locked-60-Hz tuning (default car's 0-100 went 5.30 s -> 6.40 s at time_scale 8).
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


## Every catalog variant with a driven axle; boat/drone/plane/train declare none.
func _wheel_driven_variants() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.VARIANTS:
		var scene: PackedScene = load(Catalog.VARIANTS[id]["scene"])
		var body := scene.instantiate()
		if body is BaseVehicle:
			var spec: VehicleSpec = (body as BaseVehicle).spec
			var gd: GroundDriveSpec = spec.ground_drive if spec != null else null
			if gd != null and (gd.driven_front or gd.driven_rear):
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
	# TERRAIN: every gameplay ray masks Layers.SOLID; engine-default would drop the vehicle through.
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = Layers.DYNAMIC
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
		_write_report()
		get_tree().quit(1 if _strict and _failures > 0 else 0)
		return
	_variant = _queue.pop_front()
	_current = {"variant": _variant, "family": String(Catalog.VARIANTS[_variant]["family"])}
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	add_child(_car)
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, START_Z))
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	if _coast:
		_car.contact_monitor = true
		_car.max_contacts_reported = 8
	_reset_pass(Phase.TRACKING if _track_only else Phase.ACCEL)


func _reset_pass(phase: Phase) -> void:
	_phase = phase
	_t = 0.0
	_peak = 0.0
	_dist = 0.0
	_marks = {}
	_settle_t = 0.0
	_settle_v = 0.0
	# Must reset: a stale _prev_v reads the first tick of a new pass as the last vehicle's terminal speed falling to zero.
	_prev_v = 0.0
	_coast_v0 = 0.0
	_contact_peak = 0
	_contact_t0 = -1.0
	_contact_t1 = -1.0
	_latched = false
	_track_dist = 0.0
	_drift_peak = 0.0
	_drift_final = 0.0
	_heading_peak = 0.0


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Phase.DONE:
		return
	_t += delta
	if _coast:
		var n := _car.get_contact_count()
		_contact_peak = maxi(_contact_peak, n)
		# First/last timestamps distinguish a scraping hull (long window) from a spawn bounce.
		if n > 0:
			if _contact_t0 < 0.0:
				_contact_t0 = _t
			_contact_t1 = _t
	if _phase == Phase.ACCEL:
		_tick_accel(delta)
	elif _phase == Phase.COAST:
		_tick_coast()
	else:
		_tick_tracking()


func _tick_accel(delta: float) -> void:
	var v: float = _car.telemetry.speed  # signed m/s, read out of the sim
	_inst_a = (v - _prev_v) / delta
	_prev_v = v
	_dist += absf(v) * delta
	_peak = maxf(_peak, v)
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		if not _marks.has(kmh) and v * 3.6 >= kmh:
			_marks[kmh] = _t
	if not _marks.has("quarter") and _dist >= 402.34:
		_marks["quarter"] = Vector2(_t, v * 3.6)
	# Plateaued: call it rather than idling at terminal speed for the rest of the budget.
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
		# Latch this pose as the ideal line once the launch transient is over.
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


## Mass of everything this run accelerates (chassis + coupled sub-bodies), in kg. Not
## `spec.mass`: a semi couples its trailer as a sibling, never a child (TowHost.couple).
func _rig_bodies() -> Array:
	var out: Array = [_car]
	for child in get_children():
		var body := child as RigidBody3D
		if body != null and body != _car and body.get("wheels") != null:
			out.append(body)
	return out


func _combination_mass() -> float:
	var total: float = _car.mass
	for child in get_children():
		var body := child as RigidBody3D
		if body != null and body != _car:
			total += body.mass
	return total


func _report_accel() -> void:
	var spec: VehicleSpec = _car.spec
	var all_up := _combination_mass()
	# Chassis and all-up mass reported separately where they differ (see _combination_mass).
	var mass_label := "%.0f kg" % spec.mass
	if not is_equal_approx(all_up, spec.mass):
		mass_label = "%.0f kg chassis, %.0f kg all up" % [spec.mass, all_up]
	print("=== %s (%s), %s, %s ===" % [_variant, Catalog.VARIANTS[_variant]["family"],
			mass_label, _drive_label(spec)])
	_current["mass_label"] = mass_label
	_current["drive_label"] = _drive_label(spec)
	_current["marks"] = _marks.duplicate(true)
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
		print("  %-13s : %s" % [label,
				("%.2f s" % _marks[kmh]) if _marks.has(kmh) else "not reached"])
	if _marks.has("quarter"):
		var q: Vector2 = _marks["quarter"]
		print("  %-13s : %.2f s @ %.1f km/h" % ["quarter mile", q.x, q.y])
	print("  %-13s : %.1f km/h (%.1f mph), gear %d @ %.0f rpm" % ["top (settled)",
			_peak * 3.6, _peak * 2.23694, _car.telemetry.gear_byte, _car.telemetry.rpm])
	_current["top_kmh"] = _peak * 3.6
	_current["top_gear"] = _car.telemetry.gear_byte
	_current["top_rpm"] = _car.telemetry.rpm
	# Distance separates "settled at terminal speed" from "ran out of strip" (`_peak` is a running maximum).
	var v: float = _car.telemetry.speed
	var ran_out := _dist >= RUN_LENGTH - 50.0
	print("  %-13s : %.0f m used of %.0f m, %.0f m left; speed now %.1f km/h%s"
			% ["distance", _dist, RUN_LENGTH, RUN_LENGTH - _dist, v * 3.6,
			"  <-- STRIP RAN OUT, top speed is not terminal" if ran_out else ""])
	_current["dist"] = _dist
	_current["run_length"] = RUN_LENGTH
	_current["speed_now_kmh"] = v * 3.6
	_current["ran_out"] = ran_out
	# Force balance vs. the body's own acceleration: `resistance` matches the spec's declared
	# `0.5*rho*Cd*A*v^2 + crr*N`, `tyres` matches `axle_torque / r`, `rake` is the suspension
	# force along travel (~0 on flat ground). Summed over the whole combination so a
	# trailer's coupling force cancels.
	var normal_load := 0.0
	var tyre := 0.0
	var applied := 0.0
	var declared := 0.0
	var rake := 0.0
	for body in _rig_bodies():
		var bs: GroundDriveSpec = body.spec.ground_drive
		var body_load := 0.0
		var vdir: Vector3 = body.linear_velocity.normalized()
		for w in body.wheels:
			body_load += w.suspension_force
			tyre += w.force_long
			# Per wheel: the four contacts of a body straddling a crest do not share one normal.
			rake += w.suspension_force * w.contact_normal.dot(vdir)
		normal_load += body_load
		applied += VehicleMath.road_resistance(body.linear_velocity, bs.drag_area,
				bs.rolling_resistance, body_load, body.mass, get_physics_process_delta_time()).length()
		declared += VehicleMath.aero_drag(body.linear_velocity.length(), bs.drag_area) \
				+ VehicleMath.rolling_drag(bs.rolling_resistance, body.mass * 9.81)
	var net := tyre - applied + rake
	var up_dot := rake / maxf(normal_load, 1.0)
	print("  %-13s : tyres %.0f N - resistance %.0f N (declared %.0f) + rake %.0f N = %.0f N"
			% ["balance", tyre, applied, declared, rake, net])
	print("  %-13s : contacts %.2f deg %s of perpendicular put %.1f%% of the %.0f N load into"
			% ["  rake", absf(rad_to_deg(asin(clampf(up_dot, -1.0, 1.0)))),
			"ahead" if rake > 0.0 else "behind", absf(up_dot) * 100.0, normal_load]
			+ " travel; a %.4f m/s^2 vs %.4f measured" % [net / all_up, _inst_a])
	_current["balance"] = {"tyre": tyre, "applied": applied, "declared": declared,
			"rake": rake, "net": net}
	# Unreachable ratios: the vehicle carries gears it can never use.
	var top_gear: int = _car.telemetry.gear_byte
	if top_gear > 0 and top_gear < spec.gear_ratios.size():
		print("  %-13s : tops out in gear %d of %d — the taller ratios never engage"
				% ["note", top_gear, spec.gear_ratios.size()])
		_current["gear_note"] = "tops out in gear %d of %d" % [top_gear, spec.gear_ratios.size()]
	if _coast:
		print("  %-13s : %s" % ["hull contacts", _contact_label("accel")])
		_current["accel_contacts"] = _contact_label("accel")
		var v0 := _peak
		_reset_pass(Phase.COAST)
		_coast_v0 = v0
		Input.action_release("accel")
		return
	_car.respawn()
	_reset_pass(Phase.TRACKING)


## Throttle is already released; just watch it slow down.
func _tick_coast() -> void:
	if _t < COAST_SECONDS:
		return
	var v: float = _car.telemetry.speed
	var decel := (_coast_v0 - v) / _t          # m/s^2, averaged over the window
	var all_up := _combination_mass()
	print("  %-13s : %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg"
			% ["coast-down", _coast_v0 * 3.6, v * 3.6, _t, decel, decel / 9.81,
			decel * all_up, all_up])
	print("  %-13s : %s" % ["hull contacts", _contact_label("coast")])
	_current["coast"] = {"v0_kmh": _coast_v0 * 3.6, "v1_kmh": v * 3.6, "t": _t,
			"decel": decel, "decel_g": decel / 9.81, "force_n": decel * all_up, "mass": all_up}
	_current["coast_contacts"] = _contact_label("coast")
	Input.action_press("accel")
	_car.respawn()
	_reset_pass(Phase.TRACKING)


func _report_tracking(skipped: bool) -> void:
	if skipped:
		_current["tracking"] = {"skipped": true}
	else:
		var ok := _drift_peak <= MAX_LATERAL_DRIFT and _heading_peak <= MAX_HEADING_DRIFT
		if not ok:
			_failures += 1
		print("  %-13s : %s  drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg"
				% ["tracking", "PASS" if ok else "FAIL", _drift_peak, _drift_final,
				_track_dist, _heading_peak])
		if not ok:
			print("                 straight-line pull — suspect asymmetric wheel_positions,")
			print("                 a one-sided drive split, or uneven brake torque")
		_current["tracking"] = {"skipped": false, "pass": ok, "drift_peak": _drift_peak,
				"drift_final": _drift_final, "track_dist": _track_dist, "heading_peak": _heading_peak}
	print("")
	_sweep.append(_current)
	_next_vehicle()


func _contact_label(pass_name: String) -> String:
	if _contact_peak == 0:
		return "none during %s (wheels are raycasts, so any contact is the chassis)" % pass_name
	return "x%d during %s, t=%.2f..%.2f s — a window at the very start is the spawn drop" \
			% [_contact_peak, pass_name, _contact_t0, _contact_t1]


func _drive_label(spec: VehicleSpec) -> String:
	var gd := spec.ground_drive
	if gd.driven_front and gd.driven_rear:
		return "AWD"
	return "FWD" if gd.driven_front else "RWD"


## One markdown file per sweep, measured figures beside REFERENCE_SPECS_PATH's real-world
## comparison figures. Named by timestamp so a re-run never overwrites the last one.
func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var lines: Array[String] = []
	lines.append("# Vehicle spec sweep — %s" % stamp)
	lines.append("")
	lines.append("Strip: %.0f x %.0f m flat, surface_grip 1.0, zero steer input, %.0f s cap per pass."
			% [STRIP_WIDTH, STRIP_LENGTH, _seconds])
	lines.append("Reference figures are real-world comparison numbers, not measured — see "
			+ "`tools/vehicle_reference_specs.json`.")
	lines.append("")
	for entry in _sweep:
		lines.append_array(_report_lines(entry))
	var f := FileAccess.open(REPORT_DIR + stamp + ".md", FileAccess.WRITE)
	f.store_string("\n".join(lines))


func _report_lines(e: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var ref: Dictionary = _reference.get(e["variant"], {})
	var ref_label: String = ref.get("label", "no reference data for this variant")
	lines.append("## %s (%s)" % [e["variant"], e["family"]])
	lines.append("")
	if e.has("mass_label"):
		lines.append("%s, %s" % [e["mass_label"], e["drive_label"]])
		lines.append("")
	lines.append("| Metric | Measured | Reference (%s) |" % ref_label)
	lines.append("|---|---|---|")
	if e.has("marks"):
		var marks: Dictionary = e["marks"]
		var ref_marks: Dictionary = ref.get("marks_s", {})
		for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
			var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
			var measured := ("%.2f s" % marks[kmh]) if marks.has(kmh) else "not reached"
			var ref_key := "96.56" if kmh == 96.56 else "%.0f" % kmh
			var ref_v: Variant = ref_marks.get(ref_key)
			var reference := ("%.1f s" % ref_v) if ref_v != null else "not reached"
			lines.append("| %s | %s | %s |" % [label, measured, reference])
		var q_measured := "not reached"
		if marks.has("quarter"):
			var q: Vector2 = marks["quarter"]
			q_measured = "%.2f s @ %.1f km/h" % [q.x, q.y]
		var q_reference := "not reached"
		if ref.has("quarter_mile_s"):
			q_reference = "%.1f s @ %.0f km/h" % [ref["quarter_mile_s"], ref.get("quarter_mile_kmh", 0.0)]
		lines.append("| quarter mile | %s | %s |" % [q_measured, q_reference])
		var top_reference := ("%.0f km/h" % ref["top_speed_kmh"]) if ref.has("top_speed_kmh") else "not reached"
		lines.append("| top speed | %.1f km/h, gear %d @ %.0f rpm | %s |"
				% [e["top_kmh"], e["top_gear"], e["top_rpm"], top_reference])
		lines.append("| distance used | %.0f m of %.0f m%s | — |"
				% [e["dist"], e["run_length"], "  (STRIP RAN OUT)" if e["ran_out"] else ""])
		var b: Dictionary = e["balance"]
		lines.append("| force balance | tyres %.0f N - resistance %.0f N (declared %.0f) + rake %.0f N = %.0f N | — |"
				% [b["tyre"], b["applied"], b["declared"], b["rake"], b["net"]])
		if e.has("gear_note"):
			lines.append("| note | %s | — |" % e["gear_note"])
	if e.has("tracking"):
		var t: Dictionary = e["tracking"]
		if t.get("skipped", false):
			lines.append("| tracking | never reached %.0f km/h, skipped | — |" % (TRACK_START_SPEED * 3.6))
		else:
			lines.append("| tracking | %s, drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg | — |"
					% ["PASS" if t["pass"] else "FAIL", t["drift_peak"], t["drift_final"],
					t["track_dist"], t["heading_peak"]])
	if e.has("coast"):
		var c: Dictionary = e["coast"]
		lines.append("| coast-down | %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg | — |"
				% [c["v0_kmh"], c["v1_kmh"], c["t"], c["decel"], c["decel_g"], c["force_n"], c["mass"]])
		lines.append("| hull contacts (accel) | %s | — |" % e.get("accel_contacts", "n/a"))
		lines.append("| hull contacts (coast) | %s | — |" % e["coast_contacts"])
	lines.append("")
	return lines
