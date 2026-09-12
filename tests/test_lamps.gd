extends GdUnitTestSuite
## §6 lamp decision logic + the procedural horn stream. Pure statics, no scene tree: the
## scene-touching parts of LampSet (Light3D energy, material overrides) need a tree and are not
## tested here. What is asserted is the tri-state rule, the horn synthesis, and the absence of any
## local blink clock in lamp_set.gd.

# --- rear tri-state (STOP > TAIL > OFF) --------------------------------------

func test_brake_bit_gives_stop_regardless_of_headlights() -> void:
	for lights in [LampSet.HL_OFF, LampSet.HL_CLEARANCE, LampSet.HL_LOW, LampSet.HL_HIGH]:
		assert_int(LampSet.rear_tier(true, lights)).is_equal(LampSet.Rear.STOP)


func test_tail_only_when_headlights_at_clearance_or_brighter() -> void:
	assert_int(LampSet.rear_tier(false, LampSet.HL_OFF)).is_equal(LampSet.Rear.OFF)
	assert_int(LampSet.rear_tier(false, LampSet.HL_CLEARANCE)).is_equal(LampSet.Rear.TAIL)
	assert_int(LampSet.rear_tier(false, LampSet.HL_LOW)).is_equal(LampSet.Rear.TAIL)
	assert_int(LampSet.rear_tier(false, LampSet.HL_HIGH)).is_equal(LampSet.Rear.TAIL)


func test_off_tier_is_never_dark() -> void:
	assert_float(LampSet.REAR_ENERGY[LampSet.Rear.OFF]).is_greater(0.0)


func test_headlight_levels_have_distinct_increasing_energy_and_range() -> void:
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_OFF]).is_equal(0.0)
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_CLEARANCE]).is_less(LampSet.HEAD_ENERGY[LampSet.HL_LOW])
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_LOW]).is_less(LampSet.HEAD_ENERGY[LampSet.HL_HIGH])
	assert_float(LampSet.HEAD_RANGE[LampSet.HL_CLEARANCE]).is_less(LampSet.HEAD_RANGE[LampSet.HL_HIGH])


func test_steady_lenses_are_never_dark_and_light_from_clearance_up() -> void:
	assert_float(LampSet.STEADY_ENERGY[LampSet.HL_OFF]).is_greater(0.0)
	assert_float(LampSet.STEADY_ENERGY[LampSet.HL_OFF]) \
			.is_less(LampSet.STEADY_ENERGY[LampSet.HL_CLEARANCE])
	assert_float(LampSet.STEADY_ENERGY[LampSet.HL_HIGH]) \
			.is_equal(LampSet.STEADY_ENERGY[LampSet.HL_CLEARANCE])


# --- aircraft beam ladder (dark / taxi / landing) -----------------------------

func test_aircraft_beam_is_dark_until_taxi() -> void:
	# CLEARANCE is the beacon-and-nav step: no forward beam, and the lens stays at its
	# dim housing glow — unlike a car, where clearance is a parking light.
	assert_float(LampSet.AIR_ENERGY[LampSet.HL_OFF]).is_equal(0.0)
	assert_float(LampSet.AIR_ENERGY[LampSet.HL_CLEARANCE]).is_equal(0.0)
	assert_float(LampSet.AIR_ENERGY[LampSet.HL_LOW]).is_greater(0.0)
	assert_float(LampSet.AIR_LENS_ENERGY[LampSet.HL_CLEARANCE]) \
			.is_equal(LampSet.AIR_LENS_ENERGY[LampSet.HL_OFF])


func test_taxi_beam_is_wide_and_short_landing_beam_narrow_and_long() -> void:
	assert_float(LampSet.AIR_ANGLE[LampSet.HL_LOW]).is_greater(LampSet.AIR_ANGLE[LampSet.HL_HIGH])
	assert_float(LampSet.AIR_RANGE[LampSet.HL_LOW]).is_less(LampSet.AIR_RANGE[LampSet.HL_HIGH])
	assert_float(LampSet.AIR_ENERGY[LampSet.HL_LOW]).is_less(LampSet.AIR_ENERGY[LampSet.HL_HIGH])
	# Taxi is aimed well down at the ground ahead, landing is near level.
	assert_float(LampSet.AIR_PITCH[LampSet.HL_LOW]).is_greater(LampSet.AIR_PITCH[LampSet.HL_HIGH])


func test_only_road_low_beam_is_asymmetric() -> void:
	# Road car, low beam: kerb-side (left) lamp dips extra, both splay outward.
	assert_vector(LampSet.beam_splay(false, LampSet.HL_LOW, -1.0)) \
			.is_equal(Vector2(LampSet.LOW_LEFT_EXTRA_PITCH, LampSet.LOW_OUTWARD_YAW))
	assert_vector(LampSet.beam_splay(false, LampSet.HL_LOW, 1.0)) \
			.is_equal(Vector2(0.0, -LampSet.LOW_OUTWARD_YAW))
	# A lone centred lamp must not splay sideways.
	assert_vector(LampSet.beam_splay(false, LampSet.HL_LOW, 0.0)).is_equal(Vector2.ZERO)
	# Every other road level is symmetric...
	for lights in [LampSet.HL_OFF, LampSet.HL_CLEARANCE, LampSet.HL_HIGH]:
		assert_vector(LampSet.beam_splay(false, lights, -1.0)).is_equal(Vector2.ZERO)
	# ...and an aircraft lamp keeps its authored aim at EVERY level, including LOW.
	for lights in [LampSet.HL_OFF, LampSet.HL_CLEARANCE, LampSet.HL_LOW, LampSet.HL_HIGH]:
		assert_vector(LampSet.beam_splay(true, lights, -1.0)).is_equal(Vector2.ZERO)


