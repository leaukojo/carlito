extends GdUnitTestSuite
## ShaderWarmup: culling margins grown then restored, particle twins started then freed. The
## compile itself needs a renderer and is not tested.

func _rig() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	mesh.extra_cull_margin = 1.5
	root.add_child(mesh)
	var scatter := MultiMeshInstance3D.new()
	scatter.name = "Scatter"
	root.add_child(scatter)
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.emitting = false
	dust.position = Vector3(1.0, 2.0, 3.0)
	root.add_child(dust)
	return root


func _twins(root: Node) -> Array:
	var out := []
	for node in root.find_children("*", "GPUParticles3D", true, false):
		if node.name != "Dust":
			out.append(node)
	return out


func test_margins_grow_for_the_hold_and_come_back() -> void:
	var root := _rig()
	var mesh: MeshInstance3D = root.get_node("Mesh")
	var scatter: MultiMeshInstance3D = root.get_node("Scatter")
	var warmup := ShaderWarmup.begin(root)
	assert_float(mesh.extra_cull_margin).is_equal(ShaderWarmup.CULL_MARGIN)
	assert_float(scatter.extra_cull_margin).is_equal(ShaderWarmup.CULL_MARGIN)
	warmup.end()
	assert_float(mesh.extra_cull_margin).is_equal(1.5)
	assert_float(scatter.extra_cull_margin).is_equal(0.0)


func test_each_emitter_gets_an_emitting_twin_and_the_original_is_untouched() -> void:
	var root := _rig()
	var dust: GPUParticles3D = root.get_node("Dust")
	var warmup := ShaderWarmup.begin(root)
	var twins := _twins(root)
	assert_int(twins.size()).is_equal(1)
	var twin := twins[0] as GPUParticles3D
	assert_bool(twin.emitting).is_true()
	assert_float(twin.amount_ratio).is_equal(1.0)
	assert_that(twin.global_position).is_equal(dust.global_position)
	assert_that(twin.process_material).is_same(dust.process_material)
	assert_bool(dust.emitting).is_false()
	warmup.end()
	assert_bool(twin.is_queued_for_deletion()).is_true()


func test_end_is_safe_after_the_level_is_gone() -> void:
	var root := Node3D.new()
	add_child(root)
	var mesh := MeshInstance3D.new()
	root.add_child(mesh)
	root.add_child(GPUParticles3D.new())
	var warmup := ShaderWarmup.begin(root)
	root.free()
	warmup.end()
	warmup.end()  # a second call is a no-op too
	assert_bool(is_instance_valid(root)).is_false()
