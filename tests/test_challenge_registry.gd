extends GdUnitTestSuite
## ChallengeRegistry: grouping by family, and `problems()`, the validation every shipped def is
## held to. Course fixtures are built in memory and saved under user:// (test_bake's pattern), so
## the suite commits no scene.

const GOOD := "user://challenge_course_good.tscn"
const BOAT_ONLY := "user://challenge_course_boat_only.tscn"
const DUP_ZONES := "user://challenge_course_dup_zones.tscn"
const BAD_ZONE := "user://challenge_course_bad_zone.tscn"
const NOT_3D := "user://challenge_course_not_3d.tscn"
const PREVIEW_L1 := "user://challenge_course_preview_l1.tscn"
const BOX_TRAILER := "res://src/vehicles/truck/trailers/box.tscn"


func before() -> void:
	var good := _course([])
	_add_preview(good, "flatland")
	_pack(good, GOOD)
	var other := _course([])
	_add_preview(other, "level_1")
	_pack(other, PREVIEW_L1)
	_pack(_course(["boat"]), BOAT_ONLY)
	var dup := _course([])
	_add_zone(dup, "Box", Vector3(0, 0, 10))
	_pack(dup, DUP_ZONES)
	var bad := _course([])
	var ring := _add_zone(bad, "Ring", Vector3.ZERO)
	ring.kind = ZoneShape.Kind.RING
	ring.inner_r = 5.0
	ring.outer_r = 5.0
	_pack(bad, BAD_ZONE)
	_pack(Node.new(), NOT_3D)


