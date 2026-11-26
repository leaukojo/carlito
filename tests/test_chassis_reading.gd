extends GdUnitTestSuite
## ChassisReading: the per-wheel reading the chassis view draws, off the tyre's own solve.

const WheelScript := preload("res://src/vehicles/base/wheel.gd")
const GroundDriveSpecScript := preload("res://src/vehicles/base/ground_drive_spec.gd")

const TICK := 1.0 / 60.0
const RADIUS := 0.36


## One wheel ticked once on a frozen body over flat ground, the body moving at `velocity` (body
## axes: -Z forward, +X right) with the wheel rolling at its forward speed; `lift` m raises it.
func _ticked_wheel(velocity: Vector3, lift := 0.0) -> WheelScript:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1  # TERRAIN, inside Layers.SOLID
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40.0, 1.0, 40.0)
	ground.add_child(shape)
	root.add_child(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 0
	root.add_child(body)
	body.global_position = Vector3(0.0, lift, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gd: GroundDriveSpecScript = GroundDriveSpecScript.new()
	gd.wheel_radius = RADIUS
	gd.wheel_inertia = 1.0
	gd.tyre_half_width = 0.1
	gd.rest_length = 0.3
	gd.spring_rate = 100000.0
	# A heavy corner: the one-tick caps stay far above the budget, so the force is the curve's.
	var w := WheelScript.new(Vector3(0.0, 0.6, 0.0), false, true, null, 3000.0)
	w.apply_suspension(gd)
	body.linear_velocity = velocity
	w.omega = -velocity.z / RADIUS
	w.tick(body, gd, root.get_world_3d().direct_space_state, 0.0, 0.0, TICK, [] as Array[Node])
	remove_child(root)
	root.free()
	return w


func test_a_wheel_at_rest_uses_no_grip() -> void:
	var r := ChassisReading.wheel_reading(await _ticked_wheel(Vector3.ZERO))
	assert_bool(r.in_contact).is_true()
	assert_float(r.normal_load).is_greater(0.0)
	assert_float(r.grip_use).is_less(1e-3)
	assert_bool(r.past_peak).is_false()


func test_a_patch_at_the_curves_peak_uses_its_whole_ellipse() -> void:
	# 10 m/s forward, 1.19 m/s sideways: a side slip of 0.119, just under the curve's 0.12 peak.
	var w: WheelScript = await _ticked_wheel(Vector3(1.19, 0.0, -10.0))
	var r := ChassisReading.wheel_reading(w)
	assert_float(r.grip_use).is_equal_approx(1.0, 0.02)
	assert_bool(r.past_peak).is_false()
	# The tyre pushes the car back against its slide, to the left.
	assert_float(r.force.x).is_less(0.0)


func test_a_patch_past_the_peak_reads_sliding_on_the_curves_tail() -> void:
	# A side slip of 0.3: past the 0.12 peak, on the fall toward 0.9 at 0.4.
	var w: WheelScript = await _ticked_wheel(Vector3(3.0, 0.0, -10.0))
	var r := ChassisReading.wheel_reading(w)
	assert_bool(r.past_peak).is_true()
	var expected := VehicleSpec.sample_curve(GroundDriveSpecScript.new().grip_curve, w.combined_slip)
	assert_float(r.grip_use).is_equal_approx(expected, 0.01)
	assert_float(r.grip_use).is_less(0.95)


func test_a_lifted_wheel_reads_no_contact_and_no_load() -> void:
	var r := ChassisReading.wheel_reading(await _ticked_wheel(Vector3(3.0, 0.0, -10.0), 2.0))
	assert_bool(r.in_contact).is_false()
	assert_float(r.normal_load).is_equal(0.0)
	assert_float(r.grip_use).is_equal(0.0)
	assert_bool(r.past_peak).is_false()
	assert_vector(r.force).is_equal(Vector2.ZERO)


func test_grip_use_is_the_force_over_its_ellipse() -> void:
	assert_float(ChassisReading.grip_use(Vector2(600.0, 800.0), Vector2(1000.0, 1000.0))) \
			.is_equal_approx(1.0, 1e-6)
	assert_float(ChassisReading.grip_use(Vector2(0.0, 475.0), Vector2(1050.0, 950.0))) \
			.is_equal_approx(0.5, 1e-6)
	assert_float(ChassisReading.grip_use(Vector2(100.0, 0.0), Vector2.ZERO)).is_equal(0.0)


func test_the_curves_peak_is_its_first_highest_point() -> void:
	assert_float(RayWheel.peak_slip(GroundDriveSpecScript.new().grip_curve)).is_equal_approx(0.12, 1e-6)
	# A plateau peaks where it starts; grip above 1 reads capped, as the tyre reads it.
	assert_float(RayWheel.peak_slip(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 1.0),
			Vector2(0.2, 1.3), Vector2(0.5, 0.8)]))).is_equal_approx(0.1, 1e-6)


