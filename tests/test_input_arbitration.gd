extends GdUnitTestSuite
## InputRouter local arbitration rules: key gating,
## brake-never-throttle, and the local S = brake-then-reverse scheme.
## Exercises the pure static arbitrate_local — no autoload lifecycle needed.

const RouterScript := preload("res://src/input/input_router.gd")
const BridgeSourceScript := preload("res://src/input/sources/bridge_source.gd")
const RouterFixtures := preload("res://tests/router_fixtures.gd")
const LocalSourceScript := preload("res://src/input/sources/local_source.gd")
const BodyScript := preload("res://src/vehicles/truck/refuse_body.gd")
const ContractScript := preload("res://src/bridge/contract.gd")

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


## The tests that drive BridgeSource through the Bridge autoload set its `_active` / `_inbound`;
## put them back here, so a test that errors out before its end cannot leave the bridge live.
func after_test() -> void:
	Bridge.set("_active", false)
	Bridge.set("_inbound", {})


## A router on an idle pad (`RouterFixtures`): every router a test here builds.
func _router() -> Node:
	return auto_free(RouterFixtures.idle_router())


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
	# Arbitration passes both pedals; the router's brake override (below) settles them, since it
	# needs the body's speed and a latch across ticks.
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


func test_reverse_engages_exactly_at_the_boundary_speed() -> void:
	# near_standstill is `absf(speed) <= REVERSE_ENGAGE_SPEED`: the boundary speed itself must
	# still read as standstill, not "still rolling" (<= vs <).
	var at_boundary: VehicleInput = RouterScript.arbitrate_local(
			_raw(0.0, 1.0), RouterScript.REVERSE_ENGAGE_SPEED, GEAR_D1)
	assert_int(at_boundary.gear_request).is_equal(GEAR_R)
	assert_float(at_boundary.throttle).is_equal(-1.0)
	assert_float(at_boundary.brake).is_equal(0.0)
	# Same boundary re-engaging drive from reverse.
	var from_reverse: VehicleInput = RouterScript.arbitrate_local(
			_raw(1.0, 0.0), -RouterScript.REVERSE_ENGAGE_SPEED, GEAR_R)
	assert_int(from_reverse.gear_request).is_equal(GEAR_D1)
	assert_float(from_reverse.throttle).is_equal(1.0)


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


func test_manual_bridge_gear_is_exact_and_owns_direction() -> void:
	var d1: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_D1), true)
	assert_int(d1.gear_request).is_equal(GEAR_D1)
	assert_float(d1.throttle).is_equal(1.0)
	assert_bool(d1.gear_auto).is_false()
	var rev: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_R), true)
	assert_int(rev.gear_request).is_equal(GEAR_R)
	assert_float(rev.throttle).is_equal(-1.0)
	assert_bool(rev.gear_auto).is_false()
	# Byte 0 is a real N in manual: accel still passes (the engine free-revs), nothing engages.
	var neu: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_N), true)
	assert_int(neu.gear_request).is_equal(GEAR_N)
	assert_float(neu.throttle).is_equal(1.0)
	assert_bool(neu.gear_auto).is_false()
	# Every drive byte of the bus passes exactly and drives forward; one past it is N.
	for g in range(GEAR_D1, RouterScript.GEAR_TOP + 1):
		var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.5, 0.0, 0.0, 0.0, g), true)
		assert_int(out.gear_request).override_failure_message("byte %d" % g).is_equal(g)
		assert_float(out.throttle).override_failure_message("byte %d" % g).is_equal(0.5)
	var past: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(1.0, 0.0, 0.0, 0.0, RouterScript.GEAR_TOP + 1), true)
	assert_int(past.gear_request).is_equal(GEAR_N)


func test_bridge_p_parks_in_both_gearbox_modes() -> void:
	for manual in [true, false]:
		var out: VehicleInput = RouterScript.arbitrate_bridge(
				_bridge(0.6, 0.0, 0.0, 0.0, RouterScript.GEAR_P), manual)
		assert_int(out.gear_request).is_equal(RouterScript.GEAR_P)
		# Nothing drives in P; the pedal still revs the engine, forward-signed.
		assert_float(out.throttle).is_equal(0.6)


func test_automatic_bridge_byte_0_keeps_a_parked_body_in_p() -> void:
	# Byte 0 is "no gear opinion": silence never unparks, the accelerator does.
	var held: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_N),
			false, RouterScript.GEAR_P)
	assert_int(held.gear_request).is_equal(RouterScript.GEAR_P)
	var go: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.4, 0.0, 0.0, 0.0, GEAR_N),
			false, RouterScript.GEAR_P)
	assert_int(go.gear_request).is_equal(GEAR_D1)
	# Not parked: byte 0 with no throttle is N, as before.
	var idle: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_N),
			false, GEAR_D1)
	assert_int(idle.gear_request).is_equal(GEAR_N)
	# Manual takes byte 0 exactly: a real N, parked or not.
	var manual: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_N),
			true, RouterScript.GEAR_P)
	assert_int(manual.gear_request).is_equal(GEAR_N)


func test_local_driving_leaves_p_only_when_asked_to_move() -> void:
	var held: VehicleInput = RouterScript.arbitrate_local(_intent({}), 0.0, RouterScript.GEAR_P)
	assert_int(held.gear_request).is_equal(RouterScript.GEAR_P)
	var go: VehicleInput = RouterScript.arbitrate_local(_intent({&"accel": 1.0}), 0.0,
			RouterScript.GEAR_P)
	assert_int(go.gear_request).is_equal(GEAR_D1)


func test_the_brake_override_never_latches_in_p() -> void:
	var input := VehicleInput.new()
	input.brake = 1.0
	input.throttle = 1.0
	input.gear_request = RouterScript.GEAR_P
	assert_bool(RouterScript.brake_override(false, input, 5.0)).is_false()


