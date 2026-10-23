extends GdUnitTestSuite
## Ackermann steering: `WheelDrive.ackermann_angle`, each steered wheel's angle off the bicycle
## angle, pure statics; then roll steer (`RayWheel.roll_steer`), the angle each axle adds off its
## own suspension roll, and the rear's compliance steer (`RayWheel.compliance_steer`) off its side
## force. The per-body domain check lives in test_vehicle_catalog.

const WheelDriveScript := preload("res://src/vehicles/base/wheel_drive.gd")

## `sedan`: track 1.264 m (t / L 0.80), wheelbase 1.58 m.
const SEDAN_L := 1.58
const SEDAN_HALF_TRACK := 0.632


func test_parallel_steer_returns_the_mean_for_any_offset() -> void:
	for x in [-0.9, -0.3, 0.4, 1.2]:
		assert_float(WheelDriveScript.ackermann_angle(0.5, x, 2.0, 0.0)).is_equal(0.5)


func test_a_centred_wheel_and_a_straight_rack_are_untouched() -> void:
	assert_float(WheelDriveScript.ackermann_angle(0.5, 0.0, 2.0, 1.0)).is_equal(0.5)
	assert_float(WheelDriveScript.ackermann_angle(0.0, 0.7, 2.0, 1.0)).is_equal(0.0)


func test_full_ackermann_puts_both_wheels_on_one_centre() -> void:
	var mean := deg_to_rad(30.0)
	var left := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	var right := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	# The centre's distance left of the body axis, read from each wheel: L cot δ_w - x.
	assert_float(SEDAN_L / tan(left) + SEDAN_HALF_TRACK).is_equal_approx(
			SEDAN_L / tan(right) - SEDAN_HALF_TRACK, 1e-4)


func test_sedan_full_lock_splits_to_the_computed_pair() -> void:
	var mean := deg_to_rad(38.0)
	var inner := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	var outer := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	assert_float(rad_to_deg(inner)).is_equal_approx(48.6, 0.1)
	assert_float(rad_to_deg(outer)).is_equal_approx(30.8, 0.1)


func test_any_fraction_orders_the_pair_mirrors_it_and_keeps_the_cotangent_mean() -> void:
	for f in [0.25, 0.6, 1.0]:
		for mean_deg in [5.0, 20.0, 38.0]:
			var mean := deg_to_rad(mean_deg)
			# A left turn (+): the left wheel (x < 0) is the inner one.
			var inner := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, f)
			var outer := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, f)
			assert_float(inner).is_greater(mean)
			assert_float(outer).is_less(mean)
			# Mirrored: a right turn swaps the wheels.
			assert_float(WheelDriveScript.ackermann_angle(-mean, SEDAN_HALF_TRACK, SEDAN_L, f)) \
					.is_equal_approx(-inner, 1e-6)
			assert_float(WheelDriveScript.ackermann_angle(-mean, -SEDAN_HALF_TRACK, SEDAN_L, f)) \
					.is_equal_approx(-outer, 1e-6)
			assert_float((1.0 / tan(inner) + 1.0 / tan(outer)) / 2.0).is_equal_approx(
					1.0 / tan(mean), 1e-5)


# --- roll steer: an angle off the axle's suspension roll, added after the split ----------------

## On the sedan's track, the right wheel 2 cm deeper than the left: the axle rolled right (a left
## turn) by atan(0.02 / 1.264).
const RS_LEFT := 0.050
const RS_RIGHT := 0.070


## `RayWheel.roll_steer_angle` for a wheel at `x_self` and its partner mirrored across the axle.
func _rs(comp_self: float, comp_partner: float, x_self: float, coeff: float, rear: bool) -> float:
	return RayWheel.roll_steer_angle(comp_self, comp_partner, x_self, -x_self, coeff, rear)


func test_a_zero_coefficient_steers_nothing_whatever_the_roll() -> void:
	for rear in [false, true]:
		assert_float(_rs(RS_LEFT, RS_RIGHT, -SEDAN_HALF_TRACK, 0.0, rear)).is_equal(0.0)


