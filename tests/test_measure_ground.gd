extends GdUnitTestSuite
## `MeasureRig`'s ground and welded blocks answer a wheel's rest test on the surface: the point
## `RayWheel._contact_query` reads its compression from lies on the face (or on the edge), and the
## normal is the face's, for a cylinder leaned and sunk as far as the sweep leaves it, across a
## block's cell seams too. A box tens of metres across puts that point up to tens of µm off its face
## (`docs/vehicles.md` § Contact). Near the origin: far out, Jolt's query frame (the cylinder's)
## carries the pose's float32 into the point (0.2 mm at 5.8 km under an 8 degree lean).

const MeasureRig := preload("res://tools/measure_rig.gd")
const WheelScript := preload("res://src/vehicles/base/wheel.gd")
const Layers := preload("res://src/physics/collision_layers.gd")

const RADIUS := 0.36
const HALF_WIDTH := 0.1
const TOL := 5e-6       ## m
const KERB := 0.12      ## m, a block's top over y = 0
## m the cylinder is sunk past its rounded touch: the sweep's 1/256 of a 0.32 m travel is 1.25 mm.
const DEPTHS: Array[float] = [0.0001, 0.0006, 0.00125]


func _cylinder() -> CylinderShape3D:
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = HALF_WIDTH * 2.0
	return cyl


## The rest test of `shape` posed by `basis` at `centre`, on the bodies a wheel queries.
static func _rest(space: PhysicsDirectSpaceState3D, shape: Shape3D, basis: Basis,
		centre: Vector3) -> Dictionary:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Layers.SOLID
	q.transform = Transform3D(basis, centre)
	return space.get_rest_info(q)


## The cylinder's query basis: its axis (local y) the wheel's axle, along X before it is leaned
## `lean` rad about the heading (-Z) and yawed `yaw`.
static func _wheel_basis(lean: float, yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean) * Basis(Vector3.BACK, PI / 2.0)


## The worst miss, over leans to 8 degrees, DEPTHS and seeded places and headings in `rect` (x, z,
## w, d), of the rest point's height from a flat face at `top`, or of its normal from up; INF when a
## sunk pose reads clear.
func _worst_on_face(root: Node3D, rect: Rect2, top: float) -> float:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var cyl := _cylinder()
	var cr := WheelScript.jolt_convex_radius(cyl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for lean_deg in [0.0, 2.0, -4.0, 8.0]:
		for depth in DEPTHS:
			for i in 12:
				var basis := _wheel_basis(deg_to_rad(lean_deg), rng.randf_range(-PI, PI))
				var support := WheelScript.cylinder_support(Vector3.UP, basis.y, RADIUS, HALF_WIDTH, cr)
				var rest := _rest(space, cyl, basis, Vector3(rect.position.x + rng.randf() * rect.size.x,
						top + support - depth, rect.position.y + rng.randf() * rect.size.y))
				if rest.is_empty():
					return INF
				worst = maxf(worst, absf((rest["point"] as Vector3).y - top))
				worst = maxf(worst, ((rest["normal"] as Vector3) - Vector3.UP).length())
	return worst


func _kerb(root: Node3D) -> void:
	MeasureRig.add_welded_box(root, "Kerb", Vector3(80.0, KERB + MeasureRig.BLOCK_SINK, 20.0),
			Transform3D(Basis.IDENTITY, Vector3.UP * ((KERB - MeasureRig.BLOCK_SINK) * 0.5)))


func test_the_ground_reads_a_leaned_wheel_on_its_face_at_the_spawn() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	assert_object(MeasureRig.add_ground(root, "Ground", 5800.0)).is_not_null()
	assert_float(await _worst_on_face(root, Rect2(-20.0, -20.0, 40.0, 40.0), 0.0)).is_less(TOL)


func test_a_tilted_ground_reads_a_wheel_on_its_surface_through_the_lift_point() -> void:
	# `tilt_ramp`: the surface through (0, lift, 0), rising toward -Z, for a cylinder leaned 4 degrees
	# on it and sunk as the sweep leaves it.
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var angle := deg_to_rad(7.0)
	var lift := 3.0
	assert_object(MeasureRig.tilt_ramp(root, null, 200.0, angle, lift)).is_not_null()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tilt := Basis(Vector3.RIGHT, angle)
	var normal := tilt * Vector3.UP
	var origin := Vector3.UP * lift
	var space := root.get_world_3d().direct_space_state
	var cyl := _cylinder()
	var cr := WheelScript.jolt_convex_radius(cyl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for depth in DEPTHS:
		for i in 12:
			var basis := tilt * _wheel_basis(deg_to_rad(4.0), rng.randf_range(-PI, PI))
			var support := WheelScript.cylinder_support(normal, basis.y, RADIUS, HALF_WIDTH, cr)
			var on_surface := origin + tilt * Vector3(rng.randf_range(-20.0, 20.0), 0.0,
					rng.randf_range(-20.0, 20.0))
			var rest := _rest(space, cyl, basis, on_surface + normal * (support - depth))
			assert_bool(rest.is_empty()).is_false()
			if not rest.is_empty():
				worst = maxf(worst, absf(normal.dot((rest["point"] as Vector3) - origin)))
				worst = maxf(worst, ((rest["normal"] as Vector3) - normal).length())
	assert_float(worst).is_less(TOL)


func test_a_welded_block_reads_a_leaned_wheel_on_its_face_across_its_seams() -> void:
	# 80 m along a 12 cm kerb, as the kerb pass lays it: the cells' seams every WELD_CELL.
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	_kerb(root)
	assert_float(await _worst_on_face(root, Rect2(-39.0, -9.0, 78.0, 18.0), KERB)).is_less(TOL)


func test_a_welded_block_reads_a_wheel_over_its_edge_on_the_edge() -> void:
	# Upright, the axle along the edge, the hub `e` past it and sunk past the tread's touch at
	# `sqrt(r^2 - e^2)` over the top: the point is on the edge, along the block's whole 80 m.
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	_kerb(root)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var cyl := _cylinder()
	var basis := _wheel_basis(0.0, 0.0)
	var worst := 0.0
	for e in [0.05, 0.1, 0.2, 0.3]:
		for depth in DEPTHS:
			for x in [-38.5, -21.3, -0.7, 12.9, 38.5]:
				var rest := _rest(space, cyl, basis,
						Vector3(x, KERB + sqrt(RADIUS * RADIUS - e * e) - depth, 10.0 + e))
				assert_bool(rest.is_empty()).is_false()
				if not rest.is_empty():
					var p: Vector3 = rest["point"]
					worst = maxf(worst, Vector2(p.y - KERB, p.z - 10.0).length())
	assert_float(worst).is_less(TOL)
