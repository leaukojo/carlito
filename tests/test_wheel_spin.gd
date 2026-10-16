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


# --- the cornering-stiffness load law: the side slip read against its own peak -----

const REF_N := 3000.0  ## the even corner load the laws are referred to
## The loads the clamps allow, as multiples of REF_N: `load_scaled_mu`'s floor up to the default
## `max_suspension_force` on a 300 kg corner (30 kN / 2943 N).
const LOADS: Array[float] = [0.25, 0.5, 1.0, 2.0, 10.2]
## `cornering_peak_load` around the sourced 1.92-3.33 (`docs/vehicles.md` § Balance).
const PEAKS: Array[float] = [1.5, 1.92, 2.56, 3.33]


func test_the_lateral_peak_slip_is_the_curves_at_the_reference_and_when_off() -> void:
	assert_float(WheelScript.lateral_peak_slip(REF_N, REF_N, 0.1, 2.56)).is_equal_approx(1.0, 1e-6)
	assert_float(WheelScript.lateral_peak_slip(2.0 * REF_N, REF_N, 0.1, 0.0)).is_equal(1.0)
	# Finite at no load: the budget is 0 there, but the multiple must not be NAN.
	assert_bool(is_finite(WheelScript.lateral_peak_slip(0.0, REF_N, 0.1, 2.56))).is_true()
	# Off, the force is exactly the old one.
	for slip: Vector2 in [Vector2(0.03, -0.04), Vector2(-1.0, 0.05), Vector2(0.2, 0.3)]:
		assert_that(WheelScript.combined_slip_force(slip.x, slip.y, B_LONG, B_LAT, _curve(), 1.0)) \
				.is_equal(WheelScript.combined_slip_force(slip.x, slip.y, B_LONG, B_LAT, _curve()))


## A wheel's side force at `ratio` times REF_N and side slip `slip_lat`, built the way `tick` builds
## it: budget `mu(L) * L`, the side slip over `lateral_peak_slip`.
func _side_force(ratio: float, slip_long: float, slip_lat: float, peak: float,
		sensitivity := 0.1) -> Vector2:
	var n_load := ratio * REF_N
	var budget_lat := WheelScript.load_scaled_mu(MU, n_load, REF_N, sensitivity) * n_load
	return WheelScript.combined_slip_force(slip_long, slip_lat, budget_lat, budget_lat, _curve(),
			WheelScript.lateral_peak_slip(n_load, REF_N, sensitivity, peak))


func test_with_the_law_on_an_axle_under_transfer_loses_stiffness() -> void:
	# Outer plus inner wheel at a small slip, against twice the static wheel.
	for peak: float in PEAKS:
		var static_pair := 2.0 * _side_force(1.0, 0.0, 0.01, peak).y
		for d: float in [0.2, 0.5, 0.9]:
			assert_float(_side_force(1.0 + d, 0.0, 0.01, peak).y
					+ _side_force(1.0 - d, 0.0, 0.01, peak).y).is_less(static_pair)


func test_the_law_moves_where_the_side_force_peaks_never_the_peak() -> void:
	for peak: float in PEAKS:
		for ratio: float in LOADS:
			var n_load := ratio * REF_N
			var budget := WheelScript.load_scaled_mu(MU, n_load, REF_N, 0.1) * n_load
			var p := WheelScript.lateral_peak_slip(n_load, REF_N, 0.1, peak)
			assert_float(_side_force(ratio, 0.0, 0.12 * p, peak).y).is_equal_approx(budget,
					budget * 1e-5)
			# And nowhere past the ellipse, side slip alone or combined.
			for slip: Vector2 in [Vector2(0.0, 0.05), Vector2(0.0, 2.0), Vector2(0.1, 0.1),
					Vector2(-1.0, 0.3), Vector2(0.05, -0.6)]:
				var f := _side_force(ratio, slip.x, slip.y, peak)
				assert_float(f.length() / budget).is_less_equal(1.0 + 1e-5)


func test_with_the_law_on_a_locked_wheel_still_stops_steering() -> void:
	# The force's tilt off the slide is `1 / lateral_peak_slip`: most toward the side on a light wheel
	# (p down to 0.82 at c 1.5, 0.91 at the van's 1.92), least on a heavy one. Locked at 0.05 side
	# slip the old law puts 4.0 % of the budget sideways; the worst here 4.9 %.
	var off := _side_force(1.0, -1.0, 0.05, 0.0)
	var off_share := off.y / -off.x
	for peak: float in PEAKS:
		for sensitivity: float in [0.08, 0.12]:
			for ratio: float in LOADS:
				var locked := _side_force(ratio, -1.0, 0.05, peak, sensitivity)
				var share := locked.y / -locked.x
				assert_float(share / off_share).override_failure_message(
						"c %.2f s %.2f at %.2f ref: %.3f" % [peak, sensitivity, ratio, share / off_share]) \
						.is_less(1.25)
				if peak >= 1.92:
					assert_float(share / off_share).is_less(1.15)
				if ratio >= 2.0:
					assert_float(share).is_less(off_share)


func test_a_crawling_contact_on_a_steep_side_rise_settles_without_a_cycle() -> void:
	# One contact crawling at 1 m/s (under the slip floor, past the patch spring), a steady side
	# demand of half its budget, near the least side peak slip of the lowest law here (c 1.5): the
	# side rise passes the one-tick cap, which holds it deadbeat, never ringing.
	var n_load := 0.35 * REF_N
	var budget := WheelScript.load_scaled_mu(MU, n_load, REF_N, 0.08) * n_load
	var p := WheelScript.lateral_peak_slip(n_load, REF_N, 0.08, 1.5)
	var mass := 60.0  ## a light cap mass, so the curve's rise is past the cap
	assert_float(budget / (0.12 * p * WheelScript.LOW_SPEED_FLOOR)).is_greater(mass / TICK)
	var demand := 0.5 * budget
	var v := 0.0
	var prev_dv := 0.0
	var flips := 0
	for _i in 300:
		var tyre := WheelScript.combined_slip_force(0.0, -v / WheelScript.LOW_SPEED_FLOOR, budget,
				budget, _curve(), p)
		var f := clampf(tyre.y, -mass * absf(v) / TICK, mass * absf(v) / TICK)
		var dv := (demand + f) / mass * TICK
		if absf(dv) > 1e-9 and absf(prev_dv) > 1e-9 and signf(dv) * signf(prev_dv) < 0.0:
			flips += 1  ## float noise around the settled force is not a cycle
		prev_dv = dv
		v += dv
	assert_int(flips).is_equal(0)
	assert_float(prev_dv).is_equal_approx(0.0, 1e-6)


# --- static friction: the patch spring a held wheel stands on ---------------------

const CORNER_KG := 350.0
const MU := 1.0


## One contact on a grade (`grade` = rise/run), its wheel held, stepped explicitly at 60 Hz the way
## `RayWheel.tick` builds the force: the slip force (one-tick capped) as the damper, the patch
## spring beside it, the sum in the ellipse. Semi-implicit Euler like the solver. Returns
## (position, velocity) along the slope after `ticks` (+ = up it).
func _held_on_grade(grade: float, ticks: int) -> Vector2:
	var a := atan(grade)
	var budget := MU * CORNER_KG * 9.81 * cos(a)
	var weight := -CORNER_KG * 9.81 * sin(a)
	var x := 0.0
	var v := 0.0
	var stick := Vector2.ZERO
	var k := WheelScript.stick_stiffness(budget, CORNER_KG, TICK)
	for _i in ticks:
		var slip_vel := -v  ## a held wheel: the whole contact velocity is slide
		var tyre := WheelScript.combined_slip_force(
				slip_vel / maxf(absf(v), WheelScript.LOW_SPEED_FLOOR), 0.0, budget, budget, _curve())
		var f_long := clampf(tyre.x, -CORNER_KG * absf(slip_vel) / TICK,
				CORNER_KG * absf(slip_vel) / TICK)
		var w := clampf(1.0 - absf(v) / WheelScript.STICK_SPEED, 0.0, 1.0)
		stick = WheelScript.stick_step(stick, Vector2(slip_vel, 0.0), 0.0, TICK)
		stick = WheelScript.stick_saturate(stick, Vector2(k, k), budget, budget)
		var f := WheelScript.friction_ellipse(Vector2(f_long, 0.0) + w * k * stick, budget, budget)
		v += (f.x + weight) / CORNER_KG * TICK
		x += v * TICK
	return Vector2(x, v)


