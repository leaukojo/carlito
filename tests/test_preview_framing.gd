extends GdUnitTestSuite
## The garage preview frames the vehicle and only the vehicle: SceneBounds measures geometry (no
## lights, no particles), and a display_only body ticks on a neutral input, never the driven
## body's (whose high beam would otherwise reach 90 m into the frame).

const SceneBounds := preload("res://src/ui/scene_bounds.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")


func test_bounds_are_the_mesh_not_a_long_range_light_or_an_emitter() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 4.0)
	mesh.mesh = box
	root.add_child(mesh)
	var spot := SpotLight3D.new()
	spot.spot_range = 90.0
	root.add_child(spot)
	var dust := GPUParticles3D.new()  # default visibility box is 8 m across
	root.add_child(dust)
	root.add_child(CPUParticles3D.new())
	var got := SceneBounds.world_aabb([root])
	assert_vector(got.position).is_equal_approx(Vector3(-1.0, -0.5, -2.0), Vector3.ONE * 1e-5)
	assert_vector(got.size).is_equal_approx(Vector3(2.0, 1.0, 4.0), Vector3.ONE * 1e-5)


func test_display_body_ignores_the_driven_bodys_input() -> void:
	var saved: VehicleInput = InputRouter.get_vehicle_input()
	var driven := VehicleInput.new()
	driven.steer = 1.0
	driven.lights = 4  # high beam
	driven.key = InputRouter.KEY_IGNITION
	InputRouter.set("_current", driven)
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var body := VehicleShot.spawn_display(CatalogScript.scene_of("sedan"))
	root.add_child(body)
	for i in 30:
		body._physics_process(1.0 / 60.0)
	InputRouter.set("_current", saved)
	assert_float(body.get("_steer")).is_equal(0.0)
	assert_bool(body.get("drivetrain").running).is_false()
	var spots := body.find_children("*", "SpotLight3D", true, false)
	assert_int(spots.size()).is_greater(0)
	for s in spots:
		assert_float((s as SpotLight3D).spot_range).is_equal(0.0)
	body.queue_free()
