extends Node3D
## Drives a vehicle down a flat full-grip strip and reports acceleration, top speed and
## straight-line tracking, plus an opt-in cornering pass on a skid pad. Game-mode tool scene
## (needs autoloads + a physics step).
## `track strict` is the CI gate and exits nonzero on a FAIL; the accel/top-speed report
## always exits 0.
## Driven through the bridge stash, as measure_semi_launch / measure_grade / measure_rough are: the
## keyboard path shapes its keys (src/input/key_shaper.gd), which would measure the shaper instead of
## the vehicle.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")

const STRIP_LENGTH := 6000.0

## A body that reaches an edge is flagged, never measured silently.
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
## Ticks the whole front axle may spend off the ground over the pass, launch included: a wheelie.
## The Kenney wheelbases are toy-scale under real COM heights (docs/vehicles.md § Pitch), so a COM
## or damper edit can tip a rear-driven body onto its rear axle with no other test noticing.
const MAX_FRONT_LIFT_TICKS := 0
## Variants whose tracking FAIL is a KNOWN, open defect: still measured, still printed as FAIL,
## but excluded from `strict`'s exit code so one unfixed body does not block every deploy. A
## variant that is not on this list gates CI as before, so a NEW asymmetry still turns the job
## red. Each entry names the plan that owns the fix; delete the entry with the plan. Empty today.
const KNOWN_TRACKING_FAILS: Array[String] = []

# --- coast-down pass (opt-in: pass the `coast` flag) ----------------------
## Cuts throttle at settled top speed and measures the deceleration. The gear byte stays D, so
## the engine's overrun stays in: it is printed beside the declared resistance
## model `0.5 * 1.225 * drag_area * v^2 + rolling_resistance * m * g`, both averaged per tick.
## Also reports chassis contacts: RayWheel is a raycast, so any contact is the hull scraping.
const COAST_SECONDS := 5.0

# --- cornering pass (opt-in: pass the `corner` flag) ----------------------
## The only lateral measurement there is — the tracking pass runs at zero steer, so nothing else
## can see a grip change that only shows up in a corner. Holds a speed, then winds the lock on
## until the tyres give up, and reports the peak lateral acceleration with the axle that
## saturated first. Off by default: CI needs only the tracking gate.
const CORNER_SPEED := 11.11        ## m/s (~40 km/h) held through the pass
const CORNER_RAMP_S := 10.0        ## s from zero steer to full lock
const CORNER_SMOOTH_S := 0.25      ## exponential smoothing on the lateral-g reading
## Past this slip angle the body is sliding, not cornering: `v * yaw_rate` there measures a spin,
## not a grip limit, so the peak stops being sampled and the report says the gate tripped.
const CORNER_MAX_SLIP_ANGLE := 0.5  ## |v_lat| / |v|
## The speed hold is a PI pedal, never bang-bang: full-pedal pulses through a torque-biasing diff
## send the whole engine to the slower wheel or axle, and the pass then reads power-on oversteer
## instead of grip (`race` spun at a reported 1.62 g; the SUV's rear saturated first).
const CORNER_PEDAL_KP := 0.8       ## pedal per m/s of speed error
const CORNER_PEDAL_KI := 0.5       ## pedal per second per m/s of speed error
const CORNER_PEDAL_START := 0.35   ## integral seed when the ramp begins, roughly a car's cruise
const PAD_SIZE := 300.0
const PAD_X := -400.0              ## well clear of the strip's +/- STRIP_WIDTH / 2

# --- braking pass (opt-in: pass the `brake` flag) --------------------------
## Straight stops on the strip, one per pedal in BRAKE_PEDALS: full throttle up to BRAKE_SPEED (or
## 90 % of the top the accel pass found, whichever is lower), then throttle off and the pedal held
## to a stop. Reports distance, mean deceleration, the seconds any wheel of the rig spent past
## BRAKE_LOCK_SLIP (skidding rather than rolling), and the seconds any wheel's ABS held it back.
const BRAKE_SPEED := 27.78         ## m/s (100 km/h)
const BRAKE_PEDALS: Array[float] = [0.3, 0.6, 1.0]
const BRAKE_LOCK_SLIP := 0.3
const BRAKE_STOP_SPEED := 0.3      ## m/s counted as stopped

# --- launch breakdown (accel pass) -----------------------------------------
## Where the time to each LAUNCH_MARKS mark goes, in seconds since the pass began. The buckets
## overlap (a spinning wheel can be in the fuel cut too), except `torque-bound`, which excludes the
## rest: pedal floored, no cut, every driven wheel on the ground under the grip peak, so the tyres
## had grip to spare and more torque would have bought speed. Its `stall` share has the wheel side
## under converter stall (`Drivetrain.converter_free_rpm` at full pedal): the only ticks converter
## torque multiplication could act in.
const LAUNCH_MARKS: Array[float] = [50.0, 100.0]
## Slip that counts as wheelspin: well past the 0.12 grip peak, so `tc` holding the peak reads none.
const SPIN_SLIP := 0.2
const LAUNCH_FLOORED := 0.98       ## pedal at or above this is floored
const TcPedal := preload("res://tools/tc_pedal.gd")

# --- doc presets (`doc=<id>` as arg 1) -------------------------------------
## Each runs a fixed set and rewrites its `docs/vehicles.md` region (`doc_region.gd`). Cornering
## and accel run every wheel-driven variant (accel twice, floored then `tc`, each only to
## 100 km/h); braking the set below, heavies from 90 % of their top.
const DocRegion := preload("res://tools/doc_region.gd")
const DOC_BRAKING: Array[String] = ["sedan", "pickup", "delivery", "garbage-truck", "semi", "race"]
const DOC_SECONDS := 60.0

const REFERENCE_SPECS_PATH := "res://tools/vehicle_reference_specs.json"
const REPORT_DIR := "res://reports/specs_sweep/"

enum Phase { ACCEL, COAST, TRACKING, CORNERING, BRAKING, DONE }

