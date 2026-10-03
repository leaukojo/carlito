extends GdUnitTestSuite
## KeyShaper: an on/off key becomes a hand on a wheel and a foot on a pedal. Pure statics, plus the
## router wiring (keyboard steer shaped, touch stick not, key and touch pedals shaped, gamepad and
## bridge never).

const Shaper := preload("res://src/input/key_shaper.gd")
const RouterScript := preload("res://src/input/input_router.gd")
const BridgeSourceScript := preload("res://src/input/sources/bridge_source.gd")
const LocalSourceScript := preload("res://src/input/sources/local_source.gd")
const PadSourceScript := preload("res://src/input/sources/pad_source.gd")

const TICK := 1.0 / 60.0


## Ticks of steer_step from `from` until the shaped value reaches `target` (capped).
static func _ticks_to(from: float, target: float, speed: float) -> int:
	var s := from
	var n := 0
	while not is_equal_approx(s, target) and n < 100000:
		s = Shaper.steer_step(s, target, speed, TICK)
		n += 1
	return n


# --- steer ---------------------------------------------------------------------------

func test_the_out_rate_falls_with_road_speed() -> void:
	var prev := INF
	for v: float in [0.0, 2.0, 5.0, 10.0, 15.0, 25.0, 35.0]:
		var rate := Shaper.steer_out_rate(v)
		assert_float(rate).override_failure_message("out rate rose at %.0f m/s" % v).is_less(prev)
		prev = rate
	# Halved at STEER_V0, and a quarter of that again at twice it: the 1 / v^2 tail.
	assert_float(Shaper.steer_out_rate(Shaper.STEER_V0)) \
			.is_equal_approx(Shaper.STEER_OUT_RATE * 0.5, 1e-6)
	assert_float(Shaper.steer_out_rate(-Shaper.STEER_V0)) \
			.is_equal_approx(Shaper.STEER_OUT_RATE * 0.5, 1e-6)


func test_letting_go_straightens_faster_than_the_wheel_went_out() -> void:
	for v: float in [0.0, 8.0, 25.0]:
		var out_ticks := _ticks_to(0.0, 0.5, v)
		var back_ticks := _ticks_to(0.5, 0.0, v)
		assert_int(back_ticks).override_failure_message("at %.0f m/s" % v).is_less(out_ticks)
	# Never slower than the floor, even where the out rate has nearly vanished.
	assert_float(Shaper.steer_return_rate(40.0)).is_equal(Shaper.STEER_RETURN_MIN)


func test_a_held_key_reaches_full_lock_and_never_overshoots() -> void:
	var s := 0.0
	for _i in 600:
		s = Shaper.steer_step(s, 1.0, 0.0, TICK)
		assert_float(s).is_less_equal(1.0)
	assert_float(s).is_equal(1.0)
	# From the other side too, and toward a target nearer the centre on the same side.
	s = 1.0
	for _i in 600:
		s = Shaper.steer_step(s, 0.3, 0.0, TICK)
		assert_float(s).is_greater_equal(0.3)
	assert_float(s).is_equal(0.3)


func test_a_reversal_returns_at_the_return_rate_then_goes_out_past_centre() -> void:
	# One tick big enough to cross centre: the inward leg costs dist / return_rate, the rest goes out.
	var speed := 0.0
	var c := 0.1
	var dt := 0.2
	var crossed := Shaper.steer_step(c, -1.0, speed, dt)
	var left := dt - c / Shaper.steer_return_rate(speed)
	assert_float(crossed).is_equal_approx(-Shaper.steer_out_rate(speed) * left, 1e-6)
	# Within a tick, the opposite key only brings the wheel back toward centre.
	var small := Shaper.steer_step(0.5, -1.0, speed, TICK)
	assert_float(small).is_equal_approx(0.5 - Shaper.steer_return_rate(speed) * TICK, 1e-6)


func test_a_short_tap_at_speed_asks_for_a_little_lock() -> void:
	# The whole point: a quarter-second tap at motorway speed is a lane change, not a swerve.
	var s := 0.0
	for _i in 15:
		s = Shaper.steer_step(s, 1.0, 27.8, TICK)
	assert_float(s).is_less(0.05)
	# The same tap in a car park is a real turn of the wheel.
	var slow := 0.0
	for _i in 15:
		slow = Shaper.steer_step(slow, 1.0, 1.0, TICK)
	assert_float(slow).is_greater(0.15)


