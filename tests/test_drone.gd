extends GdUnitTestSuite
## Drone flight math: static pure fns covering hover, attitude, mixer, torque, motors,
## and rotor-rpm. Shared physics lives in test_vehicle_math.gd.

const D := preload("res://src/vehicles/drone/drone.gd")
const Prop := preload("res://src/vehicles/drone/drone_propulsion.gd")
const DroneT := preload("res://src/vehicles/drone/drone_telemetry.gd")
const Bus := preload("res://src/vehicles/drone/drone_bus.gd")
const Sensors := preload("res://src/vehicles/drone/drone_sensors.gd")

# Round numbers so expected values are hand-checkable: a 5 kg drone at g = 10.
const MASS := 5.0
const G := 10.0
const CLIMB_FORCE := 30.0
const MAX_THRUST := 150.0
const DELTA := 1.0 / 60.0
const TAU_SPOOL := 0.05
const ARM := 0.407          ## the rotor lever drone.tscn authors, on both x and z

# Motor indices are DroneCAN esc_index, and DroneVehicle.MOTORS is the mapping.
const FL := 0
const FR := 1
const RL := 2
const RR := 3

# --- lift_thrust: hover equilibrium + clamps ----------------------------------

func test_lift_thrust_hovers_against_gravity() -> void:
	# Climb neutral: thrust exactly cancels weight, so a level drone holds altitude.
	assert_float(D.lift_thrust(MASS, G, 0.0, CLIMB_FORCE, MAX_THRUST)).is_equal_approx(MASS * G, 1e-6)


func test_lift_thrust_climb_stick_adds_and_removes_lift() -> void:
	assert_float(D.lift_thrust(MASS, G, 1.0, CLIMB_FORCE, MAX_THRUST)) \
			.is_equal_approx(MASS * G + CLIMB_FORCE, 1e-6)
	assert_float(D.lift_thrust(MASS, G, -1.0, CLIMB_FORCE, MAX_THRUST)) \
			.is_equal_approx(MASS * G - CLIMB_FORCE, 1e-6)


func test_lift_thrust_never_negative_and_hard_capped() -> void:
	# Full-down with a climb force larger than weight still can't suck the drone down.
	assert_float(D.lift_thrust(MASS, G, -1.0, 200.0, MAX_THRUST)).is_equal(0.0)
	# Runaway demand is capped at max_thrust (the max_suspension_force analogue).
	assert_float(D.lift_thrust(MASS, G, 1.0, 1e6, MAX_THRUST)).is_equal(MAX_THRUST)

# --- level_target_up: attitude target ------------------------------------------

func test_level_target_up_level_is_straight_up() -> void:
	assert_vector(D.level_target_up(Basis.IDENTITY, Vector2.ZERO)).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-5)


func test_level_target_up_positive_tilt_leans_the_up_vector_back() -> void:
	# Facing -Z (north). POSITIVE tilt tips the up-vector backward (+Z) — the nose-up /
	# backward-flight lean (the caller negates throttle, so W maps to negative tilt).
	var up := D.level_target_up(Basis.IDENTITY, Vector2(deg_to_rad(20.0), 0.0))
	assert_float(up.z).is_greater(0.0)      # leaned toward +Z (backward)
	assert_float(up.x).is_equal_approx(0.0, 1e-5)  # no roll introduced
	assert_float(up.y).is_equal_approx(cos(deg_to_rad(20.0)), 1e-5)

# --- align_torque: self-levelling direction is correct by construction ---------

func test_align_torque_rotates_body_up_toward_target() -> void:
	# Body rolled so its up leans to +X; target is world up. The torque must rotate the
	# up-vector back toward vertical (a positive rotation about +Z reduces a +X lean).
	var s := sin(deg_to_rad(15.0))
	var c := cos(deg_to_rad(15.0))
	var body_up := Vector3(s, c, 0.0)
	var tau := D.align_torque(body_up, Vector3.UP, 4.0)
	assert_vector(tau).is_equal_approx(Vector3(0.0, 0.0, s * 4.0), Vector3.ONE * 1e-4)
	# Already level: no corrective torque.
	assert_vector(D.align_torque(Vector3.UP, Vector3.UP, 4.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)

# --- mean_omega / rotor_rpm: read out of the motors, not modeled ----------------

func test_mean_omega_averages_the_motors_and_clamps() -> void:
	assert_float(Prop.mean_omega(PackedFloat32Array([0.5, 0.5, 0.5, 0.5]))).is_equal_approx(0.5, 1e-6)
	assert_float(Prop.mean_omega(PackedFloat32Array([1.0, 0.0, 1.0, 0.0]))).is_equal_approx(0.5, 1e-6)
	# Out-of-range speeds clamp before averaging, so the mean stays in [0, 1].
	assert_float(Prop.mean_omega(PackedFloat32Array([5.0, -5.0, 0.0, 0.0]))).is_equal_approx(0.25, 1e-6)
	# No motors bound (a rotor missing from the scene) is a stopped craft, not a divide by zero.
	assert_float(Prop.mean_omega(PackedFloat32Array())).is_equal(0.0)


func test_rotor_rpm_is_the_mean_of_the_published_esc_rpms() -> void:
	# The contract defines rotor_rpm as the mean of esc_rpm, so it is computed FROM that
	# array — not from _omega a second time — and the two cannot disagree.
	assert_int(Prop.rotor_rpm(Prop.esc_rpm(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), 12000))).is_equal(0)
	assert_int(Prop.rotor_rpm(Prop.esc_rpm(PackedFloat32Array([1.0, 1.0, 1.0, 1.0]), 12000))).is_equal(12000)
	# A yaw split raises one diagonal and lowers the other, so the MEAN barely moves.
	assert_int(Prop.rotor_rpm(Prop.esc_rpm(PackedFloat32Array([0.4, 0.6, 0.6, 0.4]), 12000))).is_equal(6000)
	assert_int(Prop.rotor_rpm(PackedInt32Array())).is_equal(0)


