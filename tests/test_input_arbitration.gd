extends GdUnitTestSuite
## InputRouter local arbitration rules: key gating,
## brake-never-throttle, and the local S = brake-then-reverse scheme.
## Exercises the pure static arbitrate_local — no autoload lifecycle needed.

const RouterScript := preload("res://src/input/input_router.gd")
const BridgeSourceScript := preload("res://src/input/sources/bridge_source.gd")
const BodyScript := preload("res://src/vehicles/truck/refuse_body.gd")

const GEAR_N := 0x00
const GEAR_D1 := 0x01
const GEAR_R := 0xFF



## The raw-intent wire is `Dictionary[StringName, Variant]`, and an inline dictionary literal is
## untyped — GDScript rejects it at the call rather than converting. This wraps the small literals
## written inline below; the multi-key ones are declared with their type instead.
static func _intent(d: Dictionary) -> Dictionary[StringName, Variant]:
	var out: Dictionary[StringName, Variant] = {}
	for k: StringName in d:
		out[k] = d[k]
	return out


func _raw(accel := 0.0, brake_reverse := 0.0, steer := 0.0, handbrake := 0.0) -> Dictionary:
	return {
		"accel": accel, "brake_reverse": brake_reverse,
		"steer": steer, "handbrake": handbrake,
	}


func test_throttle_zero_unless_key_ignition() -> void:
	for key in [RouterScript.KEY_LOCK, RouterScript.KEY_ON]:
		var out: VehicleInput = RouterScript.arbitrate_local(
				_raw(1.0), 0.0, GEAR_D1, key)
		assert_float(out.throttle).is_equal(0.0)
	var ignition: VehicleInput = RouterScript.arbitrate_local(
			_raw(1.0), 0.0, GEAR_D1, RouterScript.KEY_IGNITION)
	assert_float(ignition.throttle).is_equal(1.0)


func test_brake_never_produces_throttle_while_moving() -> void:
	var out: VehicleInput = RouterScript.arbitrate_local(
			_raw(0.0, 1.0), 15.0, GEAR_D1)
	assert_float(out.throttle).is_equal(0.0)
	assert_float(out.brake).is_equal(1.0)
	assert_int(out.gear_request).is_equal(GEAR_D1)


func test_full_accel_plus_full_brake_pass_through() -> void:
	# §6: stopping is the brake > accel force hierarchy's job (in the spec), not
	# the router's — both pedals pass through untouched.
	var out: VehicleInput = RouterScript.arbitrate_local(
			_raw(1.0, 1.0), 15.0, GEAR_D1)
	assert_float(out.throttle).is_equal(1.0)
	assert_float(out.brake).is_equal(1.0)


func test_reverse_engages_at_standstill_only() -> void:
	var rolling: VehicleInput = RouterScript.arbitrate_local(
			_raw(0.0, 1.0), 10.0, GEAR_D1)
	assert_int(rolling.gear_request).is_equal(GEAR_D1)
	assert_float(rolling.throttle).is_equal(0.0)
	for gear in [GEAR_N, GEAR_D1]:
		var stopped: VehicleInput = RouterScript.arbitrate_local(
				_raw(0.0, 1.0), 0.1, gear)
		assert_int(stopped.gear_request).is_equal(GEAR_R)
		assert_float(stopped.throttle).is_equal(-1.0)
		assert_float(stopped.brake).is_equal(0.0)


func test_accel_while_reversing_brakes_then_reengages_drive() -> void:
	var rolling: VehicleInput = RouterScript.arbitrate_local(
			_raw(1.0, 0.0), -3.0, GEAR_R)
	assert_int(rolling.gear_request).is_equal(GEAR_R)
	assert_float(rolling.throttle).is_equal(0.0)
	assert_float(rolling.brake).is_equal(1.0)
	var stopped: VehicleInput = RouterScript.arbitrate_local(
			_raw(1.0, 0.0), -0.1, GEAR_R)
	assert_int(stopped.gear_request).is_equal(GEAR_D1)
	assert_float(stopped.throttle).is_equal(1.0)
	assert_float(stopped.brake).is_equal(0.0)


func test_idle_in_reverse_stays_in_reverse() -> void:
	var out: VehicleInput = RouterScript.arbitrate_local(
			_raw(), 0.0, GEAR_R)
	assert_int(out.gear_request).is_equal(GEAR_R)
	assert_float(out.throttle).is_equal(0.0)


func test_no_input_in_neutral_requests_neutral() -> void:
	var out: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_N)
	assert_int(out.gear_request).is_equal(GEAR_N)
	assert_bool(out.gear_auto).is_true()