## Automatic is the default: the byte is a PRND lever, and the gearbox picks the gear.
func test_automatic_bridge_reads_the_gear_as_a_direction() -> void:
	for g in [1, 2, 3, 4, 5, 6]:
		var out: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.5, 0.0, 0.0, 0.0, g))
		assert_int(out.gear_request).is_equal(GEAR_D1)
		assert_bool(out.gear_auto).is_true()
		assert_float(out.throttle).is_equal(0.5)
	var rev: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_R))
	assert_int(rev.gear_request).is_equal(GEAR_R)
	assert_float(rev.throttle).is_equal(-1.0)
	assert_bool(rev.gear_auto).is_true()
	# Byte 0 = no gear opinion, NOT park: gearbox auto-drives forward as with no bridge.
	var neu: VehicleInput = RouterScript.arbitrate_bridge(_bridge(1.0, 0.0, 0.0, 0.0, GEAR_N))
	assert_int(neu.gear_request).is_equal(GEAR_D1)
	assert_float(neu.throttle).is_equal(1.0)
	assert_bool(neu.gear_auto).is_true()
	var idle: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_N))
	assert_int(idle.gear_request).is_equal(GEAR_N)
	assert_float(idle.throttle).is_equal(0.0)


func test_the_router_gearbox_mode_reaches_bridge_arbitration() -> void:
	var router := _router()
	router._bridge_source = _LiveBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_bool(router.get_vehicle_input().gear_auto).is_true()
	router.set_manual_gearbox(true)
	router._physics_process(1.0 / 60.0)
	assert_bool(router.get_vehicle_input().gear_auto).is_false()


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
	# The body's own brake-light request lights it with no pedal; it never darkens the pedal's.
	assert_bool(RouterScript.local_brake_lamp(coasting.lamps.brake_lamp, true)).is_true()
	assert_bool(RouterScript.local_brake_lamp(braking.lamps.brake_lamp, false)).is_true()
	assert_bool(RouterScript.local_brake_lamp(coasting.lamps.brake_lamp, false)).is_false()


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


func test_every_toggle_and_cycle_edge_ors_across_the_merge() -> void:
	# Every edge LocalSource reports, so a new toggle is covered the day it ships. That a key
	# survives the merge from either side is test_action_registry's; this is the OR: a press on
	# one side beats a release on the other, and a release on both stays released.
	var edges := LocalSourceScript.new().poll(0.0).keys().filter(func(k: StringName) -> bool:
		return String(k).ends_with("_toggle") or String(k).ends_with("_cycle"))
	assert_array(edges).is_not_empty()
	for k: StringName in edges:
		for pressed in [[true, false], [false, true]]:
			var m := RouterScript.merge_local(_intent({k: pressed[0]}), _intent({k: pressed[1]}))
			assert_bool(m[k]).override_failure_message("'%s' lost a one-sided press" % k).is_true()
		assert_bool(RouterScript.merge_local(_intent({k: false}), _intent({k: false}))[k]) \
			.override_failure_message("'%s' fired with neither side pressed" % k).is_false()


## What sloppyCAN mirrors verbatim through `arbitrate_bridge`: [key, sent, VehicleInput field
## (a property path), the field with the key absent]. A sent value lands as sent, and an absent
## key reads its rest state, never a hold of the last value. Rows with more than that (a scale, a
## clamp, a sentinel's reason) keep it in their own test below.
const BRIDGE_MIRRORS := [
	# The horn: absent → silent.
	["horn", true, "horn", false],
	# ISOBUS (tractor): absent → off, open diff, 2WD, 540, valve closed.
	["pto", true, "pto", false],
	["diff_lock", true, "diff_lock", false],
	["fwd_drive", true, "fwd_drive", false],
	["pto_mode", 1, "pto_mode", 0],
	["scv_flow", 0.5, "scv_flow", 0.0],
	["hand_throttle", 0.5, "hand_throttle", 0.0],
	# Flight: absent → neutral, disarmed (no local toggle on this path), retracted.
	["elevator", 0.5, "elevator", 0.0],
	["climb", -0.5, "climb", 0.0],
	["arm", true, "arm", false],
	["flaps", 0.25, "flaps", 0.0],
	["flight_mode", 1, "flight_mode", 0],
	["hardpoint_cmd", true, "hardpoint_cmd", false],
	["gimbal_pitch", -30.0, "gimbal_pitch", 0.0],
	["gimbal_yaw", 45.0, "gimbal_yaw", 0.0],
	# A failure mask: no clamp, no debounce, and absent is a healthy bus.
	["node_fail", 0b1000_0001, "node_fail", 0],
	# Lamp and warning bits, no local timer: an absent bit is off.
	["turnL", true, "lamps:turn_left", false],
	["turnR", true, "lamps:turn_right", false],
	["brakeLamp", true, "lamps:brake_lamp", false],
	["checkEngine", true, "lamps:check_engine", false],
	["battery", true, "lamps:battery_warn", false],
	["beacon", true, "lamps:beacon", false],
	["strobe", true, "lamps:strobe", false],
	["led", 2, "lamps:led", 0],
	["beep", true, "lamps:beep", false],
	["red_stop", true, "lamps:red_stop", false],
	["amber_warn", true, "lamps:amber_warn", false],
	["protect_lamp", true, "lamps:protect_lamp", false],
	["trailer_ebs_fault", true, "lamps:trailer_ebs_fault", false],
	["trailer_abs_lamp", true, "lamps:trailer_abs_lamp", false],
	# Train: absent → lowered, shut.
	["pantograph", true, "pantograph", false],
	["doors", true, "doors", false],
	# J1939: absent → released. The refuse body (CiA 422): absent → Idle, the safe pose.
	["retarder", 0.5, "retarder", 0.0],
	["body_cmd", 2, "body_cmd", 0],
	# Boat: absent → standing by with NO course commanded. 0 would be a bearing (due north) the
	# pilot would silently steer to; that is why bridge_source writes the key only when sent.
	["nav_mode", 1, "nav_mode", 0],
	["sheet", 0.5, "sheet", 0.0],
	["heading_cmd", 275.0, "heading_cmd", VehicleInput.HEADING_CMD_NONE],
]


func test_the_bridge_mirrors_each_key_as_sent_and_absent_reads_its_rest_state() -> void:
	for row: Array in BRIDGE_MIRRORS:
		var key: String = row[0]
		var field := NodePath(row[2])
		var absent := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
		absent.erase(key)   # `_bridge` writes a few keys (the horn) itself
		var bare: VehicleInput = RouterScript.arbitrate_bridge(absent)
		assert_that(bare.get_indexed(field)) \
			.override_failure_message("absent '%s': %s is %s, not its rest state %s"
					% [key, field, bare.get_indexed(field), row[3]]) \
			.is_equal(row[3])
		var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
		vals[key] = row[1]
		var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
		assert_that(out.get_indexed(field)) \
			.override_failure_message("sent '%s' = %s: %s is %s"
					% [key, row[1], field, out.get_indexed(field)]) \
			.is_equal(row[1])


