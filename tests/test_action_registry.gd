extends GdUnitTestSuite
## Action registry: one source for every bound control. Two consumers (CONTROLS sheet,
## touch overlay). Actions must be documented or CI fails. Pure static (no autoload).

const Registry := preload("res://src/input/action_registry.gd")
const RouterScript := preload("res://src/input/input_router.gd")
const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const TouchScript := preload("res://src/ui/touch_controls.gd")
const LocalSourceScript := preload("res://src/input/sources/local_source.gd")
const PadSourceScript := preload("res://src/input/sources/pad_source.gd")


## Actions enumerated from ProjectSettings (hand list gets forgotten, hence this bug).
func test_every_bound_action_is_registered() -> void:
	var registered := {}  # action -> row id
	for entry in Registry.ENTRIES:
		for action in entry["actions"]:
			if registered.has(action):
				fail("action '%s' is in two registry rows ('%s' and '%s')" % [
					action, registered[action], entry["id"]])
			registered[action] = String(entry["id"])

	var bound := _bound_actions()
	assert_array(bound).is_not_empty()
	for action in bound:
		if not registered.has(action):
			fail("action '%s' is bound in project.godot but not in ActionRegistry — add a row "
					% action + "so it appears in the CONTROLS sheet")


## ...and the other way round: a row naming an action nobody bound would document a control that
## cannot be pressed, which reads exactly like a real one on the sheet.
func test_no_registry_row_names_an_unbound_action() -> void:
	var bound := _bound_actions()
	for entry in Registry.ENTRIES:
		for action in entry["actions"]:
			if not bound.has(action):
				fail("registry row '%s' names '%s', which is not bound in project.godot" % [
					entry["id"], action])


## Every touch button's raw-intent key survives the keyboard/touch merge from either side. A key
## the merge drops or mistypes stops working on this one machine only (a touch source is
## registered), which is invisible in game; this is the cheap guard.
func test_every_touch_poll_key_is_merged() -> void:
	for entry in Registry.ENTRIES:
		var key := StringName(entry.get("poll_key", ""))
		if key != &"":
			_assert_survives_merge(key, "registry row '%s' polls" % entry["id"])


## The half the guard above misses: TouchControls.poll() also writes WIDGET_KEYS straight into
## `_held`/`_edges` for the hand-built widgets (joystick, pedals, HAND, climb pads, HORN, LIGHTS),
## Touch.WIDGET rows with no `poll_key` of their own.
func test_every_widget_key_is_merged() -> void:
	for key in TouchScript.WIDGET_KEYS:
		_assert_survives_merge(key, "TouchControls.WIDGET_KEYS has")


## Every keyboard key survives the merge too: a key lost or turned from an axis into a bit there
## drops the keyboard control the moment a touch source registers.
func test_every_local_source_key_is_merged() -> void:
	var polled := LocalSourceScript.new().poll(0.0).keys()
	assert_array(polled).is_not_empty()
	for key: StringName in polled:
		_assert_survives_merge(key, "LocalSource.poll writes")


## The pad source reports only analog keys: each must come out as the axis it went in as.
func test_every_pad_key_is_merged() -> void:
	var polled := PadSourceScript.new().poll().keys()
	assert_array(polled).is_not_empty()
	for key: StringName in polled:
		_assert_survives_merge(key, "PadSource.poll writes", 0.5)


## `key` is one the router reads (LocalSource's set: the merge ORs any name through, so a typo
## would otherwise pass), and carried by one side of merge_local (either side) it comes out as
## sent: 0.5 for a key LocalSource reports as an axis, else a set bit, so an axis the merge ORs as
## a bit reads `true` and fails.
func _assert_survives_merge(key: StringName, who: String, sample: Variant = null) -> void:
	var rest := LocalSourceScript.new().poll(0.0)
	assert_bool(rest.has(key)) \
		.override_failure_message("%s '%s', which LocalSource does not report, so " % [who, key]
				+ "InputRouter never reads it") \
		.is_true()
	if sample == null:
		sample = 0.5 if typeof(rest.get(key)) == TYPE_FLOAT else true
	var one: Dictionary[StringName, Variant] = {key: sample}
	for merged in [RouterScript.merge_local(one, {}), RouterScript.merge_local({}, one)]:
		assert_that(merged.get(key)) \
			.override_failure_message("%s '%s', which InputRouter.merge_local does not carry as "
					% [who, key] + "sent (%s in, %s out)" % [sample, merged.get(key)]) \
			.is_equal(sample)


