extends Node3D
## Drives a wheeled variant through every patch of the rough-ground dev level
## (`src/levels/dev/rough_ground/`, layout in `rough_ground_layout.gd`) and reports, per lane and
## patch, whether it crossed and how each wheel slipped doing it. The evidence for the declared
## differentials (`Differential`): an OPEN diff hands both its outputs the torque the lighter-loaded
## one can react, so on uneven or soft ground one wheel spins up and the rest are starved, and a
## biasing, locked or rigid one is what sends the torque on to the wheel that can use it.
## Game-mode tool scene (loads a level, needs autoloads and a physics step). Dev report, exits 0.
##
## Each trial is a standing start RUN_UP metres before a patch, on the lane's centre line: brake
## held while the springs settle, then a driver holding a crawl (`speed=`, default 2 m/s) with the
## accelerator and keeping to the lane's centre with the wheel, both through the bridge (gear byte
## D, automatic gearbox), so every trial is the same drive whatever the body. The crawl is a fuel
## command, fed to the pedal through the pedal map's inverse (`PedalMap.pedal_for`, the least pedal
## reaching it), so its loop gain is the same on every map. It climbs to full fuel whenever the body
## cannot hold the crawl, so a stuck trial is a floored one: the drive a player holding the key
## gets, at the least pedal that delivers it. `tc` adds a second limit, a driver feathering the
## fuel (sent through the same inverse) to hold the WORST driven wheel at the grip curve's 0.12
## peak (`tc_pedal.gd`; unlike measure_grade.gd's `tc`, on the worst wheel, not the rear axle's
## mean): it takes throttle sensitivity out of the answer, and what is left is the differentials'
## own ceiling.
##
## Per trial: CROSSED (every wheel past the patch), STUCK (under STUCK_PROGRESS of forward progress
## in STUCK_S), OFF LANE, or TIMEOUT; the time and mean speed over the patch; seconds of chassis
## contact (wheels are raycasts, so any contact is the body grounding); and per wheel, mean and peak
## |slip| while in contact, plus the share of ticks it spent in the air. `use` is the driven
## wheels' summed traction force over their summed static capacity (mu_long x surface grip x
## normal load, load sensitivity ignored), averaged over the DEMANDING ticks: the body more than
## SHORT_OF_CRAWL under the crawl AND the driver asking for everything (the fuel command floored,
## or `tc` holding the pedal back at the peak). 1.0 is every driven tyre at its peak, and an open
## diff's peel reads as a low `use` with one wheel's slip far above the others'. `-` means the body
## never ran short with full fuel asked: traction was never the limit on that patch. `short` still
## counts every tick under the crawl, the crawl controller's recoveries after a lift included.
##
##   godot --headless --path . res://tools/measure_rough.tscn -- suv
##   godot --headless --path . res://tools/measure_rough.tscn -- tractor-kenney mfwd diff
##   godot --headless --path . res://tools/measure_rough.tscn -- suv lane=mud patch=bumps_20 verbose
##   godot --headless --path . res://tools/measure_rough.tscn -- baseline tc
##   godot --headless --path . res://tools/measure_rough.tscn -- pickup lane=mud tyre=mud
##   godot --headless --path . res://tools/measure_rough.tscn -- garbage-truck rollsteer=0,0.2 angdamp=0
##
## `rollsteer=<front>,<rear>` (deg/deg), `compliance=<deg/kN>` and `angdamp=<1/s>` are
## measure_vehicles.gd's probes, applied by the same `MeasureRig` calls: a rough-ground cell
## attributed to roll or compliance steer or to the body's angular damping without editing its spec.
##
## `baseline` runs the set `docs/vehicle_measurements.md` § Rough and soft ground records: suv, tractor-kenney in
## 2WD / MFWD / MFWD + diff lock, sedan and pickup. Add `--fixed-fps 60` BEFORE `--` to run faster
## than real time: one 1/60 s tick per frame, the step itself unchanged (never Engine.time_scale,
## which enlarges the step — docs/vehicle_measurements.md).
##
##   godot --headless --path . res://tools/measure_rough.tscn -- course=tractor_mud
##
## `course=<challenge id>` drives a reach-zone challenge's own course instead of the lanes: its
## arena level with the course laid on it (as `ChallengeRunner` does), the def's variant and
## attachment, the same driver steering the straight line from the family's VehicleSpawn to its
## zone's centre, once per COURSE_CONFIGS entry; no spawn jitter. The fuel floors unless `speed=`
## sets a crawl. Per run: reached / stuck / off line / timeout, the time from the release against
## the def's `par_s` (the settle is not counted), and the share of ticks a driven wheel spun past
## SPIN_SLIP.

