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
## D, automatic gearbox), so every trial is the same drive whatever the body. The pedal climbs to
## the floor whenever the body cannot hold the crawl, so a stuck trial is a floored one: that is
## what a player holding the key gets. `tc` adds a second limit, a driver feathering the pedal to
## hold the WORST driven wheel at the grip curve's 0.12 peak (measure_grade.gd's `tc`, but on the
## worst wheel, not the rear axle's mean): it takes throttle sensitivity out of the answer, and
## what is left is the differentials' own ceiling.
##
## Per trial: CROSSED (every wheel past the patch), STUCK (under STUCK_PROGRESS of forward progress
## in STUCK_S), OFF LANE, or TIMEOUT; the time and mean speed over the patch; seconds of chassis
## contact (wheels are raycasts, so any contact is the body grounding); and per wheel, mean and peak
## |slip| while in contact, plus the share of ticks it spent in the air. `use` is the driven
## wheels' summed traction force over their summed static capacity (mu_long x surface grip x
## normal load, load sensitivity ignored), averaged over the DEMANDING ticks: the body more than
## SHORT_OF_CRAWL under the crawl AND the driver asking for everything (pedal floored, or `tc`
## holding it back at the peak). 1.0 is every driven tyre at its peak, and an open diff's peel reads
## as a low `use` with one wheel's slip far above the others'. `-` means the body never ran short
## with the pedal down: traction was never the limit on that patch. `short` still counts every
## tick under the crawl, the crawl controller's recoveries after a lift included.
##
##   godot --headless --path . res://tools/measure_rough.tscn -- suv
##   godot --headless --path . res://tools/measure_rough.tscn -- tractor-kenney mfwd diff
##   godot --headless --path . res://tools/measure_rough.tscn -- suv lane=mud patch=bumps_20 verbose
##   godot --headless --path . res://tools/measure_rough.tscn -- baseline tc
##
## `baseline` runs the set `docs/vehicles.md` § Rough and soft ground records: suv, tractor-kenney in
## 2WD / MFWD / MFWD + diff lock, sedan and pickup. Add `--fixed-fps 60` BEFORE `--` to run faster
## than real time: one 1/60 s tick per frame, the step itself unchanged (never Engine.time_scale,
## which enlarges the step — docs/vehicles.md).

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

const SETTLE_S := 1.5
const CRAWL_SPEED := 2.0       ## m/s the driver holds, overridden by `speed=`
const PEDAL_GAIN := 0.5        ## pedal units per second per m/s of speed shortfall
const BRAKE_OVER := 0.5        ## m/s over the crawl before the driver brakes
const BRAKE_GAIN := 0.5        ## brake units per m/s past that
const STEER_OFFSET_GAIN := 0.5 ## steer units per metre off the lane's centre line
const STEER_HEADING_GAIN := 3.0 ## steer units per unit of heading error (sin of the angle)
const STUCK_S := 5.0
const STUCK_PROGRESS := 0.25   ## m of forward progress that resets the stuck clock
const TRIAL_S := 60.0
const SHORT_OF_CRAWL := 0.25   ## m/s under the crawl that counts a tick as `short`
## Crawl pedal at or above this is FLOORED: the driver is asking for everything the body has.
const PEDAL_FLOORED := 0.98
const TC_TARGET_SLIP := 0.12   ## the shipped grip curves all peak here
const TC_GAIN := 12.0          ## pedal units per second per unit of slip error
const BODY_FLAG_S := 1.0       ## s of chassis contact the summary table flags

enum Ph { SETTLE, DRIVE, DONE }

var _configs: Array[Dictionary] = []
var _config: Dictionary = {}
var _trials: Array[Vector2i] = []      ## (lane, patch) left for the current config
var _lanes: Array[int] = []
var _patches: Array[int] = []
var _crawl := CRAWL_SPEED
var _tc := false
var _verbose := false

var _level: Level
var _car: BaseVehicle
var _lane := 0
var _patch := 0
var _phase: int = Ph.DONE
var _t := 0.0
var _pedal := 0.0           ## speed governor's pedal, 0..1
var _tc_pedal := 1.0        ## slip limiter's pedal (`tc`), 0..1; the driver presses the lower
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
	if which == "baseline":
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


func _next_config() -> void:
	if _configs.is_empty():
		_print_table()
		get_tree().quit(0)
		return
	_config = _configs.pop_front()
	var variant := String(_config["variant"])
	if _level.vehicle == null or GameState.current_variant != variant:
		_level.set_vehicle(variant)
	_car = _level.vehicle
	_car.contact_monitor = true
	_car.max_contacts_reported = 8
	_trials.clear()
	for lane in _lanes:
		for patch in _patches:
			_trials.append(Vector2i(lane, patch))
	print("\n--- %s: %s, %.0f kg ---" % [_config_label(_config), _drive_label(), _car.mass])
	_next_trial()


