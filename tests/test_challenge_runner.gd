extends GdUnitTestSuite
## ChallengeRunner on a real flatland: the course overlay, the fresh body at its marker, the def's
## attachment, what it does with a PASS, a RESET and any respawn, and `end()` taking it all off.
## The course is built in memory and saved under user:// (test_challenge_registry's pattern), and
## the tests call `tick` themselves after posing the body, so no goal waits on the physics engine.

const S := ChallengeCheck.Status
const V := ChallengeDef.Visibility
const DT := 1.0 / 60.0
const COURSE := "user://challenge_runner_course.tscn"
const CRATE := "res://src/levels/base/cargo_payload.tscn"
const BOX_TRAILER := "res://src/vehicles/truck/trailers/box.tscn"
const DAY_ENV := "res://src/levels/base/default_env.tres"

## The course in world space (the level root sits at the origin). The respawn from the pit back to
## the spawn is the only move here that crosses Finish, so only a pre-respawn origin carried into
## the next frame would read that teleport as a path through it.
const SPAWN_AT := Vector3(0, 0.8, 40)
const MARK_AT := Vector3(40, 1, 40)
const PIT_AT := Vector3(40, 1, -40)
const FINISH_AT := Vector3(20, 1, 0)

var _notices := PackedStringArray()
var _results: Array = []


class Rig:
	extends RefCounted

	var level: Level
	var runner: ChallengeRunner
	var first_body: BaseVehicle  ## the one the level spawned for itself, before the attempt


func before() -> void:
	var course := Node3D.new()
	course.name = "Course"
	var spawn := VehicleSpawn.new()
	spawn.name = "Spawn"
	spawn.position = SPAWN_AT
	course.add_child(spawn)
	_add_zone(course, "Finish", FINISH_AT, Vector3(6, 4, 2))
	_add_zone(course, "Mark", MARK_AT, Vector3(4, 4, 4))
	_add_zone(course, "Pit", PIT_AT, Vector3(6, 4, 6))
	for n in course.find_children("*", "", true, false):
		n.owner = course
	var packed := PackedScene.new()
	packed.pack(course)
	ResourceSaver.save(packed, COURSE)
	course.free()


func before_test() -> void:
	_notices = PackedStringArray()
	_results = []
	GameState.notice.connect(_on_notice)


func after_test() -> void:
	GameState.notice.disconnect(_on_notice)


func _on_notice(text: String, _dwell_s: float) -> void:
	_notices.append(text)


func _on_finished(passed: bool, elapsed_s: float, message: String) -> void:
	_results.append([passed, elapsed_s, message])


func _add_zone(course: Node3D, zone_name: String, pos: Vector3, size: Vector3) -> void:
	var z := ChallengeZone.new()
	z.name = zone_name
	z.position = pos
	z.size = size
	course.add_child(z)


func _reach(zone: StringName) -> ReachZoneGoal:
	var g := ReachZoneGoal.new()
	g.zone = zone
	return g


func _fail(zone: StringName, warning: String) -> FailZoneConstraint:
	var c := FailZoneConstraint.new()
	c.zone = zone
	c.warning = warning
	return c


func _def(goals: Array[ChallengeGoal], constraints: Array[ChallengeConstraint] = [],
		variant := "sedan-sports") -> ChallengeDef:
	var d := ChallengeDef.new()
	d.id = "runner_test"
	d.title = "Runner test"
	d.briefing = "Reach the finish."
	d.hint = "speed"
	d.variant = variant
	d.arena = "flatland"
	d.course = COURSE
	d.goals = goals
	d.constraints = constraints
	return d


## Flatland loaded the way the shell loads it, then the runner added under it as the shell does.
func _rig(d: ChallengeDef) -> Rig:
	var r := Rig.new()
	r.level = auto_free((load(LevelRegistry.scene_of("flatland")) as PackedScene).instantiate()) as Level
	add_child(r.level)
	r.first_body = r.level.vehicle
	r.runner = ChallengeRunner.new()
	r.runner.setup(d, 7)
	r.runner.finished.connect(_on_finished)
	r.level.add_child(r.runner)
	return r


func _put(v: BaseVehicle, pos: Vector3) -> void:
	v.global_position = pos
	v.linear_velocity = Vector3.ZERO


# --- the start -----------------------------------------------------------------------------------

