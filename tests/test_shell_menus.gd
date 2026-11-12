extends GdUnitTestSuite
## Shell menus: level-select, vehicle selector. PREVIEW not tested (needs renderer).

const WorldConditions := preload("res://src/levels/base/world_conditions.gd")
const CardGrid := preload("res://src/ui/card_grid.gd")

func _buttons(node: Node) -> Array:
	var out := []
	for b in node.find_children("*", "Button", true, false):
		out.append(b)
	return out


## Cards: name on child Label, text empty (picture card convention).
func _cards(sel: Control) -> Array:
	var out := []
	for b in _buttons(sel):
		if (b as Button).text.is_empty():
			out.append(b)
	return out


## The entries level select lists: not dev fixtures (test assets); challenge arenas included.
func _shipped() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in LevelRegistry.LEVELS:
		if not bool(entry.get("dev", false)):
			out.append(entry)
	return out


func test_level_select_lists_registry_and_emits_scene() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var cards := _cards(sel)
	var shipped := _shipped()
	assert_int(cards.size()).is_equal(shipped.size())

	var chosen := [""]
	sel.level_chosen.connect(func(path: String) -> void: chosen[0] = path)
	cards[0].pressed.emit()
	assert_str(chosen[0]).is_equal(String(shipped[0]["scene"]))


## Pause-menu section: can leave without picking (shell wires BACK and Esc).
func test_level_select_back_emits_closed() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var closed := [false]
	sel.closed.connect(func() -> void: closed[0] = true)
	for b in _buttons(sel):
		if b.text == "BACK":
			b.pressed.emit()
	assert_bool(closed[0]).is_true()


## MORE INFO toggles the long intro and relabels itself (its handler once saw a null button).
func test_challenge_select_more_info_toggles_and_relabels() -> void:
	var sel: ChallengeSelect = auto_free(ChallengeSelect.new())
	sel.setup(ChallengeProgress.new("", ChallengeRegistry.ids()))
	add_child(sel)
	_press(sel, "MORE INFO")
	assert_array(_labels(sel)).contains(["LESS INFO"])
	_press(sel, "LESS INFO")
	assert_array(_labels(sel)).contains(["MORE INFO"])


## Moving the mouse with a button down (a click that drifts) must not drop focus: the pressed
## button would cancel the click.
class _HeldMouse extends UiScale:
	func _mouse_held() -> bool:
		return true


func test_ui_scale_keeps_focus_while_a_mouse_button_is_down() -> void:
	var ui: UiScale = auto_free(_HeldMouse.new())
	add_child(ui)
	var button := Button.new()
	ui.add_child(button)
	button.grab_focus()
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(2.0, 0.0)
	ui._input(move)
	assert_bool(button.has_focus()).is_true()


## The last device used is the UI's one input mode: pointer motion drops keyboard focus, and a
## navigation press with nothing focused focuses the first usable control (the hovered one, when
## there is one) instead of doing nothing.
func test_ui_scale_tracks_the_device_and_focuses_on_a_nav_press() -> void:
	var ui: UiScale = auto_free(UiScale.new())
	add_child(ui)
	var overlay := Control.new()
	ui.add_child(overlay)
	var gone := Button.new()
	gone.disabled = true
	var first := Button.new()
	var second := Button.new()
	for b in [gone, first, second]:
		overlay.add_child(b)
	assert_int(ui.device()).is_equal(UiScale.Device.POINTER)

	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	ui._input(down)
	assert_int(ui.device()).is_equal(UiScale.Device.KEYBOARD)
	assert_bool(first.has_focus()).is_true()  # not the disabled one, not the second

	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	ui._input(pad)
	assert_int(ui.device()).is_equal(UiScale.Device.PAD)

	var move := InputEventMouseMotion.new()
	move.relative = Vector2(3.0, 0.0)
	ui._input(move)
	assert_int(ui.device()).is_equal(UiScale.Device.POINTER)
	assert_bool(first.has_focus()).is_false()

	var rest := InputEventJoypadMotion.new()  # a resting stick is not the pad being used
	rest.axis_value = 0.1
	ui._input(rest)
	assert_int(ui.device()).is_equal(UiScale.Device.POINTER)


## Every device used this session is remembered past the last one (the CONTROLS sheet's columns),
## and a finger is told apart from the mouse.
func test_ui_scale_remembers_every_device_used() -> void:
	var ui: UiScale = auto_free(UiScale.new())
	add_child(ui)
	assert_bool(ui.has_used(UiScale.Device.KEYBOARD)).is_false()
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	ui._input(key)
	var click := InputEventMouseButton.new()
	click.pressed = true
	ui._input(click)
	assert_bool(ui.has_used(UiScale.Device.KEYBOARD)).is_true()
	assert_bool(ui.has_used(UiScale.Device.PAD)).is_false()
	assert_bool(ui.has_touched()).is_false()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	ui._input(touch)
	assert_bool(ui.has_touched()).is_true()
	assert_bool(ui.has_used(UiScale.Device.KEYBOARD)).is_true()


func test_level_select_hides_dev_fixtures() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var tooltips := []
	for b in _buttons(sel):
		tooltips.append(b.tooltip_text)
	for entry in LevelRegistry.LEVELS:
		var desc := String(entry.get("desc", ""))
		if bool(entry.get("dev", false)):
			assert_array(tooltips).not_contains([desc])
		elif bool(entry.get("arena", false)):
			assert_array(tooltips).contains([desc])  # free play reaches an arena's pad


func test_level_select_cards_carry_the_registry_description() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var cards := _cards(sel)
	var shipped := _shipped()
	for i in shipped.size():
		var entry: Dictionary = shipped[i]
		assert_str(String(entry.get("desc", ""))).is_not_empty()
		assert_str(cards[i].tooltip_text).is_equal(String(entry["desc"]))
		var texts := []
		for l in (cards[i] as Button).find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		assert_array(texts).contains([String(entry["name"])])


## Bake weight on card (empty if no bake, like garage).
func test_level_select_cards_show_the_bake_weight() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var cards := _cards(sel)
	var shipped := _shipped()
	for i in shipped.size():
		var texts := []
		for l in (cards[i] as Button).find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		var weight := LevelRegistry.weight_text(String(shipped[i]["scene"]))
		if weight.is_empty():
			for t in texts:
				assert_str(String(t)).not_contains("MB")
		else:
			assert_array(texts).contains([weight])


const NO_BAKE := "no level_2.baked.scn: run tools/bake_levels.tscn"


## Weight reads as MB (answer "how long will this wait?"), empty if no bake. Formatted off a
## probe bake of a known size in user://, so it holds on an unbaked clone.
func test_weight_text_reads_as_megabytes() -> void:
	var probe := "user://weight_probe.tscn"
	var bake := "user://weight_probe.baked.scn"
	var bytes := PackedByteArray()
	bytes.resize(1572864)   # 1.5 MiB
	var f := FileAccess.open(bake, FileAccess.WRITE)
	assert_object(f).override_failure_message("cannot write the probe bake " + bake).is_not_null()
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	assert_int(LevelRegistry.weight_bytes(probe)).is_equal(1572864)
	assert_str(LevelRegistry.weight_text(probe)).is_equal("1.5 MB")
	DirAccess.remove_absolute(bake)
	assert_str(LevelRegistry.weight_text(probe)).is_empty()
	assert_str(LevelRegistry.weight_text(LevelRegistry.scene_of("garage"))).is_empty()
	assert_str(LevelRegistry.weight_text("res://nope/nope.tscn")).is_empty()


## The table the export ships for the web, where an island's bake is not on disk until its
## level pack is mounted: the same bytes the card reads here. Reads the real level_2 bake: CI
## bakes before the suite; locally, run tools/bake_levels.tscn first.
func test_bake_weights_carry_every_baked_level() -> void:
	var w := LevelRegistry.bake_weights()
	var level_2 := LevelRegistry.scene_of("level_2")
	assert_int(int(w.get(level_2, 0))).override_failure_message(NO_BAKE).is_greater(0)
	assert_int(int(w.get(level_2, 0))).is_equal(LevelRegistry.weight_bytes(level_2))
	assert_bool(w.has(LevelRegistry.scene_of("garage"))).is_false()


