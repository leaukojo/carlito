extends GdUnitTestSuite
## §6 lamp decision logic + the procedural horn stream. The scene-touching parts of
## LampSet (Light3D energy, material overrides) need a tree and are not tested here;
## the pure tri-state rule and the horn synthesis are.

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
	# OFF keeps a dim housing glow so the lens is always visible.
	assert_float(LampSet.REAR_ENERGY[LampSet.Rear.OFF]).is_greater(0.0)


func test_headlight_levels_have_distinct_increasing_energy_and_range() -> void:
	# off/clearance/low/high with distinct energy/range.
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_OFF]).is_equal(0.0)
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_CLEARANCE]).is_less(LampSet.HEAD_ENERGY[LampSet.HL_LOW])
	assert_float(LampSet.HEAD_ENERGY[LampSet.HL_LOW]).is_less(LampSet.HEAD_ENERGY[LampSet.HL_HIGH])
	assert_float(LampSet.HEAD_RANGE[LampSet.HL_CLEARANCE]).is_less(LampSet.HEAD_RANGE[LampSet.HL_HIGH])


func test_steady_lenses_are_never_dark_and_light_from_clearance_up() -> void:
	# Marker lenses (nav lights): dim housing glow off, one steady lit level above it.
	assert_float(LampSet.STEADY_ENERGY[LampSet.HL_OFF]).is_greater(0.0)
	assert_float(LampSet.STEADY_ENERGY[LampSet.HL_OFF]) \
			.is_less(LampSet.STEADY_ENERGY[LampSet.HL_CLEARANCE])
	# No tier above clearance — a nav light does not brighten with the beam.
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


# --- anti-collision beacon (the documented local-clock exception) --------------

func test_beacon_pulse_is_short_and_repeats_every_period() -> void:
	# Lit at the top of each period, dark through the long remainder of it.
	assert_bool(LampSet.beacon_lit(0.0, 1.4, 0.16)).is_true()
	assert_bool(LampSet.beacon_lit(1.4, 1.4, 0.16)).is_true()
	assert_bool(LampSet.beacon_lit(2.8, 1.4, 0.16)).is_true()
	assert_bool(LampSet.beacon_lit(0.7, 1.4, 0.16)).is_false()
	assert_bool(LampSet.beacon_lit(1.39, 1.4, 0.16)).is_false()
	# The flash is a short pulse, not a half-on square wave.
	assert_float(LampSet.BEACON_ON_FRAC).is_less(0.5)


func test_beacon_phase_does_not_drift_and_degrades_safely() -> void:
	# Phase comes from the clock, so an hour in it still lands on the period boundary.
	assert_bool(LampSet.beacon_lit(1.4 * 2500.0, 1.4, 0.16)).is_true()
	# Degenerate settings never leave the lens stuck on.
	assert_bool(LampSet.beacon_lit(0.0, 0.0, 0.16)).is_false()
	assert_bool(LampSet.beacon_lit(0.0, 1.4, 0.0)).is_false()


# --- procedural horn ---------------------------------------------------------

func test_horn_stream_is_non_empty_and_loops() -> void:
	var wav := Horn.make_stream()
	assert_int(wav.data.size()).is_greater(0)
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_greater(0)
