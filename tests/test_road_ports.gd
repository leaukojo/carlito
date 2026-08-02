extends GdUnitTestSuite
## RoadPorts (kit/helpers/road_ports.gd): port discovery on a roads GridMap.
## Pure math + headless-constructible fixtures (GridMap/MeshLibrary need no meshes for
## cell/orientation queries; world transforms are passed explicitly, so nothing is ever
## added to a tree). Hand-checked numbers use the roads lattice: cell_size (12,3,12),
## centre-true X/Z (cell 0 centred at local 6), bottom-true Y, deck painted at
## y-index 1 (cell base y=3), asphalt surface 0.12 above the base.

const Ports := preload("res://kit/helpers/road_ports.gd")

const EPS := Vector3(0.0001, 0.0001, 0.0001)


func _recipe() -> Dictionary:
	return {
		"ports": {
			"surface_y": 0.12,
			"entries": [
				{"match": ["^road-straight$"], "ports": [
					{"cell": [0, 0], "face": "+x"}, {"cell": [0, 0], "face": "-x"}]},
				{"match": ["^road-roundabout$"], "ports": [
					{"cell": [1, 0], "face": "+x"}, {"cell": [-1, 0], "face": "-x"},
					{"cell": [0, 1], "face": "+z"}, {"cell": [0, -1], "face": "-z"}]},
			],
		},
	}


func _roads_grid() -> GridMap:
	var gm: GridMap = auto_free(GridMap.new())
	gm.cell_size = Vector3(12, 3, 12)
	gm.cell_center_y = false
	var ml := MeshLibrary.new()
	ml.create_item(0)
	ml.set_item_name(0, "road-straight")
	ml.create_item(1)
	ml.set_item_name(1, "road-roundabout")
	ml.create_item(2)
	ml.set_item_name(2, "road-square")
	gm.mesh_library = ml
	return gm


func _yaw_index(gm: GridMap, degrees: float) -> int:
	return gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(degrees)))


# --- recipe parsing & validation ---


func test_real_recipe_parses_and_validates() -> void:
	var recipe: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://kit/import/roads.json"))
	assert_that(recipe).is_not_null()
	assert_array(Ports.validate(recipe)).is_empty()
	var table: Dictionary = Ports.parse_table(recipe)
	assert_float(table["surface_y"]).is_equal_approx(0.12, 0.0001)
	assert_int((table["entries"] as Array).size()).is_equal(6)


func test_validate_reports_shape_errors() -> void:
	var errors: Array = Ports.validate({"ports": {"entries": [
		{"ports": [{"cell": [0, 0], "face": "+x"}]},                    # no match
		{"match": ["("], "ports": [{"cell": [0, 0], "face": "+x"}]},    # bad regex
		{"match": ["^a$"], "ports": []},                                # no ports
		{"match": ["^b$"], "ports": [{"cell": [0, 0], "face": "+y"}]},  # bad face
		{"match": ["^c$"], "ports": [{"cell": [1], "face": "+x"}]},     # bad cell
	]}})
	assert_int(errors.size()).is_equal(5)


func test_validate_accepts_missing_ports_section() -> void:
	assert_array(Ports.validate({"kit": "roads"})).is_empty()


func test_parse_skips_malformed_ports() -> void:
	var table: Dictionary = Ports.parse_table({"ports": {"entries": [
		{"match": ["^x$"], "ports": [
			{"cell": [0, 0], "face": "+y"}, {"cell": [0, 0], "face": "-z"}]},
	]}})
	var entry: Dictionary = (table["entries"] as Array)[0]
	assert_int((entry["ports"] as Array).size()).is_equal(1)


# --- port enumeration ---


func test_straight_tile_two_ports() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_int(ports.size()).is_equal(2)
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(12, 3.12, 6), EPS)
	assert_vector(ports[0]["normal"]).is_equal_approx(Vector3(1, 0, 0), EPS)
	assert_vector(ports[1]["position"]).is_equal_approx(Vector3(0, 3.12, 6), EPS)
	assert_vector(ports[1]["normal"]).is_equal_approx(Vector3(-1, 0, 0), EPS)
	assert_that(ports[0]["cell"]).is_equal(Vector3i(0, 1, 0))


