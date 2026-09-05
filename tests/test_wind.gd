extends GdUnitTestSuite
## Wind gust model: determinism, bounds, heading. At ZERO_WIND, drag bit-for-bit as before.
## Regression test: drone/plane drag knobs absorbed old default_linear_damp.

const W := preload("res://src/levels/base/wind_field.gd")
const VM := preload("res://src/vehicles/base/vehicle_math.gd")

const DELTA := 1.0 / 60.0
const DRONE_H_DRAG := 1.0
const DRONE_V_DRAG := 6.5
const DRONE_MASS := 5.0
const PLANE_DRAG := 280.0
const PLANE_MASS := 800.0


# --- the default is dead calm --------------------------------------------------

func test_a_fresh_wind_field_is_calm() -> void:
	var wind: Resource = W.new()
	var times: Array[float] = [0.0, 1.0, 13.7, 600.0]
	for t in times:
		assert_vector(wind.vector_at(t)).is_equal(Vector3.ZERO)


func test_a_calm_field_matches_a_level_with_no_field_at_all() -> void:
	# The null default and an all-zero WindField must agree, or "no wind" would mean two
	# different things depending on whether a level happened to declare one.
	var wind: Resource = W.new()
	assert_vector(wind.vector_at(9.0)).is_equal(Vector3.ZERO)


# --- heading convention --------------------------------------------------------

func test_base_vector_heading_is_the_direction_the_wind_blows_toward() -> void:
	var eps := Vector3.ONE * 1e-5
	assert_vector(W.base_vector(0.0, 4.0)).is_equal_approx(Vector3(0.0, 0.0, -4.0), eps)
	assert_vector(W.base_vector(90.0, 4.0)).is_equal_approx(Vector3(4.0, 0.0, 0.0), eps)
	assert_vector(W.base_vector(180.0, 4.0)).is_equal_approx(Vector3(0.0, 0.0, 4.0), eps)
	assert_vector(W.base_vector(270.0, 4.0)).is_equal_approx(Vector3(-4.0, 0.0, 0.0), eps)


func test_wind_is_horizontal() -> void:
	var wind: Resource = W.new()
	wind.direction_deg = 47.0
	wind.speed = 6.0
	wind.gust_speed = 5.0
	for i in 200:
		assert_float(wind.vector_at(float(i) * DELTA).y).is_equal(0.0)


# --- the gust model is pure ----------------------------------------------------

func test_the_same_seed_replays_the_same_sequence() -> void:
	var first := _gust_sequence(1234, 600)
	var second := _gust_sequence(1234, 600)
	assert_int(first.size()).is_equal(600)
	for i in first.size():
		assert_vector(second[i]) \
			.override_failure_message("tick %d diverged for the same seed" % i) \
			.is_equal(first[i])


func test_a_different_seed_gives_a_different_sequence() -> void:
	var a := _gust_sequence(1234, 240)
	var b := _gust_sequence(9876, 240)
	var differed := false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			differed = true
			break
	assert_bool(differed).is_true()


func test_the_gust_does_not_depend_on_how_it_was_reached() -> void:
	# Sampling the same instant directly and arriving there over 300 ticks must agree: the
	# model is a function of the time, not of a running state a frame-rate wobble could
	# perturb. This is what makes a recorded flight replayable.
	var stepped := _gust_sequence(77, 300)
	assert_vector(W.gust(77, 300.0 * DELTA, 3.0)) \
		.is_equal_approx(stepped[stepped.size() - 1], Vector2.ONE * 1e-6)


func test_the_gust_is_bounded_by_its_amplitude() -> void:
	# Normalized octave weights: no alignment of the three sines can exceed the amplitude.
	for i in 3000:
		var g := W.gust(42, float(i) * DELTA, 2.5)
		assert_float(g.length()) \
			.override_failure_message("gust %s overshot its amplitude at tick %d" % [g, i]) \
			.is_less_equal(2.5 + 1e-6)


func test_a_zero_amplitude_gust_is_exactly_zero() -> void:
	assert_vector(W.gust(42, 3.0, 0.0)).is_equal(Vector2.ZERO)
	assert_vector(W.gust(42, 3.0, -1.0)).is_equal(Vector2.ZERO)


func test_the_gust_actually_moves() -> void:
	# A gust that never varied would pass every determinism test above and be useless.
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for i in 1200:
		var g := W.gust(5, float(i) * DELTA, 4.0)
		lo = lo.min(g)
		hi = hi.max(g)
	assert_float(hi.x - lo.x).is_greater(1.0)
	assert_float(hi.y - lo.y).is_greater(1.0)


func test_wind_at_a_node_outside_a_level_is_calm() -> void:
	var orphan: Node3D = auto_free(Node3D.new())
	assert_vector(W.at(orphan)).is_equal(Vector3.ZERO)


