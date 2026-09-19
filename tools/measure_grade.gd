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
## Beside each measurement it prints the two textbook ceilings, so a disagreement points at
## which one bit:
##   traction  tan(a) <= (mu * rear_share - crr) / (1 - mu * h / L)   [driven rear only]
##             tan(a) <= mu - crr                                     [all wheels driven]
##   torque    F_gear1_at_idle >= m*g*(sin a + crr * cos a)
## Both are static, single-body and ignore `load_sensitivity`, so they are a reference, not a
## gate: a coupled rig (the semi tows 24 t the moment it spawns) is outside what they describe
## and says so in the report.
##
## Dev report, always exits 0.
##
##   godot --headless --path . res://tools/measure_grade.tscn -- tractor-kenney
##   godot --headless --path . res://tools/measure_grade.tscn -- suv mud
##   godot --headless --path . res://tools/measure_grade.tscn -- tractor-kenney mud mfwd diff
##   godot --headless --path . res://tools/measure_grade.tscn -- level=level_2

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Layers := preload("res://src/physics/collision_layers.gd")
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

## Slip the `tc` loop holds the driven axle at: the shipped grip curves all peak at 0.12.
const TC_TARGET_SLIP := 0.12
const TC_GAIN := 12.0     ## pedal units per second per unit of slip error

const LEVEL_STEP := 4.0   ## m between road-curve samples in level mode

enum Ph { SETTLE, CLIMB, DONE }


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


var _queue: Array[String] = []        ## variants left to measure
var _surface_list: Array[String] = [] ## surfaces every variant is run over
var _surfaces: Array[String] = []     ## surfaces left for the current variant
var _variant := ""
var _surface := ""
var _verbose := false                 ## print every bisection trial, not just the result
## `tc`: hold the driven slip at the grip curve's peak instead of flooring the pedal, which is
## the difference between what the tyres could do and what a pedal-to-the-floor driver gets.
var _tc := false
var _throttle := 1.0                  ## pedal the TC loop is holding, 0..1
var _pedal := 0.0                     ## `pedal=<0..1>`: hold this throttle instead, diagnostic
var _hold := NAN                      ## `hold=<deg>`: one trial at this angle, diagnostic
var _mfwd := false                    ## tractor MFWD engaged for the run
var _diff := false                    ## tractor rear diff locked for the run

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
	_diff = args.has("diff")
	for i in range(1, args.size()):
		if SURFACES.has(String(args[i])):
			_surface_list.append(String(args[i]))
	if _surface_list.is_empty():
		_surface_list = DEFAULT_SURFACES.duplicate()
	if which == "all":
		_queue.assign(_wheel_driven_variants())
	elif Catalog.VARIANTS.has(which):
		_queue = [which]
	else:
		printerr("unknown variant '%s' — expected 'all' or one of: %s"
				% [which, ", ".join(_wheel_driven_variants())])
		get_tree().quit(1)
		return
	_patch = GripPatch.new()
	_patch.name = "GripPatch"
	add_child(_patch)
	print("=== grade climb: standing start, %.0f s per trial ===" % CLIMB_S)
	print("  surfaces: %s" % ", ".join(_surface_list))
	print("  throttle: %s" % ("slip-limited (tc)" if _tc else "full"))
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
		get_tree().quit(0)
		return
	_variant = _queue.pop_front()
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
	if _ramp == null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		_ramp = StaticBody3D.new()
		_ramp.name = "Ramp"
		# Every gameplay ray masks Layers.SOLID; engine-default would drop the body through.
		_ramp.collision_layer = Layers.TERRAIN
		_ramp.collision_mask = Layers.DYNAMIC
		_ramp.add_child(collision)
		_ramp.add_child(visual)
		add_child(_ramp)
	# Rotated about +X so the ramp's own -Z (the body's forward) climbs; the top face passes
	# through the world origin, which is where the up-slope measurement starts from.
	var tilt := Basis(Vector3.RIGHT, a)
	_ramp.transform = Transform3D(tilt, tilt * Vector3(0.0, -RAMP_THICKNESS * 0.5, 0.0))
	_patch.tan_angle = tan(a)
	_patch.grip = SURFACES[_surface].x
	_patch.drag = SURFACES[_surface].y