func test_no_time_no_change() -> void:
	assert_float(Shaper.steer_step(0.4, 1.0, 10.0, 0.0)).is_equal(0.4)
	assert_float(Shaper.steer_step(0.4, 0.4, 10.0, TICK)).is_equal(0.4)


# --- pedals --------------------------------------------------------------------------

func test_a_pedal_key_reaches_full_travel_in_its_apply_time() -> void:
	for apply_s: float in [Shaper.ACCEL_APPLY_S, Shaper.BRAKE_APPLY_S]:
		var p := 0.0
		var n := 0
		while p < 1.0 and n < 1000:
			p = Shaper.pedal_step(p, 1.0, apply_s, TICK)
			n += 1
		assert_float(float(n) * TICK).is_equal_approx(apply_s, TICK)


func test_a_released_pedal_comes_off_in_the_release_time() -> void:
	var p := 1.0
	var n := 0
	while p > 0.0 and n < 1000:
		p = Shaper.pedal_step(p, 0.0, Shaper.ACCEL_APPLY_S, TICK)
		n += 1
	assert_float(float(n) * TICK).is_equal_approx(Shaper.PEDAL_RELEASE_S, TICK)
	assert_float(Shaper.pedal_step(0.3, 0.3, Shaper.BRAKE_APPLY_S, TICK)).is_equal(0.3)


# --- softening (the KEY RESPONSE setting) ----------------------------------------------------

func test_zero_softening_passes_the_key_straight_through() -> void:
	assert_float(Shaper.steer_step(0.0, 1.0, 30.0, TICK, 0.0)).is_equal(1.0)
	assert_float(Shaper.steer_step(1.0, -1.0, 30.0, TICK, 0.0)).is_equal(-1.0)
	assert_float(Shaper.pedal_step(0.0, 1.0, Shaper.ACCEL_APPLY_S, TICK, 0.0)).is_equal(1.0)
	assert_float(Shaper.pedal_step(1.0, 0.0, Shaper.ACCEL_APPLY_S, TICK, 0.0)).is_equal(0.0)


func test_softening_scales_every_travel_time() -> void:
	# Half the softening = the full model run over twice the time.
	for v: float in [0.0, 12.0]:
		assert_float(Shaper.steer_step(0.0, 1.0, v, TICK, 0.5)) \
				.is_equal_approx(Shaper.steer_step(0.0, 1.0, v, 2.0 * TICK), 1e-6)
		assert_float(Shaper.steer_step(0.6, 0.0, v, TICK, 0.5)) \
				.is_equal_approx(Shaper.steer_step(0.6, 0.0, v, 2.0 * TICK), 1e-6)
	assert_float(Shaper.pedal_step(0.0, 1.0, Shaper.BRAKE_APPLY_S, TICK, 0.5)) \
			.is_equal_approx(Shaper.pedal_step(0.0, 1.0, Shaper.BRAKE_APPLY_S, 2.0 * TICK), 1e-6)


func test_the_softening_steps_cycle_through_raw_to_the_full_model() -> void:
	assert_int(Shaper.SOFTENING_LABELS.size()).is_equal(Shaper.SOFTENING_STEPS.size())
	assert_float(Shaper.SOFTENING_STEPS[0]).is_equal(0.0)
	assert_float(Shaper.SOFTENING_STEPS[-1]).is_equal(1.0)
	assert_bool(Shaper.SOFTENING_STEPS.has(Shaper.DEFAULT_SOFTENING)).is_true()
	var a: float = Shaper.SOFTENING_STEPS[0]
	for i in Shaper.SOFTENING_STEPS.size():
		assert_str(Shaper.softening_label(a)).is_equal(Shaper.SOFTENING_LABELS[i])
		a = Shaper.next_softening(a)
	assert_float(a).is_equal(Shaper.SOFTENING_STEPS[0])


func test_the_router_applies_its_softening_to_the_keys() -> void:
	var router: Node = auto_free(RouterScript.new())
	assert_float(router.key_softening()).is_equal(Shaper.DEFAULT_SOFTENING)
	router.set_key_softening(0.0)
	_key(KEY_D, true)
	router._physics_process(TICK)
	var steer: float = router.get_vehicle_input().steer
	_key(KEY_D, false)
	assert_float(steer).is_equal(1.0)


