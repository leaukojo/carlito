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


# --- carried_com: a load's mass-weighted pull on the centre of mass ---------------

func test_carried_com_is_the_mass_weighted_mean() -> void:
	# 7000 kg at z 0.3 and 1000 kg at z 2.3: (7000*0.3 + 1000*2.3) / 8000 = 0.55.
	var com := M.carried_com(Vector3(0.0, 0.8, 0.3), Vector3(0.0, 0.8, 2.3), 7000.0, 1000.0)
	assert_float(com.z).is_equal_approx(0.55, 1e-5)
	assert_float(com.y).is_equal_approx(0.8, 1e-5)


func test_carried_com_with_no_payload_is_the_base_exactly() -> void:
	# Exactly, not approximately: a detached tractor must write the spec COM bit for bit.
	var base := Vector3(0.0, 0.8305302, 0.3053797)
	assert_vector(M.carried_com(base, Vector3(1.0, 2.0, 3.0), 7000.0, 0.0)).is_equal(base)
	assert_vector(M.carried_com(base, Vector3(1.0, 2.0, 3.0), 7000.0, -5.0)).is_equal(base)


func test_carried_com_survives_a_massless_body() -> void:
	# A payload on a massless base sits at its own point; nothing at all keeps the base, never NaN.
	assert_vector(M.carried_com(Vector3.UP, Vector3.DOWN, 0.0, 2.0)).is_equal(Vector3.DOWN)
	assert_vector(M.carried_com(Vector3.UP, Vector3.DOWN, 0.0, 0.0)).is_equal(Vector3.UP)


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


func test_is_inverted_reads_the_up_axis_not_roll_alone() -> void:
	assert_bool(M.is_inverted(Basis.IDENTITY, 70.0)).is_false()
	# On its side and on its roof, about either axis: both are past 70 deg of tilt.
	assert_bool(M.is_inverted(Basis(Vector3(0, 0, -1), deg_to_rad(90.0)), 70.0)).is_true()
	assert_bool(M.is_inverted(Basis(Vector3(0, 0, -1), PI), 70.0)).is_true()
	assert_bool(M.is_inverted(Basis(Vector3.RIGHT, deg_to_rad(100.0)), 70.0)).is_true()
	# A steep grade or a hard lean is not overturned.
	assert_bool(M.is_inverted(Basis(Vector3(0, 0, -1), deg_to_rad(45.0)), 70.0)).is_false()
	assert_bool(M.is_inverted(Basis(Vector3.RIGHT, deg_to_rad(30.0)), 70.0)).is_false()
	# Yaw is not tilt: a body spun about its own up axis stays upright at any heading.
	assert_bool(M.is_inverted(Basis(Vector3.UP, deg_to_rad(170.0)), 70.0)).is_false()


func test_is_inverted_threshold_is_the_angle_from_world_up() -> void:
	var tilt := Basis(Vector3(0, 0, -1), deg_to_rad(60.0))
	assert_bool(M.is_inverted(tilt, 59.0)).is_true()
	assert_bool(M.is_inverted(tilt, 61.0)).is_false()


# --- point_velocity: the lever runs from the COM ---------------------------------

## Engine guard: a pure spin about a COM 2 m off the origin. The COM stays put while the origin
## sweeps ~2 m/s, so a lever from the origin reads every point that much wrong.
func test_point_velocity_matches_the_motion_of_a_point_on_an_off_origin_com() -> void:
	var b: RigidBody3D = auto_free(RigidBody3D.new())
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 4.0)
	cs.shape = box
	b.add_child(cs)
	b.gravity_scale = 0.0
	b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0.0, 0.5, 2.0)
	add_child(b)
	b.global_position = Vector3(0.0, 100.0, 0.0)
	await get_tree().physics_frame
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3(0.3, 1.0, 0.0)
	await get_tree().physics_frame
	var p_local := Vector3(1.0, -0.4, -1.5)
	var com := b.global_transform * b.center_of_mass
	var p := b.global_transform * p_local
	var v := M.point_velocity(b, p)
	await get_tree().physics_frame
	assert_vector(b.global_transform * b.center_of_mass).is_equal_approx(com, Vector3.ONE * 1e-4)
	# One tick's chord of the arc, ~0.03 m/s here, against the origin lever's ~2 m/s.
	assert_vector((b.global_transform * p_local - p) / DELTA) \
		.is_equal_approx(v, Vector3.ONE * 0.05)


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


# --- air_force: drag and side force against the wind, in the body frame ---------
# Bodies face -Z (Basis.IDENTITY): forward -Z, right +X.

