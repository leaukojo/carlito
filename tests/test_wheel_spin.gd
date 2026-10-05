extends GdUnitTestSuite
## RayWheel spin: 60 Hz guardrail in _integrate_spin. Clamped road reaction breaks it.

const WheelScript := preload("res://src/vehicles/base/wheel.gd")
const GroundDriveSpecScript := preload("res://src/vehicles/base/ground_drive_spec.gd")

const TICK := 1.0 / 60.0


func _spec() -> GroundDriveSpecScript:
	var spec: GroundDriveSpecScript = GroundDriveSpecScript.new()
	spec.wheel_radius = 0.36
	spec.wheel_inertia = 4.0
	return spec


## corner_mass is irrelevant to _integrate_spin (it sizes the CONTACT clamps, which live in
## tick()), so any positive value does; it is passed only because the constructor demands one.
func _wheel() -> WheelScript:
	return WheelScript.new(Vector3(0.0, 0.0, 1.0), false, true, null, 300.0)


# --- surface drag: a body force at the contact, outside the circle ----------------

func test_surface_drag_opposes_motion_scales_with_load_and_is_zero_at_rest() -> void:
	# crr 0.2 on 5000 N = 1000 N against a forward-rolling contact.
	assert_float(WheelScript.surface_drag_force(10.0, 0.2, 5000.0, 300.0, TICK)) \
			.is_equal_approx(-1000.0, 1e-6)
	assert_float(WheelScript.surface_drag_force(-10.0, 0.2, 5000.0, 300.0, TICK)) \
			.is_equal_approx(1000.0, 1e-6)
	assert_float(WheelScript.surface_drag_force(0.0, 0.2, 5000.0, 300.0, TICK)).is_equal(0.0)
	assert_float(WheelScript.surface_drag_force(10.0, 0.0, 5000.0, 300.0, TICK)).is_equal(0.0)
	assert_float(WheelScript.surface_drag_force(10.0, 0.2, 0.0, 300.0, TICK)).is_equal(0.0)


func test_surface_drag_never_exceeds_the_one_tick_stop() -> void:
	# 300 kg at 0.1 m/s can lose at most 300 * 0.1 / TICK = 1800 N this tick; crr asks 5000.
	assert_float(WheelScript.surface_drag_force(0.1, 1.0, 5000.0, 300.0, TICK)) \
			.is_equal_approx(-1800.0, 1e-6)


# --- combined slip: one slip vector, the force along it ---------------------------

const B_LONG := 1050.0
const B_LAT := 950.0


func _curve() -> PackedVector2Array:
	return _spec().grip_curve


func test_a_locked_wheel_stops_steering_and_abs_keeps_it_steering() -> void:
	# The same 0.05 lateral slip (~3 deg) rolling, at ABS's grip-peak slip, and locked.
	var rolling := WheelScript.combined_slip_force(0.0, 0.05, B_LONG, B_LAT, _curve())
	var abs_held := WheelScript.combined_slip_force(-WheelScript.ABS_SLIP, 0.05, B_LONG, B_LAT,
			_curve())
	var locked := WheelScript.combined_slip_force(-1.0, 0.05, B_LONG, B_LAT, _curve())
	# Locked, the force opposes the slide: its lateral share is the slide's own, 0.05 of it.
	assert_float(locked.y / rolling.y).is_less(0.1)
	assert_float(locked.y / -locked.x).is_equal_approx(0.05 * B_LAT / B_LONG, 1e-5)
	# ABS holds the peak and keeps a real share of the cornering force.
	assert_float(abs_held.y / rolling.y).is_greater(0.6)
	assert_float(-abs_held.x).is_greater(-locked.x)


func test_on_the_linear_rise_each_axis_is_what_it_would_be_alone() -> void:
	var f := WheelScript.combined_slip_force(0.03, -0.04, B_LONG, B_LAT, _curve())
	assert_float(f.x).is_equal_approx(B_LONG * 0.03 / 0.12, 1e-3)
	assert_float(f.y).is_equal_approx(-B_LAT * 0.04 / 0.12, 1e-3)


func test_combined_force_never_leaves_the_ellipse_and_is_zero_without_slip() -> void:
	assert_that(WheelScript.combined_slip_force(0.0, 0.0, B_LONG, B_LAT, _curve())) \
			.is_equal(Vector2.ZERO)
	# A curve peaking above 1 still cannot breach the budget.
	var hot := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.12, 1.4), Vector2(1.0, 1.2)])
	for slip: Vector2 in [Vector2(0.12, 0.0), Vector2(0.1, 0.1), Vector2(-1.0, 0.3)]:
		var f := WheelScript.combined_slip_force(slip.x, slip.y, B_LONG, B_LAT, hot)
		assert_float(Vector2(f.x / B_LONG, f.y / B_LAT).length()).is_less_equal(1.0 + 1e-5)


# --- tyre load sensitivity: mu against the corner's static reference -------------

## Reference per-wheel load, in newtons; any value does, the law is a ratio.
const REF_LOAD := 3000.0


func test_load_scaled_mu_is_the_identity_at_the_reference_and_at_zero_sensitivity() -> void:
	# Sensitivity 0 is today's exactly-linear law: mu comes back untouched at ANY load, which is
	# what lets a family opt in without moving anybody else's numbers.
	for n: float in [0.0, REF_LOAD * 0.1, REF_LOAD, REF_LOAD * 8.0]:
		assert_float(WheelScript.load_scaled_mu(1.05, n, REF_LOAD, 0.0)).is_equal(1.05)
	# At the reference load it is the identity for any sensitivity — the reason every brake number
	# derived at the even static load still means what it said.
	for sens: float in [0.08, 0.10, 0.12]:
		assert_float(WheelScript.load_scaled_mu(1.05, REF_LOAD, REF_LOAD, sens)) 				.is_equal_approx(1.05, 1e-6)
	# A degenerate reference cannot divide: fall back to the flat mu rather than to infinity.
	assert_float(WheelScript.load_scaled_mu(1.05, REF_LOAD, 0.0, 0.10)).is_equal(1.05)