func test_a_steered_wheels_force_turns_into_body_axes() -> void:
	# Straight: forward is -z, right is +x.
	assert_vector(ChassisReading.wheel_to_body(Vector2(100.0, 50.0), 0.0)) \
			.is_equal_approx(Vector2(50.0, -100.0), Vector2.ONE * 1e-4)
	# Steered a quarter turn left: its forward is the body's left (-x), its right the body's forward.
	assert_vector(ChassisReading.wheel_to_body(Vector2(100.0, 50.0), PI / 2.0)) \
			.is_equal_approx(Vector2(-100.0, -50.0), Vector2.ONE * 1e-4)


func test_the_load_centre_sits_toward_the_loaded_side() -> void:
	# A left turn's transfer: the right (outer) wheels carry three times the left's.
	var points := PackedVector2Array([Vector2(-0.8, -1.3), Vector2(0.8, -1.3),
			Vector2(-0.8, 1.3), Vector2(0.8, 1.3)])
	var loads := PackedFloat64Array([1000.0, 3000.0, 1000.0, 3000.0])
	assert_vector(ChassisReading.centre_of_loads(points, loads)) \
			.is_equal_approx(Vector2(0.4, 0.0), Vector2.ONE * 1e-5)
	# Braking on top: the fronts carry twice the rears.
	loads = PackedFloat64Array([2000.0, 6000.0, 1000.0, 3000.0])
	var c := ChassisReading.centre_of_loads(points, loads)
	assert_float(c.x).is_equal_approx(0.4, 1e-5)
	assert_float(c.y).is_equal_approx(-1.3 / 3.0, 1e-5)
	# Every wheel lifted: no centre.
	assert_bool(is_nan(ChassisReading.centre_of_loads(points, PackedFloat64Array([0, 0, 0, 0])).x)) \
			.is_true()


func test_an_anchor_box_bounds_its_anchors() -> void:
	# The semi tractor's anchors (`semi_spec.tres`): 3.6 m of wheelbase, tracks 1.44 / 1.24 m.
	var anchors := PackedVector2Array([Vector2(-0.72, -2.65), Vector2(0.72, -2.65),
			Vector2(-0.62, 0.95), Vector2(0.62, 0.95)])
	var box := ChassisReading.anchor_box(anchors)
	assert_vector(box.position).is_equal_approx(Vector2(-0.72, -2.65), Vector2.ONE * 1e-5)
	assert_vector(box.size).is_equal_approx(Vector2(1.44, 3.6), Vector2.ONE * 1e-5)
	assert_bool(ChassisReading.anchor_box(PackedVector2Array()).has_area()).is_false()


func test_a_diff_reads_none_open_biasing_or_locked() -> void:
	assert_int(ChassisReading.diff_state(NAN, NAN)).is_equal(ChassisReading.Diff.NONE)
	assert_int(ChassisReading.diff_state(0.0, 0.0)).is_equal(ChassisReading.Diff.OPEN)
	assert_int(ChassisReading.diff_state(120.0, 0.0)).is_equal(ChassisReading.Diff.OPEN)
	assert_int(ChassisReading.diff_state(120.0, -40.0)).is_equal(ChassisReading.Diff.BIASING)
	assert_int(ChassisReading.diff_state(INF, 0.0)).is_equal(ChassisReading.Diff.LOCKED)