const Layout := preload("res://tools/rough_ground_layout.gd")
const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")

const BASELINE: Array[Dictionary] = [
	{"variant": "suv", "mfwd": false, "diff": false},
	{"variant": "tractor-kenney", "mfwd": false, "diff": false},
	{"variant": "tractor-kenney", "mfwd": true, "diff": false},
	{"variant": "tractor-kenney", "mfwd": true, "diff": true},
	{"variant": "sedan", "mfwd": false, "diff": false},
	{"variant": "pickup", "mfwd": false, "diff": false},
]

## `doc=rough` (arg 1): BASELINE plus `hatchback-sports` floored, then BASELINE under `tc`, and the
## `rough` region of `docs/vehicle_measurements.md` is rewritten (`doc_region.gd`): the mud lane's matrix,
## and every asphalt cell that did not cross.
const DocRegion := preload("res://tools/doc_region.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")
const TcPedal := preload("res://tools/tc_pedal.gd")
const DOC_EXTRA: Dictionary = {"variant": "hatchback-sports", "mfwd": false, "diff": false}

const SETTLE_S := 1.5
const CRAWL_SPEED := 2.0       ## m/s the driver holds, overridden by `speed=`
const FUEL_GAIN := 0.5         ## fuel per second per m/s of speed shortfall
const BRAKE_OVER := 0.5        ## m/s over the crawl before the driver brakes
const BRAKE_GAIN := 0.5        ## brake units per m/s past that
const STEER_OFFSET_GAIN := 0.5 ## steer units per metre off the lane's centre line
const STEER_HEADING_GAIN := 3.0 ## steer units per unit of heading error (sin of the angle)
const STUCK_S := 5.0
const STUCK_PROGRESS := 0.25   ## m of forward progress that resets the stuck clock
const TRIAL_S := 60.0
const SHORT_OF_CRAWL := 0.25   ## m/s under the crawl that counts a tick as `short`
## A crawl fuel command at or above this is FLOORED: the driver is asking for everything the body
## has. Judged on the fuel, not the pedal: on the petrol map full fuel takes a pedal under 1.
const FUEL_FLOORED := 0.98
const BODY_FLAG_S := 1.0       ## s of chassis contact the summary table flags
## --- course (`course=<id>`) ---
## The drivelines a course run compares: open, the rear lock, MFWD, both.
const COURSE_CONFIGS: Array[Dictionary] = [
	{"mfwd": false, "diff": false}, {"mfwd": false, "diff": true},
	{"mfwd": true, "diff": false}, {"mfwd": true, "diff": true},
]
const COURSE_FLOORED := 99.0   ## m/s "crawl": the fuel command floors within two ticks
const COURSE_HALF_WIDTH := 10.0 ## m either side of the line before a run is OFF LINE
const SPIN_SLIP := 0.3         ## the braking table's skid threshold

enum Ph { SETTLE, DRIVE, DONE }