func test_load_scaled_mu_falls_by_the_declared_fraction_per_doubling() -> void:
	# The declaration is "0.10 of mu lost per doubling of load", so a 2x load reads 0.90 * mu and a
	# half load reads 1.10 * mu. Below the reference grip is worth MORE per newton, not less.
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 2.0, REF_LOAD, 0.10)) 			.is_equal_approx(0.90, 1e-6)
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 4.0, REF_LOAD, 0.10)) 			.is_equal_approx(0.80, 1e-6)
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.5, REF_LOAD, 0.10)) 			.is_equal_approx(1.10, 1e-6)
	# Monotone decreasing in load across the whole shipped range.
	var prev := 2.0
	for k: float in [0.3, 0.5, 1.0, 1.5, 2.0, 3.0, 6.0]:
		var mu := WheelScript.load_scaled_mu(1.0, REF_LOAD * k, REF_LOAD, 0.10)
		assert_float(mu).override_failure_message("mu rose with load at %.1fx" % k).is_less(prev)
		prev = mu


func test_load_scaled_mu_is_clamped_at_both_ends() -> void:
	# Neither bound binds on anything shipped (0.12 at the load floor reaches 1.24); they bound a
	# suspension spike or a runtime mass rewrite that leaves a corner far off its reference.
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 100.0, REF_LOAD, 0.10)).is_equal(0.5)
	# Below the ref*0.25 load floor the answer stops moving instead of running away.
	var at_floor := WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.25, REF_LOAD, 0.10)
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.01, REF_LOAD, 0.10)) 			.is_equal_approx(at_floor, 1e-6)
	assert_float(WheelScript.load_scaled_mu(1.0, 0.0, REF_LOAD, 0.10)).is_equal_approx(at_floor, 1e-6)


func test_weight_transfer_costs_the_pair_its_total_grip() -> void:
	# THE POINT OF THE WHOLE LAW. Capacity per wheel is `load_scaled_mu(..) * load`, which is
	# strictly concave in load, so a pair sharing a fixed total makes LESS force the further the
	# load is transferred toward one of them. Under the old linear law the two sums were equal and
	# transfer could not move a body's balance at all.
	var even := 2.0 * WheelScript.load_scaled_mu(1.0, REF_LOAD, REF_LOAD, 0.10) * REF_LOAD
	var prev := even
	for frac: float in [0.2, 0.4, 0.6, 0.8]:
		var hi := REF_LOAD * (1.0 + frac)
		var lo := REF_LOAD * (1.0 - frac)
		var transferred := WheelScript.load_scaled_mu(1.0, hi, REF_LOAD, 0.10) * hi 				+ WheelScript.load_scaled_mu(1.0, lo, REF_LOAD, 0.10) * lo
		assert_float(transferred) 				.override_failure_message("transfer of %.0f%% did not cost the pair grip" % (frac * 100.0)) 				.is_less(prev)
		prev = transferred
	# Sensitivity 0 is the control: the same transfer costs exactly nothing.
	var flat := WheelScript.load_scaled_mu(1.0, REF_LOAD * 1.8, REF_LOAD, 0.0) * REF_LOAD * 1.8 			+ WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.2, REF_LOAD, 0.0) * REF_LOAD * 0.2
	assert_float(flat).is_equal_approx(2.0 * REF_LOAD, 1e-6)


func test_a_loaded_wheel_still_brakes_harder_in_newtons_than_the_reference_one() -> void:
	# Why BRAKE_GRIP_FRAC stayed at 0.95: `brake_torque` is sized at 0.95 of the capacity at the
	# EVEN STATIC load, and absolute capacity still rises with load, so the axle that gains weight
	# under braking never drops under what the pedal asks. Locking stays a property of the
	# UNLOADED axle, exactly as it was.
	for k: float in [1.1, 1.5, 2.0, 2.6]:
		var n := REF_LOAD * k
		var capacity := WheelScript.load_scaled_mu(1.0, n, REF_LOAD, 0.10) * n
		assert_float(capacity) 				.override_failure_message("a wheel at %.1fx load fell under the 0.95 brake" % k) 				.is_greater(0.95 * REF_LOAD)


# --- the equilibrium invariant ------------------------------------------------

func test_a_wheel_in_equilibrium_does_not_move() -> void:
	# Drive torque exactly balanced by the road reaction is a wheel rolling at a steady slip.
	# It must not accelerate or decelerate, at ANY reaction magnitude — this is the property a
	# clamp on the reaction alone destroys: it leaves (drive - clamped_reaction) pushing every
	# tick, walking the wheel to a slip the driveline never paid for.
	var spec := _spec()
	for torque: float in [10.0, 500.0, 3000.0, 20000.0]:
		var w := _wheel()
		w.omega = 30.0
		for _i in 120:
			w._integrate_spin(torque, -torque, 0.0, spec, TICK, 0.4)
		assert_float(w.omega) \
			.override_failure_message("balanced %.0f Nm moved omega" % torque) \
			.is_equal_approx(30.0, 1e-6)


func test_the_reaction_never_overshoots_into_ringing() -> void:
	# A stationary-slip wheel handed a reaction far too big for its own inertia must settle,
	# not oscillate. Unclamped explicit integration flips the sign of the correction every
	# tick here; the semi-implicit step cannot, because its divisor only ever shrinks a step.
	var spec := _spec()
	var w := _wheel()
	w.omega = 30.0
	var prev_delta := 0.0
	for i in 60:
		var was := w.omega
		# Reaction opposing the spin, sized like a real tire (~10 kN at 0.36 m).
		w._integrate_spin(0.0, -3600.0, 0.0, spec, TICK, 0.4)
		var step := w.omega - was
		assert_float(step).override_failure_message("step %d grew" % i) \
			.is_less_equal(0.0)
		if i > 0:
			assert_float(absf(step)).override_failure_message("step %d rang" % i) \
				.is_less_equal(absf(prev_delta) + 1e-9)
		prev_delta = step