func test_steer_and_handbrake_pass_through_clamped() -> void:
	var out: VehicleInput = RouterScript.arbitrate_local(
			_raw(0.0, 0.0, -1.5, 2.0), 0.0, GEAR_D1)
	assert_float(out.steer).is_equal(-1.0)
	assert_float(out.handbrake).is_equal(1.0)


# --- bridge arbitration (gear owns direction while active) --------------------
## Values reach arbitrate_bridge already normalized (bridge_source did the /100).

func _bridge(accel := 0.0, brake := 0.0, steer := 0.0, handbrake := 0.0,
		gear := GEAR_N, key := RouterScript.KEY_IGNITION) -> Dictionary:
	return {
		"active": true, "accel": accel, "brake": brake, "steer": steer,
		"handbrake": handbrake, "gear": gear, "key": key, "lights": 1, "horn": false,
	}


func test_bridge_gear_owns_direction() -> void:
	var d1: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_int(d1.gear_request).is_equal(GEAR_D1)
	assert_float(d1.throttle).is_equal(1.0)
	assert_bool(d1.gear_auto).is_false()
	var rev: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_R))
	assert_int(rev.gear_request).is_equal(GEAR_R)
	assert_float(rev.throttle).is_equal(-1.0)
	# N (byte 0) = no gear opinion, NOT park: gearbox auto-drives forward with no bridge.
	var neu: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_N))
	assert_int(neu.gear_request).is_equal(GEAR_D1)
	assert_float(neu.throttle).is_equal(1.0)
	assert_bool(neu.gear_auto).is_true()
	var idle: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_N))
	assert_int(idle.gear_request).is_equal(GEAR_N)
	assert_float(idle.throttle).is_equal(0.0)


func test_bridge_all_forward_gears_drive_forward() -> void:
	for g in [2, 3, 4, 5, 6]:
		var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.5, 0.0, 0.0, 0.0, g))
		assert_int(out.gear_request).is_equal(g)
		assert_float(out.throttle).is_equal(0.5)


func test_bridge_key_gates_throttle() -> void:
	for key in [RouterScript.KEY_LOCK, RouterScript.KEY_ON]:
		var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_D1, key))
		assert_float(out.throttle).is_equal(0.0)
	var ign: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_D1, RouterScript.KEY_IGNITION))
	assert_float(ign.throttle).is_equal(1.0)


func test_bridge_brake_never_throttle() -> void:
	# Brake alone: no throttle, brake passes.
	var braked: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 1.0, 0.0, 0.0, GEAR_D1))
	assert_float(braked.throttle).is_equal(0.0)
	assert_float(braked.brake).is_equal(1.0)
	# Full accel + full brake: throttle from accel (signed by gear), brake still passes.
	var both: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 1.0, 0.0, 0.0, GEAR_D1))
	assert_float(both.throttle).is_equal(1.0)
	assert_float(both.brake).is_equal(1.0)


func test_bridge_steer_and_handbrake_pass_through() -> void:
	var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, -0.5, 1.0, GEAR_D1))
	assert_float(out.steer).is_equal(-0.5)
	assert_float(out.handbrake).is_equal(1.0)


# --- lamp/warning bits --------------------------------------------

func test_local_lamp_bits_default_off_and_brake_lamp_follows_brake() -> void:
	# Rolling in D1 with S held: foot brake on -> STOP; turn/warning LEDs off (no local
	# source, no blink timer).
	var braking: VehicleInput = RouterScript.arbitrate_local(_raw(0.0, 1.0), 10.0, GEAR_D1)
	assert_bool(braking.lamps.brake_lamp).is_true()
	assert_bool(braking.lamps.turn_left).is_false()
	assert_bool(braking.lamps.turn_right).is_false()
	assert_bool(braking.lamps.check_engine).is_false()
	assert_bool(braking.lamps.battery_warn).is_false()
	# Coasting: no brake -> no STOP.
	var coasting: VehicleInput = RouterScript.arbitrate_local(_raw(1.0, 0.0), 10.0, GEAR_D1)
	assert_bool(coasting.lamps.brake_lamp).is_false()


