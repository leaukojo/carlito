extends GdUnitTestSuite
## Overturned is a DETECTED STATE with a notice, never an auto-reset: the raised centre of mass
## makes rollover a real outcome, and an automatic respawn would hide the thing that just
## happened. What this pins is the wiring — the tilt maths itself is `test_vehicle_math.gd`.
##
## Nothing here asserts a telemetry field on purpose: the state is deliberately local, so the
## frozen `status` bitfield and the contract stay put.

const DELTA := 1.0 / 60.0

## Past BaseVehicle.OVERTURNED_DEG with room to spare, and on its side rather than its roof, which
## is the shape a real rollover leaves.
const ON_ITS_SIDE := 100.0


func _spawn() -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	# Frozen: this suite poses the body by hand and ticks the check, so gravity must not drag it
	# below FALL_RESPAWN_Y and respawn it out from under the assertion.
	var vehicle := (load(VehicleCatalog.scene_of("sedan")) as PackedScene).instantiate() as BaseVehicle
	root.add_child(vehicle)
	await get_tree().physics_frame
	vehicle.freeze = true
	vehicle.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	vehicle.spawn_transform = vehicle.global_transform
	return vehicle


static func _lay_on_side(v: BaseVehicle) -> void:
	v.global_transform = Transform3D(
			Basis(Vector3(0, 0, -1), deg_to_rad(ON_ITS_SIDE)), v.global_position)


static func _stand_up(v: BaseVehicle) -> void:
	v.global_transform = Transform3D(Basis.IDENTITY, v.global_position)


## Ticks the detector directly rather than waiting on the physics loop: the pose is imposed, so
## the only thing under test is the dwell.
static func _tick(v: BaseVehicle, seconds: float) -> void:
	for _i in int(round(seconds / DELTA)):
		v._tick_overturned(DELTA)


func test_a_body_on_its_side_latches_only_after_the_dwell() -> void:
	var v := await _spawn()
	assert_bool(v.is_overturned()).is_false()
	_lay_on_side(v)
	_tick(v, BaseVehicle.OVERTURNED_S * 0.5)
	assert_bool(v.is_overturned()).is_false()  # a kerb strike or a jump is not a rollover
	_tick(v, BaseVehicle.OVERTURNED_S * 0.6)
	assert_bool(v.is_overturned()).is_true()


func test_righting_the_body_clears_it_with_no_respawn() -> void:
	var v := await _spawn()
	_lay_on_side(v)
	_tick(v, BaseVehicle.OVERTURNED_S + DELTA)
	assert_bool(v.is_overturned()).is_true()
	var pose := v.global_transform
	_stand_up(v)
	_tick(v, DELTA)
	assert_bool(v.is_overturned()).is_false()
	# The dwell starts over rather than resuming where it left off.
	v.global_transform = pose
	_tick(v, BaseVehicle.OVERTURNED_S * 0.5)
	assert_bool(v.is_overturned()).is_false()


func test_a_lean_short_of_the_threshold_never_latches() -> void:
	var v := await _spawn()
	v.global_transform = Transform3D(
			Basis(Vector3(0, 0, -1), deg_to_rad(BaseVehicle.OVERTURNED_DEG - 15.0)),
			v.global_position)
	_tick(v, BaseVehicle.OVERTURNED_S * 3.0)
	assert_bool(v.is_overturned()).is_false()


func test_respawn_hands_back_a_body_that_is_not_overturned() -> void:
	var v := await _spawn()
	_lay_on_side(v)
	_tick(v, BaseVehicle.OVERTURNED_S + DELTA)
	assert_bool(v.is_overturned()).is_true()
	v.respawn()
	assert_bool(v.is_overturned()).is_false()


func test_the_notice_is_raised_once_and_cleared_by_the_exact_text() -> void:
	var v := await _spawn()
	var raised: Array[String] = []
	var cleared: Array[String] = []
	var on_raise := func(text: String, _dwell: float) -> void: raised.append(text)
	var on_clear := func(text: String) -> void: cleared.append(text)
	GameState.notice.connect(on_raise)
	GameState.notice_cleared.connect(on_clear)
	_lay_on_side(v)
	_tick(v, BaseVehicle.OVERTURNED_S * 3.0)
	# An edge latch, not a per-tick emit: a notice re-shown every tick restarts its own dwell.
	assert_array(raised).contains_exactly([BaseVehicle.OVERTURNED_NOTICE])
	assert_array(cleared).is_empty()
	_stand_up(v)
	_tick(v, BaseVehicle.OVERTURNED_S * 3.0)
	assert_array(cleared).contains_exactly([BaseVehicle.OVERTURNED_NOTICE])
	assert_array(raised).contains_exactly([BaseVehicle.OVERTURNED_NOTICE])
	# GameState is an autoload and outlives the suite, so the listeners come off again.
	GameState.notice.disconnect(on_raise)
	GameState.notice_cleared.disconnect(on_clear)


func test_a_preview_body_never_shouts_at_the_driver() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var v := (load(VehicleCatalog.scene_of("sedan")) as PackedScene).instantiate() as BaseVehicle
	v.display_only = true  # set before entering the tree, as the selector and the thumb tool do
	root.add_child(v)
	await get_tree().physics_frame
	v.freeze = true
	_lay_on_side(v)
	_tick(v, BaseVehicle.OVERTURNED_S * 3.0)
	assert_bool(v.is_overturned()).is_false()