var _queue: Array[String] = []
var _seconds := DEFAULT_SECONDS
var _car: BaseVehicle
var _variant := ""
var _phase := Phase.ACCEL
var _failures := 0
## FAILs that were on KNOWN_TRACKING_FAILS, counted apart so they never reach the exit code.
var _known_failures := 0
## Allowlisted variants that PASSED: the entry is stale and should be deleted with its plan.
var _stale_allowances: Array[String] = []
var _coast := false
## `corner`: run the skid-pad pass after tracking. Off by default so the CI invocation and the
## default dev report are unchanged.
var _corner := false
## `brake`: run the braking pass last. Off by default, like `corner`.
var _brake := false
## `track`: skip the accel/top-speed pass — CI only needs the tracking gate.
var _track_only := false
## `strict`: exit nonzero on a tracking FAIL. Off by default so dev invocation stays a report.
var _strict := false
## `trailer=<name>`: what a body with an attachment axis spawns carrying, by the attachment
## scene's file name (`box`, `flatbed`, `farm_tipper`...) or `bobtail` / `none` for nothing.
## Empty: the catalog's own first entry.
var _trailer := ""
## `doc=<braking|cornering|accel>`: the preset that ran, its region rewritten at the end; empty
## otherwise.
var _doc := ""
## `tc`: the accel pass slip-limits the worst driven wheel (`tc_pedal.gd`) instead of flooring.
var _tc := false
## This accel pass is slip-limited: `tc`, or doc=accel's second run of a body.
var _tc_run := false
var _tc_pedal := 1.0
var _loss := {}     ## launch-breakdown seconds so far this pass (`_sample_launch`)
var _launch := {}   ## `_loss` snapshotted as each LAUNCH_MARKS mark latched, keyed by km/h

# coast pass
var _coast_v0 := 0.0
var _coast_declared := 0.0   ## N, declared resistance summed over the coast's ticks
var _coast_overrun := 0.0    ## N at the road, `Drivetrain.overrun_torque` summed the same way
var _coast_ticks := 0
var _coast_tyres := 0.0      ## N, retarding tyre force over the rig's wheels, summed the same way
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
var _prev_settle_t := 0.0  ## start of the last complete settle window
var _prev_settle_v := 0.0
var _prev_v := 0.0
var _inst_a := 0.0   ## body's own acceleration last tick, for the balance audit
var _lateral_peak := 0.0  ## m the body strayed from the strip's centre line, against the edge

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
var _front_lift_ticks := 0

# cornering pass
var _corner_ramping := false   ## false while still getting up to _corner_speed
## m/s held through this body's pass (`_corner_target`).
var _corner_speed := CORNER_SPEED
var _corner_ramp_t := 0.0
var _corner_lat := 0.0         ## smoothed lateral acceleration, m/s^2
var _corner_peak := 0.0
var _corner_front := 0.0       ## front-axle saturation at the peak
var _corner_rear := 0.0
var _corner_slid := false      ## the slip-angle gate tripped at some point
var _corner_roll := 0.0        ## chassis roll (deg) at the lateral-g peak
var _corner_lifted := 0        ## most wheels off the ground in any one tick of the pass
var _corner_pedal_i := 0.0     ## integral half of the PI speed hold

# braking pass
var _top_seen := 0.0           ## m/s, the accel pass's peak (0 when it did not run)
var _brake_i := 0              ## index into BRAKE_PEDALS
var _brake_target := 0.0       ## m/s the stop starts from
var _brake_on := false         ## false while still getting up to speed
var _brake_v0 := 0.0
var _brake_t := 0.0
var _brake_x0 := Vector3.ZERO
var _brake_lock_t := 0.0       ## s any wheel spent past BRAKE_LOCK_SLIP
var _brake_abs_t := 0.0        ## s any wheel's ABS held its brake back
var _brake_rows: Array[Dictionary] = []

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
	_corner = flags.has("corner")
	_brake = flags.has("brake")
	_track_only = flags.has("track")
	_strict = flags.has("strict")
	_tc = flags.has("tc")
	for f in flags:
		if String(f).begins_with("trailer="):
			_trailer = String(f).substr(8).to_lower()
	if which.begins_with("doc="):
		_doc = which.substr(4)
		_seconds = DOC_SECONDS
		if _doc == "braking":
			_brake = true
		elif _doc == "cornering":
			_track_only = true
			_corner = true
		elif _doc == "accel":
			_tc = false  # the preset runs each body floored, then `tc`
		else:
			printerr("unknown doc preset '%s' — expected doc=braking, doc=cornering or doc=accel"
					% _doc)
			get_tree().quit(1)
			return
	var ref_file := FileAccess.open(REFERENCE_SPECS_PATH, FileAccess.READ)
	_reference = JSON.parse_string(ref_file.get_as_text())
	# Do not speed up with Engine.time_scale: it enlarges the physics step and breaks the
	# locked-60-Hz tuning (default car's 0-100 went 5.30 s -> 6.40 s at time_scale 8).
	MeasureRig.add_slab(self, "Strip", Vector3(STRIP_WIDTH, 2.0, STRIP_LENGTH))
	if _corner:
		# Skid pad: a wide square well off to the side, since a body at full lock circles in a few
		# tens of metres and the strip is only 40 m wide.
		MeasureRig.add_slab(self, "Pad", Vector3(PAD_SIZE, 2.0, PAD_SIZE), PAD_X)
	if which == "all" or _doc == "cornering" or _doc == "accel":
		_queue.assign(_wheel_driven_variants())
	elif _doc == "braking":
		_queue = DOC_BRAKING.duplicate()
	elif Catalog.VARIANTS.has(which):
		_queue = [which]
	else:
		printerr("unknown variant '%s' — expected 'all' or one of: %s" %
				[which, ", ".join(_wheel_driven_variants())])
		get_tree().quit(1)
		return
	print("strip: %.0f x %.0f m flat, surface_grip 1.0, zero steer input, %.0f s cap per pass\n" %
			[STRIP_WIDTH, STRIP_LENGTH, _seconds])
	MeasureRig.drive(100.0, 0.0)
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


func _next_vehicle() -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	if _queue.is_empty():
		if _failures > 0:
			print("%d vehicle(s) with a tracking FAIL" % _failures)
		elif _known_failures > 0:
			print("all vehicles tracked straight except %d known FAIL(s)" % _known_failures)
		else:
			print("all vehicles tracked straight")
		if _known_failures > 0:
			print("  known FAIL(s) allowed by KNOWN_TRACKING_FAILS - see the plan named there")
		for allowed in _stale_allowances:
			print("  NOTE: %s is on KNOWN_TRACKING_FAILS but PASSED - delete the entry" % allowed)
		_write_report()
		if _doc == "braking":
			DocRegion.write(_doc, _braking_table())
		elif _doc == "cornering":
			DocRegion.write(_doc, _cornering_table())
		elif _doc == "accel":
			DocRegion.write(_doc, _accel_table())
		get_tree().quit(1 if _strict and _failures > 0 else 0)
		return
	_variant = _queue.pop_front()
	_current = {"variant": _variant, "family": String(Catalog.VARIANTS[_variant]["family"])}
	_top_seen = 0.0
	_brake_i = 0
	_brake_rows = []
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	_current["abs"] = _car.spec.ground_drive.abs_equipped
	add_child(_car)
	# Strip top is y=0; wheels just touching, no spawn drop onto the springs.
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_apply_trailer()
	if _coast:
		_car.contact_monitor = true
		_car.max_contacts_reported = 8
	_tc_run = _tc
	_reset_pass(Phase.TRACKING if _track_only else Phase.ACCEL)