func test_merge_local_combines_keyboard_and_touch() -> void:
	# Analog axes take the stronger request; steer sums (clamped); bits OR.
	var kbd: Dictionary[StringName, Variant] = {"accel": 0.3, "brake_reverse": 0.0,
			"steer": 0.5, "handbrake": 0.0, "horn": false, "lights_cycle": false}
	var touch: Dictionary[StringName, Variant] = {"accel": 1.0, "brake_reverse": 0.4,
			"steer": 0.8, "handbrake": 1.0, "horn": true, "lights_cycle": false}
	var m := RouterScript.merge_local(kbd, touch)
	assert_float(m["accel"]).is_equal(1.0)
	assert_float(m["brake_reverse"]).is_equal(0.4)
	assert_float(m["steer"]).is_equal(1.0)  # 0.5 + 0.8 clamped
	assert_float(m["handbrake"]).is_equal(1.0)
	assert_bool(m["horn"]).is_true()
	assert_bool(m["lights_cycle"]).is_false()


# --- ISOBUS implement (tractor) -----------------------------------------------

func test_bridge_maps_hitch_percent_and_mirrors_pto() -> void:
	# hitch_pos arrives 0..100 (bridge_source keeps contract units); arbitrate_bridge /100.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["hitch_pos"] = 40.0
	vals["pto"] = true
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.hitch_request).is_equal_approx(0.4, 1e-4)
	assert_bool(out.pto).is_true()
	# Absent → raised (1.0) / off, the §6 default-off convention.
	var bare: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.hitch_request).is_equal(1.0)
	assert_bool(bare.pto).is_false()


func test_local_passes_hitch_and_pto_through() -> void:
	var raw := _raw()
	raw["hitch_request"] = 0.0
	raw["pto"] = true
	var out: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_float(out.hitch_request).is_equal(0.0)
	assert_bool(out.pto).is_true()
	# Defaults when the keys are absent: raised / off.
	var bare: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_float(bare.hitch_request).is_equal(1.0)
	assert_bool(bare.pto).is_false()


func test_merge_local_ors_implement_toggle_edges() -> void:
	var kbd: Dictionary[StringName, Variant] = {"hitch_toggle": true, "pto_toggle": false}
	var touch: Dictionary[StringName, Variant] = {"hitch_toggle": false, "pto_toggle": true}
	var m := RouterScript.merge_local(kbd, touch)
	assert_bool(m["hitch_toggle"]).is_true()
	assert_bool(m["pto_toggle"]).is_true()
	# Neither pressed → both false.
	var none := RouterScript.merge_local({}, {})
	assert_bool(none["hitch_toggle"]).is_false()
	assert_bool(none["pto_toggle"]).is_false()


# --- ISOBUS driveline (tractor: diff lock, MFWD, PTO mode) ---------------------

func test_bridge_mirrors_the_driveline_requests() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["diff_lock"] = true
	vals["fwd_drive"] = true
	vals["pto_mode"] = 1
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_bool(out.diff_lock).is_true()
	assert_bool(out.fwd_drive).is_true()
	assert_int(out.pto_mode).is_equal(1)
	# Absent → open diff, 2WD, 540: a real tractor's rest state, and the §6 default-off rule.
	var bare: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_bool(bare.diff_lock).is_false()
	assert_bool(bare.fwd_drive).is_false()
	assert_int(bare.pto_mode).is_equal(0)


func test_local_passes_the_driveline_toggles_through() -> void:
	var raw := _raw()
	raw["diff_lock"] = true
	raw["fwd_drive"] = true
	raw["pto_mode"] = 1
	var out: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(out.diff_lock).is_true()
	assert_bool(out.fwd_drive).is_true()
	assert_int(out.pto_mode).is_equal(1)
	# InputRouter owns the latched state, so an empty raw dict means "nothing engaged".
	var bare: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_bool(bare.diff_lock).is_false()
	assert_bool(bare.fwd_drive).is_false()
	assert_int(bare.pto_mode).is_equal(0)


func test_merge_local_ors_the_driveline_toggle_edges() -> void:
	var kbd: Dictionary[StringName, Variant] = {
			"diff_lock_toggle": true, "fwd_drive_toggle": false, "pto_mode_toggle": false}
	var touch: Dictionary[StringName, Variant] = {
			"diff_lock_toggle": false, "fwd_drive_toggle": true, "pto_mode_toggle": true}
	var m := RouterScript.merge_local(kbd, touch)
	assert_bool(m["diff_lock_toggle"]).is_true()
	assert_bool(m["fwd_drive_toggle"]).is_true()
	assert_bool(m["pto_mode_toggle"]).is_true()
	var none := RouterScript.merge_local({}, {})
	assert_bool(none["diff_lock_toggle"]).is_false()
	assert_bool(none["fwd_drive_toggle"]).is_false()
	assert_bool(none["pto_mode_toggle"]).is_false()


