extends GdUnitTestSuite
## Shell menu overlays: level-select reads the registry, the vehicle selector reads the catalog
## against the level's allow-list, and both emit their pick. Pure Control scenes, so they build
## and fire headless without a 3D level.
##
## The selector's PREVIEW is not exercised here: it instantiates a real vehicle body into a
## SubViewport, which needs a renderer the CI runner does not have. What is pinned here is the
## part that decides — the roster, the refusals, and what reaches the shell.

func _buttons(node: Node) -> Array:
	var out := []
	for b in node.find_children("*", "Button", true, false):
		out.append(b)
	return out


## The level cards, told apart from the screen's own BACK button by the thing that makes them
## cards: a card IS the screenshot, so its name rides a child Label and its `text` is empty.
func _cards(sel: LevelSelect) -> Array:
	var out := []
	for b in _buttons(sel):
		if (b as Button).text.is_empty():
			out.append(b)
	return out


## The registry entries level-select is expected to show: shipped content only. `dev: true`
## entries are test assets — the bake/check tools still walk the full list, so CI covers them.
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


## It is a pause-menu section now, not the front door, so leaving it without picking has to
## be possible — the shell wires BACK (and Esc) to this.
func test_level_select_back_emits_closed() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var closed := [false]
	sel.closed.connect(func() -> void: closed[0] = true)
	for b in _buttons(sel):
		if b.text == "BACK":
			b.pressed.emit()
	assert_bool(closed[0]).is_true()


func test_level_select_hides_dev_fixtures() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var tooltips := []
	for b in _buttons(sel):
		tooltips.append(b.tooltip_text)
	for entry in LevelRegistry.LEVELS:
		if bool(entry.get("dev", false)):
			assert_array(tooltips).not_contains([String(entry.get("desc", ""))])


func test_level_select_cards_carry_the_registry_description() -> void:
	var sel: LevelSelect = auto_free(LevelSelect.new())
	add_child(sel)
	var cards := _cards(sel)
	var shipped := _shipped()
	for i in shipped.size():
		var entry: Dictionary = shipped[i]
		# Cards are pictures: the name rides a Label on the card, the description is the
		# tooltip (and the line under the grid, fed by the same string).
		assert_str(String(entry.get("desc", ""))).is_not_empty()
		assert_str(cards[i].tooltip_text).is_equal(String(entry["desc"]))
		var texts := []
		for l in (cards[i] as Button).find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		assert_array(texts).contains([String(entry["name"])])


## What a level costs to load, on the card you decide from. Measured off the .baked.scn, so a
## level with no bake (the garage is indoor) must show nothing rather than "0.0 MB".
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


## The baked island levels are the ones with a weight to report, and it has to read as a size
## rather than a byte count — the number exists to answer "how long am I about to wait".
func test_weight_text_reads_as_megabytes() -> void:
	assert_str(LevelRegistry.weight_text(LevelRegistry.scene_of("level_2"))).ends_with(" MB")
	assert_int(LevelRegistry.weight_bytes(LevelRegistry.scene_of("level_2"))).is_greater(0)
	# No bake, nothing to measure, nothing said.
	assert_str(LevelRegistry.weight_text(LevelRegistry.scene_of("garage"))).is_empty()
	assert_str(LevelRegistry.weight_text("res://nope/nope.tscn")).is_empty()


## A selector built on a level that allows one family. EVERY family is still listed — the ones this
## level refuses are browsable and carry the reason (see the class comment on VehicleSelect) — and
## picking emits the VARIANT, not the family the old garage menu emitted.
func _selector(allowed: PackedStringArray, variant: String,
		rail := false, attachment := "") -> VehicleSelect:
	var sel: VehicleSelect = auto_free(VehicleSelect.new())
	sel.setup(allowed, "Test Level", rail, variant, attachment)
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


## Cards carry their name on a child Label and leave `text` empty (the level-select convention),
## so this tells a picture card from the family column and the footer buttons.
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
	# The whole catalog, not just what this level spawns. The caption carries the selector's own
	# "(beta)" marker, so it is built the same way the screen builds it rather than re-typed here.
	for variant: String in VehicleCatalog.VARIANTS:
		var fam: String = VehicleCatalog.family_of(variant)
		var caption := fam.to_upper() + (" (beta)" if VehicleSelect.BETA_FAMILIES.has(fam) else "")
		assert_array(labels).contains([caption])
	assert_array(labels).contains(["DRIVE", "BACK"])

	# The car family's variants are on screen as cards, and DRIVE emits the selected VARIANT —
	# the old garage emitted a family and threw the body choice away.
	assert_array(_card_names(sel)).contains(["TAXI", "POLICE"])
	var picked := [""]
	sel.vehicle_chosen.connect(func(v: String) -> void: picked[0] = v)
	_press(sel, "DRIVE")
	assert_str(picked[0]).is_equal("sedan-sports")


