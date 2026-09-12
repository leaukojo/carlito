extends GdUnitTestSuite
## Contract loader tests.
## Exercises the pure-logic ContractData parser directly — no autoload lifecycle needed.

const ContractScript := preload("res://src/bridge/contract.gd")
const BridgeSourceScript := preload("res://src/input/sources/bridge_source.gd")

## Every core bridge signal (the original parity set). The contract must cover all of them.
const CORE_IN_SIGNALS: PackedStringArray = [
	"accel", "brake", "steer", "handbrake", "key", "lights", "gear",
	"turnL", "turnR", "horn", "checkEngine", "battery", "brakeLamp",
]
const CORE_OUT_SIGNALS: PackedStringArray = [
	"speed", "kmh", "rpm", "gear", "throttle", "yaw", "accLong", "accLat",
	"steer", "slip", "ground", "posX", "posZ", "heading", "lat", "lon",
	"odo", "status", "impact", "fuel", "coolant", "battery",
]


func _parse_file(path: String) -> ContractScript.ContractData:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	return ContractScript.ContractData.parse(file.get_as_text())


func _real_contract() -> ContractScript.ContractData:
	return _parse_file(ContractScript.CONTRACT_PATH)


func test_real_contract_is_valid_v42() -> void:
	var data := _real_contract()
	assert_array(data.errors).is_empty()
	assert_int(data.version).is_equal(42)


func _assert_core_signals_present(names: PackedStringArray, dir: String) -> void:
	var data := _real_contract()
	for sig_name in names:
		assert_bool(data.has_signal_def(sig_name, dir)) \
			.override_failure_message("missing core '%s' signal: %s" % [dir, sig_name]).is_true()
		assert_bool(data.is_todo(sig_name, dir)) \
			.override_failure_message("core '%s' signal must not be todo: %s" % [dir, sig_name]).is_false()


func test_every_v1_in_signal_present() -> void:
	_assert_core_signals_present(CORE_IN_SIGNALS, "in")


func test_every_v1_out_signal_present() -> void:
	_assert_core_signals_present(CORE_OUT_SIGNALS, "out")


func test_rpm_is_a_real_out_signal() -> void:
	var rpm := _real_contract().get_signal_def("rpm", "out")
	assert_object(rpm).is_not_null()
	assert_str(rpm.type).is_equal("u16")
	assert_array(rpm.range).is_equal([0.0, 8000.0])


func test_warn_thresholds_parse_and_classify() -> void:
	var data := _real_contract()
	# rpm redline: high-side warn near the top of [0, 8000].
	var rpm := data.get_signal_def("rpm", "out")
	assert_bool(rpm.has_warn()).is_true()
	assert_float(rpm.warn).is_equal_approx(6800.0, 0.001)
	assert_bool(rpm.warn_is_low()).is_false()
	# fuel: low-side warn near the bottom of [0, 100].
	var fuel := data.get_signal_def("fuel", "out")
	assert_bool(fuel.has_warn()).is_true()
	assert_bool(fuel.warn_is_low()).is_true()
	# coolant: high-side overheat warn.
	assert_bool(data.get_signal_def("coolant", "out").warn_is_low()).is_false()
	# a signal without 'warn' reports none.
	assert_bool(data.get_signal_def("kmh", "out").has_warn()).is_false()


# --- 'count': the instanced-signal shape (DroneCAN esc_index) ------------------

func test_count_defaults_to_one_and_an_ordinary_signal_is_not_instanced() -> void:
	# The default is the path every un-annotated signal takes, so it has to be the exact behaviour
	# they had before 'count' existed.
	var data := _real_contract()
	# Instanced signals NAMED rather than pattern-matched, so a fifth one is a deliberate edit here
	# as well as in the contract. An `esc_` prefix test once let `slip` through when it grew a count.
	var instanced := ["esc_rpm", "esc_current", "esc_temp", "node_health", "slip", "tank_level"]
	for sig in data.signals:
		if not (sig.name in instanced):
			assert_int(sig.count) \
				.override_failure_message("signal '%s' (%s) must default to count 1" % [sig.name, sig.dir]) \
				.is_equal(1)
	# ...and every name on that list really is instanced, so it cannot go stale the other way round.
	for sig_name in instanced:
		assert_bool(data.get_signal_def(sig_name, "out").is_instanced()) \
			.override_failure_message("'%s' is listed as instanced but declares no count" % sig_name) \
			.is_true()
	assert_bool(data.get_signal_def("rpm", "out").is_instanced()).is_false()


