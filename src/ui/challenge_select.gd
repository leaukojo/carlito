class_name ChallengeSelect
extends Control
## The CHALLENGES screen: cards grouped by family (ChallengeRegistry), each showing its done
## state and best time (ChallengeProgress). Picking a card opens a briefing page (goal +
## constraints, a HINT button) with START; START emits `challenge_chosen`. The shell can open the
## screen straight on one challenge's briefing (the result panel's NEXT). A RESET PROGRESS
## button, behind a confirmation page, clears the store. Three pages, one visible at a time,
## the same page-swap idiom PauseMenu uses. Built in code, a transient overlay the shell frees
## on pick or BACK. No emoji.

signal challenge_chosen(id: String)
signal closed  ## BACK / Esc from the grid page

const CardGrid := preload("res://src/ui/card_grid.gd")

const CARD_W := 280.0
const CARD_ASPECT := 0.594  ## matches LevelSelect: the arena screenshot's shape
const STRIP_H := 34.0
const BORDER_W := 3.0
const MAX_COLUMNS := 4

var _progress: ChallengeProgress
var _open_id := ""  ## a challenge whose briefing the screen opens on; "" = the grid

var _grid_page: VBoxContainer
var _briefing_page: VBoxContainer
var _confirm_page: VBoxContainer
var _family_grids: Array[GridContainer] = []
var _hint_label: Label
var _confirm_no_btn: Button


## Called by the shell before add_child.
func setup(progress: ChallengeProgress, open_id := "") -> void:
	_progress = progress
	_open_id = open_id


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_grid_page = _page()
	_build_grid_page()
	_briefing_page = _page()
	_briefing_page.visible = false
	_confirm_page = _page()
	_confirm_page.visible = false
	_build_confirm_page()
	var open := ChallengeRegistry.def_of(_open_id)  # null for "": no def has an empty id
	if open != null:
		_show_briefing(open)


## A centred column filling the overlay, matching PauseMenu's page-swap idiom.
func _page() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	return col


func _build_grid_page() -> void:
	for c in _grid_page.get_children():
		c.free()

	var title := Label.new()
	title.text = "CARLITO 2  -  CHALLENGES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	_grid_page.add_child(title)

	var families := ChallengeRegistry.families()
	if families.is_empty():
		var empty := Label.new()
		empty.text = "No challenges yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.theme_type_variation = &"Dim"
		_grid_page.add_child(empty)
	else:
		_family_grids.clear()
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		_grid_page.add_child(scroll)

		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)

		var first: Button = null
		for family in families:
			var heading := Label.new()
			heading.text = family.to_upper()
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			heading.theme_type_variation = &"Title"
			body.add_child(heading)

			var grid := GridContainer.new()
			grid.columns = 1
			grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			for d in ChallengeRegistry.in_family(family):
				var card := _make_card(d)
				grid.add_child(card)
				if first == null:
					first = card
			body.add_child(grid)
			_family_grids.append(grid)

		scroll.resized.connect(_reflow_all)
		_reflow_all()
		if first != null:
			first.grab_focus()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_grid_page.add_child(row)
	row.add_child(_btn("RESET PROGRESS", _show_confirm, UiTheme.DANGER))
	row.add_child(_btn("BACK", func() -> void: closed.emit()))


## Fit as many cards across as the window allows, same rule as LevelSelect.
func _reflow_all() -> void:
	for grid in _family_grids:
		if grid.get_child_count() == 0:
			continue
		var card_w := UiTheme.px(self, CARD_W)
		var gap := float(grid.get_theme_constant("h_separation", "GridContainer"))
		var avail := size.x - UiTheme.px(self, UiTheme.MARGIN) * 2.0
		var fits := int(floorf((avail + gap) / (card_w + gap)))
		grid.columns = clampi(fits, 1, mini(MAX_COLUMNS, grid.get_child_count()))


