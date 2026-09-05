extends GdUnitTestSuite
## Sky pattern, visibility mask decoding, HDOP spread model, landed predicate (ST_GROUND).
## Raycasts ARE the measurement (level's job); tests what's derived from their output.
## Occlusion via mask bits, not geometry (honest unit-level stand-in).

const S := preload("res://src/vehicles/drone/drone_sensors.gd")

const DELTA := 1.0 / 60.0
## A hover collective for the landing tests: 5 kg at 9.8 m/s^2 against 150 N of thrust.
const HOVER := 5.0 * 9.8 / 150.0


## The full sky, as a mask: every ray in the pattern came back.
func _all_visible() -> int:
	return (1 << S.SKY_RAYS) - 1


## Top n rays (zenith angle ordered; index 0 is straight up).
func _only_top(n: int) -> int:
	return (1 << maxi(n, 0)) - 1


# --- the sky pattern ------------------------------------------------------------

func test_sky_pattern_is_unit_vectors_inside_the_mask() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	assert_int(p.size()).is_equal(S.SKY_RAYS)
	var cos_max := cos(deg_to_rad(S.SKY_MASK_DEG))
	for i in p.size():
		assert_float(p[i].length()) \
			.override_failure_message("ray %d is not a unit vector" % i) \
			.is_equal_approx(1.0, 1e-5)
		# Every ray points UP and none escapes the mask angle: a ray below the elevation mask
		# would be a satellite a real receiver has already discarded.
		assert_float(p[i].y) \
			.override_failure_message("ray %d fell below the mask angle" % i) \
			.is_greater_equal(cos_max - 1e-5)


## FIXED, not seeded — the whole reason it is a spiral rather than an RNG. Two builds of the
## same pattern are identical element for element, so `sats` cannot flicker while the craft
## stands still, and a session replays the same sky.
func test_sky_pattern_is_deterministic() -> void:
	var a := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var b := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	for i in a.size():
		assert_vector(a[i]).is_equal(b[i])


## ...and EVENLY spread, which is the other half of the choice. Area-uniform over the cap
## means the mean of the sixteen directions is (1 + cos mask) / 2 straight up — the figure
## HDOP_K is derived from, so a pattern that drifted off it would silently move every HDOP
## reading. Also the check that the rays are not all bunched on one azimuth: the horizontal
## components have to cancel.
func test_sky_pattern_is_area_uniform_over_the_cap() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var sum := Vector3.ZERO
	for d in p:
		sum += d
	var mean := sum / float(p.size())
	var expected_up := (1.0 + cos(deg_to_rad(S.SKY_MASK_DEG))) * 0.5
	assert_float(mean.y).is_equal_approx(expected_up, 0.02)
	assert_float(Vector2(mean.x, mean.z).length()) \
		.override_failure_message("the pattern leans to one side of the sky") \
		.is_less(0.05)


func test_sky_pattern_degenerates_safely() -> void:
	assert_int(S.sky_pattern(0, S.SKY_MASK_DEG).size()).is_equal(0)
	assert_int(S.sky_pattern(-3, S.SKY_MASK_DEG).size()).is_equal(0)
	# A zero mask collapses the cap to the zenith: every ray straight up, still unit length.
	for d in S.sky_pattern(4, 0.0):
		assert_vector(d).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-5)


# --- sats: decoding the mask -----------------------------------------------------

func test_sats_counts_the_visible_rays() -> void:
	assert_int(S.sats(0, S.SKY_RAYS)).is_equal(0)
	assert_int(S.sats(_all_visible(), S.SKY_RAYS)).is_equal(S.SKY_RAYS)
	assert_int(S.sats(0b1011, S.SKY_RAYS)).is_equal(3)