## The families table the export ships, and the level select's read of it where a level's LevelInfo
## is not loadable (an island on the web before its pack is mounted).
func test_allowed_families_come_from_level_info_else_the_shipped_table() -> void:
	var table := LevelRegistry.vehicle_table()
	assert_array(table.get(LevelRegistry.scene_of("open_sea"), [])).contains_exactly(["boat"])
	assert_bool(table.has(LevelRegistry.scene_of("level_2"))).is_true()
	assert_array(Array(LevelRegistry.allowed_vehicles_of(LevelRegistry.scene_of("open_sea")))) \
			.contains_exactly(["boat"])
	var packed_away := "res://src/levels/island/not_mounted/not_mounted.tscn"
	LevelRegistry._shipped[LevelRegistry.SHIPPED_VEHICLES] = {packed_away: ["car", "boat"]}
	var got: Variant = LevelRegistry.allowed_vehicles_of(packed_away)
	var unknown: Variant = LevelRegistry.allowed_vehicles_of("res://nope/nope.tscn")
	LevelRegistry._shipped.erase(LevelRegistry.SHIPPED_VEHICLES)
	assert_array(Array(got)).contains_exactly(["car", "boat"])
	assert_bool(unknown == null).is_true()


## Selector on level with allowed families; emits VARIANT not family.
func _selector(allowed: PackedStringArray, variant: String,
		rail := false, attachment := "", tyres := {}) -> VehicleSelect:
	var sel: VehicleSelect = auto_free(VehicleSelect.new())
	sel.setup(allowed, "Test Level", rail, variant, attachment, false, Callable(), tyres)
	add_child(sel)
	return sel


func _labels(node: Node) -> Array:
	var out := []
	for b in _buttons(node):
		out.append((b as Button).text)
	return out


func _press(node: Node, label: String) -> void:
	for b in _buttons(node):
		if (b as Button).text == label:
			(b as Button).pressed.emit()


## Picture cards only: name on child Label, text empty (level-select convention).
func _card_names(sel: VehicleSelect) -> Array:
	var out := []
	for b in _buttons(sel):
		if not (b as Button).text.is_empty():
			continue
		for l in (b as Button).find_children("*", "Label", true, false):
			out.append((l as Label).text)
	return out


func test_vehicle_select_lists_every_family_and_emits_the_variant() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan-sports")
	var labels := _labels(sel)
	for variant: String in VehicleCatalog.VARIANTS:
		var fam: String = VehicleCatalog.family_of(variant)
		var caption := fam.to_upper() + (" (beta)" if VehicleSelect.BETA_FAMILIES.has(fam) else "")
		assert_array(labels).contains([caption])
	assert_array(labels).contains(["DRIVE", "BACK"])

	assert_array(_card_names(sel)).contains(["TAXI", "POLICE"])
	var picked := [""]
	sel.vehicle_chosen.connect(func(v: String) -> void: picked[0] = v)
	_press(sel, "DRIVE")
	assert_str(picked[0]).is_equal("sedan-sports")


func _texts(node: Node) -> String:
	var out := PackedStringArray()
	for l in node.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return "\n".join(out)


## Every family has a home level that allows it and can place it: a spawn marker that accepts it,
## or (the train) a closed rail loop.
func test_every_family_has_a_home_level_that_spawns_it() -> void:
	var families := {}
	for variant: String in VehicleCatalog.VARIANTS:
		families[VehicleCatalog.family_of(variant)] = true
	for family: String in families:
		var home := LevelRegistry.home_of(family)
		assert_str(home).override_failure_message("no home level for " + family).is_not_empty()
		assert_bool(bool(LevelRegistry.entry_of(home).get("dev", false))).is_false()
		assert_bool(LevelRegistry.info_of(home).allows(VehicleCatalog.first_in_family(family))) \
				.override_failure_message(family + " not allowed in its home").is_true()
		var root := (load(home) as PackedScene).instantiate()
		if family == "train":
			assert_object(RailTrack.find_closed_rail(root)) \
					.override_failure_message("no closed rail in the train's home").is_not_null()
		else:
			assert_object(VehicleSpawn.first_under(root, family)) \
					.override_failure_message("no spawn for %s in its home" % family).is_not_null()
		root.free()


## A family this level refuses is not refused: DRIVE names its home level and asks first. CANCEL
## and back() put the question away; LOAD sends the body after its gearbox, with no attachment
## for a body that tows nothing.
func test_vehicle_select_offers_the_home_level_for_a_refused_family() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan")
	_press(sel, "BOAT (beta)")
	assert_array(_labels(sel)).contains(["DRIVE IN OPEN SEA"])
	assert_str(_texts(sel)).contains("NOT IN TEST LEVEL: DRIVES IN OPEN SEA")
	var got := []
	sel.vehicle_chosen.connect(func(v: String) -> void: got.append("vehicle:" + v))
	sel.level_drive_chosen.connect(func(scene: String, v: String, att: Variant) -> void:
			got.append([scene, v, att]))
	_press(sel, "DRIVE IN OPEN SEA")
	assert_array(got).is_empty()
	assert_bool(sel._confirm.visible).is_true()
	assert_str(sel._confirm_title.text).is_equal("NOT AVAILABLE IN TEST LEVEL")
	_press(sel, "CANCEL")
	assert_bool(sel._confirm.visible).is_false()
	_press(sel, "DRIVE IN OPEN SEA")
	assert_bool(sel.back()).is_true()
	assert_bool(sel._confirm.visible).is_false()
	assert_bool(sel.back()).is_false()  # nothing of its own left: the shell closes the garage
	_press(sel, "DRIVE IN OPEN SEA")
	_press(sel, "LOAD OPEN SEA")
	assert_array(got).is_equal([[LevelRegistry.scene_of("open_sea"), sel._variant, null]])
	assert_str(VehicleCatalog.family_of(sel._variant)).is_equal("boat")


## A towing body carries its attachment to its home level; gearbox and tyre go first.
func test_vehicle_select_takes_the_trailer_to_the_home_level() -> void:
	var sel := _selector(PackedStringArray(["boat"]), "semi", false, TrailerCatalog.TRAILERS[1])
	assert_str(sel._tyre).is_not_empty()  # the semi offers a tyre choice, so one rides DRIVE
	var order := []
	sel.gearbox_chosen.connect(func(_m: bool) -> void: order.append("gearbox"))
	sel.tyre_chosen.connect(func(_v: String, _id: String) -> void: order.append("tyre"))
	sel.level_drive_chosen.connect(func(scene: String, v: String, att: Variant) -> void:
			order.append([scene, v, att]))
	_press(sel, "DRIVE IN FLATLAND")
	_press(sel, "LOAD FLATLAND")
	assert_array(order).is_equal(["gearbox", "tyre",
			[LevelRegistry.scene_of("flatland"), "semi", TrailerCatalog.TRAILERS[1]]])


## A phone-width window: the footer and the question's buttons narrow to fit, the longest DRIVE
## text wrapping rather than pushing them off the edge.
func test_vehicle_select_footer_fits_a_narrow_window() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan")
	_press(sel, "TRAIN (beta)")
	_press(sel, "DRIVE IN LEVEL 5 - RAILWAY")
	sel.size = Vector2(380, 720)
	var room := 380.0 - UiTheme.px(sel, UiTheme.MARGIN * 2.0)
	for row: Control in [sel._drive_btn.get_parent(), sel._confirm_load.get_parent()]:
		assert_float(row.get_combined_minimum_size().x).is_less_equal(room)
	assert_float(sel._confirm_line.get_parent().get_parent().get_combined_minimum_size().x) \
			.is_less_equal(room)
	sel.size = Vector2(1600, 900)
	assert_float(sel._drive_btn.custom_minimum_size.x).is_equal(
			UiTheme.px(sel, VehicleSelect.FOOTER_W))


## The refusal survives only on the family's own home level, when even that cannot place it.
func test_vehicle_select_refuses_only_on_the_home_level_itself() -> void:
	var sel: VehicleSelect = auto_free(VehicleSelect.new())
	sel.setup(PackedStringArray(), "Flatland", false, "sedan", "", false,
			func(_f) -> bool: return false, {}, LevelRegistry.scene_of("flatland"))
	add_child(sel)
	assert_bool(sel._drive_btn.disabled).is_true()
	assert_str(sel._drive_btn.text).is_equal("DRIVE")
	assert_str(_texts(sel)).contains("CANNOT SPAWN HERE")
	_press(sel, "TRAIN (beta)")  # its home is elsewhere: offered, not refused
	assert_bool(sel._drive_btn.disabled).is_false()
	assert_str(sel._drive_btn.text).is_equal("DRIVE IN LEVEL 5 - RAILWAY")