func test_bridge_rudder_overrides_steer_when_present() -> void:
	# sloppyCAN driving a boat sends 'rudder' (bridge_source only includes the key
	# when sent): it becomes the steer channel, whatever 'steer' says.
	var vals := _bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1)
	vals["rudder"] = -0.6
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.steer).is_equal_approx(-0.6, 1e-6)
	# Clamped like steer.
	vals["rudder"] = -1.7
	assert_float(RouterScript.arbitrate_bridge(vals).steer).is_equal(-1.0)


func test_bridge_steer_unchanged_without_rudder() -> void:
	# Cars/trucks never send 'rudder' — steer passes through exactly as before.
	var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1))
	assert_float(out.steer).is_equal_approx(0.9, 1e-6)


# --- flight controls (plane elevator + flaps / drone climb + arm) -------------

func test_local_flight_axes_pass_through_clamped() -> void:
	var raw := _raw()
	raw["elevator"] = 0.7
	raw["climb"] = -1.4  # out of range on purpose
	raw["arm"] = true
	var out: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_float(out.elevator).is_equal_approx(0.7, 1e-6)
	assert_float(out.climb).is_equal(-1.0)  # clamped
	assert_bool(out.arm).is_true()
	# Defaults when absent: neutral axes, disarmed.
	var bare: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_float(bare.elevator).is_equal(0.0)
	assert_float(bare.climb).is_equal(0.0)
	assert_bool(bare.arm).is_false()


func test_bridge_normalizes_flight_axes_and_mirrors_arm() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["elevator"] = 0.5   # already %→unit normalized by bridge_source
	vals["climb"] = 1.6      # out of range on purpose
	vals["arm"] = true
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.elevator).is_equal_approx(0.5, 1e-6)
	assert_float(out.climb).is_equal(1.0)  # clamped
	assert_bool(out.arm).is_true()
	# Absent → neutral / disarmed (arm is authoritative from the bridge, no local toggle).
	var bare: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.elevator).is_equal(0.0)
	assert_float(bare.climb).is_equal(0.0)
	assert_bool(bare.arm).is_false()


func test_merge_local_combines_flight_axes_and_arm_edge() -> void:
	var kbd: Dictionary[StringName, Variant] = {"elevator": 0.5, "climb": 0.0, "arm_toggle": false}
	var touch: Dictionary[StringName, Variant] = {"elevator": 0.8, "climb": -0.3, "arm_toggle": true}
	var m := RouterScript.merge_local(kbd, touch)
	assert_float(m["elevator"]).is_equal(1.0)  # 0.5 + 0.8 clamped
	assert_float(m["climb"]).is_equal_approx(-0.3, 1e-6)
	assert_bool(m["arm_toggle"]).is_true()
	# Neither pressed → axes 0, edge false.
	var none := RouterScript.merge_local({}, {})
	assert_float(none["elevator"]).is_equal(0.0)
	assert_bool(none["arm_toggle"]).is_false()


func test_local_flaps_pass_through_clamped() -> void:
	# InputRouter owns the local _flaps_down toggle and injects "flaps" as 0/1; the
	# arbitration just clamps and passes it through (the hitch_request pattern).
	var raw := _raw()
	raw["flaps"] = 1.0
	var out: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_float(out.flaps).is_equal(1.0)
	raw["flaps"] = 3.0  # out of range on purpose
	out = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_float(out.flaps).is_equal(1.0)  # clamped
	# Absent → retracted.
	var bare: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_float(bare.flaps).is_equal(0.0)


func test_bridge_flaps_mirrored_clamped() -> void:
	# Already %→unit normalized by bridge_source; the bridge value is authoritative
	# (no local toggle on that path), absent → retracted.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["flaps"] = 0.4
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.flaps).is_equal_approx(0.4, 1e-6)
	vals["flaps"] = 1.7  # out of range on purpose
	out = RouterScript.arbitrate_bridge(vals)
	assert_float(out.flaps).is_equal(1.0)  # clamped
	var bare: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.flaps).is_equal(0.0)


func test_merge_local_combines_flaps_edge() -> void:
	var m := RouterScript.merge_local(_intent({"flaps_toggle": false}), _intent({"flaps_toggle": true}))
	assert_bool(m["flaps_toggle"]).is_true()
	assert_bool(RouterScript.merge_local({}, {})["flaps_toggle"]).is_false()


func test_bridge_mirrors_lamp_bits_verbatim() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["turnL"] = true
	vals["brakeLamp"] = true
	vals["checkEngine"] = true
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_bool(out.lamps.turn_left).is_true()
	assert_bool(out.lamps.turn_right).is_false()   # absent bit stays off
	assert_bool(out.lamps.brake_lamp).is_true()
	assert_bool(out.lamps.check_engine).is_true()
	assert_bool(out.lamps.battery_warn).is_false() # warning LED defaults off when not sent