func test_rotor_rpm_is_not_gated_on_arm_so_a_spool_down_still_publishes() -> void:
	var spooling := PackedFloat32Array([0.41, 0.41, 0.41, 0.41])
	assert_int(Prop.rotor_rpm(Prop.esc_rpm(spooling, 12000))).is_greater(0)
	assert_int(Prop.rotor_rpm(Prop.esc_rpm(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), 12000))).is_equal(0)

# --- the per-ESC bus (contract count-4 signals) ---------------------------------

func test_esc_rpm_is_each_motor_on_the_one_rpm_mapping() -> void:
	# esc_index order is preserved element for element — the array IS the mapping, so a
	# reordering here would renumber the bus.
	var rpms := Prop.esc_rpm(PackedFloat32Array([0.0, 0.25, 0.5, 1.0]), 12000)
	assert_int(rpms.size()).is_equal(4)
	assert_int(rpms[0]).is_equal(0)
	assert_int(rpms[1]).is_equal(3000)
	assert_int(rpms[2]).is_equal(6000)
	assert_int(rpms[3]).is_equal(12000)
	# Out-of-range speeds clamp, exactly as mean_omega's do: no negative and no over-max rpm.
	var clamped := Prop.esc_rpm(PackedFloat32Array([-1.0, 5.0]), 12000)
	assert_int(clamped[0]).is_equal(0)
	assert_int(clamped[1]).is_equal(12000)


func test_esc_current_has_a_no_load_floor_and_rises_with_motor_speed() -> void:
	var args := [12000, MAX_THRUST, 0.02, 14.8, 0.85, 1.0]
	# A stopped motor makes no torque, so it draws exactly the no-load floor — never less,
	# and never a negative current.
	assert_float(Prop.esc_current_a(0.0, args[0], args[1], args[2], args[3], args[4], args[5])) \
		.is_equal_approx(1.0, 1e-6)
	# Monotone in omega (torque ~ w^2 times shaft speed ~ w, so it climbs steeply).
	var last := 0.0
	for step in 11:
		var w := float(step) / 10.0
		var amps := Prop.esc_current_a(w, args[0], args[1], args[2], args[3], args[4], args[5])
		assert_float(amps).override_failure_message("current fell at omega %f" % w).is_greater_equal(last)
		last = amps
	# The header's hover arithmetic: collective 0.327 -> omega sqrt(0.327) -> ~15 A.
	var hover := Prop.esc_current_a(sqrt(0.327), args[0], args[1], args[2], args[3], args[4], args[5])
	assert_float(hover).is_between(13.0, 17.0)


func test_esc_current_survives_a_degenerate_conversion() -> void:
	# A zero efficiency or pack voltage must not divide by zero — the boat/RayWheel guard
	# discipline, since these are constants an edit can zero.
	assert_float(Prop.esc_current_a(1.0, 12000, MAX_THRUST, 0.02, 0.0, 0.85, 1.0)).is_greater(0.0)
	assert_float(Prop.esc_current_a(1.0, 12000, MAX_THRUST, 0.02, 14.8, 0.0, 1.0)).is_greater(0.0)


func test_esc_temp_converges_to_its_target_without_overshooting() -> void:
	# Same shape as spool_step: a first-order lag can never pass its target and never
	# reverses, so it is stable at any tick rate.
	var target := 20.0 + 0.089 * 15.0 * 15.0
	var temp := 20.0
	for _i in 60 * 200:
		var next := Prop.esc_temp_step(temp, 15.0, 20.0, 0.089, 20.0, DELTA)
		assert_float(next).override_failure_message("overshot its target").is_less_equal(target + 1e-4)
		assert_float(next).override_failure_message("a heating step went backwards").is_greater_equal(temp - 1e-6)
		temp = next
	assert_float(temp).is_equal_approx(target, 0.01)


func test_esc_temp_cools_back_toward_ambient_with_the_same_step() -> void:
	# Heating and cooling are ONE expression; which way it moves is only which side of the
	# target it started on. A cooling step may not undershoot ambient either.
	var temp := 90.0
	for _i in 60 * 200:
		temp = Prop.esc_temp_step(temp, 0.0, 20.0, 0.089, 20.0, DELTA)
		assert_float(temp).is_greater_equal(20.0 - 1e-4)
	assert_float(temp).is_equal_approx(20.0, 0.01)


func test_esc_temp_step_relaxes_as_delta_shrinks() -> void:
	# The 60 Hz discipline: a smaller tick moves it less, and a zero/absent tau collapses to
	# the target rather than dividing by zero.
	var big := Prop.esc_temp_step(20.0, 15.0, 20.0, 0.089, 20.0, 1.0) - 20.0
	var small := Prop.esc_temp_step(20.0, 15.0, 20.0, 0.089, 20.0, DELTA) - 20.0
	assert_float(small).is_less(big)
	assert_float(small).is_greater(0.0)
	assert_float(Prop.esc_temp_step(20.0, 15.0, 20.0, 0.089, 0.0, DELTA)).is_equal_approx(40.025, 0.01)


