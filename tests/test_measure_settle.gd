extends GdUnitTestSuite
## `measure_vehicles.tail_settled`, the step pass's steady-tail gate: a held step's K is read only
## once its speed, body slip and yaw rate stop drifting.

const Measure := preload("res://tools/measure_vehicles.gd")
const DT := 1.0 / 60.0
const TICKS := 30
const YAW := 0.2  # rad/s


## A tail of `n` ticks: speed from 27 m/s at `accel`, beta from -0.06 rad at `beta_rate`, the yaw
## rate from YAW at `yaw_rate` (rad/s^2).
static func _tail(accel: float, beta_rate: float, yaw_rate: float,
		n := TICKS) -> Array[PackedFloat32Array]:
	var speed := PackedFloat32Array()
	var yaw := PackedFloat32Array()
	var beta := PackedFloat32Array()
	for i in n:
		speed.append(27.0 + accel * i * DT)
		beta.append(-0.06 + beta_rate * i * DT)
		yaw.append(YAW + yaw_rate * i * DT)
	return [speed, yaw, beta]


static func _settled(t: Array[PackedFloat32Array], ticks := TICKS) -> bool:
	return Measure.tail_settled(t[0], t[1], t[2], ticks, DT)


func test_a_steady_tail_is_settled() -> void:
	assert_bool(_settled(_tail(0.0, 0.0, 0.0))).is_true()


func test_a_speed_still_recovering_past_the_gate_is_not() -> void:
	# The PI pedal's 0.136 m/s^2 three seconds into `suv`'s 100 km/h step; half the gate passes.
	assert_bool(_settled(_tail(0.136, 0.0, 0.0))).is_false()
	assert_bool(_settled(_tail(Measure.STEP_SETTLE_ACCEL * 0.5, 0.0, 0.0))).is_true()


func test_a_drifting_slip_is_read_against_the_yaw_rate() -> void:
	# beta' / r: 0.0017 rad/s on 0.187 rad/s is 0.9 % of the side force, past the gate; a third of
	# the gate's share passes.
	assert_bool(_settled(_tail(0.0, 0.0017 * YAW / 0.187, 0.0))).is_false()
	assert_bool(_settled(_tail(0.0, Measure.STEP_SETTLE_SHARE * YAW / 3.0, 0.0))).is_true()


func test_a_drifting_yaw_rate_is_not_settled() -> void:
	# 1 % of the yaw rate across the tail's half second.
	assert_bool(_settled(_tail(0.0, 0.0, 0.02 * YAW))).is_false()


func test_only_the_last_ticks_are_judged() -> void:
	# A ramp that stops: the tail after it is settled, a window over it is not.
	var t := _tail(0.5, 0.0, 0.0, 60)
	for i in range(30, 60):
		t[0][i] = t[0][29]
	assert_bool(_settled(t, 30)).is_true()
	assert_bool(_settled(t, 60)).is_false()


func test_a_tail_too_short_or_without_yaw_is_not_settled() -> void:
	assert_bool(_settled(_tail(0.0, 0.0, 0.0, 2 * Measure.STEP_SETTLE_ENDS - 1),
			2 * Measure.STEP_SETTLE_ENDS - 1)).is_false()
	var still := _tail(0.0, 0.0, 0.0)
	still[1].fill(0.0)
	assert_bool(_settled(still)).is_false()


func test_an_unsettled_tail_names_each_failing_gate_with_its_reading() -> void:
	# The yaw rate drifting 2 %/s, the speed and slip steady: only the yaw gate fails, its ends' means
	# 24 ticks apart reading 0.8 %.
	var t := _tail(0.0, 0.0, 0.02 * YAW)
	var drift := Measure.tail_drift(t[0], t[1], t[2], TICKS, DT)
	assert_float(float(drift["yaw"])).is_equal_approx(0.008, 0.0001)
	var gates := Measure.unsettled_gates(drift)
	assert_str(gates).is_equal("yaw 0.80 % (gate 0.3)")
	# The PI pedal's 0.136 m/s^2 fails the speed gate alone.
	t = _tail(0.136, 0.0, 0.0)
	assert_str(Measure.unsettled_gates(Measure.tail_drift(t[0], t[1], t[2], TICKS, DT))) \
			.is_equal("speed 0.136 m/s^2 (gate 0.02)")


func test_a_settled_tail_names_no_gate_and_a_missing_one_says_so() -> void:
	var t := _tail(0.0, 0.0, 0.0)
	assert_str(Measure.unsettled_gates(Measure.tail_drift(t[0], t[1], t[2], TICKS, DT))).is_empty()
	assert_str(Measure.unsettled_gates({})).is_equal("no tail")