# --- train controls (pantograph + doors) --------------------------------------

func test_local_train_toggles_pass_through() -> void:
	# InputRouter owns the local _pantograph / _doors toggles and injects them as bools;
	# the arbitration just passes them through (the pto pattern).
	var raw := _raw()
	raw["pantograph"] = true
	raw["doors"] = true
	var out: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(out.pantograph).is_true()
	assert_bool(out.doors).is_true()
	# Absent → lowered / shut.
	var bare: VehicleInput = RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_bool(bare.pantograph).is_false()
	assert_bool(bare.doors).is_false()


func test_bridge_mirrors_train_bits_verbatim() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["pantograph"] = true
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_bool(out.pantograph).is_true()
	assert_bool(out.doors).is_false()  # absent bit stays off
	var bare: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_bool(bare.pantograph).is_false()
	assert_bool(bare.doors).is_false()


func test_merge_local_ors_train_toggle_edges() -> void:
	var m := RouterScript.merge_local(
			_intent({"pantograph_toggle": true, "doors_toggle": false}),
			_intent({"pantograph_toggle": false, "doors_toggle": true}))
	assert_bool(m["pantograph_toggle"]).is_true()
	assert_bool(m["doors_toggle"]).is_true()
	var none := RouterScript.merge_local({}, {})
	assert_bool(none["pantograph_toggle"]).is_false()
	assert_bool(none["doors_toggle"]).is_false()


func test_bridge_guidance_overrides_steer_when_present() -> void:
	# sloppyCAN driving the tractor under auto-steer sends 'guidance_curvature';
	# bridge_source only puts the key in when it was sent, and presence is what makes it the
	# steer channel — whatever 'steer' says. Values arrive already normalized to -1..1.
	var vals := _bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1)
	vals["guidance"] = -0.4
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.steer).is_equal_approx(-0.4, 1e-6)
	# A command harder than full lock sits on the stop, like steer/rudder.
	vals["guidance"] = 2.5
	assert_float(RouterScript.arbitrate_bridge(vals).steer).is_equal(1.0)
	# Dead straight is a real command, not "absent": a guidance system holding the line at 0
	# must override a nonzero steer, or an auto-steer pass would wander.
	vals["guidance"] = 0.0
	assert_float(RouterScript.arbitrate_bridge(vals).steer).is_equal(0.0)


func test_bridge_steer_unchanged_without_guidance() -> void:
	# No guidance command → the tractor steers off 'steer' exactly as before.
	var out: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1))
	assert_float(out.steer).is_equal_approx(0.9, 1e-6)


func test_bridge_guidance_curvature_scales_off_full_lock() -> void:
	# The 1/km → steer conversion belongs to bridge_source (the units step, like steer's
	# %→unit): full-lock curvature is full lock, half of it is half lock, and the sign carries
	# through (negative curvature = curving left = negative steer).
	var full := BridgeSourceScript.FULL_LOCK_CURVATURE
	assert_float(BridgeSourceScript.steer_from_curvature(full)).is_equal(1.0)
	assert_float(BridgeSourceScript.steer_from_curvature(-full)).is_equal(-1.0)
	assert_float(BridgeSourceScript.steer_from_curvature(full * 0.5)).is_equal_approx(0.5, 1e-6)
	assert_float(BridgeSourceScript.steer_from_curvature(0.0)).is_equal(0.0)
	# Saturates rather than asking for more lock than the tractor has.
	assert_float(BridgeSourceScript.steer_from_curvature(full * 3.0)).is_equal(1.0)


func test_bridge_guidance_beats_a_stale_rudder_key() -> void:
	# Only one vehicle can send each key, so the two never collide in practice — but the
	# order is pinned so a future edit cannot silently make 'rudder' shadow auto-steer.
	var vals := _bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1)
	vals["rudder"] = 0.7
	vals["guidance"] = -0.2
	assert_float(RouterScript.arbitrate_bridge(vals).steer).is_equal_approx(-0.2, 1e-6)


func test_bridge_mirrors_scv_flow_absent_is_closed() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["scv_flow"] = 0.6   # bridge_source already did the %→unit
	assert_float(RouterScript.arbitrate_bridge(vals).scv_flow).is_equal_approx(0.6, 1e-6)
	vals["scv_flow"] = 1.8
	assert_float(RouterScript.arbitrate_bridge(vals).scv_flow).is_equal(1.0)
	# Absent → valve closed, the default-off convention.
	var bare: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.scv_flow).is_equal(0.0)