func _course(spawn_types: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Course"
	var spawn := VehicleSpawn.new()
	spawn.name = "Spawn"
	spawn.vehicle_types = PackedStringArray(spawn_types)
	root.add_child(spawn)
	_add_zone(root, "Box", Vector3.ZERO)
	return root


## A zone under its own group node, so a second zone of the same name can sit beside it.
func _add_zone(root: Node3D, zone_name: String, pos: Vector3) -> ChallengeZone:
	var group := Node3D.new()
	root.add_child(group, true)
	var z := ChallengeZone.new()
	z.name = zone_name
	z.position = pos
	group.add_child(z)
	return z


func _add_preview(root: Node3D, arena: String) -> void:
	var preview := ArenaPreview.new()
	preview.name = "ArenaPreview"
	preview.arena = arena
	root.add_child(preview)


func _pack(root: Node, path: String) -> void:
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()


## A car on flatland: stop in the box with the indicator on, a comfort limit and a manual box.
func _good(variant := "sedan-sports") -> ChallengeDef:
	var d := ChallengeDef.new()
	d.id = "box_stop"
	d.title = "Stop in the box"
	d.briefing = "Pass the gate, then stop in the box. speed is 0.01 m/s on the wire."
	d.hint = "speed, brake"
	d.variant = variant
	d.arena = "flatland"
	d.course = GOOD
	var lamp := LampWindowGoal.new()
	lamp.zone = &"Box"
	var stop := StopInZoneGoal.new()
	stop.zone = &"Box"
	d.goals.append(lamp)
	d.goals.append(stop)
	var limit := SignalLimitConstraint.new()
	limit.signal_name = "accLat"
	limit.high = 4.0
	limit.absolute = true
	d.constraints.append(limit)
	d.constraints.append(ManualGearConstraint.new())
	return d


func _assert_problem(d: ChallengeDef, needle: String) -> void:
	var found := ChallengeRegistry.problems(d)
	var hit := false
	for p in found:
		if p.contains(needle):
			hit = true
	assert_bool(hit).override_failure_message(
			"expected a problem containing '%s', got %s" % [needle, found]).is_true()


func test_a_good_def_has_no_problems() -> void:
	assert_array(ChallengeRegistry.problems(_good())).is_empty()


func test_def_fields_are_checked() -> void:
	var d := _good()
	d.id = ""
	_assert_problem(d, "lowercase letters")
	d.id = "Box Stop"
	_assert_problem(d, "lowercase letters")
	d = _good()
	d.goals.clear()
	_assert_problem(d, "no goals")
	d = _good()
	d.goals.append(null)
	_assert_problem(d, "empty goal")
	d = _good()
	d.par_s = -1.0
	_assert_problem(d, "negative par")
	d = _good()
	d.visibility = ChallengeDef.Visibility.FOG
	_assert_problem(d, "fog density")
	d.fog_density = 0.05
	assert_array(ChallengeRegistry.problems(d)).is_empty()
	_assert_problem(_good("hovercraft"), "unknown variant")


## Rule 10: the web font has no emoji glyphs.
func test_player_facing_text_is_present_and_plain_ascii() -> void:
	var d := _good()
	d.title = ""
	_assert_problem(d, "no title")
	d = _good()
	d.hint = "  "
	_assert_problem(d, "no hint")
	d = _good()
	d.briefing = "Stop in the box " + String.chr(0x2705)
	_assert_problem(d, "briefing has a non-ASCII character")


func test_the_arena_must_exist_and_let_the_family_spawn() -> void:
	var d := _good()
	d.arena = "level_99"
	_assert_problem(d, "not a registered level")
	_assert_problem(_good("boat-speed-a"), "may not spawn on 'flatland'")


func test_arena_info_is_read_off_the_scene_state() -> void:
	var info := ChallengeRegistry.arena_info(LevelRegistry.scene_of("flatland"))
	assert_bool(info.allowed_vehicles.has("tractor")).is_true()
	assert_bool(info.allowed_vehicles.has("boat")).is_false()


## An island's course ships in that island's pack; a main-pack level's course in no pack.
func test_the_course_ships_where_its_arena_does() -> void:
	var d := _good()
	d.arena = "level_1"
	_assert_problem(d, "must live under res://src/levels/island/level_1/")
	d = _good()
	d.course = "res://src/levels/island/level_1/nope_course.tscn"
	_assert_problem(d, "sits in a level pack")


func test_the_course_must_load_with_a_spawn_for_the_family() -> void:
	var d := _good()
	d.course = "user://challenge_course_missing.tscn"
	_assert_problem(d, "does not exist")
	d.course = NOT_3D
	_assert_problem(d, "Node3D root")
	d.course = BOAT_ONLY
	_assert_problem(d, "no VehicleSpawn accepting the car family")


func test_a_preview_of_another_arena_is_reported() -> void:
	var d := _good()
	d.course = PREVIEW_L1
	_assert_problem(d, "course previews 'level_1', but the arena is 'flatland'")


## A course is a runtime overlay: never among its arena's bake inputs, and its arena never among
## its dependencies — an ArenaPreview names the arena by id — so neither re-stales nor loads the
## other.
func test_a_course_and_its_arena_never_depend_on_each_other() -> void:
	var defs := ChallengeRegistry.all()
	defs.append_array(ChallengeRegistry.dev_all())
	for d in defs:
		var arena := LevelRegistry.scene_of(d.arena)
		assert_array(LevelBaker.gather_bake_inputs(arena)).not_contains([d.course])
		assert_bool(_depends_on(d.course, arena)).override_failure_message(d.id).is_false()
	assert_bool(_depends_on(PREVIEW_L1, LevelRegistry.scene_of("level_1"))).is_false()


func _depends_on(path: String, target: String) -> bool:
	for dep in ResourceLoader.get_dependencies(path):
		if String(dep).contains(target):
			return true
	return false


func test_every_zone_a_check_names_must_be_in_the_course_once() -> void:
	var d := _good()
	(d.goals[1] as StopInZoneGoal).zone = &"Nope"
	_assert_problem(d, "zone 'Nope'")
	d = _good()
	d.course = DUP_ZONES
	_assert_problem(d, "'Box' is used twice")


func test_a_zone_that_can_hold_nothing_is_reported() -> void:
	var d := _good()
	d.course = BAD_ZONE
	_assert_problem(d, "zone 'Ring'")


## Validation binds copies: the def's own checks stay free of per-attempt state.
func test_validation_leaves_the_def_unbound() -> void:
	var d := _good()
	ChallengeRegistry.problems(d)
	assert_object((d.goals[1] as StopInZoneGoal)._zone).is_null()


func test_check_parameters_are_checked() -> void:
	var d := _good()
	(d.constraints[0] as SignalLimitConstraint).low = 5.0
	_assert_problem(d, "is above high")
	d = _good()
	(d.goals[0] as LampWindowGoal).lamp = &"lights"
	_assert_problem(d, "not an on/off LampInput bit")
	d = _good()
	(d.constraints[1] as ManualGearConstraint).from_goal = 2
	_assert_problem(d, "from_goal 2 names no goal")


func test_signals_must_be_scalar_out_signals_of_the_family() -> void:
	var d := _good()
	var reach := SignalReachGoal.new()
	reach.signal_name = "trailer_abs"
	d.goals.append(reach)
	_assert_problem(d, "'trailer_abs' is not an out signal of the car family")
	d = _good()
	var slip := SignalLimitConstraint.new()
	slip.signal_name = "slip"
	d.constraints.append(slip)
	_assert_problem(d, "'slip' is an array signal")


func test_input_fields_must_exist() -> void:
	var d := _good()
	(d.goals[0] as LampWindowGoal).lamp = &"turn_lft"
	_assert_problem(d, "'turn_lft' is not a VehicleInput or LampInput field")
	d = _good()
	var led := InputEqualsGoal.new()        # `led`, a LampInput field
	led.values = PackedInt32Array([0xF800])
	d.goals.append(led)
	var gear := InputEqualsGoal.new()
	gear.field = &"gear_request"            # a plain VehicleInput field
	gear.values = PackedInt32Array([1])
	d.goals.append(gear)
	assert_array(ChallengeRegistry.problems(d)).is_empty()


func test_attachments_come_from_the_family_catalog() -> void:
	var d := _good()
	d.attachment = BOX_TRAILER
	_assert_problem(d, "nothing to attach")
	d = _good()
	d.allow_attach_key = true
	_assert_problem(d, "allow_attach_key")
	d = _good("semi")
	assert_array(ChallengeRegistry.problems(d)).is_empty()   # "" is bobtail
	d.attachment = BOX_TRAILER
	d.allow_attach_key = true
	assert_array(ChallengeRegistry.problems(d)).is_empty()
	d.attachment = ImplementCatalog.first()
	_assert_problem(d, "not in the truck catalog")
	d = _good("tractor-kenney")
	d.attachment = ImplementCatalog.first()
	assert_array(ChallengeRegistry.problems(d)).is_empty()


## Dev fixtures are reachable by id for the debug boot, and nowhere else: not in the list the
## CHALLENGES screen reads, and not among the ids the progress store keeps.
func test_dev_defs_are_never_listed() -> void:
	var listed := ChallengeRegistry.ids()
	for d in ChallengeRegistry.dev_all():
		assert_bool(listed.has(d.id)).is_false()
		assert_object(ChallengeRegistry.def_of(d.id)).is_null()
		assert_object(ChallengeRegistry.def_of(d.id, true)).is_not_null()


func test_families_group_in_first_listed_order() -> void:
	var a := _good()
	a.id = "a"
	var b := _good("semi")
	b.id = "b"
	var c := _good()
	c.id = "c"
	var e := _good("drone-mk2")
	e.id = "e"
	var defs: Array[ChallengeDef] = [a, b, c, e]
	var groups := ChallengeRegistry.group_by_family(defs)
	assert_array(groups.keys()).contains_exactly(["car", "truck", "drone"])
	assert_array(groups["car"]).contains_exactly([a, c])


func test_duplicate_ids_are_reported_once() -> void:
	var a := _good()
	var b := _good()
	var c := _good()
	c.id = "other"
	var defs: Array[ChallengeDef] = [a, b, c, _good()]
	assert_array(ChallengeRegistry.duplicate_ids(defs)).contains_exactly(["box_stop"])


## The guard every authored challenge ships under, dev fixtures included.
func test_every_registered_def_can_ship() -> void:
	var defs := ChallengeRegistry.all()
	assert_int(defs.size()).is_equal(ChallengeRegistry.DEFS.size())
	var dev := ChallengeRegistry.dev_all()
	assert_int(dev.size()).is_equal(ChallengeRegistry.DEV_DEFS.size())
	defs.append_array(dev)
	assert_array(ChallengeRegistry.duplicate_ids(defs)).is_empty()
	for d in defs:
		assert_array(ChallengeRegistry.problems(d)) \
				.override_failure_message("%s: %s" % [d.id, ChallengeRegistry.problems(d)]) \
				.is_empty()