## Attachment row appears only for towing machines (semi yes, garbage truck no).
func test_vehicle_select_offers_the_attachment_row_only_where_the_machine_tows() -> void:
	var towing := _selector(PackedStringArray(["truck"]), "semi")
	var names := _card_names(towing)
	assert_array(names).contains(["TIPPER", "TANKER", "NONE"])  # NONE is bobtail, a real entry

	var solo := _selector(PackedStringArray(["truck"]), "garbage-truck")
	assert_array(_card_names(solo)).not_contains(["TIPPER"])


## Attachment emitted as second signal after body (shell applies both).
func test_vehicle_select_emits_the_attachment_behind_the_body() -> void:
	var sel := _selector(PackedStringArray(["truck"]), "semi", false, TrailerCatalog.TRAILERS[1])
	var order := []
	sel.vehicle_chosen.connect(func(v: String) -> void: order.append(v))
	sel.attachment_chosen.connect(func(id: String) -> void: order.append(id))
	_press(sel, "DRIVE")
	assert_array(order).is_equal(["semi", TrailerCatalog.TRAILERS[1]])


## The gearbox choice exists only where the contract takes a gear byte, defaults to automatic, and
## rides DRIVE as its own signal.
func test_vehicle_select_offers_the_gearbox_only_where_the_family_takes_a_gear() -> void:
	var car := _selector(PackedStringArray(["car"]), "sedan-sports")
	assert_array(_labels(car)).contains(["AUTOMATIC", "MANUAL"])
	# Live with no bridge too: MANUAL is then the local driver's own shift control.
	for b in _buttons(car):
		if (b as Button).text == "MANUAL":
			assert_bool((b as Button).disabled).is_false()
	var chosen := []
	car.gearbox_chosen.connect(func(m: bool) -> void: chosen.append(m))
	_press(car, "DRIVE")
	_press(car, "MANUAL")
	_press(car, "DRIVE")
	assert_array(chosen).is_equal([false, true])

	var boat := _selector(PackedStringArray(["boat"]), "boat-speed-a")
	assert_array(_labels(boat)).not_contains(["AUTOMATIC", "MANUAL"])
	var boat_chosen := []
	boat.gearbox_chosen.connect(func(m: bool) -> void: boat_chosen.append(m))
	_press(boat, "DRIVE")
	assert_array(boat_chosen).is_empty()


## TYRES lists what the variant's fit is made in, stock first; it opens on the stored class when
## that fits (else the stock) and rides DRIVE as its own signal.
func test_vehicle_select_offers_the_tyres_the_variant_fits() -> void:
	var car := _selector(PackedStringArray(["car"]), "sedan")
	assert_array(_labels(car)).contains(["ALL-SEASON", "SUMMER", "WINTER", "STUDDED WINTER"])
	assert_array(_labels(car)).not_contains(["MUD", "SLICK", "M+S DRIVE"])
	var chosen := []
	car.tyre_chosen.connect(func(v: String, id: String) -> void: chosen.append(v + ":" + id))
	_press(car, "DRIVE")
	_press(car, "WINTER")
	_press(car, "DRIVE")
	assert_array(chosen).is_equal(["sedan:all_season", "sedan:winter"])

	var stored := _selector(PackedStringArray(["car"]), "sedan", false, "", {"sedan": "summer"})
	var unfitting := _selector(PackedStringArray(["car"]), "sedan", false, "", {"sedan": "mud"})
	var got := []
	stored.tyre_chosen.connect(func(_v: String, id: String) -> void: got.append(id))
	unfitting.tyre_chosen.connect(func(_v: String, id: String) -> void: got.append(id))
	_press(stored, "DRIVE")
	_press(unfitting, "DRIVE")
	assert_array(got).is_equal(["summer", "all_season"])


## The rows read GEARBOX, TYRES, BODY, top to bottom.
func test_vehicle_select_puts_the_tyres_between_gearbox_and_body() -> void:
	var car := _selector(PackedStringArray(["car"]), "sedan")
	var titles := []
	for l in car.find_children("*", "Label", true, false):
		if ["GEARBOX", "TYRES", "BODY"].has((l as Label).text.get_slice(" ", 0)):
			titles.append((l as Label).text.get_slice(" ", 0))
	assert_array(titles).is_equal(["GEARBOX", "TYRES", "BODY"])


## Only the stock fits (slicks): the row stays with that one class shown picked, so nothing below
## moves; no tyre at all (a boat): no row. Neither sends a tyre on DRIVE.
func test_vehicle_select_shows_the_lone_tyre_picked_and_none_for_a_boat() -> void:
	for pick: Array in [["car", "race"], ["boat", "boat-speed-a"]]:
		var sel := _selector(PackedStringArray([pick[0]]), pick[1])
		var chosen := []
		sel.tyre_chosen.connect(func(_v: String, id: String) -> void: chosen.append(id))
		_press(sel, "DRIVE")
		assert_array(chosen).is_empty()
		var slick: Array = _buttons(sel).filter(func(b: Button) -> bool: return b.text == "SLICK")
		if pick[0] == "car":
			assert_int(slick.size()).is_equal(1)
			assert_bool((slick[0] as Button).disabled).is_false()
			assert_bool((slick[0] as Button).button_pressed).is_true()
			(slick[0] as Button).pressed.emit()  # nothing else to pick: still no tyre sent
			_press(sel, "DRIVE")
			assert_array(chosen).is_empty()
		else:
			assert_array(slick).is_empty()


## What the cursor is on and what is picked wear different rims, on a card and on a choice button.
func test_hover_and_selection_use_different_rims() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var plain: Button = auto_free(CardGrid.card_button(host, 3.0, false))
	var picked: Button = auto_free(CardGrid.card_button(host, 3.0, true))
	assert_object(plain.get_theme_stylebox("hover").get("border_color")).is_not_equal(
			picked.get_theme_stylebox("normal").get("border_color"))
	assert_object(plain.get_theme_stylebox("hover").get("border_color")).is_equal(UiTheme.HOVER)
	assert_object(picked.get_theme_stylebox("hover").get("border_color")).is_equal(UiTheme.ACCENT)
	var theme := UiTheme.build(1.0)
	assert_object(theme.get_stylebox("hover", &"Choice").get("border_color")).is_equal(UiTheme.HOVER)
	assert_object(theme.get_stylebox("hover_pressed", &"Choice").get("border_color")).is_equal(UiTheme.ACCENT)


## A press on the body already picked pulses DRIVE once and leaves focus on the card, so a pad can
## still step to the next body.
func test_vehicle_select_a_press_on_the_picked_body_pulses_drive() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan")
	var drive: Button = _buttons(sel).filter(func(b: Button) -> bool: return b.text == "DRIVE")[0]
	var picked: Button = _buttons(sel).filter(func(b: Button) -> bool:
			return b.text.is_empty() and b.get_theme_stylebox("normal").get("border_color") == UiTheme.ACCENT)[0]
	picked.grab_focus()
	picked.pressed.emit()
	assert_bool(drive.has_focus()).is_false()
	assert_bool(picked.has_focus()).is_true()
	assert_float(sel._pulse_left).is_equal(VehicleSelect.PULSE_S)
	var idle := _selector(PackedStringArray(["car"]), "sedan")
	idle._process(0.3)
	assert_object(idle._drive_btn.modulate).is_equal(Color.WHITE)  # no pulse until asked for


## Pressing a different body rebuilds the cards; a pad keeps its place on that body's new card (a
## mouse needs no focus there), so right / left go on from it.
func test_vehicle_select_keeps_the_pad_on_the_card_it_pressed() -> void:
	var ui: UiScale = auto_free(UiScale.new())
	add_child(ui)
	var sel: VehicleSelect = VehicleSelect.new()
	sel.setup(PackedStringArray(["car"]), "T", false, "sedan", "")
	ui.add_child(sel)
	var other: Button = _cards(sel)[1]
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_RIGHT
	ui._input(key)  # a key or pad is the device in use
	other.grab_focus()
	var pick := String(other.get_meta("pick"))
	other.pressed.emit()
	var focus := sel.get_viewport().gui_get_focus_owner()
	assert_object(focus).is_not_null()
	assert_str(String(focus.get_meta("pick", ""))).is_equal(pick)
	ui._input(InputEventMouseButton.new())  # now the mouse: no focus is put back
	var third: Button = _cards(sel)[2]
	third.grab_focus()
	third.pressed.emit()
	assert_object(sel.get_viewport().gui_get_focus_owner()).is_null()


