extends GdUnitTestSuite
## DroneCAN node roster: one declaration pinned by three external sources (contract
## JSON, InputRouter). Tests roster shape, the three pins, health derivations, and
## the mode-cycle walk over full int range.

const B := preload("res://src/vehicles/drone/drone_bus.gd")
const Prop := preload("res://src/vehicles/drone/drone_propulsion.gd")
const DroneT := preload("res://src/vehicles/drone/drone_telemetry.gd")
const Router := preload("res://src/input/input_router.gd")
const ContractScript := preload("res://src/bridge/contract.gd")

## Roster indices (spelled out for readability in assertions).
const ESC1 := 0
const ESC2 := 1
const ESC3 := 2
const ESC4 := 3
const GNSS := 4
const POWER := 5
const AHRS := 6
const RANGE := 7

const WARN := 90.0   ## a stand-in esc_temp warn; the real one is read from the contract


func _contract() -> ContractScript.ContractData:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	return ContractScript.ContractData.parse(file.get_as_text())


## Four ESC temperatures, all cold unless an esc_index is named.
func _temps(hot_esc: int = -1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Prop.MOTORS.size())
	out.fill(20.0)
	if hot_esc >= 0:
		out[hot_esc] = WARN + 10.0
	return out


# --- the roster: the one declaration ------------------------------------------

func test_the_roster_is_this_airframe() -> void:
	assert_int(B.count()).is_equal(8)
	var ids := []
	var names := []
	for n: Dictionary in B.NODES:
		ids.append(int(n["id"]))
		names.append(String(n["name"]))
	assert_array(ids).is_equal([11, 12, 13, 14, 20, 21, 22, 23])
	assert_array(names).is_equal(["ESC1", "ESC2", "ESC3", "ESC4", "GNSS", "POWER", "AHRS", "RANGE"])


func test_node_ids_and_names_are_unique() -> void:
	# Two nodes sharing an id is a bus that cannot be addressed; two sharing a name is a node
	# strip that cannot be read. Both are silent failures without this.
	var ids := {}
	var names := {}
	for n: Dictionary in B.NODES:
		ids[int(n["id"])] = true
		names[String(n["name"])] = true
	assert_int(ids.size()).is_equal(B.count())
	assert_int(names.size()).is_equal(B.count())


func test_the_escs_come_first_and_in_esc_index_order() -> void:
	# offline_esc_bits, the telemetry hold and the node strip all read the two index spaces
	# side by side, so this ordering is what keeps them legible against each other.
	for esc in Prop.MOTORS.size():
		assert_int(B.esc_index_of(esc)).is_equal(esc)
	for i in range(Prop.MOTORS.size(), B.count()):
		assert_int(B.esc_index_of(i)).is_equal(-1)


func test_esc_index_of_is_safe_off_the_ends() -> void:
	assert_int(B.esc_index_of(-1)).is_equal(-1)
	assert_int(B.esc_index_of(B.count())).is_equal(-1)


## By-name lookup (roster is declaration; reordered roster keeps working).
func test_index_of_finds_every_node_and_nothing_else() -> void:
	for i in B.count():
		assert_int(B.index_of(String(B.NODES[i]["name"]))) \
			.override_failure_message("index_of lost '%s'" % B.NODES[i]["name"]).is_equal(i)
	# The two the sensors actually gate on, named so a rename fails here rather than silently
	# leaving a sensor permanently online.
	assert_int(B.index_of("GNSS")).is_greater_equal(0)
	assert_int(B.index_of("RANGE")).is_greater_equal(0)
	assert_int(B.index_of("nope")).is_equal(-1)
	assert_int(B.index_of("")).is_equal(-1)
	# ...and a -1 from a missed lookup reads as OFFLINE rather than wrapping to some node:
	# a sensor whose node cannot be found publishes nothing, which is the safe answer.
	assert_bool(B.is_online(0, B.index_of("nope"))).is_false()


func test_the_roster_fits_the_u16_bitfields() -> void:
	# node_fail and node_online are declared u16, so a roster past 16 would silently lose its
	# top nodes on the wire.
	assert_int(B.count()).is_less_equal(16)
	assert_int(B.roster_mask()).is_equal(0xFF)


# --- the pins: everything that cannot read the roster -------------------------

func test_the_contract_node_health_count_is_the_roster_size() -> void:
	# The contract JSON cannot read GDScript, so this is the gate that makes growing the
	# roster one edit: add a node and this fails until the contract follows.
	var sig: ContractScript.SignalDef = _contract().get_signal_def("node_health", "out")
	assert_object(sig).is_not_null()
	assert_int(sig.count).is_equal(B.count())
	assert_bool(sig.is_instanced()).is_true()