# --- the gamepad -------------------------------------------------------------

## InputMap cannot layer a button under L1, so a pad button bound there would fire beside the
## action PadLayer resolves for it. Axes (triggers, sticks) stay in InputMap.
func test_no_game_action_binds_a_pad_button() -> void:
	for action in _bound_actions():
		for ev in InputMap.action_get_events(action):
			assert_bool(ev is InputEventJoypadButton) \
				.override_failure_message("'%s' binds a pad button in project.godot; pad buttons "
						% action + "live in ActionRegistry's `pad` field (PadLayer injects them)") \
				.is_false()


## One slot per action, each a button PadLayer knows, optionally on the L1 layer.
func test_every_pad_slot_names_a_real_button() -> void:
	var names: Array = PadLayer.BUTTONS.values()
	for entry in Registry.ENTRIES:
		if not entry.has("pad"):
			continue
		assert_int(entry["pad"].size()) \
			.override_failure_message("row '%s' has %d pad slots for %d actions" % [
				entry["id"], entry["pad"].size(), entry["actions"].size()]) \
			.is_equal(entry["actions"].size())
		for slot: String in entry["pad"]:
			assert_bool(names.has(slot.trim_prefix(PadLayer.LAYER_PREFIX))) \
				.override_failure_message("row '%s' pad slot '%s' is no PadLayer button"
						% [entry["id"], slot]) \
				.is_true()


## A slot shared by two rows must never see both apply: every family under every capability set
## (a superset of what any machine reports), so the resolver's first match is the only match.
func test_no_two_rows_answer_one_pad_slot() -> void:
	var caps_keys: Array = Registry.CAP_NOTE.keys()
	var checked := 0
	for family in _all_families():
		for mask in 1 << caps_keys.size():
			var caps := {}
			for i in caps_keys.size():
				caps[caps_keys[i]] = ((mask >> i) & 1) == 1
			var ctx := _ctx(family, caps)
			var seen := {}  # slot -> row id
			for entry in Registry.ENTRIES:
				if not Registry.applies_entry(entry, ctx):
					continue
				for slot: String in entry.get("pad", []):
					assert_bool(seen.has(slot)) \
						.override_failure_message("'%s' with %s: pad slot '%s' answers both '%s' and '%s'"
								% [family, str(caps), slot, seen.get(slot), entry["id"]]) \
						.is_false()
					seen[slot] = entry["id"]
					checked += 1
	assert_int(checked).is_greater(1000)  # a silently-empty sweep would pass forever


## The main / second / third L1 slots keep one role across vehicles.
func test_the_l1_main_slot_follows_the_vehicle() -> void:
	assert_str(_pad("l1+square", _ctx("tractor", {"lift": true}))).is_equal("hitch")
	assert_str(_pad("l1+square", _ctx("drone"))).is_equal("arm")
	assert_str(_pad("l1+square", _ctx("plane"))).is_equal("flaps")
	assert_str(_pad("l1+square", _ctx("boat"))).is_equal("nav_mode")
	assert_str(_pad("l1+square", _ctx("train"))).is_equal("pantograph")
	assert_str(_pad("l1+square", _ctx("car"))).is_equal("")
	assert_str(_pad("l1+cross", _ctx("truck", {"body_cmd": true}))) \
			.is_equal("body_cmd")
	assert_str(_pad("l1+dpad_up", _ctx("tractor"))).is_equal("hand_throttle_up")


