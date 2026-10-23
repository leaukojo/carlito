extends GdUnitTestSuite
## Roll and pitch are never set: Jolt computes them off the collision shapes ABOUT THE DECLARED
## CENTRE OF MASS, not about the shape centroid. That is the whole reason the COM heights can be
## raised as a data change. Yaw alone may be declared (`VehicleSpec.yaw_dynamic_index`), written to
## the y component of `RigidBody3D.inertia`: Jolt overrides only an axis set above 0 and keeps
## computing the others. This suite is the guard on both engine behaviours — a Godot or Jolt
## upgrade that moved the tensor back to the centroid, or made the override all-or-nothing, would
## leave a body rolling about the wrong point or freeze its roll and pitch, with nothing to see.
##
## Read the tensor through `PhysicsDirectBodyState3D.inverse_inertia` and nothing else:
## `RigidBody3D.inertia` and `PhysicsServer3D.body_get_param(..., BODY_PARAM_INERTIA)` are the
## OVERRIDE, and both read back Vector3.ZERO on a body whose tensor is computed.

const Layers := preload("res://src/physics/collision_layers.gd")

## Sedan COM heights either side of its collision hull's own mass centroid (~0.79 m body space).
const LOW := 0.20
const MID := 0.79
const HIGH := 1.40


## `com_z` NAN keeps the shipped spec's.
func _spawn(variant: String, com_y: float, yaw_index := 0.0, com_z := NAN) -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var v := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate() as BaseVehicle
	# The spec is a shared Resource loaded off the .tres, so it is duplicated before the override
	# — nothing here is written back to the shipped vehicle.
	v.spec = v.spec.duplicate(true)
	v.spec.center_of_mass = Vector3(v.spec.center_of_mass.x, com_y,
			v.spec.center_of_mass.z if is_nan(com_z) else com_z)
	v.spec.yaw_dynamic_index = yaw_index
	v.display_only = true  # no InputRouter registration; this suite never drives anything
	root.add_child(v)
	v.global_position = Vector3(0.0, 50.0, 0.0)
	# A body is not in the space state until the space has stepped.
	await get_tree().physics_frame
	await get_tree().physics_frame
	return v


## The real tensor, per the header: 1 / inverse_inertia, component-wise.
static func _inertia(v: BaseVehicle) -> Vector3:
	var st := PhysicsServer3D.body_get_direct_state(v.get_rid())
	var inv := st.inverse_inertia
	return Vector3(1.0 / inv.x, 1.0 / inv.y, 1.0 / inv.z)


## The declared yaw moment the spec asks for, off the same axle stations the body uses.
static func _declared_yaw(v: BaseVehicle) -> float:
	var ax := BrakeSizing.axle_geometry(v.spec)
	var com_z := v.spec.center_of_mass.z
	return v.spec.yaw_dynamic_index * v.mass * (com_z - float(ax["front_z"])) \
			* (float(ax["rear_z"]) - com_z)


func test_the_override_is_never_the_way_to_read_the_tensor() -> void:
	var v := await _spawn("sedan", LOW)
	# Both of these are the override, and a body that declares no yaw sets neither. Reading them
	# as "the inertia" is the trap this suite exists to keep out of the next COM change.
	assert_vector(v.inertia).is_equal(Vector3.ZERO)
	assert_vector(PhysicsServer3D.body_get_param(
			v.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA)).is_equal(Vector3.ZERO)
	assert_vector(_inertia(v)).is_not_equal(Vector3.ZERO)
	# A body that declares its yaw writes that axis alone.
	var d := await _spawn("sedan", LOW, 1.0)
	assert_float(d.inertia.x).is_equal(0.0)
	assert_float(d.inertia.z).is_equal(0.0)
	assert_float(d.inertia.y).is_greater(0.0)


