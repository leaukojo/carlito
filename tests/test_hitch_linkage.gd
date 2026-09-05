extends GdUnitTestSuite
## HitchLinkage: tractor three-point hitch four-bar solve. Load-bearing: geometry in defaults.
## Float32 math: comparisons against float64 literals use is_equal_approx (not is_equal).

const LinkageScript := preload("res://src/vehicles/tractor/hitch_linkage.gd")

const EPS := 1e-4


func _linkage() -> HitchLinkage:
	return LinkageScript.new()

# --- circle-circle primitive --------------------------------------------------

func test_circle_intersect_returns_a_point_on_both_circles() -> void:
	var r: Dictionary = LinkageScript.circle_intersect(
			Vector2.ZERO, 1.0, Vector2(1.5, 0.0), 1.0, Vector2(0.0, 1.0))
	assert_bool(r["reachable"]).is_true()
	var p: Vector2 = r["point"]
	assert_float(p.length()).is_equal_approx(1.0, EPS)
	assert_float((p - Vector2(1.5, 0.0)).length()).is_equal_approx(1.0, EPS)
	# 'prefer' picks the branch: +Y here, -Y with the sign flipped.
	assert_bool(p.y > 0.0).is_true()
	var down: Dictionary = LinkageScript.circle_intersect(
			Vector2.ZERO, 1.0, Vector2(1.5, 0.0), 1.0, Vector2(0.0, -1.0))
	assert_bool((down["point"] as Vector2).y < 0.0).is_true()


func test_circle_intersect_reports_unreachable_and_clamps() -> void:
	# Too far apart: clamped onto circle 1, pointing at c2.
	var far: Dictionary = LinkageScript.circle_intersect(
			Vector2.ZERO, 1.0, Vector2(10.0, 0.0), 1.0, Vector2(0.0, 1.0))
	assert_bool(far["reachable"]).is_false()
	assert_vector(far["point"] as Vector2).is_equal_approx(Vector2(1.0, 0.0), Vector2.ONE * EPS)
	# One circle swallowed by the other is unreachable too.
	var inside: Dictionary = LinkageScript.circle_intersect(
			Vector2.ZERO, 5.0, Vector2(0.2, 0.0), 1.0, Vector2(0.0, 1.0))
	assert_bool(inside["reachable"]).is_false()


# --- the shipped linkage ------------------------------------------------------

func test_whole_sweep_is_reachable() -> void:
	var link := _linkage()
	var t := 0.0
	while t <= 1.0001:
		var s := link.solve(t)
		assert_bool(s["reachable"]) \
			.override_failure_message("linkage does not close at pos01 = %.2f" % t) \
			.is_true()
		t += 0.05


func test_loop_closes_at_every_step() -> void:
	# Rigid parts stay rigid: the top pin keeps its distance to BOTH the mast pivot and the
	# ball ends, and the lift rod keeps its length. That is what makes the pitch honest.
	var link := _linkage()
	var t := 0.0
	while t <= 1.0001:
		var s := link.solve(t)
		var ball: Vector2 = s["ball"]
		var top_pin: Vector2 = s["top_pin"]
		assert_float((top_pin - link.top_pivot).length()).is_equal_approx(link.top_len, EPS)
		assert_float((top_pin - ball).length()).is_equal_approx(link.mast_offset.length(), EPS)
		assert_float(((s["rod_end"] as Vector2) - (s["rod_attach"] as Vector2)).length()) \
			.is_equal_approx(link.lift_rod_len, EPS)
		assert_float(((s["rod_end"] as Vector2) - link.rock_pivot).length()) \
			.is_equal_approx(link.rock_arm_len, EPS)
		t += 0.05


func test_ball_ends_rise_monotonically() -> void:
	var link := _linkage()
	var prev := -99.0
	var t := 0.0
	while t <= 1.0001:
		var y: float = (link.solve(t)["ball"] as Vector2).y
		assert_bool(y > prev) \
			.override_failure_message("ball height not increasing at pos01 = %.2f" % t).is_true()
		prev = y
		t += 0.05
	# The lift is worth looking at: ~0.21 m (just clear of the ground) to ~0.78 m.
	assert_float((link.solve(0.0)["ball"] as Vector2).y).is_equal_approx(0.210, 0.01)
	assert_float((link.solve(1.0)["ball"] as Vector2).y).is_equal_approx(0.780, 0.01)


func test_implement_pitches_back_as_it_lifts() -> void:
	# top_len is chosen so the implement sits at its authored rest pose when fully lowered,
	# and tips back (positive planar pitch) as the linkage raises — the recognisable
	# three-point behaviour, and the reason the pitch is solved rather than lerped.
	var link := _linkage()
	assert_float(link.solve(0.0)["pitch"]).is_equal_approx(0.0, 1e-3)
	var mid: float = link.solve(0.5)["pitch"]
	var top: float = link.solve(1.0)["pitch"]
	assert_bool(mid > 0.01).is_true()
	assert_bool(top > mid).is_true()
	assert_float(rad_to_deg(top)).is_between(10.0, 25.0)


func test_rockshaft_arm_sweeps_visibly() -> void:
	# The arm angle is solved through the rigid lift rod, so it is not the lower-link angle:
	# it swings roughly twice as far, which is what makes the linkage read as machinery.
	var link := _linkage()
	var lo: float = link.solve(0.0)["rock_angle"]
	var hi: float = link.solve(1.0)["rock_angle"]
	assert_bool(hi > lo).is_true()
	assert_float(rad_to_deg(hi - lo)).is_between(40.0, 90.0)


func test_pos01_is_clamped() -> void:
	var link := _linkage()
	assert_vector(link.solve(-3.0)["ball"] as Vector2) \
		.is_equal_approx(link.solve(0.0)["ball"] as Vector2, Vector2.ONE * EPS)
	assert_vector(link.solve(9.0)["ball"] as Vector2) \
		.is_equal_approx(link.solve(1.0)["ball"] as Vector2, Vector2.ONE * EPS)


func test_every_catalog_implement_frame_closes_the_linkage() -> void:
	# mast_offset() is an override point, and an override the four-bar cannot close ships a
	# hitch that silently snaps to the clamped pose. Nothing in ThreePointHitch reads
	# `reachable`, so every A-frame the tractor can actually carry is checked here.
	var link := _linkage()
	for path in ImplementCatalog.IMPLEMENTS:
		# Towed entries are skipped, and skipped for a reason rather than for convenience: a drawbar
		# trailer has no A-frame at all — it hangs off a pin, not off the four-bar — so there is no
		# mast_offset for the linkage to close on. tests/test_drawbar_trailer.gd asserts that every
		# towed entry really does declare DRAWBAR and not THREE_POINT, so nothing gets past both.
		if not ImplementCatalog.is_attached(path) or ImplementCatalog.is_towed(path):
			continue
		var node: ImplementBase = (load(path) as PackedScene).instantiate()
		link.mast_offset = node.mast_offset()
		node.free()
		var t := 0.0
		while t <= 1.0001:
			assert_bool(link.solve(t)["reachable"]) \
				.override_failure_message("%s: linkage does not close at pos01 = %.2f" % [path, t]) \
				.is_true()
			t += 0.05


func test_a_taller_implement_frame_changes_the_solved_pitch() -> void:
	# mast_offset comes from the attached implement, so a different A-frame really does
	# re-solve the linkage (it is not a per-implement authored constant).
	var link := _linkage()
	var stock: float = link.solve(1.0)["pitch"]
	link.mast_offset = Vector2(-0.06, 0.66)
	assert_bool(absf((link.solve(1.0)["pitch"] as float) - stock) > 0.01).is_true()
