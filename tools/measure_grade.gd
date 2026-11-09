extends Node3D
## Two grade questions in one dev tool, because they only mean something against each other:
## what grade a vehicle can still pull away on (`ramp` mode), and what grade a shipped level
## actually asks for (`level=` mode). Game-mode tool scene (needs autoloads + a physics step).
##
## RAMP MODE bisects the steepest angle the body climbs FROM REST — no run-up, which is the
## honest "can it get up there" question and the one a driver asks halfway up. Each trial is a
## fresh body on a fresh ramp over a synthetic grip patch (`MeasureRig.GripPatch`, one surface).
##
## Beside each measurement it prints the three textbook ceilings, so a disagreement points at
## which one bit:
##   traction  tan(a) <= (mu * rear_share - crr) / (1 - mu * h / L)   [driven rear only]
##             tan(a) <= mu - crr                                     [all wheels driven]
## "All wheels driven" includes the tractor with `mfwd` engaged. It is the perfect all-wheel
## figure, which a rigid or biasing centre can approach; an OPEN centre stays capped by its
## lighter axle, under it.
##   torque    F_gear1_at_idle >= m*g*(sin a + crr * cos a)
##   tip       tan(a) <= b / h   [b: COM ahead of the rear axle; standing, so a climb sits under it]
## All are static, single-body and ignore `load_sensitivity`, so they are a reference, not a
## gate. A coupled rig (the semi tows 24 t the moment it spawns) swaps in the rig's mass for the
## torque ceiling and, for traction, `tan(a) <= mu * share - crr` with `share` the driven wheels'
## spring load over the rig's weight, read at the last trial's settle; it prints no tip ceiling.
##
## Dev report, always exits 0.
##
##   godot --headless --path . res://tools/measure_grade.tscn -- tractor-kenney
##   godot --headless --path . res://tools/measure_grade.tscn -- suv mud
##   godot --headless --path . res://tools/measure_grade.tscn -- tractor-kenney mud mfwd diff
##   godot --headless --path . res://tools/measure_grade.tscn -- level=level_2
##   godot --headless --path . res://tools/measure_grade.tscn -- sedan park=5.7 hand
##   godot --headless --path . res://tools/measure_grade.tscn -- sedan creep
##   godot --headless --path . res://tools/measure_grade.tscn -- sedan rollback nohold
##   godot --headless --path . res://tools/measure_grade.tscn -- semi climb grade=8 pedal=0.6
##   godot --headless --path . res://tools/measure_grade.tscn -- semi descent grade=7 km=6 kmh=60
##   godot --headless --path . res://tools/measure_grade.tscn -- sedan stops=10
##   godot --headless --path . res://tools/measure_grade.tscn -- garbage-truck descent per_brake=3357 t0=63 amb=10
##   godot --headless --path . res://tools/measure_grade.tscn -- doc=brake_check

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Groups := preload("res://src/levels/base/carlito_groups.gd")

## Surfaces by `Surface` name (any one is a flag: `Surface.from_key`).
const DEFAULT_SURFACES: Array[String] = ["asphalt", "gravel", "grass", "field", "mud"]

const RAMP_LENGTH := 400.0
const RAMP_WIDTH := 30.0
const RAMP_THICKNESS := 2.0
## Metres up the ramp the body starts, so a failing run has room to slide back without
## running off the bottom edge.
const SPAWN_UP := 60.0

const SETTLE_S := 1.5     ## brake held while the springs take the weight
const CLIMB_S := 12.0     ## full throttle after that
const CLIMB_MIN := 8.0    ## m of up-slope gain that calls a climb early
const SLIDE_BACK := -4.0  ## m of backsliding that calls the trial early
## At the timeout a body is climbing if it is still MOVING UP: right at the limit the climb is
## slow, not absent, and a distance-only test would read a 1 m/s crawl as a failure.
const CLIMB_SPEED := 0.5  ## m/s up the slope at the end of the window
const CLIMB_GAIN := 2.0   ## m gained by then

const BISECT_LO := 0.0
const BISECT_HI := 45.0
const BISECT_STEPS := 7   ## 45 deg / 2^7 -> ~0.35 deg of resolution

## The `tc` loop's slip target: the shipped grip curves all peak at 0.12.
const TC_TARGET_SLIP := 0.12
const TC_GAIN := 12.0     ## fuel units per second per unit of slip error
## Front-axle spring load, as a share of its settled load, below which the `tc` driver lifts off.
const TC_FRONT_KEEP := 0.3
const TC_LIFT_GAIN := 2.0 ## fuel units per second per unit of that share short

const LEVEL_STEP := 4.0   ## m between road-curve samples in level mode

## `doc=grade` (arg 1): this set over asphalt and mud, then the `grade` region of
## `docs/vehicle_measurements.md` is rewritten (`doc_region.gd`). The flags are per job here, not per run.
const DocRegion := preload("res://tools/doc_region.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")
const DOC_SURFACES: Array[String] = ["asphalt", "mud"]
const DOC_JOBS: Array[Dictionary] = [
	{"variant": "sedan", "mfwd": false, "diff": false, "tc": false},
	{"variant": "suv", "mfwd": false, "diff": false, "tc": false},
	{"variant": "suv-luxury", "mfwd": false, "diff": false, "tc": false},
	{"variant": "race-future", "mfwd": false, "diff": false, "tc": false},
	{"variant": "pickup", "mfwd": false, "diff": false, "tc": false},
	{"variant": "garbage-truck", "mfwd": false, "diff": false, "tc": false},
	{"variant": "tractor-kenney", "mfwd": false, "diff": false, "tc": false},
	{"variant": "tractor-kenney", "mfwd": true, "diff": false, "tc": false},
	{"variant": "tractor-kenney", "mfwd": true, "diff": true, "tc": false},
	{"variant": "tractor-kenney", "mfwd": true, "diff": true, "tc": true},
	{"variant": "tractor-cvt", "mfwd": true, "diff": true, "tc": false},
	{"variant": "semi", "mfwd": false, "diff": false, "tc": false},
]

## PARK MODE (`park=<deg>`, flags `hand` / `pawl` / `cross`): the body held on the ramp by its foot
## brake (or handbrake, `hand`, or P alone, `pawl`: no brake, a body with no pawl parks in N), nose
## up the slope (or across it, `cross`), for PARK_HOLD_S after the settle. Reports how far it
## moved: a tyre that holds statically moves nothing. Asphalt only, the hill hold off (`_nohold`):
## the table is the brake hardware's.
const PARK_HOLD_S := 60.0
## `doc=park` (arg 1): this set, then the `park` region of `docs/vehicle_measurements.md` is rewritten.
const DOC_PARK_VARIANTS: Array[String] = ["sedan", "suv", "pickup", "garbage-truck",
		"tractor-kenney", "semi"]
const DOC_PARK_ANGLES: Array[float] = [5.7, 16.7]  ## 10 % and 30 %
const DOC_PARK_MODES: Array[String] = ["foot", "hand", "pawl", "cross"]
## ...plus one handbrake hold per variant on its regulation grade (`BrakeSizing.regulation_grade`:
## 20 % to 3.5 t, 18 % above, the rig's mass for a coupled semi).

enum Ph { SETTLE, CLIMB, PARK_SETTLE, PARK_HOLD, CREEP_SETTLE, CREEP, ROLL_SETTLE, ROLL, ASCENT_SETTLE,
		ASCENT, DESC_SETTLE, DESC_RUNUP, DESC_HOLD, DESC_STOP, DONE }


var _queue: Array[Dictionary] = []    ## jobs left to measure: variant + mfwd / diff / tc
var _surface_list: Array[String] = [] ## surfaces every variant is run over
var _surfaces: Array[String] = []     ## surfaces left for the current variant
var _variant := ""
var _surface := ""
var _verbose := false                 ## print every bisection trial, not just the result
## `tc`: hold the driven slip at the tyre's best (TC_TARGET_SLIP) instead of flooring the pedal, which is
## the difference between what the tyres could do and what a pedal-to-the-floor driver gets.
var _tc := false
## The delivered fuel (0..1) the TC loop holds, sent through the pedal map's inverse
## (`PedalMap.pedal_for`) so one loop gain serves every map: on a governed tractor the pedal is a
## speed setting, which cuts no fuel until the setting reaches the lugging crank.
var _tc_fuel := 1.0
var _front_settle := NAN              ## front-axle spring load at the end of the settle, N
var _pedal := 0.0                     ## `pedal=<0..1>`: hold this throttle instead, diagnostic
var _hold := NAN                      ## `hold=<deg>`: one trial at this angle, diagnostic
var _mfwd := false                    ## tractor MFWD engaged for the run
var _diff := false                    ## tractor rear diff locked for the run
var _doc := false                     ## `doc=grade`: rewrite the doc region at the end
var _park_queue: Array[Dictionary] = []  ## park mode: variant + angle + mode jobs left
var _park_doc := false                ## `doc=park`: rewrite the park region at the end
var _park_mode := "foot"              ## foot | hand | pawl | cross, the current park job's
var _park_reg := false                ## the current job is the regulation-grade handbrake hold
var _park_peak := 0.0                 ## fastest the held body moved after the settle, m/s
var _park_rows: Array[Dictionary] = []
var _creep_queue: Array[String] = []  ## creep mode: converter variants left
var _creep_flat := true               ## the current creep trial is the flat run
var _creep_sum := Vector3.ZERO        ## flat run's last CREEP_MEAN_S: speed m/s, rpm, load %
var _creep_n := 0
var _creep_row := {}
var _creep_rows: Array[Dictionary] = []
var _roll_queue: Array[Dictionary] = []  ## rollback mode: variant + grade jobs left
var _roll_rows: Array[Dictionary] = []
var _roll_grade := 0.0                ## the current rollback job's grade, %
var _roll_delay := 0.0                ## `delay=<s>`: release to pedal
var _roll_min := 0.0                  ## most negative up-slope gain since the release, m
var _roll_go := NAN                   ## s from the release to ROLL_GO_M up the slope
var _roll_held := 0.0                 ## s after the release the hill hold last held
var _nohold := false                  ## `nohold`: the body's hill hold off, on a copy of its spec
var _tipper := false                  ## `tipper`: the tractor spawns with its drawbar tipper
## `cornering_peak=<x>`: the tyre's cornering-stiffness law (`GroundDriveSpec.cornering_peak_load`)
## on a copy of the spec, in memory (NAN: the spec's).
var _cornering_peak := NAN
## climb mode: the shifts so far, each a `MeasureRig.shift_record` plus `load`; the byte engaged
## last tick; the run's grade, %
var _ascent_shifts: Array[Dictionary] = []
var _ascent_byte := 0
var _ascent_grade := 0.0
var _ascent_room := 0.0  ## m of ramp from the start to ASCENT_MARGIN short of its top
## `gear=<1-24>`: climbs and roll-backs in the bridge's manual mode, held in that byte (0: automatic
## D). A start gear the automatic box would leave at once (it downshifts at a standstill), held.
var _held_gear := 0
## `tyre=<id>`: the `TyreCatalog` class fitted on every body ("": its stock), and what the last
## spawn fitted (`MeasureRig.fit_tyre`: the stock where the class is not made in the body's fit).
var _tyre := ""
var _tyre_label := ""
## `wind=<from_deg>:<m/s>` (`MeasureRig.wind_flag`): a steady wind on every body, answered as
## `wind_vector()`. The ramp rises toward -Z, so `wind=0:<m/s>` (out of the north) blows downhill.
var _wind := Vector3.ZERO
## descent and stops mode: the jobs left ({variant, mode, kmh}); the current job's mode, hold speed
## (m/s), the stop under way and the series' length; the run's grade (%) and hold distance (m)
var _dsc_queue: Array[Dictionary] = []
var _dsc_mode := ""
var _dsc_speed := 0.0
var _dsc_stop := 0
var _dsc_stops := 0
var _dsc_grade := 0.0
var _dsc_dist := 0.0
var _dsc_length := 0.0                ## m, the ramp's, sized once for every job of the run
var _dsc_lift := 0.0                  ## m, the ramp's raise (`MeasureRig.tilt_ramp`)
var _dsc_gear := 0                    ## the `gear` mode's held byte
var _dsc_pedal_hold := MeasureRig.PiHold.new(PEDAL_KP, PEDAL_KI)  ## the PIs: foot brake, retarder
var _dsc_ret_hold := MeasureRig.PiHold.new(RETARDER_KP, RETARDER_KI)
var _dsc_x0 := Vector3.ZERO           ## where the hold or the stop began
var _dsc_v0 := 0.0                    ## m/s, the stop's entry speed
var _dsc_gap := 0.0                   ## s, the run-up before the stop
var _dsc_ledger := {}                 ## the energy check's sums (`_ledger_start`)
var _dsc_units := {}                  ## "powered" / "trailer": {peak, min, end, fade} (`_track`)
var _dsc_gears := Vector2i.ZERO       ## lowest and highest gear byte seen on the hold
var _dsc_speed_sum := 0.0             ## m/s summed over the hold's ticks
var _dsc_ticks := 0
var _dsc_cold := {}                   ## variant -> its cold stop (m)
var _dsc_row := {}
var _dsc_rows: Array[Dictionary] = []
var _dsc_doc := false                 ## `doc=brake_fade`: rewrite the region at the end
var _dsc_trailer: TowedBody = null
var _dsc_host: TowHost = null
var _dsc_artic := 0.0                 ## rad, the hold's largest |articulation| (`TowHost.articulation`)
var _dsc_stop_artic := 0.0            ## rad, the same over the stop after it
var _dsc_check := false               ## `doc=brake_check`: rewrite that region at the end
var _dsc_job := {}                    ## the current job, its flags (`DOC_CHECK_JOBS`' keys)
var _dsc_shift := 0.0                 ## °C, the job's `amb` less the model's: on every reported brake
var _dsc_mean := {}                   ## the rig's thermal brakes now: {mean, front, n} (`_track_units`)
## The deceleration PI, its filtered reading (m/s²).
var _dsc_decel_hold := MeasureRig.PiHold.new(DECEL_KP, DECEL_KI)
var _dsc_a := 0.0
var _dsc_v_prev := 0.0
var _dsc_front0 := 0.0                ## °C, the front discs' mean as the stop began
var _dsc_front_loss := 0.0            ## J the front discs shed to the air since then (`BrakeThermal.loss_w`)

var _ramp: StaticBody3D
var _patch: MeasureRig.GripPatch
var _car: BaseVehicle

var _lo := BISECT_LO
var _hi := BISECT_HI
var _step := 0
var _angle := 0.0
var _best := NAN                      ## steepest angle climbed so far, NAN until one is
var _phase: int = Ph.DONE
var _t := 0.0
var _start := Vector3.ZERO
var _gain := 0.0                      ## up-slope metres gained this trial
var _trace_t := 0.0
var _drive_share := NAN               ## driven wheels' share of the rig's weight, at the last settle
var _rows: Array[Dictionary] = []