# --- towed bodies ---------------------------------------------------------------------------------

## The tanker's tri-axle bogie (`tanker_spec.tres`), trailer xz: z back from the kingpin.
const BOGIE := [Vector2(-0.72, 4.4), Vector2(0.72, 4.4), Vector2(-0.72, 5.2), Vector2(0.72, 5.2),
		Vector2(-0.72, 6.0), Vector2(0.72, 6.0)]


## A towed body's point placed by its frame lands where the 3D transforms put it, the rig on a grade
## (both bodies pitched alike, so the flattening is exact) and the trailer swung either way.
func test_a_towed_frame_places_its_points_as_the_bodies_do() -> void:
	var unit := Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.05),
			Vector3(3.0, 0.5, -2.0))
	for swing: float in [-0.9, 0.0, 0.5]:
		var body := Transform3D(unit.basis * Basis(Vector3.UP, swing),
				unit * Vector3(0.0, 1.05, 0.45))
		var frame := ChassisReading.towed_frame(unit, body)
		for p: Vector2 in BOGIE:
			var expect := unit.affine_inverse() * body * Vector3(p.x, -0.626, p.y)
			assert_vector(frame * p).is_equal_approx(Vector2(expect.x, expect.z),
					Vector2.ONE * 1e-4)


## With no swing the reach is the anchors' own box; with one it spans both stops, symmetric about
## the coupling for a symmetric bogie.
func test_a_swept_box_covers_the_whole_swing() -> void:
	var anchors := PackedVector2Array(BOGIE)
	var origin := Vector2(0.0, 0.45)
	var still := ChassisReading.swept_box(anchors, origin, 0.0)
	var plain := ChassisReading.anchor_box(anchors)
	assert_vector(still.position).is_equal_approx(plain.position + origin, Vector2.ONE * 1e-5)
	assert_vector(still.size).is_equal_approx(plain.size, Vector2.ONE * 1e-5)
	var yaw := deg_to_rad(75.0)
	var swept := ChassisReading.swept_box(anchors, origin, yaw)
	assert_float(swept.get_center().x).is_equal_approx(origin.x, 1e-4)
	for a: float in [-yaw, -yaw / 3.0, 0.0, yaw / 2.0, yaw]:
		for p in anchors:
			var at := origin + p.rotated(a)
			assert_bool(swept.grow(1e-4).has_point(at)) \
					.override_failure_message("%s at %.2f rad outside %s" % [p, a, swept]).is_true()


## A semi with the tanker coupled reads the tanker's six wheels in their own xz, placed at the
## kingpin, inside their swept box; uncoupled it reads none.
func test_a_coupled_semi_reads_its_trailer() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var unit := (load(VehicleCatalog.scene_of("semi")) as PackedScene).instantiate() as BaseVehicle
	root.add_child(unit)
	var host := unit.get_node("FifthWheel") as TowHost
	var hosts: Array[TowHost] = [host]
	host.uncouple()
	assert_object(ChassisReading.of(unit, hosts).towed).is_null()
	assert_bool(host.couple(
			load("res://src/vehicles/truck/trailers/tanker.tscn") as PackedScene)).is_true()
	var r := ChassisReading.of(unit, hosts)
	assert_object(r.towed).is_not_null()
	assert_int(r.towed.wheels.size()).is_equal(6)
	assert_float(r.towed.mass).is_equal(host.trailer.mass)
	assert_vector(r.towed.frame.origin).is_equal_approx(Vector2(0.0, 0.45), Vector2.ONE * 1e-3)
	assert_float(r.towed.frame.get_rotation()).is_equal_approx(0.0, 1e-4)
	assert_vector(r.towed.coupling).is_equal_approx(Vector2(0.0, 0.45), Vector2.ONE * 1e-4)
	assert_float(r.towed.yaw_stop).is_equal_approx(deg_to_rad(Articulation.JACKKNIFE_MAX_DEG), 1e-5)
	# Out of the tree no transform reads, so no trailer is read.
	remove_child(root)
	assert_object(ChassisReading.of(unit, hosts).towed).is_null()
	add_child(root)
	host.uncouple()
	remove_child(root)
	root.free()
