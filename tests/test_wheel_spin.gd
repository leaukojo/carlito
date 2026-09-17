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