## Contract "in" signals that are not a plain mirror, each with its reason. bridge_source writes
## every in-signal under its contract name, so a BRIDGE_MIRRORS key is that name.
const BRIDGE_NOT_MIRRORS := {
	"accel": "a driving field: gated by the key and owned by the gear's direction",
	"brake": "a driving field: owned by the gear's direction and the brake override",
	"steer": "a driving field, overridden by rudder or guidance when present",
	"handbrake": "a driving field, clamped (test_bridge_steer_and_handbrake_pass_through)",
	"key": "a driving field: it gates the throttle (test_throttle_zero_unless_key_ignition)",
	"lights": "a driving field and a level, not a bit: absent reads 1",
	"gear": "a driving field, read as PRND or an exact byte (test_manual_bridge_gear_*)",
	"hitch_pos": "scaled /100, and absent is raised (test_bridge_maps_hitch_percent)",
	"tcs_off": "folded with esc_off (test_tcs_off_absent_means_on_on_both_paths)",
	"esc_off": "takes tcs_off with it (test_tcs_off_absent_means_on_on_both_paths)",
	"rudder": "presence overrides steer (test_bridge_rudder_overrides_steer_when_present)",
	"guidance_curvature": "presence overrides steer; absent is a sentinel (test_bridge_guidance_*)",
}


func test_every_contract_in_signal_is_a_mirror_row_or_a_named_exception() -> void:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var data := ContractScript.ContractData.parse(file.get_as_text())
	var rows := {}
	for row: Array in BRIDGE_MIRRORS:
		rows[row[0]] = true
	var seen := 0
	for sig in data.signals:
		if sig.dir != "in":
			continue
		seen += 1
		assert_bool(rows.has(sig.name) or BRIDGE_NOT_MIRRORS.has(sig.name)) \
			.override_failure_message("in-signal '%s' is neither a BRIDGE_MIRRORS row nor in " % sig.name
					+ "BRIDGE_NOT_MIRRORS, so nothing pins what the bridge does with it") \
			.is_true()
		assert_bool(rows.has(sig.name) and BRIDGE_NOT_MIRRORS.has(sig.name)) \
			.override_failure_message("'%s' is both a mirror row and an exception" % sig.name) \
			.is_false()
	assert_int(seen).is_greater(0)
	# And the other way: a row or an exception naming no in-signal tests a key nobody sends.
	for key: String in rows.keys() + BRIDGE_NOT_MIRRORS.keys():
		assert_bool(data.has_signal_def(key, "in")) \
			.override_failure_message("'%s' is not a contract in-signal" % key).is_true()


# --- ISOBUS implement (tractor) -----------------------------------------------

func test_bridge_maps_hitch_percent() -> void:
	# hitch_pos arrives 0..100 (bridge_source keeps contract units); arbitrate_bridge /100.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["hitch_pos"] = 40.0
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.hitch_request).is_equal_approx(0.4, 1e-4)
	# Absent → raised (1.0), the §6 default-off convention.
	var bare: VehicleInput = RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1))
	assert_float(bare.hitch_request).is_equal(1.0)


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


# --- ISOBUS driveline (tractor: diff lock, MFWD, PTO mode) ---------------------

func test_tcs_off_absent_means_on_on_both_paths() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["tcs_off"] = true
	assert_bool(RouterScript.arbitrate_bridge(vals).tcs_off).is_true()
	assert_bool(RouterScript.arbitrate_bridge(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)).tcs_off) \
			.is_false()
	# Local: the router writes the player's TRACTION CONTROL setting into the raw dict.
	assert_bool(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).tcs_off).is_false()
	var raw := _raw()
	raw["tcs_off"] = true
	assert_bool(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).tcs_off).is_true()


func test_esc_off_takes_tc_with_it_and_tc_off_leaves_esc_on() -> void:
	# ESC off turns TC off too, as a car's long press does; TC off alone leaves ESC on. Absent, both
	# are on.
	var plain := RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1)
	assert_bool(plain.esc_off).is_false()
	var raw := _raw()
	raw["esc_off"] = true
	var esc_off := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(esc_off.esc_off).is_true()
	assert_bool(esc_off.tcs_off).is_true()
	raw = _raw()
	raw["tcs_off"] = true
	assert_bool(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).esc_off).is_false()
	# On the bridge: absent → on; sent, ESC off with TC; the local setting never reaches it, in
	# fallback too.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	assert_bool(RouterScript.arbitrate_bridge(vals).esc_off).is_false()
	assert_bool(RouterScript.blend_local_driving(vals, esc_off).esc_off).is_false()
	vals["esc_off"] = true
	var bridged := RouterScript.arbitrate_bridge(vals)
	assert_bool(bridged.esc_off).is_true()
	assert_bool(bridged.tcs_off).is_true()


func test_lab_abs_off_takes_esc_and_tc_with_it_on_local_input_only() -> void:
	# Absent, ABS is on; the LAB's ABS off takes ESC with it, and ESC takes TC.
	assert_bool(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).abs_off).is_false()
	var raw := _raw()
	raw["abs_off"] = true
	var off := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(off.abs_off).is_true()
	assert_bool(off.esc_off).is_true()
	assert_bool(off.tcs_off).is_true()
	# No contract signal: the bridge never carries it, a stray key included, nor does fallback.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["abs_off"] = true
	var bridged := RouterScript.arbitrate_bridge(vals)
	assert_bool(bridged.abs_off).is_false()
	assert_bool(bridged.esc_off).is_false()
	assert_bool(RouterScript.blend_local_driving(vals, off).abs_off).is_false()


const LAB_CAPS := {"abs": true, "axle_diff": true, "ackermann": true}


