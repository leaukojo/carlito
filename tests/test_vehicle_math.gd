extends GdUnitTestSuite
## Free-body math shared by boat, drone, plane. Union of cases (boat/drone/plane only
## cover their own). Key: 60 Hz one-tick clamp discipline (damper zeroes, never reverses).

const M := preload("res://src/vehicles/base/vehicle_math.gd")

const DELTA := 1.0 / 60.0

# Round numbers so expected values are hand-checkable.
const MASS := 800.0
const INERTIA := 900.0


# --- damped_force: scalar drag / rate damping ----------------------------------

func test_damped_force_opposes_velocity() -> void:
	assert_float(M.damped_force(2.0, 100.0, MASS, DELTA)).is_equal_approx(-200.0, 1e-6)
	assert_float(M.damped_force(-2.0, 100.0, MASS, DELTA)).is_equal_approx(200.0, 1e-6)
	assert_float(M.damped_force(0.0, 100.0, MASS, DELTA)).is_equal(0.0)


func test_damped_force_clamped_to_one_tick_zeroing() -> void:
	# An absurd coefficient may at most ZERO the velocity in one tick, never reverse
	# it (RayWheel's lateral cap — the parked-boat anti-jitter rule).
	var v := 1.5
	var tick_cap := MASS * v / DELTA
	assert_float(M.damped_force(v, 1e12, MASS, DELTA)).is_equal_approx(-tick_cap, 1e-3)


func test_damped_force_used_as_a_torque() -> void:
	# The plane applies the same fn to rotation rates against an inertia.
	assert_float(M.damped_force(2.0, 3.0, INERTIA, DELTA)).is_equal_approx(-6.0, 1e-4)
	var tick_cap := INERTIA * 2.0 / DELTA
	assert_float(M.damped_force(2.0, 1e12, INERTIA, DELTA)).is_equal_approx(-tick_cap, 1e-2)


# --- clamped_damper: the same rule in three dimensions -------------------------

func test_clamped_damper_opposes_velocity() -> void:
	var f := M.clamped_damper(Vector3(2.0, 0.0, 0.0), 3.0, MASS, DELTA)
	assert_vector(f).is_equal_approx(Vector3(-6.0, 0.0, 0.0), Vector3.ONE * 1e-4)


func test_clamped_damper_clamped_to_one_tick_zeroing() -> void:
	var v := Vector3(0.0, 0.0, 1.5)
	var tick_cap := MASS * v.length() / DELTA
	var f := M.clamped_damper(v, 1e12, MASS, DELTA)
	assert_float(f.length()).is_equal_approx(tick_cap, 1e-2)
	# Direction is exactly opposite the velocity (no reversal).
	assert_float(f.normalized().dot(v.normalized())).is_equal_approx(-1.0, 1e-5)


func test_clamped_damper_zero_velocity_is_zero() -> void:
	assert_vector(M.clamped_damper(Vector3.ZERO, 5.0, MASS, DELTA)).is_equal(Vector3.ZERO)


# --- air_damper: clamped_damper against the flow, not the ground ---------------

func test_air_damper_in_still_air_is_the_absolute_velocity_term() -> void:
	# The equivalence every shipped drag coefficient rests on. Dead calm is what a level with
	# no WindField reports, so on every shipped level this fn IS the old ground-relative
	# damper the boat/plane/drone were each tuned against. tests/test_wind.gd pins the same
	# claim from the vehicle side; this is it stated where the arithmetic lives.
	for vel: Vector3 in [Vector3(3.0, 0.0, -12.0), Vector3(0.0, -4.0, 0.0), Vector3.ZERO]:
		var ground := M.clamped_damper(vel, 7.0, MASS, DELTA)
		assert_vector(M.air_damper(vel, Vector3.ZERO, 7.0, MASS, DELTA)) \
				.is_equal_approx(ground, Vector3.ONE * 1e-6)