## The air every body under this tool moves through (`WindField.at`).
func wind_vector() -> Vector3:
	return _wind


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	MeasureRig.common_flags(args)
	var level_id := MeasureRig.flag(args, "level=")
	if level_id != "":
		_report_level(level_id)
		get_tree().quit(0)
		return
	var which := String(args[0]) if args.size() > 0 else "suv"
	_mfwd = args.has("mfwd")
	_verbose = args.has("verbose")
	_tc = args.has("tc")
	_pedal = MeasureRig.float_flag(args, "pedal=", _pedal)
	_hold = MeasureRig.float_flag(args, "hold=", NAN)
	_cornering_peak = MeasureRig.float_flag(args, "cornering_peak=", NAN)
	_held_gear = MeasureRig.gear_flag(args)
	if _held_gear < 0:
		get_tree().quit(1)
		return
	_tyre = MeasureRig.tyre_flag(args)
	if _tyre == "?":
		get_tree().quit(1)
		return
	_wind = MeasureRig.wind_flag(args)
	if is_nan(_wind.x):
		get_tree().quit(1)
		return
	if which.begins_with("doc=") and (not is_nan(_cornering_peak) or _tyre != ""
			or _wind != Vector3.ZERO):
		printerr("cornering_peak= / tyre= / wind= change the figures a doc preset tabulates: run them"
				+ " per body")
		get_tree().quit(1)
		return
	InputRouter.set_manual_gearbox(_held_gear > 0)
	_diff = args.has("diff")
	for i in range(1, args.size()):
		if Surface.from_key(String(args[i])) >= 0:
			_surface_list.append(String(args[i]))
	if _surface_list.is_empty():
		_surface_list = DEFAULT_SURFACES.duplicate()
	_patch = MeasureRig.GripPatch.new()
	_patch.name = "GripPatch"
	add_child(_patch)
	var park := MeasureRig.float_flag(args, "park=", NAN)
	if _held_gear > 0 and (args.has("creep") or which == "doc=park" or not is_nan(park)):
		printerr("gear= holds a start gear for the climbs and the roll-back; creep is D1, park is"
				+ " the hold")
		get_tree().quit(1)
		return
	_nohold = args.has("nohold")
	_tipper = args.has("tipper")
	if args.has("creep"):
		_nohold = true  ## creep alone: a hill hold would shorten the roll-back window
		_start_creep(which)
		return
	if args.has("rollback"):
		_start_rollback(which, args)
		return
	if args.has("climb"):
		_start_ascent(which, args)
		return
	if args.has("descent") or which in ["doc=brake_fade", "doc=brake_check"] or _stops_flag(args) > 0:
		_start_descent(which, args)
		return
	if which == "doc=park" or not is_nan(park):
		_nohold = true  ## the brake hardware alone: the tractor's hill hold would join its handbrake
		_start_park(which, park, "cross" if args.has("cross") else (
				"hand" if args.has("hand") else ("pawl" if args.has("pawl") else "foot")))
		return
	if which == "doc=grade":
		_doc = true
		_queue = DOC_JOBS.duplicate(true)
		_surface_list = DOC_SURFACES.duplicate()
	else:
		for v in MeasureRig.variants_arg(which, MeasureRig.wheel_driven_variants()):
			_queue.append({"variant": v, "mfwd": _mfwd, "diff": _diff, "tc": _tc})
		if _queue.is_empty():
			get_tree().quit(1)
			return
	print("=== grade climb: standing start, %.0f s per trial ===" % CLIMB_S)
	print("  surfaces: %s" % ", ".join(_surface_list))
	print("  throttle: %s" % ("slip-limited (tc)" if _tc else "full"))
	if _tyre != "":
		print("  tyre: %s on every body that takes it" % _tyre)
	if _held_gear > 0:
		print("  gear: manual, held in D%d (gear=%d)" % [_held_gear, _held_gear])
	if _mfwd or _diff:
		print("  tractor toggles: %s%s" % ["MFWD " if _mfwd else "", "diff-lock" if _diff else ""])
	_next_variant()


# ------------------------------------------------------------------ ramp mode

func _next_variant() -> void:
	if _queue.is_empty():
		_print_table()
		if _doc:
			DocRegion.write("grade", _doc_table())
		get_tree().quit(0)
		return
	var job: Dictionary = _queue.pop_front()
	_variant = String(job["variant"])
	_mfwd = bool(job["mfwd"])
	_diff = bool(job["diff"])
	_tc = bool(job["tc"])
	_surfaces = _surface_list.duplicate()
	_next_surface()


func _next_surface() -> void:
	if _surfaces.is_empty():
		_next_variant()
		return
	_surface = _surfaces.pop_front()
	_lo = BISECT_LO
	_hi = BISECT_HI
	_step = _first_step()
	_best = NAN
	_begin_trial(_hold if not is_nan(_hold) else (_lo + _hi) * 0.5)


## A `hold=` run is one trial, so it starts on the last bisection step.
func _first_step() -> int:
	return BISECT_STEPS - 1 if not is_nan(_hold) else 0


func _begin_trial(angle_deg: float) -> void:
	_angle = angle_deg
	_build_ramp(angle_deg)
	_spawn(angle_deg)
	_phase = Ph.SETTLE
	_t = 0.0
	_gain = 0.0
	_drive(0.0, 100.0)


func _build_ramp(angle_deg: float) -> void:
	var a := deg_to_rad(angle_deg)
	_ramp = MeasureRig.tilt_ramp(self, _ramp, Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH), a)
	_patch.tan_angle = tan(a)
	_patch.surface = Surface.from_key(_surface)


## `yaw` turns the body about the ramp's normal: PI / 2 parks it across the slope. `lift`: the
## ramp's (`MeasureRig.tilt_ramp`).
func _spawn(angle_deg: float, yaw := 0.0, up := SPAWN_UP, lift := 0.0) -> void:
	MeasureRig.free_body(self, _car)
	_car = MeasureRig.spawn(self, _variant, _spec_overrides) as BaseVehicle
	_tyre_label = MeasureRig.fit_tyre(_car, _tyre)
	if _tipper and _car.has_method(&"set_attachment"):
		# Remembered until the drawbar's spawn countdown has run, then coupled (TowHost).
		_car.call(&"set_attachment", ImplementCatalog.TOWED[0])
	elif _car is TractorVehicle:
		_car.call(&"set_attachment", AttachmentCatalog.NONE)  ## bare: an implement's weight moves the axles
	MeasureRig.place(_car, MeasureRig.slope_pose(_car, deg_to_rad(angle_deg), up, yaw, lift))
	_start = _car.global_position


## `spawn`'s prep: `nohold` and `cornering_peak=` on `car`'s own spec; neither leaves the shipped
## one.
func _spec_overrides(car: BaseVehicle) -> void:
	if not _nohold and is_nan(_cornering_peak):
		return
	var gd := MeasureRig.own_ground_drive(car)
	if _nohold:
		gd.hill_hold = HillHold.Kind.NONE
	if not is_nan(_cornering_peak):
		gd.cornering_peak_load = _cornering_peak


## Drive through the bridge, not the keyboard: `InputRouter.arbitrate_local` latches reverse on
## a brake held at a standstill, and a standstill brake is exactly the settle phase here.
func _drive(accel_pct: float, brake_pct: float, handbrake01 := 0.0, gear := -1) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, false, gear if gear >= 0 else maxi(_held_gear, 1),
			false, 3, {"handbrake": handbrake01, "diff_lock": _diff, "fwd_drive": _mfwd})


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	_t += delta
	if _phase == Ph.PARK_SETTLE or _phase == Ph.PARK_HOLD:
		_park_step()
		return
	if _phase == Ph.CREEP_SETTLE or _phase == Ph.CREEP:
		_creep_step()
		return
	if _phase == Ph.ROLL_SETTLE or _phase == Ph.ROLL:
		_roll_step()
		return
	if _phase == Ph.ASCENT_SETTLE or _phase == Ph.ASCENT:
		_ascent_step(delta)
		return
	if _phase >= Ph.DESC_SETTLE and _phase <= Ph.DESC_STOP:
		_descent_step(delta)
		return
	if _phase == Ph.SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.CLIMB
			_t = 0.0
			_tc_fuel = 1.0
			_front_settle = _front_load()
			_start = _car.global_position
			_drive_share = _driven_share()
			_drive(100.0, 0.0)
		return
	if _pedal > 0.0:
		_drive(_pedal * 100.0, 0.0)
	elif _tc:
		# Wheelspin is self-defeating here twice over: the grip curve falls away past its peak
		# AND gear 1 drags the engine into the rev limiter, so a floored pedal measures the
		# driver, not the tyre. Hold the slip at the peak and the measurement is the tyre's.
		var slip_rate := (TC_TARGET_SLIP - _rear_slip()) * TC_GAIN
		# Most force is not most climb: every newton past the weight accelerates the body and
		# unloads the front axle by `m * a * h / L`, which flips a high-COM tractor backwards
		# below its static tip angle. The driver also feathers as the front goes light, on the
		# same integrator: a hard pedal cap would porpoise (lift, cut, land, repeat).
		var front_left := _front_load() / _front_settle if _front_settle > 0.0 else 1.0
		var lift_rate := (front_left - TC_FRONT_KEEP) * TC_LIFT_GAIN
		_tc_fuel = clampf(_tc_fuel + minf(slip_rate, lift_rate) * delta, 0.0, 1.0)
		_drive(PedalMap.pedal_for(_car.spec, _tc_fuel, _car.drivetrain.rpm) * 100.0, 0.0)
	## The ramp's own up-slope direction, not the body's forward: a body that has nosed up or
	## slewed must still be measured along the hill.
	var up_slope := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3(0.0, 0.0, -1.0)
	_gain = (_car.global_position - _start).dot(up_slope)
	if _verbose and not is_nan(_hold):
		_trace_t += delta
		if _trace_t >= 1.0:
			_trace_t = 0.0
			var f_long := 0.0
			for w in _car.drive.wheels:
				f_long += w.force_long
			print("      t %4.1f  gain %6.2f  v %5.2f  slipR %5.2f  f_long %8.0f  rpm %6.0f"
					% [_t, _gain, _car.telemetry.speed, _rear_slip(), f_long,
					_car.telemetry.rpm]
					+ "  gear %d  thr %.2f  tc %.2f" % [_car.telemetry.gear_byte,
					_car.drivetrain.applied_throttle, _tc_fuel])
			for i in _car.drive.wheels.size():
				var w: RayWheel = _car.drive.wheels[i]
				print("        w%d %s%s N %7.0f  f_long %8.0f  drag %7.0f  slip %5.2f  omega %6.2f"
						% [i, "R" if w.is_rear else "F", "d" if w.driven else "-",
						w.suspension_force, w.force_long, w.surface_drag * w.suspension_force,
						w.slip, w.omega])
	if _gain >= CLIMB_MIN or _gain <= SLIDE_BACK:
		_end_trial(_gain >= CLIMB_MIN)
	elif _t >= CLIMB_S:
		var up_speed := _car.linear_velocity.dot(up_slope)
		_end_trial(up_speed >= CLIMB_SPEED and _gain >= CLIMB_GAIN)



func _end_trial(climbed: bool) -> void:
	_phase = Ph.DONE
	_drive(0.0, 100.0)
	if _verbose:
		var f_long := 0.0
		var susp := 0.0
		var drag := 0.0
		for w in _car.drive.wheels:
			f_long += w.force_long
			susp += w.suspension_force
			drag += w.surface_drag * w.suspension_force
		print("      wheels: sum f_long %8.0f N, suspension %8.0f N, surface drag %8.0f N,"
				% [f_long, susp, drag]
				+ " weight-along-slope %8.0f N" % (_car.mass * BrakeSizing.G * sin(deg_to_rad(_angle))))
		print("    %5.2f deg: %-7s gain %6.2f m, speed %5.2f m/s, rear slip %.2f, gear %d"
				% [_angle, "CLIMB" if climbed else "fail", _gain, _car.telemetry.speed,
				_rear_slip(), _car.telemetry.gear_byte])
	if climbed:
		_best = _angle
		_lo = _angle
	else:
		_hi = _angle
	_step += 1
	if _step < BISECT_STEPS:
		_begin_trial((_lo + _hi) * 0.5)
		return
	_record()
	_next_surface()


func _record() -> void:
	var spec: VehicleSpec = _car.spec
	var gd: GroundDriveSpec = spec.ground_drive
	var sid := Surface.from_key(_surface)
	# The fitted tyre's grip there (`RayWheel.tyre_grip`), the reference tyre's on no class.
	var s := Vector2(Surface.grip_in(_car.drive.wheels[0].tyre_grip, sid), Surface.drag(sid))
	var coupled := MeasureRig.towed_mass(_car)
	var traction := _traction_limit_deg(spec, gd, s.x, s.y)
	if coupled > 0.0:
		# The kingpin load on the drive axle has no static figure here: read it off the springs.
		# Grade transfer included, since the last trial settled on its slope (within a bisection
		# step of the answer).
		traction = rad_to_deg(atan(maxf(gd.mu_long * s.x * _drive_share - s.y, 0.0)))
	_rows.append({
		"variant": _variant,
		"surface": _surface,
		"measured": _best,
		"traction": traction,
		"torque": _torque_limit_deg(spec, gd, s.y, spec.mass + coupled),
		"tip": _tip_limit_deg(spec, gd) if coupled <= 0.0 else NAN,  ## kingpin load moves the COM
		"coupled": coupled,
		"label": _doc_label(spec, gd, coupled),
	})
	print("  %-16s %-8s measured %5.1f deg (%5.1f %%)%s" % [_variant, _surface,
			_best if not is_nan(_best) else 0.0,
			100.0 * tan(deg_to_rad(_best)) if not is_nan(_best) else 0.0,
			", tyre %s" % _tyre_label if _tyre != "" else ""])


