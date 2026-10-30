extends GdUnitTestSuite
## ESC's K table follows the live mass (`WheelDrive.set_esc_mass`, from `BaseVehicle.set_live_mass`):
## the shipped table at the spec mass, the baked laden one nearest a laden mass, never a build.


func _spawn(variant: String) -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var v := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate() as BaseVehicle
	v.display_only = true  # no InputRouter registration; this suite never drives anything
	root.add_child(v)
	v.global_position = Vector3(0.0, 50.0, 0.0)
	await get_tree().physics_frame
	return v


func test_the_refuse_truck_reads_its_laden_table_and_the_shipped_one_back() -> void:
	var v := await _spawn("garbage-truck")
	var gd := v.spec.ground_drive
	assert_int(gd.esc_laden_kg.size()).is_greater(1)
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_reference_k)
	var full := gd.esc_laden_kg.size() - 1
	v.set_live_mass(v.spec.mass + RefuseBody.HOPPER_PAYLOAD_KG)
	assert_float(v.mass).is_equal_approx(gd.esc_laden_kg[full], 1e-3)
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_laden_k[full])
	assert_that(v.drive.esc_reference_k).is_not_equal(gd.esc_reference_k)
	v.respawn()
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_reference_k)


func test_an_off_level_mass_reads_its_nearest_level() -> void:
	var v := await _spawn("garbage-truck")
	var gd := v.spec.ground_drive
	# A third of the way from level 0 to level 1, then two thirds.
	var step := gd.esc_laden_kg[1] - gd.esc_laden_kg[0]
	v.set_live_mass(gd.esc_laden_kg[0] + step / 3.0)
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_laden_k[0])
	v.set_live_mass(gd.esc_laden_kg[0] + 2.0 * step / 3.0)
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_laden_k[1])
	# Just over the spec mass, under half the first level: the shipped table.
	v.set_live_mass(v.spec.mass + (gd.esc_laden_kg[0] - v.spec.mass) / 3.0)
	assert_that(v.drive.esc_reference_k).is_equal(gd.esc_reference_k)


func test_a_body_with_no_laden_tables_keeps_its_shipped_one() -> void:
	var v := await _spawn("sedan")
	v.set_live_mass(v.mass * 2.0)
	assert_that(v.drive.esc_reference_k).is_equal(v.spec.ground_drive.esc_reference_k)