func test_a_braked_wheel_holds_at_rest_on_a_grade() -> void:
	# A minute held on 10 % and 30 %, both inside mu = 1: the patch spring takes the grade and the
	# contact stays put. The slip force alone, a damper, creeps here (~2 and ~5 cm/s).
	for grade: float in [0.1, 0.3]:
		var settled := _held_on_grade(grade, 90)  ## 1.5 s, the spring wound up
		var end := _held_on_grade(grade, 3690)
		assert_float(absf(end.x - settled.x)).override_failure_message(
				"crept %.3f mm in 60 s on %.0f %%" % [(end.x - settled.x) * 1000.0, grade * 100.0]) \
				.is_less(1e-4)
		assert_float(absf(end.y)).is_less(1e-5)
		# What it gave to get there is the spring's wind-up: the grade over its stiffness.
		var a := atan(grade)
		assert_float(end.x).is_equal_approx(-WheelScript.STICK_DEFLECTION * tan(a) / MU, 2e-4)


func test_past_its_grip_a_held_wheel_slides_at_the_friction_limit() -> void:
	# 1.5 rise/run beats mu = 1: the spring saturates and the contact slides at Coulomb's
	# g (sin a - mu cos a), not at a viscous crawl.
	var a := atan(1.5)
	var coulomb := 9.81 * (sin(a) - MU * cos(a))
	# Over its first quarter second the tyre's mean force is the budget, short only of the wind-up
	# and the grip curve's tail (0.8-1.0): a viscous creep would barely move.
	var end := _held_on_grade(1.5, 15)
	var mean_force := 1.0 - (-end.y / (15.0 * TICK) - coulomb) / (9.81 * MU * cos(a))
	assert_float(mean_force).override_failure_message("mean tyre force %.2f of the budget"
			% mean_force).is_between(0.85, 1.0)


func test_the_patch_spring_relaxes_as_it_rolls_and_never_flips() -> void:
	var z := Vector2(0.01, -0.01)
	assert_that(WheelScript.stick_step(z, Vector2.ZERO, 0.0, TICK)).is_equal(z)
	# One relaxation length rolled is e^-1 of the deflection; a huge roll speed decays toward 0,
	# never past it.
	var one := WheelScript.stick_step(z, Vector2.ZERO, WheelScript.STICK_RELAX / TICK, TICK)
	assert_float(one.x).is_equal_approx(0.01 * exp(-1.0), 1e-6)
	var fast := WheelScript.stick_step(z, Vector2.ZERO, 1000.0, TICK)
	assert_float(fast.x).is_between(0.0, 1e-6)
	assert_float(fast.y).is_between(-1e-6, 0.0)
	# The slide adds its own distance.
	assert_float(WheelScript.stick_step(Vector2.ZERO, Vector2(0.6, 0.0), 0.0, TICK).x) \
			.is_equal_approx(0.6 * TICK, 1e-7)


func test_the_patch_spring_reaches_the_budget_at_its_deflection_under_the_tick_clamp() -> void:
	# A car corner: 3400 N at 2 cm, well inside 0.25 * m / dt^2.
	assert_float(WheelScript.stick_stiffness(3400.0, CORNER_KG, TICK)) \
			.is_equal_approx(3400.0 / WheelScript.STICK_DEFLECTION, 1e-3)
	# A light mass under a big budget: the tick clamp binds.
	assert_float(WheelScript.stick_stiffness(3400.0, 10.0, TICK)) \
			.is_equal_approx(WheelScript.STICK_TICK_STIFFNESS * 10.0 / (TICK * TICK), 1e-3)


func test_a_saturated_patch_spring_carries_exactly_the_budget() -> void:
	var k := Vector2(50000.0, 40000.0)  ## clamped below budget / STICK_DEFLECTION
	var z := WheelScript.stick_saturate(Vector2(1.0, 1.0), k, B_LONG, B_LAT)
	assert_float(Vector2(k.x * z.x / B_LONG, k.y * z.y / B_LAT).length()) \
			.is_equal_approx(1.0, 1e-5)
	# Inside the ellipse it is left alone; no budget, no spring.
	var small := Vector2(0.001, -0.001)
	assert_that(WheelScript.stick_saturate(small, k, B_LONG, B_LAT)).is_equal(small)
	assert_that(WheelScript.stick_saturate(small, k, 0.0, B_LAT)).is_equal(Vector2.ZERO)


func test_the_friction_ellipse_keeps_direction_and_never_leaves_the_budget() -> void:
	var f := WheelScript.friction_ellipse(Vector2(3000.0, -2000.0), B_LONG, B_LAT)
	assert_float(Vector2(f.x / B_LONG, f.y / B_LAT).length()).is_equal_approx(1.0, 1e-5)
	assert_float(f.y / f.x).is_equal_approx(-2000.0 / 3000.0, 1e-5)
	assert_that(WheelScript.friction_ellipse(Vector2(10.0, 10.0), B_LONG, B_LAT)) \
			.is_equal(Vector2(10.0, 10.0))


func test_a_brake_that_stops_the_spin_holds_the_wheel_and_a_weak_one_does_not() -> void:
	# The held latch is the step's own Coulomb check: brake >= the reaction it must carry.
	var spec := _spec()
	var w := _wheel()
	w._integrate_spin(0.0, -900.0, 1000.0, spec, TICK, 0.001)
	assert_float(w.omega).is_equal(0.0)
	assert_bool(w._spin_held).is_true()
	var weak := _wheel()
	weak._integrate_spin(0.0, -900.0, 800.0, spec, TICK, 0.001)
	assert_float(weak.omega).is_not_equal(0.0)
	assert_bool(weak._spin_held).is_false()
	# No brake is never a hold, however still the wheel.
	var free := _wheel()
	free._integrate_spin(0.0, 0.0, 0.0, spec, TICK, 0.0)
	assert_bool(free._spin_held).is_false()


func test_a_held_patch_carries_no_more_than_its_brake_holds() -> void:
	# 305 Nm on 0.36 m against no drive: under the tyre's 4000 N, so the brake bounds both ways.
	var none := WheelScript.held_force_range(4000.0, 305.0, 0.0, 0.36)
	assert_float(none.y).is_equal_approx(0.98 * 305.0 / 0.36, 1e-3)
	assert_float(none.x).is_equal_approx(-0.98 * 305.0 / 0.36, 1e-3)
	# A drive is held with its sign: 100 Nm forward (a converter's creep) lets the patch push the
	# body forward by that much more and backward by that much less; reversed, the other way.
	var fwd := WheelScript.held_force_range(4000.0, 305.0, 100.0, 0.36)
	assert_float(fwd.y).is_equal_approx((100.0 + 0.98 * 305.0) / 0.36, 1e-3)
	assert_float(fwd.x).is_equal_approx((100.0 - 0.98 * 305.0) / 0.36, 1e-3)
	var back := WheelScript.held_force_range(4000.0, 305.0, -100.0, 0.36)
	assert_float(back.y).is_equal_approx(-fwd.x, 1e-3)
	# More drive than brake holds nothing.
	assert_vector(WheelScript.held_force_range(4000.0, 305.0, 400.0, 0.36)).is_equal(Vector2.ZERO)
	# A strong brake leaves the tyre's budget.
	assert_vector(WheelScript.held_force_range(4000.0, 5000.0, 0.0, 0.36)) \
			.is_equal(Vector2(-4000.0, 4000.0))
	# At either edge the step's Coulomb check still holds the wheel.
	for edge: float in [fwd.x, fwd.y]:
		var w := _wheel()
		w._integrate_spin(100.0, -edge * 0.36, 305.0, _spec(), TICK, 0.0)
		assert_bool(w._spin_held).is_true()


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
		assert_float(WheelScript.load_scaled_mu(1.05, REF_LOAD, REF_LOAD, sens)) \
				.is_equal_approx(1.05, 1e-6)
	# A degenerate reference cannot divide: fall back to the flat mu rather than to infinity.
	assert_float(WheelScript.load_scaled_mu(1.05, REF_LOAD, 0.0, 0.10)).is_equal(1.05)