# --- the router wiring -------------------------------------------------------------------

## A router running the full hand-and-foot model, whose timings these asserts read.
func _full_router() -> Node:
	var router: Node = auto_free(RouterScript.new())
	router.set_key_softening(1.0)
	return router


## A touch stand-in holding GAS and the stick hard right.
class _GasAndStickTouch extends RefCounted:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"accel": 1.0, &"steer": 0.6}


class _LiveBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"drive_sourced": true, &"accel": 1.0, &"brake": 1.0,
				&"steer": 1.0, &"gear": 1, &"key": RouterScript.KEY_IGNITION}


func test_local_pedals_ramp_and_the_touch_stick_passes_straight_through() -> void:
	var router := _full_router()
	router.set_touch_source(_GasAndStickTouch.new())
	router._physics_process(TICK)
	var first: VehicleInput = router.get_vehicle_input()
	assert_float(first.throttle).is_equal_approx(TICK / Shaper.ACCEL_APPLY_S, 1e-6)
	# Analog: the stick is not a key, so it is not shaped.
	assert_float(first.steer).is_equal_approx(0.6, 1e-6)
	for _i in roundi(Shaper.ACCEL_APPLY_S / TICK):
		router._physics_process(TICK)
	assert_float(router.get_vehicle_input().throttle).is_equal(1.0)


## Hold or release a physical key the way the OS does. LocalSource reads keys, not the action, so
## `Input.action_press` would press nothing it sees.
static func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func test_the_keyboard_steer_is_shaped() -> void:
	var router := _full_router()
	_key(KEY_D, true)
	router._physics_process(TICK)
	var steer: float = router.get_vehicle_input().steer
	_key(KEY_D, false)
	assert_float(steer).is_equal_approx(Shaper.steer_out_rate(0.0) * TICK, 1e-6)


## A body flying at 40 m/s whose steer turns no road wheel (a plane in the air).
class _FlyingBody extends Node3D:
	func get_speed() -> float:
		return 40.0
	func key_steer_speed() -> float:
		return 0.0
	func get_gear_byte() -> int:
		return RouterScript.GEAR_D1
	func key_pedals_are_a_stick() -> bool:
		return false


## A hovering body whose pedal keys are one stick axis (the drone's pitch).
class _StickBody extends Node3D:
	func get_speed() -> float:
		return 0.0
	func key_steer_speed() -> float:
		return 0.0
	func get_gear_byte() -> int:
		return RouterScript.GEAR_N
	func key_pedals_are_a_stick() -> bool:
		return true


func test_stick_pedals_ramp_both_ways_alike() -> void:
	# S at a standstill reverses: throttle = -brake, ramped at the accel rate, not the brake's.
	var router := _full_router()
	router.register_vehicle(auto_free(_StickBody.new()))
	_key(KEY_S, true)
	router._physics_process(TICK)
	var throttle: float = router.get_vehicle_input().throttle
	_key(KEY_S, false)
	assert_float(throttle).is_equal_approx(-TICK / Shaper.ACCEL_APPLY_S, 1e-6)


func test_the_steer_slows_with_the_speed_the_body_steers_wheels_at() -> void:
	# A plane at cruise banks with the key at its standstill rate: the 1 / v^2 slow-down is a wheel
	# angle's law, so the router reads key_steer_speed, not road speed.
	var router := _full_router()
	router.register_vehicle(auto_free(_FlyingBody.new()))
	_key(KEY_D, true)
	router._physics_process(TICK)
	var steer: float = router.get_vehicle_input().steer
	_key(KEY_D, false)
	assert_float(steer).is_equal_approx(Shaper.steer_out_rate(0.0) * TICK, 1e-6)


func test_the_bridge_is_never_shaped() -> void:
	var router: Node = auto_free(RouterScript.new())
	router._bridge_source = _LiveBridge.new()
	router._physics_process(TICK)
	var out: VehicleInput = router.get_vehicle_input()
	assert_float(out.throttle).is_equal(1.0)
	assert_float(out.brake).is_equal(1.0)
	assert_float(out.steer).is_equal(1.0)