## Bits above the pattern are IGNORED, not counted — a shrunk pattern must not report
## satellites that no longer exist (the roster_mask rule, one file over).
func test_sats_ignores_bits_past_the_pattern() -> void:
	assert_int(S.sats(~0, 4)).is_equal(4)
	assert_int(S.sats(~0, 0)).is_equal(0)
	assert_int(S.sats(~0, -1)).is_equal(0)


# --- fix_type --------------------------------------------------------------------

func test_fix_type_walks_the_textbook_counts() -> void:
	assert_int(S.fix_type(0)).is_equal(S.FIX_NONE)
	assert_int(S.fix_type(1)).is_equal(S.FIX_TIME_ONLY)
	assert_int(S.fix_type(2)).is_equal(S.FIX_TIME_ONLY)
	assert_int(S.fix_type(3)).is_equal(S.FIX_2D)
	assert_int(S.fix_type(4)).is_equal(S.FIX_3D)
	assert_int(S.fix_type(S.SKY_RAYS)).is_equal(S.FIX_3D)
	# A negative count cannot happen from sats(), but it must not wrap into a fix either.
	assert_int(S.fix_type(-1)).is_equal(S.FIX_NONE)


## Every one of the four states is REACHABLE from a real sky, which is the claim the level-3
## flight is supposed to demonstrate: an open sky is a 3D fix, a canyon that leaves a few
## rays overhead degrades through 2D and TIME_ONLY, and a fully blocked sky is NO FIX.
func test_every_fix_state_is_reachable_by_occluding_the_sky() -> void:
	var seen := {}
	for n in S.SKY_RAYS + 1:
		seen[S.fix_type(S.sats(_only_top(n), S.SKY_RAYS))] = true
	for state in [S.FIX_NONE, S.FIX_TIME_ONLY, S.FIX_2D, S.FIX_3D]:
		assert_bool(seen.has(state)) \
			.override_failure_message("fix state %d is unreachable" % state).is_true()


# --- hdop ------------------------------------------------------------------------

## The number the contract desc promises for an open sky: about 0.9, and comfortably under
## the warn. This is what HDOP_K is set to produce, so a mask-angle change that is not
## followed by a re-derivation of HDOP_K fails here.
func test_hdop_reads_about_one_under_an_open_sky() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var open := S.hdop(p, _all_visible())
	assert_float(open) \
		.override_failure_message("an open sky read %.2f, not ~0.9" % open) \
		.is_between(0.8, 1.0)


## ...and the shape between the ends: taking the sky away can only make the reading WORSE.
## Monotone in occlusion is the whole content of the model — if it were not, a bar that rose
## as you flew INTO a canyon would be the reading, and the signal would be noise.
func test_hdop_only_worsens_as_the_sky_is_taken_away() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var prev := S.hdop(p, _all_visible())
	for n in range(S.SKY_RAYS - 1, S.FIX_SATS_3D - 1, -1):
		var now := S.hdop(p, _only_top(n))
		assert_float(now) \
			.override_failure_message("%d rays read %.2f, better than %d rays' %.2f" % [
				n, now, n + 1, prev]) \
			.is_greater_equal(prev - 1e-6)
		prev = now


## A building taking half the sky is a real reading rather than a pin, and it is the case the
## contract desc quotes: the surviving rays all sit on one side, so their mean picks up a
## horizontal component and the spread shrinks — around 1.3 against the open sky's 0.9.
func test_hdop_degrades_with_a_building_on_one_side() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var half := 0
	for i in p.size():
		if p[i].x <= 0.0:
			half |= 1 << i
	assert_int(S.sats(half, S.SKY_RAYS)).is_greater_equal(S.FIX_SATS_3D)
	assert_float(S.hdop(p, half)).is_between(1.1, 1.6)