## Swap the spawn attachment for `trailer=`'s before the first tick: set_attachment only remembers
## an id until the coupling countdown has run, then couples it (TowHost.SPAWN_COUPLE_TICKS).
func _apply_trailer() -> void:
	if _trailer == "" or not _car.has_method(&"attachment_ids"):
		return
	var found := _trailer in ["bobtail", "none"]
	var want := AttachmentCatalog.NONE
	if not found:
		for id: String in _car.call(&"attachment_ids"):
			if id.get_file().get_basename() == _trailer:
				want = id
				found = true
	if not found:
		print("  %s has no attachment '%s'; measured on its spawn attachment" % [_variant, _trailer])
		return
	_car.call(&"set_attachment", want)
	_current["trailer"] = _trailer


func _reset_pass(phase: Phase) -> void:
	_phase = phase
	_t = 0.0
	_peak = 0.0
	_dist = 0.0
	_marks = {}
	_settle_t = 0.0
	_settle_v = 0.0
	_prev_settle_t = 0.0
	_prev_settle_v = 0.0
	# Must reset: a stale _prev_v reads the first tick of a new pass as the last vehicle's terminal speed falling to zero.
	_prev_v = 0.0
	_lateral_peak = 0.0
	_tc_pedal = 1.0
	_loss = {"spin": 0.0, "limiter": 0.0, "shift": 0.0, "torque": 0.0, "stall": 0.0, "gears": {},
			"force": 0.0, "budget": 0.0, "under_peak": 0.0, "past_peak": 0.0, "tick_cap": 0.0,
			"tcs": 0.0}
	_launch = {}
	_coast_v0 = 0.0
	_coast_declared = 0.0
	_coast_overrun = 0.0
	_coast_tyres = 0.0
	_coast_ticks = 0
	_contact_peak = 0
	_contact_t0 = -1.0
	_contact_t1 = -1.0
	_latched = false
	_track_dist = 0.0
	_drift_peak = 0.0
	_drift_final = 0.0
	_heading_peak = 0.0
	_front_lift_ticks = 0
	_corner_ramping = false
	_corner_speed = _corner_target(_car.spec)
	_corner_ramp_t = 0.0
	_corner_lat = 0.0
	_corner_peak = 0.0
	_corner_front = 0.0
	_corner_rear = 0.0
	_corner_slid = false
	_corner_roll = 0.0
	_corner_lifted = 0
	_corner_pedal_i = 0.0
	_brake_on = false
	_brake_v0 = 0.0
	_brake_t = 0.0
	_brake_lock_t = 0.0
	_brake_abs_t = 0.0


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
	elif _phase == Phase.CORNERING:
		_tick_cornering(delta)
	elif _phase == Phase.BRAKING:
		_tick_braking(delta)
	else:
		_tick_tracking()


func _tick_accel(delta: float) -> void:
	# The pedal that drove this tick, then next tick's.
	var pedal := _tc_pedal if _tc_run else 1.0
	if _tc_run:
		# Held through a shift cut: the wheels unload there, and the integral would wind up.
		if not _car.drivetrain.shift_cut_active():
			_tc_pedal = TcPedal.step(_tc_pedal, _car.wheels, delta)
		MeasureRig.drive(_tc_pedal * 100.0, 0.0)
	var v: float = _car.telemetry.speed  # signed m/s, read out of the sim
	_inst_a = (v - _prev_v) / delta
	_prev_v = v
	_dist += absf(v) * delta
	_peak = maxf(_peak, v)
	_lateral_peak = maxf(_lateral_peak, absf(_car.global_position.x))
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		if not _marks.has(kmh) and v * 3.6 >= kmh:
			_marks[kmh] = _t
	if not _marks.has("quarter") and _dist >= 402.34:
		_marks["quarter"] = Vector2(_t, v * 3.6)
	_sample_launch(delta, pedal)
	if _doc == "accel":
		if _marks.has(LAUNCH_MARKS[-1]) or _t >= _seconds:
			_end_launch_run()
		return
	# Plateaued: call it rather than idling at terminal speed for the rest of the budget.
	var settled := _t - _settle_t >= SETTLE_WINDOW
	if settled and _peak - _settle_v < maxf(SETTLE_ABS, _peak * SETTLE_REL):
		_report_accel(false)
		return
	if settled:
		# Kept for the cap note: a cap just past a restart would otherwise report a gain over 0 s.
		_prev_settle_t = _settle_t
		_prev_settle_v = _settle_v
		_settle_t = _t
		_settle_v = _peak
	if _t >= _seconds:
		_report_accel(true)


## One tick of the launch breakdown (§ launch breakdown), until the last LAUNCH_MARKS mark latches.
## The limiter is judged as `Drivetrain.process` judges it, on the driven wheels' raw rpm.
func _sample_launch(delta: float, pedal: float) -> void:
	if _launch.has(LAUNCH_MARKS[-1]):
		return
	var spec: VehicleSpec = _car.spec
	var gd := spec.ground_drive
	var dt: Drivetrain = _car.drivetrain
	var spinning := false
	var spare_grip := true
	var tcs := false
	var omega := 0.0
	var driven := 0
	for w in _car.wheels:
		if not w.driven:
			continue
		omega += w.omega
		driven += 1
		# The body's own TC acts off the ground too (`RayWheel.tick`).
		tcs = tcs or w.tcs_active
		if not w.in_contact:
			spare_grip = false
			continue
		var budget := _long_budget(w, gd)
		_loss["force"] += w.force_long * delta
		_loss["budget"] += budget * delta
		_split_deficit(w, gd, budget, delta)
		if w.slip >= TcPedal.TARGET_SLIP:
			spare_grip = false
			if w.slip > SPIN_SLIP:
				spinning = true
	var wheel_rpm := Drivetrain.wheel_engine_rpm(spec, omega / maxf(1.0, driven), dt.gear_byte)
	var cut := Drivetrain.limiter_cut(spec, wheel_rpm)
	var shifting := dt.shift_cut_active()
	if spinning:
		_loss["spin"] += delta
	if cut:
		_loss["limiter"] += delta
	if shifting:
		_loss["shift"] += delta
	if tcs:
		_loss["tcs"] += delta
	# TC holds the slip just under the peak, which reads as spare grip; a held wheel is not
	# torque-bound.
	if pedal >= LAUNCH_FLOORED and spare_grip and not cut and not shifting and not tcs:
		_loss["torque"] += delta
		if wheel_rpm < Drivetrain.converter_free_rpm(spec, 1.0):
			_loss["stall"] += delta
	var gears: Dictionary = _loss["gears"]
	gears[dt.gear_byte] = float(gears.get(dt.gear_byte, 0.0)) + delta
	for kmh in LAUNCH_MARKS:
		if _marks.has(kmh) and not _launch.has(kmh):
			_launch[kmh] = _loss.duplicate(true)


