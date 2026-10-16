extends Node3D
## Two grade questions in one dev tool, because they only mean something against each other:
## what grade a vehicle can still pull away on (`ramp` mode), and what grade a shipped level
## actually asks for (`level=` mode). Game-mode tool scene (needs autoloads + a physics step).
##
## RAMP MODE bisects the steepest angle the body climbs FROM REST — no run-up, which is the
## honest "can it get up there" question and the one a driver asks halfway up. Each trial is a
## fresh body on a fresh ramp over a synthetic grip patch (`GripPatch` below answers the same
## `grip_at`/`drag_at`/`contains_xz`/`height_at` contract `HeightmapTerrain` does, so
## `BaseVehicle._find_grip_terrains` picks it up as a sibling of the vehicle's parent).
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

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Groups := preload("res://src/levels/base/carlito_groups.gd")

## Named surfaces, (grip, added crr) — the shipped island channel tables
## (`HeightmapTerrain.channel_grip` / `channel_drag`, level 1's row).
const SURFACES := {
	"asphalt": Vector2(1.0, 0.0),
	"gravel": Vector2(0.85, 0.02),
	"grass": Vector2(0.8, 0.06),
	"dirt": Vector2(0.7, 0.03),
	"field": Vector2(0.7, 0.08),
	"mud": Vector2(0.5, 0.2),
}
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
const TC_GAIN := 12.0     ## pedal units per second per unit of slip error
## Front-axle spring load, as a share of its settled load, below which the `tc` driver lifts off.
const TC_FRONT_KEEP := 0.3
const TC_LIFT_GAIN := 2.0 ## pedal units per second per unit of that share short

const LEVEL_STEP := 4.0   ## m between road-curve samples in level mode

## `doc=grade` (arg 1): this set over asphalt and mud, then the `grade` region of
## `docs/vehicles.md` is rewritten (`doc_region.gd`). The flags are per job here, not per run.
const DocRegion := preload("res://tools/doc_region.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")
const MeasureVehicles := preload("res://tools/measure_vehicles.gd")
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
	{"variant": "semi", "mfwd": false, "diff": false, "tc": false},
]

## PARK MODE (`park=<deg>`, flags `hand` / `pawl` / `cross`): the body held on the ramp by its foot
## brake (or handbrake, `hand`, or P alone, `pawl`: no brake, a body with no pawl parks in N), nose
## up the slope (or across it, `cross`), for PARK_HOLD_S after the settle. Reports how far it
## moved: a tyre that holds statically moves nothing. Asphalt only, the hill hold off (`_nohold`):
## the table is the brake hardware's.
const PARK_HOLD_S := 60.0
## `doc=park` (arg 1): this set, then the `park` region of `docs/vehicles.md` is rewritten.
const DOC_PARK_VARIANTS: Array[String] = ["sedan", "suv", "pickup", "garbage-truck",
		"tractor-kenney", "semi"]
const DOC_PARK_ANGLES: Array[float] = [5.7, 16.7]  ## 10 % and 30 %
const DOC_PARK_MODES: Array[String] = ["foot", "hand", "pawl", "cross"]
## ...plus one handbrake hold per variant on its regulation grade (`BrakeSizing.regulation_grade`:
## 20 % to 3.5 t, 18 % above, the rig's mass for a coupled semi).

enum Ph { SETTLE, CLIMB, PARK_SETTLE, PARK_HOLD, CREEP_SETTLE, CREEP, ROLL_SETTLE, ROLL, ASCENT_SETTLE,
		ASCENT, DONE }


## Synthetic painted surface for the ramp: one grip/drag pair everywhere, and a `height_at`
## that reports the inclined plane so `RayWheel.terrain_at`'s 1 m reach finds it at any point
## of the climb. Same duck-typed contract as HeightmapTerrain, nothing more.
class GripPatch:
	extends Node3D

	var grip := 1.0
	var drag := 0.0
	var tan_angle := 0.0  ## ramp slope; surface height is -z * tan(angle)

	func contains_xz(_world_pos: Vector3) -> bool:
		return true

	func height_at(world_pos: Vector3) -> float:
		return -world_pos.z * tan_angle

	func grip_at(_world_pos: Vector3) -> float:
		return grip

	func drag_at(_world_pos: Vector3) -> float:
		return drag