## Steepest grade the tyres alone hold, in degrees: static weight split plus the uphill transfer
## onto the driven axle, minus the surface's own rolling drag. Single-body and ignoring
## `load_sensitivity`, so it is the textbook reference the measurement is read against.
func _traction_limit_deg(spec: VehicleSpec, gd: GroundDriveSpec, grip: float,
		crr: float) -> float:
	var mu := gd.mu_long * grip
	var front_driven := gd.driven_front or (_mfwd and gd.front_axle_engageable)
	if front_driven and gd.driven_rear:
		return rad_to_deg(atan(maxf(mu - crr, 0.0)))
	var front_z := INF
	var rear_z := -INF
	for p in gd.wheel_positions:
		if RayWheel.is_rear_z(p.z):
			rear_z = maxf(rear_z, p.z)
		else:
			front_z = minf(front_z, p.z)
	if is_inf(front_z) or is_inf(rear_z):
		return NAN
	var wheelbase := rear_z - front_z
	# Body space has +Z rearward, so the COM's distance from the FRONT axle is what the rear
	# axle carries a share of.
	var a_front := spec.center_of_mass.z - front_z
	var share_rear := clampf(a_front / wheelbase, 0.0, 1.0)
	if gd.driven_front and not gd.driven_rear:
		share_rear = 1.0 - share_rear
	# COM height over the contact plane, springs at half travel.
	var contact_y := gd.rest_length * 0.5 - gd.rest_ride_height()
	var h := maxf(spec.center_of_mass.y - contact_y, 0.05)
	var transfer := mu * h / wheelbase
	if gd.driven_front and not gd.driven_rear:
		transfer = -transfer  ## uphill transfer UNLOADS a driven front axle
	var num := mu * share_rear - crr
	var den := 1.0 - transfer
	if num <= 0.0 or den <= 0.0:
		return 0.0 if num <= 0.0 else 90.0
	return rad_to_deg(atan(num / den))


## Grade at which the body, standing still, tips over backwards, in degrees: the COM passes over
## the rear contact patch, `tan(a) = b / h`. A climb also spends some of that margin on
## acceleration (`m * a * h / L` off the front axle), so the measurement sits under it.
func _tip_limit_deg(spec: VehicleSpec, gd: GroundDriveSpec) -> float:
	var rear_z := -INF
	for p in gd.wheel_positions:
		if RayWheel.is_rear_z(p.z):
			rear_z = maxf(rear_z, p.z)
	if is_inf(rear_z):
		return NAN
	# Same contact plane as `_traction_limit_deg`: springs at half travel.
	var contact_y := gd.rest_length * 0.5 - gd.rest_ride_height()
	var h := maxf(spec.center_of_mass.y - contact_y, 0.05)
	return rad_to_deg(atan(maxf(rear_z - spec.center_of_mass.z, 0.0) / h))


## Fraction of the whole rig's weight across the slope that the driven wheels carry right now.
func _driven_share() -> float:
	var driven_load := 0.0
	for w in _car.drive.wheels:
		if w.driven:
			driven_load += w.suspension_force
	return driven_load / ((_car.mass + MeasureRig.towed_mass(_car)) * BrakeSizing.G
			* cos(deg_to_rad(_angle)))


## Spring load on the front axle right now, N.
func _front_load() -> float:
	var front := 0.0
	for w in _car.drive.wheels:
		if not w.is_rear:
			front += w.suspension_force
	return front


## The rear axle's mean |slip ratio| (`RayWheel.slip`): what TC_TARGET_SLIP is a target for. The
## telemetry's `slip_rear` adds side slip.
func _rear_slip() -> float:
	var total := 0.0
	var count := 0
	for w in _car.drive.wheels:
		if w.is_rear:
			total += w.slip
			count += 1
	return total / count if count > 0 else 0.0


## Steepest grade first gear at full throttle can push `mass` (kg, the whole rig) up from rest, in
## degrees. Sampled where a held body's crank sits, through a converter's stall torque ratio
## (`Drivetrain.stall_axle_torque`); a CVT's is its relief, the most its deepest ratio passes.
func _torque_limit_deg(spec: VehicleSpec, gd: GroundDriveSpec, crr: float, mass: float) -> float:
	if spec.gear_ratios.is_empty() and not Drivetrain.is_cvt(spec):
		return NAN
	var force := Drivetrain.stall_axle_torque(spec) / gd.drive_radius()
	var ratio := force / (mass * BrakeSizing.G)
	if ratio <= crr:
		return 0.0
	# sin a + crr cos a = ratio  ->  sin(a + atan(crr)) = ratio / sqrt(1 + crr^2)
	var s := ratio / sqrt(1.0 + crr * crr)
	if s >= 1.0:
		return 90.0
	return rad_to_deg(asin(s) - atan(crr))


func _print_table() -> void:
	print("\n%-16s %-8s %8s %8s %10s %10s %10s  %s"
			% ["variant", "surface", "measured", "grade", "traction", "torque", "tip", "note"])
	for r in _rows:
		var m: float = r["measured"]
		var note := ""
		if r["coupled"] > 0.0:
			note = "coupled +%.0f kg — torque on the rig, traction on its sprung drive-axle load" \
					% r["coupled"]
		print("%-16s %-8s %7.1f%s %7.0f%% %9.1f%s %9.1f%s %9.1f%s  %s" % [
			r["variant"], r["surface"],
			0.0 if is_nan(m) else m, " d",
			0.0 if is_nan(m) else 100.0 * tan(deg_to_rad(m)),
			r["traction"], " d", r["torque"], " d", r["tip"], " d", note])


## "`variant` (layout, toggles, mass)" for the doc table: the tractor reads 2WD / MFWD by its
## engageable front axle, a coupled rig its towed mass.
func _doc_label(spec: VehicleSpec, gd: GroundDriveSpec, coupled: float) -> String:
	var layout := MeasureRig.layout_label(gd)
	if gd.front_axle_engageable:
		layout = "MFWD" if _mfwd else "2WD"
	if _mfwd or not gd.front_axle_engageable:  ## a disengaged front axle leaves no centre to declare
		layout += MeasureRig.diff_label(gd)
	if _diff:
		layout += ", diff lock"
	if _tc:
		layout += ", tc"
	var mass := "%.2f t" % (spec.mass / 1000.0)
	if coupled > 0.0:
		mass += " + %.0f t towed" % (coupled / 1000.0)
	return "`%s` (%s, %s)" % [_variant, layout, mass]


## The `grade` region: one row per job, one column per DOC_SURFACES entry.
func _doc_table() -> Array[String]:
	var lines := DocRegion.wrap("%s (`measure_grade -- doc=grade`), standing start, full throttle"
			% DocRegion.measured() + " unless `tc`:")
	lines.append_array([
		"",
		"| Variant | %s |" % " | ".join(DOC_SURFACES.map(func(s: String) -> String:
				return "%s (grip %.2f, crr %.2f)" % [s, Surface.ref_grip(Surface.from_key(s)),
						Surface.drag(Surface.from_key(s))])),
		"| --- |" + " --- |".repeat(DOC_SURFACES.size()),
	])
	var row := ""
	var cells := 0
	for r in _rows:
		if cells == 0:
			row = "| %s |" % r["label"]
		var m: float = r["measured"]
		row += " %.1f %% |" % (0.0 if is_nan(m) else 100.0 * tan(deg_to_rad(m)))
		cells += 1
		if cells == DOC_SURFACES.size():
			lines.append(row)
			cells = 0
	return lines


# ------------------------------------------------------------------ park mode

## Metres of movement that ends a park trial early: the body is sliding, not held.
const PARK_SLIDE := 5.0


func _start_park(which: String, angle_deg: float, mode: String) -> void:
	if which == "doc=park":
		_park_doc = true
		for v in DOC_PARK_VARIANTS:
			for a in DOC_PARK_ANGLES:
				for m in DOC_PARK_MODES:
					_park_queue.append({"variant": v, "angle": a, "mode": m})
			_park_queue.append({"variant": v, "mode": "hand", "reg": true,
					"angle": rad_to_deg(atan(BrakeSizing.regulation_grade(MeasureRig.rig_mass(v))))})
	elif Catalog.VARIANTS.has(which):
		_park_queue.append({"variant": which, "angle": angle_deg, "mode": mode})
	else:
		printerr("unknown variant '%s'" % which)
		get_tree().quit(1)
		return
	print("=== park: held on asphalt, %.0f s after a %.1f s settle ===" % [PARK_HOLD_S, SETTLE_S])
	_next_park()


func _next_park() -> void:
	if _park_queue.is_empty():
		_print_park()
		if _park_doc:
			DocRegion.write("park", _park_doc_table())
		get_tree().quit(0)
		return
	var job: Dictionary = _park_queue.pop_front()
	_variant = String(job["variant"])
	_angle = float(job["angle"])
	_park_mode = String(job["mode"])
	_park_reg = bool(job.get("reg", false))
	_surface = "asphalt"
	_build_ramp(_angle)
	_spawn(_angle, PI / 2.0 if _park_mode == "cross" else 0.0)
	_phase = Ph.PARK_SETTLE
	_t = 0.0
	_park_peak = 0.0
	_park_hold()


## The held pedal for this job, every tick (the bridge snapshot is the whole input).
func _park_hold() -> void:
	if _park_mode == "hand":
		_drive(0.0, 0.0, 1.0)
	elif _park_mode == "pawl":
		_drive(0.0, 0.0, 0.0, Drivetrain.GEAR_P)
	else:
		_drive(0.0, 100.0)


func _park_step() -> void:
	_park_hold()
	if _phase == Ph.PARK_SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.PARK_HOLD
			_t = 0.0
			_start = _car.global_position
		return
	_park_peak = maxf(_park_peak, _car.linear_velocity.length())
	var moved := (_car.global_position - _start).length()
	if _verbose:
		_trace_t += get_physics_process_delta_time()
		if _trace_t >= 1.0:
			_trace_t = 0.0
			print("      t %4.1f  moved %7.1f mm  gear %d  thr %.2f  rpm %5.0f" % [_t, moved * 1000.0,
					_car.telemetry.gear_byte, _car.drivetrain.applied_throttle, _car.telemetry.rpm])
			for i in _car.drive.wheels.size():
				var w: RayWheel = _car.drive.wheels[i]
				print("        w%d %s%s N %7.0f  f_long %8.0f  f_lat %7.0f  omega %9.5f  held %s"
						% [i, "R" if w.is_rear else "F", "d" if w.driven else "-",
						w.suspension_force, w.force_long, w.force_lat, w.omega, w._spin_held])
	if _t >= PARK_HOLD_S or moved >= PARK_SLIDE:
		_end_park()


func _end_park() -> void:
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(_angle))
	var d := _car.global_position - _start
	var row := {
		"variant": _variant, "angle": _angle, "mode": _park_mode,
		"along": d.dot(tilt * Vector3.FORWARD),  ## + = up the slope
		"across": d.dot(tilt * Vector3.RIGHT),
		"peak": _park_peak, "t": _t, "slid": d.length() >= PARK_SLIDE,
		"reg": _park_reg,
	}
	_park_rows.append(row)
	# An oscillating front axle's beam off the body, as it settled (`RayWheel.swing`).
	var beam := ""
	if _car.spec.ground_drive.has_swing_axle():
		for w in _car.wheels:
			if not w.is_rear:
				beam = "  beam %+.1f deg" % rad_to_deg(w.swing)
				break
	print("  %-16s %4.1f %% %-5s along %+9.1f mm  across %+9.1f mm  peak %6.3f m/s%s%s" % [
		_variant, 100.0 * tan(deg_to_rad(_angle)), _park_mode,
		1000.0 * float(row["along"]), 1000.0 * float(row["across"]), _park_peak, beam,
		"  SLID (%.1f s)" % _t if row["slid"] else ""])
	_phase = Ph.DONE
	_next_park()


func _print_park() -> void:
	print("\n%-16s %6s %-5s %10s %10s %9s" % ["variant", "grade", "brake", "along mm",
			"across mm", "peak m/s"])
	for r in _park_rows:
		print("%-16s %5.0f%% %-5s %10.1f %10.1f %9.3f%s" % [r["variant"],
				100.0 * tan(deg_to_rad(r["angle"])), r["mode"], 1000.0 * float(r["along"]),
				1000.0 * float(r["across"]), r["peak"], "  slid" if r["slid"] else ""])