var _configs: Array[Dictionary] = []
var _config: Dictionary = {}
var _trials: Array[Vector2i] = []      ## (lane, patch) left for the current config
var _lanes: Array[int] = []
var _patches: Array[int] = []
var _crawl := CRAWL_SPEED
var _tc := false
var _verbose := false
var _doc := false
## `tyre=<id>`: the `TyreCatalog` class fitted on every config's body ("": its stock).
var _tyre := ""
## `rollsteer=<front>,<rear>`: every config's roll-steer coefficients (deg/deg), in memory
## (`MeasureRig.apply_roll_steer`; NAN: the spec's).
var _roll_steer := Vector2(NAN, NAN)
## `compliance=<deg/kN>`: every config's rear compliance-steer coefficient, in memory
## (`MeasureRig.apply_compliance`; NAN: the spec's).
var _compliance := NAN
## `angdamp=<1/s>`: every config's angular damping REPLACEd, a coupled trailer's too
## (`MeasureRig.apply_angdamp`; NAN: as the body sets it).
var _angdamp := NAN
## `course=<id>`: the challenge driven instead of the lanes (null: the lanes).
var _course: ChallengeDef
var _course_goal: ZoneShape
var _course_spawn := Transform3D.IDENTITY
## The line the driver holds: from `_line_o` along `_line_dir` (level, unit); the lanes' is -z.
var _line_o := Vector3.ZERO
var _line_dir := Vector3.FORWARD
var _prev_pos := Vector3.ZERO

var _level: Level
var _car: BaseVehicle
var _lane := 0
var _patch := 0
var _phase: int = Ph.DONE
var _t := 0.0
var _fuel := 0.0            ## speed governor's fuel command, 0..1
var _pedal := 0.0           ## the pedal it takes (`PedalMap.pedal_for`), 0..1
var _tc_fuel := 1.0         ## slip limiter's fuel (`tc`), 0..1; the driver presses the lower
var _best := 0.0            ## furthest forward progress so far, m
var _best_t := 0.0          ## trial time `_best` last grew by STUCK_PROGRESS
var _trace_t := 0.0
var _stats := {}
var _rows: Array[Dictionary] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "suv"
	_verbose = args.has("verbose")
	_tc = args.has("tc")
	var lane_filter := ""
	var patch_filter := ""
	for a in args:
		var s := String(a)
		if s.begins_with("speed="):
			_crawl = maxf(0.5, s.substr(6).to_float())
		elif s.begins_with("lane="):
			lane_filter = s.substr(5)
		elif s.begins_with("patch="):
			patch_filter = s.substr(6)
	_tyre = MeasureRig.tyre_flag(args)
	if _tyre == "?":
		get_tree().quit(1)
		return
	_roll_steer = MeasureRig.roll_steer_flag(args)
	_compliance = MeasureRig.compliance_flag(args)
	_angdamp = MeasureRig.angdamp_flag(args)
	if which.begins_with("course="):
		if not _load_course(which.substr(7)):
			get_tree().quit(1)
			return
		if not "speed=" in " ".join(args):
			_crawl = COURSE_FLOORED
		for c: Dictionary in COURSE_CONFIGS:
			var config := c.duplicate()
			config["variant"] = _course.variant
			_configs.append(config)
		print("=== course %s on %s: %s, par %.0f s, line %.1f m to %s ===" % [_course.id,
				_course.arena, "floored" if _crawl == COURSE_FLOORED else "crawl %.1f m/s" % _crawl,
				_course.par_s, _course_length(), (_course.goals[0] as ReachZoneGoal).zone])
		_next_config()
		return
	if which == "doc=rough":
		if _tyre != "" or not is_nan(_roll_steer.x) or not is_nan(_compliance) \
				or not is_nan(_angdamp):
			printerr("tyre= / rollsteer= / compliance= / angdamp= change the figures doc=rough"
					+ " tabulates: run them per body")
			get_tree().quit(1)
			return
		_doc = true
		_configs = BASELINE.duplicate(true)
		_configs.append(DOC_EXTRA.duplicate())
		for c: Dictionary in BASELINE:
			var tc := c.duplicate()
			tc["tc"] = true
			_configs.append(tc)
	elif which == "baseline":
		_configs = BASELINE.duplicate(true)
	elif Catalog.VARIANTS.has(which):
		_configs = [{"variant": which, "mfwd": args.has("mfwd"), "diff": args.has("diff")}]
	else:
		printerr("unknown variant '%s' — expected 'baseline' or a catalog variant" % which)
		get_tree().quit(1)
		return
	for i in Layout.LANES.size():
		if lane_filter == "" or String(Layout.LANES[i]["name"]) == lane_filter:
			_lanes.append(i)
	for i in Layout.PATCHES.size():
		if patch_filter == "" or String(Layout.PATCHES[i]["name"]) == patch_filter:
			_patches.append(i)
	if _lanes.is_empty() or _patches.is_empty():
		printerr("no lane/patch matches lane=%s patch=%s" % [lane_filter, patch_filter])
		get_tree().quit(1)
		return
	_level = (load(Layout.LEVEL_PATH) as PackedScene).instantiate() as Level
	_level.initial_variant = String(_configs[0]["variant"])
	add_child(_level)
	var driver := "pedal slip-limited on the worst driven wheel (tc)" if _tc \
			else "pedal floored when short"
	print("=== rough ground: crawl %.1f m/s, %s, standing start %.0f m before each patch ===" % [
			_crawl, driver, Layout.RUN_UP])
	_next_config()