var _queue: Array[Dictionary] = []    ## jobs left to measure: variant + mfwd / diff / tc
var _surface_list: Array[String] = [] ## surfaces every variant is run over
var _surfaces: Array[String] = []     ## surfaces left for the current variant
var _variant := ""
var _surface := ""
var _verbose := false                 ## print every bisection trial, not just the result
## `tc`: hold the driven slip at the tyre's best (TC_TARGET_SLIP) instead of flooring the pedal, which is
## the difference between what the tyres could do and what a pedal-to-the-floor driver gets.
var _tc := false
var _throttle := 1.0                  ## pedal the TC loop is holding, 0..1
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
## climb mode: the shifts so far, each {t, kmh, from, to, before, landing, load}; the byte engaged
## last tick; the run's grade, %
var _ascent_shifts: Array[Dictionary] = []
var _ascent_byte := 0
var _ascent_grade := 0.0
var _ascent_room := 0.0  ## m of ramp from the start to ASCENT_MARGIN short of its top
## `gear=<1-6>`: climbs and roll-backs in the bridge's manual mode, held in that byte (0: automatic
## D). A start gear the automatic box would leave at once (it downshifts at a standstill), held.
var _held_gear := 0

var _ramp: StaticBody3D
var _patch: GripPatch
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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a).begins_with("level="):
			_report_level(String(a).substr(6))
			get_tree().quit(0)
			return
	var which := String(args[0]) if args.size() > 0 else "suv"
	_mfwd = args.has("mfwd")
	_verbose = args.has("verbose")
	_tc = args.has("tc")
	for a in args:
		if String(a).begins_with("pedal="):
			_pedal = String(a).substr(6).to_float()
		if String(a).begins_with("hold="):
			_hold = String(a).substr(5).to_float()
		if String(a).begins_with("cornering_peak="):
			_cornering_peak = String(a).substr(15).to_float()
		if String(a).begins_with("gear="):
			_held_gear = String(a).substr(5).to_int()
			if _held_gear < 1 or _held_gear > Drivetrain.TOP_GEAR:
				printerr("gear=%s: expected a drive byte 1-%d" % [String(a).substr(5),
						Drivetrain.TOP_GEAR])
				get_tree().quit(1)
				return
	if which.begins_with("doc=") and not is_nan(_cornering_peak):
		printerr("cornering_peak= changes the figures a doc preset tabulates: run it per body")
		get_tree().quit(1)
		return
	InputRouter.set_manual_gearbox(_held_gear > 0)
	_diff = args.has("diff")
	for i in range(1, args.size()):
		if SURFACES.has(String(args[i])):
			_surface_list.append(String(args[i]))
	if _surface_list.is_empty():
		_surface_list = DEFAULT_SURFACES.duplicate()
	_patch = GripPatch.new()
	_patch.name = "GripPatch"
	add_child(_patch)
	var park := NAN
	for a in args:
		if String(a).begins_with("park="):
			park = String(a).substr(5).to_float()
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
	if which == "doc=park" or not is_nan(park):
		_nohold = true  ## the brake hardware alone: the tractor's hill hold would join its handbrake
		_start_park(which, park, "cross" if args.has("cross") else (
				"hand" if args.has("hand") else ("pawl" if args.has("pawl") else "foot")))
		return
	if which == "doc=grade":
		_doc = true
		_queue = DOC_JOBS.duplicate(true)
		_surface_list = DOC_SURFACES.duplicate()
	elif which == "all":
		for v in _wheel_driven_variants():
			_queue.append({"variant": v, "mfwd": _mfwd, "diff": _diff, "tc": _tc})
	elif Catalog.VARIANTS.has(which):
		_queue = [{"variant": which, "mfwd": _mfwd, "diff": _diff, "tc": _tc}]
	else:
		printerr("unknown variant '%s' — expected 'all' or one of: %s"
				% [which, ", ".join(_wheel_driven_variants())])
		get_tree().quit(1)
		return
	print("=== grade climb: standing start, %.0f s per trial ===" % CLIMB_S)
	print("  surfaces: %s" % ", ".join(_surface_list))
	print("  throttle: %s" % ("slip-limited (tc)" if _tc else "full"))
	if _held_gear > 0:
		print("  gear: manual, held in D%d (gear=%d)" % [_held_gear, _held_gear])
	if _mfwd or _diff:
		print("  tractor toggles: %s%s" % ["MFWD " if _mfwd else "", "diff-lock" if _diff else ""])
	_next_variant()