func test_air_force_in_still_air_is_the_aero_drag_term_opposing_velocity() -> void:
	var vel := Vector3(0.0, 0.0, -20.0)
	var f := M.air_force(vel, Vector3.ZERO, Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)
	assert_float(f.length()).is_equal_approx(M.aero_drag(20.0, 0.6), 1e-4)
	assert_float(f.normalized().dot(vel.normalized())).is_equal_approx(-1.0, 1e-5)


func test_air_force_never_looks_at_mass() -> void:
	# Godot's linear damp is an acceleration (F = mass * damp * v), so coupling a 24 t trailer to an
	# 8 t tractor would quadruple the rig's drag. The force here never reads the mass, so a
	# combination's drag is the SUM of the two bodies' own.
	var vel := Vector3(4.0, 0.0, -30.0)
	var light := M.air_force(vel, Vector3.ZERO, Basis.IDENTITY, 0.6, 5.0, 260.0, DELTA)
	var heavy := M.air_force(vel, Vector3.ZERO, Basis.IDENTITY, 0.6, 5.0, 8000.0, DELTA)
	assert_vector(light).is_equal_approx(heavy, Vector3.ONE * 1e-4)


func test_air_force_clamped_to_one_tick_zeroing_on_each_axis() -> void:
	# The 60 Hz discipline: an absurd area may at most STOP the body's air speed on that axis this
	# tick, never reverse it. `body_mass` enters here and nowhere else.
	var vel := Vector3(3.0, 0.0, -12.0)
	var f := M.air_force(vel, Vector3.ZERO, Basis.IDENTITY, 1e9, 1e9, MASS, DELTA)
	assert_float(f.z).is_equal_approx(MASS * 12.0 / DELTA, 1e-1)
	assert_float(f.x).is_equal_approx(-MASS * 3.0 / DELTA, 1e-1)


func test_air_force_is_off_in_still_air_at_a_standstill() -> void:
	var b := Basis.IDENTITY
	assert_vector(M.air_force(Vector3.ZERO, Vector3.ZERO, b, 0.6, 5.0, MASS, DELTA)) \
			.is_equal(Vector3.ZERO)
	assert_vector(M.air_force(Vector3(0.0, 0.0, -0.01), Vector3.ZERO, b, 0.6, 5.0, MASS, DELTA)) \
			.is_equal(Vector3.ZERO)
	# A zero delta is a divide-by-zero in the clamp, not a physical case.
	assert_vector(M.air_force(Vector3(0.0, 0.0, -20.0), Vector3.ZERO, b, 0.6, 5.0, MASS, 0.0)) \
			.is_equal(Vector3.ZERO)


func test_a_crosswind_on_a_parked_body_is_side_force_only() -> void:
	# The gate reads the air, not the body: a parked body in wind is pushed, broadside at
	# `0.5 rho cya w^2`, downwind, and with no drag part.
	var wind := Vector3(9.0, 0.0, 0.0)  # blowing toward +X, the body's right
	var f := M.air_force(Vector3.ZERO, wind, Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)
	assert_float(f.x).is_equal_approx(0.5 * M.AIR_DENSITY * 5.0 * 81.0, 1e-3)
	assert_float(f.z).is_equal_approx(0.0, 1e-6)
	assert_float(f.y).is_equal(0.0)


func test_a_tailwind_at_the_body_speed_gives_no_force() -> void:
	var vel := Vector3(0.0, 0.0, -15.0)
	assert_vector(M.air_force(vel, vel, Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)) \
			.is_equal(Vector3.ZERO)


func test_head_and_tail_winds_scale_drag_with_the_air_speed_squared() -> void:
	var vel := Vector3(0.0, 0.0, -25.0)
	var head := M.air_force(vel, Vector3(0.0, 0.0, 9.0), Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)
	var tail := M.air_force(vel, Vector3(0.0, 0.0, -9.0), Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)
	assert_float(head.z).is_equal_approx(M.aero_drag(34.0, 0.6), 1e-3)
	assert_float(tail.z).is_equal_approx(M.aero_drag(16.0, 0.6), 1e-3)


func test_the_side_term_is_q_cya_sin_yaw_in_a_quartering_wind() -> void:
	# Air at yaw b over the body: side force q * cya * sin(b), drag q * cda * cos(b).
	var vel := Vector3(0.0, 0.0, -25.0)
	var wind := Vector3(-9.0, 0.0, 0.0)  # comes from the right, so it pushes the body left (-X)
	var air := vel - wind
	var q := 0.5 * M.AIR_DENSITY * air.length_squared()
	var sin_b := air.x / air.length()
	var f := M.air_force(vel, wind, Basis.IDENTITY, 0.6, 5.0, MASS, DELTA)
	assert_float(f.x).is_equal_approx(-q * 5.0 * sin_b, 1e-3)