func test_local_scv_flow_is_the_routers_own_spool() -> void:
	# SCV is a binary spool owned by router (like _pto); both sources share one state.
	var raw := _raw()
	raw["scv_flow"] = 1.0
	assert_float(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).scv_flow).is_equal(1.0)
	raw["scv_flow"] = 0.0
	assert_float(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).scv_flow).is_equal(0.0)
	# Absent key = closed (never guessed opening).
	assert_float(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).scv_flow).is_equal(0.0)
	# And it is clamped like every other level the router passes through.
	raw["scv_flow"] = 4.0
	assert_float(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).scv_flow).is_equal(1.0)


func test_the_scv_toggle_merges_across_keyboard_and_touch() -> void:
	# Both sources report a per-frame EDGE and InputRouter owns the state, so a touch button and the
	# key drive one spool rather than two. The merge is the same one the PTO and diff-lock edges use.
	var kbd: Dictionary[StringName, Variant] = {"scv_toggle": true, "pto_toggle": false}
	var touch: Dictionary[StringName, Variant] = {"scv_toggle": false, "pto_toggle": true}
	var m := RouterScript.merge_local(kbd, touch)
	assert_bool(m["scv_toggle"]).is_true()
	assert_bool(m["pto_toggle"]).is_true()
	var none := RouterScript.merge_local(_intent({"scv_toggle": false}), _intent({"scv_toggle": false}))
	assert_bool(none["scv_toggle"]).is_false()


func test_bridge_mirrors_retarder_absent_is_released() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["retarder"] = 0.6   # bridge_source already did the %→unit
	assert_float(RouterScript.arbitrate_bridge(vals).retarder).is_equal_approx(0.6, 1e-6)
	vals["retarder"] = 1.8
	assert_float(RouterScript.arbitrate_bridge(vals).retarder).is_equal(1.0)
	# Absent → released, the default-off convention.
	var bare: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.retarder).is_equal(0.0)


func test_local_has_no_retarder() -> void:
	# No local stalk: released (never guessed).
	var raw := _raw()
	raw["retarder"] = 0.9   # even if a source invented the key
	assert_float(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).retarder).is_equal(0.0)


func test_bridge_mirrors_dm1_lamps_verbatim() -> void:
	# The J1939-73 DM1 lamp status byte: mirrored exactly like turnL, with no local timer and
	# no interpretation. An absent bit is off, which is its correct default.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["red_stop"] = true
	vals["protect_lamp"] = true
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_bool(out.lamps.red_stop).is_true()
	assert_bool(out.lamps.amber_warn).is_false()   # absent bit stays off
	assert_bool(out.lamps.protect_lamp).is_true()


func test_local_dm1_lamps_stay_dark() -> void:
	# No local source at all, like turnL/turnR — a fault lamp with no fault behind it would be
	# a fiction, and blinking one from a local clock is forbidden outright.
	var out: VehicleInput = RouterScript.arbitrate_local(_raw(0.0, 1.0), 10.0, GEAR_D1)
	assert_bool(out.lamps.red_stop).is_false()
	assert_bool(out.lamps.amber_warn).is_false()
	assert_bool(out.lamps.protect_lamp).is_false()


func test_the_trailer_fault_lamp_is_mirrored_and_has_no_local_source() -> void:
	# ISO 11992's only "in" signal, and it follows the DM1 rule exactly: sloppyCAN is the sole
	# authority, an absent bit is off, and there is no key, no toggle and no timer behind it. A
	# trailer fault the game invented for itself would be a fiction.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	assert_bool(RouterScript.arbitrate_bridge(vals).lamps.trailer_ebs_fault) \
		.override_failure_message("an absent trailer fault bit must read off").is_false()
	vals["trailer_ebs_fault"] = true
	assert_bool(RouterScript.arbitrate_bridge(vals).lamps.trailer_ebs_fault).is_true()
	# No local path at all, even if a source invented the key.
	var raw := _raw()
	raw["trailer_ebs_fault"] = true
	assert_bool(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).lamps.trailer_ebs_fault).is_false()


# --- the refuse body's command stalk (contract 'body_cmd') --------------------

func test_the_stalk_position_count_matches_the_body_units_command_enum() -> void:
	# BODY_CMD_COUNT mirrors RefuseBody.Cmd instead of reading it, so that the router keeps no
	# dependency on a vehicle class. That is only safe if the two cannot drift: a fifth command
	# added to the enum without widening the cycle would be reachable from the bus and
	# unreachable from the key, which is the sort of gap that reads as "the key is broken".
	assert_int(RouterScript.BODY_CMD_COUNT) \
		.override_failure_message("InputRouter.BODY_CMD_COUNT has drifted from RefuseBody.Cmd") \
		.is_equal(BodyScript.Cmd.size())