## Every catalog variant with a driven axle, same filter measure_vehicles.gd uses.
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
	_patch.grip = SURFACES[_surface].x
	_patch.drag = SURFACES[_surface].y


## `yaw` turns the body about the ramp's normal: PI / 2 parks it across the slope.
func _spawn(angle_deg: float, yaw := 0.0, up := SPAWN_UP) -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(angle_deg))
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	if _nohold:
		# On a copy, in memory, never shipped: the ground drive is a sub-resource the copy shares.
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.hill_hold = HillHold.Kind.NONE
	if not is_nan(_cornering_peak):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.cornering_peak_load = _cornering_peak
	add_child(_car)
	if _tipper and _car.has_method(&"set_attachment"):
		# Remembered until the drawbar's spawn countdown has run, then coupled (TowHost).
		_car.call(&"set_attachment", ImplementCatalog.TOWED[0])
	var surface := tilt * Vector3(0.0, 0.0, -up)  ## `up` metres up the slope from origin
	_car.global_transform = Transform3D(tilt * Basis(Vector3.UP, yaw),
			surface + tilt.y * _car.rest_ride_height())
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_start = _car.global_position


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
	if _phase == Ph.SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.CLIMB
			_t = 0.0
			_throttle = 1.0
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
		var slip_rate := (TC_TARGET_SLIP - _car.telemetry.slip_rear) * TC_GAIN
		# Most force is not most climb: every newton past the weight accelerates the body and
		# unloads the front axle by `m * a * h / L`, which flips a high-COM tractor backwards
		# below its static tip angle. The driver also feathers as the front goes light, on the
		# same integrator: a hard pedal cap would porpoise (lift, cut, land, repeat).
		var front_left := _front_load() / _front_settle if _front_settle > 0.0 else 1.0
		var lift_rate := (front_left - TC_FRONT_KEEP) * TC_LIFT_GAIN
		_throttle = clampf(_throttle + minf(slip_rate, lift_rate) * delta, 0.0, 1.0)
		_drive(_throttle * 100.0, 0.0)
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
					% [_t, _gain, _car.telemetry.speed, _car.telemetry.slip_rear, f_long,
					_car.telemetry.rpm]
					+ "  gear %d  thr %.2f" % [_car.telemetry.gear_byte,
					_car.drivetrain.applied_throttle])
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
				+ " weight-along-slope %8.0f N" % (_car.mass * 9.81 * sin(deg_to_rad(_angle))))
		print("    %5.2f deg: %-7s gain %6.2f m, speed %5.2f m/s, rear slip %.2f, gear %d"
				% [_angle, "CLIMB" if climbed else "fail", _gain, _car.telemetry.speed,
				_car.telemetry.slip_rear, _car.telemetry.gear_byte])
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
	var s: Vector2 = SURFACES[_surface]
	var coupled := _coupled_mass()
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
	print("  %-16s %-8s measured %5.1f deg (%5.1f %%)" % [_variant, _surface,
			_best if not is_nan(_best) else 0.0,
			100.0 * tan(deg_to_rad(_best)) if not is_nan(_best) else 0.0])


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
	return driven_load / ((_car.mass + _coupled_mass()) * 9.81 * cos(deg_to_rad(_angle)))