## The `park` region: one row per variant, one column per angle x mode, movement in mm over the
## hold (or "slides" when it left PARK_SLIDE behind).
func _park_doc_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_grade -- doc=park`), asphalt: mm moved in %.0f s held"
			+ " after a %.1f s settle, nose up the slope (`foot`, `hand`, `pawl`: P alone, N on a body"
			+ " with no pawl) or across it (`cross`, foot brake), and on the handbrake at the"
			+ " regulation grade (UN R13-H 20 %% to 3.5 t, R13 18 %%"
			+ " above; the semi with its trailer):") % [DocRegion.measured(), PARK_HOLD_S, SETTLE_S])
	var header := "| Variant |"
	for a in DOC_PARK_ANGLES:
		for m in DOC_PARK_MODES:
			header += " %.0f %% %s |" % [100.0 * tan(deg_to_rad(a)), m]
	header += " hand, regulation grade |"
	var per_row := DOC_PARK_ANGLES.size() * DOC_PARK_MODES.size() + 1
	lines.append_array(["", header, "| --- |" + " --- |".repeat(per_row)])
	var row := ""
	var cells := 0
	for r in _park_rows:
		if cells == 0:
			row = "| `%s` |" % r["variant"]
		var cell := "slides" if r["slid"] else "%.1f" % (1000.0 * Vector2(r["along"],
				r["across"]).length())
		if r["reg"]:
			cell += " (%.0f %%)" % (100.0 * tan(deg_to_rad(r["angle"])))
		row += " %s |" % cell
		cells += 1
		if cells == per_row:
			lines.append(row)
			cells = 0
	return lines


# ----------------------------------------------------------------- creep mode

## CREEP MODE (`creep`; a converter variant or `all` of them): settled on the foot brake on asphalt,
## then released in D1 with no pedal, the converter's idle drag the only drive (the hill hold off,
## `_nohold`). On the flat it reports the steady creep speed (the mean over the last CREEP_MEAN_S of
## CREEP_FLAT_S), the crank and `engine_load`; then the steepest grade that creep holds, bisected
## over [0, CREEP_BISECT_HI] deg: held when, CREEP_HOLD_S after the release, the body has rolled
## back less than CREEP_ROLL_M.
const CREEP_FLAT_S := 15.0
const CREEP_MEAN_S := 2.0
const CREEP_HOLD_S := 10.0
const CREEP_ROLL_M := 0.25
const CREEP_BISECT_HI := 30.0


func _start_creep(which: String) -> void:
	var variants := MeasureRig.variants_arg(which, MeasureRig.wheel_driven_variants())
	if variants.is_empty():
		get_tree().quit(1)
		return
	for v in variants:
		if Catalog.spec_of(v).coupling == VehicleSpec.Coupling.CONVERTER:
			_creep_queue.append(v)
		elif which != "all":
			print("%s has no converter (a clutch opens at a stop): nothing creeps" % v)
	print("=== creep: released in D1 with no pedal on asphalt, after a %.1f s settle ===" % SETTLE_S)
	_surface = "asphalt"
	_next_creep()


func _next_creep() -> void:
	if _creep_queue.is_empty():
		_print_creep()
		get_tree().quit(0)
		return
	_variant = _creep_queue.pop_front()
	_creep_row = {"variant": _variant}
	_creep_flat = true
	_creep_sum = Vector3.ZERO
	_creep_n = 0
	_begin_creep(0.0)


func _begin_creep(angle_deg: float) -> void:
	_angle = angle_deg
	_build_ramp(angle_deg)
	_spawn(angle_deg)
	_phase = Ph.CREEP_SETTLE
	_t = 0.0
	_drive(0.0, 100.0)


func _creep_step() -> void:
	if _phase == Ph.CREEP_SETTLE:
		_drive(0.0, 100.0)
		if _t >= SETTLE_S:
			_phase = Ph.CREEP
			_t = 0.0
			_start = _car.global_position
		return
	_drive(0.0, 0.0)
	var up_slope := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3(0.0, 0.0, -1.0)
	var gain := (_car.global_position - _start).dot(up_slope)
	if _creep_flat:
		if _t >= CREEP_FLAT_S - CREEP_MEAN_S:
			var dt: Drivetrain = _car.drivetrain
			_creep_sum += Vector3(_car.linear_velocity.dot(up_slope), dt.rpm,
					VehicleTelemetry.engine_load_pct(dt.rpm, dt.applied_throttle, _car.spec))
			_creep_n += 1
		if _t >= CREEP_FLAT_S:
			var mean := _creep_sum / maxf(1.0, _creep_n)
			_creep_row["kmh"] = mean.x * 3.6
			_creep_row["rpm"] = mean.y
			_creep_row["load"] = mean.z
			_creep_flat = false
			_lo = 0.0
			_hi = CREEP_BISECT_HI
			_step = 0
			_best = 0.0
			_begin_creep((_lo + _hi) * 0.5)
		return
	if gain <= -CREEP_ROLL_M or _t >= CREEP_HOLD_S:
		var held := gain > -CREEP_ROLL_M
		if _verbose:
			print("      %5.2f deg  %s  %+.2f m" % [_angle, "holds" if held else "rolls", gain])
		if held:
			_best = _angle
			_lo = _angle
		else:
			_hi = _angle
		_step += 1
		if _step >= BISECT_STEPS:
			_creep_row["deg"] = _best
			_creep_rows.append(_creep_row)
			print("  %-16s flat %4.1f km/h at %4.0f rpm, engine_load %2.0f %%; holds %4.1f %% (%.1f deg)"
					% [_variant, _creep_row["kmh"], _creep_row["rpm"], _creep_row["load"],
					100.0 * tan(deg_to_rad(_best)), _best])
			_phase = Ph.DONE
			_next_creep()
			return
		_begin_creep((_lo + _hi) * 0.5)


func _print_creep() -> void:
	print("
%-16s %8s %6s %6s %9s" % ["variant", "km/h", "rpm", "load", "holds"])
	for r in _creep_rows:
		print("%-16s %8.1f %6.0f %5.0f%% %8.1f%%" % [r["variant"], r["kmh"], r["rpm"], r["load"],
				100.0 * tan(deg_to_rad(r["deg"]))])


# -------------------------------------------------------------- rollback mode

## ROLLBACK MODE (`rollback`; a variant or `all`): settled SETTLE_S on the foot brake nose up a grade
## (`grade=<%>`, else each of ROLL_GRADES), then released with no pedal, and the drive pedal
## (`pedal=<0..1>`, else full) applied `delay=<s>` later (ROLL_DELAY_S), a driver moving a foot
## across. Reports how far the body rolled back, when it was ROLL_GO_M up the slope, and how long
## the hill hold held after the release. `nohold` runs the body with its hold off; `tipper` gives the
## tractor its drawbar tipper. Asphalt unless a surface is named.
const ROLL_GRADES: Array[float] = [10.0, 25.0]
const ROLL_DELAY_S := 0.5
const ROLL_S := 10.0      ## trial cap after the release
const ROLL_GO_M := 0.1    ## m up the slope that reads as moving forward
const ROLL_DONE_M := 1.0  ## m up the slope that ends the trial early
const ROLL_LOST_M := 4.0  ## m rolled back that ends it


func _start_rollback(which: String, args: PackedStringArray) -> void:
	var grade := MeasureRig.float_flag(args, "grade=", NAN)
	var grades: Array[float] = ROLL_GRADES.duplicate()  # a typed-array ternary fails at runtime
	if not is_nan(grade):
		grades = [grade]
	_roll_delay = MeasureRig.float_flag(args, "delay=", ROLL_DELAY_S)
	_surface = "asphalt"
	for a in args:
		if Surface.from_key(String(a)) >= 0:
			_surface = String(a)
	var variants := MeasureRig.variants_arg(which, MeasureRig.wheel_driven_variants())
	if variants.is_empty():
		get_tree().quit(1)
		return
	for v in variants:
		for g: float in grades:
			_roll_queue.append({"variant": v, "grade": g})
	print("=== rollback: released on %s after a %.1f s settle, pedal %.0f %% after %.2f s; hold %s%s ==="
			% [_surface, SETTLE_S, 100.0 * (_pedal if _pedal > 0.0 else 1.0), _roll_delay,
			"off (nohold)" if _nohold else "as fitted", ", tipper" if _tipper else ""])
	_next_roll()


func _next_roll() -> void:
	if _roll_queue.is_empty():
		_print_roll()
		get_tree().quit(0)
		return
	var job: Dictionary = _roll_queue.pop_front()
	_variant = String(job["variant"])
	_roll_grade = float(job["grade"])
	_angle = rad_to_deg(atan(_roll_grade / 100.0))
	_build_ramp(_angle)
	_spawn(_angle)
	_phase = Ph.ROLL_SETTLE
	_t = 0.0
	_roll_min = 0.0
	_roll_go = NAN
	_roll_held = 0.0
	_drive(0.0, 100.0)


func _roll_step() -> void:
	if _phase == Ph.ROLL_SETTLE:
		_drive(0.0, 100.0)
		if _t >= SETTLE_S:
			_phase = Ph.ROLL
			_t = 0.0
			_start = _car.global_position
		return
	var pedal := (_pedal if _pedal > 0.0 else 1.0) if _t >= _roll_delay else 0.0
	_drive(pedal * 100.0, 0.0)
	var up_slope := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3(0.0, 0.0, -1.0)
	var gain := (_car.global_position - _start).dot(up_slope)
	_roll_min = minf(_roll_min, gain)
	if _car.drive.hill_holding:
		_roll_held = _t
	if _verbose and int(round(_t * 60.0)) % 30 == 0:
		_print_roll_forces(gain)
	if is_nan(_roll_go) and gain >= ROLL_GO_M:
		_roll_go = _t
	if _t < ROLL_S and gain < ROLL_DONE_M and gain > -ROLL_LOST_M:
		return
	var row := {"variant": _variant, "grade": _roll_grade, "back": -_roll_min, "go": _roll_go,
			"held": _roll_held, "towed": MeasureRig.towed_mass(_car)}
	_roll_rows.append(row)
	print("  %-16s %4.1f %%  rolled back %7.1f mm  forward %s  held %.2f s%s" % [_variant,
			_roll_grade, 1000.0 * float(row["back"]),
			"never" if is_nan(_roll_go) else "at %.2f s" % _roll_go, _roll_held,
			"  (+%.0f kg towed)" % row["towed"] if float(row["towed"]) > 0.0 else ""])
	_phase = Ph.DONE
	_next_roll()


## `verbose` roll-back line, every 0.5 s: the tractor unit's tyre force and slip per axle and its
## rolling force (`RayWheel.force_roll`, tyre plus surface drag), and with a trailer its tyres'
## force, its rolling force, its brake and the drawbar's pull, read off the trailer's own balance
## (`m a + m g sin - sum Fx - sum roll` along the slope). Names what bounds a slow pull-away:
## traction, the drawbar, or the trailer.
func _print_roll_forces(gain: float) -> void:
	var fx := {true: 0.0, false: 0.0}
	var slip := {true: 0.0, false: 0.0}
	var n := {true: 0, false: 0}
	var roll := 0.0
	for w: RayWheel in _car.drive.wheels:
		if w.in_contact:
			fx[w.is_rear] += w.force_long
			slip[w.is_rear] += w.long_slip
			n[w.is_rear] += 1
			roll += w.force_roll
	var line := "    t %5.2f  %+7.3f m  %5.2f km/h  rpm %4.0f c %d  Fx front %6.0f rear %6.0f N  roll %6.0f N  slip %+.2f / %+.2f" \
			% [_t, gain, _car.telemetry.speed * 3.6, _car.drivetrain.rpm, _car.drivetrain.coupling_state,
			fx[false], fx[true], roll, slip[false] / maxi(n[false], 1), slip[true] / maxi(n[true], 1)]
	var host: Variant = _car.get("_drawbar")
	if host == null:
		host = _car.get("_fifth_wheel")
	var trailer: TowedBody = host.get("trailer") if host != null else null
	if trailer != null:
		var t_fx := 0.0
		var t_roll := 0.0
		for w: RayWheel in trailer.wheels:
			if w.in_contact:
				t_fx += w.force_long
				t_roll += w.force_roll
		var g_pull := trailer.mass * BrakeSizing.G * sin(deg_to_rad(_angle))
		line += "  | trailer Fx %6.0f N roll %6.0f N brake %.2f  drawbar %6.0f N (grade %6.0f)" % [
				t_fx, t_roll, trailer.brake_applied(),
				trailer.mass * trailer.accel_fwd + g_pull - t_fx - t_roll, g_pull]
	print(line)


func _print_roll() -> void:
	print("\n%-16s %6s %10s %9s %7s" % ["variant", "grade", "back mm", "forward", "held"])
	for r in _roll_rows:
		print("%-16s %5.1f%% %10.1f %9s %6.2fs" % [r["variant"], r["grade"], 1000.0 * float(r["back"]),
				"never" if is_nan(r["go"]) else "%.2fs" % r["go"], r["held"]])


# ----------------------------------------------------------------- climb mode

## CLIMB MODE (`climb`; one variant): settled SETTLE_S on the foot brake near the foot of a fixed
## grade (`grade=<%>`, else ASCENT_GRADE), then released into the automatic box at a held pedal
## (`pedal=<0..1>`, else full) for ASCENT_S or until the ramp's top. Prints each shift (road speed,
## the road speed's rpm in the gear left and the one landed in, and the gearbox's road-load
## estimate where it keeps one) and a `falls back` gate: an upshift a later downshift undoes, back
## into the gear it left. `tipper` / `mfwd` / a surface as the other modes.
const ASCENT_GRADE := 8.0
const ASCENT_S := 40.0
## Metres up from the ramp's foot the body starts, and short of its top the run ends.
const ASCENT_MARGIN := 15.0
## Deepest (m under the origin) the body starts: clear of `BaseVehicle.FALL_RESPAWN_Y`'s -20, so a
## steep ramp starts it higher up the slope instead.
const ASCENT_DEPTH := 15.0


func _start_ascent(which: String, args: PackedStringArray) -> void:
	if not Catalog.VARIANTS.has(which):
		printerr("unknown variant '%s'" % which)
		get_tree().quit(1)
		return
	_variant = which
	_ascent_grade = MeasureRig.float_flag(args, "grade=", ASCENT_GRADE)
	_surface = "asphalt"
	for a in args:
		if Surface.from_key(String(a)) >= 0:
			_surface = String(a)
	_angle = rad_to_deg(atan(_ascent_grade / 100.0))
	_build_ramp(_angle)
	var down := minf(RAMP_LENGTH * 0.5 - ASCENT_MARGIN, ASCENT_DEPTH / sin(deg_to_rad(_angle)))
	_ascent_room = RAMP_LENGTH * 0.5 - ASCENT_MARGIN + down
	_spawn(_angle, 0.0, -down)
	print("=== climb: %s on %.1f %% %s, pedal %.0f %%%s%s, automatic D, %.0f s or the ramp's top ==="
			% [_variant, _ascent_grade, _surface, 100.0 * _ascent_pedal(), ", tipper" if _tipper else "",
			", MFWD" if _mfwd else "", ASCENT_S])
	_phase = Ph.ASCENT_SETTLE
	_t = 0.0
	_trace_t = 0.0
	_drive(0.0, 100.0)


func _ascent_pedal() -> float:
	return _pedal if _pedal > 0.0 else 1.0


## The gearbox's road-load estimate (N·m at the axle), NAN where it keeps none.
func _ascent_load() -> float:
	var estimate: Variant = _car.drivetrain.get("road_load")
	return float(estimate) if estimate != null else NAN


func _ascent_step(delta: float) -> void:
	if _phase == Ph.ASCENT_SETTLE:
		_drive(0.0, 100.0)
		if _t >= SETTLE_S:
			_phase = Ph.ASCENT
			_t = 0.0
			_start = _car.global_position
			_ascent_byte = _car.drivetrain.gear_byte
			_ascent_shifts.clear()
		return
	_drive(_ascent_pedal() * 100.0, 0.0)
	var dt: Drivetrain = _car.drivetrain
	if dt.gear_byte != _ascent_byte and Drivetrain.is_drive(_ascent_byte) \
			and Drivetrain.is_drive(dt.gear_byte):
		var shift := MeasureRig.shift_record(_car, _t, _ascent_byte, dt.gear_byte)
		shift["load"] = _ascent_load()
		_ascent_shifts.append(shift)
	_ascent_byte = dt.gear_byte
	_trace_t += delta
	if _trace_t >= 1.0 - 1e-6:
		_trace_t = 0.0
		var road_load := _ascent_load()
		print("    t %5.2f  %6.2f km/h  D%d  rpm %5.0f  fuel %.2f%s" % [_t,
				_car.telemetry.speed * 3.6, dt.gear_byte, dt.rpm, dt.applied_throttle,
				"" if is_nan(road_load) else "  load %6.0f N·m" % road_load])
	var up_slope := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3(0.0, 0.0, -1.0)
	var gain := (_car.global_position - _start).dot(up_slope)
	if _t < ASCENT_S and gain < _ascent_room and gain > -ROLL_LOST_M:
		return
	_print_ascent(gain)
	_phase = Ph.DONE
	get_tree().quit(0)


func _print_ascent(gain: float) -> void:
	print("  end           : %.2f s, %.1f m up, %.1f km/h in D%d" % [_t, gain,
			_car.telemetry.speed * 3.6, _car.drivetrain.gear_byte])
	print("  each shift    : %s" % (MeasureRig.shifts_label(_ascent_shifts, true)
			if not _ascent_shifts.is_empty() else "none"))
	var falls: Array[String] = []
	for i in _ascent_shifts.size():
		var up: Dictionary = _ascent_shifts[i]
		if int(up["to"]) <= int(up["from"]):
			continue
		for j in range(i + 1, _ascent_shifts.size()):
			var later: Dictionary = _ascent_shifts[j]
			if int(later["to"]) <= int(up["from"]) and int(later["from"]) > int(later["to"]):
				falls.append("D%d>D%d at %.2f s undone at %.2f s" % [up["from"], up["to"], up["t"],
						later["t"]])
				break
	print("  falls back    : %s" % ("PASS  none" if falls.is_empty() else "FAIL  " + ", ".join(falls)))


# ------------------------------------------------------- descent and stops mode

## DESCENT MODE (`descent`; one variant): settled SETTLE_S on the foot brake facing down a fixed
## grade (`grade=<%>`, DESCENT_GRADE) near the top of a ramp sized for the run, run up in automatic
## D to the hold speed (`kmh=`, DESCENT_KMH), then held there for `km=` (DESCENT_KM) in each mode:
## `foot` (a PI on the foot brake alone, automatic D), `gear` (the same, held in the lowest gear
## under the upshift point at the hold speed, `held_gear_for`, or `gear=<1-24>`; skipped where the
## box holds no fixed gear), `retarder` (a PI on the retarder, the foot brake topping up past
## TOPUP_BAND; trucks). Then a full-pedal stop in automatic D, retarder off, against the same stop
## from a fresh body after DESCENT_COLD_S on the hold (`cold`, run first). `mode=<m>` runs one;
## `verbose` prints the hold every 10 s; `surface=<name>` (`Surface.NAMES`, asphalt by default) lays
## the ramp in it. A rig's hold also prints the kingpin's push along the grade, read off the
## trailer's own balance (its momentum change less its patches' `RayWheel.contact_force`, gravity
## and air: what is left is the joint's), and its largest articulation against ARTICULATION_BOUND_DEG.
## STOPS (`stops[=<n>]`, STOPS_DEFAULT): `n` full-pedal stops on the flat from `kmh=` (STOPS_KMH),
## back to back, floored in D between them.
## Each prints the hottest brake and the lowest fade factor of the powered unit and of a trailer,
## and the energy check: the friction brakes' heat (the per-tick `brake_reacted *
## brake_friction_share * brake_settled_spin`, never C·ΔT, which cooling empties) against the rig's
## drop in kinetic, wheel-spin and potential energy less what the sim's own forces took: rolling
## (`force_roll` at the patch), air (`VehicleMath.air_force`), the driveline (the shaft torque
## `WheelDrive._drive_torque` on the driven wheels' spin: engine braking and coupling slip), the
## retarder's share of the reacted brake and the tyres' slip (their force on the patch's slip
## velocity). Straight-line: the patch velocity is read along the body's axes, not a steered wheel's.
const DESCENT_GRADE := 7.0
const DESCENT_KM := 6.0
const DESCENT_KMH := 60.0
const DESCENT_COLD_S := 30.0    ## s held on the fresh body before its cold stop: the hold settled, so hot and cold start alike
const DESCENT_RUNUP := 600.0    ## m of ramp above the hold: the settle and the run-up
const DESCENT_RUNOUT := 400.0   ## m below it: the stop
const DESCENT_COAST := 2.0      ## m/s under the hold speed at which the run-up lifts off and coasts
const DESCENT_RUNUP_S := 120.0  ## s a run-up may take before the job is called
const STOPS_DEFAULT := 10
const STOPS_KMH := 100.0
const STOPS_CYCLE := 300.0      ## m of flat a stop and its run-up take, at most
const STOP_SPEED := 0.3         ## m/s that counts as stopped
## The hold's PI gains: demand (0..1) per m/s over the hold speed, and per s on it. Full pedal asks
## the body's whole brake capacity (`WheelDrive.brake_application`), a full retarder far less.
const PEDAL_KP := 0.15
const PEDAL_KI := 0.03
const RETARDER_KP := 1.0
const RETARDER_KI := 0.2
const TOPUP_BAND := 0.5         ## m/s over the hold speed before the foot brake tops the retarder up
## The hold's largest articulation (deg), set before any run: a straight hold swinging past it is
## starting to jackknife.
const ARTICULATION_BOUND_DEG := 5.0
## The energy check's tolerance on the heat over what the ledger leaves for it, set before any run.
const ENERGY_TOLERANCE := 0.05
## `doc=brake_fade` (arg 1): each of these at the defaults in every mode, then `sedan`'s
## STOPS_DEFAULT stops; the `brake_fade` region of `docs/vehicle_measurements.md` is rewritten.
const DOC_DESCENT_VARIANTS: Array[String] = ["semi", "garbage-truck"]
## ...then the semi's holds on low grip, no stop after them: the retarder's pushing trailer against
## the foot brake's braked one, the same hold.
const DOC_LOW_GRIP: Array[Dictionary] = [
	{"surface": "snow", "mode": "retarder"},
	{"surface": "ice", "mode": "foot"},
	{"surface": "ice", "mode": "retarder"},
]
const DOC_STOPS_VARIANT := "sedan"
const DESCENT_MODES: Array[String] = ["cold", "foot", "gear", "retarder"]
## Flags on a descent or stops run: `mass=<kg>` (the body's live mass, `BaseVehicle.set_live_mass`,
## set at the end of the settle) or `per_brake=<kg>` (that times the body's own thermal brakes);
## `t0=<°C>` (every brake at the hold's start); `amb=<°C>`: the model's ambient is a constant
## (`BrakeThermal.AMBIENT_C`), so every brake runs shifted by it and is reported shifted back: exact
## where `ε` is 0 (the law is linear in T − T_amb), a warning elsewhere. Stops: `decel=<g>` (a PI
## on the pedal instead of full pedal) and `to=<km/h>` (each stop ends there).
## The deceleration PI: pedal per m/s² short, per m/s² s; the measured deceleration's low-pass per tick.
const DECEL_KP := 0.05
const DECEL_KI := 0.2
const DECEL_FILTER := 0.1
## `doc=brake_check` (arg 1): the field runs of `docs/sources.md` § Brake heat, each against a
## tolerance set before any run (a miss names an estimate, never moves a sourced figure), into
## the `brake_check` region. WY-1901F [154]: Table 10 (p. 85: brakes averaged at the bottom, start temperatures
## stated, no retarder, ambient not stated) and Table 12's downgrade sections (p. 93, about 45 mph),
## the rig's 10 brakes (Table 4: 8 S-cam drums, 2 steer discs). Yaxi [158]: a 32.5 t 6×4, 6 drums,
## 26 km at 2.28 % at its 55.6 km/h mean, 10 °C, the hottest drum's peak. The trucks run on
## `garbage-truck` (the GSRS drums) laden to the field rig's mass per brake (`rig_kg` / `brakes`).
## `check`: `mean` (the brakes' mean rise from `t0`), `peak` (the hottest brake's rise from `amb`),
## `below` (the hottest stays at or under `field`), `stops` (each stop's front-disc rise against
## the heat the ledger leaves for the brakes, times the declared front share, less what the front
## discs shed to the air, over their `C`). Temperatures °C (the page's °F converted), masses kg
## (lb × LB_KG), speeds km/h.
const LB_KG := 0.45359237
const CHECK_TOL_WY := 0.20     ## WY's own TruckSim misses run 4's rise by about 19 %
const CHECK_TOL_YAXI := 0.25   ## a steady hold against a run that swung (69.7 km/h at most, 55.6 mean)
const CHECK_TOL_STOPS := 0.10
## The region's groups, a table row each.
const T10 := "WY-1901F Table 10, runs 1-7"
const T12 := "WY-1901F Table 12, sections 1 / 4 / 6 / 8"
const YAXI := "Yaxi, service brake / engine brake"
const DOC_CHECK_JOBS: Array[Dictionary] = [
	{"group": T10, "label": "run 1", "rig_lb": 79400.0, "grade": 7.0, "km": 6.92, "kmh": 33.8,
			"t0": 56.1, "field": 150.0},
	{"group": T10, "label": "run 2", "rig_lb": 79400.0, "grade": 4.3, "km": 6.41, "kmh": 49.9,
			"t0": 71.9, "field": 130.6},
	{"group": T10, "label": "run 3", "rig_lb": 74000.0, "grade": 7.0, "km": 6.92, "kmh": 49.9,
			"t0": 53.0, "field": 117.8},
	{"group": T10, "label": "run 4", "rig_lb": 74000.0, "grade": 6.1, "km": 8.85, "kmh": 57.9,
			"t0": 82.3, "field": 156.7},
	{"group": T10, "label": "run 5", "rig_lb": 60000.0, "grade": 6.1, "km": 8.85, "kmh": 33.8,
			"t0": 65.8, "field": 115.0},
	{"group": T10, "label": "run 6", "rig_lb": 55000.0, "grade": 7.0, "km": 6.92, "kmh": 49.9,
			"t0": 46.5, "field": 91.7},
	{"group": T10, "label": "run 7", "rig_lb": 60000.0, "grade": 6.1, "km": 8.85, "kmh": 49.9,
			"t0": 67.7, "field": 87.2},
	{"group": T12, "label": "section 1", "rig_lb": 74000.0, "grade": 7.4, "km": 1.06, "kmh": 72.4,
			"t0": 63.1, "amb": 9.9, "field": 84.9},
	{"group": T12, "label": "section 4", "rig_lb": 74000.0, "grade": 6.9, "km": 1.66, "kmh": 72.4,
			"t0": 84.6, "amb": 10.5, "field": 132.5},
	{"group": T12, "label": "section 6", "rig_lb": 74000.0, "grade": 6.5, "km": 1.30, "kmh": 72.4,
			"t0": 124.8, "amb": 11.2, "field": 164.7},
	{"group": T12, "label": "section 8", "rig_lb": 74000.0, "grade": 7.4, "km": 1.96, "kmh": 72.4,
			"t0": 148.1, "amb": 12.6, "field": 217.5},
	{"group": YAXI, "label": "service brake", "mode": "foot", "rig_kg": 32500.0, "brakes": 6,
			"grade": 2.28, "km": 26.0, "kmh": 55.6, "amb": 10.0, "field": 472.7, "check": "peak",
			"tol": CHECK_TOL_YAXI},
	{"group": YAXI, "label": "engine brake", "mode": "retarder", "rig_kg": 32500.0, "brakes": 6,
			"grade": 2.28, "km": 26.0, "kmh": 55.6, "amb": 10.0, "field": 149.7, "check": "below"},
	{"group": "`sedan`, 10 × 100 → 5 km/h at 0.4 g, J2522-style", "label": "stops",
			"variant": "sedan", "mode": "stops", "stops": 10, "kmh": 100.0, "to": 5.0, "decel": 0.4,
			"check": "stops", "tol": CHECK_TOL_STOPS},
]
## A `DOC_CHECK_JOBS` row's defaults: the WY rows'.
const DOC_CHECK_DEFAULTS := {"variant": "garbage-truck", "mode": "foot", "brakes": 10, "amb": 20.0,
		"check": "mean", "tol": CHECK_TOL_WY}


