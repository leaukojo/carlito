extends GdUnitTestSuite
## No vehicle sets `RigidBody3D.inertia`, and none needs to: Jolt computes the tensor off the
## collision shapes ABOUT THE DECLARED CENTRE OF MASS, not about the shape centroid. That is the
## whole reason the COM heights can be raised as a data change. This suite is the guard on that
## engine behaviour — a Godot or Jolt upgrade that quietly moved the tensor back to the centroid
## would leave every raised body rolling about a point below its own mass, with nothing to see.
##
## Read the tensor through `PhysicsDirectBodyState3D.inverse_inertia` and nothing else:
## `RigidBody3D.inertia` and `PhysicsServer3D.body_get_param(..., BODY_PARAM_INERTIA)` are the
## OVERRIDE, and both read back Vector3.ZERO on a body whose tensor is computed.

const Layers := preload("res://src/physics/collision_layers.gd")

## Sedan COM heights either side of its collision hull's own mass centroid (~0.79 m body space).
const LOW := 0.20
const MID := 0.79
const HIGH := 1.40


func _spawn(variant: String, com_y: float) -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var v := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate() as BaseVehicle
	# The spec is a shared Resource loaded off the .tres, so it is duplicated before the override
	# — nothing here is written back to the shipped vehicle.
	v.spec = v.spec.duplicate(true)
	v.spec.center_of_mass = Vector3(v.spec.center_of_mass.x, com_y, v.spec.center_of_mass.z)
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


func test_the_override_is_never_the_way_to_read_the_tensor() -> void:
	var v := await _spawn("sedan", LOW)
	# Both of these are the override, and a vehicle sets neither. Reading them as "the inertia"
	# is the trap this suite exists to keep out of the next COM change.
	assert_vector(v.inertia).is_equal(Vector3.ZERO)
	assert_vector(PhysicsServer3D.body_get_param(
			v.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA)).is_equal(Vector3.ZERO)
	assert_vector(_inertia(v)).is_not_equal(Vector3.ZERO)


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
	# The sedan's collision is a pair of boxes; most Kenney bodies are convex hulls. Same rule.
	var mid := _inertia(await _spawn("garbage-truck", 1.20))
	var high := _inertia(await _spawn("garbage-truck", 2.20))
	assert_float(mid.z).is_less(high.z)
	assert_float(mid.y / high.y).is_between(0.95, 1.05)


func test_the_tensor_scales_with_a_runtime_mass_rewrite() -> void:
	# The refuse truck rewrites `mass` when the hopper fills (truck.gd, beside
	# WheelDrive.set_corner_mass_from). The computed tensor follows it on its own, which is the
	# other half of why no vehicle needs an explicit `inertia`.
	var v := await _spawn("sedan", LOW)
	var unladen := _inertia(v)
	v.mass *= 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var laden := _inertia(v)
	assert_float(laden.x / unladen.x).is_equal_approx(2.0, 1e-3)
	assert_float(laden.y / unladen.y).is_equal_approx(2.0, 1e-3)
	assert_float(laden.z / unladen.z).is_equal_approx(2.0, 1e-3)