func test_the_step_never_exceeds_the_plain_explicit_one() -> void:
	# "Only ever shrinks a correction" — the same rule every clamp in wheel.gd follows.
	var spec := _spec()
	for reaction: float in [0.0, -100.0, -3600.0, 12000.0]:
		var w := _wheel()
		w.omega = 5.0
		w._integrate_spin(800.0, reaction, 0.0, spec, TICK, 0.4)
		var explicit := 5.0 + (800.0 + reaction) / spec.wheel_inertia * TICK
		assert_float(absf(w.omega - 5.0)) \
			.override_failure_message("reaction %.0f overshot the explicit step" % reaction) \
			.is_less_equal(absf(explicit - 5.0) + 1e-9)
		# ...and it never flips the sign of the correction either.
		assert_float(signf(w.omega - 5.0) * signf(explicit - 5.0)).is_greater_equal(0.0)


func test_it_relaxes_to_the_explicit_step_as_the_tick_shrinks() -> void:
	# The damping is a discretization fix, not a force model: at a fine enough tick it must
	# disappear, or it would be quietly changing the physics rather than integrating it.
	var spec := _spec()
	var fine := TICK / 64.0
	var w := _wheel()
	w.omega = 5.0
	w._integrate_spin(800.0, -400.0, 0.0, spec, fine, 0.4)
	var explicit := 5.0 + (800.0 - 400.0) / spec.wheel_inertia * fine
	assert_float(w.omega).is_equal_approx(explicit, absf(explicit - 5.0) * 0.05)


# --- brakes: inside the same step, clamped at zero spin ----------------------

func test_a_brake_the_road_holds_up_does_not_move_the_wheel() -> void:
	# A braked wheel at a steady slip: the road spins it up exactly as hard as the brake slows it.
	# Both go through the semi-implicit step, so it must not move at any magnitude. A brake outside
	# the step falls (1 + k) times faster than the road can answer, and a firm pedal locks every
	# wheel.
	var spec := _spec()
	for torque: float in [10.0, 500.0, 3000.0, 20000.0]:
		var w := _wheel()
		w.omega = 30.0
		for _i in 120:
			w._integrate_spin(0.0, torque, torque, spec, TICK, 0.4)
		assert_float(w.omega) \
			.override_failure_message("a held %.0f Nm brake moved omega" % torque) \
			.is_equal_approx(30.0, 1e-6)


func test_a_brake_under_the_tyre_settles_where_the_road_carries_it() -> void:
	# Closed loop on a linear tyre at a fixed road speed: the wheel settles where the road's torque
	# equals the brake's, slipping T / (C r) behind the ground. An explicit brake settles 1 + k times
	# further back (k = C r^2 dt / I, ~11 here).
	var spec := _spec()
	var v := 20.0
	var c := 20000.0  ## N per m/s of slip velocity: a gripping tyre
	var brake := 2000.0
	var w := _wheel()
	w.omega = v / spec.wheel_radius
	for _i in 600:
		var slip_vel := w.omega * spec.wheel_radius - v
		w._integrate_spin(0.0, -c * slip_vel * spec.wheel_radius, brake, spec, TICK, slip_vel)
	assert_float(w.omega * spec.wheel_radius - v) \
			.is_equal_approx(-brake / (c * spec.wheel_radius), 1e-3)


func test_a_wheel_on_a_decelerating_body_pays_only_its_own_inertia() -> void:
	# The same linear tyre under a body slowing at a steady 9 m/s^2: the road carries the brake less
	# the wheel's own `I * a / r`. Solved for spin alone (no `dv_long`), the road speed's drop each
	# tick reads as slip the step must buy back, and the road carries `(1 + k)` times that less.
	var spec := _spec()
	var c := 20000.0
	var brake := 2000.0
	var a := 9.0
	var v := 30.0
	var w := _wheel()
	w.omega = v / spec.wheel_radius
	var road := 0.0
	for _i in 120:
		var slip_vel := w.omega * spec.wheel_radius - v
		road = -c * slip_vel * spec.wheel_radius
		w._integrate_spin(0.0, road, brake, spec, TICK, slip_vel, v, 0.0, -a * TICK)
		v -= a * TICK
	assert_float(road).is_equal_approx(brake - spec.wheel_inertia * a / spec.wheel_radius, 1.0)


func test_abs_holds_an_over_strong_brake_at_its_slip() -> void:
	# A brake far past what the wheel can stop in a tick: without ABS the wheel locks in one step,
	# with it the wheel stops at the spin that leaves exactly ABS_SLIP of braking slip.
	var spec := _spec()
	var v := 20.0
	var locked := _wheel()
	locked.omega = v / spec.wheel_radius
	locked._integrate_spin(0.0, 0.0, 1.0e6, spec, TICK, 0.0, v, 0.0)
	assert_float(locked.omega).is_equal(0.0)
	assert_bool(locked.abs_active).is_false()
	var held := _wheel()
	held.omega = v / spec.wheel_radius
	held._integrate_spin(0.0, 0.0, 1.0e6, spec, TICK, 0.0, v, WheelScript.ABS_SLIP)
	assert_float(held.omega).is_equal_approx(v * (1.0 - WheelScript.ABS_SLIP) / spec.wheel_radius, 1e-6)
	assert_bool(held.abs_active).is_true()
	# A brake the wheel can carry is not touched, and ABS does not claim it.
	var light := _wheel()
	light.omega = v / spec.wheel_radius
	light._integrate_spin(0.0, 0.0, 10.0, spec, TICK, 0.0, v, WheelScript.ABS_SLIP)
	assert_float(light.omega).is_equal_approx(v / spec.wheel_radius - 10.0 * TICK / spec.wheel_inertia, 1e-6)
	assert_bool(light.abs_active).is_false()