## A card's caption sits under its picture, never over it, and the picture keeps its whole frame.
func test_picture_card_puts_the_caption_below_the_picture() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var path := LevelShot.thumb_path("flatland")
	var card := CardGrid.picture_card(host, 320.0, 0.594, 3.0, false, path, "NAME")
	host.add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	var thumb: TextureRect = card.find_children("*", "TextureRect", true, false)[0] \
			if ResourceLoader.exists(path) else null
	var caption: Label = card.find_children("*", "Label", true, false).filter(
			func(l: Label) -> bool: return l.text == "NAME")[0]
	if thumb != null:
		assert_float(caption.global_position.y).is_greater_equal(
				thumb.global_position.y + thumb.size.y - 0.5)
		assert_int(thumb.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_float(card.size.y).is_greater_equal(card.custom_minimum_size.y - 0.5)


## Every registered level has the LevelInfo the description panel reads its families from.
func test_every_level_has_an_info_beside_its_scene() -> void:
	for entry in LevelRegistry.LEVELS:
		var info := LevelRegistry.info_of(String(entry["scene"]))
		assert_object(info).override_failure_message(String(entry["id"])).is_not_null()
	assert_object(LevelRegistry.info_of("res://nope/nope.tscn")).is_null()


## The panel under the grid names the focused level and lists the families it allows.
func test_level_select_describes_the_focused_level_with_its_families() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var open_sea := LevelRegistry.entry_of(LevelRegistry.scene_of("open_sea"))
	sel._show_entry(open_sea)
	var texts := sel.find_children("*", "Label", true, false).map(
			func(l: Node) -> String: return (l as Label).text)
	assert_array(texts).contains(["OPEN SEA", String(open_sea["desc"]), "VEHICLES: BOAT"])


## A theme rebuild (a resize) lays the cards out again at the new scale instead of keeping the old.
func test_selectors_rebuild_their_cards_on_a_theme_change() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var sel: LevelSelect = LevelSelect.new()
	host.add_child(sel)
	var narrow: float = _cards(sel)[0].custom_minimum_size.x
	host.theme = UiTheme.build(2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_cards(sel)[0].custom_minimum_size.x).is_greater(narrow * 1.5)
	var garage: VehicleSelect = auto_free(VehicleSelect.new())
	garage.setup(PackedStringArray(["car"]), "T", false, "sedan", "")
	host.add_child(garage)
	var card_w: float = _cards(garage)[0].custom_minimum_size.x
	host.theme = UiTheme.build(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_cards(garage)[0].custom_minimum_size.x).is_less(card_w * 0.7)


## The challenge panels and the loading screen re-apply their pixel sizes on a theme change.
func test_panels_resize_their_buttons_and_bar_on_a_theme_change() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var def := ChallengeRegistry.def_of(ChallengeRegistry.ids()[0])
	var briefing: ChallengeBriefing = ChallengeBriefing.new()
	briefing.setup(def)
	host.add_child(briefing)
	var result: ChallengeResult = ChallengeResult.new()
	result.setup(def, true, 3.0, "", 2.0, false, true)
	host.add_child(result)
	var loading: LoadingScreen = LoadingScreen.new()
	host.add_child(loading)
	var widths := [_buttons(briefing)[0].custom_minimum_size.x,
			_buttons(result)[0].custom_minimum_size.x, loading._bar.custom_minimum_size.x]
	host.theme = UiTheme.build(2.0)
	await get_tree().process_frame
	assert_float(_buttons(briefing)[0].custom_minimum_size.x).is_greater(widths[0] * 1.5)
	assert_float(_buttons(result)[0].custom_minimum_size.x).is_greater(widths[1] * 1.5)
	assert_float(loading._bar.custom_minimum_size.x).is_greater(widths[2] * 1.5)


func test_tyre_choices_put_the_stock_first_in_catalog_order() -> void:
	var gd := (load("res://src/vehicles/truck/semi_spec.tres") as VehicleSpec).ground_drive
	var ids := VehicleSelect.tyre_choices(gd).map(func(c: TyreClass) -> String: return c.id)
	assert_array(ids).is_equal(["truck_drive", "winter", "mud"])
	assert_array(VehicleSelect.tyre_choices(null)).is_empty()


## Pause overlay: all entries reachable, each reaches shell. LEVEL only while the pad is in use.
func test_pause_menu_offers_the_shell_sections() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	var state := PauseMenu.State.new()
	state.level_row = true
	pause.setup({}, state)
	add_child(pause)
	var labels := []
	for b in _buttons(pause):
		labels.append(b.text)
	assert_array(labels).contains(["RESUME", "RESPAWN", "LEVEL", "SANDBOX", "CONTROLS",
			"SETTINGS"])
	# GARAGE is Create, G and touch's job; CHALLENGES is 5 and touch's; neither is this menu's.
	assert_array(labels).not_contains(["GARAGE", "CHALLENGES", "CONDITIONS", "LAB"])

	var fired := []
	pause.resume_requested.connect(func() -> void: fired.append("RESUME"))
	pause.respawn_requested.connect(func() -> void: fired.append("RESPAWN"))
	pause.level_requested.connect(func() -> void: fired.append("LEVEL"))
	for b in _buttons(pause):
		if b.text in ["RESUME", "RESPAWN", "LEVEL"]:
			b.pressed.emit()
	assert_array(fired).contains(["RESUME", "RESPAWN", "LEVEL"])

	var keyboard: PauseMenu = auto_free(PauseMenu.new())
	keyboard.setup({})
	add_child(keyboard)
	assert_array(_labels(keyboard)).not_contains(["LEVEL"])


## The shell builds LEVEL from the device in use as the menu opens.
func test_boot_pause_menu_has_level_only_on_the_pad() -> void:
	var boot := _booted()
	boot._ui._set_device(UiScale.Device.KEYBOARD)
	boot._open_pause()
	assert_array(_labels(boot._find_pause())).not_contains(["LEVEL"])
	boot._close_all_overlays()
	boot._ui._set_device(UiScale.Device.PAD)
	boot._open_pause()
	assert_array(_labels(boot._find_pause())).contains(["LEVEL"])


## SANDBOX: WORLD then VEHICLE, each headed; the driver aids say they are saved, the LAB switches
## that they are session-only; SETTINGS keeps only its three and no debug-label row.
func test_pause_menu_sandbox_holds_world_and_vehicle() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"abs": true, "axle_diff": true, "ackermann": true})
	add_child(pause)
	_press(pause, "SANDBOX")
	var texts := []  # the page's headings and buttons, in tree order
	for node in pause.find_children("*", "", true, false):
		if (node is Button or node is Label) and (node as Control).is_visible_in_tree():
			texts.append(node.get("text"))
	var order := ["WORLD", "WIND: LEVEL", "TIME: DAY", "VEHICLE", "TRACTION CONTROL: ON",
			"STABILITY CONTROL: ON", "AUTO HOLD: OFF", "ANTI-LOCK BRAKES: ON",
			"DIFFERENTIALS: STOCK", "STEERING: STOCK"]
	var at := -1
	for t: String in order:
		var i := texts.find(t)
		assert_int(i).override_failure_message(t).is_greater(at)
		at = i
	for help: String in [PauseMenu.TCS_HELP, PauseMenu.ESC_HELP, PauseMenu.AUTO_HOLD_HELP]:
		assert_str(help).ends_with(PauseMenu.SAVED)
	for help: String in [PauseMenu.ABS_HELP, PauseMenu.AXLE_DIFF_HELP, PauseMenu.STEERING_HELP]:
		assert_str(help).ends_with(PauseMenu.SESSION)
	# Every help line wraps at TEXT_W, so no row's help runs the width of the window.
	var widest := UiTheme.px(pause, PauseMenu.TEXT_W) + 0.5
	for l in pause.find_children("*", "Label", true, false):
		if (l as Label).theme_type_variation == &"Small" \
				and (l as Label).text != PauseMenu.DRIVE_FOOTNOTE:  # one short line
			assert_int((l as Label).autowrap_mode).override_failure_message((l as Label).text) \
					.is_equal(TextServer.AUTOWRAP_WORD_SMART)
			assert_float((l as Label).get_combined_minimum_size().x) \
					.override_failure_message((l as Label).text).is_less_equal(widest)
	# Every page's BACK wears the `Back` look.
	var backs := _buttons(pause).filter(func(b: Button) -> bool: return b.text == "BACK")
	assert_int(backs.size()).is_equal(4)  # CONTROLS, SETTINGS, SANDBOX, SPAWN POINT
	for b: Button in backs:
		assert_str(String(b.theme_type_variation)).is_equal("Back")
	# Focus lands on the page's first row, inside its scroll.
	assert_str((get_viewport().gui_get_focus_owner() as Button).text).is_equal("WIND: LEVEL")
	assert_bool(pause.back()).is_true()
	_press(pause, "SETTINGS")
	var settings := _buttons(pause).filter(func(b: Button) -> bool: return b.is_visible_in_tree()) \
			.map(func(b: Button) -> String: return b.text)
	assert_int(settings.size()).is_equal(4)  # DASHBOARD, UI SIZE, KEY RESPONSE, BACK
	assert_array(settings.filter(func(t: String) -> bool: return t.begins_with("EXTENDED"))) \
			.is_empty()
	assert_array(settings.filter(func(t: String) -> bool: return t.begins_with("TRACTION"))) \
			.is_empty()