func test_load_scaled_mu_falls_by_the_declared_fraction_per_doubling() -> void:
	# The declaration is "0.10 of mu lost per doubling of load", so a 2x load reads 0.90 * mu and a
	# half load reads 1.10 * mu. Below the reference grip is worth MORE per newton, not less.
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 2.0, REF_LOAD, 0.10)) \
			.is_equal_approx(0.90, 1e-6)
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 4.0, REF_LOAD, 0.10)) \
			.is_equal_approx(0.80, 1e-6)
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.5, REF_LOAD, 0.10)) \
			.is_equal_approx(1.10, 1e-6)
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
	assert_float(WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.01, REF_LOAD, 0.10)) \
			.is_equal_approx(at_floor, 1e-6)
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
		var transferred := WheelScript.load_scaled_mu(1.0, hi, REF_LOAD, 0.10) * hi \
				+ WheelScript.load_scaled_mu(1.0, lo, REF_LOAD, 0.10) * lo
		assert_float(transferred) \
				.override_failure_message("transfer of %.0f%% did not cost the pair grip" % (frac * 100.0)) \
				.is_less(prev)
		prev = transferred
	# Sensitivity 0 is the control: the same transfer costs exactly nothing.
	var flat := WheelScript.load_scaled_mu(1.0, REF_LOAD * 1.8, REF_LOAD, 0.0) * REF_LOAD * 1.8 \
			+ WheelScript.load_scaled_mu(1.0, REF_LOAD * 0.2, REF_LOAD, 0.0) * REF_LOAD * 0.2
	assert_float(flat).is_equal_approx(2.0 * REF_LOAD, 1e-6)


func test_a_loaded_wheel_still_brakes_harder_in_newtons_than_the_reference_one() -> void:
	# Absolute capacity still rises with load: the axle that gains weight under braking grips more
	# newtons than at the even static load, never fewer. Locking is a property of the UNLOADED axle.
	for k: float in [1.1, 1.5, 2.0, 2.6]:
		var n := REF_LOAD * k
		var capacity := WheelScript.load_scaled_mu(1.0, n, REF_LOAD, 0.10) * n
		assert_float(capacity) \
				.override_failure_message("a wheel at %.1fx load lost grip in newtons" % k) \
				.is_greater(REF_LOAD)


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


## Spin a brake may take off before ABS holds it: the room above the ABS floor.
func _abs_room(spin: float, v_long: float, r: float, abs_slip: float) -> float:
	return WheelScript.brake_room(spin, WheelScript.abs_floor_spin(v_long, r, abs_slip))


func test_abs_lets_a_stopping_or_stopped_wheel_hold() -> void:
	var r := 0.36
	# At walking pace the slip floor lets the brake stop the wheel: a vehicle must come to rest.
	assert_float(_abs_room(0.5, 0.18, r, WheelScript.ABS_SLIP)).is_equal(0.5)
	# Turning against its travel: braking only helps, so nothing is held back.
	assert_float(_abs_room(-3.0, 10.0, r, WheelScript.ABS_SLIP)).is_equal(3.0)
	# Reversing is the mirror image of rolling forward.
	assert_float(_abs_room(-10.0 / r, -10.0, r, WheelScript.ABS_SLIP)) \
			.is_equal_approx(_abs_room(10.0 / r, 10.0, r, WheelScript.ABS_SLIP), 1e-6)
	# Stopped with the brake on: nothing to take off, and no ABS event to report.
	var spec := _spec()
	var w := _wheel()
	w._integrate_spin(0.0, 0.0, 5000.0, spec, TICK, 0.0, 0.0, WheelScript.ABS_SLIP)
	assert_float(w.omega).is_equal(0.0)
	assert_bool(w.abs_active).is_false()


# --- traction control: the drive's own share, capped at the peak ------------------

func test_tcs_ceiling_is_the_mirror_of_abs() -> void:
	var r := 0.36
	# At rest the slip floor leaves 0.18 m/s of drive slip, on the drive's side.
	assert_float(WheelScript.tcs_ceiling_spin(0.0, 1.0, r, WheelScript.TCS_SLIP)) \
			.is_equal_approx(0.18 / r, 1e-6)
	assert_float(WheelScript.tcs_ceiling_spin(0.0, -1.0, r, WheelScript.TCS_SLIP)) \
			.is_equal_approx(-0.18 / r, 1e-6)
	# Rolling, the ceiling sits as far over the road speed as the ABS floor sits under it.
	assert_float(WheelScript.tcs_ceiling_spin(10.0, 1.0, r, WheelScript.TCS_SLIP)
			+ WheelScript.abs_floor_spin(10.0, r, WheelScript.ABS_SLIP)) \
			.is_equal_approx(20.0 / r, 1e-5)
	# Reverse mirrors forward.
	var forward := WheelScript.tcs_ceiling_spin(10.0, 1.0, r, WheelScript.TCS_SLIP)
	assert_float(WheelScript.tcs_ceiling_spin(-10.0, -1.0, r, WheelScript.TCS_SLIP)) \
			.is_equal_approx(-forward, 1e-9)
	var ceiling := WheelScript.tcs_ceiling_spin(10.0, 1.0, r, WheelScript.TCS_SLIP)
	# Turning against the drive: the hold takes nothing, all the way back to the road speed.
	assert_float(WheelScript.tcs_take(-3.0, 50.0, ceiling)).is_equal(0.0)
	# Past the peak: back to the ceiling, never more than the drive's share.
	assert_float(WheelScript.tcs_take(20.0 / r, 50.0, ceiling)) \
			.is_equal_approx(20.0 / r - ceiling, 1e-9)
	assert_float(WheelScript.tcs_take(20.0 / r, 2.0, ceiling)).is_equal_approx(2.0, 1e-9)


func test_a_light_corner_keeps_the_low_speed_floor() -> void:
	# 3000 N on 400 kg: the curve's rise, 3000 / 0.12 / 1.5 N per m/s, is under 400 / TICK.
	assert_float(WheelScript.slip_floor_for(3000.0, 400.0, _curve(), TICK)) 			.is_equal(WheelScript.LOW_SPEED_FLOOR)
	assert_float(WheelScript.slip_floor_for(3000.0, 0.0, _curve(), TICK)) 			.is_equal(WheelScript.LOW_SPEED_FLOOR)