## Splits one driven contact's `budget - force_long` into `_loss`'s three deficit buckets, which sum
## to it exactly: `tick_cap`, what the one-tick cap took off the curve force where it bound; the
## rest, the curve short of its 1.0 peak (plus the share lateral slip takes), is `under_peak` or
## `past_peak` by the slip's side of TcPedal.TARGET_SLIP. The wheel's fields are from its last tick,
## the body's velocity one step on: the slip denominator is exact under LOW_SPEED_FLOOR, which is
## where the cap binds.
func _split_deficit(w: RayWheel, gd: GroundDriveSpec, budget: float, delta: float) -> void:
	var up := _car.global_transform.basis.y
	var wheel_forward := Basis(up, w.steer_angle) * -_car.global_transform.basis.z
	var forward := (wheel_forward - w.contact_normal * wheel_forward.dot(w.contact_normal)).normalized()
	var vel := _car.linear_velocity \
			+ _car.angular_velocity.cross(w.contact_point - _car.global_position)
	var slip_denom := maxf(absf(vel.dot(forward)), RayWheel.LOW_SPEED_FLOOR)
	var slip_long := w.slip * signf(w.force_long)
	var budget_lat: float = RayWheel.load_scaled_mu(
			gd.mu_lat * w.axle_lat_grip * w.lat_grip_scale * w.surface_grip,
			w.suspension_force, w.corner_mass * 9.81, gd.load_sensitivity) * w.suspension_force
	var curve := RayWheel.combined_slip_force(slip_long,
			-vel.dot(forward.cross(w.contact_normal)) / slip_denom, budget, budget_lat,
			gd.grip_curve).x
	# A COPY of the one-tick longitudinal cap inline in `RayWheel.tick`
	# (`corner_mass * |slip_vel| / delta`): edit both together.
	var cap := w.corner_mass * absf(slip_long * slip_denom) / delta
	var capped := curve - w.force_long if absf(curve) > cap else 0.0
	_loss["tick_cap"] += capped * delta
	_loss["under_peak" if w.slip < TcPedal.TARGET_SLIP else "past_peak"] += \
			(budget - w.force_long - capped) * delta


## "spin 1.20 s, limiter 0.31 s, ...; grip use 0.62 (under peak 0.05, past peak 0.30, tick cap
## 0.03); gears 1 2.10, 2 1.00 s": one LAUNCH_MARKS snapshot. Grip use is the driven tyres' force
## over their `_long_budget`, time-weighted; the bracket is the rest of that budget
## (`_split_deficit`), so the four sum to 1.
static func _loss_label(l: Dictionary) -> String:
	var gears: Array[String] = []
	var bytes: Array = (l["gears"] as Dictionary).keys()
	bytes.sort()
	for g: int in bytes:
		gears.append("%d %.2f" % [g, l["gears"][g]])
	var d := _deficit_shares(l)
	return ("spin %.2f s, limiter %.2f s, shift %.2f s, tcs %.2f s, torque-bound %.2f s"
			+ " (%.2f s under stall);"
			+ " grip use %.2f (under peak %.2f, past peak %.2f, tick cap %.2f); gears %s s") % [
			l["spin"], l["limiter"], l["shift"], l["tcs"], l["torque"], l["stall"], _grip_use(l), d.x,
			d.y, d.z, ", ".join(gears)]


static func _grip_use(l: Dictionary) -> float:
	return float(l["force"]) / maxf(float(l["budget"]), 1.0)


## (under peak, past peak, tick cap), each a share of the time-weighted budget like `_grip_use`.
static func _deficit_shares(l: Dictionary) -> Vector3:
	return Vector3(l["under_peak"], l["past_peak"], l["tick_cap"]) / maxf(float(l["budget"]), 1.0)


func _print_launch() -> void:
	for kmh in LAUNCH_MARKS:
		if _launch.has(kmh):
			print("  %-13s : %s" % ["launch 0-%.0f" % kmh, _loss_label(_launch[kmh])])


## doc=accel: one launch is done. The body runs floored first, then slip-limited, then the next
## body; no top speed, tracking or other pass.
func _end_launch_run() -> void:
	var marks := {}
	for kmh in LAUNCH_MARKS:
		if _marks.has(kmh):
			marks[kmh] = _marks[kmh]
	print("=== %s, %s ===" % [_variant, "tc" if _tc_run else "floored"])
	for kmh in LAUNCH_MARKS:
		print("  %-13s : %s" % ["0-%.0f km/h" % kmh,
				("%.2f s" % marks[kmh]) if marks.has(kmh) else "not reached in %.0f s" % _seconds])
	_print_launch()
	_current["launch_tc" if _tc_run else "launch"] = {"tc": _tc_run, "marks": marks,
			"loss": _launch.duplicate(true)}
	_current["towed_kg"] = _combination_mass() - _car.spec.mass
	MeasureRig.drive(100.0, 0.0)
	if _tc_run:
		_tc_run = false
		_finish_vehicle()
		return
	_car.respawn()
	_tc_run = true
	_reset_pass(Phase.ACCEL)


func _tick_tracking() -> void:
	var pos := _car.global_position
	if _front_lifted():
		_front_lift_ticks += 1
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


## Every wheel on the foremost axle (front = -Z) is out of contact while another one is down. Not
## "no front contact" alone: before the first wheel tick every wheel reads out of contact.
func _front_lifted() -> bool:
	var front_z := INF
	for w in _car.wheels:
		front_z = minf(front_z, w.anchor.z)
	var other_down := false
	for w in _car.wheels:
		if is_equal_approx(w.anchor.z, front_z):
			if w.in_contact:
				return false
		elif w.in_contact:
			other_down = true
	return other_down


## CORNER_SPEED, or just under a governor that would never let the body reach it (the tractor):
## where the fade starts, so the hold has throttle left.
static func _corner_target(spec: VehicleSpec) -> float:
	if spec.speed_limit_kmh > 0.0:
		return minf(CORNER_SPEED, spec.speed_limit_kmh / 3.6 - Drivetrain.GOVERNOR_BAND)
	return CORNER_SPEED


