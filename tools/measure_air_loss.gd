extends Node3D
## Dev utility and CI gate: a live truck losing its air. Below `TruckTelemetry.AIR_SPRING_BRAKE_BAR`
## on either circuit the spring brakes apply and the box drops to N (`docs/truck.md` § Air, retarder, axle load);
## this drives a real body through it, three passes per variant:
##
## - `park`: on the regulation grade (`BrakeSizing.regulation_grade`, the rig's mass), nose up the
##   slope, key off, the brake pumped until the reservoirs are empty, then every pedal and the lever
##   released. It must stay put.
## - `floor`: drained the same way on the flat, then the key to IGNITION and the throttle floored in
##   D while the compressor climbs back (about 6 s from empty to the gate). Gear must read N, and it
##   must not move.
## - `roll`: floored in D to 30 km/h, then the air cut with the pedal still down. It must stop with
##   the spring brakes on and gear N from the tick after the gate, at no less than ROLL_MIN_DECEL.
##
## On a semi both `park` and `roll` read the trailer's spring brakes: without them the rig still
## holds on the tractor's rears, but only after settling 23 mm onto them on 18 % (measured
## 2026-10-08, then still for 180 s), and stops from 30 km/h at ~1.4 m/s^2, under the floor.
##
## Draining is honest in `park` / `floor`: the key off stops the compressor (`running`) and each
## press draws (`TruckTelemetry.air_step`). `roll` cannot drain that way without the foot brake doing
## the stopping, and the air model has no leak, so the probe WRITES `air_primary = 0` every tick from
## the cut: a burst primary line. The secondary circuit stays healthy, so the gate's minimum of the
## two circuits is exercised too.
##
## Driven through the bridge (`MeasureRig.drive`), as the other measure tools are. A dev report that
## exits 0, except with `strict`: then any FAIL exits 1 (the CI gate). Every pass prints one
## `PASS` / `FAIL` line and the run ends on an `air loss:` summary line.
##
##   godot --headless --fixed-fps 60 --path . res://tools/measure_air_loss.tscn -- all strict

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")

## `all`: the Kenney truck and both tractor units, each with the trailer it spawns coupled to.
const ALL_VARIANTS: Array[String] = ["garbage-truck", "semi", "semi-conventional"]
const PASSES: Array[String] = ["park", "floor", "roll"]

const RAMP_SIZE := Vector3(30.0, 2.0, 400.0)  ## width, thickness, length
const SPAWN_UP := 60.0          ## m up the ramp from its origin; a coupled trailer stays on it
const FLAT_X := 200.0           ## the flat slab, far enough off the ramp to share no collision
const FLAT_LENGTH := 1000.0
const FLAT_WIDTH := 40.0
const FLAT_START_Z := 400.0

const SETTLE_S := 2.0           ## foot brake held, engine running, while the springs take the weight
const PUMP_HALF_S := 0.25       ## the brake pumped: this long down, this long up
const DRAINED_BAR := 0.5        ## both circuits under this ends the drain
const DRAIN_TIMEOUT_S := 30.0
const PARK_HOLD_S := 30.0
const FLOOR_S := 4.0            ## inside the ~6 s the compressor takes back up to the gate
const ROLL_SPEED_MS := 8.33     ## 30 km/h
const ROLL_SPINUP_TIMEOUT_S := 40.0
const ROLL_STOP_TIMEOUT_S := 30.0
const STOPPED_MS := 0.05
const STOPPED_HOLD_S := 3.0     ## stopped this long, still under the gate, ends the roll pass
## How far a stopped body may move in STOPPED_HOLD_S (m): the springs settling, not a roll-off.
const STOPPED_MAX_M := 0.05
## Movement allowed while held (m). Measured 2026-10-08 (docs/truck.md § Air): 0-2.2 mm
## held, 23 mm on a semi whose trailer is not braked.
const PARK_MAX_M := 0.01
const FLOOR_MAX_M := 0.01
## Mean deceleration (m/s^2) from the cut to the stop: UN R13's secondary-braking floor for goods
## vehicles, which the spring brakes are on a loss of air. Measured 2.8-3.2 on the shipped bodies.
const ROLL_MIN_DECEL := 2.2

enum Ph { SETTLE, DRAIN, HOLD, FLOOR, SPINUP, CUT, DONE }

var _variants: Array[String] = []
var _jobs: Array[Dictionary] = []
var _strict := false
var _results: Array[Dictionary] = []