func test_on_its_slip_floor_a_crawling_tyre_reaches_its_budget_inside_the_one_tick_cap() -> void:
	# A TC-held crawl: 3900 N on a 250 kg cap mass. On the 1.5 m/s floor the peak sits at 0.18 m/s
	# of slip, where the cap passes only 2700 N; the raised floor moves the peak to where it passes
	# the whole budget, and keeps every slip short of it inside the cap too.
	var budget := 3900.0
	var m := 250.0
	assert_float(m * 0.12 * WheelScript.LOW_SPEED_FLOOR / TICK).is_less(budget)
	var floor_vel := WheelScript.slip_floor_for(budget, m, _curve(), TICK)
	assert_float(floor_vel).is_greater(WheelScript.LOW_SPEED_FLOOR)
	for i in range(1, 41):
		var slip_vel := 0.01 * i
		var f := WheelScript.combined_slip_force(slip_vel / floor_vel, 0.0, budget, budget,
				_curve()).x
		assert_float(f).override_failure_message("%.0f N past the cap at %.2f m/s" % [
				f - m * slip_vel / TICK, slip_vel]).is_less_equal(m * slip_vel / TICK + 1e-3)
	var peak := WheelScript.combined_slip_force(0.12, 0.0, budget, budget, _curve()).x
	assert_float(peak).is_equal_approx(budget, 1e-3)
	assert_float(m * 0.12 * floor_vel / TICK).is_greater_equal(budget - 1e-3)
	# The traction control holds the same peak: its ceiling reads the same floor.
	assert_float(WheelScript.tcs_ceiling_spin(0.0, 1.0, 0.36, WheelScript.TCS_SLIP, floor_vel)) 			.is_equal_approx(WheelScript.TCS_SLIP * floor_vel / 0.36, 1e-6)


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


func test_tcs_takes_back_no_more_than_the_drive_share() -> void:
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


func test_tcs_only_removes_drive_and_never_brakes() -> void:
	# The drive reaches a wheel through the crank's coupling, so the hold's share is what the
	# coupling may pass it this tick (`tcs_drive`), latched before the solve, and it can outweigh
	# what the coupling then carries. However big, it only pulls the wheel down to its ceiling,
	# which sits above road speed: the tyre's force stays forward, never a brake.
	var spec := _spec()
	var v := 10.0
	var slip_vel := 0.5 * v
	var held := _wheel()
	held.omega = (v + slip_vel) / spec.wheel_radius
	held._integrate_spin(0.0, -400.0, 0.0, spec, TICK, slip_vel, v, 0.0, 0.0,
			WheelScript.TCS_SLIP, 1.0e6)
	var ceiling := WheelScript.tcs_ceiling_spin(v, 1.0, spec.wheel_radius, WheelScript.TCS_SLIP)
	assert_float(held.omega).is_equal_approx(ceiling, 1e-9)
	assert_bool(held.tcs_active).is_true()
	assert_float(held.omega * spec.wheel_radius).is_greater(v)
	# Under its ceiling a wheel loses nothing to the hold, however big the share.
	var slow := _wheel()
	slow.omega = (v + 0.05 * v) / spec.wheel_radius
	slow._integrate_spin(0.0, -100.0, 0.0, spec, TICK, 0.05 * v, v, 0.0, 0.0,
			WheelScript.TCS_SLIP, 1.0e6)
	var plain := _wheel()
	plain.omega = (v + 0.05 * v) / spec.wheel_radius
	plain._integrate_spin(0.0, -100.0, 0.0, spec, TICK, 0.05 * v, v)
	assert_float(slow.omega).is_equal(plain.omega)
	assert_bool(slow.tcs_active).is_false()


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


func test_tc_drives_through_settle_spin() -> void:
	# A coupled wheel leaves its step with the hold latched, not applied: the differentials solve it
	# first. Settled with no coupling torque it lands exactly where a lone wheel's own step does.
	var spec := _spec()
	var lone := _wheel()
	lone._integrate_spin(1.0e6, 0.0, 0.0, spec, TICK, 0.0, 5.0, 0.0, 0.0, WheelScript.TCS_SLIP)
	var coupled := _wheel()
	coupled.coupled_spin = true
	coupled._integrate_spin(1.0e6, 0.0, 0.0, spec, TICK, 0.0, 5.0, 0.0, 0.0, WheelScript.TCS_SLIP)
	assert_float(coupled.omega).is_greater(lone.omega)
	assert_bool(coupled.tcs_active).is_false()
	coupled.settle_spin(0.0)
	assert_float(coupled.omega).is_equal(lone.omega)
	assert_bool(coupled.tcs_active).is_true()


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


## Unequal bars: each wheel carries its own axle's rate, and each axle's pair stays equal and
## opposite off the one shared latch.
func test_each_axle_reads_its_own_bar_rate_off_the_shared_snapshot() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate = 7000.0
	spec.ground_drive.anti_roll_rate_rear = 3000.0
	var drive := _drive_for(spec)
	for w in drive.wheels:
		w.in_contact = true
		w.compression = 0.050 if w.anchor.x < 0.0 else 0.040
		assert_float(w.bar_rate).is_equal(3000.0 if w.is_rear else 7000.0)
	for w in drive.wheels:
		w.latch_bar()
	for w in drive.wheels:
		w.compression += 0.008  # this tick's write must not move either axle's bar
	for w in drive.wheels:
		var f := w.bar_force(w.bar_rate)
		var mine := 0.050 if w.anchor.x < 0.0 else 0.040
		var theirs := 0.090 - mine
		assert_float(f).is_equal_approx(VehicleMath.anti_roll_force(mine, theirs, w.bar_rate), 1e-9)
		assert_float(f + w.anti_roll_partner.bar_force(w.anti_roll_partner.bar_rate)) \
				.is_equal_approx(0.0, 1e-9)


## A rear-only bar (front 0) still pairs the wheels, or it would never act.
func test_a_rear_only_bar_still_pairs_the_wheels() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate_rear = 5000.0
	for w in _drive_for(spec).wheels:
		assert_object(w.anti_roll_partner).is_not_null()
		assert_float(w.bar_rate).is_equal(5000.0 if w.is_rear else 0.0)


func test_the_rear_bar_falls_back_to_the_front_rate_only_when_negative() -> void:
	var gd := _spec()
	gd.anti_roll_rate = 7000.0
	assert_float(gd.rear_anti_roll_rate()).is_equal(7000.0)
	gd.anti_roll_rate_rear = 0.0  # no rear bar: real hardware, not the sentinel
	assert_float(gd.rear_anti_roll_rate()).is_equal(0.0)
	assert_bool(gd.has_anti_roll_bar()).is_true()


func test_the_bar_hangs_free_while_the_partner_is_airborne() -> void:
	var spec := _bench_spec(2000.0)
	spec.ground_drive.anti_roll_rate = 7000.0
	var drive := _drive_for(spec)  # holds the pair: a wheel holds its partner only weakly
	var left: RayWheel = drive.wheels[0]
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


# --- contact_masses: what a contact force really moves -------------------------------

## A lone contact's figure.
func _lone_mass(arm: Vector3, axis: Vector3, m: float, inv: Basis) -> float:
	return WheelScript.contact_masses(PackedVector3Array([arm]), axis, m, inv)[0]


func test_a_contact_at_the_centre_of_mass_moves_the_whole_body() -> void:
	var inv := Basis.from_scale(Vector3(1e-4, 1e-4, 1e-4))
	assert_float(_lone_mass(Vector3.ZERO, Vector3.RIGHT, 8000.0, inv)) 			.is_equal_approx(8000.0, 1e-6)
	# A lever along X is the force's own line: no moment, still the whole body.
	assert_float(_lone_mass(Vector3(0.72, 0.0, 0.0), Vector3.RIGHT, 8000.0, inv)) 			.is_equal_approx(8000.0, 1e-6)


func test_a_contact_below_the_centre_of_mass_rolls_the_body_and_moves_less() -> void:
	# 1.74 m under the COM on a 13500 kg*m^2 roll moment: the coupled box trailer's bogie.
	var m := 24000.0
	var inv := Basis.from_scale(Vector3(1.0 / 140000.0, 1.0 / 140000.0, 1.0 / 13500.0))
	var arm := Vector3(0.0, -1.74, 0.0)
	assert_float(_lone_mass(arm, Vector3.RIGHT, m, inv)) 			.is_equal_approx(1.0 / (1.0 / m + 1.74 * 1.74 / 13500.0), 1e-2)  # float32 Basis
	# A fore-aft offset adds the yaw the force turns as well.
	var aft := _lone_mass(arm + Vector3(0.0, 0.0, 1.42), Vector3.RIGHT, m, inv)
	assert_float(aft).is_less(_lone_mass(arm, Vector3.RIGHT, m, inv))
	assert_float(aft).is_less(m / 6.0)


