extends GdUnitTestSuite
## `measure_vehicles.chatter_runs`, the step pass's roll-steer ringing probe: it counts a swing that
## scales with the angle, never the latched compressions' contact noise under it.

const Measure := preload("res://tools/measure_vehicles.gd")


## `n` ticks about `level` (rad), alternating by `swing` (rad) from the second tick on.
static func _alternating(level: float, swing: float, n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in n:
		out.append(level + (swing if i % 2 == 1 else 0.0))
	return out


func test_a_tick_rate_swing_past_the_floor_is_one_run() -> void:
	# 10 % of a 5 mrad angle, alternating for 10 ticks: one run of flips.
	assert_int(Measure.chatter_runs(_alternating(5e-3, 5e-4, 10))).is_equal(1)


func test_contact_noise_under_the_floor_is_no_run() -> void:
	# 2 µrad on 5 mrad, the size `sedan`'s steady tail flips at: under 1 % of the angle.
	assert_int(Measure.chatter_runs(_alternating(5e-3, 2e-6, 60))).is_equal(0)


func test_one_tick_blips_ticks_apart_are_no_run() -> void:
	# `taxi`'s steady tail: a 2.5 % blip and its return, then quiet ticks, then the next blip.
	var s := PackedFloat64Array()
	for i in 60:
		s.append(1.27e-3 + (3.1e-5 if i % 6 == 3 else 0.0))
	assert_int(Measure.chatter_runs(s)).is_equal(0)


func test_a_monotonic_build_is_no_run() -> void:
	var ramp := PackedFloat64Array()
	for i in 60:
		ramp.append(5e-3 * (1.0 - exp(-float(i) / 10.0)))
	assert_int(Measure.chatter_runs(ramp)).is_equal(0)


func test_two_flips_are_not_yet_a_run() -> void:
	# Up, down, up: two flips, one short of CHATTER_FLIPS.
	var s := PackedFloat64Array([5e-3, 5.5e-3, 5e-3, 5.5e-3])
	assert_int(Measure.chatter_runs(s)).is_equal(0)