func test_abs_lets_a_stopping_or_stopped_wheel_hold() -> void:
	var r := 0.36
	# At walking pace the slip floor lets the brake stop the wheel: a vehicle must come to rest.
	assert_float(WheelScript.abs_spin_room(0.5, 0.18, r, WheelScript.ABS_SLIP)).is_equal(0.5)
	# Turning against its travel: braking only helps, so nothing is held back.
	assert_float(WheelScript.abs_spin_room(-3.0, 10.0, r, WheelScript.ABS_SLIP)).is_equal(3.0)
	# Reversing is the mirror image of rolling forward.
	assert_float(WheelScript.abs_spin_room(-10.0 / r, -10.0, r, WheelScript.ABS_SLIP)) \
			.is_equal_approx(WheelScript.abs_spin_room(10.0 / r, 10.0, r, WheelScript.ABS_SLIP), 1e-6)
	# Stopped with the brake on: nothing to take off, and no ABS event to report.
	var spec := _spec()
	var w := _wheel()
	w._integrate_spin(0.0, 0.0, 5000.0, spec, TICK, 0.0, 0.0, WheelScript.ABS_SLIP)
	assert_float(w.omega).is_equal(0.0)
	assert_bool(w.abs_active).is_false()


# --- traction control: the drive's own share, capped at the peak ------------------

func test_tcs_room_is_the_mirror_of_abs() -> void:
	var r := 0.36
	# At rest the slip floor leaves 0.18 m/s of drive slip.
	assert_float(WheelScript.tcs_spin_room(0.0, 0.0, r, WheelScript.TCS_SLIP)) \
			.is_equal_approx(0.18 / r, 1e-6)
	# Turning against the drive: all the way back to the road speed, then on to the peak.
	assert_float(WheelScript.tcs_spin_room(-3.0, 10.0, r, WheelScript.TCS_SLIP)) \
			.is_equal_approx(3.0 + 10.0 * (1.0 + WheelScript.TCS_SLIP) / r, 1e-5)
	# Already past the peak: no room left.
	assert_float(WheelScript.tcs_spin_room(20.0 / r, 10.0, r, WheelScript.TCS_SLIP)).is_equal(0.0)


func test_tcs_room_lets_the_one_tick_cap_pass_the_peak_force() -> void:
	var r := 0.36
	# A tyre loaded past its corner_mass (a tractor unit's drive axle under the plate) needs more
	# slip velocity than the floor-scaled peak for the one-tick cap to pass its budget.
	assert_float(WheelScript.tcs_spin_room(0.0, 0.0, r, WheelScript.TCS_SLIP, 0.35)) \
			.is_equal_approx(0.35 / r, 1e-6)
	# Under the peak's own slip velocity it changes nothing.
	assert_float(WheelScript.tcs_spin_room(0.0, 0.0, r, WheelScript.TCS_SLIP, 0.1)) \
			.is_equal_approx(0.18 / r, 1e-6)
	assert_float(WheelScript.tcs_spin_room(0.0, 10.0, r, WheelScript.TCS_SLIP, 0.35)) \
			.is_equal_approx(10.0 * (1.0 + WheelScript.TCS_SLIP) / r, 1e-5)


func test_tcs_holds_a_floored_drive_at_its_slip() -> void:
	var spec := _spec()
	var v := 10.0
	var c := 20000.0
	var slip_vel := 0.05 * v
	var held := _wheel()
	held.omega = (v + slip_vel) / spec.wheel_radius
	held._integrate_spin(1.0e6, -c * slip_vel * spec.wheel_radius, 0.0, spec, TICK, slip_vel, v,
			0.0, 0.0, WheelScript.TCS_SLIP)
	assert_float(held.omega).is_equal_approx(v * (1.0 + WheelScript.TCS_SLIP) / spec.wheel_radius,
			1e-6)
	assert_bool(held.tcs_active).is_true()
	# A light drive under the peak is the plain step, and TC does not claim it.
	var light := _wheel()
	light.omega = (v + slip_vel) / spec.wheel_radius
	light._integrate_spin(50.0, -c * slip_vel * spec.wheel_radius, 0.0, spec, TICK, slip_vel, v,
			0.0, 0.0, WheelScript.TCS_SLIP)
	var plain := _wheel()
	plain.omega = (v + slip_vel) / spec.wheel_radius
	plain._integrate_spin(50.0, -c * slip_vel * spec.wheel_radius, 0.0, spec, TICK, slip_vel, v)
	assert_float(light.omega).is_equal(plain.omega)
	assert_bool(light.tcs_active).is_false()


func test_tcs_reverse_mirrors_forward() -> void:
	var spec := _spec()
	var fwd := _wheel()
	fwd._integrate_spin(1.0e6, 0.0, 0.0, spec, TICK, 0.0, 5.0, 0.0, 0.0, WheelScript.TCS_SLIP)
	var rev := _wheel()
	rev._integrate_spin(-1.0e6, 0.0, 0.0, spec, TICK, 0.0, -5.0, 0.0, 0.0, WheelScript.TCS_SLIP)
	assert_float(rev.omega).is_equal_approx(-fwd.omega, 1e-6)
	assert_bool(rev.tcs_active).is_true()


func test_tcs_only_removes_drive_and_never_brakes() -> void:
	# Past the peak with a small drive: TC takes back the drive's share and no more; the road
	# reaction alone slows the wheel.
	var spec := _spec()
	var v := 10.0
	var slip_vel := 0.5 * v
	var reaction := -400.0
	var plain := _wheel()
	plain.omega = (v + slip_vel) / spec.wheel_radius
	plain._integrate_spin(20.0, reaction, 0.0, spec, TICK, slip_vel, v)
	var capped := _wheel()
	capped.omega = (v + slip_vel) / spec.wheel_radius
	capped._integrate_spin(20.0, reaction, 0.0, spec, TICK, slip_vel, v, 0.0, 0.0,
			WheelScript.TCS_SLIP)
	assert_float(capped.omega).is_equal_approx(plain.omega - 20.0 * plain.spin_compliance, 1e-9)
	assert_bool(capped.tcs_active).is_true()


