extends GdUnitTestSuite
## FamilyContent on the real Flatland: the drone's crates are in the tree only while a drone is
## driven, and every drone spawn and respawn starts with the whole set at its authored poses.


func _flatland() -> Level:
	var level := auto_free(
			(load(LevelRegistry.scene_of("flatland")) as PackedScene).instantiate()) as Level
	add_child(level)
	return level


func test_flatlands_crates_are_there_only_while_a_drone_is_driven() -> void:
	var level := _flatland()
	var payloads := level.get_node("Payloads") as FamilyContent
	level.set_vehicle("sedan")
	assert_int(payloads.get_child_count()).is_equal(0)
	assert_int(ChallengeRunner.free_payloads(level).size()).is_equal(0)
	level.set_vehicle("drone-mk2")
	assert_int(payloads.get_child_count()).is_equal(3)
	assert_int(ChallengeRunner.free_payloads(level).size()).is_equal(3)


func test_a_drone_spawn_puts_a_moved_crate_back() -> void:
	var level := _flatland()
	var payloads := level.get_node("Payloads") as FamilyContent
	level.set_vehicle("drone-mk2")
	var crate := payloads.get_child(0) as CargoPayload
	var home := crate.transform
	# Dropped elsewhere by the hook: a child of the level, away from its pose.
	crate.reparent(level)
	crate.position += Vector3(30.0, 5.0, 0.0)
	level.set_vehicle("sedan")
	assert_bool(crate.is_inside_tree()).is_false()
	level.set_vehicle("drone-mk2")
	assert_object(crate.get_parent()).is_same(payloads)
	assert_vector(crate.transform.origin).is_equal_approx(home.origin, Vector3.ONE * 1e-4)
	assert_int(payloads.get_child_count()).is_equal(3)


## A respawn starts over, crates and all: one dropped elsewhere and one still on the hook.
func test_a_respawn_puts_the_crates_back() -> void:
	var level := _flatland()
	var payloads := level.get_node("Payloads") as FamilyContent
	level.set_vehicle("drone-mk2")
	var dropped := payloads.get_child(0) as CargoPayload
	var carried := payloads.get_child(1) as CargoPayload
	var homes: Array[Vector3] = [dropped.position, carried.position]
	dropped.reparent(level)
	dropped.position += Vector3(30.0, 5.0, 0.0)
	var drone := level.vehicle as DroneVehicle
	drone._hook._payload = carried
	carried.attach_to(drone._hook._marker, Vector3.ZERO)
	drone.respawn()
	assert_int(payloads.get_child_count()).is_equal(3)
	assert_bool(carried.carried).is_false()
	assert_vector(dropped.position).is_equal_approx(homes[0], Vector3.ONE * 1e-4)
	assert_vector(carried.position).is_equal_approx(homes[1], Vector3.ONE * 1e-4)
	# On another body a respawn brings nothing back.
	level.set_vehicle("sedan")
	level.vehicle.respawn()
	assert_int(payloads.get_child_count()).is_equal(0)