func test_a_contact_below_the_centre_of_mass_pitches_the_body_along_the_wheel() -> void:
	# The same lever along the wheel meets the PITCH moment (X), not the roll one.
	var m := 1500.0
	var inv := Basis.from_scale(Vector3(1.0 / 2200.0, 1.0 / 2500.0, 1.0 / 600.0))
	var arm := Vector3(0.0, -0.74, 0.0)
	assert_float(_lone_mass(arm, Vector3.BACK, m, inv)) 			.is_equal_approx(1.0 / (1.0 / m + 0.74 * 0.74 / 2200.0), 1e-2)  # float32 Basis
	# The track's half-width adds the yaw a single wheel's push turns.
	assert_float(_lone_mass(arm + Vector3(0.63, 0.0, 0.0), Vector3.BACK, m, inv)) 			.is_less(_lone_mass(arm, Vector3.BACK, m, inv))


func test_four_wheels_pushing_together_cancel_their_yaw_and_share_the_pitch() -> void:
	# A car's four contacts 0.74 m under the COM: pushed evenly along the wheel the sides' yaw
	# cancels, so each moves a quarter of the pitch-only figure, more than a lone wheel's quarter.
	var m := 1500.0
	var inv := Basis.from_scale(Vector3(1.0 / 2200.0, 1.0 / 2500.0, 1.0 / 600.0))
	var arms := PackedVector3Array([Vector3(-0.63, -0.74, -1.3), Vector3(0.63, -0.74, -1.3),
			Vector3(-0.63, -0.74, 1.3), Vector3(0.63, -0.74, 1.3)])
	var masses := WheelScript.contact_masses(arms, Vector3.BACK, m, inv)
	var even := 1.0 / (4.0 * (1.0 / m + 0.74 * 0.74 / 2200.0))
	for i in arms.size():
		assert_float(masses[i]).is_equal_approx(even, 1e-2)  # float32 Basis
	assert_float(masses[0]).is_greater(_lone_mass(arms[0], Vector3.BACK, m, inv) / 4.0)


func test_capped_contacts_never_overshoot_in_any_mode() -> void:
	# A is the contacts' coupled inverse mass, D the caps; a mode's one-tick response is the Rayleigh
	# quotient of D^1/2 A D^1/2, which must stay <= 1 (cancel at most): an even push, the sides
	# against each other, the axles against each other, one wheel alone.
	var m := 8000.0
	var inv := Basis.from_scale(Vector3(1.0 / 30000.0, 1.0 / 32000.0, 1.0 / 6000.0))
	var arms := PackedVector3Array([Vector3(-1.0, -1.4, -2.0), Vector3(1.0, -1.4, -2.0),
			Vector3(-1.0, -1.4, 2.5), Vector3(1.0, -1.4, 2.5)])
	for axis: Vector3 in [Vector3.BACK, Vector3.RIGHT]:
		var masses := WheelScript.contact_masses(arms, axis, m, inv)
		for u: Array in [[1.0, 1.0, 1.0, 1.0], [1.0, -1.0, 1.0, -1.0], [1.0, 1.0, -1.0, -1.0],
				[1.0, 0.0, 0.0, 0.0]]:
			var response := 0.0
			var norm := 0.0
			for i in arms.size():
				norm += u[i] * u[i]
				for j in arms.size():
					var a_ij := 1.0 / m + arms[i].cross(axis).dot(inv * arms[j].cross(axis))
					response += u[i] * sqrt(masses[i]) * a_ij * sqrt(masses[j]) * u[j]
			assert_float(response / norm).is_less_equal(1.0 + 1e-4)


func test_a_massless_body_moves_nothing() -> void:
	assert_float(_lone_mass(Vector3(0.0, -1.0, 0.0), Vector3.RIGHT, 0.0, Basis.IDENTITY)) 			.is_equal(0.0)


# --- patch_offset: where a disk on the hub touches the road --------------------------

func test_a_level_wheel_touches_straight_below_its_hub() -> void:
	assert_vector(WheelScript.patch_offset(Vector3.UP, Vector3.UP, Vector3.RIGHT, 0.35)) \
			.is_equal_approx(Vector3(0.0, -0.35, 0.0), Vector3.ONE * 1e-5)


func test_a_rolled_wheel_still_touches_along_its_own_up() -> void:
	# A thin disk rolled on a flat touches the rim point in its own plane: body down, as before.
	var roll := Basis(Vector3.BACK, deg_to_rad(8.0))
	var up := roll * Vector3.UP
	assert_vector(WheelScript.patch_offset(Vector3.UP, up, roll * Vector3.RIGHT, 0.35)) \
			.is_equal_approx(-up * 0.35, Vector3.ONE * 1e-5)


func test_a_pitched_wheel_touches_straight_below_its_hub_in_the_world() -> void:
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(5.0))
	var offset := WheelScript.patch_offset(Vector3.UP, pitch * Vector3.UP, pitch * Vector3.RIGHT,
			0.35)
	assert_vector(offset).is_equal_approx(Vector3(0.0, -0.35, 0.0), Vector3.ONE * 1e-5)


func test_a_steered_wheel_touches_in_its_own_plane() -> void:
	# Steered 30 degrees on a body pitched on a flat: the patch leaves the hub in the wheel's plane
	# only, and lands on the road's line under it.
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(5.0))
	var up := pitch * Vector3.UP
	var axle := Basis(up, deg_to_rad(30.0)) * (pitch * Vector3.RIGHT)
	var offset := WheelScript.patch_offset(Vector3.UP, up, axle, 0.35)
	assert_float(offset.dot(axle)).is_equal_approx(0.0, 1e-5)
	assert_float(offset.length()).is_equal_approx(0.35, 1e-5)
	assert_float(offset.y).is_less(-0.35 * cos(deg_to_rad(5.0)))


func test_a_back_face_hit_keeps_the_patch_below_the_hub() -> void:
	var up := Vector3.UP
	assert_vector(WheelScript.patch_offset(Vector3.DOWN, up, Vector3.RIGHT, 0.35)) \
			.is_equal_approx(-up * 0.35, Vector3.ONE * 1e-5)
	# A normal along the axle has nothing in the wheel's plane.
	assert_vector(WheelScript.patch_offset(Vector3.RIGHT, up, Vector3.RIGHT, 0.35)) \
			.is_equal_approx(-up * 0.35, Vector3.ONE * 1e-5)


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


## Each wheel's latched traction-control hold, as if it had just ticked (FL, FR, RL, RR): the drive
## share it may take back and the spin it holds at.
func _set_tcs(drive: WheelDrive, shares: Array, ceilings: Array) -> void:
	for i in drive.wheels.size():
		drive.wheels[i].tcs_spin = shares[i]
		drive.wheels[i].tcs_ceiling = ceilings[i]