func test_one_declared_axis_leaves_the_other_two_computed() -> void:
	# The engine behaviour the yaw declaration stands on, pinned off any spec: set y alone on a
	# computed body and the roll and pitch it had stay what Jolt computes.
	var v := await _spawn("sedan", MID)
	var computed := _inertia(v)
	v.inertia = Vector3(0.0, computed.y * 1.5, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var declared := _inertia(v)
	assert_float(declared.y / computed.y).is_equal_approx(1.5, 1e-3)
	assert_float(declared.x / computed.x).is_equal_approx(1.0, 0.02)
	assert_float(declared.z / computed.z).is_equal_approx(1.0, 0.02)


func test_a_declared_yaw_is_index_times_mass_times_the_axle_arms() -> void:
	var v := await _spawn("sedan", MID, 1.2)
	assert_float(_inertia(v).y / _declared_yaw(v)).is_equal_approx(1.0, 1e-3)


func test_roll_and_pitch_follow_the_com_with_yaw_declared() -> void:
	var low := _inertia(await _spawn("sedan", LOW, 1.0))
	var mid := _inertia(await _spawn("sedan", MID, 1.0))
	var high := _inertia(await _spawn("sedan", HIGH, 1.0))
	assert_float(mid.z).is_less(low.z)
	assert_float(mid.z).is_less(high.z)
	assert_float(mid.x).is_less(low.x)
	assert_float(mid.x).is_less(high.x)
	assert_float(low.z / mid.z).is_greater(1.3)
	assert_float(high.z / mid.z).is_greater(1.3)


func test_a_declared_yaw_scales_with_a_runtime_mass_rewrite() -> void:
	# A declared axis does not follow a `mass` write in Jolt: set_live_mass re-declares it.
	var v := await _spawn("sedan", LOW, 1.0)
	var unladen := _inertia(v)
	v.set_live_mass(v.mass * 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var laden := _inertia(v)
	assert_float(laden.x / unladen.x).is_equal_approx(2.0, 1e-3)
	assert_float(laden.y / unladen.y).is_equal_approx(2.0, 1e-3)
	assert_float(laden.z / unladen.z).is_equal_approx(2.0, 1e-3)


func test_roll_and_pitch_moments_follow_the_custom_centre_of_mass() -> void:
	var low := _inertia(await _spawn("sedan", LOW))
	var mid := _inertia(await _spawn("sedan", MID))
	var high := _inertia(await _spawn("sedan", HIGH))
	# Parallel axis: the moment is least about the body's own mass centroid and grows with the
	# square of the offset, either side of it. A tensor left about the shape centroid would be
	# the SAME number three times.
	assert_float(mid.z).is_less(low.z)   # roll, about the forward axis
	assert_float(mid.z).is_less(high.z)
	assert_float(mid.x).is_less(low.x)   # pitch, about the right axis
	assert_float(mid.x).is_less(high.x)
	# And the growth is real, not rounding: 0.6 m off the centroid is a third again in roll.
	assert_float(low.z / mid.z).is_greater(1.3)
	assert_float(high.z / mid.z).is_greater(1.3)


func test_moving_the_com_along_y_leaves_the_yaw_moment_alone() -> void:
	var low := _inertia(await _spawn("sedan", LOW))
	var high := _inertia(await _spawn("sedan", HIGH))
	# The signature that this really is the parallel-axis shift and not some other scaling: an
	# offset along y changes no distance to the y axis, so yaw must barely move while roll and
	# pitch move a lot.
	assert_float(high.y / low.y).is_between(0.95, 1.05)
	assert_float(high.z / low.z).is_greater(1.02)


func test_a_hull_bodied_vehicle_behaves_the_same_way() -> void:
	# The sedan's collision is a pair of boxes; most Kenney bodies are convex hulls. Same rule, at
	# z 0, where the height is the COM's only offset. Off the hull's centroid in z too (the shipped
	# -0.262), parallel axis adds the product `I_yz = -m dy dz`, which grows with height and moves
	# the principal-frame yaw reading ~5 % over 1 m: real, but not this rule's signature.
	var mid := _inertia(await _spawn("garbage-truck", 1.20, 0.0, 0.0))
	var high := _inertia(await _spawn("garbage-truck", 2.20, 0.0, 0.0))
	assert_float(mid.z).is_less(high.z)
	assert_float(mid.y / high.y).is_between(0.98, 1.02)


func test_a_live_centre_of_mass_rides_the_mass_write() -> void:
	# The tractor's carried implement: a body that declares no yaw takes the COM with the mass.
	var v := await _spawn("sedan", MID)
	var moved := v.spec.center_of_mass + Vector3(0.0, 0.1, 0.4)
	v.set_live_mass(v.mass + 100.0, moved)
	assert_vector(v.center_of_mass).is_equal(moved)
	# Without one, the spec's: the refuse hopper's mass-only path, and a respawn's reset.
	v.set_live_mass(v.spec.mass)
	assert_vector(v.center_of_mass).is_equal(v.spec.center_of_mass)


func test_a_body_that_declares_yaw_refuses_a_live_centre_of_mass() -> void:
	# `index · m · a · b` is sized off the spec COM; a rear load would shrink `b` and lower the yaw
	# moment, the wrong way. Refused loudly, and the spec COM stays.
	var v := await _spawn("sedan", MID, 1.0)
	var moved := v.spec.center_of_mass + Vector3(0.0, 0.0, 0.4)
	await assert_error(func() -> void: v.set_live_mass(v.mass + 100.0, moved)) \
		.is_push_error("%s declares yaw_dynamic_index: a live centre of mass cannot be expressed"
				% v.name)
	assert_vector(v.center_of_mass).is_equal(v.spec.center_of_mass)
	assert_float(v.mass).is_equal_approx(v.spec.mass + 100.0, 1e-3)


func test_the_tensor_scales_with_a_runtime_mass_rewrite() -> void:
	# The refuse truck rewrites `mass` when the hopper fills (truck.gd, through
	# BaseVehicle.set_live_mass). The computed tensor follows it on its own, which is the
	# other half of why no vehicle needs an explicit roll or pitch `inertia`.
	var v := await _spawn("sedan", LOW)
	var unladen := _inertia(v)
	v.set_live_mass(v.mass * 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var laden := _inertia(v)
	assert_float(laden.x / unladen.x).is_equal_approx(2.0, 1e-3)
	assert_float(laden.y / unladen.y).is_equal_approx(2.0, 1e-3)
	assert_float(laden.z / unladen.z).is_equal_approx(2.0, 1e-3)
	# The setter's other half: the one-tick clamps are re-sized in the same call.
	for w in v.wheels:
		assert_float(w.corner_mass).override_failure_message(
				"set_live_mass left a corner sized for the old mass") \
				.is_equal_approx(v.mass / float(v.wheels.size()), 1e-6)


# --- angular damping: declared on the wheeled bodies, the engine's elsewhere ------------------

## A shipped scene, as built (no spec override), stepped into the space.
func _spawn_as_built(path: String) -> RigidBody3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var b := (load(path) as PackedScene).instantiate() as RigidBody3D
	if b is BaseVehicle:
		(b as BaseVehicle).display_only = true
	root.add_child(b)
	b.global_position = Vector3(0.0, 50.0, 0.0)
	await get_tree().physics_frame
	return b


func test_a_wheeled_body_and_a_trailer_declare_no_angular_damping() -> void:
	for path in [VehicleCatalog.scene_of("sedan"), "res://src/vehicles/truck/trailers/box.tscn"]:
		var b := await _spawn_as_built(path)
		assert_int(b.angular_damp_mode).override_failure_message(path) \
				.is_equal(RigidBody3D.DAMP_MODE_REPLACE)
		assert_float(b.angular_damp).override_failure_message(path).is_equal(0.0)


func test_a_declared_figure_is_the_whole_damping() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var v := (load(VehicleCatalog.scene_of("sedan")) as PackedScene).instantiate() as BaseVehicle
	v.spec = v.spec.duplicate(true)
	v.spec.angular_damping = 0.5
	v.display_only = true
	root.add_child(v)
	assert_int(v.angular_damp_mode).is_equal(RigidBody3D.DAMP_MODE_REPLACE)
	assert_float(v.angular_damp).is_equal(0.5)


func test_the_plane_and_a_boat_keep_the_engine_default() -> void:
	for variant in ["plane", "boat-speed-a"]:
		var b := await _spawn_as_built(VehicleCatalog.scene_of(variant))
		assert_int(b.angular_damp_mode).override_failure_message(variant) \
				.is_equal(RigidBody3D.DAMP_MODE_COMBINE)
