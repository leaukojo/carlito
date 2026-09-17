extends Node3D
## Dev utility: measures a coupled tractor unit's launch on a flat full-grip strip — steer-axle
## load, rear travel, pitch, joint pitch, chassis contacts, and the air gate — through
## spawn -> full throttle -> brake -> E-recouple -> brake-while-charging -> full throttle.
## Optional `front_z=<float>` / `com_z=<float>` args (variant name is args[0]) apply an
## in-memory geometry override for what-if runs, without touching the shipped spec.
##
## Driven through the BRIDGE rather than the keyboard: InputRouter.arbitrate_local latches
## GEAR_R the moment `brake_reverse` is held under REVERSE_ENGAGE_SPEED, which turns a
## standstill brake application into a full-throttle reverse — and P5 (the trailer-charge
## catch-out) is exactly a standstill brake application. The bridge path takes the gear byte
## explicitly, so `brake` stays a brake.
##
## Dev report, not CI: always exits 0.
##
##   godot --headless --path . res://tools/measure_semi_launch.tscn -- semi

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Layers := preload("res://src/physics/collision_layers.gd")

const STRIP_LENGTH := 6000.0
const STRIP_WIDTH := 40.0
const START_Z := 2800.0

const REPORT_DIR := "res://reports/semi_launch/"

const SETTLE_S := 2.0
const THROTTLE_S := 8.0
const STOP_HOLD_S := 2.0
const RECOUPLE_S := 1.0
const CHARGE_BRAKE_S := 3.0
const CHARGE_RELEASE_S := 1.0
const STOP_SPEED := 0.05
const STOP_TIMEOUT_S := 40.0

enum Ph { P1, P2, P3, P4, P5, P6, DONE }

const PH_NAMES := ["P1_settle", "P2_throttle", "P3_brake_stop", "P4_recouple",
		"P5_charge_brake", "P6_throttle", "DONE"]

var _variant := "semi"
var _car: SemiTractor = null
var _phase: int = Ph.P1
var _t := 0.0            ## seconds since the run started
var _pt := 0.0           ## seconds since the current phase started
var _ticks := 0
var _prev_speed := 0.0
var _sub := 0            ## sub-step counter inside a phase (P3 hold, P4 recouple)
var _rows: PackedStringArray = []
var _stats: Array[Dictionary] = []
var _static := {}
var _csv_suffix := ""   ## set by _apply_geometry_override; keeps override runs' CSVs distinct


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_variant = String(args[0])
	if not Catalog.VARIANTS.has(_variant):
		printerr("unknown variant '%s'" % _variant)
		get_tree().quit(1)
		return
	_build_strip()
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate() as SemiTractor
	if _car == null:
		printerr("'%s' is not a SemiTractor" % _variant)
		get_tree().quit(1)
		return
	_apply_geometry_override(args)
	add_child(_car)
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, START_Z))
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_car.contact_monitor = true
	_car.max_contacts_reported = 8
	for i in PH_NAMES.size():
		_stats.append(_new_stats())
	_rows.append("t,phase,speed,gear,rpm,applied_throttle,air_primary,air_secondary,gate,"
			+ "omegaRL,omegaRR,compRL_frac,compRR_frac,suspRL,suspRR,"
			+ "compFL_frac,compFR_frac,suspFL,suspFR,front_contact,"
			+ "pitch_deg,trailer_pitch_deg,joint_pitch_deg,chassis_contacts,trailer_air,"
			+ "bogie_comp_frac,rear_axle_kg,trailer_axle_kg")
	var gd: GroundDriveSpec = _car.spec.ground_drive
	print("=== semi rear-drag probe: %s ===" % _variant)
	print("  mass %.0f kg, com %s, wheelbase %.2f m" % [_car.spec.mass, _car.spec.center_of_mass,
			absf(gd.wheel_positions[2].z - gd.wheel_positions[0].z)])
	print("  wheel_positions %s" % [gd.wheel_positions])
	if _csv_suffix != "":
		print("  geometry override applied:%s" % _csv_suffix)
	print("  rest_length %.3f m, spring_rate %.0f N/m -> spring_rate*rest_length = %.0f N,"
			% [gd.rest_length, gd.spring_rate, gd.spring_rate * gd.rest_length]
			+ " max_suspension_force %.0f N" % gd.max_suspension_force)
	print("  kingpin local (FifthWheel.KINGPIN_LOCAL) %s" % FifthWheel.KINGPIN_LOCAL)
	print("  driving over the BRIDGE (gear byte 1, key 3) — see the script header")
	print("  phase P1_settle at t=0.000")
	_drive(0.0, 0.0)


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
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = Layers.DYNAMIC
	ground.position = Vector3(0.0, -1.0, 0.0)  # top face at y = 0
	ground.add_child(collision)
	ground.add_child(visual)
	add_child(ground)