func test_the_base_layer_gates_like_the_sheet() -> void:
	assert_str(_pad("cross", _ctx("car"))).is_equal("handbrake")
	assert_str(_pad("cross", _ctx("boat"))).is_equal("")
	assert_str(_pad("square", _ctx("car"))).is_equal("headlights")
	# sloppyCAN driving takes the handbrake, never the camera.
	var live := Registry.context("car", true, {})
	assert_str(_pad("cross", live)).is_equal("")
	assert_str(_pad("circle", live)).is_equal("camera_view")


## The camera's pad buttons answer on every vehicle, and never under a menu (the D-pad scrolls
## the CONTROLS sheet there).
func test_the_camera_buttons_answer_everywhere() -> void:
	for family in _all_families():
		assert_str(_pad("r3", _ctx(family))).is_equal("camera_recenter")
		assert_str(_pad("dpad_up", _ctx(family))).is_equal("camera_zoom_in")
		assert_str(_pad("dpad_down", _ctx(family))).is_equal("camera_zoom_out")
	assert_str(_pad("dpad_up", _ctx("car"), true)).is_equal("")
	assert_str(Registry.pad_for(Registry.find(&"camera_look"))).is_equal("Right stick")


## With L1 held, a button with nothing on the layer does its own job.
func test_pad_press_falls_back_to_the_base_layer() -> void:
	assert_str(String(Registry.pad_press("square", true, _ctx("drone")))).is_equal("arm")
	assert_str(String(Registry.pad_press("square", true, _ctx("car")))).is_equal("headlights")
	assert_str(String(Registry.pad_press("options", true, _ctx("car")))).is_equal("to_menu")
	assert_str(String(Registry.pad_press("square", false, _ctx("drone")))).is_equal("headlights")
	assert_str(String(Registry.pad_press("square", true, _ctx("drone"), true))).is_equal("")
	# A role the vehicle has but sloppyCAN holds right now stays inert, never the button's own:
	# fallback (live bridge, local driving) leaves the lights local but the hitch sloppyCAN's.
	var fallback := Registry.context("tractor", true, {"lift": true}, false)
	assert_str(String(Registry.pad_press("square", false, fallback))).is_equal("headlights")
	assert_str(String(Registry.pad_press("square", true, fallback))).is_equal("")


## Under a menu only the shell answers: Options closes it, nothing latches in the vehicle.
func test_a_paused_pad_reaches_only_the_shell() -> void:
	assert_str(_pad("options", _ctx("car"), true)).is_equal("to_menu")
	assert_str(_pad("create", _ctx("car"), true)).is_equal("garage")
	assert_str(_pad("cross", _ctx("car"), true)).is_equal("")
	assert_str(_pad("l1+square", _ctx("drone"), true)).is_equal("")


## Every slot a row names, and every slot PadLayer reads, has a name on screen.
func test_every_pad_slot_has_a_name() -> void:
	var slots: Array = PadLayer.BUTTONS.values()
	for entry in Registry.ENTRIES:
		for slot: String in entry.get("pad", []):
			slots.append(slot.trim_prefix(PadLayer.LAYER_PREFIX))
	for slot: String in slots:
		assert_bool(PadLayer.SLOT_NAMES.has(slot)) \
			.override_failure_message("pad slot '%s' has no PadLayer.SLOT_NAMES entry" % slot) \
			.is_true()


## The sheet's pad column: slots by name, the layer once, axes live from InputMap.
func test_pad_for_names_the_binding() -> void:
	assert_str(Registry.pad_for(Registry.find(&"handbrake"))).is_equal("Cross")
	assert_str(Registry.pad_for(Registry.find(&"hitch"))).is_equal("L1 + Square")
	assert_str(Registry.pad_for(Registry.find(&"hand_throttle"))) \
			.is_equal("L1 + D-pad down / D-pad up")
	assert_str(Registry.pad_for(Registry.find(&"drive"))).is_equal("R2 / L2")
	assert_str(Registry.pad_for(Registry.find(&"steer"))).is_equal("Left stick")
	assert_str(Registry.pad_for(Registry.find(&"climb"))).is_equal("Left stick up / down")
	assert_str(Registry.pad_for(Registry.find(&"day_night"))).is_equal("")