func test_the_lab_switches_pass_on_a_fitted_body() -> void:
	var lab := RouterScript.lab_raw(true, VehicleInput.AxleDiff.OPEN, true, LAB_CAPS, false)
	assert_bool(lab[&"abs_off"]).is_true()
	assert_int(lab[&"axle_diff"]).is_equal(VehicleInput.AxleDiff.OPEN)
	assert_bool(lab[&"parallel_steer"]).is_true()
	lab = RouterScript.lab_raw(false, VehicleInput.AxleDiff.STOCK, false, LAB_CAPS, false)
	assert_bool(lab[&"abs_off"]).is_false()
	assert_bool(lab[&"parallel_steer"]).is_false()


func test_the_lab_switches_never_reach_a_challenge() -> void:
	# Under the challenge lock (dev keys included) the attempt drives the stock hardware.
	var lab := RouterScript.lab_raw(true, VehicleInput.AxleDiff.LOCKED, true, LAB_CAPS, true)
	assert_bool(lab[&"abs_off"]).is_false()
	assert_int(lab[&"axle_diff"]).is_equal(VehicleInput.AxleDiff.STOCK)
	assert_bool(lab[&"parallel_steer"]).is_false()


func test_a_lab_switch_kept_through_a_body_change_never_acts_on_missing_hardware() -> void:
	# ABS off on the sedan, then the race (TC, no ABS): its TC stays on.
	var lab := RouterScript.lab_raw(true, VehicleInput.AxleDiff.LOCKED, true, {}, false)
	assert_bool(lab[&"abs_off"]).is_false()
	assert_int(lab[&"axle_diff"]).is_equal(VehicleInput.AxleDiff.STOCK)
	assert_bool(lab[&"parallel_steer"]).is_false()
	var raw := _raw()
	raw.merge(lab, true)
	var out := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(out.esc_off).is_false()
	assert_bool(out.tcs_off).is_false()


func test_a_lab_locked_axle_takes_esc_and_tc_with_it() -> void:
	var raw := _raw()
	raw["axle_diff"] = VehicleInput.AxleDiff.LOCKED
	var locked := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(locked.esc_off).is_true()
	assert_bool(locked.tcs_off).is_true()
	raw["axle_diff"] = VehicleInput.AxleDiff.OPEN
	var open := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(open.esc_off).is_false()
	assert_bool(open.tcs_off).is_false()
	assert_str(RouterScript.lab_esc_cause(true, VehicleInput.AxleDiff.LOCKED)).is_equal("ABS")
	assert_str(RouterScript.lab_esc_cause(false, VehicleInput.AxleDiff.LOCKED)) \
			.is_equal("LOCKED DIFFS")
	assert_str(RouterScript.lab_esc_cause(false, VehicleInput.AxleDiff.OPEN)).is_empty()


func test_the_lab_cascade_reaches_a_bridge_input_the_measure_tools_set() -> void:
	var input := VehicleInput.new()
	input.abs_off = true
	RouterScript.lab_cascade(input)
	assert_bool(input.esc_off).is_true()
	assert_bool(input.tcs_off).is_true()
	var stock := VehicleInput.new()
	RouterScript.lab_cascade(stock)
	assert_bool(stock.esc_off).is_false()
	assert_bool(stock.tcs_off).is_false()


func test_lab_axle_diff_reaches_local_input_only_and_never_a_challenge() -> void:
	assert_int(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).axle_diff) \
			.is_equal(VehicleInput.AxleDiff.STOCK)
	var raw := _raw()
	raw["axle_diff"] = VehicleInput.AxleDiff.LOCKED
	var locked := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_int(locked.axle_diff).is_equal(VehicleInput.AxleDiff.LOCKED)
	# No contract signal: the bridge never carries it, a stray key included, nor does fallback.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["axle_diff"] = VehicleInput.AxleDiff.LOCKED
	assert_int(RouterScript.arbitrate_bridge(vals).axle_diff).is_equal(VehicleInput.AxleDiff.STOCK)
	assert_int(RouterScript.blend_local_driving(vals, locked).axle_diff) \
			.is_equal(VehicleInput.AxleDiff.STOCK)


func test_lab_parallel_steer_reaches_local_input_only() -> void:
	assert_bool(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).parallel_steer).is_false()
	var raw := _raw()
	raw["parallel_steer"] = true
	var parallel := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(parallel.parallel_steer).is_true()
	# No contract signal: the bridge never carries it, a stray key included, nor does fallback.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["parallel_steer"] = true
	assert_bool(RouterScript.arbitrate_bridge(vals).parallel_steer).is_false()
	assert_bool(RouterScript.blend_local_driving(vals, parallel).parallel_steer).is_false()


func test_fallback_takes_tcs_off_from_the_bridge() -> void:
	# A live bridge with no driving control owns `tcs_off`: the local setting is not a driving field.
	var raw := _raw()
	raw["tcs_off"] = true
	var local := RouterScript.arbitrate_local(raw, 0.0, GEAR_D1)
	assert_bool(RouterScript.blend_local_driving(_bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1), local)
			.tcs_off).is_false()


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


func test_bridge_clamps_the_flight_axes() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["climb"] = 1.6      # out of range on purpose
	vals["elevator"] = -2.0
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.climb).is_equal(1.0)
	assert_float(out.elevator).is_equal(-1.0)


func test_merge_local_combines_flight_axes() -> void:
	var kbd: Dictionary[StringName, Variant] = {"elevator": 0.5, "climb": 0.0}
	var touch: Dictionary[StringName, Variant] = {"elevator": 0.8, "climb": -0.3}
	var m := RouterScript.merge_local(kbd, touch)
	assert_float(m["elevator"]).is_equal(1.0)  # 0.5 + 0.8 clamped
	assert_float(m["climb"]).is_equal_approx(-0.3, 1e-6)
	# Neither sent → axes 0.
	assert_float(RouterScript.merge_local({}, {})["elevator"]).is_equal(0.0)


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


func test_bridge_flaps_clamped() -> void:
	# Already %→unit normalized by bridge_source; the bridge value is authoritative.
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["flaps"] = 1.7  # out of range on purpose
	assert_float(RouterScript.arbitrate_bridge(vals).flaps).is_equal(1.0)


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


func test_bridge_guidance_curvature_absent_is_sentinel() -> void:
	# No guidance command → VehicleInput carries the "nobody's holding the auto-steer wheel"
	# sentinel, not a legal curvature (0 is dead-straight and a real command).
	var out: VehicleInput = RouterScript.arbitrate_bridge(
			_bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1))
	assert_float(out.guidance_curvature).is_equal(VehicleInput.GUIDANCE_CURVATURE_NONE)