func test_the_four_esc_signals_are_the_instanced_dronecan_bus() -> void:
	var data := _real_contract()
	for sig_name in ["esc_rpm", "esc_current", "esc_temp"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_int(sig.count).override_failure_message("'%s' count" % sig_name).is_equal(4)
		assert_bool(sig.is_instanced()).is_true()
		assert_str(sig.flavor).is_equal("dronecan")
		assert_array(sig.vehicles).contains(["drone"])
		# 'range'/'warn' apply PER ELEMENT, so an instanced signal still carries one range.
		assert_int(sig.range.size()).is_equal(2)
	# esc_temp's warn is the high-side overheat threshold (the wheel_slip rule): above the
	# midpoint of its range, or the dashboard would highlight the cold end.
	var temp := data.get_signal_def("esc_temp", "out")
	assert_bool(temp.has_warn()).is_true()
	assert_bool(temp.warn_is_low()).is_false()
	# esc_fault is the summary bitfield, deliberately NOT instanced.
	var fault := data.get_signal_def("esc_fault", "out")
	assert_object(fault).is_not_null()
	assert_int(fault.count).is_equal(1)
	assert_bool(fault.is_instanced()).is_false()
	# ...and rotor_rpm stays the plain scalar mean beside them.
	assert_int(data.get_signal_def("rotor_rpm", "out").count).is_equal(1)


func test_fixture_bad_count_fails() -> void:
	var data := _parse_file("res://tests/fixtures/bad_count.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'count'")


## 'count' > 1 is refused on the three shapes no reader can express: an inbound signal
## (bridge_source.gd normalizes by hand, per name, and float(Array) is a silent 0), a bool (the
## tell-tale path is bool(value) and ANY non-empty array is true) and an enum (the chip path is
## int(value), which throws). Each would otherwise publish correctly and render as a lie.
func test_count_is_refused_where_no_reader_can_express_an_array() -> void:
	for fixture in ["bad_count_shape", "bad_count_bool", "bad_count_enum"]:
		var data := _parse_file("res://tests/fixtures/%s.json" % fixture)
		assert_bool(data.is_valid()) \
			.override_failure_message("%s should not parse" % fixture).is_false()
		assert_str("\n".join(data.errors)) \
			.override_failure_message("%s: wrong error" % fixture).contains("'count'")
	# ...and the real contract keeps every instanced signal on the legal side of that.
	for sig in _real_contract().signals:
		if not sig.is_instanced():
			continue
		assert_str(sig.dir).override_failure_message("'%s' must be out" % sig.name).is_equal("out")
		assert_str(sig.type).is_not_equal("bool")
		assert_bool(sig.has_enum()) \
			.override_failure_message("'%s' may not carry an enum" % sig.name).is_false()


func test_fixture_bad_warn_fails() -> void:
	var data := _parse_file("res://tests/fixtures/bad_warn.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'warn'")


## A threshold with no declared side is half a threshold: the dashboard would not know whether to
## highlight above or below it. So 'warn' and 'warn_side' are required together and refused apart,
## and the side is never guessed from where the threshold sits in 'range'.
func test_warn_and_warn_side_are_required_together() -> void:
	for fixture in ["bad_warn_side_missing", "bad_warn_side_value", "bad_warn_side_orphan"]:
		var data := _parse_file("res://tests/fixtures/%s.json" % fixture)
		assert_bool(data.is_valid()) \
			.override_failure_message("%s should not parse" % fixture).is_false()
		assert_str("\n".join(data.errors)) \
			.override_failure_message("%s: wrong error" % fixture).contains("warn_side")
	# ...and every warn in the real contract declares one.
	for sig in _real_contract().signals:
		if not sig.has_warn():
			continue
		assert_array(ContractScript.WARN_SIDES) \
			.override_failure_message("'%s' (%s) needs a warn_side" % [sig.name, sig.dir]) \
			.contains([sig.warn_side])


func test_gear_enum_decodes_ramn_byte_semantics() -> void:
	var gear := _real_contract().get_signal_def("gear", "in")
	assert_object(gear).is_not_null()
	assert_str(gear.enum_label(0)).is_equal("N")
	assert_str(gear.enum_label(1)).is_equal("D1")
	assert_str(gear.enum_label(3)).is_equal("D3")
	assert_str(gear.enum_label(6)).is_equal("D6")
	assert_str(gear.enum_label(255)).is_equal("R")
	assert_str(gear.enum_label(7)).is_equal("")


func test_lights_and_key_enums_decode() -> void:
	var data := _real_contract()
	var lights := data.get_signal_def("lights", "in")
	assert_str(lights.enum_label(1)).is_equal("OFF")
	assert_str(lights.enum_label(4)).is_equal("HIGH")
	var key := data.get_signal_def("key", "in")
	assert_str(key.enum_label(3)).is_equal("Ignition")


func test_battery_resolves_distinctly_per_dir() -> void:
	var data := _real_contract()
	var led := data.get_signal_def("battery", "in")
	var volts := data.get_signal_def("battery", "out")
	assert_object(led).is_not_null()
	assert_object(volts).is_not_null()
	assert_str(led.type).is_equal("bool")
	assert_str(volts.type).is_equal("f32")


func test_contract_is_fully_implemented() -> void:
	var data := _real_contract()
	# Tractor ISOBUS signals: implemented (not todo), flavored isobus.
	assert_bool(data.is_todo("hitch_pos", "in")).is_false()
	var hitch := data.get_signal_def("hitch_pos", "in")
	assert_str(hitch.flavor).is_equal("isobus")
	# Boat signals: implemented — as of v5 NO signal is todo anymore.
	assert_bool(data.is_todo("pitch", "out")).is_false()
	for sig in data.signals:
		assert_bool(sig.todo) \
			.override_failure_message("signal still marked todo: %s/%s" % [sig.dir, sig.name]) \
			.is_false()


func test_flying_signals_present_and_flavored() -> void:
	var data := _real_contract()
	# New flavored in signals.
	var elevator := data.get_signal_def("elevator", "in")
	assert_object(elevator).is_not_null()
	assert_str(elevator.flavor).is_equal("canaerospace")
	assert_str(elevator.type).is_equal("i8")
	assert_str(data.get_signal_def("flaps", "in").flavor).is_equal("canaerospace")
	assert_str(data.get_signal_def("climb", "in").flavor).is_equal("dronecan")
	var arm := data.get_signal_def("arm", "in")
	assert_object(arm).is_not_null()
	assert_str(arm.flavor).is_equal("dronecan")
	assert_str(arm.type).is_equal("bool")
	# New out signals: altitude/vspeed are cross-family instruments (bars via range).
	var altitude := data.get_signal_def("altitude", "out")
	assert_array(altitude.range).is_equal([0.0, 500.0])
	assert_array(data.get_signal_def("vspeed", "out").range).is_equal([-20.0, 20.0])
	assert_str(data.get_signal_def("rotor_rpm", "out").flavor).is_equal("dronecan")
	assert_str(data.get_signal_def("armed", "out").type).is_equal("bool")


func test_plane_and_drone_wired_into_shared_signals() -> void:
	var data := _real_contract()
	# Plane: engine + wheels — joins rpm/gear/fuel/coolant/ground plus the shared set.
	var plane_out := data.signals_for_vehicle("plane", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(plane_out).contains(["kmh", "rpm", "gear", "ground", "fuel", "altitude", "vspeed", "pitch", "roll"])
	var plane_in := data.signals_for_vehicle("plane", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(plane_in).contains(["accel", "brake", "elevator", "flaps", "gear"])
	assert_array(plane_in).not_contains(["climb", "arm", "rudder"])
	# Drone: battery-electric — no rpm/gear/fuel/coolant/ground, but altitude/vspeed/climb/arm.
	var drone_out := data.signals_for_vehicle("drone", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(drone_out).contains(["kmh", "altitude", "vspeed", "rotor_rpm", "armed", "pitch", "roll"])
	# The pack: it keeps the SHARED 'battery' volts (a pack voltage is a battery voltage) and
	# adds the rest of DroneCAN's BatteryInfo. 'fuel' stays absent — soc is its charge gauge.
	assert_array(drone_out).contains(["battery", "pack_current", "soc", "pack_temp"])
	assert_array(drone_out).not_contains(["rpm", "gear", "ground", "fuel", "coolant"])
	var drone_in := data.signals_for_vehicle("drone", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(drone_in).contains(["accel", "brake", "steer", "climb", "arm"])
	assert_array(drone_in).not_contains(["elevator", "flaps", "gear", "handbrake"])


func test_signals_for_vehicle_filters() -> void:
	var data := _real_contract()
	var boat_in := data.signals_for_vehicle("boat", "in")
	var names := boat_in.map(func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(names).contains(["accel", "steer", "horn"])
	assert_array(names).not_contains(["gear", "brakeLamp"])


func test_fixture_duplicate_signal_fails() -> void:
	var data := _parse_file("res://tests/fixtures/dup_signal.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("duplicate")


func test_fixture_unknown_type_fails() -> void:
	var data := _parse_file("res://tests/fixtures/unknown_type.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'type'")


func test_fixture_bad_range_fails() -> void:
	var data := _parse_file("res://tests/fixtures/bad_range.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'range'")


func test_fixture_bad_version_fails() -> void:
	var data := _parse_file("res://tests/fixtures/bad_version.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'version'")


func test_not_json_fails() -> void:
	var data := ContractScript.ContractData.parse("this is not json {")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("invalid JSON")


# --- tractor Tier 1 ISOBUS (traction & powertrain) ---

func test_tier1_isobus_signals_are_tractor_only_and_flavored() -> void:
	var data := _real_contract()
	var tractor_in := data.signals_for_vehicle("tractor", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(tractor_in).contains(["diff_lock", "fwd_drive", "pto_mode"])
	var tractor_out := data.signals_for_vehicle("tractor", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(tractor_out).contains(["diff_lock_state", "fwd_drive_state",
			"wheel_speed", "ground_speed", "wheel_slip", "engine_hours"])
	# Driveline signals belong to the tractor alone, or a spec-gated behaviour would start looking
	# like a cross-family one. engine_hours is deliberately not in this list: it is a shared meter.
	for entry: Array in [["diff_lock", "in"], ["fwd_drive", "in"], ["pto_mode", "in"],
			["diff_lock_state", "out"], ["fwd_drive_state", "out"], ["wheel_speed", "out"],
			["ground_speed", "out"], ["wheel_slip", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be isobus-flavored" % entry).is_equal("isobus")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be tractor-only" % entry).is_equal(["tractor"])


func test_shared_engine_signals_are_reused_by_the_truck_not_duplicated() -> void:
	# Rule 4: engine_load / pto / pto_state are one signal each, listing both families. They keep
	# the isobus flavor because ISO 11783 is built on J1939 — engine_load is SPN 92 whoever reads
	# it. If a truck-flavored copy ever appears beside these, this fails.
	var data := _real_contract()
	for entry: Array in [["engine_load", "out"], ["pto", "in"], ["pto_state", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be shared tractor+truck" % entry) \
			.is_equal(["tractor", "truck"])
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must stay isobus-flavored" % entry).is_equal("isobus")
	# engine_hours is shared too, but Phase 5 widened it to the boat and dropped the isobus
	# flavor: a boat does not speak J1939/ISOBUS, so the flavor would misstate the wire the
	# reading travels for that family (the speed_limit/wheel_slip precedent).
	var hours := data.get_signal_def("engine_hours", "out")
	assert_object(hours).override_failure_message("missing engine_hours/out").is_not_null()
	assert_array(hours.vehicles).is_equal(["tractor", "truck", "boat"])
	assert_str(hours.flavor).is_equal("")
	# The J1939 block must not re-declare any of them under a second flavor.
	for sig in data.signals:
		if sig.flavor != "j1939":
			continue
		assert_str(sig.name) \
			.override_failure_message("'%s' duplicates a shared signal under the j1939 flavor" % sig.name) \
			.is_not_equal("engine_load")


# --- truck J1939 chassis (FMS subset + DM1 lamps) ---

func test_j1939_chassis_signals_are_truck_only_and_flavored() -> void:
	var data := _real_contract()
	var truck_in := data.signals_for_vehicle("truck", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_in).contains(["retarder", "red_stop", "amber_warn", "protect_lamp", "pto"])
	var truck_out := data.signals_for_vehicle("truck", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_out).contains(["air_primary", "air_secondary", "retarder_state",
			"axle_load", "engine_load", "engine_hours", "pto_state"])
	# The tractor's ISOBUS-only signals stay off the truck (decision: extending diff_lock to
	# trucks would mislabel the protocol, since signals are unique by (name, dir)).
	assert_array(truck_in).not_contains(["diff_lock", "fwd_drive", "hitch_pos", "scv_flow"])
	assert_array(truck_out).not_contains(["diff_lock_state", "draft_force", "pto_rpm"])
	# The J1939 chassis signals belong to the truck alone.
	for entry: Array in [["retarder", "in"], ["red_stop", "in"], ["amber_warn", "in"],
			["protect_lamp", "in"], ["air_primary", "out"], ["air_secondary", "out"],
			["retarder_state", "out"], ["axle_load", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be j1939-flavored" % entry).is_equal("j1939")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be truck-only" % entry).is_equal(["truck"])


# --- boat NMEA 2000 ---

func test_nmea2000_signals_are_boat_only_and_flavored() -> void:
	var data := _real_contract()
	for entry: Array in [["rudder", "in"], ["rudder_actual", "out"], ["trim", "out"],
			["awa", "out"], ["aws", "out"], ["twd", "out"], ["tws", "out"],
			["stw", "out"], ["sog", "out"], ["cog", "out"],
			["current_set", "out"], ["current_drift", "out"], ["depth", "out"],
			["nav_mode", "in"], ["heading_cmd", "in"],
			["nav_mode_actual", "out"], ["heading_target", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be nmea2000-flavored" % entry).is_equal("nmea2000")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be boat-only" % entry).is_equal(["boat"])


func test_nmea2000_engine_room_signals_are_boat_only_and_flavored() -> void:
	var data := _real_contract()
	for entry: Array in [["fuel_rate", "out"], ["oil_press", "out"], ["tank_level", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be nmea2000-flavored" % entry).is_equal("nmea2000")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be boat-only" % entry).is_equal(["boat"])
	# tank_level is instanced (fresh/waste/live-well) and carries no warn: the three tanks have
	# opposite dangerous directions, so no single threshold applies array-wide (the node_health
	# reasoning). fuel stays the shared scalar signal and is deliberately not in this array.
	var tank := data.get_signal_def("tank_level", "out")
	assert_int(tank.count).is_equal(3)
	assert_bool(tank.is_instanced()).is_true()
	assert_bool(tank.has_warn()).is_false()
	var fuel := data.get_signal_def("fuel", "out")
	assert_int(fuel.count).is_equal(1)


## The autopilot pair follows the drone's flight_mode/mode_actual shape exactly: both ends carry
## an enum and NO range, so nav_mode_actual lands on the state-chip path rather than becoming a
## 0-1 bar with no meaningful full scale. heading_target DOES carry one, like the other bearings.
func test_the_autopilot_pair_is_enum_and_range_less_while_the_course_is_a_bearing() -> void:
	var data := _real_contract()
	for entry: Array in [["nav_mode", "in"], ["nav_mode_actual", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_bool(sig.has_enum()) \
			.override_failure_message("%s/%s must carry an enum" % entry).is_true()
		assert_array(sig.range) \
			.override_failure_message("%s/%s must stay range-less (the mode_actual rule)" % entry) \
			.is_empty()
	for entry: Array in [["heading_cmd", "in"], ["heading_target", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_array(sig.range) \
			.override_failure_message("%s/%s must be a [0,360] bearing" % entry) \
			.is_equal([0.0, 360.0])


func test_depth_warns_low_and_carries_its_no_bottom_sentinel_inside_the_range() -> void:
	# Shallow is the dangerous side. The -1 sentinel lives INSIDE the range so the bar and the
	# bridge agree on it, and it must stay below the warn rather than being confused with 0.
	var data := _real_contract()
	var sig := data.get_signal_def("depth", "out")
	assert_str(sig.warn_side).is_equal("low")
	assert_float(sig.warn).is_greater(0.0)
	assert_int(sig.range.size()).is_equal(2)
	assert_float(sig.range[0]).is_equal(-1.0)
	assert_float(sig.range[1]).is_greater(sig.warn)


func test_dm1_lamps_are_bools_and_add_nothing_for_the_mil() -> void:
	# The DM1 lamp status byte, mirrored verbatim like turnL. checkEngine already IS DM1's
	# Malfunction Indicator Lamp, so there must be no fourth signal duplicating it.
	var data := _real_contract()
	for sig_name in ["red_stop", "amber_warn", "protect_lamp"]:
		assert_str(data.get_signal_def(sig_name, "in").type) \
			.override_failure_message("%s must be a bool tell-tale" % sig_name).is_equal("bool")
	assert_bool(data.has_signal_def("mil", "in")).is_false()
	assert_array(data.get_signal_def("checkEngine", "in").vehicles).contains(["truck"])


func test_air_pressure_warns_low_and_axle_load_warns_high() -> void:
	# The side is DECLARED (warn_side) rather than inferred: air pressure is dangerous when LOW, axle
	# load when HIGH.
	var data := _real_contract()
	for sig_name in ["air_primary", "air_secondary"]:
		var air := data.get_signal_def(sig_name, "out")
		assert_array(air.range).is_equal([0.0, 12.0])
		assert_float(air.warn).is_equal_approx(5.0, 1e-6)
		assert_bool(air.warn_is_low()) \
			.override_failure_message("%s warn must read as a LOW-side danger" % sig_name).is_true()
	var axle := data.get_signal_def("axle_load", "out")
	assert_array(axle.range).is_equal([0.0, 20000.0])
	assert_float(axle.warn).is_equal_approx(11500.0, 1e-6)
	assert_bool(axle.warn_is_low()) \
		.override_failure_message("axle_load warn must read as a HIGH-side danger").is_false()


func test_retarder_state_range_fills_its_bar_the_right_way() -> void:
	# SPN 520 reports retarder torque NEGATIVE (it is a brake). DashBar fills linearly min -> max, so
	# a [-100, 0] range would show full retardation as an empty bar. The magnitude is published
	# instead and the convention documented in the desc; both halves of that decision are pinned here.
	var sig := _real_contract().get_signal_def("retarder_state", "out")
	assert_array(sig.range).is_equal([0.0, 100.0])
	assert_str(sig.desc).contains("SPN 520")
	# The request has no display: it is an "in" u8, so it generates neither a lamp nor a chip.
	var req := _real_contract().get_signal_def("retarder", "in")
	assert_str(req.type).is_equal("u8")
	assert_bool(req.has_enum()).is_false()


# --- truck CiA 422 body network, across the CiA 413 gateway ---

func test_cleanopen_body_signals_are_truck_only_and_flavored() -> void:
	var data := _real_contract()
	var truck_in := data.signals_for_vehicle("truck", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_in).contains(["body_cmd"])
	var truck_out := data.signals_for_vehicle("truck", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_out).contains(["body_state", "body_pos", "body_inhibit", "body_bus",
			"hopper_load"])
	# The body network is the truck's alone and a DIFFERENT flavor from the chassis around it, so a
	# copy-paste of "j1939" here must fail.
	for entry: Array in [["body_cmd", "in"], ["body_state", "out"], ["body_pos", "out"],
			["body_inhibit", "out"], ["body_bus", "out"], ["hopper_load", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be cleanopen-flavored" % entry).is_equal("cleanopen")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be truck-only" % entry).is_equal(["truck"])


func test_the_body_command_and_state_enums_cover_the_whole_cycle() -> void:
	var data := _real_contract()
	var cmd := data.get_signal_def("body_cmd", "in")
	assert_bool(cmd.has_enum()).is_true()
	for pair: Array in [[0, "Idle"], [1, "Lift"], [2, "Dump"], [3, "Lower"]]:
		assert_str(cmd.enum_label(pair[0])) \
			.override_failure_message("body_cmd %d must decode to %s" % pair).is_equal(pair[1])
	var state := data.get_signal_def("body_state", "out")
	assert_bool(state.has_enum()).is_true()
	# Inhibited is a REPORTED state, not just a refusal: without it the cluster cannot show why
	# the arm did not move.
	for pair: Array in [[0, "Stowed"], [1, "Lifting"], [2, "Dumping"], [3, "Lowering"],
			[4, "Inhibited"]]:
		assert_str(state.enum_label(pair[0])) \
			.override_failure_message("body_state %d must decode to %s" % pair).is_equal(pair[1])
	# body_state is a FLAVORED enum "out", which is what makes the dashboard generate its chip
	# with no code change (implement_type's precedent).
	assert_str(state.flavor).is_not_equal("")


func test_the_body_bars_are_plain_percentages_with_no_warn() -> void:
	# body_pos and hopper_load become generated bars because they are flavored and ranged, NOT because
	# they are warn'd. A warn would highlight a full hopper as a fault; overload belongs on axle_load.
	var data := _real_contract()
	for sig_name in ["body_pos", "hopper_load"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_array(sig.range) \
			.override_failure_message("%s must be a [0,100] bar" % sig_name).is_equal([0.0, 100.0])
		assert_str(sig.unit).is_equal("%")
		assert_bool(sig.has_warn()) \
			.override_failure_message("%s must not carry a warn" % sig_name).is_false()


func test_there_is_no_trailer_type_style_body_type_signal() -> void:
	# CiA 422 reports a body's FUNCTIONAL UNITS, not a body-type code, and the firetruck stays in the
	# family with no body network at all — so a "body_type" enum would have exactly one real value.
	var data := _real_contract()
	assert_bool(data.has_signal_def("body_type", "out")).is_false()
	assert_bool(data.has_signal_def("body_type", "in")).is_false()


# --- truck ISO 11992 trailer bus (the THIN boundary) ---

func test_iso11992_trailer_signals_are_truck_only_and_flavored() -> void:
	var data := _real_contract()
	var truck_in := data.signals_for_vehicle("truck", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_in).contains(["trailer_ebs_fault"])
	var truck_out := data.signals_for_vehicle("truck", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(truck_out).contains(["trailer_connected", "trailer_axle_load",
			"trailer_brake_demand", "trailer_abs"])
	# The trailer bus is a DIFFERENT flavor from the chassis it hangs off and from the body network
	# on the other side of the same truck: three networks, three flavors.
	for entry: Array in [["trailer_ebs_fault", "in"], ["trailer_connected", "out"],
			["trailer_axle_load", "out"], ["trailer_brake_demand", "out"], ["trailer_abs", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be iso11992-flavored" % entry).is_equal("iso11992")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be truck-only" % entry).is_equal(["truck"])


func test_the_trailer_bus_is_bidirectional_and_carries_no_body_type() -> void:
	# ISO 11992-2 is the application layer for brakes and running gear only, and it runs both ways:
	# EBS11 towing-to-towed, EBS21 towed-to-towing. None of it says what the trailer IS, so the
	# absence of a trailer_type is asserted rather than merely intended.
	var data := _real_contract()
	assert_bool(data.has_signal_def("trailer_type", "out")).is_false()
	assert_bool(data.has_signal_def("trailer_type", "in")).is_false()
	# ...and the decision is written down where someone adding one would read it.
	assert_str(data.get_signal_def("trailer_connected", "out").desc).contains("trailer_type")
	var dirs := {}
	for sig in data.signals:
		if sig.flavor == "iso11992":
			dirs[sig.dir] = true
	assert_bool(dirs.has("in") and dirs.has("out")) \
		.override_failure_message("the trailer bus must carry traffic in BOTH directions").is_true()


func test_the_trailer_bus_display_assignment_is_two_bars_and_three_lamps() -> void:
	# The cluster layout is settled in advance (a 280 px column at 18 px per bar), so what the
	# dashboard GENERATES from this metadata is pinned: ranged+flavored = a bar, bool = a tell-tale.
	var data := _real_contract()
	for sig_name in ["trailer_connected", "trailer_abs"]:
		assert_str(data.get_signal_def(sig_name, "out").type) \
			.override_failure_message("%s must be a bool tell-tale" % sig_name).is_equal("bool")
		assert_int(data.get_signal_def(sig_name, "out").range.size()) \
			.override_failure_message("%s must not generate a bar" % sig_name).is_equal(0)
	assert_str(data.get_signal_def("trailer_ebs_fault", "in").type).is_equal("bool")
	# The load bar: dangerous when HIGH, the opposite side to air_primary.
	var load_sig := data.get_signal_def("trailer_axle_load", "out")
	assert_array(load_sig.range).is_equal([0.0, 30000.0])
	assert_float(load_sig.warn).is_equal_approx(24000.0, 1e-6)
	assert_bool(load_sig.warn_is_low()) \
		.override_failure_message("trailer_axle_load warn must read as a HIGH-side danger").is_false()
	# The demand bar is a plain percentage: a hard brake application is not a fault.
	var demand := data.get_signal_def("trailer_brake_demand", "out")
	assert_array(demand.range).is_equal([0.0, 100.0])
	assert_str(demand.unit).is_equal("%")
	assert_bool(demand.has_warn()) \
		.override_failure_message("trailer_brake_demand must not carry a warn").is_false()


func test_guidance_and_scv_are_tractor_only_and_flavored() -> void:
	var data := _real_contract()
	for sig_name in ["guidance_curvature", "scv_flow"]:
		var sig := data.get_signal_def(sig_name, "in")
		assert_object(sig).override_failure_message("missing %s/in" % sig_name).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s must be isobus-flavored" % sig_name).is_equal("isobus")
		assert_array(sig.vehicles) \
			.override_failure_message("%s must be tractor-only" % sig_name).is_equal(["tractor"])


func test_guidance_curvature_range_matches_the_full_lock_scale() -> void:
	# bridge_source divides the command by FULL_LOCK_CURVATURE to reach the -1..1 steer channel, so
	# the contract's range and that constant must be the same number: the signal saturates exactly at
	# the steering stop, with no dead top end and no command asking for more lock than exists.
	var sig := _real_contract().get_signal_def("guidance_curvature", "in")
	assert_str(sig.type).is_equal("i8")
	assert_str(sig.unit).is_equal("1/km")
	assert_int(sig.range.size()).is_equal(2)
	assert_float(sig.range[0]).is_equal(-BridgeSourceScript.FULL_LOCK_CURVATURE)
	assert_float(sig.range[1]).is_equal(BridgeSourceScript.FULL_LOCK_CURVATURE)


func test_pto_mode_enum_decodes_shaft_speeds() -> void:
	var pto_mode := _real_contract().get_signal_def("pto_mode", "in")
	assert_str(pto_mode.type).is_equal("u8")
	assert_str(pto_mode.enum_label(0)).is_equal("540")
	assert_str(pto_mode.enum_label(1)).is_equal("1000")
	assert_str(pto_mode.enum_label(2)).is_equal("")


func test_engine_hours_is_range_less_so_it_never_becomes_a_bar() -> void:
	# The dashboard generates a bar for every ranged + flavored "out" signal. An hour meter has
	# no meaningful full scale, so it deliberately carries no range and lives on the readout.
	var hours := _real_contract().get_signal_def("engine_hours", "out")
	assert_array(hours.range).is_empty()
	assert_str(hours.unit).is_equal("h")
	# The two speeds DO get bars. Slip is dangerous when HIGH — good traction is not a warning.
	var data := _real_contract()
	assert_array(data.get_signal_def("wheel_speed", "out").range).is_equal([0.0, 60.0])
	assert_array(data.get_signal_def("ground_speed", "out").range).is_equal([0.0, 60.0])
	var slip := data.get_signal_def("wheel_slip", "out")
	assert_bool(slip.has_warn()).is_true()
	assert_bool(slip.warn_is_low()).is_false()


func test_speed_limit_is_range_less_and_unflavored_so_it_never_becomes_a_bar() -> void:
	# The road-speed governor (J1939 SPN 74) is the file's one CONFIGURED out signal, shaped on
	# engine_hours rather than on a bar: a value that cannot change for the whole session has no
	# meaningful full scale. Both halves of the bar predicate are pinned, since either alone
	# generates it.
	var lim := _real_contract().get_signal_def("speed_limit", "out")
	assert_object(lim).is_not_null()
	assert_array(lim.range).is_empty()
	assert_bool(lim.has_warn()).is_false()
	assert_str(lim.flavor).is_equal("")
	# u8 IS SPN 74's wire form -- 1 byte, 1 km/h per bit, 0..250 -- so the contract type and the
	# signal it borrows its name from cannot drift apart.
	assert_str(lim.type).is_equal("u8")
	assert_str(lim.unit).is_equal("km/h")
	# Keyed on the FAMILY: every family whose specs carry a limiter declares it (so an ungoverned
	# sedan publishes a real 0 rather than changing the cluster's shape), and no family that never
	# runs Drivetrain.governor_scale does. Unflavored on purpose — the SPN is a naming reference.
	for family in ["car", "truck", "tractor"]:
		assert_bool(lim.vehicles.has(family)) 			.override_failure_message("speed_limit must be declared for '%s'" % family).is_true()
	for family in ["boat", "plane", "drone", "train"]:
		assert_bool(lim.vehicles.has(family)) 			.override_failure_message("speed_limit must NOT be declared for '%s'" % family).is_false()


# --- train family (flavor "train": rail practice, not a real train CAN standard) ---

func test_train_wired_into_shared_signals_and_flavored_rail_signals() -> void:
	var data := _real_contract()
	assert_bool(data.is_valid()).is_true()
	var train_in := data.signals_for_vehicle("train", "in").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(train_in).contains(["accel", "brake", "key", "gear", "handbrake",
			"pantograph", "doors"])
	# Rail-guided: no steering; no rear-lamp / turn-signal equivalent.
	assert_array(train_in).not_contains(["steer", "turnL", "turnR", "brakeLamp"])

	var train_out := data.signals_for_vehicle("train", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(train_out).contains(["kmh", "speed", "gear", "odo", "status",
			"pantograph_state", "doors_state", "catenary_volts", "motor_current",
			"brake_pipe", "grade", "coupler_force"])
	# Electric traction: no engine RPM, fuel or coolant; no wheel slip/ground.
	assert_array(train_out).not_contains(["rpm", "fuel", "coolant", "slip", "ground", "steer"])

	assert_str(data.get_signal_def("pantograph", "in").flavor).is_equal("train")
	assert_str(data.get_signal_def("coupler_force", "out").flavor).is_equal("train")
	# catenary_volts / brake_pipe warn on the LOW side; motor_current on the high side.
	assert_bool(data.get_signal_def("catenary_volts", "out").warn_is_low()).is_true()
	assert_bool(data.get_signal_def("brake_pipe", "out").warn_is_low()).is_true()
	assert_bool(data.get_signal_def("motor_current", "out").warn_is_low()).is_false()


# --- the DroneCAN node bus (v23) ----------------------------------------------
# The roster-shaped assertions (count == DroneBus.count(), the router's mirrored copy, the no-enum
# rule) live in tests/test_drone_bus.gd, beside the roster they pin. What is here belongs to the
# CONTRACT: that the three signals exist, are scoped and flavored, and that node_fail is the first
# inbound bitfield rather than a fourth drone bool.

func test_the_drone_declares_the_node_bus() -> void:
	var data := _real_contract()
	var ins := data.signals_for_vehicle("drone", "in").map(func(s: ContractScript.SignalDef) -> String:
		return s.name)
	var outs := data.signals_for_vehicle("drone", "out").map(func(s: ContractScript.SignalDef) -> String:
		return s.name)
	assert_array(ins).contains(["node_fail"])
	assert_array(outs).contains(["node_health", "node_online"])
	for pair in [["node_fail", "in"], ["node_health", "out"], ["node_online", "out"]]:
		var sig := data.get_signal_def(pair[0], pair[1])
		assert_object(sig).override_failure_message("missing '%s'" % pair[0]).is_not_null()
		assert_str(sig.flavor).is_equal("dronecan")
		assert_array(sig.vehicles).is_equal(["drone"])


func test_no_other_vehicle_sees_the_node_bus() -> void:
	# It is airframe-specific in a way `battery` and `pitch` are not: a truck has no roster.
	var data := _real_contract()
	for vehicle in ["car", "truck", "tractor", "boat", "plane", "train"]:
		for dir in ["in", "out"]:
			var names := data.signals_for_vehicle(vehicle, dir).map(
				func(s: ContractScript.SignalDef) -> String: return s.name)
			assert_array(names) \
				.override_failure_message("%s/%s leaked a node signal" % [vehicle, dir]) \
				.not_contains(["node_fail", "node_health", "node_online"])


func test_node_fail_is_the_first_inbound_bitfield() -> void:
	# Every other 'in' bit in this file is its own bool signal (turnL, red_stop, ...) because each is
	# an independent lamp. This one is packed because it is ONE field with an index, the same reason
	# node_health is instanced — and it is the only one, so the next inbound bitfield is a decision
	# and not a habit.
	var packed := _real_contract().signals.filter(func(s: ContractScript.SignalDef) -> bool:
		return s.dir == "in" and s.unit == "bitfield")
	assert_int(packed.size()).is_equal(1)
	assert_str(packed[0].name).is_equal("node_fail")


# --- the drone's sensors (v25) -------------------------------------------------
# The laws behind these (the sky pattern, the fix thresholds, the HDOP spread model, the landed
# predicate) live in tests/test_drone_sensors.gd beside the code they pin, including the pins that
# tie SKY_RAYS / HDOP_MAX / RANGE_MAX / RANGE_INVALID to the ranges declared here.

func test_the_drone_declares_the_gnss_and_rangefinder_block() -> void:
	var data := _real_contract()
	var outs := data.signals_for_vehicle("drone", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(outs).contains(["sats", "fix_type", "hdop", "agl"])
	for sig_name in ["sats", "fix_type", "hdop", "agl"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_str(sig.flavor).is_equal("dronecan")
		assert_array(sig.vehicles).is_equal(["drone"])
	# No other family sees them: a truck has no sky mask and no beam.
	for vehicle in ["car", "truck", "tractor", "boat", "plane", "train"]:
		var names := data.signals_for_vehicle(vehicle, "out").map(
				func(s: ContractScript.SignalDef) -> String: return s.name)
		assert_array(names) 			.override_failure_message("%s leaked a drone sensor signal" % vehicle) 			.not_contains(["sats", "fix_type", "hdop", "agl"])


## The three display assignments in this block, each a decision: `sats` warns LOW (the count a 3D
## fix needs), `hdop` warns HIGH (the wheel_slip rule), and `fix_type` carries an enum with NO
## range so it renders as a state chip rather than as an ordinal on a 0-3 bar.
func test_the_gnss_block_reads_the_right_way_round_on_the_dashboard() -> void:
	var data := _real_contract()
	var sats := data.get_signal_def("sats", "out")
	assert_bool(sats.has_warn()).is_true()
	assert_bool(sats.warn_is_low()) 		.override_failure_message("sats warn must be low-side (too FEW satellites)").is_true()
	assert_float(sats.warn).is_equal(4.0)
	var hdop := data.get_signal_def("hdop", "out")
	assert_bool(hdop.has_warn()).is_true()
	assert_bool(hdop.warn_is_low()) 		.override_failure_message("hdop warn must be high-side (dilution is bad)").is_false()
	var fix := data.get_signal_def("fix_type", "out")
	assert_bool(fix.has_enum()).is_true()
	assert_int(fix.range.size()) 		.override_failure_message("fix_type must carry no range or it becomes a bar").is_equal(0)
	# The enum is the DroneCAN Fix2.status ordinals, verbatim and complete.
	for pair in [[0, "NO FIX"], [1, "TIME"], [2, "2D"], [3, "3D"]]:
		assert_str(fix.enum_label(pair[0])).is_equal(pair[1])


## `agl`'s range BOTTOM is the invalid sentinel, not a floor on a real reading — the one place in
## the contract where a range endpoint carries meaning. A zero there would be a plausible reading
## and exactly the value a landing detector would act on.
func test_agl_reserves_its_range_floor_for_the_invalid_reading() -> void:
	var agl := _real_contract().get_signal_def("agl", "out")
	assert_array(agl.range).is_equal([-1.0, 100.0])
	assert_bool(agl.has_warn()) 		.override_failure_message("agl has no danger threshold - it is a measurement").is_false()


## The IMU triples are complete and deliberately UNFLAVORED: honest body motion, not a DroneCAN
## concept, so another airframe can declare them without inheriting a protocol. Unflavored and
## warn-less also means they render on no dashboard, exactly as yaw / accLong / accLat do —
## asserted, because "it draws nothing" is the claim a generic dashboard change breaks silently.
func test_the_imu_axes_complete_two_triples_and_stay_unflavored() -> void:
	var data := _real_contract()
	for sig_name in ["roll_rate", "pitch_rate", "acc_vert"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_str(sig.type).is_equal("f32")
		assert_str(sig.flavor) 			.override_failure_message("'%s' must stay unflavored" % sig_name).is_equal("")
		assert_bool(sig.has_warn()) 			.override_failure_message("'%s' must not warn" % sig_name).is_false()
		# The plane declares all three (v30) at the cost of three list entries and no code: BaseVehicle
		# has always computed the triple off the rigid body for every vehicle.
		assert_array(sig.vehicles) \
			.override_failure_message("'%s' must be declared for the plane too" % sig_name) \
			.contains(["plane", "drone"])
	# Same scale as the axis each one joins, so a triple reads on one set of units.
	assert_array(data.get_signal_def("roll_rate", "out").range) 		.is_equal(data.get_signal_def("yaw", "out").range)
	assert_array(data.get_signal_def("pitch_rate", "out").range) 		.is_equal(data.get_signal_def("yaw", "out").range)
	assert_array(data.get_signal_def("acc_vert", "out").range) 		.is_equal(data.get_signal_def("accLong", "out").range)


# --- the drone's flight modes (v26) ---------------------------------------------
# The ladder and every law behind it (resolve_mode's refusals, the altitude cascade, the position
# controller, RTL's legs, the geofence, and the pins tying the two enum tables and home_dist's
# range to DroneModes) live in tests/test_drone_modes.gd beside the code. What is here belongs to
# the CONTRACT: the three signals exist, are scoped and flavored, and the request/readback pair is
# the shape it has to be to render at all.

func test_the_drone_declares_the_mode_ladder() -> void:
	var data := _real_contract()
	var ins := data.signals_for_vehicle("drone", "in").map(func(s: ContractScript.SignalDef) -> String:
		return s.name)
	var outs := data.signals_for_vehicle("drone", "out").map(func(s: ContractScript.SignalDef) -> String:
		return s.name)
	assert_array(ins).contains(["flight_mode"])
	assert_array(outs).contains(["mode_actual", "home_dist"])
	for pair in [["flight_mode", "in"], ["mode_actual", "out"], ["home_dist", "out"]]:
		var sig := data.get_signal_def(pair[0], pair[1])
		assert_object(sig).override_failure_message("missing '%s'" % pair[0]).is_not_null()
		assert_str(sig.flavor).is_equal("dronecan")
		assert_array(sig.vehicles).is_equal(["drone"])


func test_no_other_vehicle_sees_the_mode_ladder() -> void:
	# Airframe-specific in the way the node bus is: a boat has no flight controller to be in a
	# mode, and `guidance_curvature` is the tractor's own answer to the same idea.
	var data := _real_contract()
	for vehicle in ["car", "truck", "tractor", "boat", "plane", "train"]:
		for dir in ["in", "out"]:
			var names := data.signals_for_vehicle(vehicle, dir).map(
				func(s: ContractScript.SignalDef) -> String: return s.name)
			assert_array(names) 				.override_failure_message("%s/%s leaked a flight-mode signal" % [vehicle, dir]) 				.not_contains(["flight_mode", "mode_actual", "home_dist"])


## The request and the readback are a PAIR, and it only works if both decode the same table. Typed
## twice is the drift that leaves the MODE chip naming a different mode from the one sent.
func test_the_mode_request_and_readback_share_one_table() -> void:
	var data := _real_contract()
	var request := data.get_signal_def("flight_mode", "in")
	var actual := data.get_signal_def("mode_actual", "out")
	assert_str(request.type).is_equal("u8")
	assert_str(actual.type).is_equal("u8")
	assert_bool(request.has_enum()).is_true()
	assert_bool(actual.has_enum()).is_true()
	for mode in 5:
		assert_str(actual.enum_label(mode)) 			.override_failure_message("the two mode tables disagree at %d" % mode) 			.is_equal(request.enum_label(mode))
	# Five modes and no sixth: a label past the ladder means an entry nothing can request.
	assert_str(request.enum_label(5)).is_equal("")
	assert_str(actual.enum_label(5)).is_equal("")


## An enum out signal renders as a state chip ONLY without a range; with one it also lands on the
## generated-bar path as a 0-4 bar with no meaningful full scale. That is the node_health decision,
## and this keeps mode_actual on the right side of it.
func test_mode_actual_is_a_chip_and_not_a_bar() -> void:
	var actual := _real_contract().get_signal_def("mode_actual", "out")
	assert_int(actual.range.size()) 		.override_failure_message("mode_actual grew a range and would render as a 0-4 bar") 		.is_equal(0)
	assert_bool(actual.has_warn()).is_false()
	assert_int(actual.count).is_equal(1)



# --- contract v30: the hardpoint, the gimbal, the barometer and the lamp bits -----
# The laws behind these live beside their code (tests/test_drone_payload.gd, test_drone_gimbal.gd,
# test_drone_air_data.gd). What is here belongs to the CONTRACT: the signals exist, are scoped and
# flavored, and land on the dashboard path they were chosen for — which is no path at all.


## The drone's cluster has no rows left. Dashboard.BAR_ROWS_MAX says so in prose; this is the
## assertion, and it fails if a future drone signal is given a range without re-deriving that
## budget. The generated-bar gate is `a range PLUS (a warn or a flavor)`, and every drone signal
## v30 added is flavored, so a range on any of them is a new bar row.
func test_the_new_drone_readings_carry_no_range_and_generate_no_bars() -> void:
	var data := _real_contract()
	for sig_name in ["payload_weight", "gimbal_pitch_actual", "gimbal_yaw_actual",
			"baro_alt", "static_press", "oat"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_str(sig.flavor).is_equal("dronecan")
		assert_array(sig.vehicles).is_equal(["drone"])
		assert_int(sig.range.size()) \
			.override_failure_message("'%s' grew a range and takes the drone cluster to three columns" % sig_name) \
			.is_equal(0)


## The hook is a REQUEST and a STATE, and the pair is the reading: commanding HOLD over open ground
## leaves the two disagreeing. Same shape as arm/armed and hitch_pos/hitch_pos_actual, both bools,
## so both generate tell-tales with no dashboard code.
func test_the_hardpoint_is_a_request_and_a_state() -> void:
	var data := _real_contract()
	var cmd := data.get_signal_def("hardpoint_cmd", "in")
	var state := data.get_signal_def("hardpoint_state", "out")
	assert_object(cmd).is_not_null()
	assert_object(state).is_not_null()
	assert_str(cmd.type).is_equal("bool")
	assert_str(state.type).is_equal("bool")
	assert_str(cmd.flavor).is_equal("dronecan")
	assert_str(state.flavor).is_equal("dronecan")
	assert_array(cmd.vehicles).is_equal(["drone"])
	assert_array(state.vehicles).is_equal(["drone"])
	# The force the latch reports is in NEWTON, the unit hardpoint.Status specifies: a latch measures a
	# force on itself, and a kilogram here would be the wrong signal under the right name.
	assert_str(data.get_signal_def("payload_weight", "out").unit).is_equal("N")


## The gimbal commands are in DEGREES with the mount's own stops as their range — no percent
## fiction between the number and where the camera points. DroneVehicle reads those two ranges at
## _ready as its travel limits, so a contract edit cannot let the mount travel out of reach.
func test_the_gimbal_commands_carry_the_mounts_stops_in_degrees() -> void:
	var data := _real_contract()
	for sig_name in ["gimbal_pitch", "gimbal_yaw"]:
		var sig := data.get_signal_def(sig_name, "in")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_str(sig.type).is_equal("i8")
		assert_str(sig.unit).is_equal("deg")
		assert_int(sig.range.size()) \
			.override_failure_message("'%s' needs a range: it IS the mount's travel" % sig_name) \
			.is_equal(2)
		# The stops have to fit i8 in whole degrees, which is the whole reason the contract
		# carries degrees here rather than a percent of travel.
		assert_float(float(sig.range[0])).is_greater_equal(-128.0)
		assert_float(float(sig.range[1])).is_less_equal(127.0)
	# Pitch reaches further DOWN than up: a belly mount looks at the ground.
	var pitch := data.get_signal_def("gimbal_pitch", "in")
	assert_float(absf(float(pitch.range[0]))).is_greater(absf(float(pitch.range[1])))


## The plane's two flashing lamps. They exist SO THAT nothing in the game blinks — see
## tests/test_lamps.gd, which asserts the absence LampSet used to be the exception to.
func test_the_aircraft_flash_bits_are_two_separate_plane_signals() -> void:
	var data := _real_contract()
	for sig_name in ["beacon", "strobe"]:
		var sig := data.get_signal_def(sig_name, "in")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_str(sig.type).is_equal("bool")
		assert_str(sig.flavor).is_equal("canaerospace")
		assert_array(sig.vehicles).is_equal(["plane"])
	# No vehicle but the plane sees them, and there is no "out" counterpart: a mirrored lamp
	# bit has nothing to read back — what the lamp is doing IS what the bus said.
	assert_object(data.get_signal_def("beacon", "out")).is_null()
	assert_object(data.get_signal_def("strobe", "out")).is_null()


## The per-axle slip split (v30). `slip` was one mean and is now two elements, the first use of the
## instanced-signal mechanism outside the drone and the first on an UNFLAVORED signal. Zero-based,
## matching the wire, like every other `count`.
func test_slip_is_instanced_per_axle_and_stays_off_the_dashboard() -> void:
	var slip := _real_contract().get_signal_def("slip", "out")
	assert_object(slip).is_not_null()
	assert_int(slip.count).is_equal(2)
	assert_bool(slip.is_instanced()).is_true()
	# Unflavored and warn-less, so it generates NO bars: the split is for the bus, where a per-axle
	# reading was asked for. A warn would put three rows on the car, the truck and the tractor at once.
	assert_str(slip.flavor).is_equal("")
	assert_bool(slip.has_warn()).is_false()
	# Still the wheeled families only — a boat has no axle to slip.
	assert_array(slip.vehicles).is_equal(["car", "truck", "tractor"])


## The instanced-signal parse rules the ESCs introduced still hold for the new consumer: an
## array-valued signal is "out"-only, and carries neither an enum nor type bool.
func test_the_instanced_rules_still_hold_across_every_count_signal() -> void:
	for sig in _real_contract().signals:
		if not sig.is_instanced():
			continue
		assert_str(sig.dir) \
			.override_failure_message("instanced '%s' must be an out signal" % sig.name) \
			.is_equal("out")
		assert_bool(sig.has_enum()) \
			.override_failure_message("instanced '%s' may not carry an enum" % sig.name) \
			.is_false()
		assert_str(sig.type) \
			.override_failure_message("instanced '%s' may not be a bool" % sig.name) \
			.is_not_equal("bool")