## The L1 legend: the vehicle's layer in main / second / third order, nothing it can never use,
## and a bridge-owned row kept (the legend greys it).
func test_pad_layer_rows_follow_the_vehicle() -> void:
	var ids := func(ctx: Dictionary) -> Array:
		return Registry.pad_layer_rows(ctx).map(func(e: Dictionary) -> String: return String(e["id"]))
	assert_array(ids.call(_ctx("drone"))) \
			.contains_exactly(["arm", "flight_mode", "hardpoint", "node_fail"])
	assert_array(ids.call(_ctx("car"))).is_empty()
	assert_array(ids.call(_ctx("car", {"tows": true}))).contains_exactly(["next_attachment"])
	var tractor: Array = ids.call(_ctx("tractor", {"lift": true, "pto": true}))
	assert_str(String(tractor[0])).is_equal("hitch")
	assert_array(tractor).contains(["hand_throttle", "pto_mode", "hand_throttle_pto"])
	assert_array(tractor).not_contains(["scv", "diff_lock"])
	assert_array(ids.call(Registry.context("drone", true, {}))).contains(["arm"])


## A typo in a family name is a control that is never offered on any vehicle, and nothing else
## would notice: the gate just returns false forever.
func test_gate_families_are_real_vehicle_families() -> void:
	var families := _all_families()
	for entry in Registry.ENTRIES:
		for fam in entry.get("families", []) + entry.get("excludes", []):
			assert_bool(families.has(fam)) \
				.override_failure_message("registry row '%s' names family '%s', which is not in "
						% [entry["id"], fam] + "VehicleCatalog") \
				.is_true()


## The family gates are validated against the contract, not hand-copied from it (rule 4). A row
## that rides contract IN signals names them in `signals`, and the families it is offered to must
## be exactly the union of those signals' own `vehicles` lists.
##
## This is the guard that earns its keep: it is what caught `handbrake` omitting the plane, whose
## tricycle gear takes handbrake_torque on three RayWheels and whose park brake was therefore real
## in the sim and absent from the contract. Rows gated only by CAPABILITY (which is narrower than
## any family) still declare their families here so they are checked too — except `hitch`, which
## carries no `signals` for the reason written on the row.
func test_family_gates_match_the_contract() -> void:
	var contract := ContractScript.ContractData.parse(
			FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ).get_as_text())
	assert_array(contract.errors).is_empty()
	var all_families := _all_families()

	var checked := 0
	for entry in Registry.ENTRIES:
		var signal_names: Array = entry.get("signals", [])
		if signal_names.is_empty():
			continue
		var expected := {}
		for sig_name in signal_names:
			var sig := contract.get_signal_def(String(sig_name), "in")
			assert_object(sig) \
				.override_failure_message("registry row '%s' names contract signal '%s', which has "
						% [entry["id"], sig_name] + "no 'in' definition") \
				.is_not_null()
			for fam in sig.vehicles:
				expected[fam] = true
		var actual := {}
		for fam in Registry.families_of(entry, all_families):
			actual[fam] = true
		assert_array(actual.keys()) \
			.override_failure_message("registry row '%s' is offered to %s, but the contract says "
					% [entry["id"], str(actual.keys())] + "%s speak %s"
					% [str(expected.keys()), str(signal_names)]) \
			.contains_exactly_in_any_order(expected.keys())
		checked += 1
	assert_int(checked).is_greater(9)  # a silently-empty sweep would pass forever


func test_bindings_are_read_live_from_the_input_map() -> void:
	# Two-action rows read as one control on two keys, which is how a person thinks about them.
	assert_str(Registry.keys_for(Registry.find(&"drive"))).is_equal("W / S")
	assert_str(Registry.keys_for(Registry.find(&"steer"))).is_equal("A / D")
	assert_str(Registry.keys_for(Registry.find(&"climb"))).is_equal("R / F")
	assert_str(Registry.keys_for(Registry.find(&"pantograph"))).is_equal("U")