## Optional in-memory geometry override, driven by extra command-line args of the form
## front_z=<float> / com_z=<float> (variant name is args[0]). Applied BEFORE add_child so
## BaseVehicle._ready / WheelDrive._init build the wheels from the overridden spec. spec is
## a shared Resource loaded straight from the .tres, so it is duplicated first — nothing is
## written back to it.
func _apply_geometry_override(args: PackedStringArray) -> void:
	var front_z := NAN
	var com_z := NAN
	for i in range(1, args.size()):
		var a := String(args[i])
		if a.begins_with("front_z="):
			front_z = a.substr(8).to_float()
		elif a.begins_with("com_z="):
			com_z = a.substr(6).to_float()
	if is_nan(front_z) and is_nan(com_z):
		return
	_car.spec = _car.spec.duplicate(true)
	var gd: GroundDriveSpec = _car.spec.ground_drive
	if not is_nan(front_z):
		var positions := gd.wheel_positions
		for i in positions.size():
			if positions[i].z < 0.0:
				positions[i] = Vector3(positions[i].x, positions[i].y, front_z)
		gd.wheel_positions = positions
		_csv_suffix += "_fz%.2f" % front_z
	if not is_nan(com_z):
		var com := _car.spec.center_of_mass
		_car.spec.center_of_mass = Vector3(com.x, com.y, com_z)
		_csv_suffix += "_comz%.2f" % com_z


## sloppyCAN's inbound stash, written straight into the (desktop-inert) Bridge autoload.
## Percentages are the contract's "in" ranges; bridge_source normalizes them.
func _drive(accel_pct: float, brake_pct: float) -> void:
	Bridge.set("_active", true)
	Bridge.set("_inbound", {
		"key": 3, "gear": 1, "accel": accel_pct, "brake": brake_pct,
		"steer": 0.0, "handbrake": 0.0,
	})


func _new_stats() -> Dictionary:
	return {
		"ticks": 0, "t0": -1.0, "t1": -1.0,
		"max_rear_comp": 0.0, "bottom_ticks": 0,
		"max_rear_susp": 0.0, "min_front_susp": INF, "front_air_ticks": 0,
		"max_pitch": -INF, "min_pitch": INF, "max_joint": -INF, "min_joint": INF,
		"contact_ticks": 0, "contact_t0": -1.0, "contact_t1": -1.0, "contact_peak": 0,
		"gate_ticks": 0, "gate_above3_ticks": 0, "pinned_rolling_ticks": 0,
		"min_air1": INF, "min_air2": INF,
		"peak_accel": -INF, "max_speed": 0.0,
		"t_2ms": -1.0, "t_5ms": -1.0,
		"max_rear_axle_kg": 0.0, "min_rear_axle_kg": INF,
	}


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	_t += delta
	_pt += delta
	_ticks += 1
	var s := _sample(delta)
	_rows.append(_row(s))
	_accumulate(_stats[_phase], s)
	if _phase == Ph.P1 and _static.is_empty() \
			and _ticks > TowHost.SPAWN_COUPLE_TICKS + 30 and _pt >= SETTLE_S - 0.2:
		_static = s.duplicate(true)
	_advance(s)


func _rear_wheel(left: bool) -> RayWheel:
	for w in _car.wheels:
		if w.is_rear and ((w.anchor.x < 0.0) == left):
			return w
	return null


func _front_wheel(left: bool) -> RayWheel:
	for w in _car.wheels:
		if not w.is_rear and ((w.anchor.x < 0.0) == left):
			return w
	return null