var _ramp: StaticBody3D
var _car: TruckVehicle
var _variant := ""
var _pass := ""
var _phase: int = Ph.DONE
var _t := 0.0                ## seconds into the current phase
var _ticks := 0              ## ticks since the body was laid
var _start := Vector3.ZERO   ## where the measured phase began
var _fail := ""              ## first broken check of this pass, "" while it holds
var _peak := 0.0             ## fastest the held body moved, m/s
var _peak_throttle := 0.0    ## floor: most fuel the engine was given, or the pass proves nothing
var _gate_tick := -1         ## roll: the tick the gate first read true
var _stopped_t := -1.0       ## roll: phase time it came under STOPPED_MS, -1 while rolling
var _cut_speed := 0.0
var _stop_at := Vector3.ZERO  ## roll: where it first came under STOPPED_MS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_strict = args.has("strict")
	var which := String(args[0]) if args.size() > 0 else "all"
	if which == "all":
		_variants = ALL_VARIANTS.duplicate()
	elif Catalog.VARIANTS.has(which):
		_variants = [which]
	else:
		printerr("unknown variant '%s'" % which)
		get_tree().quit(1)
		return
	for v in _variants:
		for p in PASSES:
			_jobs.append({"variant": v, "pass": p})
	MeasureRig.add_slab(self, "Flat", Vector3(FLAT_WIDTH, 2.0, FLAT_LENGTH), FLAT_X)
	print("=== air loss: spring brakes + auto-neutral on a live truck ===")
	_next_job()


# ------------------------------------------------------------------ jobs

func _next_job() -> void:
	if _jobs.is_empty():
		_finish()
		return
	var job: Dictionary = _jobs.pop_front()
	_variant = String(job["variant"])
	_pass = String(job["pass"])
	_fail = ""
	_peak = 0.0
	_peak_throttle = 0.0
	_gate_tick = -1
	_stopped_t = -1.0
	if _pass == "park":
		var angle := atan(BrakeSizing.regulation_grade(MeasureRig.rig_mass(_variant)))
		_ramp = MeasureRig.tilt_ramp(self, _ramp, RAMP_SIZE, angle)
		var tilt := Basis(Vector3.RIGHT, angle)
		_spawn(func(car: TruckVehicle) -> Transform3D:
			return Transform3D(tilt, tilt * Vector3(0.0, 0.0, -SPAWN_UP)
					+ tilt.y * car.rest_ride_height()))
	else:
		_spawn(func(car: TruckVehicle) -> Transform3D:
			return Transform3D(Basis.IDENTITY,
					Vector3(FLAT_X, car.rest_ride_height(), FLAT_START_Z)))
	_to(Ph.SETTLE)


## A fresh body per pass: removing the unit takes its trailer with it, and a new one starts on spawn
## air with the trailer coupled by the host's countdown during the settle.
func _spawn(pose: Callable) -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate() as TruckVehicle
	add_child(_car)
	_car.global_transform = pose.call(_car)
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_ticks = 0


func _to(phase: int) -> void:
	_phase = phase
	_t = 0.0
	if _car != null:
		_start = _car.global_position


# ------------------------------------------------------------------ the tick