func test_bridge_guidance_curvature_carries_through_when_present() -> void:
	# bridge_source writes the raw curvature (1/km) alongside the steer-unit 'guidance' key;
	# arbitrate_bridge carries it onto VehicleInput verbatim for WheelDrive to use.
	var vals := _bridge(0.0, 0.0, 0.9, 0.0, GEAR_D1)
	vals["guidance"] = -0.4
	vals["guidance_curvature"] = -50.8
	var out: VehicleInput = RouterScript.arbitrate_bridge(vals)
	assert_float(out.guidance_curvature).is_equal_approx(-50.8, 1e-6)
	# Dead straight (0) is a real command and must not read as the sentinel.
	vals["guidance_curvature"] = 0.0
	assert_float(RouterScript.arbitrate_bridge(vals).guidance_curvature).is_equal(0.0)


func test_bridge_source_clamps_guidance_curvature_to_full_lock() -> void:
	# The raw curvature key is clamped to the wire's +-127 1/km i8, same ceiling as the
	# steer-unit conversion, so WheelDrive never asks for more angle than sloppyCAN could
	# legally have sent.
	var src := BridgeSourceScript.new()
	Bridge.set("_active", true)
	Bridge.set("_inbound", {"guidance_curvature": 500.0})
	var out := src.poll()
	assert_float(float(out["guidance_curvature"])).is_equal(BridgeSourceScript.FULL_LOCK_CURVATURE)
	Bridge.set("_inbound", {"guidance_curvature": -500.0})
	out = src.poll()
	assert_float(float(out["guidance_curvature"])).is_equal(-BridgeSourceScript.FULL_LOCK_CURVATURE)


func test_bridge_source_survives_non_numeric_json() -> void:
	# JSON.stringify turns a NaN into null, and the inbound side is not origin-gated, so a value
	# can arrive as null or an Array. Each reads as the field's default, with no engine error.
	var src := BridgeSourceScript.new()
	Bridge.set("_active", true)
	Bridge.set("_inbound", {"accel": null, "steer": [1], "horn": [1], "gear": "x", "key": {}})
	var out: Dictionary[StringName, Variant] = {}
	await assert_error(func() -> void: out.merge(src.poll())).is_success()
	assert_float(float(out["accel"])).is_equal(0.0)
	assert_float(float(out["steer"])).is_equal(0.0)
	assert_bool(out["horn"]).is_false()
	assert_int(out["gear"]).is_equal(0)
	assert_int(out["key"]).is_equal(3)


func test_bridge_runs_under_a_paused_tree_and_the_router_does_not() -> void:
	assert_int(Bridge.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_int(InputRouter.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


func test_bridge_scv_flow_clamped() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["scv_flow"] = 1.8   # bridge_source already did the %→unit
	assert_float(RouterScript.arbitrate_bridge(vals).scv_flow).is_equal(1.0)


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


func test_bridge_retarder_clamped() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_D1)
	vals["retarder"] = 1.8   # bridge_source already did the %→unit
	assert_float(RouterScript.arbitrate_bridge(vals).retarder).is_equal(1.0)


func test_local_has_no_retarder() -> void:
	# No local stalk: released (never guessed).
	var raw := _raw()
	raw["retarder"] = 0.9   # even if a source invented the key
	assert_float(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).retarder).is_equal(0.0)


func test_local_dm1_lamps_stay_dark() -> void:
	# No local source at all, like turnL/turnR — a fault lamp with no fault behind it would be
	# a fiction, and blinking one from a local clock is forbidden outright.
	var out: VehicleInput = RouterScript.arbitrate_local(_raw(0.0, 1.0), 10.0, GEAR_D1)
	assert_bool(out.lamps.red_stop).is_false()
	assert_bool(out.lamps.amber_warn).is_false()
	assert_bool(out.lamps.protect_lamp).is_false()


func test_the_trailer_fault_lamp_has_no_local_source() -> void:
	# ISO 11992's only "in" signal, and it follows the DM1 rule exactly: sloppyCAN is the sole
	# authority (BRIDGE_MIRRORS), and there is no key, no toggle and no timer behind it. A
	# trailer fault the game invented for itself would be a fiction, even if a source invented the key.
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


## A touch source pressing only the body-command stalk, one edge per poll.
class _StalkTouch extends RefCounted:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"body_cmd_toggle": true}


## No bridge connected: the local sources drive.
class _NoBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {}


func test_the_local_stalk_cycles_through_every_command_and_wraps() -> void:
	# Cycled, not flipped: the whole reason InputRouter owns a byte here rather than a bool.
	var router := _router()
	router.set_touch_source(_StalkTouch.new())
	router._bridge_source = _NoBridge.new()
	var seen := {}
	for i in RouterScript.BODY_CMD_COUNT:
		router._physics_process(1.0 / 60.0)
		var cmd: int = router.get_vehicle_input().body_cmd
		assert_int(cmd).override_failure_message("press %d did not advance the stalk" % (i + 1)) \
			.is_equal((i + 1) % RouterScript.BODY_CMD_COUNT)
		seen[cmd] = true
	assert_int(seen.size()) \
		.override_failure_message("the cycle does not reach every command").is_equal(
			RouterScript.BODY_CMD_COUNT)
	router._physics_process(1.0 / 60.0)
	assert_int(router.get_vehicle_input().body_cmd) \
		.override_failure_message("the cycle must wrap past Idle").is_equal(1)


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


func test_local_node_fail_rides_the_vehicle_input() -> void:
	var raw := _raw()
	raw["node_fail"] = 0b0100
	assert_int(RouterScript.arbitrate_local(raw, 0.0, GEAR_D1).node_fail).is_equal(0b0100)
	# Absent (every vehicle that is not the drone, and a drone with a healthy bus): 0, which
	# is every node online — the same "absent = the harmless state" rule the lamp bits follow.
	assert_int(RouterScript.arbitrate_local(_raw(), 0.0, GEAR_D1).node_fail).is_equal(0)


func test_a_new_body_clears_the_node_failure_but_not_the_other_toggles() -> void:
	var router := _router()
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


func test_a_new_body_clears_the_autopilot() -> void:
	# A new hull must not spawn with an engaged pilot steering to the last boat's course.
	var router := _router()
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