func _sample(delta: float) -> Dictionary:
	var t := _car.telemetry as TruckTelemetry
	var gd: GroundDriveSpec = _car.spec.ground_drive
	var rl := _rear_wheel(true)
	var rr := _rear_wheel(false)
	var fl := _front_wheel(true)
	var fr := _front_wheel(false)
	var speed: float = t.speed
	var accel := (speed - _prev_speed) / delta
	_prev_speed = speed

	var trailer: TowedBody = _car._fifth_wheel.trailer if _car._fifth_wheel != null else null
	var trailer_pitch := 0.0
	var bogie_frac := 0.0
	if trailer != null and is_instance_valid(trailer):
		trailer_pitch = VehicleMath.pitch_deg(trailer.global_transform.basis)
		var tgd: GroundDriveSpec = trailer.spec.ground_drive
		var n := 0
		for w in trailer.wheels:
			bogie_frac += w.compression / tgd.rest_length
			n += 1
		if n > 0:
			bogie_frac /= float(n)

	var kingpin_y: float = (_car.global_transform * FifthWheel.KINGPIN_LOCAL).y
	return {
		"t": _t,
		"phase": PH_NAMES[_phase],
		"speed": speed,
		"accel": accel,
		"gear": t.gear_byte,
		"rpm": t.rpm,
		"applied_throttle": _car.drivetrain.applied_throttle,
		"air1": t.air_primary,
		"air2": t.air_secondary,
		"gate": TruckTelemetry.spring_brakes_applied(t.air_primary, t.air_secondary),
		"omegaRL": rl.omega, "omegaRR": rr.omega,
		"compRL": rl.compression / gd.rest_length, "compRR": rr.compression / gd.rest_length,
		"suspRL": rl.suspension_force, "suspRR": rr.suspension_force,
		"compFL": fl.compression / gd.rest_length, "compFR": fr.compression / gd.rest_length,
		"suspFL": fl.suspension_force, "suspFR": fr.suspension_force,
		"front_contact": fl.in_contact and fr.in_contact,
		"front_wheels_up": (0 if fl.in_contact else 1) + (0 if fr.in_contact else 1),
		"pitch": t.pitch,
		"trailer_pitch": trailer_pitch,
		"joint_pitch": t.pitch - trailer_pitch,
		"contacts": _car.get_contact_count(),
		"trailer_air": _car._trailer_air,
		"bogie_comp": bogie_frac,
		"rear_axle_kg": t.axle_load,
		"trailer_axle_kg": t.trailer_axle_load,
		"bogie_kg": (TruckTelemetry.axle_load_kg(trailer.bogie_suspension_force())
				if trailer != null and is_instance_valid(trailer) else 0.0),
		"kingpin_y": kingpin_y,
		"coupled": trailer != null and is_instance_valid(trailer),
	}


func _row(s: Dictionary) -> String:
	return ("%.4f,%s,%.4f,%d,%.1f,%.4f,%.4f,%.4f,%d,%.4f,%.4f,%.5f,%.5f,%.1f,%.1f,"
			+ "%.5f,%.5f,%.1f,%.1f,%d,%.4f,%.4f,%.4f,%d,%.4f,%.5f,%.1f,%.1f") % [
		s["t"], s["phase"], s["speed"], s["gear"], s["rpm"], s["applied_throttle"],
		s["air1"], s["air2"], 1 if s["gate"] else 0,
		s["omegaRL"], s["omegaRR"], s["compRL"], s["compRR"], s["suspRL"], s["suspRR"],
		s["compFL"], s["compFR"], s["suspFL"], s["suspFR"], 1 if s["front_contact"] else 0,
		s["pitch"], s["trailer_pitch"], s["joint_pitch"], s["contacts"], s["trailer_air"],
		s["bogie_comp"], s["rear_axle_kg"], s["trailer_axle_kg"],
	]


func _accumulate(st: Dictionary, s: Dictionary) -> void:
	st["ticks"] = int(st["ticks"]) + 1
	if float(st["t0"]) < 0.0:
		st["t0"] = s["t"]
	st["t1"] = s["t"]
	var rear_comp: float = maxf(s["compRL"], s["compRR"])
	st["max_rear_comp"] = maxf(st["max_rear_comp"], rear_comp)
	if rear_comp >= 0.99:
		st["bottom_ticks"] = int(st["bottom_ticks"]) + 1
	st["max_rear_susp"] = maxf(st["max_rear_susp"], maxf(s["suspRL"], s["suspRR"]))
	st["min_front_susp"] = minf(st["min_front_susp"], minf(s["suspFL"], s["suspFR"]))
	if int(s["front_wheels_up"]) > 0:
		st["front_air_ticks"] = int(st["front_air_ticks"]) + 1
	st["max_pitch"] = maxf(st["max_pitch"], s["pitch"])
	st["min_pitch"] = minf(st["min_pitch"], s["pitch"])
	if bool(s["coupled"]):
		st["max_joint"] = maxf(st["max_joint"], s["joint_pitch"])
		st["min_joint"] = minf(st["min_joint"], s["joint_pitch"])
	var contacts := int(s["contacts"])
	if contacts > 0:
		st["contact_ticks"] = int(st["contact_ticks"]) + 1
		st["contact_peak"] = maxi(int(st["contact_peak"]), contacts)
		if float(st["contact_t0"]) < 0.0:
			st["contact_t0"] = s["t"]
		st["contact_t1"] = s["t"]
	if bool(s["gate"]):
		st["gate_ticks"] = int(st["gate_ticks"]) + 1
		if minf(s["air1"], s["air2"]) >= TruckTelemetry.AIR_SPRING_BRAKE_BAR:
			st["gate_above3_ticks"] = int(st["gate_above3_ticks"]) + 1
	if absf(s["omegaRL"]) < 1e-9 and absf(s["omegaRR"]) < 1e-9 and absf(s["speed"]) > 0.5:
		st["pinned_rolling_ticks"] = int(st["pinned_rolling_ticks"]) + 1
	st["min_air1"] = minf(st["min_air1"], s["air1"])
	st["min_air2"] = minf(st["min_air2"], s["air2"])
	st["peak_accel"] = maxf(st["peak_accel"], s["accel"])
	st["max_speed"] = maxf(st["max_speed"], s["speed"])
	if float(st["t_2ms"]) < 0.0 and float(s["speed"]) >= 2.0:
		st["t_2ms"] = float(s["t"]) - float(st["t0"])
	if float(st["t_5ms"]) < 0.0 and float(s["speed"]) >= 5.0:
		st["t_5ms"] = float(s["t"]) - float(st["t0"])
	st["max_rear_axle_kg"] = maxf(st["max_rear_axle_kg"], s["rear_axle_kg"])
	st["min_rear_axle_kg"] = minf(st["min_rear_axle_kg"], s["rear_axle_kg"])


