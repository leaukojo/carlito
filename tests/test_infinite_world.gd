extends GdUnitTestSuite
## The endless levels' two followers: InfiniteGround and an `infinite` WaterSurface re-centre
## on the active camera, on their lattice, and the sea contains every point.

const Layers := preload("res://src/physics/collision_layers.gd")

const CAM_POS := Vector3(1234.5, 30.0, -987.6)


func _camera() -> Camera3D:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.global_position = CAM_POS
	cam.make_current()
	return cam


func test_infinite_sea_contains_everywhere_and_a_bounded_one_does_not() -> void:
	var sea: WaterSurface = auto_free(WaterSurface.new())
	sea.infinite = true
	add_child(sea)
	assert_bool(sea.contains_xz(Vector3(50000.0, 0.0, -80000.0))).is_true()
	sea.infinite = false
	assert_bool(sea.contains_xz(Vector3(50000.0, 0.0, -80000.0))).is_false()


func test_infinite_sea_follows_the_camera_on_the_wave_quad_lattice() -> void:
	_camera()
	var sea: WaterSurface = auto_free(WaterSurface.new())
	sea.size = Vector2(4000.0, 4000.0)
	sea.infinite = true
	add_child(sea)
	sea.position.y = 2.0
	sea._physics_process(1.0 / 60.0)
	var step := WaterSurface.follow_step(sea.size)
	assert_float(sea.global_position.x).is_equal_approx(snappedf(CAM_POS.x, step.x), 0.001)
	assert_float(sea.global_position.z).is_equal_approx(snappedf(CAM_POS.z, step.y), 0.001)
	assert_float(sea.global_position.y).is_equal(2.0)


## The step must be exactly one quad of the mesh WaterSurface builds, or every re-centre
## moves the vertices off their wave samples and the surface pops.
func test_follow_step_is_one_quad_of_the_built_mesh() -> void:
	var sea: WaterSurface = auto_free(WaterSurface.new())
	sea.size = Vector2(4000.0, 4000.0)
	add_child(sea)
	var plane: PlaneMesh = null
	for c in sea.get_children(true):
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh:
			plane = (c as MeshInstance3D).mesh
			break
	var quads := plane.subdivide_width + 1
	assert_float(WaterSurface.follow_step(sea.size).x).is_equal_approx(4000.0 / quads, 0.0001)


func test_ground_follows_the_camera_and_sits_on_the_terrain_layer() -> void:
	_camera()
	var ground: InfiniteGround = auto_free(InfiniteGround.new())
	add_child(ground)
	ground._physics_process(1.0 / 60.0)
	assert_float(ground.global_position.x).is_equal_approx(
			snappedf(CAM_POS.x, InfiniteGround.FOLLOW_STEP), 0.001)
	assert_float(ground.global_position.z).is_equal_approx(
			snappedf(CAM_POS.z, InfiniteGround.FOLLOW_STEP), 0.001)
	assert_float(ground.global_position.y).is_equal(0.0)
	assert_int(ground.collision_layer).is_equal(Layers.TERRAIN)


func test_ground_slab_top_face_is_the_node_plane() -> void:
	var ground: InfiniteGround = auto_free(InfiniteGround.new())
	add_child(ground)
	for c in ground.get_children(true):
		if c is CollisionShape3D:
			var box := (c as CollisionShape3D).shape as BoxShape3D
			assert_float(c.position.y + box.size.y * 0.5).is_equal_approx(0.0, 0.0001)
			assert_float(box.size.x).is_equal(ground.extent)