## Hold `_corner_speed` on the pad, then wind the lock on from zero over CORNER_RAMP_S and watch
## what the tyres will hold. Full pedal up to the speed, then a PI hold (CORNER_PEDAL_KP / _KI)
## through the ramp; a governed or slow body simply sits on the pedal.
func _tick_cornering(delta: float) -> void:
	var vel: Vector3 = _car.linear_velocity
	# Horizontal: a body off the pad edge would otherwise reach the speed by falling.
	var speed := Vector2(vel.x, vel.z).length()
	var err := _corner_speed - speed
	if _corner_ramping:
		_corner_pedal_i = clampf(_corner_pedal_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	var pedal := clampf(_corner_pedal_i + err * CORNER_PEDAL_KP, 0.0, 1.0) if _corner_ramping 			else 1.0
	if not _corner_ramping:
		MeasureRig.drive(pedal * 100.0, 0.0)
		# Wait for the speed, but never past the budget — a body that cannot reach 40 km/h says so
		# rather than silently reporting the transient.
		if speed >= _corner_speed:
			_corner_ramping = true
			_corner_pedal_i = CORNER_PEDAL_START
		elif _t >= _seconds:
			print("  %-13s : never reached %.0f km/h, skipped"
					% ["cornering", _corner_speed * 3.6])
			_report_cornering(true)
		return
	_corner_ramp_t += delta
	MeasureRig.drive(pedal * 100.0, 0.0, minf(_corner_ramp_t / CORNER_RAMP_S, 1.0) * 100.0)
	# Lateral acceleration of the motion that actually happened: `v * yaw_rate` is the centripetal
	# term of the body's own velocity and angular velocity, both read out of the sim (rule 3).
	var lat := speed * absf(_car.angular_velocity.y)
	_corner_lat += (lat - _corner_lat) * clampf(delta / CORNER_SMOOTH_S, 0.0, 1.0)
	var airborne := 0
	for w in _car.wheels:
		if not w.in_contact:
			airborne += 1
	_corner_lifted = maxi(_corner_lifted, airborne)
	var slip_angle := absf(vel.dot(_car.global_transform.basis.x)) / maxf(speed, 1.0)
	if slip_angle > CORNER_MAX_SLIP_ANGLE:
		_corner_slid = true
	elif _corner_lat > _corner_peak:
		_corner_peak = _corner_lat
		_corner_front = _axle_saturation(false)
		_corner_rear = _axle_saturation(true)
		_corner_roll = absf(VehicleMath.roll_deg(_car.global_transform.basis))
	if _corner_ramp_t >= CORNER_RAMP_S or _t >= _seconds:
		_report_cornering(false)


## Mean share of the friction ellipse each of one axle's contacts uses,
## `|(force_long / long budget, force_lat / lat budget)|`, 1.0 being a saturated tyre: a driven
## wheel's drive spends the budget its side grip would use (`RayWheel.combined_slip_force`). The
## budgets are rebuilt through `RayWheel.load_scaled_mu` rather than stored on the wheel, so the
## reading cannot drift away from the law the sim actually applied.
func _axle_saturation(rear: bool) -> float:
	var gd: GroundDriveSpec = _car.spec.ground_drive
	var total := 0.0
	var n := 0
	for w in _car.wheels:
		if w.is_rear != rear or not w.in_contact:
			continue
		var ref_load: float = w.corner_mass * 9.81
		var budget_long := _long_budget(w, gd)
		var budget_lat: float = RayWheel.load_scaled_mu(
				gd.mu_lat * w.axle_lat_grip * w.lat_grip_scale * w.surface_grip,
				w.suspension_force, ref_load, gd.load_sensitivity) * w.suspension_force
		total += Vector2(w.force_long / maxf(budget_long, 1.0),
				w.force_lat / maxf(budget_lat, 1.0)).length()
		n += 1
	return total / maxf(float(n), 1.0)


## A contact's longitudinal grip budget (N): load-scaled `mu_long` times its spring load.
static func _long_budget(w: RayWheel, gd: GroundDriveSpec) -> float:
	return RayWheel.load_scaled_mu(gd.mu_long * w.surface_grip, w.suspension_force,
			w.corner_mass * 9.81, gd.load_sensitivity) * w.suspension_force


func _report_cornering(skipped: bool) -> void:
	# Release the lock before anything else: a held steer input would ride into the next vehicle's
	# passes and read there as a chassis that pulls.
	MeasureRig.drive(100.0, 0.0)
	if skipped:
		_current["cornering"] = {"skipped": true, "speed_kmh": _corner_speed * 3.6}
		_after_lateral_passes()
		return
	var axle := "front" if _corner_front >= _corner_rear else "rear"
	var note := "  <-- SLID: peak is the last reading before the body let go" if _corner_slid else ""
	print("  %-13s : peak %.2f m/s^2 (%.2f g) at %.0f km/h; %s saturates first"
			% ["cornering", _corner_peak, _corner_peak / 9.81, _corner_speed * 3.6, axle]
			+ " (front %.2f, rear %.2f)%s" % [_corner_front, _corner_rear, note])
	print("  %-13s : roll %.1f deg at the peak, up to %d wheel(s) off the ground%s"
			% ["", _corner_roll, _corner_lifted,
			"  <-- OVERTURNED" if _car.is_overturned() else ""])
	_current["cornering"] = {"skipped": false, "peak": _corner_peak, "speed_kmh": _corner_speed * 3.6,
			"peak_g": _corner_peak / 9.81, "front": _corner_front, "rear": _corner_rear,
			"axle": axle, "slid": _corner_slid, "roll_deg": _corner_roll,
			"wheels_lifted": _corner_lifted, "overturned": _car.is_overturned()}
	_after_lateral_passes()


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


## `capped`: the time cap ended the pass, not the settle test, so the top figure is a floor.
func _report_accel(capped: bool) -> void:
	var spec: VehicleSpec = _car.spec
	var all_up := _combination_mass()
	# Chassis and all-up mass reported separately where they differ (see _combination_mass).
	var mass_label := "%.0f kg" % spec.mass
	if not is_equal_approx(all_up, spec.mass):
		mass_label = "%.0f kg chassis, %.0f kg all up" % [spec.mass, all_up]
	if _current.has("trailer"):
		mass_label += ", trailer=%s" % _current["trailer"]
	print("=== %s (%s), %s, %s ===" % [_variant, Catalog.VARIANTS[_variant]["family"],
			mass_label, _drive_label(spec)])
	_current["mass_label"] = mass_label
	_current["towed_kg"] = all_up - spec.mass
	_current["drive_label"] = _drive_label(spec)
	_current["marks"] = _marks.duplicate(true)
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
		print("  %-13s : %s" % [label,
				("%.2f s" % _marks[kmh]) if _marks.has(kmh) else "not reached"])
	if _marks.has("quarter"):
		var q: Vector2 = _marks["quarter"]
		print("  %-13s : %.2f s @ %.1f km/h" % ["quarter mile", q.x, q.y])
	if _tc_run:
		print("  %-13s : slip-limited at %.2f on the worst driven wheel (tc)"
				% ["pedal", TcPedal.TARGET_SLIP])
	_print_launch()
	_current["launch"] = {"tc": _tc_run, "loss": _launch.duplicate(true)}
	# The passes after this one run floored.
	_tc_run = false
	MeasureRig.drive(100.0, 0.0)
	# Settled, capped, or a peak the body then lost: three different claims, never one label.
	var v_now: float = _car.telemetry.speed
	var top_label := "top (settled)"
	var top_note := ""
	if capped:
		top_label = "top (time cap)"
		top_note = "  <-- still gaining %.2f km/h over the last %.1f s: a floor, not terminal" \
				% [(_peak - _prev_settle_v) * 3.6, _t - _prev_settle_t]
	elif v_now < _peak * 0.95:
		top_label = "top (lost)"
		top_note = "  <-- speed fell to %.1f km/h after the peak: not terminal" % (v_now * 3.6)
	print("  %-13s : %.1f km/h (%.1f mph), gear %d @ %.0f rpm%s" % [top_label,
			_peak * 3.6, _peak * 2.23694, _car.telemetry.gear_byte, _car.telemetry.rpm, top_note])
	_current["top_label"] = top_label
	_current["top_kmh"] = _peak * 3.6
	_top_seen = _peak
	_current["top_gear"] = _car.telemetry.gear_byte
	_current["top_rpm"] = _car.telemetry.rpm
	# Distance separates "settled at terminal speed" from "ran out of strip" (`_peak` is a running maximum).
	var v: float = _car.telemetry.speed
	var ran_out := _dist >= RUN_LENGTH - 50.0
	var off_edge := _lateral_peak >= STRIP_WIDTH * 0.5 - 2.0
	print("  %-13s : %.0f m used of %.0f m, %.0f m left; speed now %.1f km/h%s"
			% ["distance", _dist, RUN_LENGTH, RUN_LENGTH - _dist, v * 3.6,
			"  <-- STRIP RAN OUT, top speed is not terminal" if ran_out else ""])
	print("  %-13s : %.1f m off the centre line at most, %.0f m to the edge%s"
			% ["  lateral", _lateral_peak, STRIP_WIDTH * 0.5,
			"  <-- LEFT THE STRIP, nothing after that is a measurement" if off_edge else ""])
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
		# The speed actually held, not `_peak`: a capped or lost run is not at its peak here.
		var v0 := v
		_reset_pass(Phase.COAST)
		_coast_v0 = v0
		MeasureRig.drive(0.0, 0.0)
		return
	_car.respawn()
	_reset_pass(Phase.TRACKING)


## Throttle is already released; just watch it slow down.
func _tick_coast() -> void:
	for body in _rig_bodies():
		var bs: GroundDriveSpec = body.spec.ground_drive
		_coast_declared += VehicleMath.aero_drag(body.linear_velocity.length(), bs.drag_area) \
				+ VehicleMath.rolling_drag(bs.rolling_resistance, body.mass * 9.81)
		for w in body.wheels:
			_coast_tyres -= w.force_long
	var dt: Drivetrain = _car.drivetrain
	_coast_overrun += absf(Drivetrain.overrun_torque(_car.spec, dt.rpm, 0.0, dt.gear_byte)) \
			/ _car.spec.ground_drive.wheel_radius
	_coast_ticks += 1
	if _t < COAST_SECONDS:
		return
	var v: float = _car.telemetry.speed
	var decel := (_coast_v0 - v) / _t          # m/s^2, averaged over the window
	var all_up := _combination_mass()
	var declared := _coast_declared / _coast_ticks
	var overrun := _coast_overrun / _coast_ticks
	var tyres := _coast_tyres / _coast_ticks
	print("  %-13s : %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg"
			% ["coast-down", _coast_v0 * 3.6, v * 3.6, _t, decel, decel / 9.81,
			decel * all_up, all_up])
	print("  %-13s : declared resistance %.0f N + engine overrun %.0f N = %.0f N (mean per tick)"
			% ["  model", declared, overrun, declared + overrun])
	# What reached the road: the overrun less what the wheels' own spin absorbs or gives back.
	print("  %-13s : the tyres carried %.0f N of retardation, so declared + tyres = %.0f N"
			% ["", tyres, declared + tyres])
	print("  %-13s : %s" % ["hull contacts", _contact_label("coast")])
	_current["coast"] = {"v0_kmh": _coast_v0 * 3.6, "v1_kmh": v * 3.6, "t": _t,
			"decel": decel, "decel_g": decel / 9.81, "force_n": decel * all_up, "mass": all_up,
			"declared_n": declared, "overrun_n": overrun, "tyres_n": tyres}
	_current["coast_contacts"] = _contact_label("coast")
	MeasureRig.drive(100.0, 0.0)
	_car.respawn()
	_reset_pass(Phase.TRACKING)


func _report_tracking(skipped: bool) -> void:
	# In track-only mode nothing else prints the variant name (the `===` header belongs to the
	# accel report), so a FAIL in an `all` sweep would be anonymous.
	if _track_only:
		print("=== %s ===" % _variant)
	if skipped:
		_current["tracking"] = {"skipped": true}
	else:
		var ok := _drift_peak <= MAX_LATERAL_DRIFT and _heading_peak <= MAX_HEADING_DRIFT 				and _front_lift_ticks <= MAX_FRONT_LIFT_TICKS
		var known := KNOWN_TRACKING_FAILS.has(_variant)
		if not ok:
			if known:
				_known_failures += 1
			else:
				_failures += 1
		elif known:
			_stale_allowances.append(_variant)
		var verdict := "PASS" if ok else ("FAIL (known)" if known else "FAIL")
		print("  %-13s : %s  drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg,"
				% ["tracking", verdict, _drift_peak, _drift_final,
				_track_dist, _heading_peak]
				+ " front axle off the ground %d ticks" % _front_lift_ticks)
		if _front_lift_ticks > MAX_FRONT_LIFT_TICKS:
			print("                 wheelie — suspect a raised com_y or softer pitch damping")
		elif not ok:
			print("                 straight-line pull — suspect asymmetric wheel_positions,")
			print("                 a one-sided drive split, or uneven brake torque")
		_current["tracking"] = {"skipped": false, "pass": ok, "drift_peak": _drift_peak,
				"drift_final": _drift_final, "track_dist": _track_dist, "heading_peak": _heading_peak,
				"front_lift_ticks": _front_lift_ticks}
	if _corner:
		# Onto the pad: spawn_transform is what respawn() re-lays the body (and any trailer) on.
		# Pad top is y=0, same as the strip.
		_car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(PAD_X, _car.rest_ride_height(), 0.0))
		_car.respawn()
		_reset_pass(Phase.CORNERING)
		return
	_after_lateral_passes()