func test_shaping_starts_over_when_the_bridge_hands_back_and_on_a_new_body() -> void:
	var router: Node = auto_free(RouterScript.new())
	router.set_touch_source(_GasAndStickTouch.new())
	for _i in 30:
		router._physics_process(TICK)
	assert_float(router._pedal_accel).is_equal(1.0)
	router._bridge_source = _LiveBridge.new()
	router._physics_process(TICK)
	assert_float(router._pedal_accel).is_equal(0.0)
	router._bridge_source = BridgeSourceScript.new()
	for _i in 30:
		router._physics_process(TICK)
	router.register_vehicle(null)
	assert_float(router._pedal_accel).is_equal(0.0)
	assert_float(router._key_steer).is_equal(0.0)


# --- the gamepad ---------------------------------------------------------------------------

## A pad stand-in holding whatever the test sets.
class _StubPad extends PadSourceScript:
	var vals: Dictionary[StringName, Variant] = {}
	func poll() -> Dictionary[StringName, Variant]:
		return vals


## A car at 30 m/s, where a held key takes ~11 s to full lock.
class _FastCar extends Node3D:
	func get_speed() -> float:
		return 30.0
	func key_steer_speed() -> float:
		return 30.0
	func get_gear_byte() -> int:
		return RouterScript.GEAR_D1
	func key_pedals_are_a_stick() -> bool:
		return false


func test_the_pad_stick_and_trigger_pass_straight_through() -> void:
	var router: Node = auto_free(RouterScript.new())
	router.register_vehicle(auto_free(_FastCar.new()))
	var pad := _StubPad.new()
	pad.vals = {&"steer": 1.0, &"accel": 1.0}
	router._pad_source = pad
	router._physics_process(TICK)
	var out: VehicleInput = router.get_vehicle_input()
	assert_float(out.steer).is_equal(1.0)
	assert_float(out.throttle).is_equal(1.0)


func test_key_and_pad_merge_like_any_two_local_sources() -> void:
	var router := _full_router()
	router.register_vehicle(auto_free(_FastCar.new()))
	var pad := _StubPad.new()
	pad.vals = {&"steer": -0.5, &"accel": 0.3}
	router._pad_source = pad
	_key(KEY_D, true)
	router._physics_process(TICK)
	var out: VehicleInput = router.get_vehicle_input()
	_key(KEY_D, false)
	# Steer sums (the key's shaped share plus the stick); the pedal takes the stronger request.
	assert_float(out.steer).is_equal_approx(Shaper.steer_out_rate(30.0) * TICK - 0.5, 1e-6)
	assert_float(out.throttle).is_equal_approx(0.3, 1e-6)


func test_a_pad_axis_reads_like_the_engines_action_strength() -> void:
	# Bound direction only, zero inside the deadzone, rescaled from its edge.
	assert_float(PadSourceScript.axis_strength(-0.8, 1.0, 0.2)).is_equal(0.0)
	assert_float(PadSourceScript.axis_strength(0.0, 1.0, 0.2)).is_equal(0.0)
	assert_float(PadSourceScript.axis_strength(0.15, 1.0, 0.2)).is_equal(0.0)
	assert_float(PadSourceScript.axis_strength(0.6, 1.0, 0.2)).is_equal_approx(0.5, 1e-5)
	assert_float(PadSourceScript.axis_strength(-0.6, -1.0, 0.2)).is_equal_approx(0.5, 1e-5)
	assert_float(PadSourceScript.axis_strength(1.0, 1.0, 0.2)).is_equal(1.0)
	assert_float(PadSourceScript.axis_strength(1.0, 1.0, 1.0)).is_equal(1.0)


func test_the_keyboard_source_reads_keys_not_the_action() -> void:
	# action_press holds the action with no key down, which is what a pad axis does to it.
	Input.action_press("steer_right")
	var action := Input.get_action_strength("steer_right")
	var key := LocalSourceScript.key_strength(&"steer_right")
	Input.action_release("steer_right")
	assert_float(action).is_equal(1.0)
	assert_float(key).is_equal(0.0)
	_key(KEY_D, true)
	key = LocalSourceScript.key_strength(&"steer_right")
	_key(KEY_D, false)
	assert_float(key).is_equal(1.0)