func _to_phase(next: int) -> void:
	_phase = next
	_pt = 0.0
	_sub = 0
	print("  phase %s at t=%.3f" % [PH_NAMES[next], _t])


func _advance(s: Dictionary) -> void:
	match _phase:
		Ph.P1:
			if _ticks >= TowHost.SPAWN_COUPLE_TICKS and _pt >= SETTLE_S:
				_to_phase(Ph.P2)
				_drive(100.0, 0.0)
		Ph.P2:
			if _pt >= THROTTLE_S:
				_to_phase(Ph.P3)
				_drive(0.0, 100.0)
		Ph.P3:
			if _sub == 0:
				if absf(s["speed"]) < STOP_SPEED or _pt >= STOP_TIMEOUT_S:
					_sub = 1
					_pt = 0.0
					print("    stopped at t=%.3f (speed %.4f), holding the brake %.0f s"
							% [_t, s["speed"], STOP_HOLD_S])
			elif _pt >= STOP_HOLD_S:
				_to_phase(Ph.P4)
				_drive(0.0, 0.0)
				_car.set_attachment(TrailerCatalog.BOBTAIL)
				print("    dropped the trailer (bobtail) at t=%.3f" % _t)
		Ph.P4:
			if _sub == 0:
				_sub = 1
				_car.set_attachment(TrailerCatalog.first())
				print("    re-coupled by driving at t=%.3f, trailer_air=%.3f"
						% [_t, _car._trailer_air])
				_pt = 0.0
			elif _pt >= RECOUPLE_S:
				_to_phase(Ph.P5)
				_drive(0.0, 100.0)
		Ph.P5:
			if _sub == 0 and _pt >= CHARGE_BRAKE_S:
				_sub = 1
				_pt = 0.0
				_drive(0.0, 0.0)
				print("    brake released at t=%.3f (air %.3f / %.3f, trailer_air %.3f)"
						% [_t, s["air1"], s["air2"], _car._trailer_air])
			elif _sub == 1 and _pt >= CHARGE_RELEASE_S:
				_to_phase(Ph.P6)
				_drive(100.0, 0.0)
		Ph.P6:
			if _pt >= THROTTLE_S:
				_finish()


func _finish() -> void:
	_phase = Ph.DONE
	_write_csv()
	_print_summary()
	get_tree().quit(0)