# --- the gate ----------------------------------------------------------------
# One case per shape the touch overlay used to hand-write, because a wrong gate is a control that
# silently does nothing rather than an error.

func test_family_gate_offers_a_control_only_to_the_family_that_has_it() -> void:
	assert_bool(Registry.applies(&"flaps", _ctx("plane"))).is_true()
	assert_bool(Registry.applies(&"flaps", _ctx("car"))).is_false()
	assert_bool(Registry.applies(&"arm", _ctx("drone"))).is_true()
	assert_bool(Registry.applies(&"arm", _ctx("plane"))).is_false()
	# Both aircraft share the one vertical axis.
	assert_bool(Registry.applies(&"climb", _ctx("plane"))).is_true()
	assert_bool(Registry.applies(&"climb", _ctx("drone"))).is_true()
	assert_bool(Registry.applies(&"climb", _ctx("boat"))).is_false()


## The one negative family gate: the train is rail-guided, so it has no steering surface.
func test_steer_applies_to_everything_except_the_train() -> void:
	assert_bool(Registry.applies(&"steer", _ctx("car"))).is_true()
	assert_bool(Registry.applies(&"steer", _ctx("boat"))).is_true()
	assert_bool(Registry.applies(&"steer", _ctx("train"))).is_false()


## sloppyCAN owns the contract IN signals while it drives, so those controls go away — but ONLY
## those. The shell conveniences have no signal behind them and must survive a live bridge, or
## a bridged session cannot change its own trailer or camera.
func test_bridge_takes_only_the_controls_it_owns() -> void:
	var live := Registry.context("train", true, {"tows": true})
	assert_bool(Registry.applies(&"pantograph", live)).is_false()
	assert_bool(Registry.applies(&"horn", live)).is_false()
	assert_bool(Registry.applies(&"handbrake", live)).is_false()
	assert_bool(Registry.applies(&"next_attachment", live)).is_true()
	assert_bool(Registry.applies(&"camera_view", live)).is_true()
	assert_bool(Registry.applies(&"respawn", live)).is_true()
	assert_bool(Registry.applies(&"to_menu", live)).is_true()


## PTO and TIP follow the CAPABILITY, not the family, and this is the case that proves why: both
## of these are family `truck`, and they disagree. A semi pulling a tipper has both; the same semi
## after one E press has neither.
func test_capability_gate_outranks_the_family() -> void:
	var tipper := _ctx("truck", {"tows": true, "pto": true, "lift": true})
	var bobtail := _ctx("truck", {"tows": true})
	assert_bool(Registry.applies(&"pto", tipper)).is_true()
	assert_bool(Registry.applies(&"hitch", tipper)).is_true()
	assert_bool(Registry.applies(&"pto", bobtail)).is_false()
	assert_bool(Registry.applies(&"hitch", bobtail)).is_false()
	assert_bool(Registry.applies(&"next_attachment", bobtail)).is_true()
	assert_bool(Registry.applies(&"next_attachment", _ctx("car"))).is_false()


## The driveline flags are spec-gated in BaseVehicle, so a car offering DIFF would be a button
## whose input the vehicle throws away.
func test_driveline_controls_follow_the_spec_flags() -> void:
	var tractor := _ctx("tractor", {"diff_lock": true, "fwd_drive": true})
	assert_bool(Registry.applies(&"diff_lock", tractor)).is_true()
	assert_bool(Registry.applies(&"fwd_drive", tractor)).is_true()
	assert_bool(Registry.applies(&"diff_lock", _ctx("car"))).is_false()
	assert_bool(Registry.applies(&"fwd_drive", _ctx("car"))).is_false()
	# pto_mode is tractor anatomy rather than a flag: one gearbox, always there.
	assert_bool(Registry.applies(&"pto_mode", _ctx("tractor"))).is_true()
	assert_bool(Registry.applies(&"pto_mode", _ctx("truck"))).is_false()