# --- the flashing lamps: there is no clock left to test ------------------------
#
# `beacon_lit` used to live here, with two tests pinning its period and its phase. Both are gone
# with the function: the contract carries `beacon` and `strobe` since v30, sloppyCAN toggles them,
# and LampSet mirrors the bits like every other lamp. What is left to assert is the ABSENCE, and
# it is asserted rather than assumed - a timer creeping back into the one file that used to have
# one should fail here, not be noticed by driving.

func test_lamp_set_has_no_local_blink_clock() -> void:
	var src := FileAccess.get_file_as_string("res://src/vehicles/base/lamp_set.gd")
	assert_str(src).is_not_empty()
	# The two constants and the function that used them, as DECLARATIONS — the header still
	# names all three in prose, saying they were deleted, and that sentence must not fail this.
	assert_bool(src.contains("const BEACON_PERIOD")).is_false()
	assert_bool(src.contains("const BEACON_ON_FRAC")).is_false()
	assert_bool(src.contains("func beacon_lit")).is_false()
	# ...and the wall clock itself, under either of the two names a blink would reach for.
	assert_bool(src.contains("Time.get_ticks_msec")).is_false()
	assert_bool(src.contains("Time.get_unix_time")).is_false()


func test_the_drone_status_lights_keep_no_clock_either() -> void:
	# DroneIndicators lights the airframe's node LEDs from sim state rather than off the bus, and the
	# same rule binds it: a steady colour per state, never a pattern timed here.
	var src := FileAccess.get_file_as_string("res://src/vehicles/drone/drone_indicators.gd")
	assert_str(src).is_not_empty()
	assert_bool(src.contains("Time.get_ticks_msec")).is_false()
	assert_bool(src.contains("Time.get_unix_time")).is_false()
	assert_bool(src.contains("Timer")).is_false()


func test_the_beacon_and_the_strobes_are_separate_contract_bits() -> void:
	# Two bits rather than one, because they are two switches on a real aircraft. Both "in", both
	# the plane's, both bool - the turnL/turnR shape exactly.
	for signal_name in ["beacon", "strobe"]:
		var sig: RefCounted = Contract.data.get_signal_def(signal_name, "in")
		assert_object(sig).is_not_null()
		assert_str(sig.type).is_equal("bool")
		assert_array(sig.vehicles).contains(["plane"])


# --- indication LEDs (uavcan.equipment.indication.LightsCommand, RGB565) -------

func test_led_color_decodes_rgb565_at_both_ends_of_every_field() -> void:
	# 0 is black: the commanded-off state, and what an absent bit / no bridge gives.
	assert_that(LampSet.led_color(0)).is_equal(Color(0.0, 0.0, 0.0))
	# All sixteen bits set is WHITE, which only holds because each field is scaled by its own
	# maximum — a shared /256 would top out short of 1.0 and never make white.
	assert_that(LampSet.led_color(0xFFFF)).is_equal(Color(1.0, 1.0, 1.0))
	# One field at a time, at the LightsCommand bit positions: red 15-11, green 10-5, blue 4-0.
	assert_that(LampSet.led_color(0xF800)).is_equal(Color(1.0, 0.0, 0.0))
	assert_that(LampSet.led_color(0x07E0)).is_equal(Color(0.0, 1.0, 0.0))
	assert_that(LampSet.led_color(0x001F)).is_equal(Color(0.0, 0.0, 1.0))
	# Green really does carry the extra bit (63 steps against red/blue's 31).
	assert_float(LampSet.led_color(0x0020).g).is_equal_approx(1.0 / 63.0, 1e-5)
	assert_float(LampSet.led_color(0x0800).r).is_equal_approx(1.0 / 31.0, 1e-5)


func test_led_color_ignores_bits_above_the_packed_word() -> void:
	# A peer sending a richer LightsCommand is describing hardware this airframe does not have,
	# so the high bits are ignored rather than rejected — the node_fail rule.
	assert_that(LampSet.led_color(0xDEAD0000 | 0x001F)).is_equal(LampSet.led_color(0x001F))
	# ...and the colour never leaves the unit cube whatever arrives.
	for packed in [0, 0x1234, 0xFFFF, 0x7FFFFFFF]:
		var c := LampSet.led_color(packed)
		for ch in [c.r, c.g, c.b]:
			assert_float(ch).is_between(0.0, 1.0)


# --- procedural horn ---------------------------------------------------------

func test_horn_stream_is_non_empty_and_loops() -> void:
	var wav := Horn.make_stream()
	assert_int(wav.data.size()).is_greater(0)
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_greater(0)