## Spring load on the front axle right now, N.
func _front_load() -> float:
	var front := 0.0
	for w in _car.drive.wheels:
		if not w.is_rear:
			front += w.suspension_force
	return front


## Steepest grade first gear at full throttle can push `mass` (kg, the whole rig) up from rest, in
## degrees. Sampled where a held body's crank sits, through a converter's stall torque ratio
## (`Drivetrain.stall_axle_torque`).
func _torque_limit_deg(spec: VehicleSpec, gd: GroundDriveSpec, crr: float, mass: float) -> float:
	if spec.gear_ratios.is_empty():
		return NAN
	var force := Drivetrain.stall_axle_torque(spec) / gd.drive_radius()
	var ratio := force / (mass * 9.81)
	if ratio <= crr:
		return 0.0
	# sin a + crr cos a = ratio  ->  sin(a + atan(crr)) = ratio / sqrt(1 + crr^2)
	var s := ratio / sqrt(1.0 + crr * crr)
	if s >= 1.0:
		return 90.0
	return rad_to_deg(asin(s) - atan(crr))


## Total towed mass hanging off the body right now (kg), 0 when nothing is coupled. The semi
## couples a 24 t box the moment it spawns, which is exactly the case the single-body
## predictions above do not describe.
func _coupled_mass() -> float:
	var host: Variant = _car.get("_fifth_wheel")
	if host == null:
		host = _car.get("_drawbar")
	if host == null:
		return 0.0
	return float(host.call(&"towed_mass_kg"))


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
	var layout := "AWD" if gd.driven_front and gd.driven_rear else ("FWD" if gd.driven_front else "RWD")
	if gd.front_axle_engageable:
		layout = "MFWD" if _mfwd else "2WD"
	if _mfwd or not gd.front_axle_engageable:  ## a disengaged front axle leaves no centre to declare
		layout += MeasureVehicles._diff_label(gd)
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
				return "%s (grip %.1f, crr %.2f)" % [s, SURFACES[s].x, SURFACES[s].y])),
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
	print("  %-16s %4.1f %% %-5s along %+9.1f mm  across %+9.1f mm  peak %6.3f m/s%s" % [
		_variant, 100.0 * tan(deg_to_rad(_angle)), _park_mode,
		1000.0 * float(row["along"]), 1000.0 * float(row["across"]), _park_peak,
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
	for v in (_wheel_driven_variants() if which == "all" else [which]):
		if not Catalog.VARIANTS.has(v):
			printerr("unknown variant '%s'" % v)
			get_tree().quit(1)
			return
		var body: Node = (load(Catalog.VARIANTS[v]["scene"]) as PackedScene).instantiate()
		var spec := body.get("spec") as VehicleSpec
		if spec.coupling == VehicleSpec.Coupling.CONVERTER:
			_creep_queue.append(v)
		elif which != "all":
			print("%s has no converter (a clutch opens at a stop): nothing creeps" % v)
		body.free()
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
					VehicleTelemetry.engine_load_pct(dt.rpm, dt.applied_throttle, _car.spec, false,
					0.0))
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
	var grades := ROLL_GRADES.duplicate()
	_roll_delay = ROLL_DELAY_S
	_surface = "asphalt"
	for a in args:
		if String(a).begins_with("grade="):
			grades = [String(a).substr(6).to_float()]
		elif String(a).begins_with("delay="):
			_roll_delay = String(a).substr(6).to_float()
		elif SURFACES.has(String(a)):
			_surface = String(a)
	for v in (_wheel_driven_variants() if which == "all" else [which]):
		if not Catalog.VARIANTS.has(v):
			printerr("unknown variant '%s'" % v)
			get_tree().quit(1)
			return
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
			"held": _roll_held, "towed": _coupled_mass()}
	_roll_rows.append(row)
	print("  %-16s %4.1f %%  rolled back %7.1f mm  forward %s  held %.2f s%s" % [_variant,
			_roll_grade, 1000.0 * float(row["back"]),
			"never" if is_nan(_roll_go) else "at %.2f s" % _roll_go, _roll_held,
			"  (+%.0f kg towed)" % row["towed"] if float(row["towed"]) > 0.0 else ""])
	_phase = Ph.DONE
	_next_roll()


