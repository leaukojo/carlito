extends GdUnitTestSuite
## Contract loader tests.
## Exercises the pure-logic ContractData parser directly — no autoload lifecycle needed.

const ContractScript := preload("res://src/bridge/contract.gd")
const BridgeSourceScript := preload("res://src/input/sources/bridge_source.gd")

## Every core bridge signal (the original parity set). The contract must
## cover all of them.
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


func test_real_contract_is_valid_v19() -> void:
	var data := _real_contract()
	assert_array(data.errors).is_empty()
	assert_int(data.version).is_equal(19)


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


func test_fixture_bad_warn_fails() -> void:
	var data := _parse_file("res://tests/fixtures/bad_warn.json")
	assert_bool(data.is_valid()).is_false()
	assert_str("\n".join(data.errors)).contains("'warn'")


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
	# Driveline signals belong to the tractor alone — nothing else may declare them, or a
	# spec-gated behaviour would start looking like a cross-family one. engine_hours is
	# deliberately NOT in this list: it is a shared meter, asserted below.
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
	# Rule 4: engine_load / engine_hours / pto / pto_state are ONE signal each, listing both
	# families. They keep the isobus flavor because ISO 11783 is built on J1939 and the
	# tractor's was always the borrowed one — engine_load is SPN 92 whoever reads it. If a
	# truck-flavored copy ever appears beside these, this fails.
	var data := _real_contract()
	for entry: Array in [["engine_load", "out"], ["engine_hours", "out"],
			["pto", "in"], ["pto_state", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be shared tractor+truck" % entry) \
			.is_equal(["tractor", "truck"])
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must stay isobus-flavored" % entry).is_equal("isobus")
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
	# The whole reason the plan pins these: warn_is_low() infers the side from the RANGE
	# MIDPOINT, so a threshold on the wrong side of it highlights the safe end of the bar.
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
	# SPN 520 reports retarder torque NEGATIVE (it is a brake). The dashboard generates bars
	# straight from 'range' and DashBar fills linearly min -> max, so a [-100, 0] range would
	# show full retardation as an EMPTY bar. The magnitude is published instead and the
	# convention is documented in the desc — pin both halves of that decision here.
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
	# The body network is the truck's alone, and it is a DIFFERENT flavor from the chassis around
	# it — that difference is the whole lesson, so a copy-paste of "j1939" here must fail.
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
	# body_pos and hopper_load become generated bars because they are flavored and ranged, NOT
	# because they are warn'd. A warn here would highlight a full hopper as a fault, which it is
	# not — the axle_load warn is where an overload belongs, and it gets there through mass.
	var data := _real_contract()
	for sig_name in ["body_pos", "hopper_load"]:
		var sig := data.get_signal_def(sig_name, "out")
		assert_array(sig.range) \
			.override_failure_message("%s must be a [0,100] bar" % sig_name).is_equal([0.0, 100.0])
		assert_str(sig.unit).is_equal("%")
		assert_bool(sig.has_warn()) \
			.override_failure_message("%s must not carry a warn" % sig_name).is_false()


func test_there_is_no_trailer_type_style_body_type_signal() -> void:
	# CiA 422 reports a body's FUNCTIONAL UNITS, not a body-type code, and the firetruck stays in
	# the family with no body network at all — so a "body_type" enum would have exactly one real
	# value and would undercut the family boundary this phase is built on.
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
	# on the other side of the same truck — three networks, three flavors, which is the whole point.
	for entry: Array in [["trailer_ebs_fault", "in"], ["trailer_connected", "out"],
			["trailer_axle_load", "out"], ["trailer_brake_demand", "out"], ["trailer_abs", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.flavor) \
			.override_failure_message("%s/%s must be iso11992-flavored" % entry).is_equal("iso11992")
		assert_array(sig.vehicles) \
			.override_failure_message("%s/%s must be truck-only" % entry).is_equal(["truck"])


func test_the_trailer_bus_is_bidirectional_and_carries_no_body_type() -> void:
	# ISO 11992-2 is the application layer for BRAKES AND RUNNING GEAR ONLY, and it runs both ways:
	# EBS11 towing-to-towed, EBS21 towed-to-towing. No other signal group here does that, and none
	# of it says what the trailer IS — a trailer_type would undercut the exact thin-boundary lesson
	# the flavor exists to teach, so its absence is asserted rather than merely intended.
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
	# The load bar: 'warn' must sit ABOVE the range midpoint or the dashboard highlights the safe
	# end — the same trap air_primary sits on the other side of.
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
	# bridge_source divides the command by FULL_LOCK_CURVATURE to reach the -1..1 steer
	# channel, so the contract's range and that constant must be the same number: the
	# signal is meant to saturate exactly at the steering stop, with no dead top end and no
	# reachable command that asks for more lock than exists.
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
	# The two speeds DO get bars. Slip's warn must sit in the HIGH half of its range, or
	# warn_is_low() infers the wrong side and the dashboard highlights good traction as danger.
	var data := _real_contract()
	assert_array(data.get_signal_def("wheel_speed", "out").range).is_equal([0.0, 60.0])
	assert_array(data.get_signal_def("ground_speed", "out").range).is_equal([0.0, 60.0])
	var slip := data.get_signal_def("wheel_slip", "out")
	assert_bool(slip.has_warn()).is_true()
	assert_bool(slip.warn_is_low()).is_false()


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