## The sheet's third column. A greyed row with no reason is worse than no row — it teaches
## nothing and looks broken.
func test_every_unavailable_row_says_why() -> void:
	var car := _ctx("car")
	for entry in Registry.ENTRIES:
		if Registry.applies_entry(entry, car):
			assert_str(Registry.gate_note(entry, car)) \
				.override_failure_message("row '%s' applies but carries a reason" % entry["id"]) \
				.is_empty()
		else:
			assert_str(Registry.gate_note(entry, car)) \
				.override_failure_message("row '%s' is greyed with no reason" % entry["id"]) \
				.is_not_empty()


## The touch stack's two columns are DERIVED from the gate, not declared, so a button cannot land
## in the "every vehicle has this" column while being vehicle-specific.
func test_universal_rows_are_the_ungated_ones() -> void:
	assert_bool(Registry.is_universal(Registry.find(&"horn"))).is_true()
	assert_bool(Registry.is_universal(Registry.find(&"to_menu"))).is_true()
	assert_bool(Registry.is_universal(Registry.find(&"flaps"))).is_false()
	assert_bool(Registry.is_universal(Registry.find(&"pto"))).is_false()
	assert_bool(Registry.is_universal(Registry.find(&"steer"))).is_false()
	# HAND sits in the vehicle column, not beside MENU: the boat and the drone have no handbrake.
	assert_bool(Registry.is_universal(Registry.find(&"handbrake"))).is_false()
	assert_bool(Registry.applies(&"handbrake", _ctx("plane"))).is_true()
	assert_bool(Registry.applies(&"handbrake", _ctx("boat"))).is_false()
	assert_bool(Registry.applies(&"handbrake", _ctx("drone"))).is_false()


## The web font has no emoji glyphs, so anything non-ASCII on a button renders as tofu.
func test_labels_are_present_and_plain_ascii() -> void:
	for entry in Registry.ENTRIES:
		var label := String(entry["label"])
		assert_str(label).is_not_empty()
		for text in [label, String(entry.get("touch_label", ""))]:
			for i in text.length():
				assert_int(text.unicode_at(i)) \
					.override_failure_message("row '%s' has a non-ASCII character in '%s'" % [
						entry["id"], text]) \
					.is_less(128)


## Every button kind the stack builds needs the field it is built from, or the loop reads a
## missing key and the button silently does nothing.
func test_touch_rows_carry_what_their_kind_needs() -> void:
	for entry in Registry.ENTRIES:
		var kind: int = entry.get("touch", Registry.Touch.NONE)
		if kind == Registry.Touch.NONE or kind == Registry.Touch.WIDGET:
			continue
		assert_str(String(entry.get("touch_label", ""))) \
			.override_failure_message("row '%s' has a touch button with no caption" % entry["id"]) \
			.is_not_empty()
		if kind == Registry.Touch.TAP or kind == Registry.Touch.HOLD:
			assert_str(String(entry.get("poll_key", ""))) \
				.override_failure_message("row '%s' writes no raw-intent key" % entry["id"]) \
				.is_not_empty()


## ...and a SHELL_SIGNAL row needs a signal at the other end. That map is the one hand-written
## thing left in the touch overlay, so it is the one place a new row can be forgotten — and the
## symptom is a button that does nothing at all. Checked against the overlay's own map rather
## than a copy of it here.
func test_every_shell_signal_row_has_a_handler() -> void:
	var overlay := TouchScript.new()
	var handlers: Dictionary = overlay._shell_signals()
	overlay.free()
	for entry in Registry.ENTRIES:
		if int(entry.get("touch", Registry.Touch.NONE)) != Registry.Touch.SHELL_SIGNAL:
			continue
		assert_bool(handlers.has(entry["id"])) \
			.override_failure_message("registry row '%s' asks for a shell-signal button, but "
					% entry["id"] + "TouchControls has no signal for it") \
			.is_true()


