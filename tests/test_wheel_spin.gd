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


# --- brakes are unchanged -----------------------------------------------------

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
	# The real path: TruckVehicle writes `mass = spec.mass + payload` and calls
	# set_corner_mass_from beside it. Pinned on the shipped spec so a payload change is visible.
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