## Tracking and the optional cornering pass are done: the braking pass if asked for, else the next
## vehicle.
func _after_lateral_passes() -> void:
	if _brake:
		_start_brake_run()
		return
	_finish_vehicle()


## Re-lay the rig at the strip's start (the cornering pass may have moved it to the pad) and run up
## to this stop's entry speed.
func _start_brake_run() -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_reset_pass(Phase.BRAKING)
	_brake_target = BRAKE_SPEED if _top_seen <= 0.0 else minf(BRAKE_SPEED, 0.9 * _top_seen)
	MeasureRig.drive(100.0, 0.0)


func _tick_braking(delta: float) -> void:
	var v: float = _car.telemetry.speed
	if not _brake_on:
		# Up to speed, or out of budget (a body that never gets there brakes from where it is).
		if v >= _brake_target or _t >= _seconds:
			_brake_on = true
			_brake_v0 = v
			_brake_x0 = _car.global_position
			MeasureRig.drive(0.0, BRAKE_PEDALS[_brake_i] * 100.0)
		return
	_brake_t += delta
	var skidding := false
	var anti_lock := false
	for body in _rig_bodies():
		for w in body.wheels:
			if w.in_contact and w.slip > BRAKE_LOCK_SLIP:
				skidding = true
			if w.abs_active:
				anti_lock = true
	if skidding:
		_brake_lock_t += delta
	if anti_lock:
		_brake_abs_t += delta
	if absf(v) > BRAKE_STOP_SPEED and _brake_t < _seconds:
		return
	var dist := (_car.global_position - _brake_x0).length()
	var row := {"pedal": BRAKE_PEDALS[_brake_i], "v0_kmh": _brake_v0 * 3.6, "t": _brake_t,
			"dist": dist, "g": _brake_v0 / maxf(_brake_t, 1e-6) / 9.81, "skid_t": _brake_lock_t,
			"abs_t": _brake_abs_t}
	_brake_rows.append(row)
	print("  %-13s : %3.0f%% from %.0f km/h: %.2f s, %.1f m, %.2f g mean; skidding %.2f s, ABS %.2f s"
			% ["braking", row["pedal"] * 100.0, row["v0_kmh"], row["t"], row["dist"], row["g"],
			row["skid_t"], row["abs_t"]])
	_brake_i += 1
	if _brake_i < BRAKE_PEDALS.size():
		_start_brake_run()
		return
	_current["braking"] = _brake_rows.duplicate(true)
	MeasureRig.drive(100.0, 0.0)
	_finish_vehicle()


