extends GdUnitTestSuite
## The sailboat's rig: the boom's travel against the sheet, the flat-plate polar with its luff
## band, and the force's direction in the hull's own frame. All pure statics — how the force is
## APPLIED (at sail_center, so it heels the hull) is wiring and belongs with the _tick_extras
## cases, not here.
##
## THE SIGN CONVENTION, since every case below rests on it: `sail_angle` is measured in the same
## rotational sense as `awa`, which is what makes `aoa = awa - sail_angle` true. A boom is an
## AFT-pointing spar, so a positive angle in that sense lays its far end to PORT — and since the
## boom always goes to leeward, `sail_angle` always shares `awa`'s sign. The number is how far
## out the boom is; the sign says which side the wind is on.

const S := preload("res://src/vehicles/boat/boat_sail.gd")

# The hull's own axes, as boat.gd hands them over: bow = -Z, starboard = +X, level.
const BOW := Vector3(0.0, 0.0, -1.0)
const STBD := Vector3(1.0, 0.0, 0.0)

const MAX_DEG := 90.0
const AREA := 14.0


# --- the boom -----------------------------------------------------------------

func test_the_sheet_limits_the_boom_and_the_wind_picks_the_side() -> void:
	assert_float(S.boom_angle(0.0, 90.0, MAX_DEG)).is_equal_approx(0.0, 1e-6)
	assert_float(S.boom_angle(0.5, 90.0, MAX_DEG)).is_equal_approx(45.0, 1e-6)
	# Wind from the other side and the boom swings the other way, so it is always to leeward.
	assert_float(S.boom_angle(0.5, -90.0, MAX_DEG)).is_equal_approx(-45.0, 1e-6)


func test_the_sheet_is_a_limit_not_a_position() -> void:
	# Close-hauled at 30 deg apparent with the sheet fully eased: the boom cannot swing past the
	# airflow, so it stops at 30 and the sail is dead (aoa 0), not eased to 90.
	assert_float(S.boom_angle(1.0, 30.0, MAX_DEG)).is_equal_approx(30.0, 1e-6)
	assert_float(S.attack_angle(30.0, S.boom_angle(1.0, 30.0, MAX_DEG))).is_equal_approx(0.0, 1e-6)


func test_a_dead_calm_leaves_the_boom_on_the_centreline() -> void:
	# apparent_wind reports awa 0 when the angle is undefined; there is no side to fall to.
	assert_float(S.boom_angle(1.0, 0.0, MAX_DEG)).is_equal_approx(0.0, 1e-6)


func test_hauling_in_never_lets_the_attack_angle_change_sign() -> void:
	for sheet in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for awa in [-170.0, -90.0, -20.0, 20.0, 90.0, 170.0]:
			var aoa := S.attack_angle(awa, S.boom_angle(sheet, awa, MAX_DEG))
			assert_float(absf(aoa)) \
				.override_failure_message("sheet %s awa %s -> aoa %s" % [sheet, awa, aoa]) \
				.is_less_equal(absf(awa) + 1e-6)
			assert_bool(aoa * awa >= -1e-9) \
				.override_failure_message("sheet %s awa %s flipped the aoa sign" % [sheet, awa]) \
				.is_true()


# --- the polar ----------------------------------------------------------------

func test_the_flat_plate_polar_hits_its_three_known_points() -> void:
	# Edge-on: no lift, minimum drag. 45 deg: peak lift. Broadside: no lift again, maximum drag.
	assert_float(S.lift_coeff(0.0)).is_equal_approx(0.0, 1e-6)
	assert_float(S.drag_coeff(0.0)).is_equal_approx(S.CD_MIN, 1e-6)
	assert_float(S.lift_coeff(45.0)).is_equal_approx(S.CL_MAX, 1e-6)
	assert_float(S.lift_coeff(90.0)).is_equal_approx(0.0, 1e-6)
	assert_float(S.drag_coeff(90.0)).is_equal_approx(S.CD_MIN + S.CD_STALL, 1e-6)


func test_the_sail_luffs_below_the_luff_angle_and_fills_smoothly_above_it() -> void:
	# A soft sail makes NOTHING at a small angle of attack — this is what makes irons real.
	assert_float(S.lift_coeff(S.LUFF_DEG - 1.0)).is_equal(0.0)
	assert_float(S.lift_coeff(0.0)).is_equal(0.0)
	# ...and it fills over the band rather than switching on.
	var edge := S.lift_coeff(S.LUFF_DEG + S.LUFF_BAND_DEG * 0.5)
	assert_float(edge).is_greater(0.0)
	assert_float(edge).is_less(S.lift_coeff(S.LUFF_DEG + S.LUFF_BAND_DEG))
	# Drag carries no luff factor: a flapping sail still has its edge-on drag.
	assert_float(S.drag_coeff(S.LUFF_DEG - 1.0)).is_greater_equal(S.CD_MIN)


func test_the_polar_is_symmetric_about_the_centreline() -> void:
	for aoa in [15.0, 30.0, 45.0, 70.0, 120.0]:
		assert_float(S.lift_coeff(-aoa)) \
			.override_failure_message("lift at -%s" % aoa).is_equal_approx(S.lift_coeff(aoa), 1e-9)
		assert_float(S.drag_coeff(-aoa)) \
			.override_failure_message("drag at -%s" % aoa).is_equal_approx(S.drag_coeff(aoa), 1e-9)


