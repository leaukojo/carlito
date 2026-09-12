extends GdUnitTestSuite
## Boat buoyancy/thrust/rudder, the wind instruments and the track/tide ones. 60 Hz one-tick
## clamp: probe damper never reverses velocity, buoyancy hard-capped. Hull drag, windage and
## attitude are all VehicleMath calls made inline in _tick_extras, so they are tested there, not
## here (test_vehicle_math.gd, test_wind.gd, test_current.gd).

const B := preload("res://src/vehicles/boat/boat.gd")
const BoatT := preload("res://src/vehicles/boat/boat_telemetry.gd")
const W := preload("res://src/levels/base/wind_field.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const TerrainScript := preload("res://src/levels/base/heightmap_terrain.gd")

const DELTA := 1.0 / 60.0

# 800 kg boat, 4 probes, 0.4 m deep at g=10 -> k = 5000 N/m per probe.
const MASS := 800.0
const G := 10.0
const PROBES := 4.0
const FLOAT_DEPTH := 0.4
const K := MASS * G / (PROBES * FLOAT_DEPTH)      # 5000
const PROBE_MASS := MASS / PROBES                 # 200
const MAX_F := 3.0 * PROBE_MASS * G               # 6000


# --- probe_force: spring ------------------------------------------------------

func test_probe_force_zero_at_and_above_surface() -> void:
	assert_float(B.probe_force(0.0, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)
	assert_float(B.probe_force(-1.0, -5.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)


func test_probe_force_spring_is_linear_in_depth() -> void:
	assert_float(B.probe_force(0.1, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)) \
			.is_equal_approx(500.0, 1e-6)
	assert_float(B.probe_force(0.2, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)) \
			.is_equal_approx(1000.0, 1e-6)


func test_probe_force_all_probes_at_float_depth_carry_the_boat() -> void:
	# Floating level at the design depth, at rest: the probes sum to exactly m*g.
	var per_probe := B.probe_force(FLOAT_DEPTH, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)
	assert_float(per_probe * PROBES).is_equal_approx(MASS * G, 1e-6)


# --- probe_force: 60 Hz clamps ------------------------------------------------

func test_probe_force_damper_clamped_to_one_tick_reversal() -> void:
	# Sinking at 2 m/s with an absurd damper coefficient: the damper contribution must
	# cap at probe_mass * |v| / delta (RayWheel's damper clamp), not the raw c*v.
	# max_force is lifted out of the way so this isolates the damper clamp.
	var v := -2.0
	var tick_cap := PROBE_MASS * absf(v) / DELTA  # 24000
	var f := B.probe_force(0.1, v, K, 1e9, PROBE_MASS, DELTA, 1e12)
	assert_float(f).is_equal_approx(500.0 + tick_cap, 1e-3)


func test_probe_force_never_negative_when_rising() -> void:
	# Rising fast out of the water: the damper pulls down but water never sucks the
	# hull under — total force clamps at zero.
	assert_float(B.probe_force(0.05, 10.0, K, 1e9, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)


func test_probe_force_hard_capped_on_deep_penetration() -> void:
	# Slammed 3 m deep (a drop from the crane): raw spring would be 15000 N; the cap
	# holds it at MAX_F so the boat never catapults (max_suspension_force analogue).
	assert_float(B.probe_force(3.0, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(MAX_F)


# --- aground predicate (contract status bit ST_GROUND) --------------------------

func test_aground_floating_at_rest_depth_is_not_aground() -> void:
	# A genuinely floating hull settles to ~float_depth per probe by construction.
	assert_bool(B.aground_now(true, FLOAT_DEPTH, 0.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_false()


func test_aground_shallow_depth_while_settled_is_aground() -> void:
	# The bed is holding the hull up: probes can't reach rest submersion, and it's not
	# still falling/bouncing.
	var shallow := FLOAT_DEPTH * B.AGROUND_SHALLOW_FRAC * 0.5
	assert_bool(B.aground_now(true, shallow, 0.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_true()


func test_aground_shallow_but_still_moving_vertically_is_not_aground() -> void:
	# Same shallow reading, but the hull is still settling (a splashdown, a wave) —
	# not a stable "resting on the bed" reading yet.
	var shallow := FLOAT_DEPTH * B.AGROUND_SHALLOW_FRAC * 0.5
	assert_bool(B.aground_now(true, shallow, 5.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_false()


func test_aground_no_water_and_settled_is_aground() -> void:
	# Beached past any WaterSurface region entirely: no buoyancy at all, and settled.
	assert_bool(B.aground_now(false, -10.0, 0.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_true()


func test_aground_no_water_but_falling_is_not_aground() -> void:
	# Launched clear of the water polygon mid-air: not settled yet.
	assert_bool(B.aground_now(false, -10.0, 5.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_false()


func test_aground_hold_accumulates_while_true_and_resets_on_false() -> void:
	var s := B.aground_hold(0.0, true, DELTA)
	assert_float(s).is_equal_approx(DELTA, 1e-9)
	s = B.aground_hold(s, true, DELTA)
	assert_float(s).is_equal_approx(2.0 * DELTA, 1e-9)
	s = B.aground_hold(s, false, DELTA)
	assert_float(s).is_equal(0.0)


# --- depth sounder (PGN 128267, read off the same seabed the hull collides with) --

func _shoal_warn() -> float:
	# The threshold is the CONTRACT's, never a second copy here.
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var data := ContractScript.ContractData.parse(file.get_as_text())
	return data.get_signal_def("depth", "out").warn


func test_sounding_is_the_water_under_the_keel() -> void:
	# Transducer 5.65 m up, bed at 0: 5.65 m under it.
	assert_float(BoatT.sounding(true, 5.65, 0.0)).is_equal_approx(5.65, 1e-6)
	# Bed right at the transducer: no water under the keel, and that is a real 0.
	assert_float(BoatT.sounding(true, 5.65, 5.65)).is_equal(0.0)


func test_sounding_never_reads_negative() -> void:
	# Hard aground with the bed above the keel line: still 0, not a number no sounder produces.
	assert_float(BoatT.sounding(true, 5.65, 7.0)).is_equal(0.0)


func test_sounding_with_no_bottom_is_the_invalid_value_and_not_zero() -> void:
	# Off every terrain's extent, or out of the water: NO DEPTH, never the value an alarm acts on.
	assert_float(BoatT.sounding(false, 5.65, 0.0)).is_equal(BoatT.DEPTH_INVALID)
	assert_float(BoatT.DEPTH_INVALID).is_equal(-1.0)
	assert_float(BoatT.DEPTH_INVALID).is_less(0.0)


## No height texture, so height_at is the node's own Y — a flat bed at `y` over a square extent.
func _bed(y: float, extent := 100.0, pos_xz := Vector2.ZERO) -> HeightmapTerrain:
	var t: HeightmapTerrain = auto_free(TerrainScript.new())
	t.terrain_size = Vector2(extent, extent)
	t.position = Vector3(pos_xz.x, y, pos_xz.y)
	add_child(t)
	return t


func test_seabed_sounding_reads_the_water_between_the_transducer_and_the_bed() -> void:
	var terrains: Array[Node] = [_bed(0.0)]
	assert_float(B.seabed_sounding(Vector3(0.0, 5.65, 0.0), terrains)).is_equal_approx(5.65, 1e-5)
	# It is the POINT's Y that is measured, not the hull's: this is what puts the reading on the
	# probe plane rather than at the waterline, and it is the whole agreement with aground_now.
	assert_float(B.seabed_sounding(Vector3(0.0, 3.0, 0.0), terrains)).is_equal_approx(3.0, 1e-5)


func test_seabed_sounding_off_every_extent_has_no_bottom() -> void:
	# contains_xz is the gate: height_at CLAMPS its UV outside the extent, so without it the boat
	# would sound the terrain's EDGE height from open water and publish a fabricated bottom.
	var terrains: Array[Node] = [_bed(0.0, 40.0)]
	assert_float(B.seabed_sounding(Vector3(500.0, 5.0, 0.0), terrains)).is_equal(BoatT.DEPTH_INVALID)
	var none: Array[Node] = []
	assert_float(B.seabed_sounding(Vector3(0.0, 5.0, 0.0), none)).is_equal(BoatT.DEPTH_INVALID)


func test_seabed_sounding_takes_the_topmost_bed_where_two_overlap() -> void:
	# The shallower of two overlapping terrains is the one the hull would touch first.
	var terrains: Array[Node] = [_bed(0.0), _bed(2.0)]
	assert_float(B.seabed_sounding(Vector3(0.0, 6.0, 0.0), terrains)).is_equal_approx(4.0, 1e-5)
	terrains.reverse()
	assert_float(B.seabed_sounding(Vector3(0.0, 6.0, 0.0), terrains)).is_equal_approx(4.0, 1e-5)


func test_the_shoal_alarm_fires_while_the_boat_is_still_floating() -> void:
	# depth and the aground bit are two readings of ONE seabed, and the transducer rides the PROBE
	# PLANE — the plane aground_now itself measures — so the three events below fall in one order.
	# Each step is typed against the same FLOAT_DEPTH the predicate is given, so a threshold moving
	# under either reading breaks this; the WIRING that puts the transducer on that plane is pinned
	# by the seabed_sounding cases above and by test_boat_vehicle.gd, which ticks a real hull.
	var warn := _shoal_warn()
	assert_float(warn).is_greater(0.0)
	# 1. The alarm, with the bed a whole warn below a hull that only draws FLOAT_DEPTH: every probe
	#    is still at its rest depth, so nothing is aground.
	assert_float(warn).is_greater(FLOAT_DEPTH)
	assert_bool(B.aground_now(true, FLOAT_DEPTH, 0.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_false()
	# 2. The bed touches the probe plane the transducer rides: a real 0, reached while the hull is
	#    still floating at the rest depth asserted above.
	assert_float(BoatT.sounding(true, 0.0, 0.0)).is_equal(0.0)
	# 3. Only once the bed has come up far enough to hold the hull shallower than a floating one
	#    would sit does the bit set — after the alarm, and after the sounding has bottomed out.
	assert_bool(B.aground_now(true, FLOAT_DEPTH * B.AGROUND_SHALLOW_FRAC * 0.5, 0.0, FLOAT_DEPTH,
			B.AGROUND_SHALLOW_FRAC, B.AGROUND_VSPEED)).is_true()


# --- thrust + rudder ------------------------------------------------------------

func test_thrust_scale_forward_full_reverse_scaled() -> void:
	assert_float(B.thrust_scale(1.0, 0.4)).is_equal(1.0)
	assert_float(B.thrust_scale(0.5, 0.4)).is_equal(0.5)
	assert_float(B.thrust_scale(-1.0, 0.4)).is_equal_approx(-0.4, 1e-6)
	assert_float(B.thrust_scale(0.0, 0.4)).is_equal(0.0)
	# Out-of-range input clamps first.
	assert_float(B.thrust_scale(2.0, 0.4)).is_equal(1.0)


func test_rudder_authority_needs_flow() -> void:
	# Dead in the water, no throttle: no flow over the blade, no turn.
	assert_float(B.rudder_authority(0.0, 0.0)).is_equal(0.0)
	# Prop wash alone gives partial authority from standstill (turn out of a dock).
	assert_float(B.rudder_authority(0.0, 1.0)).is_equal_approx(B.RUDDER_PROP_WASH, 1e-6)
	# Full authority at/above the reference speed, clamped at 1.
	assert_float(B.rudder_authority(B.RUDDER_SPEED_REF, 0.0)).is_equal(1.0)
	assert_float(B.rudder_authority(30.0, 1.0)).is_equal(1.0)
	# Reverse flow works the blade too.
	assert_float(B.rudder_authority(-B.RUDDER_SPEED_REF, 0.0)).is_equal(1.0)


# --- trim model (modeled honest value, like engine_load) ------------------------

func test_trim_step_chases_forward_throttle() -> void:
	# 40 %/s toward throttle*100; one second at full throttle from zero.
	assert_float(BoatT.trim_step(0.0, 1.0, 40.0, 1.0)).is_equal_approx(40.0, 1e-6)
	# move_toward never overshoots the target.
	assert_float(BoatT.trim_step(95.0, 1.0, 40.0, 1.0)).is_equal(100.0)
	# Off throttle / reverse both trim back toward zero.
	assert_float(BoatT.trim_step(50.0, 0.0, 40.0, 1.0)).is_equal_approx(10.0, 1e-6)
	assert_float(BoatT.trim_step(50.0, -1.0, 40.0, 1.0)).is_equal_approx(10.0, 1e-6)


# --- apparent / true wind (PGN 130306, read out of the sim) ---------------------

func test_motoring_in_dead_calm_reads_its_own_speed_dead_ahead() -> void:
	# Bow = -Z, so 5 m/s ahead is (0, 0, -5); the air comes from straight over the bow.
	var aw := BoatT.apparent_wind(Vector3(0.0, 0.0, -5.0), Vector3.ZERO, Basis.IDENTITY)
	assert_float(aw.x).is_equal_approx(5.0, 1e-6)
	assert_float(aw.y).is_equal_approx(0.0, 1e-6)


func test_running_dead_downwind_at_wind_speed_is_calm_on_deck() -> void:
	# The angle is genuinely undefined here; 0 is the pinned value, and the SPEED is what a
	# reader acts on.
	var wind := Vector3(0.0, 0.0, -7.0)
	var aw := BoatT.apparent_wind(wind, wind, Basis.IDENTITY)
	assert_float(aw.x).is_equal(0.0)
	assert_float(aw.y).is_equal(0.0)


func test_apparent_wind_angle_is_positive_to_starboard() -> void:
	# Hull stopped, so the apparent wind IS the true wind. WindField blows TOWARD its heading,
	# so wind toward -X comes FROM starboard (+X) on a boat facing -Z.
	var eps := 1e-4
	assert_float(BoatT.apparent_wind(Vector3.ZERO, Vector3(-6.0, 0.0, 0.0),
			Basis.IDENTITY).y).is_equal_approx(90.0, eps)
	assert_float(BoatT.apparent_wind(Vector3.ZERO, Vector3(6.0, 0.0, 0.0),
			Basis.IDENTITY).y).is_equal_approx(-90.0, eps)
	# Blowing toward -Z is a wind from dead astern.
	assert_float(absf(BoatT.apparent_wind(Vector3.ZERO, Vector3(0.0, 0.0, -6.0),
			Basis.IDENTITY).y)).is_equal_approx(180.0, eps)
	# ...and toward +Z is dead on the bow.
	assert_float(BoatT.apparent_wind(Vector3.ZERO, Vector3(0.0, 0.0, 6.0),
			Basis.IDENTITY).y).is_equal_approx(0.0, eps)


func test_apparent_wind_speed_adds_hull_speed_beating_and_cancels_running() -> void:
	var head := Vector3(0.0, 0.0, 4.0)    # blows toward +Z: a headwind for a boat facing -Z
	assert_float(BoatT.apparent_wind(Vector3(0.0, 0.0, -5.0), head,
			Basis.IDENTITY).x).is_equal_approx(9.0, 1e-6)
	assert_float(BoatT.apparent_wind(Vector3(0.0, 0.0, 5.0), head,
			Basis.IDENTITY).x).is_equal_approx(1.0, 1e-6)


func test_true_wind_inverts_the_wind_fields_toward_convention() -> void:
	# Level 6's field: 200 deg TOWARD at 5 m/s, so it comes FROM 020.
	var tw := BoatT.true_wind(W.base_vector(200.0, 5.0))
	assert_float(tw.x).is_equal_approx(5.0, 1e-5)
	assert_float(tw.y).is_equal_approx(20.0, 1e-4)
	# The inversion holds all the way round, including across the 0/360 wrap.
	for deg: float in [0.0, 90.0, 179.0, 181.0, 270.0, 359.0]:
		var t2 := BoatT.true_wind(W.base_vector(deg, 3.0))
		assert_float(t2.y) 			.override_failure_message("toward %f did not inverse-map" % deg) 			.is_equal_approx(fposmod(deg + 180.0, 360.0), 1e-3)


func test_a_heeling_hull_reads_the_same_apparent_wind() -> void:
	# The angle is measured in the water plane, so heel must not move it — and a beam wind is
	# itself what lays the hull over, through the windage term above the COM. A Y-only flatten
	# would shrink the lateral term by cos(heel) and swing AWA toward the bow as she heels.
	var wind := Vector3(-6.0, 0.0, 0.0)          # blows toward -X: comes FROM starboard
	var level := BoatT.apparent_wind(Vector3.ZERO, wind, Basis.IDENTITY)
	# Heel is rotation about the bow axis and pitch is rotation about the beam; neither turns
	# the bow, so both leave the reading alone. (Composing the two DOES yaw the bow, which is
	# a real heading change and not what this pins.)
	for deg: float in [10.0, 25.0, -25.0]:
		var attitudes: Array[Basis] = [
			Basis(Vector3(0.0, 0.0, -1.0), deg_to_rad(deg)),   # heel
			Basis(Vector3.RIGHT, deg_to_rad(deg)),             # pitch
		]
		for b in attitudes:
			var tilted := BoatT.apparent_wind(Vector3.ZERO, wind, b)
			assert_float(tilted.x) 				.override_failure_message("AWS moved at %f deg" % deg) 				.is_equal_approx(level.x, 1e-5)
			assert_float(tilted.y) 				.override_failure_message("AWA moved at %f deg" % deg) 				.is_equal_approx(level.y, 1e-3)


func test_true_wind_in_dead_calm_is_zero() -> void:
	var tw := BoatT.true_wind(Vector3.ZERO)
	assert_float(tw.x).is_equal(0.0)
	assert_float(tw.y).is_equal(0.0)


# --- flow_toward, and the track/tide readings built on it -----------------------

func test_flow_toward_reads_the_bearing_a_vector_points_at() -> void:
	# The one place both a current and (inverted) a wind get their bearing. Bow/north is -Z.
	var eps := 1e-4
	assert_float(BoatT.flow_toward(Vector3(0.0, 0.0, -4.0)).y).is_equal_approx(0.0, eps)
	assert_float(BoatT.flow_toward(Vector3(4.0, 0.0, 0.0)).y).is_equal_approx(90.0, eps)
	assert_float(BoatT.flow_toward(Vector3(0.0, 0.0, 4.0)).y).is_equal_approx(180.0, eps)
	assert_float(BoatT.flow_toward(Vector3(-4.0, 0.0, 0.0)).y).is_equal_approx(270.0, eps)
	assert_float(BoatT.flow_toward(Vector3(0.0, 0.0, -4.0)).x).is_equal_approx(4.0, 1e-6)


func test_flow_toward_ignores_the_vertical_and_reads_zero_for_no_flow() -> void:
	# A heaving hull must not have its speed over the ground inflated by the wave it is riding,
	# and a vector with no length has no bearing: (0, 0) is the sentinel `cog` publishes.
	assert_float(BoatT.flow_toward(Vector3(3.0, 9.0, -4.0)).x).is_equal_approx(5.0, 1e-6)
	var none := BoatT.flow_toward(Vector3(0.0, 6.0, 0.0))
	assert_float(none.x).is_equal(0.0)
	assert_float(none.y).is_equal(0.0)


func test_in_still_water_the_two_speeds_and_the_two_courses_agree() -> void:
	# The whole speed-log-versus-GPS distinction, stated as its degenerate case: with no tide the
	# speed log and the GPS read one number, and a hull with no leeway steers where it points.
	# A hull making 6 m/s straight along its own bow, with no tide to set it off. The expected
	# course is a LITERAL, not a second call to the function under test: comparing flow_toward
	# with heading_from_forward on the same vector passes however wrong the convention is.
	var cases := {0.0: Vector3(0.0, 0.0, -6.0), 90.0: Vector3(6.0, 0.0, 0.0),
			180.0: Vector3(0.0, 0.0, 6.0), 270.0: Vector3(-6.0, 0.0, 0.0)}
	for expected: float in cases:
		var velocity: Vector3 = cases[expected]
		var ground := BoatT.flow_toward(velocity)
		var water := BoatT.flow_toward(velocity - Vector3.ZERO)
		assert_float(ground.x).is_equal(water.x)
		assert_float(ground.y).is_equal(water.y)
		# ...and that course is the bearing the bow is on, since a hull with no leeway and no
		# tide goes where it points. `heading` is written off the same convention by
		# BaseVehicle._update_telemetry, so COG and HDG read one number here.
		assert_float(ground.y) \
			.override_failure_message("course is not the heading on %03d" % expected) \
			.is_equal_approx(expected, 1e-4)


func test_a_beam_tide_crabs_the_track_without_touching_the_log() -> void:
	# Making 5 m/s through the water due north, with 1.5 m/s of stream setting due east.
	var stw := 5.0
	var drift := 1.5
	var through_water := Vector3(0.0, 0.0, -stw)
	var current := Vector3(drift, 0.0, 0.0)
	var velocity := through_water + current
	assert_float(BoatT.flow_toward(velocity - current).x).is_equal_approx(stw, 1e-6)
	# The resulting crab is atan(drift/stw), NOT asin: asin is the angle you would STEER to
	# hold a track against this stream, and this is the track the stream produces instead.
	var track := BoatT.flow_toward(velocity)
	assert_float(track.x).is_equal_approx(sqrt(stw * stw + drift * drift), 1e-6)
	assert_float(track.y).is_equal_approx(rad_to_deg(atan(drift / stw)), 1e-4)
	# The tide reads out with NO inversion, unlike the wind: set is where it goes.
	var tide := BoatT.flow_toward(current)
	assert_float(tide.x).is_equal_approx(drift, 1e-6)
	assert_float(tide.y).is_equal_approx(90.0, 1e-4)


func test_stemming_the_tide_holds_the_log_up_while_the_track_stops() -> void:
	# The picture that makes STW vs SOG obvious by driving: pointing into the stream at exactly
	# drift rate, the boat sits still over the bed with full steerage way.
	var current := Vector3(0.0, 0.0, -1.5)
	var velocity := Vector3.ZERO
	assert_float(BoatT.flow_toward(velocity).x).is_equal(0.0)
	assert_float(BoatT.flow_toward(velocity - current).x).is_equal_approx(1.5, 1e-6)


# --- engine room & tanks (PGN 127489 / 127505, modeled honest values) -----------

func test_fuel_rate_is_zero_off_and_rises_with_load() -> void:
	assert_float(BoatT.fuel_rate_model(1.0, false)).is_equal(0.0)
	assert_float(BoatT.fuel_rate_model(0.0, true)).is_equal_approx(BoatT.FUEL_RATE_IDLE, 1e-6)
	assert_float(BoatT.fuel_rate_model(1.0, true)) \
			.is_equal_approx(BoatT.FUEL_RATE_IDLE + BoatT.FUEL_RATE_LOAD, 1e-6)
	assert_float(BoatT.fuel_rate_model(1.0, true)).is_greater(BoatT.fuel_rate_model(0.0, true))


func test_oil_press_is_zero_off_low_at_idle_nominal_above_it() -> void:
	# Off (key not at Ignition) reads zero even at a plausible idle rpm — the gate is `running`,
	# not `rpm <= 0`, because the boat's inert engine model never actually zeros rpm off-ignition.
	assert_float(BoatT.oil_press_model(800.0, 800.0, false)).is_equal(0.0)
	assert_float(BoatT.oil_press_model(800.0, 800.0, true)) \
			.is_equal_approx(BoatT.OIL_PRESS_IDLE, 1e-6)
	assert_float(BoatT.oil_press_model(1200.0, 800.0, true)) \
			.is_equal_approx(BoatT.OIL_PRESS_NOMINAL, 1e-6)
	assert_float(BoatT.oil_press_model(2500.0, 800.0, true)) \
			.is_equal_approx(BoatT.OIL_PRESS_NOMINAL, 1e-6)


func test_tank_step_drains_fresh_fills_waste_holds_livewell() -> void:
	var start := [100.0, 0.0, 50.0]
	assert_array(BoatT.tank_step(start, false, 1.0)).is_equal(start)
	var stepped := BoatT.tank_step(start, true, 1.0)
	assert_float(stepped[0]).is_less(start[0])
	assert_float(stepped[1]).is_greater(start[1])
	assert_float(stepped[2]).is_equal(start[2])
	# Clamps at the bounds rather than running past them.
	assert_float(BoatT.tank_step([1.0, 99.0, 50.0], true, 10.0)[0]).is_equal(0.0)
	assert_float(BoatT.tank_step([1.0, 99.0, 50.0], true, 10.0)[1]).is_equal(100.0)


func test_boat_telemetry_bridge_dict_adds_boat_fields() -> void:
	var t := BoatT.new()
	t.pitch = 4.5
	t.roll = -2.0
	t.rudder_actual = -60
	t.trim = 35
	var d: Dictionary = t.to_bridge_dict()
	assert_float(d["pitch"]).is_equal(4.5)
	assert_float(d["roll"]).is_equal(-2.0)
	assert_int(d["rudder_actual"]).is_equal(-60)
	assert_int(d["trim"]).is_equal(35)
	# Base fields still ride along (super() first, tractor pattern).
	assert_bool(d.has("speed")).is_true()
	assert_bool(d.has("status")).is_true()
	t.awa = -35.0
	t.aws = 9.5
	t.twd = 20.0
	t.tws = 5.0
	d = t.to_bridge_dict()
	assert_float(d["awa"]).is_equal(-35.0)
	assert_float(d["aws"]).is_equal(9.5)
	assert_float(d["twd"]).is_equal(20.0)
	assert_float(d["tws"]).is_equal(5.0)
	t.stw = 5.0
	t.sog = 5.22
	t.cog = 16.7
	t.current_set = 110.0
	t.current_drift = 1.5
	d = t.to_bridge_dict()
	assert_float(d["stw"]).is_equal(5.0)
	assert_float(d["sog"]).is_equal(5.22)
	assert_float(d["cog"]).is_equal(16.7)
	assert_float(d["current_set"]).is_equal(110.0)
	assert_float(d["current_drift"]).is_equal(1.5)
	t.depth = 5.65
	d = t.to_bridge_dict()
	assert_float(d["depth"]).is_equal(5.65)
	t.sail_angle = -62.0
	d = t.to_bridge_dict()
	assert_float(d["sail_angle"]).is_equal(-62.0)
	t.fuel_rate = 6.2
	t.oil_press = 310.0
	t.tank_level = [80.0, 20.0, 50.0]
	d = t.to_bridge_dict()
	assert_float(d["fuel_rate"]).is_equal(6.2)
	assert_float(d["oil_press"]).is_equal(310.0)
	assert_array(d["tank_level"]).is_equal([80.0, 20.0, 50.0])