func _finish_vehicle() -> void:
	print("")
	_sweep.append(_current)
	_next_vehicle()


func _contact_label(pass_name: String) -> String:
	if _contact_peak == 0:
		return "none during %s (wheels are raycasts, so any contact is the chassis)" % pass_name
	return "x%d during %s, t=%.2f..%.2f s — a real problem, not a spawn drop" \
			% [_contact_peak, pass_name, _contact_t0, _contact_t1]


func _drive_label(spec: VehicleSpec) -> String:
	var gd := spec.ground_drive
	var layout := "AWD"
	if not (gd.driven_front and gd.driven_rear):
		layout = "FWD" if gd.driven_front else "RWD"
	return layout + _diff_label(gd)


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


## The `braking` region: one row per body, a cell per pedal (mean g, distance), noting where any
## wheel's ABS acted or any wheel skidded (slip past BRAKE_LOCK_SLIP).
func _braking_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=braking`; per body `-- <variant>"
			+ " %.0f brake`): stops from 100 km/h, or 90 %% of the top where that is lower (`from`).")
			% [DocRegion.measured(), _seconds])
	lines.append_array(["", "| Body | 30 % pedal | 60 % | 100 % |", "| --- | --- | --- | --- |"])
	for e in _sweep:
		var rows: Array = e.get("braking", [])
		if rows.is_empty():
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		if float(rows[0]["v0_kmh"]) < BRAKE_SPEED * 3.6 - 1.0:
			label += " (from %.0f)" % float(rows[0]["v0_kmh"])
		if not bool(e["abs"]):
			label += " (no ABS)"
		var cells: Array[String] = []
		for b: Dictionary in rows:
			var cell := "%.2f g, %.1f m" % [b["g"], b["dist"]]
			if float(b["abs_t"]) > 0.0:
				cell += ", ABS"
			if float(b["skid_t"]) >= 0.05:
				cell += ", skids %.2f s" % float(b["skid_t"])
			cells.append(cell)
		lines.append("| %s | %s |" % [label, " | ".join(cells)])
	return lines


## The `cornering` region: every wheel-driven variant on the skid pad.
func _cornering_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=cornering`; per body `-- <variant>"
			+ " %.0f track corner`): peak lateral g, the axle that saturates first (by its share of"
			+ " the friction ellipse), roll at the peak, most wheels lifted at once.")
			% [DocRegion.measured(), _seconds])
	lines.append_array(["", "| Body | Peak | Saturates first | Roll | Lifted |",
			"| --- | --- | --- | --- | --- |"])
	for e in _sweep:
		var c: Dictionary = e.get("cornering", {})
		if c.is_empty():
			continue
		if c.get("skipped", false):
			lines.append("| `%s` | never reached %.0f km/h | | | |" % [e["variant"], c["speed_kmh"]])
			continue
		lines.append("| `%s` | %.2f g%s | %s | %.1f deg | %d%s |" % [e["variant"], c["peak_g"],
				" (slid)" if c["slid"] else "", c["axle"], c["roll_deg"], c["wheels_lifted"],
				", overturned" if c["overturned"] else ""])
	return lines