## `stops` / `stops=<n>`: the series' length, 0 when absent.
static func _stops_flag(args: PackedStringArray) -> int:
	if args.has("stops"):
		return STOPS_DEFAULT
	var n := MeasureRig.flag(args, "stops=")
	return maxi(n.to_int(), 1) if n != "" else 0


## The lowest drive byte whose engine speed at `wheel_omega` (rad/s at the drive radius) stays at or
## under the box's upshift point: the gear a driver holds down a grade. 0 on a CVT or none.
static func held_gear_for(spec: VehicleSpec, wheel_omega: float) -> int:
	if Drivetrain.is_cvt(spec):
		return 0
	for byte in range(1, mini(spec.gear_ratios.size(), Drivetrain.TOP_GEAR) + 1):
		if Drivetrain.wheel_engine_rpm(spec, wheel_omega, byte) <= spec.shift_up_rpm:
			return byte
	return 0


## Power (W) a tyre turns to slip heat: its longitudinal force on the slip velocity `omega * radius -
## v_long`, and its side force on the patch's side velocity. Positive whenever the force opposes the slip.
static func slip_loss_w(force_long: float, omega: float, radius: float, v_long: float,
		force_lat := 0.0, v_lat := 0.0) -> float:
	return force_long * (omega * radius - v_long) - force_lat * v_lat


## The brakes' heat over what the ledger leaves for it (`drop - rest`, J); NAN when that is within
## the tolerance of nothing (a retarder hold): a ratio over the ledger's residue measures nothing.
static func heat_share(drop: float, heat: float, rest: float) -> float:
	var expected := drop - rest
	return heat / expected if expected > ENERGY_TOLERANCE * absf(drop) else NAN


func _start_descent(which: String, args: PackedStringArray) -> void:
	InputRouter.set_manual_gearbox(false)  ## per job: only the `gear` hold is manual
	_dsc_grade = MeasureRig.float_flag(args, "grade=", DESCENT_GRADE)
	_dsc_dist = MeasureRig.float_flag(args, "km=", DESCENT_KM) * 1000.0
	_dsc_stops = _stops_flag(args)
	var kmh := MeasureRig.float_flag(args, "kmh=", NAN)
	var only := MeasureRig.flag(args, "mode=")
	var flags := {}  ## the job flags (`mass=`, `per_brake=`, `t0=`, `amb=`, `decel=`, `to=`)
	var surface := MeasureRig.flag(args, "surface=")
	if surface != "":
		if Surface.from_key(surface) < 0:
			printerr("surface=%s: expected one of %s" % [surface, ", ".join(Surface.NAMES)])
			get_tree().quit(1)
			return
		flags["surface"] = surface.to_lower()
	for key: String in ["mass", "per_brake", "t0", "amb", "decel", "to"]:
		if MeasureRig.flag(args, key + "=") != "":
			flags[key] = MeasureRig.float_flag(args, key + "=", 0.0)
	var tuned := not flags.is_empty() or ["grade=", "km=", "kmh=", "mode="].any(
			func(prefix: String) -> bool: return MeasureRig.flag(args, prefix) != "")
	if which in ["doc=brake_fade", "doc=brake_check"]:
		if tuned or _dsc_stops > 0:
			printerr("%s runs its own set: no grade= / km= / kmh= / mode= / stops / mass= / per_brake="
					% which + " / t0= / amb= / decel= / to=")
			get_tree().quit(1)
			return
	if which == "doc=brake_fade":
		_dsc_doc = true
		_dsc_stops = STOPS_DEFAULT
		for v in DOC_DESCENT_VARIANTS:
			for m in DESCENT_MODES:
				_dsc_queue.append({"variant": v, "mode": m, "kmh": DESCENT_KMH})
		for g in DOC_LOW_GRIP:
			_dsc_queue.append({"variant": "semi", "mode": g["mode"], "kmh": DESCENT_KMH,
					"surface": g["surface"], "hold_only": true})
		_dsc_queue.append({"variant": DOC_STOPS_VARIANT, "mode": "stops", "kmh": STOPS_KMH})
	elif which == "doc=brake_check":
		_dsc_check = true
		for j in DOC_CHECK_JOBS:
			var job: Dictionary = j.duplicate()
			job.merge(DOC_CHECK_DEFAULTS)
			if job.has("rig_lb"):
				job["rig_kg"] = float(job["rig_lb"]) * LB_KG
			_dsc_queue.append(job)
	elif not Catalog.VARIANTS.has(which):
		printerr("unknown variant '%s'" % which)
		get_tree().quit(1)
		return
	elif _dsc_stops > 0:
		_dsc_queue.append({"variant": which, "mode": "stops",
				"kmh": STOPS_KMH if is_nan(kmh) else kmh})
	else:
		if only != "" and not DESCENT_MODES.has(only):
			printerr("mode=%s: expected one of %s" % [only, ", ".join(DESCENT_MODES)])
			get_tree().quit(1)
			return
		for m in DESCENT_MODES:
			if only == "" or m == only or m == "cold":
				_dsc_queue.append({"variant": which, "mode": m,
						"kmh": DESCENT_KMH if is_nan(kmh) else kmh})
	for j in _dsc_queue:
		j.merge(flags)
		j.merge({"grade": _dsc_grade, "km": _dsc_dist / 1000.0, "stops": _dsc_stops})
	var descends := _dsc_queue.any(func(j: Dictionary) -> bool: return j["mode"] != "stops")
	_dsc_length = 0.0
	for j in _dsc_queue:
		_dsc_length = maxf(_dsc_length, DESCENT_RUNUP + (STOPS_CYCLE * int(j["stops"])
				if j["mode"] == "stops" else float(j["km"]) * 1000.0 + DESCENT_RUNOUT))
	if _dsc_check:
		print(("=== brake_check: %d field runs (`docs/sources.md` § Brake heat), each against its"
				+ " tolerance; energy tolerance ±%.0f %% ===") % [_dsc_queue.size(), 100.0 * ENERGY_TOLERANCE])
	elif descends:
		print("=== descent: %.1f %% for %.1f km, held at the job's speed, then a full-pedal stop;"
				% [_dsc_grade, _dsc_dist / 1000.0] + " energy tolerance ±%.0f %% ===" % (100.0 * ENERGY_TOLERANCE))
	if _dsc_stops > 0:
		print("=== stops: %d %s stops on the flat, floored in D between them ===" % [_dsc_stops,
				"full-pedal" if not flags.has("decel") else "%.2f g" % flags["decel"]])
	_next_descent()