## The L1 legend lists the vehicle's layer by button name, without the "L1 + " its title says,
## and a vehicle with nothing there says so.
func test_pad_legend_lists_the_vehicle_layer() -> void:
	var legend: PadLegend = auto_free(PadLegend.new())
	add_child(legend)
	legend.show_layer(ActionRegistry.context("drone", false, {}))
	var texts := []
	for label in legend.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_bool(legend.visible).is_true()
	assert_array(texts).contains(["Square", String(ActionRegistry.find(&"arm")["label"])])
	legend.show_layer(ActionRegistry.context("car", false, {}))
	texts.clear()
	for label in legend.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_array(texts).contains([PadLegend.EMPTY_TEXT])
	assert_array(texts).not_contains(["Square"])


## The hint is one line and nothing else (no title); the layer brings its title back.
func test_pad_legend_hint_is_one_line() -> void:
	var legend: PadLegend = auto_free(PadLegend.new())
	add_child(legend)
	legend.show_hint()
	var shown := []
	for label in legend.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			shown.append((label as Label).text)
	assert_array(shown).contains_exactly([PadLegend.HINT_TEXT])
	legend.show_layer(ActionRegistry.context("drone", false, {}))
	assert_bool(legend._title.visible).is_true()


## CONTROLS is a second page of the same overlay, and back() is what the shell calls on Esc
## before it decides to resume — so Esc walks the overlay out the way it came in.
func test_pause_menu_controls_page_is_backed_out_of() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	add_child(pause)
	assert_bool(pause.back()).is_false()  # already on the root page: Esc means resume
	for b in _buttons(pause):
		if b.text == "CONTROLS":
			b.pressed.emit()
	assert_bool(pause.back()).is_true()
	assert_bool(pause.back()).is_false()


## The sheet is GENERATED from ActionRegistry, and this is the drift fix seen from the UI side:
## `pantograph` is one of the ten actions the old hand-typed table had lost, and its label and its
## live binding both have to reach the page without anyone having typed either into this file.
func test_pause_menu_controls_page_is_generated_from_the_registry() -> void:
	var saved_vehicle := GameState.current_vehicle
	GameState.current_vehicle = "train"  # pantograph is relevant only here
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"tows": true, "pto": true, "lift": true})
	add_child(pause)
	pause._fit_pad(0.0)  # the text column, not the drawn pad
	var texts := []
	for label in pause.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var entry := ActionRegistry.find(&"pantograph")
	assert_array(texts).contains([String(entry["label"]), ActionRegistry.keys_for(entry),
			ActionRegistry.pad_for(entry)])
	# Every section heading is there, so no group of controls can go missing wholesale.
	assert_array(texts).contains(ActionRegistry.GROUP_TITLES)
	GameState.current_vehicle = saved_vehicle


## A row the current vehicle can never use (family/capability gate fails) is hidden outright —
## a car has no pantograph, and driving one is never going to change that.
func test_pause_menu_controls_page_hides_rows_the_vehicle_can_never_use() -> void:
	var saved_vehicle := GameState.current_vehicle
	GameState.current_vehicle = "car"
	var pause: PauseMenu = auto_free(PauseMenu.new())
	add_child(pause)
	var texts := []
	for label in pause.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var entry := ActionRegistry.find(&"pantograph")
	assert_array(texts).not_contains([String(entry["label"])])
	GameState.current_vehicle = saved_vehicle


## One column per device used this session; the mouse alone reads as the keyboard, or as touch on
## a touch display.
func test_pause_menu_sheet_columns_follow_the_devices_used() -> void:
	var C := PauseMenu.Column
	assert_array(PauseMenu.sheet_columns(true, false, false, false)).is_equal([C.KEY])
	assert_array(PauseMenu.sheet_columns(false, true, false, false)).is_equal([C.PAD])
	assert_array(PauseMenu.sheet_columns(true, true, false, true)).is_equal([C.KEY, C.PAD])
	assert_array(PauseMenu.sheet_columns(false, false, true, true)).is_equal([C.TOUCH])
	assert_array(PauseMenu.sheet_columns(false, false, false, false)).is_equal([C.KEY])
	assert_array(PauseMenu.sheet_columns(false, false, false, true)).is_equal([C.TOUCH])


## The sheet carries only the columns handed over, and drops a row none of them reaches: on the
## keyboard no GAMEPAD head and no pad-only recenter; on touch HAND by its caption, no F-key rows
## and no arrow-key footnote.
func test_pause_menu_controls_sheet_shows_only_the_devices_used() -> void:
	var saved_vehicle := GameState.current_vehicle
	GameState.current_vehicle = "car"
	var recenter := String(ActionRegistry.find(&"camera_recenter")["label"])
	var debug := ActionRegistry.find(&"debug_overlay")
	var hand := ActionRegistry.find(&"parking_brake")

	var state := PauseMenu.State.new()
	state.columns = [PauseMenu.Column.KEY]
	var keys := _sheet_texts(state)
	assert_array(keys).contains(["KEY", String(debug["label"]), ActionRegistry.keys_for(debug),
			PauseMenu.DRIVE_FOOTNOTE])
	assert_array(keys).not_contains(["GAMEPAD", "TOUCH", recenter, ActionRegistry.pad_for(hand)])

	state.columns = [PauseMenu.Column.TOUCH]
	var touch := _sheet_texts(state)
	assert_array(touch).contains(["TOUCH", String(hand["label"]), ActionRegistry.touch_for(hand),
			ActionRegistry.touch_for(ActionRegistry.find(&"drive"))])
	assert_array(touch).not_contains(["KEY", "GAMEPAD", String(debug["label"]),
			PauseMenu.DRIVE_FOOTNOTE])
	GameState.current_vehicle = saved_vehicle


## With the pad in use the GAMEPAD column is drawn where it fits, and is the text column where it
## does not (a narrow window): the table loses or regains the pad's names, the drawing hides or
## shows. On the pad alone a car has no L1 set, so one drawing.
func test_pause_menu_draws_the_pad_where_it_fits() -> void:
	var saved_vehicle := GameState.current_vehicle
	GameState.current_vehicle = "car"
	var hand := ActionRegistry.pad_for(ActionRegistry.find(&"parking_brake"))
	var state := PauseMenu.State.new()
	state.columns = [PauseMenu.Column.KEY, PauseMenu.Column.PAD]
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({}, state)
	add_child(pause)
	assert_int(pause._pad_diagrams.size()).is_equal(1)
	pause._fit_pad(100000.0)
	assert_bool(pause._pad_box.visible).is_true()
	assert_array(_table_texts(pause)).not_contains([hand])
	pause._fit_pad(0.0)
	assert_bool(pause._pad_box.visible).is_false()
	assert_array(_table_texts(pause)).contains([hand, "GAMEPAD"])

	state.columns = [PauseMenu.Column.KEY]
	var keys: PauseMenu = auto_free(PauseMenu.new())
	keys.setup({}, state)
	add_child(keys)
	assert_bool(keys._pad_diagrams.is_empty()).is_true()
	GameState.current_vehicle = saved_vehicle


func _table_texts(pause: PauseMenu) -> Array:
	var texts := []
	for label in pause._table.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _sheet_texts(state: PauseMenu.State) -> Array:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({}, state)
	add_child(pause)
	var texts := []
	for label in pause._controls.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


## SETTINGS is a page of this overlay like CONTROLS, and its one button CYCLES: it relabels
## itself and emits the new value, which the shell applies and persists. The menu applies
## nothing itself (standing rule 6), so what is asserted is what reaches the shell.
func test_pause_menu_settings_cycles_the_dashboard_density() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({})
	add_child(pause)
	_press(pause, "SETTINGS")

	var picked := []
	pause.dashboard_density_changed.connect(func(s: int) -> void: picked.append(s))
	var expected := Dashboard.next_setting(Dashboard.Density.COMPACT)
	_press(pause, "DASHBOARD: COMPACT")
	assert_array(picked).is_equal([expected])
	# The button says what it now is, so a second press cycles on from there rather than repeating.
	assert_array(_labels(pause)).contains(["DASHBOARD: %s" % Dashboard.key_of(expected).to_upper()])

	# Esc walks back out of this page the same way it does out of CONTROLS.
	assert_bool(pause.back()).is_true()
	assert_bool(pause.back()).is_false()