func test_air_damper_opposes_the_flow_over_the_body() -> void:
	# 20 m/s of ground speed into an 8 m/s headwind is 28 m/s of flow, and 5 m/s downwind of a
	# 20 m/s tailwind is 15 m/s the other way — the drag reverses even though the body has not.
	var head := M.air_damper(Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, 8.0), 2.0, MASS, DELTA)
	assert_vector(head).is_equal_approx(Vector3(0.0, 0.0, 56.0), Vector3.ONE * 1e-4)
	var over := M.air_damper(Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -20.0), 2.0, MASS, DELTA)
	assert_vector(over).is_equal_approx(Vector3(0.0, 0.0, -30.0), Vector3.ONE * 1e-4)


func test_air_damper_is_zero_when_the_body_drifts_with_the_air() -> void:
	# A balloon in a gale feels no drag. This is also what stops the wind acting as a second
	# propulsion term: it can only ever push a body up TO the air speed, never past it.
	var wind := Vector3(6.0, 0.0, -3.0)
	assert_vector(M.air_damper(wind, wind, 1e6, MASS, DELTA)).is_equal(Vector3.ZERO)


func test_air_damper_axis_mask_splits_the_coefficients() -> void:
	# The drone damps horizontal and vertical on two different numbers, so each call sees only
	# its own axes. The masked components come back exactly zero; the kept ones are what the
	# unmasked call makes of a velocity with the others already removed.
	var vel := Vector3(3.0, -9.0, -4.0)
	var wind := Vector3(1.0, 0.0, 0.0)
	var h := M.air_damper(vel, wind, 2.0, MASS, DELTA, Vector3(1.0, 0.0, 1.0))
	assert_float(h.y).is_equal(0.0)
	assert_vector(h).is_equal_approx(
			M.clamped_damper(Vector3(2.0, 0.0, -4.0), 2.0, MASS, DELTA), Vector3.ONE * 1e-6)
	var v := M.air_damper(vel, wind, 2.0, MASS, DELTA, Vector3(0.0, 1.0, 0.0))
	assert_float(v.x).is_equal(0.0)
	assert_float(v.z).is_equal(0.0)
	assert_vector(v).is_equal_approx(
			M.clamped_damper(Vector3(0.0, -9.0, 0.0), 2.0, MASS, DELTA), Vector3.ONE * 1e-6)


func test_air_damper_keeps_the_one_tick_clamp() -> void:
	# The clamp is measured against the RELATIVE speed, since that is the motion the force
	# opposes — an absurd coefficient may at most bring the body to the air's speed this tick.
	var vel := Vector3(0.0, 0.0, -20.0)
	var wind := Vector3(0.0, 0.0, -5.0)
	var tick_cap := MASS * 15.0 / DELTA
	var f := M.air_damper(vel, wind, 1e12, MASS, DELTA)
	assert_float(f.length()).is_equal_approx(tick_cap, 1e-2)
	assert_float(f.normalized().dot(Vector3(0.0, 0.0, -1.0))).is_equal_approx(-1.0, 1e-5)


# --- flow_authority: no flow over the surface, no control ----------------------

func test_flow_authority_is_linear_up_to_the_reference_speed() -> void:
	# The plane's tail: control_authority(v, 15) with no prop wash.
	assert_float(M.flow_authority(0.0, 15.0)).is_equal(0.0)
	assert_float(M.flow_authority(7.5, 15.0)).is_equal_approx(0.5, 1e-6)
	assert_float(M.flow_authority(15.0, 15.0)).is_equal_approx(1.0, 1e-6)
	assert_float(M.flow_authority(60.0, 15.0)).is_equal(1.0)
	# Flying backwards still moves air over the surfaces.
	assert_float(M.flow_authority(-7.5, 15.0)).is_equal_approx(0.5, 1e-6)