func _next_descent() -> void:
	InputRouter.set_manual_gearbox(false)
	if _dsc_queue.is_empty():
		_print_descent()
		if _dsc_doc:
			DocRegion.write("brake_fade", _descent_doc_table())
		if _dsc_check:
			var table := _check_doc_table()
			print("\n" + "\n".join(table))
			DocRegion.write("brake_check", table)
		get_tree().quit(0)
		return
	var job: Dictionary = _dsc_queue.pop_front()
	_dsc_job = job
	_variant = String(job["variant"])
	_dsc_mode = String(job["mode"])
	_dsc_speed = float(job["kmh"]) / 3.6
	_dsc_grade = float(job["grade"])
	_dsc_dist = float(job["km"]) * 1000.0
	_dsc_stops = int(job["stops"])
	_dsc_shift = float(job.get("amb", BrakeThermal.AMBIENT_C)) - BrakeThermal.AMBIENT_C
	_dsc_mean = {}
	_angle = 0.0 if _dsc_mode == "stops" else rad_to_deg(atan(_dsc_grade / 100.0))
	var a := deg_to_rad(_angle)
	_dsc_lift = _dsc_length * 0.5 * sin(a) + 5.0  ## the foot 5 m over the origin
	# Wide as a tenth of its length: room for a rig that jackknifes off the steered line on low grip.
	_ramp = MeasureRig.tilt_ramp(self, _ramp, Vector3(maxf(RAMP_WIDTH, 0.1 * _dsc_length),
			RAMP_THICKNESS, _dsc_length), a, _dsc_lift)
	_patch.tan_angle = tan(a)
	_patch.lift = _dsc_lift
	_surface = String(job.get("surface", "asphalt"))
	_patch.surface = Surface.from_key(_surface)
	_spawn(_angle, PI, _dsc_length * 0.5 - SPAWN_UP, _dsc_lift)  ## facing down, near the top
	var gd: GroundDriveSpec = _car.spec.ground_drive
	if _dsc_mode == "gear":
		_dsc_gear = _held_gear if _held_gear > 0 else held_gear_for(_car.spec,
				_dsc_speed / gd.drive_radius())
		if _dsc_gear == 0:
			print("  %-16s gear     : skipped, the box holds no fixed gear" % _variant)
			_next_descent()
			return
	if _dsc_mode == "retarder" and not gd.retarder_equipped:
		print("  %-16s retarder : skipped, none fitted" % _variant)
		_next_descent()
		return
	_dsc_row = {"variant": _variant, "mode": _dsc_mode, "kmh": float(job["kmh"]), "stops": [],
			"job": job}
	_dsc_stop = 0
	_dsc_trailer = null
	_dsc_host = null
	_phase = Ph.DESC_SETTLE
	_t = 0.0
	_dsc_drive(0.0, 100.0)


## Driven through the bridge as `_drive`, with the retarder request (0..1) and the gear byte (1: D,
## or the held byte under `InputRouter.set_manual_gearbox`), steered down the ramp's centre line
## (`MeasureRig.pursuit_steer`): unsteered, a rig's slow yaw walks it off the ramp on low grip.
func _dsc_drive(accel_pct: float, brake_pct: float, retarder01 := 0.0, gear := 1) -> void:
	# The centre line on the ramp's top face (it passes through (0, lift, 0)), not under it: a line
	# below the face reads the body's roll as a lateral error.
	var steer := MeasureRig.pursuit_steer(_car, Vector3.UP * _dsc_lift, _downhill()) \
			if _car != null else 0.0
	MeasureRig.drive(accel_pct, brake_pct, steer * 100.0, false, gear, false, 3,
			{"retarder": retarder01 * 100.0})


func _descent_step(delta: float) -> void:
	var down := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3.BACK
	var v := _car.linear_velocity.dot(down)
	if _phase == Ph.DESC_SETTLE:
		_dsc_drive(0.0, 100.0)
		if _t >= SETTLE_S:
			_dsc_host = MeasureRig.coupled_host(_car)
			_dsc_trailer = _dsc_host.trailer if _dsc_host != null else null
			_apply_job_mass()
			_phase = Ph.DESC_RUNUP
			_t = 0.0
		return
	if _phase == Ph.DESC_RUNUP:
		var coast := 0.0 if _dsc_mode == "stops" else DESCENT_COAST
		_dsc_drive(100.0 if v < _dsc_speed - coast else 0.0, 0.0)
		if v >= _dsc_speed:
			_dsc_gap = _t
			if _dsc_mode == "stops":
				_begin_stop(v)
			else:
				_begin_hold()
		elif _t >= DESCENT_RUNUP_S:
			print("  %-16s %-8s : never reached %.0f km/h (%.1f km/h after %.0f s)" % [_variant,
					_dsc_mode, _dsc_speed * 3.6, v * 3.6, _t])
			_next_descent()
		return
	_ledger_tick(delta)
	_track_units()
	if _phase == Ph.DESC_STOP:
		if is_instance_valid(_dsc_trailer):
			_dsc_stop_artic = maxf(_dsc_stop_artic, absf(_dsc_host.articulation()))
		for w in _thermal_brakes():
			if not w.is_rear:
				_dsc_front_loss += BrakeThermal.loss_w(w.brake_temp, _car.linear_velocity.length(),
						w.brake_figures) * delta
		_dsc_drive(0.0, 100.0 if not _dsc_job.has("decel") else _decel_pedal(v, delta) * 100.0)
		if absf(v) < maxf(STOP_SPEED, float(_dsc_job.get("to", 0.0)) / 3.6) or _t >= DESCENT_RUNUP_S:
			_end_stop()
		return
	var over := v - _dsc_speed
	var pedal_over := over - TOPUP_BAND if _dsc_mode == "retarder" else over
	var pedal := _dsc_pedal_hold.step(pedal_over, delta)
	var ret := 0.0
	if _dsc_mode == "retarder":
		ret = _dsc_ret_hold.step(over, delta)
	_dsc_drive(0.0, pedal * 100.0, ret, _dsc_gear if _dsc_mode == "gear" else 1)
	var byte := _car.drivetrain.gear_byte
	if _t >= 1.0:  ## past the shift into a held gear, which reads the last request's byte a tick
		_dsc_gears = Vector2i(mini(_dsc_gears.x, byte), maxi(_dsc_gears.y, byte))
	_dsc_speed_sum += v
	_dsc_ticks += 1
	if is_instance_valid(_dsc_trailer):
		_dsc_artic = maxf(_dsc_artic, absf(_dsc_host.articulation()))
	var dist := (_car.global_position - _dsc_x0).dot(down)
	if _verbose:
		_trace_t += delta
		if _trace_t >= 10.0:
			_trace_t = 0.0
			print("      t %5.0f  %6.0f m  across %+6.2f m  y %6.1f  %5.1f km/h  pedal %.2f  ret %.2f  D%d  %s%s"
					% [_t, dist, _car.global_position.x, _car.global_position.y, v * 3.6, pedal,
					ret, byte, _units_line(), "" if not is_instance_valid(_dsc_trailer)
					else "  articulation %+.2f°" % rad_to_deg(_dsc_host.articulation())])
	if _t >= 3.0 * _dsc_dist / _dsc_speed or dist < -1.0:  ## stalled, or respawned off the ramp
		print("  %-16s %-8s : the hold ended at %.0f m after %.0f s (%.1f km/h), not measured%s"
				% [_variant, _dsc_mode, dist, _t, v * 3.6, "" if not is_instance_valid(_dsc_trailer)
				else "; articulation %.1f° at most" % rad_to_deg(_dsc_artic)])
		if _dsc_job.has("hold_only"):  ## a low-grip row records the loss rather than vanishing
			# Past a respawn the brakes, the ledger and the gear read the fresh body: only the
			# articulation reached on the ramp is kept.
			_dsc_row["lost"] = true
			_dsc_row["hold"] = {"artic": rad_to_deg(_dsc_artic)}
			_dsc_rows.append(_dsc_row)
		_next_descent()
		return
	if not _dsc_row.has("onset") and _dsc_units.values().any(func(u: Dictionary) -> bool:
			return u["fade"] < 1.0):
		_dsc_row["onset"] = dist  ## m down the hold where the first brake fades
	if (_t >= DESCENT_COLD_S) if _dsc_mode == "cold" else (dist >= _dsc_dist):
		_end_hold(dist, v)


func _begin_hold() -> void:
	_phase = Ph.DESC_HOLD
	_t = 0.0
	_dsc_x0 = _car.global_position
	_dsc_pedal_hold.integral = 0.0
	_dsc_ret_hold.integral = 0.0
	_dsc_gears = Vector2i(Drivetrain.TOP_GEAR + 1, 0)
	_dsc_speed_sum = 0.0
	_dsc_ticks = 0
	_dsc_artic = 0.0
	_dsc_units = {}
	_trace_t = 0.0
	_ledger_start()
	InputRouter.set_manual_gearbox(_dsc_mode == "gear")
	if _dsc_job.has("t0"):
		for w in _thermal_brakes():
			w.brake_temp = float(_dsc_job["t0"]) - _dsc_shift
	if _dsc_shift != 0.0 and _thermal_brakes().any(func(w: RayWheel) -> bool:
			return w.brake_figures.emissivity > 0.0):
		print("  WARNING amb=%.1f: a radiating brake (ε > 0) is not linear in T − T_amb, the shift is"
				% (BrakeThermal.AMBIENT_C + _dsc_shift) + " approximate")


func _end_hold(dist: float, v: float) -> void:
	var check := _ledger_result()
	var gears := "D%d" % _dsc_gears.x if _dsc_gears.x == _dsc_gears.y \
			else "D%d-D%d" % [_dsc_gears.x, _dsc_gears.y]
	var n := maxi(int(_dsc_mean.get("n", 0)), 1)
	_dsc_row["hold"] = {"units": _dsc_units.duplicate(true), "check": check, "gears": gears,
			"mean": _dsc_mean.duplicate(), "power": float(check["brakes"]) / maxf(_t, 1e-6) / n,
			"artic": rad_to_deg(_dsc_artic)}
	print("  %-16s %-8s : %.0f m in %.0f s at %.1f km/h mean, %s; %s; %s" % [_variant, _dsc_mode,
			dist, _t, _dsc_speed_sum / maxi(_dsc_ticks, 1) * 3.6, gears, _units_line(),
			"no fade" if not _dsc_row.has("onset") else "fades from %.0f m (%.0f m drop)" % [
			_dsc_row["onset"], float(_dsc_row["onset"]) * sin(deg_to_rad(_angle))]])
	print("    energy  : %s; %.1f kW a brake" % [_ledger_line(check),
			float(_dsc_row["hold"]["power"]) / 1000.0])
	if is_instance_valid(_dsc_trailer):
		var artic := float(_dsc_row["hold"]["artic"])
		print("    kingpin : push %.1f kN down the grade (+ = the trailer pushes); articulation %.1f°"
				% [float(check["kingpin"]) / 1000.0, artic]
				+ " at most, %s (under %.0f°)" % ["PASS" if artic < ARTICULATION_BOUND_DEG else "FAIL",
				ARTICULATION_BOUND_DEG])
	InputRouter.set_manual_gearbox(false)
	if _dsc_job.has("check") or _dsc_job.has("hold_only"):  ## its figure is the hold's
		_dsc_rows.append(_dsc_row)
		_phase = Ph.DONE
		_next_descent()
		return
	if is_instance_valid(_dsc_trailer) and rad_to_deg(_dsc_artic) >= ARTICULATION_BOUND_DEG:
		_lost_stop("jackknifed", _dsc_artic)
		return
	_begin_stop(v)


## The stop after a hold, never run or ended by a lost rig (`why`: jackknifed, left the ramp, never
## stopped): a distance and closure there read a folded, respawned or moving body, so the row
## keeps only `why`.
func _lost_stop(why: String, artic: float) -> void:
	_dsc_row["stop"] = {"lost": why}
	print("    stop    : none, the rig %s%s" % [why, "" if not is_instance_valid(_dsc_trailer)
			else " (articulation %.1f° at most)" % rad_to_deg(artic)])
	_dsc_rows.append(_dsc_row)
	_phase = Ph.DONE
	_next_descent()


func _begin_stop(v: float) -> void:
	_phase = Ph.DESC_STOP
	_t = 0.0
	_dsc_x0 = _car.global_position
	_dsc_v0 = v
	_dsc_units = {}
	_ledger_start()
	_dsc_front0 = float(_brake_means()["front"])
	_dsc_front_loss = 0.0
	_dsc_stop_artic = 0.0
	if _dsc_job.has("decel"):
		_dsc_v_prev = v
		_dsc_a = float(_dsc_job["decel"]) * BrakeSizing.G
		_dsc_decel_hold.integral = _decel_feedforward()
		_dsc_drive(0.0, _dsc_decel_hold.integral * 100.0)
	else:
		_dsc_drive(0.0, 100.0)