func test_the_local_stalk_cycles_through_every_command_and_wraps() -> void:
	# Cycled, not flipped: the whole reason InputRouter owns a byte here rather than a bool.
	var seen := {}
	var pos := 0
	for _i in RouterScript.BODY_CMD_COUNT:
		seen[pos] = true
		pos = (pos + 1) % RouterScript.BODY_CMD_COUNT
	assert_int(seen.size()) \
		.override_failure_message("the cycle does not reach every command").is_equal(
			RouterScript.BODY_CMD_COUNT)
	assert_int(pos).override_failure_message("the cycle must wrap back to Idle").is_equal(0)


func test_local_body_command_rides_the_struct_from_the_router_owned_cycle() -> void:
	# The field rides VehicleInput like every other subsystem request — never a side channel —
	# and InputRouter owns the latched value, so arbitrate_local only forwards it.
	var raw := _raw()
	raw["body_cmd"] = BodyScript.Cmd.DUMP
	assert_int(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).body_cmd).is_equal(
			BodyScript.Cmd.DUMP)
	# Absent (every non-truck vehicle, and a truck at rest): Idle, the safe pose.
	assert_int(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).body_cmd).is_equal(
			BodyScript.Cmd.IDLE)


func test_bridge_owns_the_body_command_while_it_is_live() -> void:
	# CiA 422 reaches us across the gateway, and sloppyCAN is the sole authority while the bridge
	# drives — so the local cycle cannot leak in, and an absent byte is Idle rather than a hold.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["body_cmd"] = BodyScript.Cmd.LIFT
	assert_int(RouterScript.arbitrate_bridge(vals).body_cmd).is_equal(BodyScript.Cmd.LIFT)
	assert_int(RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)).body_cmd).is_equal(BodyScript.Cmd.IDLE)


func test_the_body_command_edge_survives_merge_local() -> void:
	# merge_local builds its dict EXPLICITLY, so a missing key drops the keyboard's edge for as
	# long as a touch source is registered. That failure is silent, hence the assertion.
	assert_bool(RouterScript.merge_local(_intent({"body_cmd_toggle": true}), {})["body_cmd_toggle"]).is_true()
	assert_bool(RouterScript.merge_local({}, _intent({"body_cmd_toggle": true}))["body_cmd_toggle"]).is_true()
	assert_bool(RouterScript.merge_local({}, {})["body_cmd_toggle"]).is_false()


func test_local_node_fail_rides_the_vehicle_input() -> void:
	var raw := _raw()
	raw["node_fail"] = 0b0100
	assert_int(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).node_fail).is_equal(0b0100)
	# Absent (every vehicle that is not the drone, and a drone with a healthy bus): 0, which
	# is every node online — the same "absent = the harmless state" rule the lamp bits follow.
	assert_int(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).node_fail).is_equal(0)


func test_bridge_mirrors_node_fail_verbatim() -> void:
	# sloppyCAN is the sole authority while it drives: the mask passes through untouched (no
	# clamp, no timer, no debounce), the local latch cannot leak in, and an absent value is a
	# healthy bus rather than a hold of whatever was failed last.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["node_fail"] = 0b1000_0001
	assert_int(RouterScript.arbitrate_bridge(vals).node_fail).is_equal(0b1000_0001)
	assert_int(RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)).node_fail).is_equal(0)


func test_the_node_fail_edge_survives_merge_local() -> void:
	# merge_local builds its dict EXPLICITLY, so a missing key drops the keyboard's Y edge for
	# as long as a touch source is registered. That failure is silent, hence the assertion.
	assert_bool(RouterScript.merge_local(_intent({"node_fail_cycle": true}), {})["node_fail_cycle"]).is_true()
	assert_bool(RouterScript.merge_local({}, _intent({"node_fail_cycle": true}))["node_fail_cycle"]).is_true()
	assert_bool(RouterScript.merge_local({}, {})["node_fail_cycle"]).is_false()


func test_a_new_body_clears_the_node_failure_but_not_the_other_toggles() -> void:
	var router: Node = auto_free(RouterScript.new())
	add_child(router)
	router._node_fail = 0b0010
	router._pto = true
	router._armed = true
	router._lights = 3
	router.register_vehicle(null)
	assert_int(router._node_fail).is_equal(0)
	assert_bool(router._pto).is_true()
	assert_bool(router._armed).is_true()
	assert_int(router._lights).is_equal(3)