func _write_csv() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	var path := "%s%s%s.csv" % [REPORT_DIR, _variant, _csv_suffix]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("could not write %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string("\n".join(_rows))
	f.close()
	print("\nCSV: %s (%d rows)" % [ProjectSettings.globalize_path(path), _rows.size() - 1])


func _f(v: float) -> String:
	return "n/a" if not is_finite(v) else "%.3f" % v


func _print_summary() -> void:
	var gd: GroundDriveSpec = _car.spec.ground_drive
	var spring_max := gd.spring_rate * gd.rest_length
	print("\n===== SUMMARY: %s =====" % _variant)
	print("spec: mass %.0f kg, com %s, wheelbase %.2f m, rest_length %.3f m,"
			% [_car.spec.mass, _car.spec.center_of_mass,
			absf(gd.wheel_positions[2].z - gd.wheel_positions[0].z), gd.rest_length]
			+ " spring_rate %.0f N/m" % gd.spring_rate)
	print("       spring_rate*rest_length = %.0f N/wheel, max_suspension_force = %.0f N"
			% [spring_max, gd.max_suspension_force])
	print("       joint pitch limit = %.1f deg (FifthWheel.PITCH_LIMIT_DEG)"
			% FifthWheel.PITCH_LIMIT_DEG)

	print("\n-- P1 static pose (end of settle, coupled, no input) --")
	if _static.is_empty():
		print("   not captured")
	else:
		print("   tractor pitch      : %.3f deg   (+ = nose up)" % _static["pitch"])
		print("   trailer pitch      : %.3f deg" % _static["trailer_pitch"])
		print("   joint pitch        : %.3f deg  of the %.1f deg stop"
				% [_static["joint_pitch"], FifthWheel.PITCH_LIMIT_DEG])
		print("   rear comp frac     : RL %.4f  RR %.4f" % [_static["compRL"], _static["compRR"]])
		print("   front comp frac    : FL %.4f  FR %.4f" % [_static["compFL"], _static["compFR"]])
		print("   rear susp force    : RL %.0f N  RR %.0f N" % [_static["suspRL"], _static["suspRR"]])
		print("   front susp force   : FL %.0f N  FR %.0f N" % [_static["suspFL"], _static["suspFR"]])
		print("   rear axle load     : %.0f kg   trailer bogie %.0f kg"
				% [_static["rear_axle_kg"], _static["bogie_kg"]])
		print("   kingpin over road  : %.4f m (chassis * FifthWheel.KINGPIN_LOCAL)"
				% _static["kingpin_y"])
		print("   fifth-wheel marker : %s (TowHost.marker_local)" % _car._fifth_wheel.marker_local())
	for i in Ph.DONE:
		_print_phase(i, spring_max, gd.max_suspension_force)


func _print_phase(i: int, spring_max: float, susp_cap: float) -> void:
	var st: Dictionary = _stats[i]
	if int(st["ticks"]) == 0:
		return
	print("\n-- %s  (t %.3f .. %.3f, %d ticks) --" % [PH_NAMES[i], st["t0"], st["t1"], st["ticks"]])
	print("   rear comp frac max : %.4f   ticks >= 0.99: %d"
			% [st["max_rear_comp"], st["bottom_ticks"]])
	print("   rear susp force max: %.0f N  (%.1f%% of spring_rate*rest_length %.0f N,"
			% [st["max_rear_susp"], 100.0 * float(st["max_rear_susp"]) / spring_max, spring_max]
			+ " %.1f%% of max_suspension_force %.0f N)"
			% [100.0 * float(st["max_rear_susp"]) / susp_cap, susp_cap])
	print("   front susp force min: %.0f N   ticks with a front wheel out of contact: %d"
			% [st["min_front_susp"], st["front_air_ticks"]])
	print("   tractor pitch      : %s .. %s deg" % [_f(st["min_pitch"]), _f(st["max_pitch"])])
	print("   joint pitch        : %s .. %s deg  (limit +-%.1f)"
			% [_f(st["min_joint"]), _f(st["max_joint"]), FifthWheel.PITCH_LIMIT_DEG])
	print("   chassis contacts   : %d ticks, peak %d, window t=%s..%s"
			% [st["contact_ticks"], st["contact_peak"],
			_f(st["contact_t0"]), _f(st["contact_t1"])])
	print("   gate (spring brakes): %d ticks true; with air min >= 3 bar: %d (must be 0);"
			% [st["gate_ticks"], st["gate_above3_ticks"]]
			+ " both rear omega == 0 while speed > 0.5: %d" % st["pinned_rolling_ticks"])
	print("   air min            : primary %.3f bar, secondary %.3f bar"
			% [st["min_air1"], st["min_air2"]])
	print("   peak fwd accel     : %s m/s^2   max speed %.3f m/s (%.1f km/h)"
			% [_f(st["peak_accel"]), st["max_speed"], float(st["max_speed"]) * 3.6])
	print("   0-2 m/s / 0-5 m/s  : %s s / %s s"
			% [_f(st["t_2ms"]) if float(st["t_2ms"]) >= 0.0 else "not reached",
			_f(st["t_5ms"]) if float(st["t_5ms"]) >= 0.0 else "not reached"])
	print("   rear axle load     : %.0f .. %.0f kg" % [st["min_rear_axle_kg"], st["max_rear_axle_kg"]])