func _end_stop() -> void:
	var down := Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3.BACK
	var dist := (_car.global_position - _dsc_x0).dot(down)
	var check := _ledger_result()
	var stop := {"v0": _dsc_v0, "dist": dist, "t": _t, "gap": _dsc_gap,
			"units": _dsc_units.duplicate(true), "check": check}
	if _dsc_mode == "stops":
		var gd: GroundDriveSpec = _car.spec.ground_drive
		var fronts := _thermal_brakes().filter(func(w: RayWheel) -> bool: return not w.is_rear)
		stop["front_rise"] = float(_brake_means()["front"]) - _dsc_front0
		stop["front_expected"] = (float(check["left"]) * front_brake_share(gd) - _dsc_front_loss) \
				/ (maxf(fronts.size(), 1) * maxf(gd.brake_heat_capacity, 1e-6))
		(_dsc_row["stops"] as Array).append(stop)
		_dsc_stop += 1
		print("  %-16s stop %2d : %5.1f km/h -> %.0f in %5.1f m (%4.1f s) after a %4.1f s run-up; %s"
				% [_variant, _dsc_stop, _dsc_v0 * 3.6, _car.linear_velocity.length() * 3.6, dist,
				_t, _dsc_gap, _units_line()])
		print("    energy  : %s" % _ledger_line(check))
		print("    front   : discs rose %.2f K against %.2f K expected, %.2f K of it shed to the air (%.3f)"
				% [stop["front_rise"], stop["front_expected"], _dsc_front_loss / (maxf(fronts.size(), 1)
				* maxf(gd.brake_heat_capacity, 1e-6)), float(stop["front_rise"])
				/ maxf(float(stop["front_expected"]), 1e-6)])
		if _dsc_stop < _dsc_stops:
			_phase = Ph.DESC_RUNUP
			_t = 0.0
			return
	else:
		# Off the ramp the body respawns at the top: the distance reads back up the grade. A stop the
		# cap ended still moving has no distance to report either.
		var lost := "left the ramp" if dist < -1.0 else "jackknifed" if is_instance_valid(_dsc_trailer) \
				and rad_to_deg(_dsc_stop_artic) >= ARTICULATION_BOUND_DEG else "never stopped" \
				if absf(_car.linear_velocity.dot(down)) >= maxf(STOP_SPEED,
				float(_dsc_job.get("to", 0.0)) / 3.6) else ""
		if lost != "":
			_lost_stop(lost, _dsc_stop_artic)
			return
		_dsc_row["stop"] = stop
		if _dsc_mode == "cold":
			_dsc_cold[_variant] = dist
		print("    stop    : %5.1f km/h -> 0 in %5.1f m (%4.1f s)%s; %s" % [_dsc_v0 * 3.6, dist, _t,
				"" if _dsc_mode == "cold" or not _dsc_cold.has(_variant)
				else ", cold %.1f m" % _dsc_cold[_variant], _units_line()])
		print("    energy  : %s" % _ledger_line(check))
	_dsc_rows.append(_dsc_row)
	_phase = Ph.DONE
	_next_descent()


## The powered unit's and a coupled trailer's brakes, this tick: the hottest and the lowest factor
## now, and the peak and the minimum since the hold or stop began.
func _track_units() -> void:
	_track("powered", _car.drive.wheels)
	if is_instance_valid(_dsc_trailer):
		_track("trailer", _dsc_trailer.wheels)
	_dsc_mean = _brake_means()


func _track(unit: String, wheels: Array[RayWheel]) -> void:
	var u: Dictionary = _dsc_units.get(unit, {"peak": BrakeThermal.AMBIENT_C + _dsc_shift, "min": 1.0})
	var hottest := BrakeThermal.AMBIENT_C
	var fade := 1.0
	for w in wheels:
		hottest = maxf(hottest, w.brake_temp)
		fade = minf(fade, w.brake_fade())
	hottest += _dsc_shift
	u["peak"] = maxf(float(u["peak"]), hottest)
	u["min"] = minf(float(u["min"]), fade)
	u["end"] = hottest
	u["fade"] = fade
	_dsc_units[unit] = u


func _units_line() -> String:
	var parts: Array[String] = []
	for unit in ["powered", "trailer"]:
		if _dsc_units.has(unit):
			var u: Dictionary = _dsc_units[unit]
			parts.append("%s peak %.0f °C (end %.0f), fade min %.2f (end %.2f)" % [unit, u["peak"],
					u["end"], u["min"], u["fade"]])
	if not _dsc_mean.is_empty():
		parts.append("mean of %d brakes %.1f °C (front %.1f)" % [_dsc_mean["n"], _dsc_mean["mean"],
				_dsc_mean["front"]])
	return ", ".join(parts)


## Every friction brake on the rig with a thermal model (the trailer's too).
func _thermal_brakes() -> Array[RayWheel]:
	var out: Array[RayWheel] = []
	for b in MeasureRig.rig_bodies(_car):
		for w in _wheels_of(b):
			if w.brake_figures.capacity > 0.0:
				out.append(w)
	return out


## The rig's thermal brakes now: {mean, front (the front axle's mean), n}, °C shifted by `amb=`.
func _brake_means() -> Dictionary:
	var sum := 0.0
	var front := Vector2.ZERO  ## sum, count
	var brakes := _thermal_brakes()
	for w in brakes:
		sum += w.brake_temp
		if not w.is_rear:
			front += Vector2(w.brake_temp, 1.0)
	return {"mean": sum / maxf(brakes.size(), 1) + _dsc_shift,
			"front": front.x / maxf(front.y, 1.0) + _dsc_shift, "n": brakes.size()}


## The job's `mass=` or mass per brake (`per_brake=`, or `rig_kg` / `brakes`) on the body: per
## brake counts the body's own thermal brakes, a coupled trailer keeping its mass and brakes.
func _apply_job_mass() -> void:
	var kg := float(_dsc_job.get("mass", NAN))
	var per := float(_dsc_job.get("per_brake", NAN))
	if _dsc_job.has("rig_kg"):
		per = float(_dsc_job["rig_kg"]) / float(_dsc_job["brakes"])
	var own := _car.drive.wheels.filter(func(w: RayWheel) -> bool: return w.brake_figures.capacity > 0.0)
	if not is_nan(per):
		kg = per * own.size()
	_dsc_row["mass"] = _car.mass
	if is_nan(kg):
		return
	_car.set_live_mass(kg)
	_dsc_row["mass"] = kg
	print("  %-16s mass %.0f kg, %.0f kg a thermal brake" % [_variant, kg, kg / maxf(own.size(), 1)])


## The pedal holding the job's `decel`: a PI on the filtered deceleration.
func _decel_pedal(v: float, delta: float) -> float:
	_dsc_a = lerpf(_dsc_a, (_dsc_v_prev - v) / delta, DECEL_FILTER)
	_dsc_v_prev = v
	return _dsc_decel_hold.step(float(_dsc_job["decel"]) * BrakeSizing.G - _dsc_a, delta)


## The pedal the job's `decel` asks on the cold brake: `WheelDrive.brake_application` inverted.
func _decel_feedforward() -> float:
	var cap := BrakeSizing.g_per_demand(_car.spec, _car.mass)
	var k := 1.0
	if cap > WheelDrive.BRAKE_HALF_PEDAL_G:
		k = log(WheelDrive.BRAKE_HALF_PEDAL_G / cap) / log(0.5)
	return pow(clampf(float(_dsc_job["decel"]) / maxf(cap, 1e-6), 0.0, 1.0), 1.0 / k)


## The front axle's share of the foot brake's force at the road (`BrakeSizing.brake_force`'s
## terms), which is its share of the heat: a wheel's brake power is its torque over its radius times v.
static func front_brake_share(gd: GroundDriveSpec) -> float:
	var front := 0.0
	var all := 0.0
	for p in gd.wheel_positions:
		var rear := RayWheel.is_rear_z(p.z)
		var f := gd.axle_brake_torque(rear) / maxf(gd.axle_radius(rear), 1e-6)
		all += f
		if not rear:
			front += f
	return front / maxf(all, 1e-6)


func _wheels_of(b: RigidBody3D) -> Array[RayWheel]:
	return (b as BaseVehicle).drive.wheels if b is BaseVehicle else (b as TowedBody).wheels


## Kinetic, wheel-spin and potential energy of the rig (J).
func _rig_energy() -> float:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var e := 0.0
	for b in MeasureRig.rig_bodies(_car):
		e += 0.5 * b.mass * b.linear_velocity.length_squared() + b.mass * g * b.global_position.y
		for w in _wheels_of(b):
			e += 0.5 * w.wheel_inertia * w.omega * w.omega
	return e


func _ledger_start() -> void:
	_dsc_ledger = {"e0": _rig_energy(), "brakes": 0.0, "retarder": 0.0, "driveline": 0.0,
			"rolling": 0.0, "air": 0.0, "slip": 0.0, "t": 0.0, "towed_ext": 0.0,
			"towed_p0": _towed_momentum()}


## The ramp's downhill direction (world).
func _downhill() -> Vector3:
	return Basis(Vector3.RIGHT, deg_to_rad(_angle)) * Vector3.BACK


## The trailer's momentum down the grade (kg m/s), 0 bobtail.
func _towed_momentum() -> float:
	if not is_instance_valid(_dsc_trailer):
		return 0.0
	return _dsc_trailer.mass * _dsc_trailer.linear_velocity.dot(_downhill())


## One tick of the ledger, read before the bodies tick: last tick's forces and settles, on the
## motion they produced.
func _ledger_tick(delta: float) -> void:
	var l := _dsc_ledger
	l["t"] += delta
	for b in MeasureRig.rig_bodies(_car):
		var fwd := -b.global_basis.z
		var right := b.global_basis.x
		var gd: GroundDriveSpec = (b.get("spec") as VehicleSpec).ground_drive
		# The trailer's forces besides the joint, down the grade: its patches, gravity, air (below).
		# COMPROMISE: Jolt reports no joint force, so the joint's is the residual; a body touching the
		# ground besides its patches would count in it. Reading the joint's impulse needs an engine API.
		var towed := b == _dsc_trailer
		var ext := Vector3.ZERO
		if towed:
			ext = Vector3.DOWN * b.mass * b.gravity_scale \
					* float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		for w in _wheels_of(b):
			if towed:
				ext += w.contact_force
			var work := w.brake_reacted * w.brake_settled_spin * delta
			l["brakes"] += work * w.brake_friction_share
			l["retarder"] += work * (1.0 - w.brake_friction_share)
			if not w.in_contact:
				continue
			var vel := b.linear_velocity + b.angular_velocity.cross(w.contact_point - b.global_position)
			l["rolling"] -= w.force_roll * vel.dot(fwd) * delta
			l["slip"] += slip_loss_w(w.force_long, w.omega, w.wheel_radius, vel.dot(fwd), w.force_lat,
					vel.dot(right)) * delta
		if gd.drag_area > 0.0 or b is TowedBody:  ## as `WheelDrive._apply_resistance` / `tick_towed`
			var air := VehicleMath.air_force(b.linear_velocity, WindField.at(b), b.global_basis,
					gd.drag_area, gd.side_area, b.mass, delta)
			l["air"] -= air.dot(b.linear_velocity) * delta
			ext += air
		if towed:
			l["towed_ext"] += ext.dot(_downhill()) * delta
	var drive := _car.drive
	var spin := 0.0
	for i in drive.wheels.size():
		if drive.wheels[i].driven:
			spin += drive._ratio[i] * drive.wheels[i].omega
	l["driveline"] -= drive._drive_torque / maxf(1.0, drive._driven_count) * spin * delta


func _ledger_result() -> Dictionary:
	var l := _dsc_ledger.duplicate()
	l["drop"] = float(l["e0"]) - _rig_energy()
	var rest := float(l["retarder"]) + float(l["driveline"]) + float(l["rolling"]) \
			+ float(l["air"]) + float(l["slip"])
	l["share"] = heat_share(float(l["drop"]), float(l["brakes"]), rest)
	l["left"] = float(l["drop"]) - rest  ## J, what the ledger leaves for the friction brakes
	# Where the rest leaves the brakes nothing (a retarder hold), the share has no denominator: the
	# ledger's closure on the drop is judged instead.
	l["closure"] = (float(l["drop"]) - rest - float(l["brakes"])) / maxf(float(l["drop"]), 1.0)
	# The joint's mean force on the trailer down the grade is its momentum change less the rest;
	# the push on the tractor is its opposite (+ = the trailer pushes). NAN bobtail.
	l["kingpin"] = NAN if not is_instance_valid(_dsc_trailer) else -(_towed_momentum()
			- float(l["towed_p0"]) - float(l["towed_ext"])) / maxf(float(l["t"]), 1e-6)
	return l


func _ledger_line(l: Dictionary) -> String:
	var share := float(l["share"])
	var ok := absf(share - 1.0) <= ENERGY_TOLERANCE if not is_nan(share) \
			else absf(float(l["closure"])) <= ENERGY_TOLERANCE
	return ("drop %.3f MJ: brakes %.3f, retarder %.3f, driveline %.3f, rolling %.3f, air %.3f,"
			+ " tyre slip %.3f MJ; %s  %s (±%.0f %%)") % [
			float(l["drop"]) / 1e6, float(l["brakes"]) / 1e6, float(l["retarder"]) / 1e6,
			float(l["driveline"]) / 1e6, float(l["rolling"]) / 1e6, float(l["air"]) / 1e6,
			float(l["slip"]) / 1e6, _check_cell(l), "PASS" if ok else "FAIL",
			100.0 * ENERGY_TOLERANCE]


## The check's figure: the heat share, or the closure where nothing was left for the brakes.
static func _check_cell(l: Dictionary) -> String:
	if is_nan(float(l["share"])):
		return "nothing left for the brakes, closure %+.1f %% of the drop" % (100.0 * float(l["closure"]))
	return "brakes / (drop - the rest) %.3f" % float(l["share"])


## `_check_cell` for a table.
static func _check_short(l: Dictionary) -> String:
	if is_nan(float(l["share"])):
		return "closure %+.1f %%" % (100.0 * float(l["closure"]))
	return "%.3f" % float(l["share"])