func test_tcs_off_is_todays_step_bit_for_bit() -> void:
	var spec := _spec()
	var a := _wheel()
	a.omega = 30.0
	a._integrate_spin(800.0, -300.0, 0.0, spec, TICK, 2.0, 10.0, 0.0, 0.1)
	var b := _wheel()
	b.omega = 30.0
	b._integrate_spin(800.0, -300.0, 0.0, spec, TICK, 2.0, 10.0, 0.0, 0.1, 0.0)
	assert_float(b.omega).is_equal(a.omega)
	assert_bool(b.tcs_active).is_false()


func test_tcs_holds_an_airborne_wheel_at_the_body_speed_plus_the_peak() -> void:
	# Off the ground the step has no reaction, so the whole drive is the share; TC reads the hub's
	# own speed and holds the wheel at the peak over it (the spawn's flash gone).
	var spec := _spec()
	var v := 0.5
	var w := _wheel()
	w._integrate_spin(2000.0, 0.0, 0.0, spec, TICK, 0.0, v, 0.0, 0.0, WheelScript.TCS_SLIP)
	assert_float(w.omega).is_equal_approx(
			(v + WheelScript.TCS_SLIP * WheelScript.LOW_SPEED_FLOOR) / spec.wheel_radius, 1e-6)
	assert_bool(w.tcs_active).is_true()


func test_brakes_decelerate_toward_zero_and_never_reverse_the_spin() -> void:
	var spec := _spec()
	var w := _wheel()
	w.omega = 1.0
	# A brake torque far bigger than one tick's worth stops the wheel dead, not backwards.
	w._integrate_spin(0.0, 0.0, 1.0e6, spec, TICK, 0.0)
	assert_float(w.omega).is_equal(0.0)
	# Reverse spin brakes toward zero from the other side.
	w.omega = -1.0
	w._integrate_spin(0.0, 0.0, 1.0e6, spec, TICK, 0.0)
	assert_float(w.omega).is_equal(0.0)


func test_airborne_spin_is_pure_drive_and_brake() -> void:
	# No contact = no reaction and no slip velocity; the wheel just spins up under drive.
	var spec := _spec()
	var w := _wheel()
	w._integrate_spin(400.0, 0.0, 0.0, spec, TICK, 0.0)
	assert_float(w.omega).is_equal_approx(400.0 / spec.wheel_inertia * TICK, 1e-9)


func test_a_free_wheel_sheds_spin_and_never_reverses_or_gains() -> void:
	# Exponential toward zero at FREE_SPIN_DECAY: one tick off 80 rad/s.
	var decayed := WheelScript.free_spin_omega(80.0, TICK)
	assert_float(decayed).is_equal_approx(
			80.0 - 80.0 * WheelScript.FREE_SPIN_DECAY * TICK, 1e-9)
	assert_bool(decayed < 80.0).is_true()
	# Symmetric on a reversing wheel, and it stops at zero rather than crossing it.
	assert_float(WheelScript.free_spin_omega(-80.0, TICK)).is_equal_approx(-decayed, 1e-9)
	assert_float(WheelScript.free_spin_omega(0.0, TICK)).is_equal(0.0)
	# Even an absurd step lands on zero, never past it.
	assert_float(WheelScript.free_spin_omega(80.0, 1000.0)).is_equal(0.0)


func test_a_free_wheel_falls_below_a_tripped_rev_limiter_within_a_few_ticks() -> void:
	# The bug this exists for: with the pedal down and the limiter cutting, drive, reaction,
	# brake and overrun are all zero, so any wheel that does not decay pins rpm at redline
	# forever. A cut must clear on its own.
	var omega := 82.3
	var ticks := 0
	while omega >= 81.2 and ticks < 600:
		omega = WheelScript.free_spin_omega(omega, TICK)
		ticks += 1
	assert_int(ticks).is_less(30)


# --- corner_mass sizes the one-tick contact clamps ----------------------------

const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
const RefuseBodyScript := preload("res://src/vehicles/truck/refuse_body.gd")


## WheelDrive only reads `get_node_or_null` / `add_child` off its body, so a bare Node3D builds a
## real wheel set with no physics server and no scene.
func _drive_for(spec: VehicleSpec) -> WheelDrive:
	var body: Node3D = auto_free(Node3D.new())
	return WheelDrive.new(body, spec)


func _bench_spec(mass: float) -> VehicleSpec:
	var gd := GroundDriveSpec.new()
	gd.wheel_positions = [
		Vector3(-0.8, 0.0, -1.3), Vector3(0.8, 0.0, -1.3),
		Vector3(-0.8, 0.0, 1.3), Vector3(0.8, 0.0, 1.3),
	]
	var spec := VehicleSpec.new()
	spec.mass = mass
	spec.ground_drive = gd
	return spec


# --- anti-roll bar: the pairing, not the force -------------------------------

## The force itself is `VehicleMath.anti_roll_force` (tests/test_vehicle_math.gd). What is asserted
## here is the WIRING — a bar whose partners never got set is silently inert, and the pure function
## passes either way.

func test_the_bar_pairs_every_wheel_with_the_one_across_its_axle() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate = 7000.0
	var drive := _drive_for(spec)
	for w in drive.wheels:
		assert_object(w.anti_roll_partner).is_not_null()
		assert_object(w.anti_roll_partner).is_not_same(w)
		assert_float(w.anti_roll_partner.anchor.z).is_equal_approx(w.anchor.z, 1e-9)
		assert_float(signf(w.anti_roll_partner.anchor.x)).is_equal(-signf(w.anchor.x))


## The snapshot, not the pairing: after one shared latch, the first wheel of a pair updating its
## live compression (what its `tick` does before its partner's runs) must not move either bar
## force. A latch inside `tick` fails this — the partner's reading goes one tick stale for the
## first wheel only, a phantom left-side damper that the open split turns into ~1 m of drift.
func test_the_bar_reads_one_shared_snapshot_whatever_the_tick_order() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate = 7000.0
	var drive := _drive_for(spec)
	var left: RayWheel = drive.wheels[0]
	var right: RayWheel = left.anti_roll_partner
	for w in [left, right]:
		w.in_contact = true
	left.compression = 0.050
	right.compression = 0.040
	for w in drive.wheels:
		w.latch_bar()
	left.compression = 0.058  # left ticks first and writes this tick's compression
	var f_left := left.bar_force(7000.0)
	right.compression = 0.047
	var f_right := right.bar_force(7000.0)
	assert_float(f_left).is_equal_approx(VehicleMath.anti_roll_force(0.050, 0.040, 7000.0), 1e-9)
	assert_float(f_left + f_right).is_equal_approx(0.0, 1e-9)