# --- the boat's autopilot ------------------------------------------------------

func test_local_nav_mode_rides_the_vehicle_input() -> void:
	var raw := _raw()
	raw["nav_mode"] = 1
	var engaged: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_int(engaged.nav_mode).is_equal(1)
	# There is no local `heading_cmd` and there must not be: no keyboard types a bearing, so a
	# locally-engaged pilot holds the heading it captured. NONE is what says "nothing commanded".
	assert_float(engaged.heading_cmd).is_equal(VehicleInput.HEADING_CMD_NONE)
	assert_int(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).nav_mode).is_equal(0)


func test_bridge_mirrors_the_autopilot_and_leaves_an_uncommanded_course_alone() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["nav_mode"] = 1
	vals["heading_cmd"] = 275.0
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_int(out.nav_mode).is_equal(1)
	assert_float(out.heading_cmd).is_equal_approx(275.0, 1e-6)
	# Absent: standing by, with NO course commanded — 0 would be a bearing (due north), and the
	# pilot would silently steer to it. This is the `rudder` presence rule, and it is the whole
	# reason bridge_source writes the key only when sloppyCAN sends it.
	var quiet: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_int(quiet.nav_mode).is_equal(0)
	assert_float(quiet.heading_cmd).is_equal(VehicleInput.HEADING_CMD_NONE)


func test_the_autopilot_edge_survives_merge_local() -> void:
	assert_bool(RouterScript.merge_local(_intent({"nav_mode_cycle": true}), {})["nav_mode_cycle"]).is_true()
	assert_bool(RouterScript.merge_local({}, _intent({"nav_mode_cycle": true}))["nav_mode_cycle"]).is_true()
	assert_bool(RouterScript.merge_local({}, {})["nav_mode_cycle"]).is_false()


func test_a_new_body_clears_the_autopilot() -> void:
	# A new hull must not spawn with an engaged pilot steering to the last boat's course.
	var router: Node = auto_free(RouterScript.new())
	add_child(router)
	router._nav_mode = 1
	router.register_vehicle(null)
	assert_int(router._nav_mode).is_equal(0)


# --- the bridge-only lock (challenges) --------------------------------------------

## A touch stand-in that counts its polls and always asks for full throttle.
class _CountingTouch extends RefCounted:
	var polls := 0

	func poll() -> Dictionary[StringName, Variant]:
		polls += 1
		return {&"accel": 1.0}


## A bridge that is live and sending full throttle in D1.
class _LiveBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"accel": 1.0, &"gear": GEAR_D1, &"key": RouterScript.KEY_IGNITION}


## Kept out of the tree so no real physics tick runs between the steps a test makes by hand.
func _locked_router(touch: _CountingTouch) -> Node:
	var router: Node = auto_free(RouterScript.new())
	router._dev_keys = false
	router.set_touch_source(touch)
	router.set_bridge_only(true)
	return router


func test_the_locked_idle_is_key_lock_with_the_handbrake_on() -> void:
	var out: VehicleInput = RouterScript.locked_idle()
	assert_int(out.key).is_equal(RouterScript.KEY_LOCK)
	assert_float(out.handbrake).is_equal(1.0)
	assert_float(out.throttle).is_equal(0.0)
	assert_float(out.brake).is_equal(0.0)
	assert_float(out.steer).is_equal(0.0)
	assert_int(out.gear_request).is_equal(GEAR_N)


func test_bridge_only_never_polls_local_or_touch() -> void:
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(0)
	var out: VehicleInput = router.get_vehicle_input()
	assert_int(out.key).is_equal(RouterScript.KEY_LOCK)
	assert_float(out.handbrake).is_equal(1.0)
	assert_float(out.throttle).is_equal(0.0)
	# Lifting the lock hands driving straight back to the local sources.
	router.set_bridge_only(false)
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(1)
	assert_float(router.get_vehicle_input().throttle).is_equal(1.0)


func test_a_live_bridge_drives_under_the_lock() -> void:
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._bridge_source = _LiveBridge.new()
	router._physics_process(1.0 / 60.0)
	var out: VehicleInput = router.get_vehicle_input()
	assert_int(out.key).is_equal(RouterScript.KEY_IGNITION)
	assert_float(out.throttle).is_equal(1.0)
	assert_int(out.gear_request).is_equal(GEAR_D1)
	assert_int(touch.polls).is_equal(0)


func test_the_dev_override_lets_local_drive_under_the_lock() -> void:
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._dev_keys = true
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(1)
	assert_float(router.get_vehicle_input().throttle).is_equal(1.0)