func test_esc_fault_bits_map_one_bit_per_esc_index() -> void:
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([20.0, 20.0, 20.0, 20.0]), 90.0)).is_equal(0)
	# Bit i is esc_index i, so a hot RotorRL (index 2) is bit 2 and nothing else.
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([20.0, 20.0, 95.0, 20.0]), 90.0)).is_equal(1 << 2)
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([95.0, 20.0, 20.0, 95.0]), 90.0)).is_equal(0b1001)
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([95.0, 95.0, 95.0, 95.0]), 90.0)).is_equal(0b1111)
	# Exactly AT the threshold is not over it.
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([90.0, 90.0, 90.0, 90.0]), 90.0)).is_equal(0)
	# An unread warn (INF, the contract signal missing) never faults.
	assert_int(Prop.esc_fault_bits(PackedFloat32Array([200.0, 200.0]), INF)).is_equal(0)


## The instance count is declared in THREE places that must agree — the contract's 'count',
## DroneVehicle.MOTORS, and the array literals DroneTelemetry sizes its fields to. test_telemetry
## pins the telemetry defaults against the contract; this pins the flight sim against it, which
## is the one the bridge cannot catch cheaply: a mismatch there produces correctly-shaped
## defaults and wrong-length LIVE arrays, so the ESC signals would drop after one warn-once and
## go silent for the rest of the session.
func test_the_motor_count_is_the_contracts_instance_count() -> void:
	for sig_name in ["esc_rpm", "esc_current", "esc_temp"]:
		var sig := Contract.data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_int(Prop.MOTORS.size()) \
			.override_failure_message("MOTORS has %d motors, '%s' declares count %d" % [
				Prop.MOTORS.size(), sig_name, sig.count]) \
			.is_equal(sig.count)


## The drone's REAL tuning, read off the script and the spec rather than restated here: the
## suite's MASS/G/CLIMB_FORCE constants above are round stand-ins for the pure-function tests,
## and an envelope gate carrying its own copy of climb_force would keep passing after a retune
## moved the very thing it guards.
func _knob(knob: String) -> float:
	var script: Script = D
	return float(script.get_property_default_value(knob))


func _amps(demand: float) -> float:
	# mix_quad_x clamps the summed demand and takes its sqrt: that is the motor SPEED.
	return Prop.esc_current_a(sqrt(clampf(demand, 0.0, 1.0)), Prop.ROTOR_MAX_RPM, _knob("max_thrust"),
			_knob("prop_torque_ratio"), Prop.ESC_PACK_VOLTS, Prop.ESC_ETA, Prop.ESC_I_NOLOAD)


## The steady state a current settles at — tau 0 collapses the lag straight to its target.
func _settled(amps: float) -> float:
	return Prop.esc_temp_step(0.0, amps, Prop.ESC_AMBIENT, Prop.ESC_TEMP_K, 0.0, DELTA)


## The regression gate for the ranges. Both models must stay inside the scale the contract
## publishes them on across the WHOLE achievable envelope, not just the straight-line case.
## The first cut set the 40 A top from a full-stick climb and an ordinary lean already beat it,
## because mix_quad_x adds roll/pitch/yaw demand on top of collective and clamps the SUM to 1 —
## so demand 1.0 is a real motor state, reachable from a hover with a lean and a yaw, and it is
## the binding case: esc_current_a is monotone in omega, so a model that fits at the clamp fits
## everywhere below it. A retune of ESC_TEMP_K, ESC_ETA or the thrust knobs that puts either
## model off its own bar fails here rather than on the bus.
func test_the_esc_models_stay_inside_their_contract_ranges() -> void:
	var cur := Contract.data.get_signal_def("esc_current", "out")
	var tmp := Contract.data.get_signal_def("esc_temp", "out")
	assert_int(cur.range.size()).is_equal(2)
	assert_int(tmp.range.size()).is_equal(2)
	var saturated := _amps(1.0)
	assert_float(saturated) \
		.override_failure_message("a saturated motor draws %.1f A, past the contract's %.0f A top" % [
			saturated, cur.range[1]]) \
		.is_between(float(cur.range[0]), float(cur.range[1]))
	# The temperature is the one model allowed to TARGET past its top, because ESC_TEMP_TAU is
	# 20 s and a continuously pinned motor is a tumble rather than a flight. What it may not do
	# is get there quickly: a second of saturation must still leave it on the bar.
	assert_float(Prop.esc_temp_step(Prop.ESC_AMBIENT, saturated, Prop.ESC_AMBIENT, Prop.ESC_TEMP_K,
			Prop.ESC_TEMP_TAU, 1.0)) \
		.override_failure_message("one second of saturation already ran off the temperature bar") \
		.is_less(float(tmp.range[1]))