## SANDBOX's WORLD rows are like SETTINGS: cycling buttons that emit new values and apply nothing
## themselves (rule 6) — what is asserted is what reaches the shell.
func test_pause_menu_conditions_page_cycles_and_emits() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({})
	add_child(pause)
	_press(pause, "SANDBOX")

	var picked := []
	pause.conditions_changed.connect(func(w: int, c: int, d: float) -> void: picked.append([w, c, d]))
	_press(pause, "WIND: LEVEL")
	assert_int(picked.size()).is_equal(1)
	assert_int(picked[0][0]).is_equal(WorldConditions.next_preset(WorldConditions.Preset.LEVEL))
	assert_array(_labels(pause)).contains(["WIND: %s" % WorldConditions.PRESET_LABELS[picked[0][0]]])

	var nights := []
	pause.night_toggled.connect(func(on: bool) -> void: nights.append(on))
	_press(pause, "TIME: DAY")
	assert_array(nights).is_equal([true])
	assert_array(_labels(pause)).contains(["TIME: NIGHT"])

	assert_bool(pause.back()).is_true()
	assert_bool(pause.back()).is_false()


## Wind/current grey out (and say why) on a family the level's fields never read; the button
## still cycles, since the shell keeps the pick for whatever machine comes next.
func test_pause_menu_conditions_page_greys_wind_and_current_off_family() -> void:
	var saved_vehicle := GameState.current_vehicle
	GameState.current_vehicle = "train"  # neither a WIND nor a CURRENT family
	var pause: PauseMenu = auto_free(PauseMenu.new())
	add_child(pause)
	_press(pause, "SANDBOX")
	var disabled := {}
	for b in _buttons(pause):
		if (b as Button).text.begins_with("WIND") or (b as Button).text.begins_with("WATER CURRENT"):
			disabled[(b as Button).text] = (b as Button).disabled
	assert_bool(disabled.values().all(func(v: bool) -> bool: return v)).is_true()
	GameState.current_vehicle = saved_vehicle


## A challenge owns wind, current and lighting: every WORLD button greys out and says so.
func test_pause_menu_conditions_page_locks_during_a_challenge() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	var state := PauseMenu.State.new()
	state.conditions_locked = true
	pause.setup({}, state)
	add_child(pause)
	_press(pause, "SANDBOX")
	var locked := 0
	for b in _buttons(pause):
		var text := (b as Button).text
		if text.begins_with("WIND") or text.begins_with("WATER CURRENT") \
				or text.begins_with("FROM") or text.begins_with("TIME"):
			assert_bool((b as Button).disabled).override_failure_message(text).is_true()
			locked += 1
	assert_int(locked).is_equal(4)
	var said := 0
	for l in pause.find_children("*", "Label", true, false):
		if (l as Label).text == PauseMenu.LOCKED_HELP:
			said += 1
	assert_int(said).is_equal(4)


## LAB's ABS switch cycles and emits like SETTINGS (rule 6), and the ESC and TC rows say they
## went with it.
func test_pause_menu_lab_page_flips_abs_and_relabels_esc_and_tc() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"abs": true})
	add_child(pause)
	_press(pause, "SANDBOX")
	var picked := []
	pause.abs_off_changed.connect(func(off: bool) -> void: picked.append(off))
	_press(pause, "ANTI-LOCK BRAKES: ON")
	assert_array(picked).is_equal([true])
	assert_array(_labels(pause)).contains(["ANTI-LOCK BRAKES: OFF",
			"STABILITY CONTROL: OFF (WITH ABS)", "TRACTION CONTROL: OFF (WITH ABS)"])
	assert_bool(pause.back()).is_true()
	assert_bool(pause.back()).is_false()


## The switch greys out (and says why) on a body without ABS, and in a challenge, which drives stock.
func test_pause_menu_lab_page_greys_abs_without_it_and_in_a_challenge() -> void:
	var bare: PauseMenu = auto_free(PauseMenu.new())
	bare.setup({})
	add_child(bare)
	var locked: PauseMenu = auto_free(PauseMenu.new())
	var state := PauseMenu.State.new()
	state.lab_locked = true
	state.abs_off = true
	locked.setup({"abs": true}, state)
	add_child(locked)
	for pause: PauseMenu in [bare, locked]:
		for b in _buttons(pause):
			if (b as Button).text.begins_with("ANTI-LOCK BRAKES"):
				assert_bool((b as Button).disabled).is_true()
	var helps := locked.find_children("*", "Label", true, false).map(
			func(l: Node) -> String: return (l as Label).text)
	assert_array(helps).contains([PauseMenu.LOCKED_HELP])
	# A stored OFF never reaches the attempt, so ESC reads its own setting there.
	assert_array(_labels(locked)).contains(["STABILITY CONTROL: ON"])
	# Nor a body without ABS: a switch kept from the last body leaves its ESC and TC on.
	var race: PauseMenu = auto_free(PauseMenu.new())
	var kept := PauseMenu.State.new()
	kept.abs_off = true
	race.setup({}, kept)
	add_child(race)
	assert_array(_labels(race)).contains(["STABILITY CONTROL: ON", "TRACTION CONTROL: ON"])


## LAB's DIFFERENTIALS: LOCKED takes ESC and TC with it, and their rows say so.
func test_pause_menu_lab_locked_diffs_relabel_esc_and_tc() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"axle_diff": true})
	add_child(pause)
	_press(pause, "SANDBOX")
	_press(pause, "DIFFERENTIALS: STOCK")
	assert_array(_labels(pause)).contains(["STABILITY CONTROL: ON"])
	_press(pause, "DIFFERENTIALS: OPEN")
	assert_array(_labels(pause)).contains(["STABILITY CONTROL: OFF (WITH LOCKED DIFFS)",
			"TRACTION CONTROL: OFF (WITH LOCKED DIFFS)"])


## LAB's DIFFERENTIALS cycles STOCK, OPEN, LOCKED and back, emitting each (rule 6).
func test_pause_menu_lab_page_cycles_the_axle_diffs() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"axle_diff": true})
	add_child(pause)
	_press(pause, "SANDBOX")
	var picked := []
	pause.axle_diff_changed.connect(func(mode: VehicleInput.AxleDiff) -> void: picked.append(mode))
	for label in ["DIFFERENTIALS: STOCK", "DIFFERENTIALS: OPEN", "DIFFERENTIALS: LOCKED"]:
		_press(pause, label)
	assert_array(picked).is_equal([VehicleInput.AxleDiff.OPEN, VehicleInput.AxleDiff.LOCKED,
			VehicleInput.AxleDiff.STOCK])
	assert_array(_labels(pause)).contains(["DIFFERENTIALS: STOCK"])


## The row greys out without an axle diff and in a challenge; a body with its own DIFF LOCK key
## (the tractors) has no row at all.
func test_pause_menu_lab_page_greys_or_hides_the_axle_diffs() -> void:
	var bare: PauseMenu = auto_free(PauseMenu.new())
	bare.setup({})
	add_child(bare)
	var locked: PauseMenu = auto_free(PauseMenu.new())
	var state := PauseMenu.State.new()
	state.lab_locked = true
	locked.setup({"axle_diff": true}, state)
	add_child(locked)
	for pause: PauseMenu in [bare, locked]:
		for b in _buttons(pause):
			if (b as Button).text.begins_with("DIFFERENTIALS"):
				assert_bool((b as Button).disabled).is_true()
	var tractor: PauseMenu = auto_free(PauseMenu.new())
	tractor.setup({"diff_lock": true, "fwd_drive": true})
	add_child(tractor)
	assert_array(_labels(tractor).filter(
			func(t: String) -> bool: return t.begins_with("DIFFERENTIALS"))).is_empty()


## LAB's STEERING flips STOCK and PARALLEL, emitting each (rule 6); greyed without Ackermann and in
## a challenge.
func test_pause_menu_lab_page_flips_the_steering() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"ackermann": true})
	add_child(pause)
	_press(pause, "SANDBOX")
	var picked := []
	pause.parallel_steer_changed.connect(func(on: bool) -> void: picked.append(on))
	_press(pause, "STEERING: STOCK")
	_press(pause, "STEERING: PARALLEL")
	assert_array(picked).is_equal([true, false])
	var bare: PauseMenu = auto_free(PauseMenu.new())
	bare.setup({})
	add_child(bare)
	var locked: PauseMenu = auto_free(PauseMenu.new())
	var state := PauseMenu.State.new()
	state.lab_locked = true
	locked.setup({"ackermann": true}, state)
	add_child(locked)
	for menu: PauseMenu in [bare, locked]:
		for b in _buttons(menu):
			if (b as Button).text.begins_with("STEERING"):
				assert_bool((b as Button).disabled).is_true()