# --- the brake override: both pedals held, the brake wins once the body moves -----------------

static func _both(gear := GEAR_D1) -> VehicleInput:
	var out := VehicleInput.new()
	out.throttle = -1.0 if gear == GEAR_R else 1.0
	out.brake = 1.0
	out.gear_request = gear
	return out


func test_a_standstill_press_revs_and_a_moving_one_latches_the_cut() -> void:
	assert_bool(RouterScript.brake_override(false, _both(), 0.0)).is_false()
	var over := RouterScript.BRAKE_OVERRIDE_SPEED + 0.01
	assert_bool(RouterScript.brake_override(false, _both(), over)).is_true()
	assert_bool(RouterScript.brake_override(false, _both(GEAR_R), -over)).is_true()
	# Latched, it holds down to a standstill, where the brakes then hold the body.
	assert_bool(RouterScript.brake_override(true, _both(), 0.0)).is_true()


func test_the_cut_clears_when_either_pedal_lifts_and_never_latches_in_neutral() -> void:
	var off_brake := _both()
	off_brake.brake = 0.0
	var off_gas := _both()
	off_gas.throttle = 0.0
	for input: VehicleInput in [off_brake, off_gas, _both(GEAR_N)]:
		assert_bool(RouterScript.brake_override(true, input, 5.0)).is_false()


# --- the auto hold: keys and touch at a standstill in gear ----------------------------------

static func _idle(gear := GEAR_D1, throttle := 0.0) -> VehicleInput:
	var out := VehicleInput.new()
	out.gear_request = gear
	out.throttle = throttle
	return out


func test_the_auto_hold_latches_at_a_standstill_in_d_or_r_with_no_throttle() -> void:
	assert_bool(RouterScript.auto_hold(false, _idle(), 0.0, false)).is_true()
	assert_bool(RouterScript.auto_hold(false, _idle(GEAR_R), -0.2, false)).is_true()
	assert_bool(RouterScript.auto_hold(false, _idle(3), RouterScript.REVERSE_ENGAGE_SPEED,
			false)).is_true()


func test_the_auto_hold_never_latches_moving_out_of_gear_or_under_the_pad() -> void:
	var moving := RouterScript.REVERSE_ENGAGE_SPEED + 0.01
	assert_bool(RouterScript.auto_hold(false, _idle(), moving, false)).is_false()
	assert_bool(RouterScript.auto_hold(false, _idle(GEAR_N), 0.0, false)).is_false()
	assert_bool(RouterScript.auto_hold(false, _idle(RouterScript.GEAR_P), 0.0, false)).is_false()
	assert_bool(RouterScript.auto_hold(false, _idle(), 0.0, true)).is_false()
	assert_bool(RouterScript.auto_hold(true, _idle(), 0.0, true)).is_false()


func test_the_auto_hold_keeps_what_it_caught_until_the_throttle_asks_to_move() -> void:
	# A body its brakes cannot hold slides, and stays held.
	assert_bool(RouterScript.auto_hold(true, _idle(), 3.0, false)).is_true()
	assert_bool(RouterScript.auto_hold(true, _idle(GEAR_D1, 0.1), 0.0, false)).is_false()
	assert_bool(RouterScript.auto_hold(true, _idle(GEAR_R, -0.1), 0.0, false)).is_false()
	assert_bool(RouterScript.auto_hold(true, _idle(GEAR_N), 0.0, false)).is_false()


func test_the_auto_hold_stands_aside_with_the_lab_abs_off() -> void:
	# It holds through the ABS modulator, as hill-start assist does; `abs_off` arrives fitment-gated.
	var off := _idle()
	off.abs_off = true
	assert_bool(RouterScript.auto_hold(false, off, 0.0, false)).is_false()
	assert_bool(RouterScript.auto_hold(true, off, 0.0, false)).is_false()


func test_the_last_pedal_device_decides_whether_the_pad_drives() -> void:
	assert_bool(RouterScript.pad_drives_pedals(false, 0.0, 0.3)).is_true()
	assert_bool(RouterScript.pad_drives_pedals(true, 0.5, 0.0)).is_false()
	assert_bool(RouterScript.pad_drives_pedals(false, 0.5, 0.5)).is_true()
	# Neither pedal down: the last device stands.
	assert_bool(RouterScript.pad_drives_pedals(true, 0.0, 0.0)).is_true()
	assert_bool(RouterScript.pad_drives_pedals(false, 0.0, 0.0)).is_false()


## A live bridge in D with every pedal up.
class _IdleBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"drive_sourced": true, &"accel": 0.0, &"brake": 0.0,
				&"gear": GEAR_D1, &"key": RouterScript.KEY_IGNITION}


func test_the_auto_hold_is_off_by_default_and_never_latches_while_off() -> void:
	var router := _router()
	var body: _RollingBody = auto_free(_RollingBody.new())
	router.register_vehicle(body)
	assert_bool(router.auto_hold_on()).is_false()
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().brake).is_equal(0.0)
	assert_bool(router.auto_hold_holding()).is_false()
	# Switched off while holding, it lets go at once.
	router.set_auto_hold_on(true)
	router._physics_process(1.0 / 60.0)
	assert_bool(router.auto_hold_holding()).is_true()
	router.set_auto_hold_on(false)
	assert_bool(router.auto_hold_holding()).is_false()
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().brake).is_equal(0.0)


func test_the_local_path_holds_the_brake_at_a_standstill_and_the_bridge_creeps() -> void:
	var router := _router()
	router.set_auto_hold_on(true)
	var body: _RollingBody = auto_free(_RollingBody.new())
	router.register_vehicle(body)
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().brake).is_equal(RouterScript.AUTO_HOLD_BRAKE)
	assert_bool(router.get_vehicle_input().lamps.brake_lamp).is_true()
	# A body whose engine drives no road wheel (a drone's pedals are a stick) never gets it.
	body.holds = false
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().brake).is_equal(0.0)
	body.holds = true
	router._bridge_source = _IdleBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().brake).is_equal(0.0)