func test_air_force_drops_the_body_up_part_of_the_air() -> void:
	# A body falling or bouncing takes no drag from it: the model is drag and side force only.
	var b := Basis(Vector3.RIGHT, 0.3)  # pitched, so body-up is not world-up
	var vel := b.y * 10.0
	assert_vector(M.air_force(vel, Vector3.ZERO, b, 0.6, 5.0, MASS, DELTA)) \
			.is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-5)


func test_the_downforce_point_splits_by_the_front_share() -> void:
	# A vertical force at z splits by lever: the front axle takes (rear_z - z) / wheelbase.
	var front_z := -1.3
	var rear_z := 1.2
	for share: float in [0.0, 0.4, 0.5, 1.0]:
		var p := M.downforce_point(front_z, rear_z, share)
		assert_float((rear_z - p.z) / (rear_z - front_z)).is_equal_approx(share, 1e-5)
		assert_float(p.x).is_equal(0.0)
		assert_float(p.y).is_equal(0.0)
	assert_float(M.downforce_point(front_z, rear_z, 0.0).z).is_equal_approx(rear_z, 1e-6)
	assert_float(M.downforce_point(front_z, rear_z, 1.0).z).is_equal_approx(front_z, 1e-6)


func test_an_unset_aero_centre_is_the_central_force() -> void:
	# ZERO is "unset": the force goes through the live COM and turns nothing, wherever the COM
	# sits. A declared centre above the COM pitches the body under a rearward (+Z) drag.
	# The point is measured from the ORIGIN: placed at the COM it turns nothing either.
	var spins: Array[Vector3] = []
	for at: Vector3 in [Vector3.ZERO, Vector3(0.0, 0.8, 0.0), Vector3(0.0, 0.3, 0.4)]:
		var body: RigidBody3D = auto_free(RigidBody3D.new())
		body.gravity_scale = 0.0
		body.collision_layer = 0
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = Vector3(0.0, 0.3, 0.4)
		add_child(body)
		await get_tree().physics_frame
		WheelDrive.apply_at(body, Vector3(0.0, 0.0, 500.0), at)
		await get_tree().physics_frame
		spins.append(body.angular_velocity)
	assert_vector(spins[0]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)
	# r x F with r = (0, 0.5, -0.4) from the COM and F = +Z: +X, the top pushed back (nose up).
	assert_float(spins[1].x).is_greater(1e-4)
	assert_vector(spins[2]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)


func test_anti_roll_force_is_equal_and_opposite_across_the_axle() -> void:
	var left := M.anti_roll_force(0.10, 0.02, 10000.0)
	var right := M.anti_roll_force(0.02, 0.10, 10000.0)
	assert_float(left).is_equal_approx(800.0, 1e-3)
	assert_float(left + right).is_equal_approx(0.0, 1e-3)


func test_anti_roll_force_is_zero_when_the_axle_is_level_or_the_bar_is_off() -> void:
	assert_float(M.anti_roll_force(0.07, 0.07, 10000.0)).is_equal(0.0)
	assert_float(M.anti_roll_force(0.10, 0.02, 0.0)).is_equal(0.0)
	assert_float(M.anti_roll_force(0.10, 0.02, -5000.0)).is_equal(0.0)


## At the hang the partner's spring exactly balances the bar's pull: its tyre carries nothing.
func test_the_bar_hangs_its_partner_where_the_partners_spring_balances_it() -> void:
	var k := 22000.0
	var bar := 10000.0
	var hang := M.anti_roll_hang(0.10, bar, k)
	assert_float(hang).is_equal_approx(0.10 * bar / (k + bar), 1e-9)
	assert_float(k * hang + M.anti_roll_force(hang, 0.10, bar)).is_equal_approx(0.0, 1e-6)
	# What the bar then puts on this corner: the bar in series with the partner's spring.
	assert_float(M.anti_roll_force(0.10, hang, bar)).is_equal_approx(0.10 * bar * k / (k + bar), 1e-6)


func test_no_bar_hangs_nothing() -> void:
	assert_float(M.anti_roll_hang(0.10, 0.0, 22000.0)).is_equal(0.0)
	assert_float(M.anti_roll_hang(0.10, -5000.0, 22000.0)).is_equal(0.0)
	assert_float(M.anti_roll_hang(-0.01, 10000.0, 22000.0)).is_equal(0.0)