func test_node_health_carries_neither_an_enum_nor_a_range() -> void:
	# TWO deliberate omissions with different reasons, and both are load-bearing.
	#   'enum'  — count > 1 with one is PARSE-REJECTED: an instanced enum has no reader, since
	#             the dashboard chip path decodes with int(value) and throws on an array. So the
	#             health table lives in the desc. This one is not a choice; the parser enforces it.
	#   'range' — a LAYOUT choice, and it was made the other way first. With a range this lands
	#             on the generated-bar path as eight bars plus a caption, nine rows on a cluster
	#             already generating twenty-four, which took the drone to three bar columns and a
	#             cluster wider than a 1280 window. A four-step severity code has no meaningful
	#             full scale anyway, so it takes the esc_fault route: publish, render nowhere,
	#             and wait for the node strip.
	var sig: ContractScript.SignalDef = _contract().get_signal_def("node_health", "out")
	assert_str(sig.type).is_equal("u8")
	assert_str(sig.flavor).is_equal("dronecan")
	assert_bool(sig.has_enum()).is_false()
	assert_int(sig.range.size()).is_equal(0)
	assert_bool(sig.has_warn()).is_false()


func test_node_fail_is_an_inbound_scalar_bitfield() -> void:
	# The contract's first inbound bitfield: 'in', so it may NOT be instanced (bridge_source
	# normalizes inbound signals by hand, per name, with no array concept).
	var data := _contract()
	var sig: ContractScript.SignalDef = data.get_signal_def("node_fail", "in")
	assert_object(sig).is_not_null()
	assert_str(sig.type).is_equal("u16")
	assert_str(sig.unit).is_equal("bitfield")
	assert_str(sig.flavor).is_equal("dronecan")
	assert_bool(sig.is_instanced()).is_false()
	assert_array(Array(sig.vehicles)).is_equal(["drone"])
	# ...and there is no 'out' twin: node_online is the readback, under its own name.
	assert_bool(data.has_signal_def("node_fail", "out")).is_false()


func test_node_online_is_a_scalar_bitfield_that_renders_nowhere() -> void:
	# The esc_fault precedent: no range and no enum, so it falls through every dashboard
	# branch and only publishes. Declaring a range would put eight meaningless bars on screen.
	var sig: ContractScript.SignalDef = _contract().get_signal_def("node_online", "out")
	assert_object(sig).is_not_null()
	assert_str(sig.type).is_equal("u16")
	assert_int(sig.range.size()).is_equal(0)
	assert_bool(sig.has_enum()).is_false()
	assert_bool(sig.is_instanced()).is_false()


func test_the_router_mirrors_the_roster_size() -> void:
	# InputRouter must not depend on a vehicle class (the BODY_CMD_COUNT rule), so it carries
	# its own copy. This is the pin that stops the Y key quietly failing to reach a new node.
	assert_int(Router.NODE_FAIL_COUNT).is_equal(B.count())


func test_the_telemetry_default_is_roster_shaped_and_all_ok() -> void:
	# A to_bridge_dict() off a craft that has never flown must still be the right SHAPE, or the
	# bridge drops the signal.
	var t := DroneT.new()
	assert_int(t.node_health.size()).is_equal(B.count())
	for v: int in t.node_health:
		assert_int(v).is_equal(B.HEALTH_OK)
	assert_int(t.node_online).is_equal(B.roster_mask())
	var d := t.to_bridge_dict()
	assert_bool(d.has("node_health")).is_true()
	assert_bool(d.has("node_online")).is_true()
	assert_int((d["node_health"] as Array).size()).is_equal(B.count())


# --- presence -----------------------------------------------------------------

func test_an_empty_mask_is_a_healthy_bus() -> void:
	for i in B.count():
		assert_bool(B.is_online(0, i)).is_true()
	assert_int(B.online_bits(0)).is_equal(B.roster_mask())


func test_one_failed_bit_takes_exactly_that_node() -> void:
	for k in B.count():
		var bits := 1 << k
		for i in B.count():
			assert_bool(B.is_online(bits, i)).is_equal(i != k)
		assert_int(B.online_bits(bits)).is_equal(B.roster_mask() & ~bits)


func test_bits_above_the_roster_are_ignored_not_rejected() -> void:
	# node_fail is mirrored verbatim off the bus, so a peer describing an airframe with more
	# nodes than this one must not disturb the eight this one has.
	var bits := 1 << (B.count() + 3)
	assert_int(B.online_bits(bits)).is_equal(B.roster_mask())
	for i in B.count():
		assert_bool(B.is_online(bits, i)).is_true()


func test_is_online_is_safe_off_the_ends() -> void:
	assert_bool(B.is_online(0, -1)).is_false()
	assert_bool(B.is_online(0, B.count())).is_false()