## One challenge card: the arena's screenshot behind, title on a bottom strip, done/best in the
## corner. The whole card is the Button; pressing it opens the briefing.
func _make_card(d: ChallengeDef) -> Button:
	var card_w := UiTheme.px(self, CARD_W)
	var done := _progress.is_done(d.id)

	var card := Button.new()
	card.custom_minimum_size = Vector2(card_w, roundf(card_w * CARD_ASPECT))
	card.clip_contents = true
	card.tooltip_text = d.briefing
	card.add_theme_stylebox_override("normal", CardGrid.card_box(self, BORDER_W, done))
	card.add_theme_stylebox_override("hover", CardGrid.card_box(self, BORDER_W, true))
	card.add_theme_stylebox_override("pressed", CardGrid.card_box(self, BORDER_W, true))
	card.add_theme_stylebox_override("focus", CardGrid.card_box(self, BORDER_W, true))
	card.pressed.connect(_show_briefing.bind(d))

	var inset := UiTheme.px(self, BORDER_W)
	var thumb_path := LevelShot.thumb_path(d.arena)
	if ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = load(thumb_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = inset
		thumb.offset_top = inset
		thumb.offset_right = -inset
		thumb.offset_bottom = -inset
		card.add_child(thumb)
	else:
		var missing := Label.new()
		missing.text = "no screenshot"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		missing.theme_type_variation = &"Dim"
		missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(missing)

	var strip := ColorRect.new()
	strip.color = UiTheme.SCRIM
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = inset
	strip.offset_right = -inset
	strip.offset_top = -UiTheme.px(self, STRIP_H)
	strip.offset_bottom = -inset
	card.add_child(strip)

	var label := Label.new()
	label.text = d.title
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"Title"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = UiTheme.px(self, 10.0)
	strip.add_child(label)

	var status := Label.new()
	status.text = "BEST %s S" % String.num(_progress.best_time(d.id), 1) if done else "NOT DONE"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.theme_type_variation = &"Dim"
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.offset_right = -UiTheme.px(self, 10.0)
	strip.add_child(status)

	return card


func _show_briefing(d: ChallengeDef) -> void:
	for c in _briefing_page.get_children():
		c.free()

	var title := Label.new()
	title.text = d.title.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	_briefing_page.add_child(title)

	var status := Label.new()
	status.text = "BEST: %s S" % String.num(_progress.best_time(d.id), 1) \
			if _progress.is_done(d.id) else "NOT DONE YET"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.theme_type_variation = &"Dim"
	_briefing_page.add_child(status)

	var briefing := Label.new()
	briefing.text = d.briefing
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing.custom_minimum_size.x = UiTheme.px(self, 480.0)
	_briefing_page.add_child(briefing)

	if d.par_s > 0.0:
		var par := Label.new()
		par.text = "PAR: %s S" % String.num(d.par_s, 1)
		par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		par.theme_type_variation = &"Small"
		_briefing_page.add_child(par)

	_hint_label = Label.new()
	_hint_label.text = d.hint
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size.x = UiTheme.px(self, 480.0)
	_hint_label.theme_type_variation = &"Dim"
	_hint_label.visible = false
	_briefing_page.add_child(_hint_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_briefing_page.add_child(row)
	row.add_child(_btn("HINT", func() -> void: _hint_label.visible = not _hint_label.visible))
	var start := Button.new()
	start.text = "START"
	start.theme_type_variation = &"Primary"
	start.custom_minimum_size = Vector2(UiTheme.px(self, 200.0), UiTheme.px(self, UiTheme.TOUCH_MIN))
	start.pressed.connect(func() -> void: challenge_chosen.emit(d.id))
	row.add_child(start)
	row.add_child(_btn("BACK", func() -> void: _show_page(_grid_page)))

	_show_page(_briefing_page)
	start.grab_focus()


func _build_confirm_page() -> void:
	var title := Label.new()
	title.text = "RESET ALL CHALLENGE PROGRESS?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Title"
	_confirm_page.add_child(title)

	var warn := Label.new()
	warn.text = "Every best time is forgotten. This cannot be undone."
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.theme_type_variation = &"Dim"
	_confirm_page.add_child(warn)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_page.add_child(row)
	row.add_child(_btn("YES, RESET", _on_reset_confirmed, UiTheme.DANGER))
	_confirm_no_btn = _btn("NO", func() -> void: _show_page(_grid_page))
	row.add_child(_confirm_no_btn)


func _show_confirm() -> void:
	_show_page(_confirm_page)
	# NO, not YES: a keyboard/gamepad player landing here on a stray press must not be one more
	# press away from wiping every best time.
	if _confirm_no_btn != null:
		_confirm_no_btn.grab_focus()


func _on_reset_confirmed() -> void:
	_progress.reset()
	_build_grid_page()
	_show_page(_grid_page)


## Focuses the first Button under `page` — a card or BACK is never a direct child (both sit
## inside a scroll/row), so this has to walk, not just check `get_children()`.
func _show_page(page: VBoxContainer) -> void:
	_grid_page.visible = page == _grid_page
	_briefing_page.visible = page == _briefing_page
	_confirm_page.visible = page == _confirm_page
	var buttons := page.find_children("*", "Button", true, false)
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus()


func _btn(text: String, on_press: Callable, rim := UiTheme.RIM) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UiTheme.px(self, 200.0), UiTheme.px(self, UiTheme.TOUCH_MIN))
	if rim != UiTheme.RIM:
		b.add_theme_stylebox_override("normal", UiTheme.keycap(UiTheme.SURFACE, rim, UiTheme.scale_of(self)))
		b.add_theme_stylebox_override("hover", UiTheme.keycap(UiTheme.SURFACE_HI, rim, UiTheme.scale_of(self)))
	b.pressed.connect(on_press)
	return b