func _print_descent() -> void:
	print("\n%-16s %-8s %-8s %20s %20s %14s %8s" % ["variant", "mode", "gears", "powered °C / fade",
			"trailer °C / fade", "stop m (cold)", "energy"])
	for r in _dsc_rows:
		if r["mode"] == "stops":
			for i in (r["stops"] as Array).size():
				var s: Dictionary = r["stops"][i]
				print("%-16s stop %-3d %-8s %20s %20s %14.1f %8s" % [r["variant"], i + 1, "",
						_unit_cell(s["units"], "powered"), _unit_cell(s["units"], "trailer"), s["dist"],
						_check_short(s["check"])])
			continue
		if not r.has("stop"):  ## a field run (`doc=brake_check`): its table follows
			continue
		var h: Dictionary = r["hold"]
		var stop_m := String(r["stop"]["lost"]) if r["stop"].has("lost") \
				else "%7.1f (%4.1f)" % [r["stop"]["dist"], _dsc_cold.get(r["variant"], NAN)]
		print("%-16s %-8s %-8s %20s %20s %14s %8s" % [r["variant"], r["mode"], h["gears"],
				_unit_cell(h["units"], "powered"), _unit_cell(h["units"], "trailer"), stop_m,
				_check_short(h["check"])])


## "°C, factor" at the end of the hold or stop, "none" without that unit.
static func _unit_cell(units: Dictionary, unit: String) -> String:
	if not units.has(unit):
		return "none"
	return "%.0f °C, %.2f" % [units[unit]["end"], units[unit]["fade"]]


## The `brake_fade` region: one row per descent, then the stop series across.
func _descent_doc_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_grade -- doc=brake_fade`): %.0f km down %.0f %% at"
			+ " %.0f km/h, steered, on the foot brake, a held lower gear and it, or the retarder it tops"
			+ " up (last on low grip); the hottest brake and its fade, where fade starts, a full-pedal"
			+ " stop hot / cold, the energy check (±%.0f %%), the kingpin's mean push (+ = the trailer"
			+ " pushes) and largest articulation (past %.0f° it jackknifes):") % [
			DocRegion.measured(), DESCENT_KM, DESCENT_GRADE, DESCENT_KMH, 100.0 * ENERGY_TOLERANCE,
			ARTICULATION_BOUND_DEG])
	lines.append_array(["", "| Run | Powered unit | Trailer | Fades from | Stop hot / cold | Energy check | Kingpin |",
			"| --- | --- | --- | --- | --- | --- | --- |"])
	var series: Dictionary = {}
	var grip: Array[Dictionary] = []
	for r in _dsc_rows:
		if r["mode"] == "stops":
			series = r
			continue
		if r["job"].has("hold_only"):
			grip.append(r)
			continue
		if r["mode"] == "cold":
			continue
		var h: Dictionary = r["hold"]
		var towed := "" if not h["units"].has("trailer") else " + %.0f t" % (_dsc_trailer_t(r) / 1000.0)
		var kingpin := float(h["check"]["kingpin"])
		var lost: String = r["stop"].get("lost", "")
		lines.append("| `%s`%s, %s (%s) | %s | %s | %s | %s / %s | %s / %s | %s |" % [
				r["variant"], towed, r["mode"], h["gears"], _unit_cell(h["units"], "powered"),
				_unit_cell(h["units"], "trailer"),
				"none" if not r.has("onset") else "%.0f m" % r["onset"],
				lost if lost != "" else "%.1f" % r["stop"]["dist"],
				"%.1f m" % _dsc_cold[r["variant"]] if _dsc_cold.has(r["variant"]) else "none",
				_check_short(h["check"]),
				"none" if lost != "" else _check_short(r["stop"]["check"]), "none" if is_nan(kingpin)
				else "%+.1f kN, %.1f°" % [kingpin / 1000.0, float(h["artic"])]])
	for r in grip:  ## no stop after a low-grip hold
		var h: Dictionary = r["hold"]
		var artic := float(h["artic"])
		if r.has("lost"):
			lines.append("| `%s` + %.0f t, %s, %s | none | none | none | none | left the ramp | %.1f°, jackknifes |"
					% [r["variant"], _dsc_trailer_t(r) / 1000.0, r["mode"], r["job"]["surface"], artic])
			continue
		var kingpin := float(h["check"]["kingpin"])
		lines.append("| `%s` + %.0f t, %s (%s), %s | %s | %s | %s | none | %s / none | %s, %.1f°%s |" % [
				r["variant"], _dsc_trailer_t(r) / 1000.0, r["mode"], h["gears"], r["job"]["surface"],
				_unit_cell(h["units"], "powered"), _unit_cell(h["units"], "trailer"),
				"none" if not r.has("onset") else "%.0f m" % r["onset"],
				_check_short(h["check"]),
				"none" if is_nan(kingpin) else "%+.1f kN" % (kingpin / 1000.0), artic,
				"" if artic < ARTICULATION_BOUND_DEG else ", jackknifes"])
	if series.is_empty():
		return lines
	var stops: Array = series["stops"]
	lines.append("")
	lines.append_array(DocRegion.wrap("`%s`, %d full-pedal stops from %.0f km/h on the flat, floored between:"
			% [series["variant"], stops.size(), series["kmh"]]))
	var header := "| Stop |"
	var dist := "| m |"
	var temp := "| °C |"
	var fade := "| Fade |"
	var check := "| Energy |"
	for i in stops.size():
		header += " %d |" % (i + 1)
		dist += " %.1f |" % stops[i]["dist"]
		temp += " %.0f |" % stops[i]["units"]["powered"]["end"]
		fade += " %.2f |" % stops[i]["units"]["powered"]["fade"]
		check += " %s |" % _check_short(stops[i]["check"])
	lines.append_array(["", header, "| --- |" + " --- |".repeat(stops.size()), dist, temp, fade,
			check])
	return lines


## The towed mass (kg) behind a doc row's variant: `MeasureRig.rig_mass` less the body's.
func _dsc_trailer_t(r: Dictionary) -> float:
	return MeasureRig.rig_mass(r["variant"]) - Catalog.spec_of(r["variant"]).mass


## WY-1901F Table 11's power into one of the rig's 10 brakes (W): `HP_B = (Wθ − F_drag) V / 375 −
## HP_eng`, `F_drag = 459.35 + 0.132 V²` (lb), `HP_eng` 63.3 (the engine brake off), V in mph.
static func gsrs_brake_power_w(rig_lb: float, grade_pct: float, kmh: float) -> float:
	var mph := kmh / 1.609344
	var hp := (rig_lb * grade_pct / 100.0 - (459.35 + 0.132 * mph * mph)) * mph / 375.0 - 63.3
	return hp * 745.7 / 10.0


## A `doc=brake_check` row's verdict: `ratios` (the sim's rise over the field's: one, or one a
## stop; none for `below`), `cell` (its table text), `ok` of `n` within `tol` (its table text).
static func check_verdict(r: Dictionary) -> Dictionary:
	var job: Dictionary = r["job"]
	var field := float(job.get("field", NAN))
	var tol := float(job.get("tol", 0.0))
	var ratios: Array[float] = []
	match String(job["check"]):
		"mean":
			ratios.append((float(r["hold"]["mean"]["mean"]) - float(job["t0"]))
					/ (field - float(job["t0"])))
		"peak":
			ratios.append((float(r["hold"]["units"]["powered"]["peak"]) - float(job["amb"]))
					/ (field - float(job["amb"])))
		"below":
			var peak := float(r["hold"]["units"]["powered"]["peak"])
			return {"ratios": ratios, "cell": "%.0f °C" % peak, "ok": 1 if peak <= field else 0,
					"n": 1, "tol": "at most %.1f °C" % field}
		"stops":
			for s: Dictionary in r["stops"]:
				ratios.append(float(s["front_rise"]) / maxf(float(s["front_expected"]), 1e-6))
	var ok := ratios.filter(func(x: float) -> bool: return absf(x - 1.0) <= tol).size()
	return {"ratios": ratios, "cell": _span(ratios), "ok": ok, "n": ratios.size(),
			"tol": "±%.0f %%" % (100.0 * tol)}


## "lo-hi" of `values` in `fmt`, one figure where both ends print alike.
static func _span(values: Array, fmt := "%.2f") -> String:
	if values.is_empty():
		return "-"
	var lo: String = fmt % values.min()
	var hi: String = fmt % values.max()
	return lo if lo == hi else lo + "-" + hi


## The `brake_check` region: one row a field-run group (`DOC_CHECK_JOBS`' `group`), the console
## each run's.
func _check_doc_table() -> Array[String]:
	var lines := DocRegion.wrap("%s (`doc=brake_check`), the field runs of `docs/sources.md` § Brake heat:"
			% DocRegion.measured())
	lines.append_array(["", "| Field run | Sim / field rise | Power a brake, sim / WY Table 11 | Within |",
			"| --- | --- | --- | --- |"])
	var groups := {}  ## group -> its rows, in run order
	for r in _dsc_rows:
		if (r["job"] as Dictionary).has("check"):
			var g: Array = groups.get_or_add(r["job"]["group"], [])
			g.append(r)
	for group: String in groups:
		var rows: Array = groups[group]
		var ratios := []
		var cells: Array[String] = []
		var powers := []
		var masses := []
		var results: Array[String] = []
		var ok := 0
		var n := 0
		for r: Dictionary in rows:
			var v := check_verdict(r)
			var job: Dictionary = r["job"]
			ratios.append_array(v["ratios"])
			cells.append(v["cell"])
			ok += int(v["ok"])
			n += int(v["n"])
			results.append(("pass" if v["ok"] == v["n"] else "**miss**") + " (%s)" % v["tol"])
			masses.append(float(r["mass"]) / 1000.0)
			var power := "-"
			if r.has("hold"):
				power = "%.1f kW" % (float(r["hold"]["power"]) / 1000.0)
				if job.has("rig_lb"):
					var gsrs := gsrs_brake_power_w(float(job["rig_lb"]), float(job["grade"]),
							float(job["kmh"]))
					powers.append(float(r["hold"]["power"]) / gsrs)
					power += " / %.1f" % (gsrs / 1000.0)
			print("  check  %s, %s: %s (%s), %s" % [group, job["label"], v["cell"], results[-1], power])
		var same := rows.all(func(r: Dictionary) -> bool: return r["job"]["check"] == rows[0]["job"]["check"])
		lines.append("| %s (`%s`, %s t) | %s | %s | %s |" % [group, rows[0]["variant"],
				_span(masses, "%.1f"), " / ".join(cells) if rows.size() > 1 and rows.size() <= 4
				else _span(ratios),
				"-" if powers.is_empty() else _span(powers), "%d of %d (%s)" % [ok, n,
				check_verdict(rows[0])["tol"]] if same else " / ".join(results)])
	return lines


# ----------------------------------------------------------------- level mode

## What a shipped level's roads actually ask for: grade and painted surface along every road
## curve. Instantiated, never treed — the road nodes join their group in `_init`, which is what
## makes the walk work here (src/levels/base/carlito_groups.gd).
func _report_level(id: String) -> void:
	var path := id if id.contains("/") else "res://src/levels/island/%s/%s.tscn" % [id, id]
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("cannot load level '%s'" % path)
		return
	var root := packed.instantiate()
	add_child(root)  ## terrains decode their splatmaps in _ready
	var roads: Array[Node] = []
	var terrains: Array[Node] = []
	_collect(root, roads, terrains)
	print("=== %s: %d road path(s), %d painted terrain(s) ===" % [path, roads.size(),
			terrains.size()])
	for road in roads:
		_report_road(road, terrains)
	root.queue_free()


func _collect(node: Node, roads: Array[Node], terrains: Array[Node]) -> void:
	if node.is_in_group(Groups.ROAD):
		roads.append(node)
	if node.has_method("grip_at") and node.has_method("contains_xz") \
			and node.has_method("height_at"):
		terrains.append(node)
	for child in node.get_children():
		_collect(child, roads, terrains)


func _report_road(road: Node, terrains: Array[Node]) -> void:
	var path3d: Path3D = null
	for child in road.get_children():
		if child is Path3D:
			path3d = child
	if path3d == null or path3d.curve == null or path3d.curve.point_count < 2:
		print("  %s: no usable curve" % road.name)
		return
	var curve := path3d.curve
	var to_world := (road as Node3D).global_transform * path3d.transform
	var length := curve.get_baked_length()
	var worst := 0.0
	var worst_at := 0.0
	var sum := 0.0
	var samples := 0
	var over_10 := 0.0  ## metres of road steeper than each band
	var over_15 := 0.0
	var over_25 := 0.0
	var grip_sum := 0.0
	var drag_sum := 0.0
	var prev := to_world * curve.sample_baked(0.0)
	var heights := PackedFloat32Array([prev.y])  ## every LEVEL_STEP: the descents below
	var d := LEVEL_STEP
	while d <= length:
		var p := to_world * curve.sample_baked(d)
		heights.append(p.y)
		var run := Vector2(p.x - prev.x, p.z - prev.z).length()
		if run > 0.001:
			var grade := absf(p.y - prev.y) / run
			sum += grade
			samples += 1
			if grade > worst:
				worst = grade
				worst_at = d
			if grade > 0.10:
				over_10 += LEVEL_STEP
			if grade > 0.15:
				over_15 += LEVEL_STEP
			if grade > 0.25:
				over_25 += LEVEL_STEP
		var terrain := RayWheel.terrain_at(p, terrains)
		if terrain != null:
			grip_sum += terrain.grip_at(p, PackedFloat32Array())
			drag_sum += terrain.drag_at(p)
		prev = p
		d += LEVEL_STEP
	if samples == 0:
		return
	print("  %s: %.0f m long" % [road.name, length])
	print("    mean grade %.1f %%, worst %.1f %% (%.1f deg) at %.0f m"
			% [100.0 * sum / samples, 100.0 * worst, rad_to_deg(atan(worst)), worst_at])
	print("    over 10%% : %.0f m     over 15%% : %.0f m     over 25%% : %.0f m"
			% [over_10, over_15, over_25])
	print("    surface under the ribbon: mean grip %.2f, mean added crr %.3f"
			% [grip_sum / samples, drag_sum / samples])
	var lo := heights[0]
	var hi := heights[0]
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var run := longest_descent(heights)
	print("    height range %.0f m; longest unbroken descent (either way) %.0f m down over %.0f m"
			% [hi - lo, run.x, run.y * LEVEL_STEP])


## The deepest unbroken descent along `heights` (one sample a step, driven either way): its drop
## (m) and its length in steps. A sample that does not fall ends it.
static func longest_descent(heights: PackedFloat32Array) -> Vector2:
	var best := Vector2.ZERO
	for dir: int in [1, -1]:
		var drop := 0.0
		var steps := 0
		var i: int = 0 if dir == 1 else heights.size() - 1
		while i + dir >= 0 and i + dir < heights.size():
			var fall := heights[i] - heights[i + dir]
			if fall > 0.0:
				drop += fall
				steps += 1
				if drop > best.x:
					best = Vector2(drop, steps)
			else:
				drop = 0.0
				steps = 0
			i += dir
	return best