func test_esc_is_online_is_the_inverse_lookup() -> void:
	for esc in Prop.MOTORS.size():
		assert_bool(B.esc_is_online(1 << esc, esc)).is_false()
		assert_bool(B.esc_is_online(1 << GNSS, esc)).is_true()
	# An esc_index no node drives is offline, the same safe answer is_online gives.
	assert_bool(B.esc_is_online(0, Prop.MOTORS.size())).is_false()


# --- the esc_fault term -------------------------------------------------------

func test_offline_esc_bits_reports_in_esc_index_space() -> void:
	for esc in Prop.MOTORS.size():
		assert_int(B.offline_esc_bits(1 << esc)).is_equal(1 << esc)
	assert_int(B.offline_esc_bits(0b1010)).is_equal(0b1010)


func test_a_failed_sensor_node_contributes_no_esc_fault() -> void:
	# GNSS/POWER/AHRS/RANGE drive no motor, so they must not light an ESC's fault bit.
	for i in [GNSS, POWER, AHRS, RANGE]:
		assert_int(B.offline_esc_bits(1 << i)).is_equal(0)


func test_esc_fault_ors_a_dropped_node_onto_the_over_temperature_bits() -> void:
	# The two honest sources, combined the way DroneVehicle combines them: a cold ESC whose
	# node is gone still faults, because a node that stopped talking cannot file its own.
	var hot := Prop.esc_fault_bits(_temps(ESC2), WARN)
	assert_int(hot).is_equal(1 << ESC2)
	assert_int(hot | B.offline_esc_bits(1 << ESC4)).is_equal((1 << ESC2) | (1 << ESC4))
	assert_int(Prop.esc_fault_bits(_temps(), WARN) | B.offline_esc_bits(1 << ESC1)).is_equal(1 << ESC1)


# --- the motor gate -----------------------------------------------------------

## Binary-exact float32 (0.125/0.25/0.75/1.0). PackedFloat32Array stores float32;
## is_equal required (not is_equal_approx). Untouched motor has no rescaling.
func test_a_healthy_bus_leaves_every_command_untouched() -> void:
	var cmd := PackedFloat32Array([0.125, 0.25, 0.75, 1.0])
	assert_array(Array(B.gate_commands(cmd, 0))).is_equal([0.125, 0.25, 0.75, 1.0])


func test_an_offline_esc_is_zeroed_and_the_others_are_bit_identical() -> void:
	var cmd := PackedFloat32Array([0.125, 0.25, 0.75, 1.0])
	for esc in Prop.MOTORS.size():
		var got := B.gate_commands(cmd, 1 << esc)
		for i in cmd.size():
			# Exact, not approximate: the failure is a hard zero, and every other motor must
			# come through with no rescaling and no compensation at all.
			assert_float(got[i]).is_equal(0.0 if i == esc else cmd[i])


func test_a_failed_sensor_node_does_not_touch_the_motors() -> void:
	var cmd := PackedFloat32Array([0.125, 0.25, 0.75, 1.0])
	for i in [GNSS, POWER, AHRS, RANGE]:
		assert_array(Array(B.gate_commands(cmd, 1 << i))).is_equal([0.125, 0.25, 0.75, 1.0])


func test_two_dead_motors_are_both_zeroed() -> void:
	var got := B.gate_commands(PackedFloat32Array([0.5, 0.5, 0.5, 0.5]), (1 << ESC1) | (1 << ESC3))
	assert_array(Array(got)).is_equal([0.0, 0.5, 0.0, 0.5])


func test_the_gate_does_not_alias_its_input() -> void:
	# DroneVehicle passes the mixer's own output straight in; a gate that wrote through would
	# be mutating a value the caller may still read.
	var cmd := PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	B.gate_commands(cmd, 1 << ESC1)
	assert_float(cmd[ESC1]).is_equal(0.5)


func test_the_gate_survives_a_short_command_array() -> void:
	assert_array(Array(B.gate_commands(PackedFloat32Array(), 0xFF))).is_empty()


# --- health, derived ----------------------------------------------------------

func test_a_healthy_cold_bus_is_all_ok() -> void:
	for i in B.count():
		assert_int(B.health_of(i, 0, _temps(), WARN)).is_equal(B.HEALTH_OK)


func test_an_esc_over_its_temperature_warn_is_a_warning() -> void:
	# Derived with NOTHING injected: node_fail is 0 here, and the craft still reports a fault.
	var t := _temps(ESC3)
	assert_int(B.health_of(ESC3, 0, t, WARN)).is_equal(B.HEALTH_WARNING)
	assert_int(B.health_of(ESC1, 0, t, WARN)).is_equal(B.HEALTH_OK)


