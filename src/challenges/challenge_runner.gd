class_name ChallengeRunner
extends Node
## Runs one ChallengeDef on the loaded level. The shell adds it under the level root for an attempt
## (`boot.gd _begin_challenge`), so it is freed with the level. It instances the def's course as a
## runtime overlay beside the level's own content, spawns a fresh body at the course's marker with
## the def's attachment, lays the def's visibility over the level's lighting, and each physics tick
## builds a ChallengeFrame and steps a ChallengeAttempt. `end()` takes all of it off again.
##
## What comes back is acted on here:
## - RESET (a fail zone): the constraint's warning as a notice, then a respawn.
## - PASS / FAIL: `finished`. The attempt keeps its result and the body stays drivable.
## - Any respawn, whatever caused it (R, a fall, a RESET), starts the attempt over from the next
##   tick, and the start pose for the respawn after it is rolled then.
##
## Every START is a fresh body (`start`, and `restart` for a retry), so the TowHost spawn countdown
## lays exactly the def's attachment at the course pose and every attempt begins with the same aux
## state (fuel, air, battery). A respawn within an attempt is the vehicle's own `respawn()`.

signal finished(passed: bool, elapsed_s: float, message: String)

const Groups := preload("res://src/levels/base/carlito_groups.gd")
## After every vehicle's `_physics_process` (priority 0), so a frame reads the telemetry this tick
## published, against the pose it was computed from.
const PHYSICS_PRIORITY := 100

var def: ChallengeDef
var attempt: ChallengeAttempt  ## null until the first start

var _level: Level
var _course: Node3D
var _spawn: VehicleSpawn               ## the course's marker; the jitter moves it
var _spawn_base := Transform3D.IDENTITY  ## its authored pose, which every jitter is rolled from
var _zones: Dictionary[StringName, ZoneShape] = {}
var _rng := RandomNumberGenerator.new()
var _prev_origin := Vector3.INF
var _respawned := false                ## see _on_respawned
var _vehicle: BaseVehicle              ## the body this runner spawned, whose respawns it hears
var _lighting := {}                    ## the ChallengeVisibility snapshot end() restores
var _ended := false


## Before `add_child`. A negative seed takes a random one; a test passes its own.
func setup(p_def: ChallengeDef, rng_seed := -1) -> void:
	def = p_def
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	_level = get_parent() as Level
	if _level == null or def == null:
		push_error("ChallengeRunner: needs setup(def) and a Level parent")
		set_physics_process(false)
		return
	start()


func _exit_tree() -> void:
	# The level may be leaving with this node inside it, when nothing may be unparented.
	end(false)


## Start an attempt from scratch: a fresh body at a newly jittered start, carrying the def's
## attachment. A broken def fails on the spot.
func start() -> void:
	if _ended:
		return
	if _course == null:
		_build_course()
	if _spawn == null:
		return
	_place_spawn()
	var before := _level.vehicle
	_level.set_vehicle(def.variant, _spawn)
	if _level.vehicle == null or _level.vehicle == before:
		push_error("ChallengeRunner: %s: '%s' did not spawn on this level" % [def.id, def.variant])
		return
	_vehicle = _level.vehicle
	_vehicle.respawned.connect(_on_respawned)
	_apply_attachment()
	_roll_next_start()
	attempt = ChallengeAttempt.new(def, _zones)
	_prev_origin = Vector3.INF
	_respawned = false
	if attempt.status != ChallengeCheck.Status.RUNNING:
		push_error("ChallengeRunner: %s: %s" % [def.id, attempt.message])
		finished.emit(false, 0.0, attempt.message)


## A retry: the same as the first start.
func restart() -> void:
	start()


## Take the attempt off the level: the lighting back, the course gone, and the body's respawn
## pointed at the level's own spawn again. The body stays where it is. Safe to call twice.
func end(unparent := true) -> void:
	if _ended:
		return
	_ended = true
	set_physics_process(false)
	if _level == null:
		return
	ChallengeVisibility.restore(_level.environment(), _level.sun_light(), _lighting)
	_lighting = {}
	if is_instance_valid(_course):
		# Out of the tree now, not at the end of the frame: no zone or marker outlives the attempt.
		if unparent and _course.get_parent() != null:
			_course.get_parent().remove_child(_course)
		_course.queue_free()
	_course = null
	_spawn = null
	if is_instance_valid(_vehicle):
		if _vehicle.respawned.is_connected(_on_respawned):
			_vehicle.respawned.disconnect(_on_respawned)
		var home := _level.pick_spawn(def.family())
		if home != null:
			_vehicle.spawn_transform = home.global_transform


func _physics_process(delta: float) -> void:
	tick(delta)