func test_vehicle_select_back_emits_closed() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan-sports")
	var closed := [false]
	sel.closed.connect(func() -> void: closed[0] = true)
	_press(sel, "BACK")
	assert_bool(closed[0]).is_true()


# --- boot's overlay stack -----------------------------------------------------

## A live Boot on flatland. `_ready()`'s own `_boot()` kicks off a threaded load that awaits
## `RenderingServer.frame_post_draw` — a frame this CLI test runner never presents, so that
## coroutine sits stuck at the await forever, harmlessly. Force the level in directly instead,
## the same scene the headless path would have loaded synchronously.
func _booted() -> Boot:
	var boot := (load("res://src/shell/boot.tscn") as PackedScene).instantiate() as Boot
	add_child(boot)
	boot._next_variant = ""
	boot._finish_load(load(LevelRegistry.scene_of(Boot.DEFAULT_LEVEL)) as PackedScene)
	auto_free(boot)
	return boot


## Mirrors `Boot._start_challenge` (end any attempt, queue the def, load its arena) with the
## same direct `_finish_load` in place of the stuck-await threaded load.
func _run_challenge(boot: Boot, id: String) -> void:
	var def := ChallengeRegistry.def_of(id)
	boot._end_challenge()
	boot._pending_challenge = def
	boot._next_variant = def.variant
	boot._finish_load(load(LevelRegistry.scene_of(def.arena)) as PackedScene)


func after_test() -> void:
	get_tree().paused = false


## A home-level load spawns the picked body with the picked attachment, then forgets it.
func test_a_home_level_load_fits_the_picked_attachment() -> void:
	var boot := _booted()
	boot._next_variant = "semi"
	boot._next_attachment = TrailerCatalog.TRAILERS[1]
	boot._level.queue_free()
	boot._finish_load(load(LevelRegistry.scene_of("flatland")) as PackedScene)
	assert_str(GameState.current_variant).is_equal("semi")
	assert_str(String(boot._level.vehicle.current_attachment())).is_equal(TrailerCatalog.TRAILERS[1])
	assert_object(boot._next_attachment).is_null()


func _crates(level: Node) -> Array:
	return level.find_children("*", "CargoPayload", true, false)


## Flatland's three crates are there only while a drone is driven, and each drone spawn finds them
## back at their authored poses, one the drone left elsewhere in the level included.
func test_flatland_crates_come_with_the_drone() -> void:
	var boot := _booted()
	var level := boot._level
	assert_array(_crates(level)).is_empty()  # a car: no crates
	level.set_vehicle(VehicleCatalog.first_in_family("drone"))
	var crates := _crates(level)
	assert_int(crates.size()).is_equal(3)
	var home := (crates[0] as Node3D).global_position
	var moved := crates[0] as CargoPayload
	moved.get_parent().remove_child(moved)  # as a drop does: a child of the level, elsewhere
	level.add_child(moved)
	moved.global_position = home + Vector3(40, 0, 0)
	level.set_vehicle("sedan")
	assert_array(_crates(level)).is_empty()
	level.set_vehicle(VehicleCatalog.first_in_family("drone"))
	assert_int(_crates(level).size()).is_equal(3)
	assert_object(moved.get_parent()).is_same(level.get_node(^"Payloads"))
	assert_float(moved.global_position.distance_to(home)).is_less(1e-4)