func test_flow_authority_prop_wash_turns_a_boat_out_of_a_dock() -> void:
	# The boat's rudder: RUDDER_SPEED_REF 6, RUDDER_PROP_WASH 0.5. Standing still on full
	# throttle the blade still gets half authority, which is the whole reason the term exists.
	assert_float(M.flow_authority(0.0, 6.0, 0.5, 1.0)).is_equal_approx(0.5, 1e-6)
	assert_float(M.flow_authority(0.0, 6.0, 0.5, 0.0)).is_equal(0.0)
	# Reverse throttle washes the blade just as well as forward.
	assert_float(M.flow_authority(0.0, 6.0, 0.5, -1.0)).is_equal_approx(0.5, 1e-6)
	# Hull speed and wash add, and the total clamps at 1.
	assert_float(M.flow_authority(3.0, 6.0, 0.5, 0.5)).is_equal_approx(0.75, 1e-6)
	assert_float(M.flow_authority(6.0, 6.0, 0.5, 1.0)).is_equal(1.0)


func test_flow_authority_survives_a_zero_reference_speed() -> void:
	# maxf(0.1, ref) rather than a divide by zero — an authored 0 gives full authority at any
	# speed instead of an inf, which is a knob set wrong, not a crash.
	assert_float(M.flow_authority(1.0, 0.0)).is_equal(1.0)
	assert_float(M.flow_authority(0.0, 0.0)).is_equal(0.0)


# --- yaw_torque: drives the yaw rate toward target, clamped --------------------

func test_yaw_torque_pushes_toward_target_rate() -> void:
	# Below target: positive torque; above target: negative.
	assert_float(M.yaw_torque(2.0, 0.0, 4.0, 0.6, DELTA, 6.0)).is_greater(0.0)
	assert_float(M.yaw_torque(0.0, 2.0, 4.0, 0.6, DELTA, 6.0)).is_less(0.0)
	# At the target: no torque.
	assert_float(M.yaw_torque(1.5, 1.5, 4.0, 0.6, DELTA, 6.0)).is_equal(0.0)


func test_yaw_torque_capped_and_one_tick_clamped() -> void:
	# A huge gain is capped at max_torque.
	assert_float(M.yaw_torque(5.0, 0.0, 1e6, 0.6, DELTA, 6.0)).is_equal(6.0)
	# With a tiny error the one-tick cap (inertia*err/delta) binds below max_torque.
	var err := 0.001
	var tick_cap := 0.6 * err / DELTA
	assert_float(M.yaw_torque(err, 0.0, 1e6, 0.6, DELTA, 6.0)).is_equal_approx(tick_cap, 1e-4)
	# Same at the plane's scale, where the cap is four orders of magnitude larger.
	var p_err := 0.00001
	var p_cap := INERTIA * p_err / DELTA
	assert_float(M.yaw_torque(p_err, 0.0, 1e9, INERTIA, DELTA, 6000.0)) \
			.is_equal_approx(p_cap, 1e-4)


# --- inertia_of: box footprint, symmetric in its two dimensions ----------------

func test_inertia_of_box_footprint() -> void:
	# m (a^2 + b^2) / 12 with round numbers: 12 * (4 + 2) / 12 = 6.
	assert_float(M.inertia_of(12.0, 2.0, sqrt(2.0))).is_equal_approx(6.0, 1e-5)
	# The boat's hull footprint: 1200 * (16 + 4) / 12 = 2000.
	assert_float(M.inertia_of(1200.0, 4.0, 2.0)).is_equal_approx(2000.0, 1e-6)


func test_inertia_of_is_symmetric_in_its_dimensions() -> void:
	# Why the boat may pass length/width and the flyers width/depth.
	assert_float(M.inertia_of(1200.0, 4.0, 2.0)) \
			.is_equal_approx(M.inertia_of(1200.0, 2.0, 4.0), 1e-6)


# --- pitch / roll extraction (straight from the sim's basis) --------------------