## Loads challenge `id`'s arena with its course under the level root, as `ChallengeRunner` does
## (its props stand on the line), and reads the family's VehicleSpawn and the first goal's zone,
## which must be a reach.
func _load_course(id: String) -> bool:
	_course = ChallengeRegistry.def_of(id)
	if _course == null or _course.goals.is_empty() or not _course.goals[0] is ReachZoneGoal:
		printerr("course=%s: no challenge of that id whose first goal is a zone to reach" % id)
		return false
	if LevelRegistry.scene_of(_course.arena) == "":
		printerr("course=%s: arena '%s' is no registered level" % [id, _course.arena])
		return false
	_level = (load(LevelRegistry.scene_of(_course.arena)) as PackedScene).instantiate() as Level
	_level.initial_variant = _course.variant
	add_child(_level)
	var course := (load(_course.course) as PackedScene).instantiate() as Node3D
	_level.add_child(course)
	var spawn: VehicleSpawn = null
	for n in course.find_children("*", "VehicleSpawn", true, false):
		if (n as VehicleSpawn).accepts(_course.family()):
			spawn = n as VehicleSpawn
			break
	var zone := (_course.goals[0] as ReachZoneGoal).zone
	# The level root sits at the world origin: the zones and the spawn are world space.
	_course_goal = ChallengeZone.zones_of(course).get(zone) as ZoneShape
	if spawn == null or _course_goal == null:
		printerr("course=%s: its course has no %s spawn or no zone '%s'" % [id, _course.family(),
				zone])
		return false
	_course_spawn = spawn.global_transform
	_line_o = _course_spawn.origin
	_line_dir = Vector3(_course_goal.xform.origin.x - _line_o.x, 0.0,
			_course_goal.xform.origin.z - _line_o.z).normalized()
	return true


func _course_length() -> float:
	var d := _course_goal.xform.origin - _line_o
	return Vector2(d.x, d.z).length()


func _next_config() -> void:
	if _configs.is_empty():
		if _course == null:   # a course run's line is its table
			_print_table()
		if _doc:
			DocRegion.write("rough", _doc_table())
		get_tree().quit(0)
		return
	_config = _configs.pop_front()
	if _doc:
		_tc = bool(_config.get("tc", false))
	var variant := String(_config["variant"])
	if _level.vehicle == null or GameState.current_variant != variant:
		_level.set_vehicle(variant)
	_car = _level.vehicle
	if _course != null:
		if _car.has_method(&"set_attachment"):
			_car.call(&"set_attachment", _course.attachment)  ## the def's, as the runner lays it
	elif _car is TractorVehicle:
		_car.call(&"set_attachment", AttachmentCatalog.NONE)  ## bare: an implement's weight moves the axles
	var tyre := MeasureRig.fit_tyre(_car, _tyre)
	MeasureRig.apply_roll_steer(_car, _roll_steer)
	MeasureRig.apply_compliance(_car, _compliance)
	_car.contact_monitor = true
	_car.max_contacts_reported = 8
	_trials.clear()
	if _course != null:
		_trials.append(Vector2i.ZERO)
	for lane in _lanes:
		for patch in _patches:
			_trials.append(Vector2i(lane, patch))
	print("\n--- %s: %s, %.0f kg, tyre %s%s ---" % [_config_label(_config), _drive_label(),
			_car.mass, tyre, _probe_label()])
	_next_trial()