func test_the_bar_hangs_free_while_the_partner_is_airborne() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate = 7000.0
	var left: RayWheel = _drive_for(spec).wheels[0]
	left.compression = 0.05
	left.latch_bar()
	left.anti_roll_partner.in_contact = false
	assert_float(left.bar_force(7000.0)).is_equal(0.0)


func test_no_bar_rate_leaves_every_partner_null() -> void:
	for w in _drive_for(_bench_spec(2000.0)).wheels:
		assert_object(w.anti_roll_partner).is_null()


func test_corner_mass_starts_as_the_specs_share_per_wheel() -> void:
	var drive := _drive_for(_bench_spec(2000.0))
	assert_int(drive.wheels.size()).is_equal(4)
	for w in drive.wheels:
		assert_float(w.corner_mass).is_equal_approx(500.0, 1e-9)


func test_the_one_tick_caps_scale_with_a_rewritten_mass() -> void:
	# All three RayWheel caps are `corner_mass * |v| / delta`, so re-sharing the LIVE mass is the
	# whole of "the clamp follows what the body weighs". Nothing here weakens a clamp: the cap is
	# recomputed from a bigger number, it is not widened by a factor.
	var drive := _drive_for(_bench_spec(2000.0))
	var cap_empty: float = drive.wheels[0].corner_mass * 3.0 / TICK   ## cap at 3 m/s of slip
	drive.set_corner_mass_from(3000.0)
	for w in drive.wheels:
		assert_float(w.corner_mass).is_equal_approx(750.0, 1e-9)
	var cap_laden: float = drive.wheels[0].corner_mass * 3.0 / TICK
	assert_float(cap_laden / cap_empty).override_failure_message(
			"the one-tick cap did not follow the laden mass").is_equal_approx(1.5, 1e-9)
	# And it comes back down again, so a dumped hopper is not left over-clamped.
	drive.set_corner_mass_from(2000.0)
	assert_float(drive.wheels[0].corner_mass * 3.0 / TICK).is_equal_approx(cap_empty, 1e-9)


func test_a_full_refuse_hopper_moves_the_shipped_trucks_caps() -> void:
	# The real path: TruckVehicle hands `spec.mass + payload` to BaseVehicle.set_live_mass, which
	# calls set_corner_mass_from. Pinned on the shipped spec so a payload change is visible.
	var scene: PackedScene = load(CatalogScript.scene_of("garbage-truck"))
	var state := scene.get_state()
	var spec: VehicleSpec = null
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"spec":
			spec = state.get_node_property_value(0, i) as VehicleSpec
			break
	assert_object(spec).is_not_null()
	var drive := _drive_for(spec)
	var empty: float = drive.wheels[0].corner_mass
	assert_float(empty).is_equal_approx(
			spec.mass / float(spec.ground_drive.wheel_positions.size()), 1e-6)
	var laden: float = spec.mass + RefuseBodyScript.hopper_mass_kg(100.0)
	drive.set_corner_mass_from(laden)
	assert_float(drive.wheels[0].corner_mass).override_failure_message(
			"a full hopper left the caps sized for the empty truck") \
			.is_equal_approx(laden / float(spec.ground_drive.wheel_positions.size()), 1e-6)
	assert_float(drive.wheels[0].corner_mass).is_greater(empty)


# --- the foot brake split by axle ----------------------------------------------------------

func test_no_bias_brakes_every_wheel_alike_and_a_bias_keeps_the_total() -> void:
	var gd := _bench_spec(1500.0).ground_drive
	gd.brake_torque = 1000.0
	assert_float(gd.axle_brake_torque(false)).is_equal(1000.0)
	assert_float(gd.axle_brake_torque(true)).is_equal(1000.0)
	gd.brake_bias_front = 0.75
	assert_float(gd.axle_brake_torque(false)).is_equal_approx(1500.0, 1e-6)
	assert_float(gd.axle_brake_torque(true)).is_equal_approx(500.0, 1e-6)
	# The pedal's whole torque is unchanged: the bias only moves it between the axles.
	assert_float(2.0 * gd.axle_brake_torque(false) + 2.0 * gd.axle_brake_torque(true)) \
			.is_equal_approx(4.0 * gd.brake_torque, 1e-6)
	# 0 is a real share, rear only; only a negative bias means every wheel alike.
	gd.brake_bias_front = 0.0
	assert_float(gd.axle_brake_torque(false)).is_equal(0.0)
	assert_float(gd.axle_brake_torque(true)).is_equal_approx(2000.0, 1e-6)


# --- rear-axle spring/damper accessors: 0 falls back, dampers track the rate --------------

func test_rear_accessors_fall_back_to_the_front_values_at_zero() -> void:
	var gd := _spec()
	gd.spring_rate = 240000.0
	gd.damper_bump = 12000.0
	gd.damper_rebound = 15800.0
	assert_float(gd.rear_spring_rate()).is_equal_approx(240000.0, 1e-6)
	assert_float(gd.rear_damper_bump()).is_equal_approx(12000.0, 1e-6)
	assert_float(gd.rear_damper_rebound()).is_equal_approx(15800.0, 1e-6)


func test_rear_dampers_scale_by_sqrt_of_the_rate_ratio_when_only_the_rate_is_set() -> void:
	var gd := _spec()
	gd.spring_rate = 240000.0
	gd.damper_bump = 12000.0
	gd.damper_rebound = 15800.0
	gd.spring_rate_rear = 360000.0
	# sqrt(360000/240000) = sqrt(1.5) ~= 1.224745, keeping the front's damping ratio at 1.5x the rate.
	assert_float(gd.rear_spring_rate()).is_equal_approx(360000.0, 1e-6)
	assert_float(gd.rear_damper_bump()).is_equal_approx(14696.9, 0.1)
	assert_float(gd.rear_damper_rebound()).is_equal_approx(19351.0, 0.1)