func test_pitch_deg_nose_up_positive() -> void:
	assert_float(M.pitch_deg(Basis.IDENTITY)).is_equal_approx(0.0, 1e-4)
	# Rotating about +X (right axis) lifts the nose/bow (-Z gains +Y).
	assert_float(M.pitch_deg(Basis(Vector3.RIGHT, deg_to_rad(20.0)))) \
			.is_equal_approx(20.0, 1e-4)
	assert_float(M.pitch_deg(Basis(Vector3.RIGHT, deg_to_rad(-35.0)))) \
			.is_equal_approx(-35.0, 1e-4)


func test_roll_deg_starboard_down_positive() -> void:
	assert_float(M.roll_deg(Basis.IDENTITY)).is_equal_approx(0.0, 1e-4)
	# Rotating about the forward axis (-Z) tips the starboard/right side down.
	assert_float(M.roll_deg(Basis(Vector3(0, 0, -1), deg_to_rad(30.0)))) \
			.is_equal_approx(30.0, 1e-4)
	assert_float(M.roll_deg(Basis(Vector3(0, 0, -1), deg_to_rad(-45.0)))) \
			.is_equal_approx(-45.0, 1e-4)
	# atan2 keeps a full capsize/flip readable (contract range -180..180).
	assert_float(absf(M.roll_deg(Basis(Vector3(0, 0, -1), PI)))) \
			.is_equal_approx(180.0, 1e-4)

# --- road resistance: aero + rolling, the wheeled vehicles' whole drag model ----

func test_aero_drag_is_the_textbook_formula() -> void:
	# 0.5 * 1.225 * 2.0 * 10^2 = 122.5 N.
	assert_float(M.aero_drag(10.0, 2.0)).is_equal_approx(122.5, 1e-4)
	assert_float(M.aero_drag(0.0, 2.0)).is_equal(0.0)


func test_aero_drag_is_quadratic_in_speed() -> void:
	# The model exists for this. Godot's linear damp is linear in v, which is
	# why it bit hardest where reality is weakest (low speed) and let go at the top end.
	var at_10 := M.aero_drag(10.0, 1.5)
	assert_float(M.aero_drag(20.0, 1.5)).is_equal_approx(at_10 * 4.0, 1e-4)
	assert_float(M.aero_drag(30.0, 1.5)).is_equal_approx(at_10 * 9.0, 1e-4)


func test_aero_drag_scales_with_area_and_ignores_a_negative_one() -> void:
	assert_float(M.aero_drag(25.0, 2.0)).is_equal_approx(M.aero_drag(25.0, 1.0) * 2.0, 1e-4)
	assert_float(M.aero_drag(25.0, -1.0)).is_equal(0.0)


func test_aero_downforce_is_the_drag_formula_on_the_lift_coefficient() -> void:
	# Same 0.5 * rho * C*A * v^2, different coefficient — 0.5 * 1.225 * 2.24 * 38.89^2 = 2075 N,
	# the ~0.24 g the open-wheelers gain at the 140 km/h their corners used to let go at.
	assert_float(M.aero_downforce(38.89, 2.24)).is_equal_approx(2075.0, 1.0)
	assert_float(M.aero_downforce(10.0, 2.0)).is_equal_approx(M.aero_drag(10.0, 2.0), 1e-6)
	assert_float(M.aero_downforce(0.0, 2.24)).is_equal(0.0)


func test_aero_downforce_climbs_with_v_squared() -> void:
	# Without it a tyre's cornering limit is flat in speed, which is why an
	# open-wheeler that is stable at 60 let go at 140 on the same steering input. Doubling the
	# speed quadruples the normal load the wing adds.
	var at_20 := M.aero_downforce(20.0, 2.24)
	assert_float(M.aero_downforce(40.0, 2.24)).is_equal_approx(at_20 * 4.0, 1e-4)
	assert_float(M.aero_downforce(80.0, 2.24)).is_equal_approx(at_20 * 16.0, 1e-4)