## ...and the tuning is not merely inside the range, it is the SHAPE the contract desc promises:
## a cool hover, a sustained full-stick climb approaching the warn without tripping it, and a
## lean or yaw on top of that climb crossing it. This is what "tuned on the envelope, not on the
## hover" means, and it is the sentence in the desc that would otherwise quietly become false.
func test_the_esc_temperature_is_tuned_on_the_envelope_not_the_hover() -> void:
	var tmp := Contract.data.get_signal_def("esc_temp", "out")
	var spec: Resource = load("res://src/vehicles/drone/drone_spec.tres")
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var thrust := _knob("max_thrust")
	var hover: float = spec.mass * gravity / thrust
	var climb: float = (spec.mass * gravity + _knob("climb_force")) / thrust
	# The mixer's own conversions, so the lean tracks the attitude tuning instead of restating it.
	var roll := Prop.torque_to_demand(_knob("max_attitude_torque"), 0.407, thrust)
	var yaw := Prop.torque_to_demand(_knob("max_yaw_torque"), _knob("prop_torque_ratio"), thrust)

	assert_float(_settled(_amps(hover))) \
		.override_failure_message("a hover should sit cool, well under the warn") \
		.is_between(Prop.ESC_AMBIENT, tmp.warn * 0.5)
	assert_float(_settled(_amps(climb))) \
		.override_failure_message("a sustained climb should APPROACH the warn, not trip it") \
		.is_between(tmp.warn * 0.8, tmp.warn)
	assert_float(_settled(_amps(climb + roll + yaw))) \
		.override_failure_message("a climbing lean-and-yaw should cross the warn") \
		.is_greater(tmp.warn)
	# The finding that started this: hover + ONE full axis already beats a full climb, which is
	# why neither range may be read off the straight-line case again.
	assert_float(_amps(hover + roll)) \
		.override_failure_message("hover+roll should out-draw a full climb") \
		.is_greater(_amps(climb))

# --- mix_quad_x: the mixer ------------------------------------------------------

func test_mix_pure_collective_gives_four_equal_commands() -> void:
	# No axis demand: every motor carries a quarter of the craft. The command is the SPEED
	# fraction, so it is the square root of the thrust fraction (0.25 -> 0.5).
	var cmd := Prop.mix_quad_x(0.25, 0.0, 0.0, 0.0)
	assert_int(cmd.size()).is_equal(4)
	for i in cmd.size():
		assert_float(cmd[i]).is_equal_approx(0.5, 1e-6)


func test_mix_roll_raises_one_SIDE_pair_and_lowers_the_other() -> void:
	# On an X quad, roll acts on the two motors on ONE SIDE — sx = sign(x). (Only YAW acts
	# on a diagonal pair; see the test below. "Diagonal" for roll is not what the
	# geometry does.) A positive roll demand raises the RIGHT pair,
	# which torques about body +Z and rolls the craft LEFT.
	var cmd := Prop.mix_quad_x(0.25, 0.15, 0.0, 0.0)
	assert_float(cmd[FR]).is_greater(0.5)
	assert_float(cmd[RR]).is_greater(0.5)
	assert_float(cmd[FL]).is_less(0.5)
	assert_float(cmd[RL]).is_less(0.5)
	# The pairs are symmetric, so a pure roll introduces no pitch and no yaw.
	assert_float(cmd[FR]).is_equal_approx(cmd[RR], 1e-6)
	assert_float(cmd[FL]).is_equal_approx(cmd[RL], 1e-6)


func test_mix_pitch_raises_the_front_pair() -> void:
	# sp = -sign(z) and forward is -Z, so a positive pitch demand raises the FRONT pair —
	# torque about body +X, nose up.
	var cmd := Prop.mix_quad_x(0.25, 0.0, 0.15, 0.0)
	assert_float(cmd[FL]).is_greater(0.5)
	assert_float(cmd[FR]).is_greater(0.5)
	assert_float(cmd[RL]).is_less(0.5)
	assert_float(cmd[RR]).is_less(0.5)
	assert_float(cmd[FL]).is_equal_approx(cmd[FR], 1e-6)


func test_mix_yaw_raises_one_SPIN_DIRECTION_pair() -> void:
	# Yaw acts on counter-rotating pairs; raises one diagonal, lowers the other.
	var cmd := Prop.mix_quad_x(0.25, 0.0, 0.0, 0.15)
	assert_float(cmd[FR]).is_greater(0.5)
	assert_float(cmd[RL]).is_greater(0.5)
	assert_float(cmd[FL]).is_less(0.5)
	assert_float(cmd[RR]).is_less(0.5)
	assert_int(int(Prop.MOTORS[FR]["spin"])).is_equal(int(Prop.MOTORS[RL]["spin"]))
	assert_int(int(Prop.MOTORS[FL]["spin"])).is_equal(int(Prop.MOTORS[RR]["spin"]))


func test_mix_commands_stay_in_unit_range() -> void:
	# Absurd demands saturate rather than escaping the range — a command outside [0, 1]
	# would mean a motor spinning backwards or past its own ceiling.
	for cmd in [Prop.mix_quad_x(0.5, 10.0, -10.0, 5.0), Prop.mix_quad_x(-5.0, 0.0, 0.0, 0.0),
			Prop.mix_quad_x(2.0, 0.0, 0.0, 0.0), Prop.mix_quad_x(0.3, -8.0, 8.0, -8.0)]:
		for i in cmd.size():
			assert_float(cmd[i]).is_between(0.0, 1.0)
	# Collective below zero puts every motor at a dead stop, not into reverse.
	var stopped := Prop.mix_quad_x(-5.0, 0.0, 0.0, 0.0)
	for i in stopped.size():
		assert_float(stopped[i]).is_equal(0.0)


## Why Land's touchdown cut zeroes all four demands and not only the collective. The mix is a sum
## clamped per motor, so a zero collective is not a stopped aircraft while any axis still has a
## demand on it: two motors go positive and a craft sitting on a slope fights the ground with them.
## A cut is all four, and this pins both halves of that.
func test_a_zero_collective_is_not_a_cut_while_an_axis_still_asks() -> void:
	var leaning := Prop.mix_quad_x(0.0, 0.3, 0.0, 0.0)
	var turning := 0
	for i in leaning.size():
		if leaning[i] > 0.0:
			turning += 1
	assert_int(turning) \
		.override_failure_message("a zero collective already stops the motors; the cut could shrink") \
		.is_equal(2)
	# The real cut: nothing asked for on any axis, so nothing turns.
	for c in Prop.mix_quad_x(0.0, 0.0, 0.0, 0.0):
		assert_float(c).is_equal(0.0)