## A body the test rolls by hand: the router reads only these off a registered vehicle.
class _RollingBody extends Node3D:
	var speed := 0.0
	var holds := true  ## an engine that drives road wheels (`key_auto_hold`)
	func get_speed() -> float:
		return speed
	func key_steer_speed() -> float:
		return speed
	func get_gear_byte() -> int:
		return RouterScript.GEAR_D1
	func key_pedals_are_a_stick() -> bool:
		return false
	func key_auto_hold() -> bool:
		return holds


class _BothPedalsBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"drive_sourced": true, &"accel": 1.0, &"brake": 1.0,
				&"gear": GEAR_D1, &"key": RouterScript.KEY_IGNITION}


func test_the_router_cuts_the_throttle_once_a_braked_body_creeps() -> void:
	var router := _router()
	router._bridge_source = _BothPedalsBridge.new()
	var body: _RollingBody = auto_free(_RollingBody.new())
	router.register_vehicle(body)
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().throttle).is_equal(1.0)
	body.speed = RouterScript.BRAKE_OVERRIDE_SPEED + 0.5
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().throttle).is_equal(0.0)
	assert_float(router.get_vehicle_input().brake).is_equal(1.0)
	body.speed = 0.0
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().throttle).is_equal(0.0)


## A bridge that is live and sending full throttle in D1.
class _LiveBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"drive_sourced": true, &"accel": 1.0, &"gear": GEAR_D1,
				&"key": RouterScript.KEY_IGNITION}


## A bridge that is live but carries no driving control (non-RAMN traffic). It sends key Lock so
## a test can see fallback ignore the bridge's key, and it commands the refuse body.
class _QuietBridge extends BridgeSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"active": true, &"drive_sourced": false, &"key": RouterScript.KEY_LOCK,
				&"body_cmd": 2}


## Kept out of the tree so no real physics tick runs between the steps a test makes by hand.
func _locked_router(touch: _CountingTouch) -> Node:
	var router := _router()
	router._dev_keys = false
	router.set_touch_source(touch)
	router.set_bridge_only(true)
	return router


func test_the_locked_idle_is_key_lock_in_p_with_the_handbrake_on() -> void:
	var out: VehicleInput = RouterScript.locked_idle()
	assert_int(out.key).is_equal(RouterScript.KEY_LOCK)
	assert_float(out.handbrake).is_equal(1.0)
	assert_float(out.throttle).is_equal(0.0)
	assert_float(out.brake).is_equal(0.0)
	assert_float(out.steer).is_equal(0.0)
	assert_int(out.gear_request).is_equal(RouterScript.GEAR_P)


func test_bridge_only_never_polls_local_or_touch() -> void:
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(0)
	var out: VehicleInput = router.get_vehicle_input()
	assert_int(out.key).is_equal(RouterScript.KEY_LOCK)
	assert_float(out.handbrake).is_equal(1.0)
	assert_float(out.throttle).is_equal(0.0)
	# Lifting the lock hands driving straight back to the local sources (the pedal key ramps in,
	# KeyShaper, so any throttle at all is the hand-back).
	router.set_bridge_only(false)
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(1)
	assert_float(router.get_vehicle_input().throttle).is_greater(0.0)


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


func test_a_quiet_bridge_under_the_lock_still_owns_the_vehicle() -> void:
	# A challenge: no driving controls until the player sends them is the expected state (S8).
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._bridge_source = _QuietBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(0)
	assert_bool(router.bridge_drives()).is_true()
	assert_float(router.get_vehicle_input().throttle).is_equal(0.0)
	assert_int(router.get_vehicle_input().key).is_equal(RouterScript.KEY_LOCK)


# --- fallback: a live bridge with no driving controls -------------------------------

func test_drive_sourced_is_the_presence_of_a_driving_control() -> void:
	assert_bool(BridgeSourceScript.drive_sourced({})).is_false()
	assert_bool(BridgeSourceScript.drive_sourced({"beacon": 1, "strobe": 0, "key": 3})).is_false()
	for control in ["accel", "brake", "steer"]:
		assert_bool(BridgeSourceScript.drive_sourced({control: 0})).is_true()


func test_a_quiet_bridge_hands_the_driving_group_to_local() -> void:
	var touch := _CountingTouch.new()
	var router := _router()
	router.set_touch_source(touch)
	router._bridge_source = _QuietBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(1)
	assert_bool(router.bridge_drives()).is_false()
	var out: VehicleInput = router.get_vehicle_input()
	assert_int(out.key).is_equal(RouterScript.KEY_IGNITION)
	assert_float(out.throttle).is_greater(0.0)  # local drives; the pedal key ramps (KeyShaper)
	assert_int(out.body_cmd).is_equal(2)
	# A driving control arriving hands the vehicle straight back to the bridge.
	router._bridge_source = _LiveBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_bool(router.bridge_drives()).is_true()
	assert_int(router.get_vehicle_input().body_cmd).is_equal(0)


func test_the_blend_takes_the_driving_group_from_local_and_the_rest_from_the_bridge() -> void:
	var vals := _bridge(0.0, 0.0, 0.0, 0.0, GEAR_N, RouterScript.KEY_LOCK)
	vals["body_cmd"] = 1
	vals["hitch_pos"] = 20.0
	vals["red_stop"] = true
	vals["pto"] = true
	var raw := _raw(0.8, 0.0, -0.5, 1.0)
	raw["lights"] = 3
	raw["horn"] = true
	raw["arm"] = true
	raw["climb"] = 0.4
	raw["elevator"] = -0.3
	var local: VehicleInput = RouterScript.arbitrate_local(raw, 0.0, GEAR_N)
	var out: VehicleInput = RouterScript.blend_local_driving(vals, local, true)
	assert_float(out.throttle).is_equal_approx(0.8, 1e-6)
	assert_float(out.steer).is_equal(-0.5)
	assert_float(out.handbrake).is_equal(1.0)
	assert_int(out.key).is_equal(RouterScript.KEY_IGNITION)
	assert_int(out.gear_request).is_equal(GEAR_D1)
	# Local always drives automatic, even with the manual gearbox selected.
	assert_bool(out.gear_auto).is_true()
	assert_int(out.lights).is_equal(3)
	assert_bool(out.horn).is_true()
	assert_bool(out.arm).is_true()
	assert_float(out.climb).is_equal_approx(0.4, 1e-6)
	assert_float(out.elevator).is_equal_approx(-0.3, 1e-6)
	# Everything outside the group stays the bridge's.
	assert_int(out.body_cmd).is_equal(1)
	assert_float(out.hitch_request).is_equal_approx(0.2, 1e-6)
	assert_bool(out.lamps.red_stop).is_true()
	assert_bool(out.pto).is_true()