func test_rotated_straight_ports_follow_orientation() -> void:
	var gm := _roads_grid()
	# yaw +90 maps local +x to -z: the ports land on the cell's z faces
	gm.set_cell_item(Vector3i(0, 1, 0), 0, _yaw_index(gm, 90))
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_int(ports.size()).is_equal(2)
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(6, 3.12, 0), EPS)
	assert_vector(ports[0]["normal"]).is_equal_approx(Vector3(0, 0, -1), EPS)
	assert_vector(ports[1]["position"]).is_equal_approx(Vector3(6, 3.12, 12), EPS)
	assert_vector(ports[1]["normal"]).is_equal_approx(Vector3(0, 0, 1), EPS)
	# yaw 180 flips back onto the x faces, normals swapped vs identity
	gm.set_cell_item(Vector3i(0, 1, 0), 0, _yaw_index(gm, 180))
	ports = Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(0, 3.12, 6), EPS)
	assert_vector(ports[0]["normal"]).is_equal_approx(Vector3(-1, 0, 0), EPS)


func test_shared_face_emits_no_port() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	gm.set_cell_item(Vector3i(1, 1, 0), 0)
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	# only the two outer ends survive; the shared boundary is suppressed on both sides
	assert_int(ports.size()).is_equal(2)
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(0, 3.12, 6), EPS)
	assert_vector(ports[1]["position"]).is_equal_approx(Vector3(24, 3.12, 6), EPS)


func test_roundabout_multi_cell_offsets() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 1)
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_int(ports.size()).is_equal(4)
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(24, 3.12, 6), EPS)
	assert_that(ports[0]["cell"]).is_equal(Vector3i(1, 1, 0))
	assert_vector(ports[1]["position"]).is_equal_approx(Vector3(-12, 3.12, 6), EPS)
	assert_vector(ports[2]["position"]).is_equal_approx(Vector3(6, 3.12, 24), EPS)
	assert_vector(ports[3]["position"]).is_equal_approx(Vector3(6, 3.12, -12), EPS)


func test_rotated_roundabout_offsets_rotate_with_cell() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 1, _yaw_index(gm, 90))
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_int(ports.size()).is_equal(4)
	# the table's first port (offset [1,0], face +x) lands where identity's -z port was
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(6, 3.12, -12), EPS)
	assert_vector(ports[0]["normal"]).is_equal_approx(Vector3(0, 0, -1), EPS)
	assert_that(ports[0]["cell"]).is_equal(Vector3i(0, 1, -1))


func test_unlisted_tile_has_no_ports() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 2)  # road-square: no table entry
	assert_array(Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))).is_empty()


func test_world_xform_moves_ports_and_normals() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	var xform := Transform3D(Basis(Vector3.UP, PI), Vector3(100, 5, -50))
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()), xform)
	assert_vector(ports[0]["position"]).is_equal_approx(Vector3(88, 8.12, -56), EPS)
	assert_vector(ports[0]["normal"]).is_equal_approx(Vector3(-1, 0, 0), EPS)


func test_enumeration_is_deterministic() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	gm.set_cell_item(Vector3i(3, 1, 2), 1)
	gm.set_cell_item(Vector3i(-2, 1, 1), 0, _yaw_index(gm, 270))
	var table: Dictionary = Ports.parse_table(_recipe())
	var a := Ports.enumerate_ports(gm, table)
	var b := Ports.enumerate_ports(gm, table)
	assert_that(a).is_equal(b)
	assert_int(a.size()).is_equal(8)


# --- nearest_port ---


func test_nearest_port_uses_horizontal_distance() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	# ground-level click beside the raised deck: y difference must not count
	var hit := Ports.nearest_port(ports, Vector3(11, 0, 6), 3.0)
	assert_bool(hit.is_empty()).is_false()
	assert_vector(hit["position"]).is_equal_approx(Vector3(12, 3.12, 6), EPS)


func test_nearest_port_respects_radius() -> void:
	var gm := _roads_grid()
	gm.set_cell_item(Vector3i(0, 1, 0), 0)
	var ports := Ports.enumerate_ports(gm, Ports.parse_table(_recipe()))
	assert_bool(Ports.nearest_port(ports, Vector3(20, 0, 6), 3.0).is_empty()).is_true()
	assert_bool(Ports.nearest_port(ports, Vector3(6, 0, 6), 3.0).is_empty()).is_true()


func test_nearest_port_on_empty_list() -> void:
	assert_bool(Ports.nearest_port([], Vector3.ZERO, 100.0).is_empty()).is_true()