func _spawn(angle_deg: float) -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(angle_deg))
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	add_child(_car)
	var surface := tilt * Vector3(0.0, 0.0, -SPAWN_UP)  ## SPAWN_UP up the slope from origin
	_car.global_transform = Transform3D(tilt, surface + tilt.y * _car.rest_ride_height())
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_start = _car.global_position


## Drive through the bridge, not the keyboard: `InputRouter.arbitrate_local` latches reverse on
## a brake held at a standstill, and a standstill brake is exactly the settle phase here.
func _drive(accel_pct: float, brake_pct: float) -> void:
	Bridge.set("_active", true)
	Bridge.set("_inbound", {
		"key": 3, "gear": 1, "accel": accel_pct, "brake": brake_pct,
		"steer": 0.0, "handbrake": 0.0,
		"diff_lock": _diff, "fwd_drive": _mfwd,
	})


func _physics_process(delta: float) -> void:
	if _car == null or _phase == Ph.DONE:
		return
	_t += delta
	if _phase == Ph.SETTLE:
		if _t >= SETTLE_S:
			_phase = Ph.CLIMB
			_t = 0.0
			_throttle = 1.0
			_start = _car.global_position
			_drive(100.0, 0.0)
		return
	if _pedal > 0.0:
		_drive(_pedal * 100.0, 0.0)
	elif _tc:
		# Wheelspin is self-defeating here twice over: the grip curve falls away past its peak
		# AND gear 1 drags the engine into the rev limiter, so a floored pedal measures the
		# driver, not the tyre. Hold the slip at the peak and the measurement is the tyre's.
		_throttle = clampf(_throttle + (TC_TARGET_SLIP - _car.telemetry.slip_rear) * TC_GAIN * delta,
				0.0, 1.0)
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
	_rows.append({
		"variant": _variant,
		"surface": _surface,
		"measured": _best,
		"traction": _traction_limit_deg(spec, gd, s.x, s.y),
		"torque": _torque_limit_deg(spec, gd, s.y),
		"coupled": _coupled_mass(),
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
	if gd.driven_front and gd.driven_rear:
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
	var contact_y := gd.wheel_positions[0].y - gd.rest_length * 0.5 - gd.wheel_radius
	var h := maxf(spec.center_of_mass.y - contact_y, 0.05)
	var transfer := mu * h / wheelbase
	if gd.driven_front and not gd.driven_rear:
		transfer = -transfer  ## uphill transfer UNLOADS a driven front axle
	var num := mu * share_rear - crr
	var den := 1.0 - transfer
	if num <= 0.0 or den <= 0.0:
		return 0.0 if num <= 0.0 else 90.0
	return rad_to_deg(atan(num / den))


## Steepest grade first gear at idle rpm can push the body's own weight up, in degrees. No
## clutch or converter is modelled, so idle torque IS what pulls away (semi_spec.tres § the
## drivetrain block).
func _torque_limit_deg(spec: VehicleSpec, gd: GroundDriveSpec, crr: float) -> float:
	if spec.gear_ratios.is_empty():
		return NAN
	var force := Drivetrain.wheel_torque(spec, spec.idle_rpm, 1.0, 1) / gd.wheel_radius
	var ratio := force / (spec.mass * 9.81)
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
	var fifth: Variant = _car.get("_fifth_wheel")
	if fifth == null:
		return 0.0
	var trailer: Variant = fifth.get("trailer")
	if trailer == null or not is_instance_valid(trailer):
		return 0.0
	return float(trailer.mass)


func _print_table() -> void:
	print("\n%-16s %-8s %8s %8s %10s %10s  %s"
			% ["variant", "surface", "measured", "grade", "traction", "torque", "note"])
	for r in _rows:
		var m: float = r["measured"]
		var note := ""
		if r["coupled"] > 0.0:
			note = "coupled +%.0f kg — predictions are tractor-only" % r["coupled"]
		print("%-16s %-8s %7.1f%s %7.0f%% %9.1f%s %9.1f%s  %s" % [
			r["variant"], r["surface"],
			0.0 if is_nan(m) else m, " d",
			0.0 if is_nan(m) else 100.0 * tan(deg_to_rad(m)),
			r["traction"], " d", r["torque"], " d", note])


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
