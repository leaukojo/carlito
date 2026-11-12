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
const STATUS_W := 120.0  ## top-left DONE badge width, over the screenshot
const BORDER_W := 3.0
const MAX_COLUMNS := 4

var _progress: ChallengeProgress
var _open_id := ""  ## a challenge whose briefing the screen opens on; "" = the grid

var _briefing_def: ChallengeDef  ## the briefing page's challenge, to lay it out again on a resize
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
	title.text = "CHALLENGES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	_grid_page.add_child(title)

	var intro := Label.new()
	intro.text = "Small challenges to prove your mastery of the CAN bus. Solve with your own scripts."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size.x = UiTheme.px(self, 480.0)
	intro.theme_type_variation = &"LeadDim"
	_grid_page.add_child(intro)

	var intro_full := Label.new()
	intro_full.text = ("Connect an external CAN adapter to RAMN, or use sloppyCAN's scripting " +
			"feature (top-right button).\n\nHints:\n" +
			"- Load a vehicle on a regular level, and find out which signals you need to override.\n" +
			"- You may need to disable RAMN's own communications for those signals first " +
			"(in the simulator, they'll go off automatically).\n\n" +
			"Some of them can be solved by driving manually - but the game is to solve them using only the CAN bus.")
	intro_full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_full.custom_minimum_size.x = UiTheme.px(self, 480.0)
	intro_full.theme_type_variation = &"LeadDim"
	intro_full.visible = false
	_grid_page.add_child(intro_full)

	# Not a lambda over `intro_btn`: a lambda captures a local by value, so it would see null here.
	var intro_btn := UiTheme.button(self, "MORE INFO", Callable())
	intro_btn.pressed.connect(func() -> void:
		intro_full.visible = not intro_full.visible
		intro_btn.text = "LESS INFO" if intro_full.visible else "MORE INFO")
	_grid_page.add_child(intro_btn)

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
			heading.theme_type_variation = &"Heading"
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
	row.add_child(UiTheme.button(self, "RESET PROGRESS", _show_confirm, UiTheme.DANGER))
	row.add_child(UiTheme.button(self, "BACK", func() -> void: closed.emit()))


## Fit as many cards across as the window allows, same rule as LevelSelect.
func _reflow_all() -> void:
	for grid in _family_grids:
		if grid.get_child_count() == 0:
			continue
		var gap := float(grid.get_theme_constant("h_separation", "GridContainer"))
		grid.columns = CardGrid.columns_for(self, CARD_W, gap, MAX_COLUMNS, grid.get_child_count())


## One challenge card: the arena's screenshot with the title under it, DONE/best time
## top-left over the screenshot (nothing shown until done). The whole card is the Button;
## pressing it opens the briefing.
func _make_card(d: ChallengeDef) -> Button:
	var done := _progress.is_done(d.id)
	# The challenge's own spawn shot (gen_challenge_thumbs.gd) if generated, else the arena's
	# shared landscape shot — never neither, so an ungenerated challenge still shows something.
	var thumb_path := CardImport.challenge_thumb_path(d.id)
	if not ResourceLoader.exists(thumb_path):
		thumb_path = LevelShot.thumb_path(d.arena)
	var card := CardGrid.picture_card(self, CARD_W, CARD_ASPECT, BORDER_W, done, thumb_path, d.title)
	card.tooltip_text = d.briefing
	card.pressed.connect(_show_briefing.bind(d))

	var inset := UiTheme.px(self, BORDER_W)
	if done:
		# Top-left, over the screenshot: the caption row is title-only, and a long title
		# would otherwise run under a status label sharing it.
		var status_scrim := ColorRect.new()
		status_scrim.color = UiTheme.SCRIM
		status_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_scrim.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		status_scrim.offset_left = inset
		status_scrim.offset_top = inset
		status_scrim.offset_right = inset + UiTheme.px(self, STATUS_W)
		status_scrim.offset_bottom = inset + UiTheme.px(self, CardGrid.CAPTION_H)
		card.add_child(status_scrim)

		var status := Label.new()
		status.text = "DONE: %s S" % String.num(_progress.best_time(d.id), 1)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.theme_type_variation = &"Dim"
		status.add_theme_color_override("font_color", UiTheme.OK)
		status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		status_scrim.add_child(status)

	return card


## Card, margin and text-width pixel sizes are fixed when built; a theme rebuild (a window resize,
## UI SIZE) leaves them stale, so the open pages are laid out again. Deferred: this fires while
## the theme is still propagating through the children it would free.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _confirm_page != null:
		_relayout.call_deferred()


func _relayout() -> void:
	var margin := int(UiTheme.px(self, UiTheme.MARGIN))
	for page: VBoxContainer in [_grid_page, _briefing_page, _confirm_page]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
				margin)
	var up := _confirm_page if _confirm_page.visible \
			else (_briefing_page if _briefing_page.visible else _grid_page)
	_build_grid_page()
	for c in _confirm_page.get_children():
		c.free()
	_build_confirm_page()
	if _briefing_def != null:
		_show_briefing(_briefing_def)  # rebuilt, and focused on START when it is the page up
	# Each rebuild grabbed focus on its own page: put back the page that was up, and its focus.
	_grid_page.visible = up == _grid_page
	_briefing_page.visible = up == _briefing_page
	_confirm_page.visible = up == _confirm_page
	if up == _confirm_page:
		_confirm_no_btn.grab_focus()
	elif up == _grid_page and not _family_grids.is_empty():
		_family_grids[0].get_child(0).grab_focus()


func _show_briefing(d: ChallengeDef) -> void:
	_briefing_def = d
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
	status.theme_type_variation = &"LeadDim"
	_briefing_page.add_child(status)

	var briefing := Label.new()
	briefing.text = d.briefing
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing.theme_type_variation = &"Lead"
	briefing.custom_minimum_size.x = UiTheme.px(self, 480.0)
	_briefing_page.add_child(briefing)

	if d.par_s > 0.0:
		var par := Label.new()
		par.text = "TIME LIMIT: %s S" % String.num(d.par_s, 1)
		par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		par.theme_type_variation = &"Dim"
		_briefing_page.add_child(par)

	if not d.gearbox_text().is_empty():
		var gearbox := Label.new()
		gearbox.text = d.gearbox_text()
		gearbox.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gearbox.theme_type_variation = &"Lead"
		_briefing_page.add_child(gearbox)

	_hint_label = Label.new()
	_hint_label.text = d.hint
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size.x = UiTheme.px(self, 480.0)
	_hint_label.theme_type_variation = &"LeadDim"
	_hint_label.visible = false
	_briefing_page.add_child(_hint_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_briefing_page.add_child(row)
	row.add_child(UiTheme.button(self, "HINT",
			func() -> void: _hint_label.visible = not _hint_label.visible))
	var start := UiTheme.button(self, "START", func() -> void: challenge_chosen.emit(d.id))
	start.theme_type_variation = &"Primary"
	row.add_child(start)
	row.add_child(UiTheme.button(self, "BACK", func() -> void: _show_page(_grid_page)))

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
	row.add_child(UiTheme.button(self, "YES, RESET", _on_reset_confirmed, UiTheme.DANGER))
	_confirm_no_btn = UiTheme.button(self, "NO", func() -> void: _show_page(_grid_page))
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