func test_rolled_right_steers_the_front_right_and_the_rear_left() -> void:
	# A left turn rolls the body right: understeer steers the front out of it (right, -) and the
	# rear into it (left, +), read the same off either wheel of the axle.
	for x: float in [-SEDAN_HALF_TRACK, SEDAN_HALF_TRACK]:
		var mine := RS_LEFT if x < 0.0 else RS_RIGHT
		var theirs := RS_RIGHT if x < 0.0 else RS_LEFT
		assert_float(_rs(mine, theirs, x, 0.2, false)).is_less(0.0)
		assert_float(_rs(mine, theirs, x, 0.1, true)).is_greater(0.0)


func test_pure_heave_steers_nothing() -> void:
	assert_float(_rs(0.06, 0.06, -SEDAN_HALF_TRACK, 0.2, false)).is_equal(0.0)
	assert_float(_rs(0.06, 0.06, SEDAN_HALF_TRACK, 0.1, true)).is_equal(0.0)


func test_the_angle_is_the_coefficient_times_the_axle_roll() -> void:
	var phi := atan((RS_RIGHT - RS_LEFT) / (2.0 * SEDAN_HALF_TRACK))
	assert_float(_rs(RS_LEFT, RS_RIGHT, -SEDAN_HALF_TRACK, 0.2, false)).is_equal_approx(-0.2 * phi,
			1e-12)
	assert_float(_rs(RS_RIGHT, RS_LEFT, SEDAN_HALF_TRACK, 0.13, true)).is_equal_approx(0.13 * phi,
			1e-12)


## A 2000 kg four-wheeler on the sedan's track, front steered, roll steer on both axles, rear
## compliance steer `compliance` (deg/kN) and an anti-roll bar of `bar` N/m on both (0: none).
func _rs_drive(front: float, rear: float, compliance := 0.0, bar := 0.0) -> WheelDrive:
	var gd := GroundDriveSpec.new()
	gd.wheel_positions = [
		Vector3(-SEDAN_HALF_TRACK, 0.0, -0.79), Vector3(SEDAN_HALF_TRACK, 0.0, -0.79),
		Vector3(-SEDAN_HALF_TRACK, 0.0, 0.79), Vector3(SEDAN_HALF_TRACK, 0.0, 0.79),
	]
	gd.ackermann = 1.0
	gd.roll_steer_front = front
	gd.roll_steer_rear = rear
	gd.compliance_steer_rear = compliance
	gd.anti_roll_rate = bar
	var spec := VehicleSpec.new()
	spec.mass = 2000.0
	spec.ground_drive = gd
	return WheelDrive.new(auto_free(Node3D.new()), spec)


## Rolled right off one shared latch, then each wheel writes this tick's compression as it ticks.
func _roll_and_latch(drive: WheelDrive) -> void:
	for w in drive.wheels:
		w.compression = RS_LEFT if w.anchor.x < 0.0 else RS_RIGHT
	for w in drive.wheels:
		w.latch_bar()


func test_both_wheels_of_an_axle_take_one_increment_whichever_ticks_first() -> void:
	var drive := _rs_drive(0.2, 0.1)
	_roll_and_latch(drive)
	var latched := PackedFloat64Array()
	for w in drive.wheels:
		latched.append(w.roll_steer())
	drive.wheels[0].compression += 0.01  # the first wheel ticks and writes its live compression
	for i in drive.wheels.size():
		var w: RayWheel = drive.wheels[i]
		assert_float(w.roll_steer()).is_equal(latched[i])
		assert_float(w.roll_steer()).is_equal(w.anti_roll_partner.roll_steer())


func test_a_lifted_partner_reads_full_droop() -> void:
	# Roll steer is the links' kinematics: with no bar the airborne wheel hangs at full droop (its
	# ray's 0), and the axle steers off that.
	var drive := _rs_drive(0.2, 0.0)
	var left: RayWheel = drive.wheels[0]
	var right: RayWheel = left.anti_roll_partner
	left.in_contact = true
	left.compression = RS_LEFT
	right.in_contact = false
	right.compression = 0.0
	left.latch_bar()
	right.latch_bar()
	assert_float(left.roll_steer()).is_equal_approx(
			-0.2 * atan(-RS_LEFT / (2.0 * SEDAN_HALF_TRACK)), 1e-7)  # float32 anchors
	assert_float(left.bar_force(left.bar_rate)).is_equal(0.0)