func test_a_tc_held_wheel_stays_at_its_ceiling_through_a_limited_slip_axle() -> void:
	# RL spins past its ceiling (32 against 30, 4 rad/s of drive share), RR grips. The 2.5 LSD
	# carries its capacity into RR, and RL stays held at its ceiling, never pulled under it.
	var spec := _bench_spec(1500.0)
	spec.ground_drive.diff_bias_rear = 2.5
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var cap := Differential.bias_capacity(1000.0, 2.5)
	_set_spin(drive, [0.0, 0.0, 32.0, 28.0], [0.001, 0.001, 0.002, 0.0002])
	_set_tcs(drive, [0.0, 0.0, 4.0, 4.0], [0.0, 0.0, 30.0, 30.0])
	drive._couple_differentials(spec.ground_drive, input, 1000.0)
	var w := drive.wheels
	assert_float(w[2].omega).is_equal_approx(30.0, 1e-9)
	assert_bool(w[2].tcs_active).is_true()
	assert_float(w[3].omega).is_equal_approx(28.0 + cap * 0.0002, 1e-9)
	assert_bool(w[3].tcs_active).is_false()
	# Both spinning, RL on the outside of a turn (ceiling 34): the LSD may not lift the slower RR
	# past its own ceiling. Between the two held wheels it carries its capacity and holds both.
	_set_spin(drive, [0.0, 0.0, 36.0, 31.0], [0.001, 0.001, 0.002, 0.002])
	_set_tcs(drive, [0.0, 0.0, 4.0, 4.0], [0.0, 0.0, 34.0, 30.0])
	drive._couple_differentials(spec.ground_drive, input, 1000.0)
	assert_float(w[2].omega).is_equal_approx(34.0, 1e-9)
	assert_float(w[3].omega).is_equal_approx(30.0, 1e-9)
	assert_bool(w[3].tcs_active).is_true()


## Each wheel's latched brake, as if it had just ticked (FL, FR, RL, RR): the spin it can take off.
func _set_brakes(drive: WheelDrive, brake_spins: Array) -> void:
	for i in drive.wheels.size():
		drive.wheels[i].brake_spin = brake_spins[i]
		drive.wheels[i].abs_floor = 0.0


func test_an_awd_body_holds_on_its_brake_total_through_the_centre() -> void:
	# The rears' own brakes cannot stop their drive (1.0 rad/s of spin against 0.8), the fronts'
	# have spare: the Torsen centre carries the rears' 2 x 200 N·m forward, under its 1000 N·m at
	# 4000 N·m in, and every wheel is held.
	var spec := _bench_spec(1600.0)
	spec.ground_drive.driven_front = true
	spec.ground_drive.centre_diff_bias = 3.0
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [0.5, 0.5, 1.0, 1.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [3.0, 3.0, 0.8, 0.8])
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	for w in drive.wheels:
		assert_float(w.omega).is_equal_approx(0.0, 1e-12)
	# The fronts hold with spare; the rears' brakes sit at their limit, the centre carrying only
	# what holding them takes.
	assert_bool(drive.wheels[0]._spin_held).is_true()
	assert_bool(drive.wheels[1]._spin_held).is_true()
	# The torque each wheel's brake now holds besides its own drive: what the patch hold reads.
	assert_float(drive.wheels[2].coupled_torque).is_equal_approx(-200.0, 1e-6)
	assert_float(drive.wheels[0].coupled_torque).is_equal_approx(200.0, 1e-6)
	# An open centre carries nothing: the rears turn against their brakes.
	spec.ground_drive.centre_diff_bias = 1.0
	_set_spin(drive, [0.5, 0.5, 1.0, 1.0], [0.001, 0.001, 0.001, 0.001])
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	assert_float(drive.wheels[2].omega).is_equal_approx(0.2, 1e-9)
	assert_bool(drive.wheels[2]._spin_held).is_false()
	assert_float(drive.wheels[0].omega).is_equal(0.0)


func test_the_mfwd_shaft_brakes_the_fronts_on_the_rear_brakes() -> void:
	# The tractor's pedal: rear-only brakes, the fronts tied on by the rigid shaft. The fronts'
	# drive goes through the shaft into the rears' spare brake and the whole body holds.
	var spec := _mfwd_spec()
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	input.fwd_drive = true
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [0.6, 0.6, 0.6, 0.6], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 2.0, 2.0])
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	var w := drive.wheels
	assert_float(w[2].omega).is_equal(0.0)
	assert_float(w[3].omega).is_equal(0.0)
	assert_bool(w[2]._spin_held).is_true()
	assert_float(w[0].omega + w[1].omega).is_equal_approx(0.0, 1e-9)
	# The brakes under the drive in total (2 x 0.5 against 4 x 0.6): the shaft turns, the rears'
	# brakes slipping, the axle means still tied.
	_set_spin(drive, [0.6, 0.6, 0.6, 0.6], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.5, 0.5])
	drive._couple_differentials(spec.ground_drive, input, 4000.0)
	assert_float(w[2].omega).is_equal_approx(0.35, 1e-9)
	assert_float((w[0].omega + w[1].omega) * 0.5).is_equal_approx(0.35, 1e-9)
	assert_bool(w[2]._spin_held).is_false()


## The pawl in, as `WheelDrive.tick` sets it: each driven wheel takes `rating`, and the pass locks
## them all to the case at `rating` times their count.
func _couple_in_park(drive: WheelDrive, gd: GroundDriveSpec, input: VehicleInput,
		rating: float) -> void:
	var locked := PackedInt32Array()
	for i in drive.wheels.size():
		drive.wheels[i].lock_torque = rating if drive.wheels[i].driven else 0.0
		if drive.wheels[i].driven:
			locked.append(i)
	drive._couple_differentials(gd, input, 0.0, locked, rating * locked.size())


func test_the_pawl_locks_the_driveline_and_holds_every_driven_wheel() -> void:
	# A parked RWD body rolling back a touch on its open rear axle: the pawl stops both rears and
	# they hold, its torque kept out of what the brake-and-lock hold is measured against.
	var spec := _bench_spec(1500.0)
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [-0.3, -0.3, -0.2, -0.2], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	_couple_in_park(drive, spec.ground_drive, input, 3000.0)
	var w := drive.wheels
	for i in [2, 3]:
		assert_float(w[i].omega).is_equal(0.0)
		assert_bool(w[i]._spin_held).is_true()
		assert_float(w[i].coupled_torque).is_equal_approx(0.0, 1e-9)
	# The undriven fronts roll on, unheld.
	assert_float(w[0].omega).is_equal(-0.3)
	assert_bool(w[0]._spin_held).is_false()