## Nothing is hidden: a family this level will not spawn opens, previews, and says why — and only
## DRIVE is refused. Both refusals are derived (the allow-list, and the runtime rail answer).
func test_vehicle_select_shows_a_refused_family_with_its_reason() -> void:
	var sel := _selector(PackedStringArray(["car", "train"]), "sedan-sports")
	_press(sel, "TRUCK")  # not in the allow-list at all
	var refused := [""]
	sel.vehicle_chosen.connect(func(v: String) -> void: refused[0] = v)
	_press(sel, "DRIVE")
	assert_str(refused[0]).is_empty()  # the button is disabled, so pressing it does nothing

	# Allowed by the level, refused at runtime: a rail family with no closed loop to run on.
	_press(sel, "TRAIN (beta)")
	var texts := []
	for l in sel.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var said_why := false
	for t: String in texts:
		if t.contains("NO CLOSED RAIL LOOP HERE"):
			said_why = true
	assert_bool(said_why).is_true()


## The second row is the PREVIEWED machine's own answer (duck-typed attachment_ids), so it appears
## for a semi and not for a garbage truck — without this screen learning what a trailer is.
func test_vehicle_select_offers_the_attachment_row_only_where_the_machine_tows() -> void:
	var towing := _selector(PackedStringArray(["truck"]), "semi")
	var names := _card_names(towing)
	assert_array(names).contains(["TIPPER", "TANKER", "NONE"])  # NONE is bobtail, a real entry

	var solo := _selector(PackedStringArray(["truck"]), "garbage-truck")
	assert_array(_card_names(solo)).not_contains(["TIPPER"])


## DRIVE hands the attachment over as a second signal right behind the body, so the shell can
## apply both — and so "no attachment" needs no sentinel (DETACHED and BOBTAIL are both "").
func test_vehicle_select_emits_the_attachment_behind_the_body() -> void:
	var sel := _selector(PackedStringArray(["truck"]), "semi", false, TrailerCatalog.TRAILERS[1])
	var order := []
	sel.vehicle_chosen.connect(func(v: String) -> void: order.append(v))
	sel.attachment_chosen.connect(func(id: String) -> void: order.append(id))
	_press(sel, "DRIVE")
	assert_array(order).is_equal(["semi", TrailerCatalog.TRAILERS[1]])


## The pause overlay is the one place everything is reachable from, so the entries have to be
## there and each has to reach the shell.
func test_pause_menu_offers_the_shell_sections() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	add_child(pause)
	var labels := []
	for b in _buttons(pause):
		labels.append(b.text)
	assert_array(labels).contains(["RESUME", "VEHICLE", "LEVEL", "CONTROLS", "SETTINGS"])

	var fired := []
	pause.resume_requested.connect(func() -> void: fired.append("RESUME"))
	pause.vehicle_requested.connect(func() -> void: fired.append("VEHICLE"))
	pause.level_requested.connect(func() -> void: fired.append("LEVEL"))
	for b in _buttons(pause):
		if b.text in ["RESUME", "VEHICLE", "LEVEL"]:
			b.pressed.emit()
	assert_array(fired).contains(["RESUME", "VEHICLE", "LEVEL"])


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
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({"tows": true, "pto": true, "lift": true})
	add_child(pause)
	var texts := []
	for label in pause.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var entry := ActionRegistry.find(&"pantograph")
	assert_array(texts).contains([String(entry["label"]), ActionRegistry.keys_for(entry)])
	# Every section heading is there, so no group of controls can go missing wholesale.
	assert_array(texts).contains(ActionRegistry.GROUP_TITLES)


## SETTINGS is a page of this overlay like CONTROLS, and its one button CYCLES: it relabels
## itself and emits the new value, which the shell applies and persists. The menu applies
## nothing itself (standing rule 6), so what is asserted is what reaches the shell.
func test_pause_menu_settings_cycles_the_dashboard_density() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	pause.setup({}, Dashboard.Density.AUTO)
	add_child(pause)
	_press(pause, "SETTINGS")

	var picked := []
	pause.dashboard_density_changed.connect(func(s: int) -> void: picked.append(s))
	var expected := Dashboard.next_setting(Dashboard.Density.AUTO)
	_press(pause, "DASHBOARD: AUTO")
	assert_array(picked).is_equal([expected])
	# The button says what it now is, so a second press cycles on from there rather than repeating.
	assert_array(_labels(pause)).contains(["DASHBOARD: %s" % Dashboard.key_of(expected).to_upper()])

	# Esc walks back out of this page the same way it does out of CONTROLS.
	assert_bool(pause.back()).is_true()
	assert_bool(pause.back()).is_false()


func test_vehicle_select_back_emits_closed() -> void:
	var sel := _selector(PackedStringArray(["car"]), "sedan-sports")
	var closed := [false]
	sel.closed.connect(func() -> void: closed[0] = true)
	_press(sel, "BACK")
	assert_bool(closed[0]).is_true()