## On a bar the unloaded wheel's link hangs where its spring balances the bar
## (`VehicleMath.anti_roll_hang`), touching or airborne, and both wheels still take one angle.
func test_a_lifted_partner_on_a_bar_reads_its_hang() -> void:
	var drive := _rs_drive(0.2, 0.0, 0.0, 7000.0)
	var left: RayWheel = drive.wheels[0]
	var right: RayWheel = left.anti_roll_partner
	var hang := VehicleMath.anti_roll_hang(RS_LEFT, 7000.0, right.spring_rate)
	var expected := -0.2 * atan(-(RS_LEFT - hang) / (2.0 * SEDAN_HALF_TRACK))
	for touching: float in [0.0, hang * 0.5]:
		left.compression = RS_LEFT
		right.compression = touching
		right.in_contact = touching > 0.0
		left.latch_bar()
		right.latch_bar()
		assert_float(left.roll_steer()).is_equal_approx(expected, 1e-7)  # float32 anchors
		assert_float(right.roll_steer()).is_equal(left.roll_steer())


func test_roll_steer_alone_pairs_the_axles_with_no_bar_force() -> void:
	var drive := _rs_drive(0.0, 0.1)
	for w in drive.wheels:
		w.in_contact = true
		assert_object(w.anti_roll_partner).is_not_null()
	_roll_and_latch(drive)
	for w in drive.wheels:
		assert_float(w.bar_force(w.bar_rate)).is_equal(0.0)


func test_each_wheel_angle_is_the_split_plus_its_roll_steer() -> void:
	var drive := _rs_drive(0.2, 0.1)
	var spec_gd := GroundDriveSpec.new()
	spec_gd.ackermann = 1.0
	drive._applied_steer = deg_to_rad(10.0)
	_roll_and_latch(drive)
	var phi := atan((RS_RIGHT - RS_LEFT) / (2.0 * SEDAN_HALF_TRACK))
	for w in drive.wheels:
		var split := WheelDriveScript.ackermann_angle(drive.mean_steer_angle(), w.anchor.x,
				drive._wheelbase, 1.0) if w.steered else 0.0
		var expected := split + (0.1 * phi if w.is_rear else -0.2 * phi)
		# float32 anchors
		assert_float(drive.wheel_steer_angle(w, spec_gd)).is_equal_approx(expected, 1e-7)
	# The driver's angle never carries it.
	assert_float(drive.mean_steer_angle()).is_equal(deg_to_rad(10.0))


func test_with_no_roll_steer_each_wheel_angle_is_the_split_bit_for_bit() -> void:
	var drive := _rs_drive(0.0, 0.0)
	var spec_gd := GroundDriveSpec.new()
	spec_gd.ackermann = 1.0
	drive._applied_steer = deg_to_rad(17.0)
	_roll_and_latch(drive)
	for w in drive.wheels:
		var split := WheelDriveScript.ackermann_angle(drive.mean_steer_angle(), w.anchor.x,
				drive._wheelbase, 1.0) if w.steered else 0.0
		assert_float(drive.wheel_steer_angle(w, spec_gd)).is_equal(split)


# --- compliance steer (`RayWheel.compliance_steer`) -------------------------------------------------

## A left turn's tyre forces on the sedan's rear (N, + = right): the outer (right) wheel carries more.
const CS_LEFT := -900.0
const CS_RIGHT := -1700.0


## Each wheel's side force as a left turn leaves it, then one shared latch.
func _push_and_latch(drive: WheelDrive) -> void:
	for w in drive.wheels:
		w.in_contact = true
		w.force_lat = CS_LEFT if w.anchor.x < 0.0 else CS_RIGHT
	for w in drive.wheels:
		w.latch_bar()


func test_a_zero_coefficient_complies_nothing_whatever_the_force() -> void:
	assert_float(RayWheel.compliance_steer_angle(CS_LEFT, CS_RIGHT, 0.0)).is_equal(0.0)