## `verbose` roll-back line, every 0.5 s: the tractor unit's tyre force and slip per axle, and with a
## trailer its tyres' force, its brake and the drawbar's pull, read off the trailer's own balance
## (`m a + m g sin - sum Fx` along the slope; its rolling resistance is a body force, so it lands in
## the pull). Names what bounds a slow pull-away: traction, the drawbar, or the trailer.
func _print_roll_forces(gain: float) -> void:
	var fx := {true: 0.0, false: 0.0}
	var slip := {true: 0.0, false: 0.0}
	var n := {true: 0, false: 0}
	for w: RayWheel in _car.drive.wheels:
		if w.in_contact:
			fx[w.is_rear] += w.force_long
			slip[w.is_rear] += w.long_slip
			n[w.is_rear] += 1
	var line := "    t %5.2f  %+7.3f m  %5.2f km/h  rpm %4.0f c %d  Fx front %6.0f rear %6.0f N  slip %+.2f / %+.2f" \
			% [_t, gain, _car.telemetry.speed * 3.6, _car.drivetrain.rpm, _car.drivetrain.coupling_state,
			fx[false], fx[true], slip[false] / maxi(n[false], 1), slip[true] / maxi(n[true], 1)]
	var host: Variant = _car.get("_drawbar")
	if host == null:
		host = _car.get("_fifth_wheel")
	var trailer: TowedBody = host.get("trailer") if host != null else null
	if trailer != null:
		var t_fx := 0.0
		for w: RayWheel in trailer.wheels:
			if w.in_contact:
				t_fx += w.force_long
		var g_pull := trailer.mass * 9.81 * sin(deg_to_rad(_angle))
		line += "  | trailer Fx %6.0f N brake %.2f  drawbar %6.0f N (grade %6.0f)" % [t_fx,
				trailer.brake_applied(), trailer.mass * trailer.accel_fwd + g_pull - t_fx, g_pull]
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
	_ascent_grade = ASCENT_GRADE
	_surface = "asphalt"
	for a in args:
		if String(a).begins_with("grade="):
			_ascent_grade = String(a).substr(6).to_float()
		elif SURFACES.has(String(a)):
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
	var road_omega := _car.telemetry.speed / dt.road_radius
	if dt.gear_byte != _ascent_byte and Drivetrain.is_drive(_ascent_byte) \
			and Drivetrain.is_drive(dt.gear_byte):
		_ascent_shifts.append({"t": _t, "kmh": _car.telemetry.speed * 3.6, "from": _ascent_byte,
				"to": dt.gear_byte,
				"before": Drivetrain.rpm_from_wheel(dt.spec, road_omega, _ascent_byte),
				"landing": Drivetrain.rpm_from_wheel(dt.spec, road_omega, dt.gear_byte),
				"load": _ascent_load()})
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
	var lines: Array[String] = []
	for s in _ascent_shifts:
		lines.append("D%d>D%d %.2f s %.1f km/h %.0f>%.0f rpm%s" % [s["from"], s["to"], s["t"],
				s["kmh"], s["before"], s["landing"],
				"" if is_nan(float(s["load"])) else " load %.0f" % s["load"]])
	print("  each shift    : %s" % (", ".join(lines) if not lines.is_empty() else "none"))
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
	var d := LEVEL_STEP
	while d <= length:
		var p := to_world * curve.sample_baked(d)
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
			grip_sum += terrain.grip_at(p)
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
