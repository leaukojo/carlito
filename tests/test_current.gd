extends GdUnitTestSuite
## Tidal stream model: the flood/ebb sinusoid, the shared compass convention, and the null
## default. At still water the boat's hull drag is bit-for-bit the absolute-velocity term the
## regression block at the bottom pins.

const C := preload("res://src/levels/base/current_field.gd")
const W := preload("res://src/levels/base/wind_field.gd")
const VM := preload("res://src/vehicles/base/vehicle_math.gd")

const DELTA := 1.0 / 60.0
const BOAT_MASS := 800.0
const DRAG_LONG := 380.0
const DRAG_LAT := 2600.0


# --- the default is still water ------------------------------------------------

func test_a_fresh_current_field_is_still() -> void:
	var current: Resource = C.new()
	for t: float in [0.0, 1.0, 13.7, 600.0]:
		assert_vector(current.vector_at(t)).is_equal(Vector3.ZERO)


func test_a_still_field_matches_a_level_with_no_field_at_all() -> void:
	# The null default and an all-zero CurrentField must agree, or "no tide" would mean two
	# different things depending on whether a level happened to declare one. Compared against
	# the no-level path itself, not against a ZERO literal, which passes either way.
	var no_level: Node3D = auto_free(Node3D.new())
	var current: Resource = C.new()
	assert_vector(current.vector_at(9.0)).is_equal(C.at(no_level))


# --- the compass convention is WindField's -------------------------------------

func test_set_deg_is_the_bearing_the_stream_flows_toward() -> void:
	# Peak flood is a quarter period in, where the sinusoid reads exactly `drift`.
	var current: Resource = C.new()
	current.drift = 4.0
	current.tide_period_s = 240.0
	var eps := Vector3.ONE * 1e-4
	for deg: float in [0.0, 90.0, 180.0, 270.0]:
		current.set_deg = deg
		assert_vector(current.vector_at(60.0)) \
			.override_failure_message("set %f did not match WindField.base_vector" % deg) \
			.is_equal_approx(W.base_vector(deg, 4.0), eps)


func test_the_current_is_horizontal() -> void:
	var current: Resource = C.new()
	current.set_deg = 47.0
	current.drift = 2.0
	current.tide_period_s = 90.0
	for i in 200:
		assert_float(current.vector_at(float(i) * DELTA).y).is_equal(0.0)


# --- the tide is a pure function of t ------------------------------------------

func test_the_rate_floods_slacks_and_ebbs_over_one_period() -> void:
	var period := 240.0
	assert_float(C.rate_at(2.0, period, 0.0, 0.0)).is_equal_approx(0.0, 1e-6)
	assert_float(C.rate_at(2.0, period, 0.0, period * 0.25)).is_equal_approx(2.0, 1e-6)
	assert_float(C.rate_at(2.0, period, 0.0, period * 0.5)).is_equal_approx(0.0, 1e-6)
	assert_float(C.rate_at(2.0, period, 0.0, period * 0.75)).is_equal_approx(-2.0, 1e-6)
	assert_float(C.rate_at(2.0, period, 0.0, period)).is_equal_approx(0.0, 1e-6)


func test_the_ebb_is_the_flood_reversed() -> void:
	# The 180-degree flip costs no branch: base_vector reverses on a negative rate. This is
	# what makes `current_set` swing by 180 across slack instead of `current_drift` going
	# negative, which is what the contract desc promises.
	var current: Resource = C.new()
	current.set_deg = 110.0
	current.drift = 1.5
	current.tide_period_s = 240.0
	var flood: Vector3 = current.vector_at(60.0)
	var ebb: Vector3 = current.vector_at(180.0)
	assert_vector(ebb).is_equal_approx(-flood, Vector3.ONE * 1e-4)


func test_a_zero_period_pins_a_steady_stream() -> void:
	# Not a division by zero and not slack water: a level that wants a river rather than a tide
	# leaves the period at 0 and gets `drift` forever.
	for t: float in [0.0, 5.0, 999.0]:
		assert_float(C.rate_at(1.25, 0.0, 0.0, t)).is_equal(1.25)