func test_with_no_compliance_steer_each_angle_is_the_split_plus_its_roll_steer_bit_for_bit() -> void:
	var drive := _rs_drive(0.2, 0.1)
	var spec_gd := GroundDriveSpec.new()
	spec_gd.ackermann = 1.0
	drive._applied_steer = deg_to_rad(10.0)
	_roll_and_latch(drive)
	_push_and_latch(drive)
	for w in drive.wheels:
		assert_float(w.compliance_steer()).is_equal(0.0)
		var split := WheelDriveScript.ackermann_angle(drive.mean_steer_angle(), w.anchor.x,
				drive._wheelbase, 1.0) if w.steered else 0.0
		assert_float(drive.wheel_steer_angle(w, spec_gd)).is_equal(split + w.roll_steer())


func test_a_leftward_force_steers_an_understeering_rear_left_into_the_turn() -> void:
	# `force_lat` is + = right (`side = forward x normal`): a left turn pushes the body left (< 0),
	# and + `coeff` steers the rear into it (left, +); the stock sign (-) steers it out.
	assert_float(RayWheel.compliance_steer_angle(CS_LEFT, CS_RIGHT, 0.06)).is_greater(0.0)
	assert_float(RayWheel.compliance_steer_angle(CS_LEFT, CS_RIGHT, -0.06)).is_less(0.0)


func test_the_angle_is_the_coefficient_per_kn_of_half_the_axles_force() -> void:
	var half := (CS_LEFT + CS_RIGHT) / 2.0
	assert_float(RayWheel.compliance_steer_angle(CS_LEFT, CS_RIGHT, 0.0625)).is_equal_approx(
			-deg_to_rad(0.0625) * half / 1000.0, 1e-12)


func test_a_lifted_partner_adds_nothing_and_the_total_is_still_halved() -> void:
	# The inner wheel off the ground carries no force (`force_lat` 0, latched as 0): the outer's force
	# alone, over two, as the both-wheels-loaded figure reads the axle's total.
	var drive := _rs_drive(0.0, 0.0, 0.0625)
	var outer: RayWheel = drive.wheels[3]
	var inner: RayWheel = outer.anti_roll_partner
	outer.in_contact = true
	outer.force_lat = CS_RIGHT
	inner.in_contact = false
	inner.force_lat = 0.0
	outer.latch_bar()
	inner.latch_bar()
	var expected := -deg_to_rad(0.0625) * CS_RIGHT / 2.0 / 1000.0
	assert_float(outer.compliance_steer()).is_equal_approx(expected, 1e-12)
	assert_float(inner.compliance_steer()).is_equal_approx(expected, 1e-12)


func test_both_rear_wheels_take_one_compliance_angle_whichever_ticks_first() -> void:
	var drive := _rs_drive(0.0, 0.0, 0.0625)
	_push_and_latch(drive)
	var latched := PackedFloat64Array()
	for w in drive.wheels:
		latched.append(w.compliance_steer())
	drive.wheels[2].force_lat += 400.0  # the first rear wheel ticks and writes its live force
	for i in drive.wheels.size():
		var w: RayWheel = drive.wheels[i]
		assert_float(w.compliance_steer()).is_equal(latched[i])
		assert_float(w.compliance_steer()).is_equal(w.anti_roll_partner.compliance_steer())


func test_the_front_never_complies() -> void:
	var drive := _rs_drive(0.0, 0.0, 0.0625)
	_push_and_latch(drive)
	for w in drive.wheels:
		if w.is_rear:
			assert_float(w.compliance_steer()).is_not_equal(0.0)
		else:
			assert_float(w.compliance_steer_coeff).is_equal(0.0)
			assert_float(w.compliance_steer()).is_equal(0.0)


func test_compliance_steer_alone_pairs_the_axles_and_reaches_the_rear_angle() -> void:
	var drive := _rs_drive(0.0, 0.0, 0.0625)
	var spec_gd := GroundDriveSpec.new()
	spec_gd.ackermann = 1.0
	_push_and_latch(drive)
	var expected := RayWheel.compliance_steer_angle(CS_LEFT, CS_RIGHT, 0.0625)
	for w in drive.wheels:
		assert_object(w.anti_roll_partner).is_not_null()
		assert_float(w.bar_force(w.bar_rate)).is_equal(0.0)
		if w.is_rear:
			assert_float(drive.wheel_steer_angle(w, spec_gd)).is_equal(expected)
	# The driver's angle never carries it.
	assert_float(drive.mean_steer_angle()).is_equal(0.0)