func test_start_spawns_a_fresh_body_at_the_jittered_course_marker() -> void:
	var d := _def([_reach(&"Finish")])
	d.spawn_jitter_m = 2.0
	d.spawn_jitter_deg = 10.0
	var r := _rig(d)
	var v := r.level.vehicle
	assert_object(v).is_not_same(r.first_body)
	assert_bool(r.first_body.is_queued_for_deletion()).is_true()
	var off := Vector2(v.global_position.x - SPAWN_AT.x, v.global_position.z - SPAWN_AT.z)
	assert_float(off.length()).is_less_equal(2.0 + 1e-4)
	assert_float(v.global_position.y).is_equal_approx(SPAWN_AT.y, 1e-4)
	assert_str(GameState.current_variant).is_equal("sedan-sports")
	assert_object(r.runner._course.get_parent()).is_same(r.level)
	assert_int(r.runner.attempt.status).is_equal(S.RUNNING)


## Frames read the telemetry the vehicle published this tick, so the runner steps after it.
func test_the_runner_steps_after_every_vehicle() -> void:
	var r := _rig(_def([_reach(&"Finish")]))
	assert_int(r.runner.process_physics_priority) \
			.is_greater(r.level.vehicle.process_physics_priority)


func test_a_broken_def_fails_at_the_start() -> void:
	_rig(_def([_reach(&"Nope")]))
	assert_int(_results.size()).is_equal(1)
	assert_bool(_results[0][0]).is_false()
	assert_str(_results[0][2]).contains("broken")


## The countdown lays whatever id the body remembers, and the runner sets it before the first tick:
## a bobtail def spawns bobtail though the semi's own `_ready` picks the box.
func test_a_bobtail_def_spawns_bobtail() -> void:
	var d := _def([_reach(&"Finish")], [], "semi")
	var r := _rig(d)
	for _i in TowHost.SPAWN_COUPLE_TICKS + 2:
		await get_tree().physics_frame
	var v := r.level.vehicle
	assert_bool((v.get_node("FifthWheel") as TowHost).is_coupled()).is_false()
	assert_int(ChallengeRunner.rig_wheels(v).size()).is_equal(v.wheels.size())


## A coupled trailer's wheels are the rig's: Truck 1's whole rig has to stop in the box.
func test_a_trailer_def_spawns_coupled_and_its_wheels_count() -> void:
	var d := _def([_reach(&"Finish")], [], "semi")
	d.attachment = BOX_TRAILER
	var r := _rig(d)
	for _i in TowHost.SPAWN_COUPLE_TICKS + 2:
		await get_tree().physics_frame
	var v := r.level.vehicle
	var host := v.get_node("FifthWheel") as TowHost
	assert_bool(host.is_coupled()).is_true()
	assert_int(ChallengeRunner.rig_wheels(v).size()) \
			.is_equal(v.wheels.size() + host.trailer.wheels.size())


# --- the ticks -----------------------------------------------------------------------------------

func test_reaching_the_finish_passes_once_with_the_time() -> void:
	var r := _rig(_def([_reach(&"Finish")]))
	r.runner.tick(DT)
	_put(r.level.vehicle, FINISH_AT)
	r.runner.tick(DT)
	assert_int(r.runner.attempt.status).is_equal(S.PASS)
	assert_int(_results.size()).is_equal(1)
	assert_bool(_results[0][0]).is_true()
	assert_float(_results[0][1]).is_equal_approx(2.0 * DT, 1e-6)
	r.runner.tick(DT)
	assert_int(_results.size()).is_equal(1)


func test_a_fail_zone_respawns_with_its_warning_and_the_teleport_is_no_path() -> void:
	var r := _rig(_def([_reach(&"Finish")], [_fail(&"Pit", "Into the pit")]))
	var v := r.level.vehicle
	r.runner.tick(DT)
	_put(v, MARK_AT)
	r.runner.tick(DT)
	_put(v, PIT_AT)
	r.runner.tick(DT)
	assert_array(_notices).contains(["INTO THE PIT"])
	assert_float(v.global_position.distance_to(SPAWN_AT)).is_less(1e-3)
	# The first tick after the respawn: started over, and the pit-to-spawn jump crossed no Finish.
	r.runner.tick(DT)
	assert_int(r.runner.attempt.status).is_equal(S.RUNNING)
	assert_float(r.runner.attempt.elapsed).is_equal_approx(DT, 1e-6)
	assert_array(_results).is_empty()