func test_an_explicit_rear_damper_wins_over_the_rate_scaling() -> void:
	var gd := _spec()
	gd.spring_rate = 240000.0
	gd.damper_bump = 12000.0
	gd.damper_rebound = 15800.0
	gd.spring_rate_rear = 360000.0
	gd.damper_bump_rear = 13000.0
	gd.damper_rebound_rear = 17000.0
	assert_float(gd.rear_damper_bump()).is_equal_approx(13000.0, 1e-6)
	assert_float(gd.rear_damper_rebound()).is_equal_approx(17000.0, 1e-6)


## `link_slope * force_long` is the link force along the contact normal: drive lifts the rear
## (anti-squat) and pulls the front down (anti-lift); braking lifts the front (anti-dive).
func test_link_slopes_are_signed_per_axle() -> void:
	var gd := _spec()
	gd.anti_dive_slope = 0.12
	gd.anti_squat_slope = 0.15
	var front := WheelScript.new(Vector3(0.0, 0.0, -1.0), true, true, null, 300.0)
	var rear := WheelScript.new(Vector3(0.0, 0.0, 1.0), false, true, null, 300.0)
	front.apply_suspension(gd)
	rear.apply_suspension(gd)
	assert_float(rear.link_slope * 1000.0).is_equal_approx(150.0, 1e-4)    # drive: tail up
	assert_float(front.link_slope * 1000.0).is_equal_approx(-120.0, 1e-4)  # drive: nose down
	assert_float(front.link_slope * -1000.0).is_equal_approx(120.0, 1e-4)  # brake: nose up


# --- lateral_mass_at: what a sideways contact force really moves -------------------

func test_a_contact_at_the_centre_of_mass_moves_the_whole_body() -> void:
	var inv := Basis.from_scale(Vector3(1e-4, 1e-4, 1e-4))
	assert_float(WheelScript.lateral_mass_at(Vector3.ZERO, 8000.0, inv)) \
			.is_equal_approx(8000.0, 1e-6)
	# A lever along X is the force's own line: no moment, still the whole body.
	assert_float(WheelScript.lateral_mass_at(Vector3(0.72, 0.0, 0.0), 8000.0, inv)) \
			.is_equal_approx(8000.0, 1e-6)


func test_a_contact_below_the_centre_of_mass_rolls_the_body_and_moves_less() -> void:
	# 1.74 m under the COM on a 13500 kg*m^2 roll moment: the coupled box trailer's bogie.
	var m := 24000.0
	var inv := Basis.from_scale(Vector3(1.0 / 140000.0, 1.0 / 140000.0, 1.0 / 13500.0))
	var arm := Vector3(0.0, -1.74, 0.0)
	assert_float(WheelScript.lateral_mass_at(arm, m, inv)) \
			.is_equal_approx(1.0 / (1.0 / m + 1.74 * 1.74 / 13500.0), 1e-2)  # float32 Basis
	# A fore-aft offset adds the yaw the force turns as well.
	var aft := WheelScript.lateral_mass_at(arm + Vector3(0.0, 0.0, 1.42), m, inv)
	assert_float(aft).is_less(WheelScript.lateral_mass_at(arm, m, inv))
	assert_float(aft).is_less(m / 6.0)


func test_a_massless_body_moves_nothing() -> void:
	assert_float(WheelScript.lateral_mass_at(Vector3(0.0, -1.0, 0.0), 0.0, Basis.IDENTITY)) \
			.is_equal(0.0)


# --- rest ride height: the spawn placer's ground-clearance figure ------------------

func test_rest_ride_height_is_radius_plus_rest_length_above_the_lowest_anchor() -> void:
	var gd := GroundDriveSpecScript.new()
	gd.wheel_radius = 0.32
	gd.rest_length = 0.25
	gd.wheel_positions = PackedVector3Array([
		Vector3(-0.78, -0.1, -1.25), Vector3(0.78, -0.1, -1.25),
		Vector3(-0.78, -0.1, 1.25), Vector3(0.78, -0.1, 1.25),
	])
	# All four anchors share y = -0.1, so the height is 0.32 + 0.25 - (-0.1).
	assert_float(gd.rest_ride_height()).is_equal_approx(0.67, 1e-6)


func test_rest_ride_height_is_set_by_the_lowest_anchor_when_they_differ() -> void:
	var gd := GroundDriveSpecScript.new()
	gd.wheel_radius = 0.5
	gd.rest_length = 0.3
	gd.wheel_positions = PackedVector3Array([
		Vector3(-0.8, -0.05, -1.3), Vector3(0.8, -0.2, -1.3),
	])
	# The lower anchor (-0.2) reaches the ground first, so it sets the origin height.
	assert_float(gd.rest_ride_height()).is_equal_approx(0.5 + 0.3 + 0.2, 1e-6)


func test_rest_ride_height_is_zero_with_no_wheel_positions() -> void:
	var gd := GroundDriveSpecScript.new()
	gd.wheel_positions = PackedVector3Array()
	assert_float(gd.rest_ride_height()).is_equal(0.0)


## BaseVehicle.rest_ride_height() forwards to the spec's ground drive, or 0.0 with none — built
## with no tree, since the method reads only `spec`.
func test_base_vehicle_forwards_rest_ride_height_and_is_zero_with_no_ground_drive() -> void:
	var gd := GroundDriveSpecScript.new()
	gd.wheel_radius = 0.32
	gd.rest_length = 0.25
	gd.wheel_positions = PackedVector3Array([Vector3(0.0, -0.1, -1.0)])
	var wheeled_spec := VehicleSpec.new()
	wheeled_spec.ground_drive = gd
	var wheeled: BaseVehicle = auto_free(BaseVehicle.new())
	wheeled.spec = wheeled_spec
	assert_float(wheeled.rest_ride_height()).is_equal_approx(gd.rest_ride_height(), 1e-6)

	var free_body: BaseVehicle = auto_free(BaseVehicle.new())
	free_body.spec = VehicleSpec.new()  # ground_drive left null, like the boat/drone/train
	assert_float(free_body.rest_ride_height()).is_equal(0.0)