func _next_trial() -> void:
	if _trials.is_empty():
		_next_config()
		return
	var trial: Vector2i = _trials.pop_front()
	_lane = trial.x
	_patch = trial.y
	var start := Vector3(float(Layout.LANES[_lane]["x"]),
			Layout.PLATEAU_Y + _car.rest_ride_height(), Layout.patch_start_z(_patch) + Layout.RUN_UP)
	_car.spawn_transform = Transform3D(Basis.IDENTITY, start)
	_car.respawn()
	_phase = Ph.SETTLE
	_t = 0.0
	_pedal = 0.0
	_tc_pedal = 1.0
	_best = 0.0
	_best_t = 0.0
	_trace_t = 0.0
	_stats = {
		"on": false, "t_on": 0.0, "dist": 0.0, "ticks": 0, "body": 0.0,
		"slip_sum": [], "slip_peak": [], "contact": [], "air": [],
		"short_ticks": 0, "demand_ticks": 0, "use_sum": 0.0, "fx_sum": 0.0, "cap_sum": 0.0,
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
	Bridge.set("_active", true)
	Bridge.set("_inbound", {
		"key": 3, "gear": 1, "accel": accel_pct, "brake": brake_pct,
		"steer": steer_pct, "handbrake": 0.0,
		"diff_lock": bool(_config["diff"]), "fwd_drive": bool(_config["mfwd"]),
	})


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	_t += delta
	if _phase == Ph.SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.DRIVE
			_t = 0.0
		return
	var xform := _car.global_transform
	var forward := -xform.basis.z
	var speed := _car.linear_velocity.dot(forward)
	var lane_x := float(Layout.LANES[_lane]["x"])
	var offset := xform.origin.x - lane_x
	var steer := clampf(-(STEER_OFFSET_GAIN * offset + STEER_HEADING_GAIN * forward.x), -1.0, 1.0)
	_pedal = clampf(_pedal + (_crawl - speed) * PEDAL_GAIN * delta, 0.0, 1.0)
	if _tc:
		_tc_pedal = clampf(_tc_pedal + (TC_TARGET_SLIP - _worst_driven_slip()) * TC_GAIN * delta,
				0.0, 1.0)
	var brake := clampf((speed - _crawl - BRAKE_OVER) * BRAKE_GAIN, 0.0, 1.0)
	if brake > 0.0:
		_pedal = 0.0
	_drive(minf(_pedal, _tc_pedal) * 100.0, brake * 100.0, steer * 100.0)

	var progress := Layout.patch_start_z(_patch) + Layout.RUN_UP - xform.origin.z
	if progress > _best + STUCK_PROGRESS:
		_best = progress
		_best_t = _t
	_sample(speed, delta)
	if _verbose:
		_trace(delta)

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


func _worst_driven_slip() -> float:
	var worst := 0.0
	for w in _car.drive.wheels:
		if w.driven and w.in_contact:
			worst = maxf(worst, w.slip)
	return worst


## Accumulates this tick's wheel state while any hub is over the patch (and after, until the
## trial ends, so a body stuck with its rear still on the run-up keeps counting).
func _sample(speed: float, delta: float) -> void:
	var xform := _car.global_transform
	var start_z := Layout.patch_start_z(_patch)
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
	if speed < _crawl - SHORT_OF_CRAWL:
		_stats["short_ticks"] += 1
	# `use` reads only the ticks the driver asks for everything: short of the crawl with the pedal
	# floored, or with `tc` holding it back because the worst wheel is at the peak. A short tick
	# with the pedal still climbing is the crawl controller recovering from a lift, not traction.
	var demanding := _pedal >= PEDAL_FLOORED or (_tc and _tc_pedal < _pedal)
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
		"lane": String(Layout.LANES[_lane]["name"]),
		"patch": String(Layout.PATCHES[_patch]["name"]),
		"result": result,
		"into": Layout.patch_start_z(_patch) - _car.global_position.z,
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
	var line := "      t %5.1f  z %7.2f  v %4.2f  pedal %4.2f  thr %4.2f  gear %d  rpm %5.0f |" % [
			_t, _car.global_position.z, _car.linear_velocity.length(), _pedal,
			_car.drivetrain.applied_throttle, _car.telemetry.gear_byte, _car.telemetry.rpm]
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
		line += " %-14s" % cell
	if line != "":
		print(line)


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