# --- the motors: spool, thrust, and losing one ----------------------------------

func test_spool_step_lags_toward_the_command_without_overshooting() -> void:
	# One tick covers exactly 1 - exp(-dt/tau) of the gap, and never more than the gap.
	var w := Prop.spool_step(0.0, 1.0, TAU_SPOOL, DELTA)
	assert_float(w).is_equal_approx(1.0 - exp(-DELTA / TAU_SPOOL), 1e-6)
	assert_float(w).is_between(0.0, 1.0)
	# Already there: nothing moves, so a settled hover does not jitter.
	assert_float(Prop.spool_step(0.6, 0.6, TAU_SPOOL, DELTA)).is_equal_approx(0.6, 1e-6)
	# Spooling down is the same lag in reverse, and it cannot cross zero.
	var down := Prop.spool_step(1.0, 0.0, TAU_SPOOL, DELTA)
	assert_float(down).is_between(0.0, 1.0)
	assert_float(down).is_less(1.0)


func test_spool_step_relaxes_as_delta_shrinks() -> void:
	# A shorter tick moves strictly less — a lag, never a fixed step, so it is stable at
	# any tick rate (the 60 Hz discipline, in the motors' flavor).
	var full := Prop.spool_step(0.0, 1.0, TAU_SPOOL, DELTA)
	var half := Prop.spool_step(0.0, 1.0, TAU_SPOOL, DELTA * 0.5)
	assert_float(half).is_less(full)
	assert_float(half).is_greater(0.0)


func test_spool_step_clamps_command_and_state() -> void:
	assert_float(Prop.spool_step(0.0, 5.0, TAU_SPOOL, DELTA)).is_between(0.0, 1.0)
	assert_float(Prop.spool_step(0.5, -5.0, TAU_SPOOL, DELTA)).is_between(0.0, 0.5)
	# Degenerate tau/delta snap to the clamped command instead of dividing by zero.
	assert_float(Prop.spool_step(0.2, 0.9, 0.0, DELTA)).is_equal_approx(0.9, 1e-6)
	assert_float(Prop.spool_step(0.2, 2.0, TAU_SPOOL, 0.0)).is_equal(1.0)


func test_motor_thrust_is_quadratic_capped_and_never_negative() -> void:
	assert_float(Prop.motor_thrust(0.0, MAX_THRUST)).is_equal(0.0)
	# All four at full make exactly max_thrust, so one motor's ceiling is a quarter of it.
	assert_float(Prop.motor_thrust(1.0, MAX_THRUST)).is_equal_approx(MAX_THRUST / 4.0, 1e-6)
	# Half speed is a QUARTER of the thrust: thrust ~ w^2, not linear.
	assert_float(Prop.motor_thrust(0.5, MAX_THRUST)).is_equal_approx(MAX_THRUST / 16.0, 1e-6)
	# Out-of-range speed clamps, and no rotor can ever push the craft down.
	assert_float(Prop.motor_thrust(5.0, MAX_THRUST)).is_equal_approx(MAX_THRUST / 4.0, 1e-6)
	assert_float(Prop.motor_thrust(-3.0, MAX_THRUST)).is_equal(0.0)


func test_hover_mix_carries_the_weight_and_one_motor_out_does_not() -> void:
	# The collective the vehicle hands the mixer at hover is the thrust FRACTION.
	var hover := MASS * G / MAX_THRUST          # 50 / 150 = 1/3
	var cmd := Prop.mix_quad_x(hover, 0.0, 0.0, 0.0)
	var total := 0.0
	var three := 0.0
	for i in cmd.size():
		var f := Prop.motor_thrust(cmd[i], MAX_THRUST)
		total += f
		if i != FL:
			three += f
	# Mix -> command -> thrust round-trips: four motors at the hover mix hold the craft up.
	assert_float(total).is_equal_approx(MASS * G, 1e-4)
	# Kill one and the remaining three keep their own commands — nothing compensates.
	assert_float(three).is_less(MASS * G)
	assert_float(three).is_equal_approx(0.75 * MASS * G, 1e-4)

# --- torque_to_demand: the N*m <-> demand levers ---------------------------------

func test_torque_to_demand_inverts_the_mixer_lever() -> void:
	# The roll demand a 20 N*m attitude cap asks for on this airframe — and it is exactly
	# the headroom a 1/3 hover collective has, which is why the shipped cap still fits.
	assert_float(Prop.torque_to_demand(20.0, ARM, MAX_THRUST)) \
			.is_equal_approx(20.0 / (ARM * MAX_THRUST), 1e-6)
	assert_float(Prop.torque_to_demand(20.0, ARM, MAX_THRUST)).is_equal_approx(1.0 / 3.0, 0.01)
	assert_float(Prop.torque_to_demand(0.0, ARM, MAX_THRUST)).is_equal(0.0)
	# Sign carries through, so a negative torque rolls the other way.
	assert_float(Prop.torque_to_demand(-5.0, ARM, MAX_THRUST)).is_less(0.0)
	# A degenerate lever asks for nothing rather than infinity.
	assert_float(Prop.torque_to_demand(5.0, 0.0, MAX_THRUST)).is_equal(0.0)
	assert_float(Prop.torque_to_demand(5.0, ARM, 0.0)).is_equal(0.0)