## One physics tick of the attempt; `_physics_process` calls it, and so do the tests.
func tick(delta: float) -> void:
	if attempt == null or _ended or not is_instance_valid(_vehicle):
		return
	if _respawned:
		_respawned = false
		attempt.reset()
		_prev_origin = Vector3.INF
		_apply_attachment()
		_roll_next_start()
	if attempt.status != ChallengeCheck.Status.RUNNING:
		return
	var frame := build_frame(_vehicle, _level, _prev_origin)
	_prev_origin = frame.pose.origin
	match attempt.step(frame, delta):
		ChallengeCheck.Status.RESET:
			GameState.notice.emit(attempt.message.to_upper(), 0.0)
			_vehicle.respawn()
		ChallengeCheck.Status.PASS:
			finished.emit(true, attempt.elapsed, "")
		ChallengeCheck.Status.FAIL:
			finished.emit(false, attempt.elapsed, attempt.message)


## Instance the course under the level root, find its marker and zones, and lay the visibility.
## Leaves `_spawn` null when the course cannot host the def (registry validation keeps a shipped
## def from getting here).
func _build_course() -> void:
	var packed := load(def.course) as PackedScene
	var node: Node = packed.instantiate() if packed != null else null
	if not node is Node3D:
		if node != null:
			node.free()
		push_error("ChallengeRunner: course '%s' is not a scene with a Node3D root" % def.course)
		return
	_course = node as Node3D
	_level.add_child(_course)
	var family := def.family()
	for n in _course.find_children("*", "VehicleSpawn", true, false):
		if (n as VehicleSpawn).accepts(family):
			_spawn = n as VehicleSpawn
			break
	if _spawn == null:
		push_error("ChallengeRunner: course '%s' has no spawn for the %s family" % [def.course, family])
		return
	_spawn_base = _spawn.transform
	# The course's parent is the level root, which sits at the world origin: these are world space.
	_zones = ChallengeZone.zones_of(_course)
	_lighting = ChallengeVisibility.apply(_level.environment(), _level.sun_light(),
			def.visibility, def.fog_density)


func _place_spawn() -> void:
	_spawn.transform = jittered(_spawn_base, def.spawn_jitter_m, def.spawn_jitter_deg, _rng)


## Roll where the next attempt starts, which is where the next respawn lands.
func _roll_next_start() -> void:
	_place_spawn()
	_vehicle.spawn_transform = _spawn.global_transform


## The def's attachment, whatever E did to it during the last attempt. Duck-typed like every other
## attachment hook: a body with no catalog has nothing to set.
func _apply_attachment() -> void:
	if not _vehicle.has_method(&"set_attachment"):
		return
	if String(_vehicle.call(&"current_attachment")) != def.attachment:
		_vehicle.call(&"set_attachment", def.attachment)


## Only flags it. BaseVehicle emits `respawned` partway through a respawn, and the semi and the
## tractor go on to read `spawn_transform` to re-lay their trailer; rolling the next start here
## would lay the trailer there while the chassis stands at this one. The next tick handles it.
func _on_respawned() -> void:
	_respawned = true


## One tick of `vehicle` as a challenge sees it.
static func build_frame(vehicle: BaseVehicle, level: Node, prev_origin: Vector3) -> ChallengeFrame:
	var f := ChallengeFrame.new()
	f.signals = vehicle.telemetry.to_bridge_dict()
	f.input = InputRouter.get_vehicle_input()
	f.pose = vehicle.global_transform
	f.velocity = vehicle.linear_velocity
	f.prev_origin = prev_origin
	var wheels := rig_wheels(vehicle)
	f.wheel_count = wheels.size()
	for w in wheels:
		if w.in_contact:
			f.wheel_contacts.append(w.contact_point)
	f.payloads = free_payloads(level)
	return f


## Every wheel of the RIG: the body's own, plus those of whatever a TowHost on it has coupled, so a
## coupled trailer has to stop in the box too.
static func rig_wheels(vehicle: BaseVehicle) -> Array[RayWheel]:
	var out: Array[RayWheel] = []
	out.append_array(vehicle.wheels)
	for node in vehicle.find_children("*", "TowHost", true, false):
		var host := node as TowHost
		if host.is_coupled():
			out.append_array(host.trailer.wheels)
	return out


## World positions of the payloads under `level` that are not on a hook. A group lookup, correct
## here because this only ever runs in the game's one live level.
static func free_payloads(level: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node in level.get_tree().get_nodes_in_group(Groups.PAYLOAD):
		var payload := node as CargoPayload
		if payload != null and not payload.carried and level.is_ancestor_of(payload):
			out.append(payload.global_position)
	return out


## `base` moved to a uniformly random point within `radius_m` in its own XZ plane and turned up to
## `yaw_deg` either way about its own up axis. Always draws three numbers, so a seed replays.
static func jittered(base: Transform3D, radius_m: float, yaw_deg: float,
		rng: RandomNumberGenerator) -> Transform3D:
	var r := radius_m * sqrt(rng.randf())
	var a := rng.randf() * TAU
	var yaw := deg_to_rad(rng.randf_range(-yaw_deg, yaw_deg))
	var b := base.basis.orthonormalized()
	var offset := b * Vector3(r * cos(a), 0.0, r * sin(a))
	return Transform3D(b * Basis(Vector3.UP, yaw), base.origin + offset)