## R, a fall, anything: the attempt starts over, and the next start is rolled anew.
func test_any_respawn_starts_the_attempt_over() -> void:
	var d := _def([_reach(&"Mark"), _reach(&"Finish")])
	d.spawn_jitter_m = 3.0
	var r := _rig(d)
	var v := r.level.vehicle
	r.runner.tick(DT)
	_put(v, MARK_AT)
	r.runner.tick(DT)
	assert_int(r.runner.attempt.goal_index).is_equal(1)
	var landed := v.spawn_transform
	v.respawn()
	r.runner.tick(DT)
	assert_int(r.runner.attempt.goal_index).is_equal(0)
	assert_float(r.runner.attempt.elapsed).is_equal_approx(DT, 1e-6)
	assert_bool(v.spawn_transform.is_equal_approx(landed)).is_false()


func test_the_frame_holds_the_body_and_only_the_free_payloads() -> void:
	var r := _rig(_def([_reach(&"Finish")]))
	var loose := (load(CRATE) as PackedScene).instantiate() as CargoPayload
	r.level.add_child(loose)
	loose.global_position = Vector3(5, 1, 5)
	var hooked := (load(CRATE) as PackedScene).instantiate() as CargoPayload
	r.level.add_child(hooked)
	hooked.carried = true
	var elsewhere := auto_free((load(CRATE) as PackedScene).instantiate()) as CargoPayload
	add_child(elsewhere)
	var frame := ChallengeRunner.build_frame(r.level.vehicle, r.level, Vector3.INF)
	assert_int(frame.payloads.size()).is_equal(1)
	assert_float(frame.payloads[0].distance_to(Vector3(5, 1, 5))).is_less(1e-4)
	assert_int(frame.wheel_count).is_equal(4)
	assert_bool(frame.signals.has("heading")).is_true()
	assert_bool(frame.prev_origin.is_finite()).is_false()


# --- the end -------------------------------------------------------------------------------------

func test_end_takes_the_attempt_off_and_hands_the_body_back() -> void:
	var d := _def([_reach(&"Finish")])
	d.visibility = V.DARK
	var r := _rig(d)
	var env := r.level.environment()
	assert_float(env.ambient_light_energy).is_equal(0.0)
	assert_bool(r.level.sun_light().visible).is_false()
	var course: Node3D = r.runner._course
	r.runner.end()
	var day := load(DAY_ENV) as Environment
	assert_float(env.ambient_light_energy).is_equal(day.ambient_light_energy)
	assert_int(env.background_mode).is_equal(day.background_mode)
	assert_bool(r.level.sun_light().visible).is_true()
	assert_object(course.get_parent()).is_null()
	assert_bool(r.level.vehicle.spawn_transform.is_equal_approx(
			r.level.pick_spawn("car").global_transform)).is_true()
	r.runner.end()
	assert_bool(r.runner.is_physics_processing()).is_false()


# --- the jitter ----------------------------------------------------------------------------------

func test_jitter_stays_in_its_disc_and_yaw_and_replays_from_its_seed() -> void:
	var base := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1, -2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var again := RandomNumberGenerator.new()
	again.seed = 11
	for _i in 50:
		var t := ChallengeRunner.jittered(base, 2.0, 15.0, rng)
		assert_bool(t.is_equal_approx(ChallengeRunner.jittered(base, 2.0, 15.0, again))).is_true()
		var off := base.affine_inverse() * t.origin
		assert_float(off.y).is_equal_approx(0.0, 1e-5)
		assert_float(Vector2(off.x, off.z).length()).is_less_equal(2.0 + 1e-5)
		assert_float(absf(rad_to_deg((base.basis.inverse() * t.basis).get_euler().y))) \
				.is_less_equal(15.0 + 1e-3)
		assert_float(t.basis.y.dot(base.basis.y)).is_equal_approx(1.0, 1e-5)


func test_no_jitter_is_the_marker_exactly() -> void:
	var base := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1, -2))
	var rng := RandomNumberGenerator.new()
	assert_bool(ChallengeRunner.jittered(base, 0.0, 0.0, rng).is_equal_approx(base)).is_true()