func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	_t += delta
	_ticks += 1
	var t := _car.telemetry as TruckTelemetry
	var gate := TruckTelemetry.spring_brakes_applied(t.air_primary, t.air_secondary)
	var speed := absf(t.speed)
	match _phase:
		Ph.SETTLE:
			MeasureRig.drive(0.0, 100.0)
			if _t >= SETTLE_S and _ticks > TowHost.SPAWN_COUPLE_TICKS:
				_to(Ph.SPINUP if _pass == "roll" else Ph.DRAIN)
		Ph.DRAIN:
			# Key off (no compressor), the brake pumped: down, up, down...
			var down := fmod(_t, 2.0 * PUMP_HALF_S) < PUMP_HALF_S
			MeasureRig.drive(0.0, 100.0 if down else 0.0, 0.0, false, 1, false, InputRouter.KEY_LOCK)
			if not down and maxf(t.air_primary, t.air_secondary) < DRAINED_BAR:
				print("  %-18s %-5s drained in %.1f s (air %.2f / %.2f bar)"
						% [_variant, _pass, _t, t.air_primary, t.air_secondary])
				_to(Ph.HOLD if _pass == "park" else Ph.FLOOR)
			elif _t >= DRAIN_TIMEOUT_S:
				_check(false, "air never drained (%.2f / %.2f bar)" % [t.air_primary, t.air_secondary])
				_end_pass()
		Ph.HOLD:
			MeasureRig.drive(0.0, 0.0, 0.0, false, 1, false, InputRouter.KEY_LOCK)
			_check(gate, "the gate let go while parked")
			_peak = maxf(_peak, _car.linear_velocity.length())
			if _t >= PARK_HOLD_S:
				var moved := _moved()
				_check(moved <= PARK_MAX_M, "moved %.0f mm" % (moved * 1000.0))
				_end_pass("held %.0f s on %.0f %%: moved %.1f mm, peak %.3f m/s" % [PARK_HOLD_S,
						100.0 * tan(_ramp.rotation.x), moved * 1000.0, _peak])
		Ph.FLOOR:
			MeasureRig.drive(100.0, 0.0)
			_check(gate, "the compressor lifted the gate inside the window")
			# The box was already inhibited by the drain; a D request on the key-on tick is N too.
			_check(t.gear_byte == Drivetrain.GEAR_N, "gear read %d floored under the gate" % t.gear_byte)
			_peak = maxf(_peak, _car.linear_velocity.length())
			_peak_throttle = maxf(_peak_throttle, _car.drivetrain.applied_throttle)
			if _t >= FLOOR_S:
				var moved := _moved()
				# Standing still only means something if the engine was fuelled: the pedal reached it.
				_check(_peak_throttle >= 0.9, "the engine was never fuelled (%.2f)" % _peak_throttle)
				_check(moved <= FLOOR_MAX_M, "moved %.0f mm" % (moved * 1000.0))
				_end_pass(("floored %.0f s (fuel %.2f): gear N, moved %.1f mm, peak %.3f m/s,"
						+ " air %.2f / %.2f") % [FLOOR_S, _peak_throttle, moved * 1000.0, _peak,
						t.air_primary, t.air_secondary])
		Ph.SPINUP:
			MeasureRig.drive(100.0, 0.0)
			if speed >= ROLL_SPEED_MS:
				_cut_speed = speed
				_to(Ph.CUT)
			elif _t >= ROLL_SPINUP_TIMEOUT_S:
				_check(false, "never reached %.0f km/h (%.1f)" % [ROLL_SPEED_MS * 3.6, speed * 3.6])
				_end_pass()
		Ph.CUT:
			MeasureRig.drive(100.0, 0.0)
			# The burst line: this node ticks before its child, so the truck's own air step reads it.
			t.air_primary = 0.0
			if gate and _gate_tick < 0:
				_gate_tick = _ticks
			# The gate applies from the NEXT wheel tick (truck.gd), so the tick after it is checked.
			if _gate_tick >= 0 and _ticks > _gate_tick:
				_check(gate, "the gate let go with the line burst")
				_check(_car.drive.spring_brake >= 1.0, "spring brakes off under the gate")
				_check(t.gear_byte == Drivetrain.GEAR_N, "gear read %d: drive into the spring brakes"
						% t.gear_byte)
			if _stopped_t < 0.0 and speed < STOPPED_MS:
				_stopped_t = _t
				_stop_at = _car.global_position
				print("  %-18s %-5s stopped from %.1f km/h in %.2f s over %.1f m"
						% [_variant, _pass, _cut_speed * 3.6, _t, _moved()])
			elif _stopped_t >= 0.0:
				# Judged by where it stands, not the speed signal: the body pitches back on its
				# springs once the wheels stop, which reads as a few cm/s for a moment.
				if _t - _stopped_t >= STOPPED_HOLD_S:
					var crept := (_car.global_position - _stop_at).length()
					var decel := _cut_speed / maxf(_stopped_t, 1e-6)
					_check(decel >= ROLL_MIN_DECEL, "stopped at %.2f m/s^2, under %.1f"
							% [decel, ROLL_MIN_DECEL])
					_check(crept <= STOPPED_MAX_M, "crept %.0f mm after the stop" % (crept * 1000.0))
					_end_pass(("stopped from %.1f km/h in %.2f s over %.1f m (%.2f m/s^2), floored"
							+ " in gear N; %.1f mm in the next %.0f s") % [_cut_speed * 3.6,
							_stopped_t, (_stop_at - _start).length(), decel, crept * 1000.0,
							STOPPED_HOLD_S])
			if _stopped_t < 0.0 and _t >= ROLL_STOP_TIMEOUT_S:
				_check(false, "still at %.1f km/h after %.0f s" % [speed * 3.6, ROLL_STOP_TIMEOUT_S])
				_end_pass()


func _moved() -> float:
	return (_car.global_position - _start).length()


## Keeps the FIRST broken check: later ones usually follow from it.
func _check(ok: bool, why: String) -> void:
	if not ok and _fail == "":
		_fail = why


func _end_pass(what := "") -> void:
	var ok := _fail == ""
	_results.append({"variant": _variant, "pass": _pass, "ok": ok})
	print("  %-18s %-5s %s: %s" % [_variant, _pass, what if ok else _fail, "PASS" if ok else "FAIL"])
	_phase = Ph.DONE
	_next_job()


func _finish() -> void:
	_phase = Ph.DONE
	var failed := 0
	for r in _results:
		if not bool(r["ok"]):
			failed += 1
	print("air loss: %d of %d passes FAIL" % [failed, _results.size()] if failed > 0
			else "air loss: all %d passes PASS" % _results.size())
	get_tree().quit(1 if _strict and failed > 0 else 0)