## ...and the case above CANNOT reach: a car is refused by every capability row's FAMILY first, so
## `gate_note` returns the family phrase and CAP_NOTE is never consulted. A capability with no
## entry there falls through to the generic "unavailable", which is a greyed row that teaches
## nothing — and nothing else would have caught it. Sweep each row in ITS OWN family with no
## capabilities granted, which is the state a machine that lacks the hardware is actually in.
func test_every_capability_row_names_the_hardware_it_wants() -> void:
	for entry in Registry.ENTRIES:
		var cap := String(entry.get("capability", ""))
		if cap == "":
			continue
		var families: Array = entry.get("families", [])
		var family := String(families[0]) if not families.is_empty() else "car"
		var note := Registry.gate_note(entry, _ctx(family))
		var msg := "row '%s' (capability '%s') has no CAP_NOTE" % [entry["id"], cap]
		assert_str(note).override_failure_message(msg).is_not_equal("unavailable")
		assert_str(note).override_failure_message(msg).is_not_empty()


# --- relevant_entry: the CONTROLS sheet's hide-vs-grey rule -------------------

## `relevant_entry` is `applies_entry` with the bridge gate forced open: a row that fits the
## vehicle stays relevant however sloppyCAN is driving, so the sheet greys it instead of hiding
## it, and that reason (BRIDGE_NOTE) can still surface from `gate_note`.
func test_relevant_entry_ignores_only_the_bridge_gate() -> void:
	var live := Registry.context("car", true, {})
	# handbrake is bridge_owned and fits a car (excludes only boat/drone), so it disagrees with
	# applies_entry only because the bridge is live right now.
	var handbrake := Registry.find(&"handbrake")
	assert_bool(Registry.applies_entry(handbrake, live)).is_false()
	assert_bool(Registry.relevant_entry(handbrake, live)).is_true()
	assert_str(Registry.gate_note(handbrake, live)).is_equal(Registry.BRIDGE_NOTE)


## Fallback (a live bridge carrying no driving control): a `driving` row is the keyboard's again,
## while every other bridge-owned row stays sloppyCAN's and says so without claiming it drives.
func test_fallback_frees_only_the_driving_rows() -> void:
	var fallback := Registry.context("car", true, {}, false)
	assert_bool(Registry.applies(&"handbrake", fallback)).is_true()
	assert_bool(Registry.applies(&"headlights", fallback)).is_true()
	assert_bool(Registry.applies(&"horn", fallback)).is_true()
	var tractor := Registry.context("tractor", true, {"pto": true}, false)
	var pto := Registry.find(&"pto")
	assert_bool(Registry.applies_entry(pto, tractor)).is_false()
	assert_str(Registry.gate_note(pto, tractor)).is_equal(Registry.BRIDGE_SETS_NOTE)
	# The drone's arm and vertical axis are driving rows: fallback flies it from the keyboard.
	var drone := Registry.context("drone", true, {}, false)
	assert_bool(Registry.applies(&"arm", drone)).is_true()
	assert_bool(Registry.applies(&"climb", drone)).is_true()
	assert_bool(Registry.applies(&"flight_mode", drone)).is_false()


## Family and capability gates still hide the row under `relevant_entry` — only the bridge gate
## is forced open, or a car would show every tractor-only control, greyed forever.
func test_relevant_entry_still_hides_family_and_capability_gates() -> void:
	var car := Registry.context("car", true, {})
	assert_bool(Registry.relevant_entry(Registry.find(&"flaps"), car)).is_false()
	assert_bool(Registry.relevant_entry(Registry.find(&"pto"), car)).is_false()
	var bobtail := Registry.context("truck", true, {"tows": true})
	assert_bool(Registry.relevant_entry(Registry.find(&"pto"), bobtail)).is_false()


# --- the on-screen rail --------------------------------------------------------