## Hover collective (thrust-fraction units): at 1/3, full 20 N*m demand stays [0, 1].
const HOVER := MASS * G / MAX_THRUST     # 50 / 150 = 1/3
const PROP := 0.02                       ## prop_torque_ratio (m), drone.gd's default


# --- the closed form: demand -> mixer -> motors -> N*m round-trips ----------------
# `max_attitude_torque = 20` and `max_yaw_torque = 1.0` are not taste values — drone.gd and
# src/vehicles/CLAUDE.md both derive them from tau_roll = arm_x * max_thrust * roll and
# tau_yaw = prop_torque_ratio * max_thrust * yaw. Nothing used to exercise those identities
# end to end, so the tuning rested on arithmetic in a comment. These do.

## The three body torques the airframe REALLY makes from a mixer command array, built from
## the GEOMETRY (r x F and the per-prop reaction) rather than from the closed form under
## test: roll = sum(x_i * f_i) about body +Z, pitch = sum(-z_i * f_i) about body +X, yaw =
## sum(+/- k_q * f_i) about body +Y. MOTORS' sign columns are exactly those unit vectors.
func _realized_torques(cmd: PackedFloat32Array) -> Dictionary:
	var out := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "thrust": 0.0}
	for i in cmd.size():
		var f := Prop.motor_thrust(cmd[i], MAX_THRUST)
		out["roll"] += float(Prop.MOTORS[i]["roll"]) * ARM * f
		out["pitch"] += float(Prop.MOTORS[i]["pitch"]) * ARM * f
		out["yaw"] += float(Prop.MOTORS[i]["yaw"]) * PROP * f
		out["thrust"] += f
	return out


func test_mixer_really_delivers_the_commanded_roll_torque() -> void:
	# The identity max_attitude_torque is sized against: 20 N*m is what a HOVERING quad on
	# this airframe can actually make, so the cap and the real authority coincide.
	for want: float in [5.0, 12.0, 20.0, -20.0]:
		var demand := Prop.torque_to_demand(want, ARM, MAX_THRUST)
		var got: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, demand, 0.0, 0.0))
		assert_float(got["roll"]).is_equal_approx(want, 1e-3)


func test_mixer_really_delivers_the_commanded_pitch_torque() -> void:
	for want: float in [5.0, 20.0, -20.0]:
		var demand := Prop.torque_to_demand(want, ARM, MAX_THRUST)
		var got: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.0, demand, 0.0))
		assert_float(got["pitch"]).is_equal_approx(want, 1e-3)


func test_mixer_really_delivers_the_commanded_yaw_torque() -> void:
	# max_yaw_torque = 1.0 is the prop ceiling at hover (0.327 * 0.02 * 150 = 0.98) rounded
	# up, so 0.98 is the largest demand that still fits inside every motor's range.
	for want: float in [0.4, 0.98, -0.98]:
		var demand := Prop.torque_to_demand(want, PROP, MAX_THRUST)
		var got: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.0, 0.0, demand))
		assert_float(got["yaw"]).is_equal_approx(want, 1e-4)


func test_mixer_axes_are_orthogonal() -> void:
	# Each axis rides a different partition of the four motors and every mix column sums to
	# zero, so an unsaturated demand on one axis makes NOTHING on the other two. This is
	# what lets the three closed-form constants above be independent one-liners.
	var roll_only: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.25, 0.0, 0.0))
	assert_float(roll_only["pitch"]).is_equal_approx(0.0, 1e-4)
	assert_float(roll_only["yaw"]).is_equal_approx(0.0, 1e-5)
	var pitch_only: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.0, 0.25, 0.0))
	assert_float(pitch_only["roll"]).is_equal_approx(0.0, 1e-4)
	assert_float(pitch_only["yaw"]).is_equal_approx(0.0, 1e-5)
	var yaw_only: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.0, 0.0, 0.25))
	assert_float(yaw_only["roll"]).is_equal_approx(0.0, 1e-4)
	assert_float(yaw_only["pitch"]).is_equal_approx(0.0, 1e-4)
	# A pure roll or pitch also leaves the collective alone: the raised pair gains exactly
	# what the lowered pair loses, so total thrust is untouched.
	assert_float(roll_only["thrust"]).is_equal_approx(HOVER * MAX_THRUST, 1e-3)
	assert_float(pitch_only["thrust"]).is_equal_approx(HOVER * MAX_THRUST, 1e-3)


func test_saturation_only_ever_attenuates_the_commanded_torque() -> void:
	# The one-tick discipline the mixer is claimed to TIGHTEN: clamping a motor to 0 raises
	# the low side, which SHRINKS the differential — so the realized torque can never exceed
	# the demand, and never flips sign. Here the craft is in a commanded descent, where the
	# collective has no room for a full-authority lean.
	var descent := D.lift_thrust(MASS, G, -1.0, CLIMB_FORCE, MAX_THRUST) / MAX_THRUST
	var demand := Prop.torque_to_demand(20.0, ARM, MAX_THRUST)
	var got: Dictionary = _realized_torques(Prop.mix_quad_x(descent, demand, 0.0, 0.0))
	assert_float(got["roll"]).is_greater(0.0)     # same sign as the demand
	assert_float(got["roll"]).is_less(20.0)       # but attenuated, and NOT compensated for
	# ...and the documented consequence: attitude has priority over throttle, so pinning the
	# low pair at zero pushes TOTAL thrust up and the commanded descent slows while it leans.
	assert_float(got["thrust"]).is_greater(descent * MAX_THRUST)
	assert_float(got["thrust"]).is_less(MAX_THRUST)