# --- spin compliance: how a differential reaches the spin step ------------------

func test_a_torque_applied_through_the_compliance_is_the_one_inside_the_step() -> void:
	# The semi-implicit step is linear in the applied torque, so a coupling torque applied after it
	# through `spin_compliance` IS the same torque added to drive_t, at any reaction. That is what
	# lets `Differential` couple wheels after they tick without the explicit over-correction.
	var spec := _spec()
	for reaction: float in [0.0, -400.0, -3600.0, -20000.0]:
		var inside := _wheel()
		inside.omega = 20.0
		inside._integrate_spin(800.0 - 150.0, reaction, 0.0, spec, TICK, 0.4)
		var outside := _wheel()
		outside.omega = 20.0
		outside._integrate_spin(800.0, reaction, 0.0, spec, TICK, 0.4)
		outside.omega -= 150.0 * outside.spin_compliance
		assert_float(outside.omega) \
				.override_failure_message("reaction %.0f: post-tick torque diverged" % reaction) \
				.is_equal_approx(inside.omega, 1e-9)


func test_a_gripping_wheel_is_stiffer_than_a_free_one() -> void:
	var spec := _spec()
	var free_wheel := _wheel()
	free_wheel._integrate_spin(400.0, 0.0, 0.0, spec, TICK, 0.0)
	assert_float(free_wheel.spin_compliance).is_equal_approx(TICK / spec.wheel_inertia, 1e-12)
	var gripping := _wheel()
	gripping._integrate_spin(400.0, -3600.0, 0.0, spec, TICK, 0.4)
	assert_float(gripping.spin_compliance).is_less(free_wheel.spin_compliance)


# --- the differential passes in WheelDrive ---------------------------------------

## Hand-set spin and compliance on every wheel, as if they had just ticked: FL, FR, RL, RR.
func _set_spin(drive: WheelDrive, omegas: Array, compliances: Array) -> void:
	for i in drive.wheels.size():
		drive.wheels[i].omega = omegas[i]
		drive.wheels[i].spin_compliance = compliances[i]


func _mfwd_spec() -> VehicleSpec:
	var spec := _bench_spec(5500.0)
	spec.ground_drive.front_axle_engageable = true
	spec.ground_drive.rear_diff_lockable = true
	spec.ground_drive.centre_diff_rigid = true
	return spec


const SPREAD_OMEGAS := [10.0, 12.0, 30.0, 20.0]
const SPREAD_COMPLIANCE := [0.004, 0.002, 0.003, 0.0005]


func test_open_differentials_leave_every_wheel_exactly_as_it_ticked() -> void:
	# All open is today's equal split, bit for bit: the passes must not touch a single omega.
	var spec := _bench_spec(1500.0)
	spec.ground_drive.driven_front = true  # AWD, open centre and axles
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, SPREAD_OMEGAS, SPREAD_COMPLIANCE)
	drive._couple_differentials(spec.ground_drive, input, 2000.0)
	for i in drive.wheels.size():
		assert_float(drive.wheels[i].omega).is_equal(SPREAD_OMEGAS[i])
	assert_bool(drive.rear_diff_locked).is_false()


func test_engaged_mfwd_ties_the_front_axle_to_the_rear() -> void:
	var spec := _mfwd_spec()
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	input.fwd_drive = true
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, SPREAD_OMEGAS, SPREAD_COMPLIANCE)
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	var w := drive.wheels
	assert_float((w[0].omega + w[1].omega) * 0.5) \
			.is_equal_approx((w[2].omega + w[3].omega) * 0.5, 1e-9)
	# Both axles stay open inside: the rear pair keeps a spread, only the axle means are tied.
	assert_float(w[2].omega - w[3].omega).is_greater(0.0)


func test_disengaged_mfwd_couples_nothing_across_the_axles() -> void:
	var spec := _mfwd_spec()
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, SPREAD_OMEGAS, SPREAD_COMPLIANCE)
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	for i in drive.wheels.size():
		assert_float(drive.wheels[i].omega).is_equal(SPREAD_OMEGAS[i])


func test_the_diff_lock_puts_the_rear_pair_on_one_shaft() -> void:
	var spec := _mfwd_spec()
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	input.diff_lock = true
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, SPREAD_OMEGAS, SPREAD_COMPLIANCE)
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	var w := drive.wheels
	assert_float(w[2].omega).is_equal_approx(w[3].omega, 1e-9)
	# The stiff (gripping) RR moves less than the soft RL: the compliance-weighted mean.
	assert_float(w[2].omega).is_equal_approx((0.0005 * 30.0 + 0.003 * 20.0) / 0.0035, 1e-9)
	assert_bool(drive.rear_diff_locked).is_true()
	# Undriven front, untouched.
	assert_float(w[0].omega).is_equal(10.0)


func test_a_limited_slip_axle_moves_no_more_than_its_capacity() -> void:
	var spec := _bench_spec(1500.0)
	spec.ground_drive.diff_bias_rear = 2.5
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	# A wide spread on stiff wheels asks far more torque than a 2.5 bias carries at 1000 N·m in.
	_set_spin(drive, [0.0, 0.0, 60.0, 5.0], [0.001, 0.001, 0.0001, 0.0001])
	drive._couple_differentials(spec.ground_drive, input, 1000.0)
	var moved := (60.0 - drive.wheels[2].omega) / 0.0001
	assert_float(moved).is_equal_approx(Differential.bias_capacity(1000.0, 2.5), 1e-6)
	assert_float((drive.wheels[3].omega - 5.0) / 0.0001).is_equal_approx(moved, 1e-6)