func test_an_open_axle_counter_rotates_under_the_pawl() -> void:
	# One rear on ice spun back hard, its partner gripping: the pawl stops their mean, never each
	# wheel, so they turn against each other and neither holds, as a real one in P lets go.
	var spec := _bench_spec(1500.0)
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [0.0, 0.0, -4.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	_couple_in_park(drive, spec.ground_drive, input, 3000.0)
	var w := drive.wheels
	assert_float(w[2].omega + w[3].omega).is_equal_approx(0.0, 1e-9)
	assert_float(w[2].omega).is_equal_approx(-2.0, 1e-9)
	assert_bool(w[2]._spin_held).is_false()
	assert_bool(w[3]._spin_held).is_false()
	# The diff lock makes the pair one shaft: the pawl holds them both.
	spec.ground_drive.rear_diff_lockable = true
	input.diff_lock = true
	_set_spin(drive, [0.0, 0.0, -4.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_couple_in_park(drive, spec.ground_drive, input, 3000.0)
	assert_bool(w[2]._spin_held).is_true()
	assert_bool(w[3]._spin_held).is_true()


func test_an_awd_body_holds_on_the_pawl_through_its_centre() -> void:
	# Torsen centre: the lock leaves the axles counter-rotating (+-0.03 rad/s), the centre ties
	# them back and moves their mean off zero by what their compliances differ (the one pass,
	# ~0.007 rad/s here), under LOCK_STUCK_SPIN: the whole driveline holds.
	var spec := _bench_spec(1600.0)
	spec.ground_drive.driven_front = true
	spec.ground_drive.centre_diff_bias = 3.0
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [-0.05, -0.05, -0.08, -0.08], [0.0008, 0.0008, 0.0005, 0.0005])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	_couple_in_park(drive, spec.ground_drive, input, 3000.0)
	for w in drive.wheels:
		assert_float(w.omega).is_equal(0.0)
		assert_bool(w._spin_held).is_true()


func test_a_pawl_under_its_load_holds_nothing() -> void:
	# A rating far under what stopping the shaft takes: the lock slips, no wheel is held.
	var spec := _bench_spec(1500.0)
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	_set_spin(drive, [0.0, 0.0, -2.0, -2.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	_couple_in_park(drive, spec.ground_drive, input, 100.0)
	# 2 x 100 N·m through the shaft, 100 each: 0.1 rad/s back off each rear.
	assert_float(drive.wheels[2].omega).is_equal_approx(-1.9, 1e-9)
	assert_bool(drive.wheels[2]._spin_held).is_false()


# --- the crank, solved first in the WheelDrive pass ------------------------------------

## A rear-driven bench body whose engine drives its wheels: a car's crank (0.2 kg·m²) behind a
## 1.5x-peak clutch, on VehicleSpec's default curve and gearing.
func _crank_spec() -> VehicleSpec:
	var spec := _bench_spec(1500.0)
	spec.engine_inertia = 0.2
	spec.coupling = VehicleSpec.Coupling.CLUTCH
	return spec


## A Drivetrain on `spec` in D1, its crank at `crank_axle` rad/s through the gear, its coupling in
## `state`, and this tick's `process` already run against the driven wheels' `wheel_mean`.
func _crank_in_d1(spec: VehicleSpec, state: Drivetrain.CouplingState, crank_axle: float,
		wheel_mean: float, throttle: float) -> Drivetrain:
	var dt := Drivetrain.new(spec)
	dt.gear_byte = 1
	dt.coupling_state = state
	dt.rpm = crank_axle * Drivetrain.ratio_for_byte(spec, 1) * Drivetrain.RADS_TO_RPM
	dt.process(TICK, throttle, wheel_mean, wheel_mean * spec.ground_drive.wheel_radius, 1, false)
	return dt


func test_a_locked_crank_lands_on_the_compliance_weighted_mean_with_its_wheels() -> void:
	# Crank 20 rad/s through gear 1, the open rear pair 18 each: one rigid shaft, the crank's
	# reflected compliance against the pair's mean (`delta / (J G^2 eta)` driving).
	var spec := _crank_spec()
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := _crank_in_d1(spec, Drivetrain.CouplingState.LOCKED, 20.0, 18.0, 0.0)
	_set_spin(drive, [0.0, 0.0, 18.0, 18.0], [0.001, 0.001, 0.002, 0.002])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	drive._couple_differentials(spec.ground_drive, input, 0.0, PackedInt32Array(), 0.0, dt)
	var g := Drivetrain.ratio_for_byte(spec, 1)
	var c_crank := TICK / (spec.engine_inertia * g * g * spec.efficiency)
	var c_pair := (0.002 + 0.002) / 4.0
	var mean := (20.0 / c_crank + 18.0 / c_pair) / (1.0 / c_crank + 1.0 / c_pair)
	var w := drive.wheels
	assert_float(w[2].omega).is_equal_approx(mean, 1e-6)
	assert_float(w[3].omega).is_equal_approx(mean, 1e-6)
	assert_float(dt.rpm / Drivetrain.RADS_TO_RPM / g).is_equal_approx(mean, 1e-6)
	# Undriven fronts, untouched.
	assert_float(w[0].omega).is_equal(0.0)


func test_a_slipping_coupling_carries_only_its_capacity() -> void:
	# A weak coupling (0.1x peak) locked onto a wide spread: it carries its rating through the
	# ratio and the driveline loss, split over the open pair, and no more.
	var spec := _crank_spec()
	spec.clutch_reserve = 0.1
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := _crank_in_d1(spec, Drivetrain.CouplingState.LOCKED, 40.0, 0.0, 1.0)
	_set_spin(drive, [0.0, 0.0, 0.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	drive._couple_differentials(spec.ground_drive, input, 0.0, PackedInt32Array(), 0.0, dt)
	var g := Drivetrain.ratio_for_byte(spec, 1)
	var carried := Drivetrain.clutch_rating(spec) * g * spec.efficiency
	assert_float(drive.wheels[2].coupled_torque + drive.wheels[3].coupled_torque) \
			.is_equal_approx(carried, 1e-6)
	assert_float(drive.wheels[2].omega).is_equal_approx(carried / 2.0 * 0.001, 1e-9)


func test_a_lifted_driven_pair_spins_up_with_the_crank_through_the_ratio_squared() -> void:
	# Floored, locked, both driven wheels off the ground (no tyre: compliance delta / I_w): one tick
	# moves them `G eta T / (n I_w + eta J G^2)` per second, where the wheels' own inertia alone made
	# it `G eta T / (n I_w)`. The crank is what keeps a low gear from flashing a tyre.
	for j: float in [0.2, Drivetrain.MIN_ENGINE_INERTIA]:
		var spec := _crank_spec()
		spec.engine_inertia = j
		var gd := spec.ground_drive
		var drive := _drive_for(spec)
		var input := VehicleInput.new()
		drive.drive_omega(gd, input)
		var w0 := 30.0
		var g := Drivetrain.ratio_for_byte(spec, 1)
		var dt := _crank_in_d1(spec, Drivetrain.CouplingState.LOCKED, w0, w0, 1.0)
		var c_free := TICK / gd.wheel_inertia
		_set_spin(drive, [0.0, 0.0, w0, w0], [c_free, c_free, c_free, c_free])
		_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
		drive._couple_differentials(gd, input, 0.0, PackedInt32Array(), 0.0, dt)
		var torque := Drivetrain.engine_torque(spec, w0 * g * Drivetrain.RADS_TO_RPM)
		var expected := g * spec.efficiency * torque \
				/ (2.0 * gd.wheel_inertia + spec.efficiency * j * g * g)
		assert_float((drive.wheels[2].omega - w0) / TICK).is_equal_approx(expected, 1e-6 * expected)
		if j < 0.01:
			# J -> 0 is the wheels' own inertia alone.
			var bare := g * spec.efficiency * torque / (2.0 * gd.wheel_inertia)
			assert_float((drive.wheels[2].omega - w0) / TICK).is_equal_approx(bare, 0.02 * bare)


func test_in_park_the_pawl_holds_and_the_crank_revs_free() -> void:
	var spec := _crank_spec()
	spec.ground_drive.park_pawl_torque = 3000.0
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := Drivetrain.new(spec)
	var idle_rpm := dt.rpm
	dt.process(TICK, 1.0, 0.0, 0.0, Drivetrain.GEAR_P, false)
	_set_spin(drive, [-0.3, -0.3, -0.2, -0.2], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	var locked := PackedInt32Array([2, 3])
	for i in locked:
		drive.wheels[i].lock_torque = 3000.0
	drive._couple_differentials(spec.ground_drive, input, 0.0, locked, 6000.0, dt)
	for i in locked:
		assert_float(drive.wheels[i].omega).is_equal(0.0)
		assert_bool(drive.wheels[i]._spin_held).is_true()
	# The pedal revs the crank, which drives nothing in P.
	assert_float(dt.rpm).is_greater(idle_rpm)


func test_a_converter_settles_its_crank_and_wheels_on_its_law() -> void:
	# Floored behind a converter, crank at 20 rad/s through gear 1 against a resting open pair: the
	# impeller torque is the law at the two sides' END speeds, and the pair takes it through the
	# ratio and the driveline loss, half each.
	var spec := _crank_spec()
	spec.coupling = VehicleSpec.Coupling.CONVERTER
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := _crank_in_d1(spec, Drivetrain.CouplingState.SLIPPING, 20.0, 0.0, 1.0)
	assert_bool(dt.converting).is_true()
	_set_spin(drive, [0.0, 0.0, 0.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	drive._couple_differentials(spec.ground_drive, input, 0.0, PackedInt32Array(), 0.0, dt)
	var g := Drivetrain.ratio_for_byte(spec, 1)
	var w := drive.wheels
	var axle := w[2].coupled_torque + w[3].coupled_torque
	assert_float(axle).is_equal_approx(dt.coupling_torque * g * spec.efficiency, 1e-6)
	assert_float(w[2].omega).is_equal_approx(axle / 2.0 * 0.001, 1e-9)
	var turbine := (w[2].omega + w[3].omega) / 2.0 * g
	var coef := TorqueConverter.capacity_coefficient(spec)
	assert_float(dt.coupling_torque).is_equal_approx(TorqueConverter.impeller_torque(coef,
			dt.rpm / Drivetrain.RADS_TO_RPM, turbine), 1e-3)
	assert_float(dt.coupling_torque).is_greater(0.0)


func test_a_tc_held_wheel_behind_a_converter_stays_at_its_ceiling() -> void:
	# The same launch with RL's traction control holding it at 0.5 rad/s: it settles there, and the
	# converter's law reads the held wheel, so the crank is loaded by what the pair turns at.
	var spec := _crank_spec()
	spec.coupling = VehicleSpec.Coupling.CONVERTER
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := _crank_in_d1(spec, Drivetrain.CouplingState.SLIPPING, 20.0, 0.0, 1.0)
	_set_spin(drive, [0.0, 0.0, 0.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [0.0, 0.0, 0.0, 0.0])
	_set_tcs(drive, [0.0, 0.0, 4.0, 0.0], [0.0, 0.0, 0.5, 0.0])
	drive._couple_differentials(spec.ground_drive, input, 0.0, PackedInt32Array(), 0.0, dt)
	var w := drive.wheels
	assert_float(w[2].omega).is_equal_approx(0.5, 1e-9)
	assert_bool(w[2].tcs_active).is_true()
	assert_float(w[3].omega).is_greater(0.5)
	var g := Drivetrain.ratio_for_byte(spec, 1)
	var turbine := (w[2].omega + w[3].omega) / 2.0 * g
	var coef := TorqueConverter.capacity_coefficient(spec)
	assert_float(dt.coupling_torque).is_equal_approx(TorqueConverter.impeller_torque(coef,
			dt.rpm / Drivetrain.RADS_TO_RPM, turbine), 1e-3)


## The axle torque a converter in D1 passes `drive`'s braked, stopped wheels this tick, its crank at
## `crank_axle` rad/s through the gear with `throttle`: what the hill hold weighs next tick.
func _held_converter_drive(spec: VehicleSpec, drive: WheelDrive, input: VehicleInput,
		crank_axle: float, throttle: float) -> Drivetrain:
	var dt := _crank_in_d1(spec, Drivetrain.CouplingState.SLIPPING, crank_axle, 0.0, throttle)
	_set_spin(drive, [0.0, 0.0, 0.0, 0.0], [0.001, 0.001, 0.001, 0.001])
	_set_brakes(drive, [10.0, 10.0, 10.0, 10.0])
	drive._couple_differentials(spec.ground_drive, input, 0.0, PackedInt32Array(), 0.0, dt)
	return dt


func test_hill_start_assist_holds_until_the_converter_carries_the_grade() -> void:
	# Released on a grade its idle creep cannot hold but its floored drive can: the held application
	# stays on (`foot_pedal`, what a trailer is sent too) while the converter creeps, and lets go the
	# tick after the floored drive passes the grade's pull.
	var spec := _crank_spec()
	spec.coupling = VehicleSpec.Coupling.CONVERTER
	var gd := spec.ground_drive
	gd.hill_hold = HillHold.Kind.ASSIST
	gd.hill_hold_s = 1.0
	var drive := _drive_for(spec)
	var body: RigidBody3D = auto_free(RigidBody3D.new())
	add_child(body)
	var input := VehicleInput.new()
	drive.drive_omega(gd, input)
	var g := Drivetrain.ratio_for_byte(spec, 1)
	var idle_axle := spec.idle_rpm / Drivetrain.RADS_TO_RPM / g
	_held_converter_drive(spec, drive, input, idle_axle, 0.0)
	var creep := drive._drive_torque
	var floored_dt := _held_converter_drive(spec, drive, input, 20.0, 1.0)
	var floored := drive._drive_torque
	assert_float(creep).is_greater(0.0)
	assert_float(floored).is_greater(2.0 * creep)
	# The grade whose pull sits halfway between: the ground rises toward the body's forward (-Z).
	var gravity := body.get_gravity().length()
	var sin_a := (creep + floored) * 0.5 / (gravity * spec.mass * gd.wheel_radius)
	var normal := Vector3(0.0, sqrt(1.0 - sin_a * sin_a), sin_a)
	for w in drive.wheels:
		w.in_contact = true
		w.contact_normal = normal
	var creep_dt := _held_converter_drive(spec, drive, input, idle_axle, 0.0)
	input.brake = 0.6
	drive.hold_step(body, gd, input, creep_dt, 0.0, TICK)
	input.brake = 0.0
	drive.hold_step(body, gd, input, creep_dt, 0.0, TICK)
	assert_bool(drive.hill_holding).is_true()
	assert_float(drive.foot_pedal(input)).is_equal_approx(0.6, 1e-6)
	# Floored: the converter's drive passes the pull, and the next tick's hold lets go.
	input.throttle = 1.0
	_held_converter_drive(spec, drive, input, 20.0, 1.0)
	drive.hold_step(body, gd, input, floored_dt, 0.0, TICK)
	assert_bool(drive.hill_holding).is_false()
	assert_float(drive.foot_pedal(input)).is_equal(0.0)


func test_the_wheels_report_abs_and_overrun_slip_to_the_controller() -> void:
	var spec := _crank_spec()
	spec.ground_drive.tcs_equipped = true
	var drive := _drive_for(spec)
	var input := VehicleInput.new()
	drive.drive_omega(spec.ground_drive, input)
	var dt := Drivetrain.new(spec)
	dt.gear_byte = 1
	drive.wheels[2].abs_active = true
	drive._report_to_controller(spec.ground_drive, input, dt)
	assert_bool(dt.abs_release).is_true()
	drive.wheels[2].abs_active = false
	# Engine braking dragging the driven pair past the floor: drag-torque control, while TC is on.
	dt.overrun = true
	drive.wheels[2].long_slip = -0.3
	drive.wheels[3].long_slip = -0.3
	drive._report_to_controller(spec.ground_drive, input, dt)
	assert_bool(dt.abs_release).is_false()
	assert_bool(dt.drag_control).is_true()
	input.tcs_off = true
	drive._report_to_controller(spec.ground_drive, input, dt)
	assert_bool(dt.drag_control).is_false()


# --- visual spin: the drawn tread moves at the contact's surface speed ------------

func test_a_bigger_visual_tyre_turns_slower_to_show_the_same_tread_speed() -> void:
	var r := 0.36
	var spin := 10.0 / r  # rolling at 10 m/s on the physics radius
	# Same radius: the physics spin unchanged.
	assert_float(WheelScript.visual_spin_step(spin, TICK, r, r)).is_equal_approx(spin * TICK, 1e-6)
	# The tractor's 0.66 m rear: its drawn tread covers exactly the ground the body does.
	var step := WheelScript.visual_spin_step(spin, TICK, r, 0.66)
	assert_float(step * 0.66).is_equal_approx(10.0 * TICK, 1e-6)
	# Its 0.44 m front turns 0.66 / 0.44 = 1.5x the rear's rate.
	assert_float(WheelScript.visual_spin_step(spin, TICK, r, 0.44) / step).is_equal_approx(1.5, 1e-5)
	# No visual radius declared: drawn at the physics radius.
	assert_float(WheelScript.visual_spin_step(spin, TICK, r, 0.0)).is_equal_approx(spin * TICK, 1e-6)