func _next_trial() -> void:
	if _trials.is_empty():
		_next_config()
		return
	var trial: Vector2i = _trials.pop_front()
	_lane = trial.x
	_patch = trial.y
	if _course != null:
		_car.spawn_transform = _course_spawn
	else:
		var start := Vector3(float(Layout.LANES[_lane]["x"]), Layout.PLATEAU_Y
				+ _car.rest_ride_height(), Layout.patch_start_z(_patch) + Layout.RUN_UP)
		_car.spawn_transform = Transform3D(Basis.IDENTITY, start)
		_line_o = start
		_line_dir = Vector3.FORWARD
	_car.respawn()
	_prev_pos = _car.global_position
	_phase = Ph.SETTLE
	_t = 0.0
	_fuel = 0.0
	_pedal = 0.0
	_tc_fuel = 1.0
	_best = 0.0
	_best_t = 0.0
	_trace_t = 0.0
	_stats = {
		"on": false, "t_on": 0.0, "dist": 0.0, "ticks": 0, "body": 0.0,
		"slip_sum": [], "slip_peak": [], "contact": [], "air": [],
		"short_ticks": 0, "demand_ticks": 0, "use_sum": 0.0, "fx_sum": 0.0, "cap_sum": 0.0,
		"spin_ticks": 0,
	}
	for w in _car.drive.wheels:
		(_stats["slip_sum"] as Array).append(0.0)
		(_stats["slip_peak"] as Array).append(0.0)
		(_stats["contact"] as Array).append(0)
		(_stats["air"] as Array).append(0)
	_drive(0.0, 100.0, 0.0)


## Through the bridge, not the keyboard, as measure_grade.gd does: `InputRouter.arbitrate_local`
## latches reverse on a brake held at a standstill, and the settle phase is exactly that.
func _drive(accel_pct: float, brake_pct: float, steer_pct: float) -> void:
	MeasureRig.drive(accel_pct, brake_pct, steer_pct, false, 1, false, 3,
			{"diff_lock": bool(_config["diff"]), "fwd_drive": bool(_config["mfwd"])})


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	MeasureRig.apply_angdamp(_car, _angdamp)
	_t += delta
	if _phase == Ph.SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.DRIVE
			_t = 0.0
		return
	var xform := _car.global_transform
	var forward := -xform.basis.z
	var speed := _car.linear_velocity.dot(forward)
	var right := _line_dir.cross(Vector3.UP)
	var offset := (xform.origin - _line_o).dot(right)
	var steer := clampf(-(STEER_OFFSET_GAIN * offset + STEER_HEADING_GAIN * forward.dot(right)),
			-1.0, 1.0)
	_fuel = clampf(_fuel + (_crawl - speed) * FUEL_GAIN * delta, 0.0, 1.0)
	if _tc:
		_tc_fuel = TcPedal.step(_tc_fuel, _car.drive.wheels, delta, _car.drivetrain)
	var brake := clampf((speed - _crawl - BRAKE_OVER) * BRAKE_GAIN, 0.0, 1.0)
	if brake > 0.0:
		_fuel = 0.0
	_pedal = PedalMap.pedal_for(_car.spec, minf(_fuel, _tc_fuel), _car.drivetrain.rpm)
	_drive(_pedal * 100.0, brake * 100.0, steer * 100.0)

	var progress := (xform.origin - _line_o).dot(_line_dir)
	if progress > _best + STUCK_PROGRESS:
		_best = progress
		_best_t = _t
	_sample(speed, delta)
	if _verbose:
		_trace(delta)

	if _course != null:
		var reached := _course_goal.contains(xform.origin) \
				or _course_goal.crosses(_prev_pos, xform.origin)
		_prev_pos = xform.origin
		if reached:
			_end("REACHED")
		elif absf(offset) > COURSE_HALF_WIDTH:
			_end("OFF LINE")
		elif _t - _best_t > STUCK_S:
			_end("STUCK")
		elif _t > maxf(TRIAL_S, 2.0 * _course.par_s):
			_end("TIMEOUT")
		return
	var end_z := Layout.patch_end_z(_patch)
	var cleared := true
	for w in _car.drive.wheels:
		if (xform * w.anchor).z >= end_z:
			cleared = false
	if cleared:
		_end("CROSSED")
	elif absf(offset) > Layout.LANE_WIDTH * 0.5:
		_end("OFF LANE")
	elif _t - _best_t > STUCK_S:
		_end("STUCK")
	elif _t > TRIAL_S:
		_end("TIMEOUT")