func _action_event(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


## V / E reach the shell while a menu is open (boot is PROCESS_MODE_ALWAYS and the overlays do not
## eat letter keys): they must not swap the live body or cycle the trailer under the menu.
func test_boot_vehicle_and_attachment_keys_are_inert_behind_an_overlay() -> void:
	var boot := _booted()
	boot._level.set_vehicle("sedan")
	# Control: with no overlay, V swaps the body.
	var was := GameState.current_variant
	boot._unhandled_input(_action_event("next_vehicle"))
	assert_str(GameState.current_variant).is_not_equal(was)

	boot._on_menu_key()
	assert_int(boot._overlays.size()).is_equal(1)
	was = GameState.current_variant
	boot._unhandled_input(_action_event("next_vehicle"))
	assert_str(GameState.current_variant).is_equal(was)

	boot._on_menu_key()
	boot._level.set_vehicle("tractor-kenney")
	var implement: Variant = boot._level.vehicle.get("_implement_id")
	boot._on_menu_key()
	boot._unhandled_input(_action_event("next_attachment"))
	assert_that(boot._level.vehicle.get("_implement_id")).is_equal(implement)


## SPAWN POINT shows only with somewhere to choose, and its page hands the shell an index.
func test_pause_menu_spawn_page_needs_two_spawns_and_emits_the_index() -> void:
	var one := PauseMenu.State.new()
	one.spawns = PackedStringArray(["Spawn"])
	var lone: PauseMenu = auto_free(PauseMenu.new())
	lone.setup({}, one)
	add_child(lone)
	assert_array(_buttons(lone).map(func(b: Button) -> String: return b.text)) \
			.not_contains(["SPAWN POINT"])

	var three := PauseMenu.State.new()
	three.spawns = PackedStringArray(["Spawn", "Pad Wet", "Pad Snow"])
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({}, three)
	add_child(pause)
	var picked := []
	pause.spawn_picked.connect(func(i: int) -> void: picked.append(i))
	for b in _buttons(pause):
		if b.text == "SPAWN POINT":
			b.pressed.emit()
	assert_bool(pause.back()).is_true()  # it was a page of its own
	for b in _buttons(pause):
		if b.text == "PAD SNOW":
			b.pressed.emit()
	assert_array(picked).is_equal([2])


## The arena offers its pad's spawns; a pick moves the same body there and makes it the respawn
## point, and a challenge offers none (its course owns the spawn).
func test_boot_spawn_point_moves_the_body_and_respawn_returns_there() -> void:
	var boot := _booted()
	boot._next_variant = "sedan"
	boot._finish_load(load(LevelRegistry.scene_of("car_arena")) as PackedScene)
	var names := boot._spawn_points().map(func(n: VehicleSpawn) -> String: return String(n.name))
	assert_array(names).is_equal(["Spawn", "PadAsphalt", "PadWet", "PadSnow", "Skidpad"])
	var body: BaseVehicle = boot._level.vehicle
	var snow: VehicleSpawn = boot._spawn_points()[3]
	boot._on_spawn_picked(3)
	assert_object(boot._level.vehicle).is_same(body)
	var at := Vector2(body.global_position.x, body.global_position.z)
	var want := Vector2(snow.global_position.x, snow.global_position.z)
	assert_float(at.distance_to(want)).is_less(0.01)
	body.global_position += Vector3(30.0, 0.0, 0.0)
	boot._respawn()
	at = Vector2(body.global_position.x, body.global_position.z)
	assert_float(at.distance_to(want)).is_less(0.01)

	_run_challenge(boot, "car_box_stop")
	assert_array(boot._spawn_points()).is_empty()


## A sticky notice outlives the default dwell; a transient one shown over it hands back to it.
func test_boot_sticky_notice_outlasts_a_transient_one() -> void:
	var boot := _booted()
	GameState.notice.emit("STICKY", GameState.NOTICE_STICKY)
	GameState.notice.emit("BRIEF", 0.05)
	assert_str(boot._notice.text).is_equal("BRIEF")
	await get_tree().create_timer(0.15).timeout
	assert_bool(boot._notice.visible).is_true()
	assert_str(boot._notice.text).is_equal("STICKY")
	# No timer runs for it at all: the default dwell passes and it is still up.
	await get_tree().create_timer(NoticeLine.NOTICE_DWELL_S + 0.2).timeout
	assert_bool(boot._notice.visible).is_true()
	assert_str(boot._notice.text).is_equal("STICKY")


## Clearing takes down only the matching text: the next sticky one shows, a transient one stays.
func test_boot_clearing_a_notice_removes_only_its_own_text() -> void:
	var boot := _booted()
	GameState.notice.emit("FIRST", GameState.NOTICE_STICKY)
	GameState.notice.emit("SECOND", GameState.NOTICE_STICKY)
	GameState.notice_cleared.emit("FIRST")
	assert_str(boot._notice.text).is_equal("SECOND")
	GameState.notice.emit("BRIEF", 0.0)
	GameState.notice_cleared.emit("SECOND")
	assert_str(boot._notice.text).is_equal("BRIEF")
	assert_bool(boot._notice.visible).is_true()
	GameState.notice_cleared.emit("BRIEF")
	assert_bool(boot._notice.visible).is_false()


## The L1 hint in the running shell: up once the pad is the device in use on a body with an L1
## layer, not on one without (a car), never under a menu, and gone for good after L1's first press.
func test_boot_shows_the_l1_hint_while_the_pad_drives() -> void:
	var boot := _booted()
	boot._level.set_vehicle("tractor-kenney")
	boot._ui._set_device(UiScale.Device.KEYBOARD)
	assert_bool(boot._pad_legend.visible).is_false()
	boot._ui._set_device(UiScale.Device.PAD)
	assert_bool(boot._pad_legend.visible).is_true()
	assert_bool(boot._pad_legend._title.visible).is_false()
	boot._level.set_vehicle("sedan")
	assert_bool(boot._pad_legend.visible).is_false()
	boot._level.set_vehicle("tractor-kenney")
	assert_bool(boot._pad_legend.visible).is_true()
	boot._open_pause()
	assert_bool(boot._pad_legend.visible).is_false()
	boot._close_all_overlays()
	assert_bool(boot._pad_legend.visible).is_true()
	boot._pad._set_l1(0, true)
	boot._pad._set_l1(0, false)
	assert_bool(boot._pad_legend.visible).is_false()


## The overturned notice names the respawn control of the device in use, read from the registry;
## a sloppyCAN driver is sent to the pause menu; the pointer gets the RESPAWN button.
func test_the_overturned_notice_names_the_devices_respawn() -> void:
	var D := UiScale.Device
	var cases := [
		[D.KEYBOARD, false, false, "OVERTURNED - PRESS BACKSPACE TO RESPAWN", false],
		[D.PAD, false, false, "OVERTURNED - PRESS TRIANGLE TO RESPAWN", false],
		[D.POINTER, false, false, "OVERTURNED - PRESS BACKSPACE TO RESPAWN", true],
		[D.POINTER, false, true, "OVERTURNED", true],
		[D.PAD, true, false, "OVERTURNED - RESPAWN FROM THE PAUSE MENU", false],
	]
	for c: Array in cases:
		var shown := Boot.overturned_notice(c[0], c[1], c[2])
		assert_str(String(shown["text"])).is_equal(c[3])
		assert_bool(bool(shown["button"])).is_equal(c[4])


## The neutral notice names the device's shift-up control, read from the registry's `shift` row.
func test_the_neutral_notice_names_the_devices_shift_up() -> void:
	var D := UiScale.Device
	var cases := [
		[D.KEYBOARD, false, "NEUTRAL GEAR SELECTED - PRESS PERIOD TO SHIFT UP"],
		[D.PAD, false, "NEUTRAL GEAR SELECTED - PRESS D-PAD UP TO SHIFT UP"],
		[D.POINTER, false, "NEUTRAL GEAR SELECTED - PRESS PERIOD TO SHIFT UP"],
		[D.POINTER, true, "NEUTRAL GEAR SELECTED - PRESS GEAR + TO SHIFT UP"],
	]
	for c: Array in cases:
		var shown := Boot.neutral_notice(c[0], c[1])
		assert_str(String(shown["text"])).is_equal(c[2])
		assert_bool(bool(shown["button"])).is_false()


## Raised by the vehicle with its fixed text, shown with the shell's words and button, cleared by
## that same fixed text; the button respawns.
func test_boot_overturned_notice_shows_and_clears_with_its_button() -> void:
	var boot := _booted()
	boot._ui._set_device(UiScale.Device.PAD)
	GameState.notice.emit(BaseVehicle.OVERTURNED_NOTICE, GameState.NOTICE_STICKY)
	assert_str(boot._notice.text).contains("TRIANGLE")
	var button: Button = boot._notice._actions[BaseVehicle.OVERTURNED_NOTICE]["button"]
	assert_bool(button.visible).is_false()
	boot._ui._set_device(UiScale.Device.POINTER)
	boot._notice._process(0.0)
	assert_bool(button.visible).is_true()
	assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
	var body: BaseVehicle = boot._level.vehicle
	var spawn := body.spawn_transform.origin
	body.global_position += Vector3(30.0, 0.0, 0.0)
	button.pressed.emit()
	assert_float(body.global_position.distance_to(spawn)).is_less(0.01)
	GameState.notice_cleared.emit(BaseVehicle.OVERTURNED_NOTICE)
	assert_bool(boot._notice.visible).is_false()
	assert_bool(button.visible).is_false()


## LEVEL then CHALLENGES: Esc closes the top of the stack (CHALLENGES) only, and the world
## stays paused underneath since LEVEL is still open.
func test_boot_esc_closes_the_top_overlay_only() -> void:
	var boot := _booted()
	boot._show_level_select()
	boot._show_challenge_select()
	assert_int(boot._overlays.size()).is_equal(2)

	boot._on_menu_key()
	assert_int(boot._overlays.size()).is_equal(1)
	assert_bool(boot._overlays[0] is LevelSelect).is_true()
	assert_bool(get_tree().paused).is_true()

	boot._on_menu_key()
	assert_int(boot._overlays.size()).is_equal(0)
	assert_bool(get_tree().paused).is_false()


## INFO during an attempt, then LEVEL on top of it: two Esc presses walk back out in the order
## they were opened and land back in the running attempt, not free play.
func test_boot_briefing_then_level_esc_twice_returns_to_the_attempt() -> void:
	var boot := _booted()
	_run_challenge(boot, "car_blind_stadium")
	assert_object(boot._challenge).is_not_null()
	assert_object(boot._runner).is_not_null()

	boot._show_challenge_info()
	boot._show_level_select()
	assert_int(boot._overlays.size()).is_equal(2)

	boot._on_menu_key()
	assert_int(boot._overlays.size()).is_equal(1)
	assert_bool(boot._overlays[0] is ChallengeBriefing).is_true()
	assert_bool(get_tree().paused).is_true()

	boot._on_menu_key()
	assert_int(boot._overlays.size()).is_equal(0)
	assert_bool(get_tree().paused).is_false()
	# Still the same attempt: neither Esc undid it, unlike picking a level/vehicle/challenge would.
	assert_object(boot._challenge).is_not_null()
	assert_object(boot._runner).is_not_null()


## A menu key for an overlay already open elsewhere in the stack reveals it (closes whatever is
## stacked above) instead of stacking a duplicate instance.
func test_boot_menu_key_reveals_an_already_open_overlay() -> void:
	var boot := _booted()
	boot._show_level_select()
	var first: LevelSelect = boot._overlays[0]
	boot._open_vehicle_select()
	assert_int(boot._overlays.size()).is_equal(2)

	boot._show_level_select()
	assert_int(boot._overlays.size()).is_equal(1)
	assert_object(boot._overlays[0]).is_same(first)


## The stored tyre is on every free-play spawn of its variant and survives a respawn; an unknown
## id reads as the stock. A challenge runs the stock, and the stored class comes back with the lock.
func test_boot_fits_the_stored_tyre_and_a_challenge_runs_the_stock() -> void:
	var boot := _booted()
	boot._settings = UserSettings.new("")
	boot._settings.set_tyre("sedan", "winter")
	boot._level.set_vehicle("sedan")
	assert_str(boot._level.vehicle.drive.tyre.id).is_equal("winter")
	boot._level.vehicle.respawn()
	assert_str(boot._level.vehicle.drive.tyre.id).is_equal("winter")
	boot._settings.set_tyre("sedan", "no_such_class")
	boot._level.set_vehicle("sedan")
	assert_str(boot._level.vehicle.drive.tyre.id).is_equal("all_season")
	# A pick is stored under the variant it was made for, never the body still driven (the level
	# may refuse the new one).
	boot._on_tyre_picked("pickup", "mud")
	assert_str(boot._settings.tyre_of("pickup")).is_equal("mud")
	assert_str(boot._settings.tyre_of("sedan")).is_equal("no_such_class")

	boot._settings.set_tyre("sedan-sports", "summer")
	_run_challenge(boot, "car_blind_stadium")
	assert_str(GameState.current_variant).is_equal("sedan-sports")
	assert_str(boot._level.vehicle.drive.tyre.id).is_equal("all_season")
	boot._end_challenge()
	assert_str(boot._level.vehicle.drive.tyre.id).is_equal("summer")