## A touch stand-in pressing every edge on one tick.
class _EveryEdgeTouch extends RefCounted:
	func poll() -> Dictionary[StringName, Variant]:
		return {&"lights_cycle": true, &"arm_toggle": true, &"pto_toggle": true,
				&"flight_mode_cycle": true, &"node_fail_cycle": true}


func test_fallback_advances_only_the_driving_toggles() -> void:
	# A PTO or flight-mode edge the bridge still owns must not latch unseen and apply the moment
	# the bridge goes away.
	var router := _router()
	router.set_touch_source(_EveryEdgeTouch.new())
	router._bridge_source = _QuietBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_int(router._lights).is_equal(2)
	assert_bool(router._armed).is_true()
	assert_bool(router._pto).is_false()
	assert_int(router._flight_mode).is_equal(0)
	assert_int(router._node_fail).is_equal(0)


func test_the_blend_leaves_a_bridge_steer_override_on_the_wheel() -> void:
	var local: VehicleInput = RouterScript.arbitrate_local(_raw(0.5, 0.0, -1.0), 0.0, GEAR_N)
	var vals := _bridge()
	vals["guidance"] = 0.25
	assert_float(RouterScript.blend_local_driving(vals, local).steer).is_equal(0.25)
	vals = _bridge()
	vals["rudder"] = -0.75
	assert_float(RouterScript.blend_local_driving(vals, local).steer).is_equal(-0.75)


func test_the_dev_override_lets_local_drive_under_the_lock() -> void:
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._dev_keys = true
	router._physics_process(1.0 / 60.0)
	assert_int(touch.polls).is_equal(1)
	assert_float(router.get_vehicle_input().throttle).is_greater(0.0)


func test_the_dev_override_lets_local_drive_under_the_lock_with_a_merely_connected_bridge() -> void:
	# A bridge that is live but sends no accel/brake/steer (only lamps/DM1) must not force
	# bridge_drives just because bridge_only is on — the dev override still wins.
	var touch := _CountingTouch.new()
	var router := _locked_router(touch)
	router._dev_keys = true
	router._bridge_source = _QuietBridge.new()
	router._physics_process(1.0 / 60.0)
	assert_bool(router.bridge_drives()).is_false()
	assert_int(touch.polls).is_equal(1)
	assert_float(router.get_vehicle_input().throttle).is_greater(0.0)


# --- the hand throttle ------------------------------------------------------------------------

func test_the_hand_throttle_steps_clamp_and_the_preset_sets_and_clears() -> void:
	var step := RouterScript.HAND_THROTTLE_STEP
	assert_float(RouterScript.hand_throttle_step(0.0, false, true, false, NAN)).is_equal_approx(step, 1e-9)
	assert_float(RouterScript.hand_throttle_step(0.0, true, false, false, NAN)).is_equal(0.0)
	assert_float(RouterScript.hand_throttle_step(0.95, false, true, false, NAN)).is_equal(1.0)
	# The preset sets the machine's figure, and a second press drops it to 0.
	assert_float(RouterScript.hand_throttle_step(0.2, false, false, true, 0.69)).is_equal(0.69)
	assert_float(RouterScript.hand_throttle_step(0.69, false, false, true, 0.69)).is_equal(0.0)
	# A body with no preset (NAN) leaves it alone.
	assert_float(RouterScript.hand_throttle_step(0.3, false, false, true, NAN)).is_equal(0.3)


func test_the_hand_throttle_rides_the_input_from_either_source() -> void:
	var local: VehicleInput = RouterScript.arbitrate_local(_intent({"hand_throttle": 0.4}), 0.0,
			GEAR_D1)
	assert_float(local.hand_throttle).is_equal_approx(0.4, 1e-9)
	# The bridge's value is mirrored; absent reads 0, never the local latch.
	var vals := _bridge()
	assert_float(RouterScript.arbitrate_bridge(vals).hand_throttle).is_equal(0.0)
	vals["hand_throttle"] = 0.7
	assert_float(RouterScript.arbitrate_bridge(vals).hand_throttle).is_equal_approx(0.7, 1e-9)
	# In fallback it stays the bridge's (not the driving group), and its local edges are dropped.
	assert_float(RouterScript.blend_local_driving(vals, local).hand_throttle).is_equal_approx(0.7, 1e-9)
	var edges := RouterScript.driving_edges_only(_intent({"hand_throttle_up_cycle": true,
			"hand_throttle_down_cycle": true, "hand_throttle_pto_toggle": true}))
	assert_bool(edges.is_empty()).is_true()


## A touch source that taps the hand throttle's PTO preset once.
class _PresetTap extends RefCounted:
	var taps := 1

	func poll() -> Dictionary[StringName, Variant]:
		var tap := taps > 0
		taps -= 1
		return {&"hand_throttle_pto_toggle": tap}


## `_RollingBody` that answers the PTO preset probe, as a tractor does.
class _PresetBody extends _RollingBody:
	func pto_hand_throttle() -> float:
		return 0.69


func test_the_preset_edge_asks_the_machine_and_the_latch_is_driver_state() -> void:
	var router := _router()
	var body: _PresetBody = auto_free(_PresetBody.new())
	router.register_vehicle(body)
	var touch := _PresetTap.new()
	router.set_touch_source(touch)
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().hand_throttle).is_equal_approx(0.69, 1e-6)
	# Driver state like _pto: neither a respawn's reset nor a new body clears it.
	router.reset_vehicle_cycles()
	var other: _RollingBody = auto_free(_RollingBody.new())
	router.register_vehicle(other)
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().hand_throttle).is_equal_approx(0.69, 1e-6)
	# A body with no preset (no `pto_hand_throttle`) leaves the latch where it is on the edge.
	touch.taps = 1
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().hand_throttle).is_equal_approx(0.69, 1e-6)
	# Back on the machine, the edge again clears it.
	router.register_vehicle(body)
	touch.taps = 1
	router._physics_process(1.0 / 60.0)
	assert_float(router.get_vehicle_input().hand_throttle).is_equal(0.0)