## Squeezed hard enough it PINS, and this is the model's own end rather than the no-fix rule
## reaching it first: a tight cone of rays with every one of them visible still has plenty of
## satellites, but they are all pointing the same way, so their mean is nearly a unit vector,
## the spread collapses and the bar tops out. That is the whole content of DOP — a
## constellation bunched into one patch of sky solves a position badly.
func test_hdop_pins_when_the_visible_sky_collapses_to_one_direction() -> void:
	var tight := S.sky_pattern(8, 2.0)
	assert_int(S.sats((1 << 8) - 1, 8)).is_greater_equal(S.FIX_SATS_3D)
	assert_float(S.hdop(tight, (1 << 8) - 1)).is_equal(S.HDOP_MAX)


## Below a 3D fix — and therefore also with the GNSS node offline, which DroneVehicle
## expresses as an EMPTY sky rather than as a second branch — there is no precision left to
## dilute, so it publishes the ceiling rather than a plausible small number.
func test_hdop_is_the_ceiling_without_a_fix() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	for n in S.FIX_SATS_3D:
		assert_float(S.hdop(p, _only_top(n))) \
			.override_failure_message("%d satellites reported a usable hdop" % n) \
			.is_equal(S.HDOP_MAX)
	assert_float(S.hdop(p, 0)).is_equal(S.HDOP_MAX)
	assert_float(S.hdop(PackedVector3Array(), _all_visible())).is_equal(S.HDOP_MAX)


## Never off the bar in either direction, at any occlusion, which is what lets the contract
## range be the published ceiling AND the no-fix value at the same time.
func test_hdop_stays_inside_its_contract_range() -> void:
	var p := S.sky_pattern(S.SKY_RAYS, S.SKY_MASK_DEG)
	var sig := Contract.data.get_signal_def("hdop", "out")
	for mask in S.SKY_RAYS + 1:
		var v := S.hdop(p, _only_top(mask))
		assert_float(v).is_between(float(sig.range[0]), float(sig.range[1]))


# --- the landed predicate ---------------------------------------------------------

func _landed(agl: float, vspeed: float, collective: float) -> bool:
	return S.landed_now(agl, vspeed, collective, S.LANDED_AGL, S.LANDED_VSPEED,
			HOVER * S.LANDED_COLLECTIVE_FRAC)


func test_landed_needs_all_three_conditions() -> void:
	# On the skids: the ground is right there, nothing is moving, the stick is centred so the
	# collective is exactly a hover.
	assert_bool(_landed(0.06, 0.0, HOVER)).is_true()
	# Any one of the three breaking is enough to say "flying".
	assert_bool(_landed(4.0, 0.0, HOVER)) \
		.override_failure_message("four metres up is not landed").is_false()
	assert_bool(_landed(0.06, 2.0, HOVER)) \
		.override_failure_message("climbing away is not landed").is_false()
	assert_bool(_landed(0.06, -2.0, HOVER)) \
		.override_failure_message("dropping is not landed").is_false()
	assert_bool(_landed(0.06, 0.0, 1.0)) \
		.override_failure_message("full collective is a takeoff, not a landing").is_false()


## A disarmed craft commands NO collective at all, so the ceiling can never be the thing that
## keeps a settled aircraft from reading landed.
func test_a_disarmed_craft_on_the_ground_is_landed() -> void:
	assert_bool(_landed(0.06, 0.0, 0.0)).is_true()


## The invalid reading is not "close to the ground". -1 is smaller than every threshold, so a
## naive `agl <= agl_max` would call a craft whose rangefinder sees nothing — 200 m up, or
## with the RANGE node pulled — landed. That is the bug the sentinel's sign creates and the
## reason landed_now tests for it explicitly.
func test_an_invalid_rangefinder_reading_is_never_landed() -> void:
	assert_bool(_landed(S.RANGE_INVALID, 0.0, 0.0)).is_false()
	assert_bool(_landed(-0.001, 0.0, 0.0)).is_false()


## The collective ceiling is the HOVER, plus slack — so the stick being centred on the skids
## still reads landed, and asking for real lift does not.
func test_the_collective_ceiling_sits_just_above_a_hover() -> void:
	assert_bool(_landed(0.06, 0.0, HOVER * 1.02)).is_true()
	assert_bool(_landed(0.06, 0.0, HOVER * 1.2)).is_false()


