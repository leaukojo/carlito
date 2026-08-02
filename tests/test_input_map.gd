extends GdUnitTestSuite
## Project input-map sanity: no two game actions may share a physical key — a duplicate
## silently fires both actions on one press (regression: `hitch` and `next_vehicle` were
## both on V, so V on the tractor cycled the variant AND toggled the hitch).


func test_no_two_actions_share_a_physical_key() -> void:
	var owner_of := {}  # physical keycode -> action name
	for prop in ProjectSettings.get_property_list():
		var pname: String = prop["name"]
		if not pname.begins_with("input/"):
			continue
		var action := pname.trim_prefix("input/")
		var setting: Dictionary = ProjectSettings.get_setting(pname)
		for ev in setting.get("events", []):
			var key_ev := ev as InputEventKey
			if key_ev == null or key_ev.physical_keycode == KEY_NONE:
				continue
			var code := key_ev.physical_keycode
			if owner_of.has(code) and owner_of[code] != action:
				fail("physical key %s bound to both '%s' and '%s'" % [
					OS.get_keycode_string(code), owner_of[code], action])
			owner_of[code] = action
	assert_dict(owner_of).is_not_empty()