# --- the airframe: MOTORS is the scene, not a guess ------------------------------

func test_motors_table_matches_the_scene_geometry() -> void:
	# The mix signs ARE each drone scene's geometry (roll = sign(x), pitch = -sign(z)), so a
	# rotor moved in any of them must fail here rather than silently invert a control axis.
	var variants := VehicleCatalog.variants_in_family("drone")
	assert_int(variants.size()).is_greater(0)
	assert_int(Prop.MOTORS.size()).is_equal(4)
	for variant in variants:
		var drone: Node = (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate()
		auto_free(drone)
		for i in Prop.MOTORS.size():
			var m: Dictionary = Prop.MOTORS[i]
			var rotor := drone.get_node_or_null(NodePath(m["node"])) as Node3D
			assert_object(rotor).override_failure_message(
					"%s has no %s" % [variant, m["node"]]).is_not_null()
			assert_float(signf(rotor.position.x)).is_equal(float(m["roll"]))
			assert_float(signf(-rotor.position.z)).is_equal(float(m["pitch"]))
			# ...and the MAGNITUDE, not just the sign. drone.gd's closed-form torque constants
			# use the MEAN lever (_arm_x / _arm_z), which only represents the airframe while all
			# four levers are equal. A rotor dragged inward keeps its sign, so a sign-only check
			# would pass it while every attitude constant silently rescaled — and an ASYMMETRIC
			# airframe would start coupling roll into yaw. This is also what ties the ARM
			# constant this suite computes torques with to the scenes that author it.
			assert_float(absf(rotor.position.x)).is_equal_approx(ARM, 1e-4)
			assert_float(absf(rotor.position.z)).is_equal_approx(ARM, 1e-4)
			# A rotor reacts on the body opposite its own spin — that is the whole of yaw.
			assert_int(int(m["yaw"])).is_equal(-int(m["spin"]))


func test_motors_order_is_esc_index_and_the_pairs_are_diagonal() -> void:
	# Per-ESC arrays in this order; renumbering would renumber the bus.
	var names: Array[String] = []
	for m: Dictionary in Prop.MOTORS:
		names.append(String(m["node"]))
	assert_array(names).is_equal(["RotorFL", "RotorFR", "RotorRL", "RotorRR"])
	# The counter-rotating pairs are the diagonals, which is what makes it an X quad.
	assert_int(int(Prop.MOTORS[FL]["spin"])).is_equal(int(Prop.MOTORS[RR]["spin"]))
	assert_int(int(Prop.MOTORS[FR]["spin"])).is_equal(int(Prop.MOTORS[RL]["spin"]))
	assert_int(int(Prop.MOTORS[FL]["spin"])).is_not_equal(int(Prop.MOTORS[FR]["spin"]))

# --- telemetry bridge coverage -------------------------------------------------

func test_drone_telemetry_bridge_dict_adds_flight_fields() -> void:
	var t := DroneT.new()
	t.altitude = 42.0
	t.vspeed = -1.5
	t.rotor_rpm = 8000
	t.armed = true
	t.esc_rpm = [7900, 8100, 8050, 7950]
	t.esc_current = [15.0, 15.5, 15.2, 14.9]
	t.esc_temp = [40.0, 41.0, 40.5, 39.5]
	t.esc_fault = 0b0010
	t.pack_current = 61.4
	t.soc = 72.6
	t.pack_temp = 31.5
	t.battery = 15.4
	t.pitch = 6.0
	t.roll = -3.0
	var d := t.to_bridge_dict()
	assert_float(d["altitude"]).is_equal(42.0)
	assert_float(d["vspeed"]).is_equal(-1.5)
	assert_int(d["rotor_rpm"]).is_equal(8000)
	assert_bool(d["armed"]).is_true()
	# The instanced signals ride as plain Arrays of exactly the contract's 'count'; the
	# bridge drops any other shape (test_telemetry sweeps that against the contract).
	assert_array(d["esc_rpm"]).is_equal([7900, 8100, 8050, 7950])
	assert_array(d["esc_current"]).is_equal([15.0, 15.5, 15.2, 14.9])
	assert_array(d["esc_temp"]).is_equal([40.0, 41.0, 40.5, 39.5])
	assert_int(d["esc_fault"]).is_equal(0b0010)
	assert_float(d["pack_current"]).is_equal(61.4)
	# soc is u8 on the wire, so the float accumulator is rounded on the way out (the base
	# does the same for 'fuel'); pack_temp and battery are f32 and ride unrounded.
	assert_int(d["soc"]).is_equal(73)
	assert_float(d["pack_temp"]).is_equal(31.5)
	# `battery` is the SHARED base field, overwritten with the LiPo model — not redeclared.
	assert_float(d["battery"]).is_equal(15.4)
	assert_float(d["pitch"]).is_equal(6.0)
	assert_float(d["roll"]).is_equal(-3.0)
	# Base fields still ride along (super() first, tractor/boat pattern).
	assert_bool(d.has("speed")).is_true()
	assert_bool(d.has("status")).is_true()

# --- what a dead node costs the flight model ----------------------------------
# The roster and its laws live in tests/test_drone_bus.gd; what is asserted HERE is the part
# that belongs to the airframe — that gating a motor really does take the authority away, in
# the same closed-form N*m terms the mixer's own tuning is pinned in.

func test_a_gated_motor_spools_down_while_the_others_hold_their_commands() -> void:
	# The command is zeroed, not the speed: a dropped ESC's prop coasts to a stop over ~5*tau
	# and makes decaying lift the whole way, exactly like a disarm.
	var cmd := Prop.mix_quad_x(HOVER, 0.0, 0.0, 0.0)
	var gated := Bus.gate_commands(cmd, 1 << FL)
	var omega := PackedFloat32Array()
	omega.resize(cmd.size())
	for i in cmd.size():
		omega[i] = cmd[i]   # start settled at the hover mix
	for _step in 60:        # one second, ~20 time constants
		for i in omega.size():
			omega[i] = Prop.spool_step(omega[i], gated[i], TAU_SPOOL, DELTA)
	assert_float(omega[FL]).is_less(1e-4)
	for i in omega.size():
		if i != FL:
			assert_float(omega[i]).is_equal_approx(cmd[i], 1e-6)


func test_one_motor_out_cannot_hold_yaw() -> void:
	# THE headline consequence. Yaw comes from the counter-rotating DIAGONALS, so killing one
	# motor halves one diagonal: the craft is left with a large uncommanded yaw torque it
	# cannot null, and asking for yaw the other way cannot cancel it either. Nothing here
	# compensates, and nothing should.
	var level: Dictionary = _realized_torques(Prop.mix_quad_x(HOVER, 0.0, 0.0, 0.0))
	assert_float(level["yaw"]).is_equal_approx(0.0, 1e-9)
	var dead: Dictionary = _realized_torques(Bus.gate_commands(Prop.mix_quad_x(HOVER, 0.0, 0.0, 0.0), 1 << FL))
	# FL's reaction is simply missing, so the residual is that one prop's whole torque —
	# and it is the WRONG sign to be cancelled by the yaw the controller can command
	# (max_yaw_torque is the ~0.98 N*m hover ceiling; this residual is a quarter of hover
	# thrust times the same lever, which is larger).
	var one_prop := PROP * MASS * G / 4.0
	assert_float(absf(dead["yaw"])).is_equal_approx(one_prop, 1e-6)
	assert_float(absf(dead["yaw"])).is_greater(0.0)
	# ...and the craft is also no longer holding itself up, which is the other half of it.
	assert_float(dead["thrust"]).is_less(level["thrust"])


func test_a_gated_motor_costs_roll_authority_asymmetrically() -> void:
	# Roll one way still works (the surviving side pair carries it); roll the OTHER way is
	# short by the dead motor. An airframe that degraded symmetrically would be a fiction.
	var demand := Prop.torque_to_demand(10.0, ARM, MAX_THRUST)
	var right: Dictionary = _realized_torques(Bus.gate_commands(Prop.mix_quad_x(HOVER, demand, 0.0, 0.0), 1 << FL))
	var left: Dictionary = _realized_torques(Bus.gate_commands(Prop.mix_quad_x(HOVER, -demand, 0.0, 0.0), 1 << FL))
	assert_float(absf(right["roll"])).is_not_equal(absf(left["roll"]))


func test_the_bus_fields_ride_the_bridge_dict() -> void:
	var t := DroneT.new()
	t.node_health = [0, 0, 3, 1, 0, 0, 0, 0]
	t.node_online = 0b1111_1011
	var d := t.to_bridge_dict()
	assert_array(d["node_health"]).is_equal([0, 0, 3, 1, 0, 0, 0, 0])
	assert_int(d["node_online"]).is_equal(0b1111_1011)


func test_the_sensor_fields_ride_the_bridge_dict() -> void:
	var t := DroneT.new()
	# A craft that has never ticked reports NOTHING SEEN rather than a plausible sky: no
	# satellites, no fix, the hdop ceiling and the invalid beam. Same as a respawn.
	var fresh := t.to_bridge_dict()
	assert_int(fresh["sats"]).is_equal(0)
	assert_int(fresh["fix_type"]).is_equal(Sensors.FIX_NONE)
	assert_float(fresh["hdop"]).is_equal(Sensors.HDOP_MAX)
	assert_float(fresh["agl"]).is_equal(Sensors.RANGE_INVALID)
	t.sats = 11
	t.fix_type = Sensors.FIX_3D
	t.hdop = 0.9
	t.agl = 4.25
	var d := t.to_bridge_dict()
	assert_int(d["sats"]).is_equal(11)
	assert_int(d["fix_type"]).is_equal(3)
	assert_float(d["hdop"]).is_equal(0.9)
	assert_float(d["agl"]).is_equal(4.25)


## The IMU triple is NOT a drone field — it rides the SHARED base struct beside yaw /
## accLong / accLat, which is what lets the plane declare it later with no code at all. So
## the assertion that matters is that the base dict carries it on a DroneTelemetry.
func test_the_imu_axes_ride_the_shared_base_fields() -> void:
	var t := DroneT.new()
	t.yaw = 0.4
	t.roll_rate = -1.25
	t.pitch_rate = 0.75
	t.acc_long = 1.0
	t.acc_lat = -2.0
	t.acc_vert = 3.5
	var d := t.to_bridge_dict()
	assert_float(d["yaw"]).is_equal(0.4)
	assert_float(d["roll_rate"]).is_equal(-1.25)
	assert_float(d["pitch_rate"]).is_equal(0.75)
	assert_float(d["accLong"]).is_equal(1.0)
	assert_float(d["accLat"]).is_equal(-2.0)
	assert_float(d["acc_vert"]).is_equal(3.5)