## The rail carries MENU/GARAGE/LEVEL/CAMERA plus ATTACH (a vehicle control, not a shell one) —
## RESPAWN and NIGHT are keyboard-only, reached on touch through the pause menu.
func test_the_touch_rail_is_exactly_menu_garage_level_challenges_camera_and_attach() -> void:
	var labels := {}
	for entry in Registry.ENTRIES:
		if int(entry.get("touch", Registry.Touch.NONE)) == Registry.Touch.SHELL_SIGNAL:
			labels[String(entry.get("touch_label", ""))] = true
	assert_array(labels.keys()).contains_exactly_in_any_order(
			["MENU", "VEHICLE", "LEVEL", "CHALLENGE", "CAMERA", "ATTACH"])
	assert_bool(Registry.applies(&"respawn", _ctx("car"))).is_true()
	assert_int(Registry.find(&"respawn").get("touch", Registry.Touch.NONE)).is_equal(Registry.Touch.NONE)
	assert_int(Registry.find(&"day_night").get("touch", Registry.Touch.NONE)).is_equal(Registry.Touch.NONE)


## The overlay's STACK_HEAD names real SHELL_SIGNAL rows, so MENU/GARAGE/LEVEL can't silently
## fall out of the head of the stack after a registry edit.
func test_stack_head_names_shell_signal_rows() -> void:
	for id: StringName in TouchControls.STACK_HEAD:
		assert_int(int(Registry.find(id).get("touch", Registry.Touch.NONE))) \
				.is_equal(Registry.Touch.SHELL_SIGNAL)
	assert_that(TouchControls.STACK_HEAD[0]).is_equal(&"to_menu")


## A `touch_state` names the VehicleInput field the overlay reads back each frame; a typo reads
## null, and the button just never shows ON.
func test_every_touch_state_is_a_vehicle_input_field() -> void:
	var fields := {}
	for p in VehicleInput.new().get_property_list():
		fields[String(p["name"])] = true
	for entry in Registry.ENTRIES:
		var field := String(entry.get("touch_state", ""))
		if field == "":
			continue
		assert_bool(fields.has(field)) \
			.override_failure_message("row '%s' touch_state '%s' is not a VehicleInput field"
					% [entry["id"], field]) \
			.is_true()


## The important column and the driving pads hide on two different keys, so putting the pads
## away never takes MENU with them.
func test_important_and_driving_layers_toggle_on_separate_keys() -> void:
	assert_bool(InputMap.has_action("toggle_important")).is_true()
	assert_bool(InputMap.has_action("toggle_touch")).is_true()
	assert_str(Registry.keys_for(Registry.find(&"toggle_important"))) \
			.is_not_equal(Registry.keys_for(Registry.find(&"toggle_touch")))


## LEVEL reaches the keyboard too (L is already headlights; the free key here is 4), same as
## every other rail button.
func test_level_select_is_bound_and_registered() -> void:
	assert_bool(InputMap.has_action("level_select")).is_true()
	var entry := Registry.find(&"level_select")
	assert_str(String(entry.get("touch_label", ""))).is_equal("LEVEL")
	assert_str(Registry.keys_for(entry)).is_not_empty()


# --- helpers -----------------------------------------------------------------

func _ctx(family: String, caps := {}) -> Dictionary:
	return Registry.context(family, false, caps)


func _pad(slot: String, ctx: Dictionary, paused := false) -> String:
	return String(Registry.pad_action(slot, ctx, paused))


func _all_families() -> PackedStringArray:
	var out := PackedStringArray()
	for variant in Catalog.VARIANTS:
		var fam: String = Catalog.VARIANTS[variant]["family"]
		if not out.has(fam):
			out.append(fam)
	return out


## Every GAME action bound in project.godot. `ui_*` is the engine's own menu navigation (91 of the
## 119 entries here) — not controls anyone drives with, and not this project's to document.
func _bound_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for prop in ProjectSettings.get_property_list():
		var pname: String = prop["name"]
		if not pname.begins_with("input/"):
			continue
		var action := pname.trim_prefix("input/")
		if not action.begins_with("ui_"):
			out.append(action)
	return out