func test_the_plate_lift_reverses_past_ninety_degrees() -> void:
	# Blown backwards the plate's lift term changes sign; that is the model, not a bug.
	assert_float(S.lift_coeff(120.0)).is_less(0.0)


# --- the force ----------------------------------------------------------------

func test_a_starboard_beam_reach_pulls_the_hull_forward_and_heels_it_to_port() -> void:
	# awa +90 is wind from the starboard beam. The air blows the hull to port (drag) and the rig
	# pulls it forward (lift). This is the case that pins the whole sign convention.
	var f := S.force(Vector2(6.0, 90.0), 45.0, AREA, BOW, STBD)
	assert_float(f.dot(BOW)).override_failure_message("no drive on a beam reach").is_greater(0.0)
	assert_float(f.dot(STBD)).override_failure_message("pushed to windward").is_less(0.0)


func test_a_port_beam_reach_is_the_exact_mirror() -> void:
	var from_stbd := S.force(Vector2(6.0, 90.0), 45.0, AREA, BOW, STBD)
	var from_port := S.force(Vector2(6.0, -90.0), -45.0, AREA, BOW, STBD)
	assert_float(from_port.dot(BOW)).is_equal_approx(from_stbd.dot(BOW), 1e-5)
	assert_float(from_port.dot(STBD)).is_equal_approx(-from_stbd.dot(STBD), 1e-5)


func test_close_hauled_the_rig_heels_far_harder_than_it_drives() -> void:
	# THE NO-GO ZONE LIVES HERE and is not clamped anywhere: close to the wind the side force runs
	# several times the drive, and against the hull's drag_lat that is the leeway which stops the
	# boat making ground to windward however high the bow points.
	var f := S.force(Vector2(6.0, 30.0), 0.0, AREA, BOW, STBD)
	var drive := f.dot(BOW)
	var side := absf(f.dot(STBD))
	assert_float(drive).is_greater(0.0)
	assert_float(side).override_failure_message("side %s vs drive %s" % [side, drive]) \
		.is_greater(drive * 3.0)


func test_a_reach_drives_better_than_the_same_wind_close_hauled() -> void:
	var reach := S.force(Vector2(6.0, 90.0), 45.0, AREA, BOW, STBD).dot(BOW)
	var beat := S.force(Vector2(6.0, 30.0), 0.0, AREA, BOW, STBD).dot(BOW)
	assert_float(reach).is_greater(beat)


func test_easing_past_the_apparent_wind_luffs_the_sail_dead() -> void:
	# Trimmed to 45 deg of attack the rig drives; eased until the boom lines up with the airflow
	# it makes nothing but its own edge-on drag. Ease-to-slow is the whole point of the control.
	var trimmed := S.force(Vector2(6.0, 90.0), 45.0, AREA, BOW, STBD).length()
	var luffed := S.force(Vector2(6.0, 90.0), 90.0, AREA, BOW, STBD).length()
	assert_float(luffed).is_less(trimmed * 0.25)


func test_a_dead_run_with_the_boom_square_is_pure_drag_down_the_bow() -> void:
	# awa 180, boom 90: the plate is broadside to the flow, so the lift term is zero and what is
	# left pushes straight along the bow. This is why sheet_max_deg is 90 and not less.
	var f := S.force(Vector2(6.0, 180.0), 90.0, AREA, BOW, STBD)
	assert_float(f.dot(STBD)).is_equal_approx(0.0, 1e-4)
	assert_float(f.dot(BOW)).is_greater(0.0)


func test_the_force_grows_with_the_square_of_the_apparent_wind() -> void:
	# Why a gust is felt: doubling the wind quadruples the rig. Nothing clamps this — the hull's
	# own drag_long is what terminates it.
	var one := S.force(Vector2(5.0, 90.0), 45.0, AREA, BOW, STBD).length()
	var two := S.force(Vector2(10.0, 90.0), 45.0, AREA, BOW, STBD).length()
	assert_float(two).is_equal_approx(one * 4.0, one * 4.0 * 1e-5)


func test_a_hull_with_no_rig_and_a_dead_calm_both_make_no_force() -> void:
	# The two powerboats declare sail_area 0 and pay one comparison a tick.
	assert_vector(S.force(Vector2(6.0, 90.0), 45.0, 0.0, BOW, STBD)).is_equal(Vector3.ZERO)
	assert_vector(S.force(Vector2(0.0, 0.0), 0.0, AREA, BOW, STBD)).is_equal(Vector3.ZERO)


func test_the_force_stays_in_the_water_plane() -> void:
	# apparent_wind is flattened, and so are the axes boat.gd passes in, so a heeling hull must
	# not find the rig lifting it or pressing it under.
	for awa in [-150.0, -90.0, -25.0, 25.0, 90.0, 150.0]:
		var f := S.force(Vector2(6.0, awa), S.boom_angle(0.5, awa, MAX_DEG), AREA, BOW, STBD)
		assert_float(f.y).override_failure_message("awa %s lifted the hull" % awa) \
			.is_equal_approx(0.0, 1e-6)