## Accumulates this tick's wheel state while any hub is over the patch (and after, until the
## trial ends, so a body stuck with its rear still on the run-up keeps counting).
func _sample(speed: float, delta: float) -> void:
	var xform := _car.global_transform
	var start_z := Layout.patch_start_z(_patch)
	if _course != null:
		_stats["on"] = true   # a course run counts from the release
	if not _stats["on"]:
		for w in _car.drive.wheels:
			if (xform * w.anchor).z < start_z:
				_stats["on"] = true
		if not _stats["on"]:
			return
	_stats["t_on"] += delta
	_stats["dist"] += maxf(speed, 0.0) * delta
	_stats["ticks"] += 1
	if _car.get_contact_count() > 0:
		_stats["body"] += delta
	var gd := _car.spec.ground_drive
	var fx := 0.0
	var cap := 0.0
	var spun := false
	for i in _car.drive.wheels.size():
		var w: RayWheel = _car.drive.wheels[i]
		if not w.in_contact:
			_stats["air"][i] += 1
			continue
		_stats["contact"][i] += 1
		_stats["slip_sum"][i] += w.slip
		_stats["slip_peak"][i] = maxf(_stats["slip_peak"][i], w.slip)
		if w.driven:
			fx += w.force_long
			cap += gd.mu_long * w.surface_grip * w.suspension_force
			spun = spun or absf(w.slip) > SPIN_SLIP
	if spun:
		_stats["spin_ticks"] += 1
	if speed < _crawl - SHORT_OF_CRAWL:
		_stats["short_ticks"] += 1
	# `use` reads only the ticks the driver asks for everything: short of the crawl with the fuel
	# command floored, or with `tc` holding the pedal back because the worst wheel is at the peak. A
	# short tick with the fuel still climbing is the crawl controller recovering from a lift, not
	# traction.
	var demanding := _fuel >= FUEL_FLOORED or (_tc and _tc_fuel < _fuel)
	if speed < _crawl - SHORT_OF_CRAWL and demanding and cap > 0.0:
		_stats["demand_ticks"] += 1
		_stats["use_sum"] += fx / cap
		_stats["fx_sum"] += fx
		_stats["cap_sum"] += cap


func _end(result: String) -> void:
	_phase = Ph.DONE
	_drive(0.0, 100.0, 0.0)
	var s := _stats
	var n := maxi(1, int(s["ticks"]))
	var short := int(s["short_ticks"])
	var demand := int(s["demand_ticks"])
	var row := {
		"config": _config_label(_config),
		"tc": _tc,
		"lane": "course" if _course != null else String(Layout.LANES[_lane]["name"]),
		"patch": _course.id if _course != null else String(Layout.PATCHES[_patch]["name"]),
		"result": result,
		"into": (_car.global_position - _line_o).dot(_line_dir) if _course != null
				else Layout.patch_start_z(_patch) - _car.global_position.z,
		"spin": float(s["spin_ticks"]) / float(n),
		"t": float(s["t_on"]),
		"v": float(s["dist"]) / maxf(float(s["t_on"]), 0.001),
		"body": float(s["body"]),
		"short": float(short) / float(n),
		"use": float(s["use_sum"]) / float(demand) if demand > 0 else NAN,
		"fx": float(s["fx_sum"]) / float(demand) if demand > 0 else NAN,
		"cap": float(s["cap_sum"]) / float(demand) if demand > 0 else NAN,
		"wheels": [],
	}
	for i in _car.drive.wheels.size():
		var w: RayWheel = _car.drive.wheels[i]
		var c := int(s["contact"][i])
		(row["wheels"] as Array).append({
			"label": _wheel_label(w), "driven": w.driven,
			"mean": float(s["slip_sum"][i]) / float(c) if c > 0 else 0.0,
			"peak": float(s["slip_peak"][i]),
			"air": float(s["air"][i]) / float(n),
		})
	_rows.append(row)
	_print_row(row)
	_next_trial()


