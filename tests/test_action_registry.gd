extends GdUnitTestSuite
## The action registry: the one description of what every bound control is, who has it, and what
## its on-screen button says. Two consumers read it (the pause menu's CONTROLS sheet and the touch
## overlay's button stack), so these tests protect the property that made it worth building:
##
##   AN ACTION CANNOT EXIST WITHOUT BEING DOCUMENTED. The hand-typed help this replaced had drifted
##   to ten missing actions and six with no touch button, silently, over months. test_every_bound
##   _action_is_registered is what makes that a CI failure instead of a discovery.
##
## Pure static data + pure functions, so the whole suite runs off preloads with no autoload and no
## scene tree (standing rule 8), exactly like test_input_arbitration.

const Registry := preload("res://src/input/action_registry.gd")
const RouterScript := preload("res://src/input/input_router.gd")
const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const TouchScript := preload("res://src/ui/touch_controls.gd")


## Every action bound in project.godot appears in exactly one registry row. Enumerated from
## ProjectSettings rather than a hand list, the same read test_input_map uses — a list here would
## be one more thing to forget to update, which is the bug this whole file exists to prevent.
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


## Every touch button's raw-intent key survives the keyboard/touch merge. InputRouter.merge_local
## builds its dict EXPLICITLY, so a key missing from it is not merely unmerged — it silently drops
## the KEYBOARD's edge too, for as long as a touch source is registered. That failure is invisible
## in game (the key just stops working on this one machine) and this is the cheap guard.
func test_every_touch_poll_key_is_merged() -> void:
	var merged := RouterScript.merge_local({}, {})
	for entry in Registry.ENTRIES:
		var key := String(entry.get("poll_key", ""))
		if key == "":
			continue
		assert_bool(merged.has(key)) \
			.override_failure_message("registry row '%s' polls '%s', which InputRouter.merge_local "
					% [entry["id"], key] + "does not merge — the keyboard's edge would be dropped") \
			.is_true()


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


## THE FAMILY GATES ARE VALIDATED AGAINST THE CONTRACT, not hand-copied from it (rule 4). A row
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


## Rule 10: the web font has no emoji glyphs, so anything non-ASCII on a button renders as tofu.
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


# --- helpers -----------------------------------------------------------------

func _ctx(family: String, caps := {}) -> Dictionary:
	return Registry.context(family, false, caps)


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