func test_landed_hold_accumulates_and_resets() -> void:
	var held := 0.0
	held = S.landed_hold(held, true, DELTA)
	assert_float(held).is_equal_approx(DELTA, 1e-9)
	held = S.landed_hold(held, true, DELTA)
	assert_float(held).is_equal_approx(2.0 * DELTA, 1e-9)
	# One failing tick throws the whole accumulation away.
	assert_float(S.landed_hold(held, false, DELTA)).is_equal(0.0)


## THE ASYMMETRY, as behaviour: touching down takes LANDED_DEBOUNCE to be believed, and
## lifting off is believed immediately. A ground bit that lingered into a takeoff would be
## the same lie it replaced, only shorter.
func test_the_debounce_is_slow_to_set_and_instant_to_clear() -> void:
	var held := 0.0
	var ticks := 0
	while held < S.LANDED_DEBOUNCE and ticks < 1000:
		held = S.landed_hold(held, true, DELTA)
		ticks += 1
	assert_int(ticks) \
		.override_failure_message("the debounce set in one tick").is_greater(1)
	assert_float(float(ticks) * DELTA).is_between(S.LANDED_DEBOUNCE, S.LANDED_DEBOUNCE + DELTA)
	assert_float(S.landed_hold(held, false, DELTA)) \
		.override_failure_message("clearing must not wait").is_equal(0.0)


func test_landed_hold_ignores_a_negative_delta() -> void:
	assert_float(S.landed_hold(0.25, true, -1.0)).is_equal(0.25)


# --- the contract pins ------------------------------------------------------------

## The four constants that are ALSO contract range endpoints. Each is written once here and
## declared once in the JSON, and there is no runtime read tying them together — so this is
## what keeps them equal. A wider sky pattern, a longer beam or a different HDOP ceiling that
## is not followed into the contract fails CI instead of publishing off its own bar.
func test_the_sensor_constants_are_the_contracts_own_scales() -> void:
	var sats := Contract.data.get_signal_def("sats", "out")
	assert_int(int(sats.range[1])) \
		.override_failure_message("the pattern casts %d rays, 'sats' tops out at %d" % [
			S.SKY_RAYS, int(sats.range[1])]) \
		.is_equal(S.SKY_RAYS)
	assert_float(float(Contract.data.get_signal_def("hdop", "out").range[1])) \
		.override_failure_message("HDOP_MAX is not the 'hdop' bar top").is_equal(S.HDOP_MAX)
	var agl := Contract.data.get_signal_def("agl", "out")
	assert_float(float(agl.range[1])) \
		.override_failure_message("RANGE_MAX is not the 'agl' bar top").is_equal(S.RANGE_MAX)
	assert_float(float(agl.range[0])) \
		.override_failure_message("RANGE_INVALID is not the 'agl' range floor") \
		.is_equal(S.RANGE_INVALID)


## The fix enum values ARE the contract's enum ordinals, so a chip reading "3D" and a bus
## carrying 3 cannot come apart.
func test_the_fix_enum_matches_the_contract_table() -> void:
	var sig := Contract.data.get_signal_def("fix_type", "out")
	assert_str(sig.enum_label(S.FIX_NONE)).is_equal("NO FIX")
	assert_str(sig.enum_label(S.FIX_TIME_ONLY)).is_equal("TIME")
	assert_str(sig.enum_label(S.FIX_2D)).is_equal("2D")
	assert_str(sig.enum_label(S.FIX_3D)).is_equal("3D")


## `sats` warns at the count a 3D fix needs — the one number in the contract that has to
## agree with a threshold in this file rather than with a range endpoint.
func test_the_sats_warn_is_the_3d_fix_threshold() -> void:
	assert_float(Contract.data.get_signal_def("sats", "out").warn) \
		.is_equal(float(S.FIX_SATS_3D))