func _print_row(r: Dictionary) -> void:
	var outcome := String(r["result"])
	if _course != null:
		print("  %-26s %-9s %5.1f s (par %.0f: %s)  %.1f m along the line  spin %3.0f%%  use %s" % [
				r["config"], outcome, r["t"], _course.par_s,
				"inside" if outcome == "REACHED" and float(r["t"]) <= _course.par_s else "missed",
				r["into"], 100.0 * float(r["spin"]), _use_text(r)])
	else:
		if outcome != "CROSSED":
			outcome += " at %+.1f m" % float(r["into"])
		print("  %-7s %-9s %-18s %5.1f s  %4.2f m/s  body %4.1f s  short %3.0f%%  use %s" % [
				r["lane"], r["patch"], outcome, r["t"], r["v"], r["body"], 100.0 * float(r["short"]),
				_use_text(r)])
	var parts: Array[String] = []
	for w: Dictionary in r["wheels"]:
		parts.append("%s%s %4.2f/%5.2f%s" % [w["label"], "*" if w["driven"] else " ",
				w["mean"], w["peak"],
				(" air %2.0f%%" % (100.0 * float(w["air"]))) if float(w["air"]) > 0.0 else ""])
	print("      slip mean/peak  %s" % "  ".join(parts))


func _use_text(r: Dictionary) -> String:
	if is_nan(float(r["use"])):
		return "  -"
	return "%4.2f (%4.1f of %4.1f kN)" % [r["use"], float(r["fx"]) / 1000.0,
			float(r["cap"]) / 1000.0]


func _trace(delta: float) -> void:
	_trace_t += delta
	if _trace_t < 0.5:
		return
	_trace_t = 0.0
	var line := "      t %5.2f  z %7.2f  v %4.2f  pedal %4.2f  tc %4.2f  thr %4.2f  gear %d  rpm %5.0f c %d |" % [
			_t, _car.global_position.z, _car.linear_velocity.length(), _pedal, _tc_fuel,
			_car.drivetrain.applied_throttle, _car.telemetry.gear_byte, _car.telemetry.rpm,
			_car.drivetrain.coupling_state]
	for w in _car.drive.wheels:
		line += "  %s N %6.0f s %5.2f fx %6.0f" % [_wheel_label(w), w.suspension_force, w.slip,
				w.force_long]
	print(line)


## One row per config and lane, one column per patch: seconds to cross, or where it stopped
## (STUCK / OFF LANE / TIMEOUT, metres past the patch's edge), `b` when the chassis was on the
## ground for BODY_FLAG_S or more (a grounded body is geometry, which no split fixes), then `use`
## where the body ran short.
func _print_table() -> void:
	var head := "%-28s %-7s" % ["config", "lane"]
	for p: Dictionary in Layout.PATCHES:
		head += " %-14s" % p["name"]
	print("\n" + head)
	var line := ""
	var key := ""
	for r in _rows:
		var row_key := "%s|%s" % [r["config"], r["lane"]]
		if row_key != key:
			if line != "":
				print(line)
			key = row_key
			line = "%-28s %-7s" % [r["config"], r["lane"]]
		line += " %-14s" % _cell(r)
	if line != "":
		print(line)


## One summary-table cell: seconds to cross or where it stopped, `b`, then `use`.
func _cell(r: Dictionary) -> String:
	var cell := ""
	match String(r["result"]):
		"CROSSED":
			cell = "%.1fs" % float(r["t"])
		"STUCK":
			cell = "stuck%+.1f" % float(r["into"])
		"OFF LANE":
			cell = "off%+.1f" % float(r["into"])
		_:
			cell = "t/o%+.1f" % float(r["into"])
	if float(r["body"]) >= BODY_FLAG_S:
		cell += "b"
	if not is_nan(float(r["use"])):
		cell += " .%02d" % clampi(roundi(100.0 * float(r["use"])), 0, 99)
	return cell