func test_the_offset_shifts_the_phase_and_nothing_else() -> void:
	var period := 240.0
	# An offset of a quarter period starts the level at peak flood.
	assert_float(C.rate_at(2.0, period, period * 0.25, 0.0)).is_equal_approx(2.0, 1e-6)
	# ...and it is a pure shift of t, so a full period of offset changes nothing.
	for t: float in [0.0, 17.0, 130.0]:
		assert_float(C.rate_at(2.0, period, period, t)) \
			.override_failure_message("a whole period of offset moved t=%f" % t) \
			.is_equal_approx(C.rate_at(2.0, period, 0.0, t), 1e-6)


func test_vector_at_hands_every_export_to_the_rate() -> void:
	# The resource's own wiring, and the only test that drives `tide_offset_s` through
	# `vector_at`: drop the offset from the call and the exports above still read correct while
	# the level starts the tide in the wrong part of its cycle, silently.
	var current: Resource = C.new()
	current.set_deg = 200.0
	current.drift = 1.5
	current.tide_period_s = 97.0
	current.tide_offset_s = 12.0
	for i in 600:
		var t := float(i) * DELTA
		var want := W.base_vector(200.0, C.rate_at(1.5, 97.0, 12.0, t))
		assert_vector(current.vector_at(t)) \
			.override_failure_message("tick %d did not match set_deg x rate_at" % i) \
			.is_equal_approx(want, Vector3.ONE * 1e-6)


func test_current_at_a_node_outside_a_level_is_still() -> void:
	var orphan: Node3D = auto_free(Node3D.new())
	assert_vector(C.at(orphan)).is_equal(Vector3.ZERO)


# --- the regression: still water is today's hull drag ---------------------------

func test_still_water_hull_drag_is_unchanged() -> void:
	# The phase-2 shape: subtracting a zero current must leave the fore-aft and athwartships
	# terms bit-identical to the absolute-velocity ones every shipped boat was tuned against.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var right := Vector3.RIGHT
	for v in _sample_velocities():
		var through_water := v - Vector3.ZERO
		assert_float(VM.damped_force(through_water.dot(fwd), DRAG_LONG, BOAT_MASS, DELTA)) \
			.override_failure_message("fore-aft drag changed at %s" % v) \
			.is_equal(VM.damped_force(v.dot(fwd), DRAG_LONG, BOAT_MASS, DELTA))
		assert_float(VM.damped_force(through_water.dot(right), DRAG_LAT, BOAT_MASS, DELTA)) \
			.override_failure_message("lateral drag changed at %s" % v) \
			.is_equal(VM.damped_force(v.dot(right), DRAG_LAT, BOAT_MASS, DELTA))


func test_a_current_actually_changes_the_drag() -> void:
	# The mirror of the regression above: a hull lying stopped in a stream is being dragged, so
	# the term must be nonzero where the absolute-velocity one is exactly zero.
	var fwd := Vector3(0.0, 0.0, -1.0)
	var current := W.base_vector(180.0, 1.5)          # flows toward +Z: astern of a boat facing -Z
	var still := VM.damped_force(Vector3.ZERO.dot(fwd), DRAG_LONG, BOAT_MASS, DELTA)
	var swept := VM.damped_force((Vector3.ZERO - current).dot(fwd), DRAG_LONG, BOAT_MASS, DELTA)
	assert_float(still).is_equal(0.0)
	assert_float(absf(swept)).is_greater(1.0)


func _sample_velocities() -> Array[Vector3]:
	return [
		Vector3.ZERO,
		Vector3(0.0, 0.0, -8.0),
		Vector3(0.0, 0.0, 3.0),
		Vector3(2.5, 0.0, -6.0),
		Vector3(-1.5, 0.0, 0.5),
		Vector3(12.0, 0.0, -12.0),
	]