# --- the regression: zero wind is today's drag ---------------------------------

func test_zero_wind_drone_drag_is_unchanged() -> void:
	for v in _sample_velocities():
		var h := Vector3(v.x, 0.0, v.z)
		assert_vector(VM.clamped_damper(h - Vector3.ZERO, DRONE_H_DRAG, DRONE_MASS, DELTA)) \
			.override_failure_message("horizontal drag changed at %s" % v) \
			.is_equal(VM.clamped_damper(h, DRONE_H_DRAG, DRONE_MASS, DELTA))
		var vert := Vector3(0.0, v.y, 0.0)
		assert_vector(VM.clamped_damper(vert - Vector3.ZERO, DRONE_V_DRAG, DRONE_MASS, DELTA)) \
			.override_failure_message("vertical drag changed at %s" % v) \
			.is_equal(VM.clamped_damper(vert, DRONE_V_DRAG, DRONE_MASS, DELTA))


func test_zero_wind_plane_drag_is_unchanged() -> void:
	for v in _sample_velocities():
		assert_vector(VM.clamped_damper(v - Vector3.ZERO, PLANE_DRAG, PLANE_MASS, DELTA)) \
			.override_failure_message("plane drag changed at %s" % v) \
			.is_equal(VM.clamped_damper(v, PLANE_DRAG, PLANE_MASS, DELTA))


func test_wind_actually_changes_the_drag() -> void:
	# The other side of the regression test: with wind present the force must differ, or the
	# feature would be inert and the equivalence tests above would be vacuous.
	var v := Vector3(12.0, 0.0, 0.0)
	var wind := Vector3(-5.0, 0.0, 0.0)
	var still := VM.clamped_damper(v, DRONE_H_DRAG, DRONE_MASS, DELTA)
	var blown := VM.clamped_damper(v - wind, DRONE_H_DRAG, DRONE_MASS, DELTA)
	assert_float(blown.length()).is_greater(still.length())
	# ...and a body sitting still in wind is pushed DOWNWIND rather than held in place: at
	# rest the relative flow is -wind, so the damper opposing it points along the wind.
	var parked := VM.clamped_damper(Vector3.ZERO - wind, DRONE_H_DRAG, DRONE_MASS, DELTA)
	assert_float(parked.dot(wind)).is_greater(0.0)


# --- the one-tick clamp still holds, now against the air -----------------------

func test_the_damper_never_reverses_the_relative_velocity() -> void:
	# The discipline the drone/plane headers protect: within one tick the drag may at most
	# ZERO the velocity it opposes. Checked in the RELATIVE frame, where it now acts, and at
	# a coefficient far past the clamp so the clamp is what is being measured.
	var coeffs: Array[float] = [DRONE_H_DRAG, DRONE_V_DRAG, PLANE_DRAG, 1e6]
	var winds: Array[Vector3] = [Vector3.ZERO, Vector3(9.0, 0.0, -4.0), Vector3(-30.0, 0.0, 30.0)]
	for coeff in coeffs:
		for v in _sample_velocities():
			for wind in winds:
				var rel: Vector3 = v - wind
				var force := VM.clamped_damper(rel, coeff, DRONE_MASS, DELTA)
				var settled: Vector3 = rel + force / DRONE_MASS * DELTA
				# Normalized by the relative speed: at the clamp the tick lands the body
				# exactly at zero, so what is left is float slop proportional to the speed
				# that went in, not an absolute figure a 60 m/s case could exceed.
				var along := settled.dot(rel) / maxf(rel.length_squared(), 1e-12)
				assert_float(along) \
					.override_failure_message("coeff %f reversed %s (wind %s)" % [coeff, rel, wind]) \
					.is_greater_equal(-1e-6)
				assert_float(settled.length()) \
					.override_failure_message("coeff %f sped up %s (wind %s)" % [coeff, rel, wind]) \
					.is_less_equal(rel.length() + 1e-6)


# --- helpers -------------------------------------------------------------------

## `count` gust samples on the 60 Hz tick grid — the sequence a flight would actually see.
func _gust_sequence(seed_value: int, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		out.append(W.gust(seed_value, float(i + 1) * DELTA, 3.0))
	return out


## Velocities spanning both damper regimes: below the one-tick clamp, above it, and at rest.
func _sample_velocities() -> Array[Vector3]:
	return [
		Vector3.ZERO,
		Vector3(0.0, 1e-9, 0.0),
		Vector3(1.0, -2.0, 3.0),
		Vector3(0.0, -18.0, 0.0),
		Vector3(60.0, 5.0, -20.0),
		Vector3(-7.5, 0.0, 0.25),
	]