func test_exactly_at_the_warn_is_not_yet_a_warning() -> void:
	# Strictly over, matching esc_fault_bits' own threshold, so the bar and the health agree.
	var t := _temps()
	t[ESC1] = WARN
	assert_int(B.health_of(ESC1, 0, t, WARN)).is_equal(B.HEALTH_OK)


func test_any_offline_node_is_critical() -> void:
	for i in B.count():
		assert_int(B.health_of(i, 1 << i, _temps(), WARN)).is_equal(B.HEALTH_CRITICAL)


func test_offline_dominates_an_over_temperature() -> void:
	# A node that is not on the bus is not reporting a temperature either, so the severe
	# answer is the true one.
	assert_int(B.health_of(ESC2, 1 << ESC2, _temps(ESC2), WARN)).is_equal(B.HEALTH_CRITICAL)


func test_health_of_is_critical_off_the_ends() -> void:
	assert_int(B.health_of(-1, 0, _temps(), WARN)).is_equal(B.HEALTH_CRITICAL)
	assert_int(B.health_of(B.count(), 0, _temps(), WARN)).is_equal(B.HEALTH_CRITICAL)


func test_a_missing_temperature_is_not_over_warn() -> void:
	# What lets all_ok() build the published default before the craft has ever ticked.
	for i in B.count():
		assert_int(B.health_of(i, 0, PackedFloat32Array(), -1.0)).is_equal(B.HEALTH_OK)


func test_health_all_is_roster_shaped_and_agrees_elementwise() -> void:
	var bits := (1 << ESC1) | (1 << AHRS)
	var t := _temps(ESC3)
	var all := B.health_all(bits, t, WARN)
	assert_int(all.size()).is_equal(B.count())
	for i in B.count():
		assert_int(all[i]).is_equal(B.health_of(i, bits, t, WARN))
	assert_array(all).is_equal([3, 0, 1, 0, 0, 0, 3, 0])


func test_all_ok_is_the_roster_sized_healthy_default() -> void:
	var all := B.all_ok()
	assert_int(all.size()).is_equal(B.count())
	for v: int in all:
		assert_int(v).is_equal(B.HEALTH_OK)


func test_error_is_never_reported() -> void:
	# ERROR (2) is deliberately unreachable: the craft has exactly two honest fault sources
	# and they land on WARNING and CRITICAL. Sweep every roster index against every single-bit
	# failure and both temperature sides, so a third source is a decision rather than a drift.
	for bits in range(0, B.roster_mask() + 1):
		for i in B.count():
			for hot in [-1, ESC1, ESC2, ESC3, ESC4]:
				assert_int(B.health_of(i, bits, _temps(hot), WARN)).is_not_equal(B.HEALTH_ERROR)


# --- the Y cycle --------------------------------------------------------------

func test_the_cycle_walks_the_roster_and_comes_home() -> void:
	var bits := 0
	for i in B.count():
		bits = B.cycle_fail(bits)
		assert_int(bits).is_equal(1 << i)
	# One more press and the bus is whole again — exactly count() + 1 states, so a press per
	# node plus a press for "none".
	assert_int(B.cycle_fail(bits)).is_equal(0)


func test_the_cycle_terminates_from_any_state() -> void:
	# It is total over every int, not just the eight states it can normally hold: a
	# bus-commanded multi-bit mask pressed on top of must still walk out rather than stick.
	for start in [0b11, 0b101, 0b1111_1111, 1 << 20, -1]:
		var bits: int = start
		var steps := 0
		while bits != 0 and steps < 64:
			bits = B.cycle_fail(bits)
			steps += 1
		assert_int(bits).is_equal(0)


func test_the_router_cycle_is_the_same_rule() -> void:
	# InputRouter mirrors cycle_fail rather than calling it (it must not depend on a vehicle
	# class). This pins the two implementations equal across the whole range they can meet on,
	# so "change both or neither" is enforced instead of asked for.
	#
	# Both sides are called. Re-typing the router's rule here instead would pin the bus against
	# a copy living in this file, and an edit to InputRouter would keep every test green — which
	# is exactly what this assertion is supposed to make impossible.
	for bits in range(0, (B.roster_mask() + 1) * 4):
		assert_int(B.cycle_fail(bits)) 			.override_failure_message("DroneBus.cycle_fail and InputRouter.cycle_node_fail disagree at %d" % bits) 			.is_equal(Router.cycle_node_fail(bits))
	# ...and off the ends the key can still be pressed on: a mask the bus set past the roster.
	for bits in [-1, 1 << 20, 1 << 40]:
		assert_int(B.cycle_fail(bits)).is_equal(Router.cycle_node_fail(bits))
