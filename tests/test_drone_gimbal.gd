extends GdUnitTestSuite
## Drone camera gimbal: slew limit, mount basis. Pure statics, no scene.

const G := preload("res://src/vehicles/drone/drone_gimbal.gd")

const LO := -90.0
const HI := 30.0

# --- the slew limit -----------------------------------------------------------

func test_a_step_command_walks_at_the_mounts_own_rate() -> void:
	var tick1 := G.slew(0.0, -90.0, 60.0, 1.0 / 60.0, LO, HI)
	assert_float(tick1).is_equal_approx(-1.0, 1e-5)
	assert_float(G.slew(tick1, -90.0, 60.0, 1.0 / 60.0, LO, HI)).is_equal_approx(-2.0, 1e-5)


func test_it_arrives_and_then_stops_rather_than_overshooting() -> void:
	# One second at 60 deg/s covers 60 degrees, so a 10 degree command must land ON 10 and not
	# 60 past it — the clamp is on the STEP, not a sign.
	assert_float(G.slew(0.0, 10.0, 60.0, 1.0, LO, HI)).is_equal_approx(10.0, 1e-5)
	assert_float(G.slew(10.0, 10.0, 60.0, 1.0, LO, HI)).is_equal_approx(10.0, 1e-5)


func test_it_slews_both_ways_at_the_same_rate() -> void:
	assert_float(G.slew(0.0, 30.0, 60.0, 0.1, LO, HI)).is_equal_approx(6.0, 1e-5)
	assert_float(G.slew(0.0, -30.0, 60.0, 0.1, LO, HI)).is_equal_approx(-6.0, 1e-5)

# --- the stops ----------------------------------------------------------------

func test_a_command_past_a_stop_sits_on_the_stop() -> void:
	# It is a MOUNT, not a clamp on a number: the command is clamped to the travel and then
	# walked to, so a command far past a stop still takes the full time to get there.
	assert_float(G.slew(0.0, -500.0, 60.0, 10.0, LO, HI)).is_equal(LO)
	assert_float(G.slew(0.0, 500.0, 60.0, 10.0, LO, HI)).is_equal(HI)


func test_an_actual_outside_the_travel_is_pulled_back_inside_it() -> void:
	# A stop that moved (a contract edit narrowing the range) must not leave the mount parked
	# outside its own travel for ever.
	assert_float(G.slew(120.0, 0.0, 60.0, 0.0, LO, HI)).is_equal(HI)


func test_a_zero_length_tick_moves_nothing() -> void:
	# The measure tools and the editor both hand out a zero delta on the first frame.
	assert_float(G.slew(-12.0, 30.0, 60.0, 0.0, LO, HI)).is_equal(-12.0)
	assert_float(G.slew(-12.0, 30.0, 60.0, -1.0, LO, HI)).is_equal(-12.0)

# --- the mount's basis --------------------------------------------------------

func test_the_rest_pose_is_the_identity_basis() -> void:
	# The neutral pose agrees with every other view, so switching into HOOD is not disorienting.
	assert_bool(G.basis_of(G.REST_PITCH, G.REST_YAW).is_equal_approx(Basis.IDENTITY)).is_true()


func test_pitch_is_up_and_yaw_is_right() -> void:
	# The camera looks down -Z (Godot's forward). Tilting UP must raise where it points, and
	# panning right must swing it toward +X.
	var up := G.basis_of(45.0, 0.0) * Vector3.FORWARD
	assert_float(up.y).is_greater(0.0)
	var right := G.basis_of(0.0, -90.0) * Vector3.FORWARD
	assert_float(right.x).is_greater(0.0)


func test_yaw_is_applied_first_so_a_panned_tilt_keeps_the_horizon_level() -> void:
	# "Pan, then tilt" — the reverse order tilts the pan axis over with the camera and the
	# horizon rolls. With yaw first the mount's own right axis stays horizontal at any pan.
	var right_axis := G.basis_of(-40.0, 70.0).x
	assert_float(absf(right_axis.y)).is_less(1e-5)