func test_aero_downforce_is_zero_without_a_wing() -> void:
	# Every body but the two open-wheelers declares downforce_area 0, so this is the path
	# almost the whole catalog takes.
	assert_float(M.aero_downforce(80.0, 0.0)).is_equal(0.0)
	assert_float(M.aero_downforce(80.0, -2.0)).is_equal(0.0)


func test_rolling_drag_is_crr_times_the_normal_load() -> void:
	assert_float(M.rolling_drag(0.012, 10000.0)).is_equal_approx(120.0, 1e-6)
	# An airborne wheel carries no load, so it resists nothing — the reason the load is read
	# off the springs rather than computed from mass * g.
	assert_float(M.rolling_drag(0.012, 0.0)).is_equal(0.0)
	assert_float(M.rolling_drag(0.012, -500.0)).is_equal(0.0)
	assert_float(M.rolling_drag(-0.01, 10000.0)).is_equal(0.0)


func test_road_resistance_sums_both_terms_and_opposes_velocity() -> void:
	var vel := Vector3(0.0, 0.0, -20.0)
	var f := M.road_resistance(vel, 0.6, 0.012, 10000.0, MASS, DELTA)
	var expected := M.aero_drag(20.0, 0.6) + M.rolling_drag(0.012, 10000.0)
	assert_float(f.length()).is_equal_approx(expected, 1e-4)
	assert_float(f.normalized().dot(vel.normalized())).is_equal_approx(-1.0, 1e-5)


func test_road_resistance_never_looks_at_mass() -> void:
	# The argument this exists for. Godot's linear damp is an acceleration
	# (F = mass * damp * v), so coupling a 24 t trailer to an 8 t tractor quadrupled the rig's
	# resistance. Neither term here reads the mass, so the same coefficients produce the same
	# force on a 260 kg body and on an 8 t truck — and a combination's drag is the SUM of the
	# two bodies' own, roughly 1.2x a rigid truck rather than 4x.
	var vel := Vector3(0.0, 0.0, -30.0)
	var light := M.road_resistance(vel, 0.6, 0.012, 10000.0, 260.0, DELTA)
	var heavy := M.road_resistance(vel, 0.6, 0.012, 10000.0, 8000.0, DELTA)
	assert_vector(light).is_equal_approx(heavy, Vector3.ONE * 1e-4)


func test_road_resistance_clamped_to_one_tick_zeroing() -> void:
	# The 60 Hz discipline: an absurd drag area may at most STOP the body this tick, never
	# push it backwards. `body_mass` enters here and nowhere else.
	var vel := Vector3(0.0, 0.0, -12.0)
	var tick_cap := MASS * vel.length() / DELTA
	var f := M.road_resistance(vel, 1e9, 0.0, 0.0, MASS, DELTA)
	assert_float(f.length()).is_equal_approx(tick_cap, 1e-2)
	assert_float(f.normalized().dot(vel.normalized())).is_equal_approx(-1.0, 1e-5)


func test_road_resistance_is_off_at_a_standstill() -> void:
	# Rolling resistance does not fade with speed, so without the floor it would keep shoving
	# a parked vehicle. Zero velocity and a crawl both come back exactly zero.
	assert_vector(M.road_resistance(Vector3.ZERO, 0.6, 0.012, 10000.0, MASS, DELTA)) 			.is_equal(Vector3.ZERO)
	assert_vector(M.road_resistance(Vector3(0.0, 0.0, -0.01), 0.6, 0.012, 10000.0, MASS, DELTA)) 			.is_equal(Vector3.ZERO)
	# A zero delta is a divide-by-zero in the clamp, not a physical case.
	assert_vector(M.road_resistance(Vector3(0.0, 0.0, -20.0), 0.6, 0.012, 1e4, MASS, 0.0)) 			.is_equal(Vector3.ZERO)