## The `rough` region: the date and run line, the asphalt cells that did not cross, then the mud
## lane's matrix, floored configs first and `tc` ones under a `tc` line (labels without the ` tc`).
func _doc_table() -> Array[String]:
	var misses: Array[String] = []
	for r in _rows:
		if r["lane"] == "asphalt" and r["result"] != "CROSSED":
			misses.append("`%s` %s (%s)" % [r["config"], r["patch"], _cell(r)])
	var lines := DocRegion.wrap("%s (`measure_rough -- doc=rough`, with `--fixed-fps 60`), mud lane"
			% DocRegion.measured() + " below. Asphalt cells that did not cross: %s."
			% ("none" if misses.is_empty() else ", ".join(misses)))
	lines.append_array(["", "```"])
	var head := "%-25s" % "floored"
	for p: Dictionary in Layout.PATCHES:
		head += " %-14s" % p["name"]
	lines.append(head.strip_edges(false, true))
	var in_tc := false
	var line := ""
	var key := ""
	for r in _rows:
		if r["lane"] != "mud":
			continue
		if String(r["config"]) != key:
			if line != "":
				lines.append(line.strip_edges(false, true))
			key = String(r["config"])
			if bool(r["tc"]) and not in_tc:
				in_tc = true
				lines.append("tc")
			line = "%-25s" % key.replace(" tc", "")
		line += " %-14s" % _cell(r)
	if line != "":
		lines.append(line.strip_edges(false, true))
	lines.append("```")
	return lines


func _config_label(c: Dictionary) -> String:
	var label := String(c["variant"]) + (" tc" if _tc else "")
	if bool(c["mfwd"]):
		label += " mfwd"
	if bool(c["diff"]):
		label += " diff"
	return label


func _drive_label() -> String:
	var gd := _car.spec.ground_drive
	var label := "AWD" if gd.driven_front and gd.driven_rear else ("FWD" if gd.driven_front else "RWD")
	if gd.front_axle_engageable:
		label += " + MFWD %s" % ("on" if bool(_config["mfwd"]) else "off")
	if gd.rear_diff_lockable:
		label += ", rear diff %s" % ("locked" if bool(_config["diff"]) else "open")
	return label + _diff_label(gd)


## The probes on the body, e.g. ", roll steer 0.00 / 0.20 deg/deg (not the spec's)"; empty with none.
func _probe_label() -> String:
	var label := ""
	if not is_nan(_roll_steer.x):
		label += ", roll steer %.2f / %.2f deg/deg (not the spec's)" % [_roll_steer.x, _roll_steer.y]
	if not is_nan(_compliance):
		label += ", compliance steer %.4f deg/kN (not the spec's)" % _compliance
	if not is_nan(_angdamp):
		label += ", angular damping %.2f /s (not the body's)" % _angdamp
	return label


## The declared differentials that are not open (`GroundDriveSpec` § Driveline), e.g.
## ", centre 3.0:1, rear LSD 2.5:1"; empty when every diff is open.
static func _diff_label(gd: GroundDriveSpec) -> String:
	var label := ""
	if gd.centre_diff_rigid:
		label += ", centre rigid"
	elif gd.centre_diff_bias > 1.0:
		label += ", centre %.1f:1" % gd.centre_diff_bias
	if gd.diff_bias_front > 1.0:
		label += ", front LSD %.1f:1" % gd.diff_bias_front
	if gd.diff_bias_rear > 1.0:
		label += ", rear LSD %.1f:1" % gd.diff_bias_rear
	return label


## FL/FR/RL/RR from the anchor (body +Z is rearward, -X is left); a third axle reads as a
## second R pair, which is all a trial table needs.
static func _wheel_label(w: RayWheel) -> String:
	return ("R" if w.is_rear else "F") + ("L" if w.anchor.x < 0.0 else "R")
