extends GdUnitTestSuite
## Drone cargo hook: latch law, airframe mass. Pure statics, no physics body.

const P := preload("res://src/vehicles/drone/drone_payload.gd")

# --- the latch ----------------------------------------------------------------

func test_the_latch_closes_only_with_something_under_the_hook() -> void:
	assert_bool(P.latched(true, false, false)).is_false()
	assert_bool(P.latched(true, false, true)).is_true()


func test_a_captured_payload_stays_captured_once_it_is_off_the_ground() -> void:
	# A crate riding the hook no longer sits under the capture ray, so `prev` is what holds it:
	# without this the load would drop itself the instant it left the pad.
	assert_bool(P.latched(true, true, false)).is_true()


func test_release_needs_nothing_at_all() -> void:
	# The asymmetry is the model. Closing needs a payload; opening needs no condition and no
	# timer, because the failure a real cargo hook must never have is a load it cannot drop.
	assert_bool(P.latched(false, true, true)).is_false()
	assert_bool(P.latched(false, true, false)).is_false()
	assert_bool(P.latched(false, false, false)).is_false()

# --- the mass -----------------------------------------------------------------

func test_carried_mass_adds_the_payload_and_an_open_hook_adds_nothing() -> void:
	assert_float(P.carried_mass(5.0, 0.0)).is_equal(5.0)
	assert_float(P.carried_mass(5.0, 2.0)).is_equal(7.0)


func test_carried_mass_clamps_at_the_declared_ceiling() -> void:
	# Not a strength model — the point past which the airframe cannot hold a hover, so a heavier
	# crate is refused as MASS rather than making the aircraft unflyable.
	assert_float(P.carried_mass(5.0, 99.0)).is_equal(5.0 + P.MAX_PAYLOAD_KG)
	# ...and a negative payload can never make the craft lighter than its own airframe.
	assert_float(P.carried_mass(5.0, -3.0)).is_equal(5.0)


func test_the_centre_of_mass_moves_toward_the_hook_and_never_past_it() -> void:
	var com := Vector3(0.0, 0.05, 0.0)
	var hook := Vector3(0.0, -0.1, 0.0)
	# An open hook leaves the airframe's own centre of mass exactly where it was.
	assert_vector(P.carried_com(com, hook, 5.0, 0.0)).is_equal(com)
	# A load pulls it DOWN toward the hook — which is why a slung craft is steadier in roll.
	var loaded := P.carried_com(com, hook, 5.0, 2.0)
	assert_float(loaded.y).is_less(com.y)
	assert_float(loaded.y).is_greater(hook.y)
	# Mass-weighted, not a lerp with a taste constant: 5 kg at +0.05 and 2 kg at -0.1 is
	# (5*0.05 + 2*-0.1) / 7 = 0.0071...
	assert_float(loaded.y).is_equal_approx((5.0 * 0.05 + 2.0 * -0.1) / 7.0, 1e-5)


func test_a_massless_airframe_keeps_its_own_centre_of_mass() -> void:
	# Degenerate rather than expected, but it must not divide by zero and hand the body a NaN
	# centre of mass — which Godot accepts and then flies apart on.
	assert_vector(P.carried_com(Vector3.UP, Vector3.DOWN, 0.0, 0.0)).is_equal(Vector3.UP)

# --- what the hook reports ----------------------------------------------------

func test_payload_weight_is_a_force_in_newton() -> void:
	# uavcan.equipment.hardpoint.Status.payload_weight is specified in NEWTON, not kilogram: a
	# latch measures the force on itself. 2 kg at 9.8 is 19.6 N.
	assert_float(P.payload_weight_n(2.0, 9.8)).is_equal_approx(19.6, 1e-4)
	# An open hook reads a true zero, which is what an unloaded load cell reports.
	assert_float(P.payload_weight_n(0.0, 9.8)).is_equal(0.0)


func test_payload_weight_honours_the_same_ceiling_the_mass_does() -> void:
	# The published force and the mass really on the body must not be able to disagree, or the
	# bus would report a load the aircraft is not carrying.
	assert_float(P.payload_weight_n(99.0, 10.0)).is_equal(P.MAX_PAYLOAD_KG * 10.0)