## The `accel` region: every wheel-driven variant's standing start, floored and `tc`, beside the
## real-world reference, with the floored run's 0-50 breakdown.
func _accel_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=accel`; per body `-- <variant> %.0f`,"
			+ " plus `tc` for the slip-limited run): standing starts on the strip, pedal floored (with the"
			+ " body's own traction control where fitted), then"
			+ " slip-limited at the %.2f grip peak (`tc`), beside the real-world reference"
			+ " (`tools/vehicle_reference_specs.json`). The breakdown is the floored run's 0-50"
			+ " seconds: a driven wheel past %.2f slip, the limiter's fuel cut, a shift cut, the body's"
			+ " traction control holding a driven wheel back, and"
			+ " torque-bound (pedal floored, no cut or hold, every driven tyre under its peak), the part of"
			+ " that under converter stall in brackets; then grip use, the driven tyres' force over"
			+ " their load-scaled `mu_long` budget, floored / tc, with the rest of that budget in"
			+ " brackets: the grip curve short of its peak with the slip under / past %.2f, and"
			+ " what the one-tick force cap took off.")
			% [DocRegion.measured(), _seconds, TcPedal.TARGET_SLIP, SPIN_SLIP, TcPedal.TARGET_SLIP])
	lines.append_array(["", "| Body | 0-50 floored / tc / ref | 0-100 floored / tc / ref"
			+ " | 0-50 spin / limiter / shift / tcs / torque-bound (stall) | 0-50 grip use (under peak /"
			+ " past peak / tick cap) |",
			"| --- | --- | --- | --- | --- |"])
	for e in _sweep:
		if not e.has("launch"):
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		var ref: Dictionary = (_reference.get(e["variant"], {}) as Dictionary).get("marks_s", {})
		var cells: Array[String] = []
		for kmh in LAUNCH_MARKS:
			var floored: Dictionary = e["launch"]["marks"]
			var tc: Dictionary = e.get("launch_tc", {}).get("marks", {})
			var ref_v: Variant = ref.get("%.0f" % kmh)
			cells.append("%s / %s / %s" % [_secs(floored.get(kmh)), _secs(tc.get(kmh)),
					_secs(ref_v, "%.1f")])
		var loss: Dictionary = e["launch"]["loss"].get(LAUNCH_MARKS[0], {})
		cells.append("-" if loss.is_empty() else "%.2f / %.2f / %.2f / %.2f / %.2f (%.2f)"
				% [loss["spin"], loss["limiter"], loss["shift"], loss["tcs"], loss["torque"],
				loss["stall"]])
		var tc_loss: Dictionary = e.get("launch_tc", {}).get("loss", {}).get(LAUNCH_MARKS[0], {})
		cells.append("%s / %s" % [_grip_cell(loss), _grip_cell(tc_loss)])
		lines.append("| %s | %s |" % [label, " | ".join(cells)])
	return lines


## "0.80 (0.02 / 0.15 / 0.03)": a grip-use table cell, `-` with no snapshot.
static func _grip_cell(l: Dictionary) -> String:
	if l.is_empty():
		return "-"
	var d := _deficit_shares(l)
	return "%.2f (%.2f / %.2f / %.2f)" % [_grip_use(l), d.x, d.y, d.z]


## Seconds for a table cell, `-` where the mark was not reached (or has no reference).
static func _secs(v: Variant, fmt := "%.2f") -> String:
	return "-" if v == null else fmt % float(v)


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
		lines.append("| %s | %.1f km/h, gear %d @ %.0f rpm | %s |"
				% [e["top_label"], e["top_kmh"], e["top_gear"], e["top_rpm"], top_reference])
		lines.append("| distance used | %.0f m of %.0f m%s | — |"
				% [e["dist"], e["run_length"], "  (STRIP RAN OUT)" if e["ran_out"] else ""])
		var b: Dictionary = e["balance"]
		lines.append("| force balance | tyres %.0f N - resistance %.0f N (declared %.0f) + rake %.0f N = %.0f N | — |"
				% [b["tyre"], b["applied"], b["declared"], b["rake"], b["net"]])
		if e.has("gear_note"):
			lines.append("| note | %s | — |" % e["gear_note"])
	for key in ["launch", "launch_tc"]:
		if not e.has(key):
			continue
		var l: Dictionary = e[key]
		for kmh in LAUNCH_MARKS:
			if (l["loss"] as Dictionary).has(kmh):
				lines.append("| launch 0-%.0f%s | %s | — |" % [kmh, " (tc)" if l["tc"] else "",
						_loss_label(l["loss"][kmh])])
	if e.has("tracking"):
		var t: Dictionary = e["tracking"]
		if t.get("skipped", false):
			lines.append("| tracking | never reached %.0f km/h, skipped | — |" % (TRACK_START_SPEED * 3.6))
		else:
			lines.append("| tracking | %s, drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg | — |"
					% ["PASS" if t["pass"] else "FAIL", t["drift_peak"], t["drift_final"],
					t["track_dist"], t["heading_peak"]])
	if e.has("cornering"):
		var c: Dictionary = e["cornering"]
		if c.get("skipped", false):
			lines.append("| cornering | never reached %.0f km/h, skipped | — |" % c["speed_kmh"])
		else:
			lines.append("| cornering | peak %.2f m/s^2 (%.2f g) at %.0f km/h, %s saturates first (front %.2f, rear %.2f)%s | — |"
					% [c["peak"], c["peak_g"], c["speed_kmh"], c["axle"], c["front"],
					c["rear"], "  (SLID)" if c["slid"] else ""])
	if e.has("braking"):
		for b: Dictionary in e["braking"]:
			lines.append("| braking %.0f%% | from %.0f km/h: %.2f s, %.1f m, %.2f g mean; skidding %.2f s, ABS %.2f s | — |"
					% [b["pedal"] * 100.0, b["v0_kmh"], b["t"], b["dist"], b["g"], b["skid_t"],
					b["abs_t"]])
	if e.has("coast"):
		var c: Dictionary = e["coast"]
		lines.append("| coast-down | %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg | — |"
				% [c["v0_kmh"], c["v1_kmh"], c["t"], c["decel"], c["decel_g"], c["force_n"], c["mass"]])
		lines.append("| coast model | declared %.0f N + overrun %.0f N = %.0f N; tyres carried %.0f N | — |"
				% [c["declared_n"], c["overrun_n"], c["declared_n"] + c["overrun_n"], c["tyres_n"]])
		lines.append("| hull contacts (accel) | %s | — |" % e.get("accel_contacts", "n/a"))
		lines.append("| hull contacts (coast) | %s | — |" % e["coast_contacts"])
	lines.append("")
	return lines
