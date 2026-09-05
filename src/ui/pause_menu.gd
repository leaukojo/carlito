class_name PauseMenu
extends Control
## The pause overlay: RESUME / VEHICLE / LEVEL / CONTROLS / SETTINGS. Never tears the level
## down on its own. VEHICLE and LEVEL are signals — the garage and level-select overlays are
## the shell's to create/free (rule 6); this menu never learns what a level or vehicle is.
## CONTROLS and SETTINGS own nothing either: CONTROLS is generated from ActionRegistry (same
## source the touch overlay reads), SETTINGS emits new values for the shell to apply/persist.
## Built in code, colour/type from the inherited theme. No emoji.

signal resume_requested
signal vehicle_requested
signal level_requested
## New Dashboard.Density setting picked; the shell applies it and writes it to user://.
signal dashboard_density_changed(setting: int)
## New UI-size multiplier picked; the shell applies it to UiScale and writes it to user://.
signal ui_scale_changed(factor: float)

## Widest sensible button in logical px (scaled through UiTheme), matching the garage.
const BUTTON_W := 260.0

## Row shows one key per action, else "W / Up / S / Down" becomes the widest thing on the page.
const DRIVE_FOOTNOTE := "Arrow keys and a gamepad also drive."

## "COMPACT" alone doesn't say what you'd lose.
const DENSITY_HELP := "AUTO uses the compact cluster on a small screen or while the bridge is live."

## The automatic scale is the right default but still wrong for some screens/seating.
const UI_SCALE_HELP := "Scales all on-screen controls and text. 100% is the automatic size."

## How far Up/Down move the CONTROLS sheet, in logical px (scaled). About two rows.
const SHEET_STEP := 64.0

var _root: VBoxContainer
var _controls: VBoxContainer
var _settings: VBoxContainer
var _sheet: ScrollContainer  ## CONTROLS sheet's scroll area, driven by Up/Down (_unhandled_input)
var _resume_btn: Button
var _density_btn: Button
var _ui_scale_btn: Button
## Active vehicle's capabilities from the shell — same read the touch buttons gate on.
var _caps := {}
var _density: int = Dashboard.Density.AUTO
var _ui_scale := UiScale.USER_DEFAULT


## Called by the shell before add_child; pages build in _ready. Optional: with nothing handed
## over, capability-gated rows read unavailable and both settings read default.
func setup(caps: Dictionary, density_setting := Dashboard.Density.AUTO,
		ui_scale_factor := UiScale.USER_DEFAULT) -> void:
	_caps = caps
	_density = density_setting
	_ui_scale = ui_scale_factor


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.SCRIM  # over a live paused scene, so a scrim rather than a backdrop
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks aimed at the world behind
	add_child(bg)

	_root = _page()
	_build_root()
	_controls = _page()
	_controls.visible = false
	_build_controls()
	_settings = _page()
	_settings.visible = false
	_build_settings()

	_resume_btn.grab_focus()  # keyboard/gamepad start point


## A centred column filling the overlay. Both pages are one of these; only one is visible.
func _page() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	return col


func _build_root() -> void:
	_root.add_child(_title("PAUSED"))
	_resume_btn = _menu_button("RESUME", func() -> void: resume_requested.emit())
	_root.add_child(_resume_btn)
	_root.add_child(_menu_button("VEHICLE", func() -> void: vehicle_requested.emit()))
	_root.add_child(_menu_button("LEVEL", func() -> void: level_requested.emit()))
	_root.add_child(_menu_button("CONTROLS", func() -> void: _show_page(_controls)))
	_root.add_child(_menu_button("SETTINGS", func() -> void: _show_page(_settings)))


## Generated from ActionRegistry: every row, grouping and gate comes from that table, and key
## strings are read live from InputMap, so a control can't exist without appearing here and a
## rebinding can't go stale. Three columns: what it does, the key, and why not if it doesn't
## apply — greyed rather than hidden, since "the boat has no diff lock" teaches something.
func _build_controls() -> void:
	_controls.add_child(_title("CONTROLS"))

	var ctx := ActionRegistry.context(GameState.current_vehicle, Bridge.is_active(), _caps)
	# Scrolls: every bound action doesn't fit a phone.
	_sheet = ScrollContainer.new()
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet.add_child(body)
	_controls.add_child(_sheet)

	for group in ActionRegistry.Group.values():
		var rows := ActionRegistry.in_group(group)
		if rows.is_empty():
			continue
		var heading := Label.new()
		heading.text = ActionRegistry.GROUP_TITLES[group]
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.theme_type_variation = &"Title"
		body.add_child(heading)

		# Centred as a block so pairs line up instead of drifting apart on a wide window.
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for entry in rows:
			var applies := ActionRegistry.applies_entry(entry, ctx)
			var what := Label.new()
			what.text = String(entry["label"])
			what.theme_type_variation = &"Muted" if not applies else &""
			grid.add_child(what)
			var key := Label.new()
			key.text = ActionRegistry.keys_for(entry)
			key.theme_type_variation = &"MutedSmall" if not applies else &"Dim"
			grid.add_child(key)
			var note := Label.new()
			note.text = ActionRegistry.gate_note(entry, ctx)
			note.theme_type_variation = &"MutedSmall"
			grid.add_child(note)
		body.add_child(grid)

		if group == ActionRegistry.Group.DRIVE:
			var footnote := Label.new()
			footnote.text = DRIVE_FOOTNOTE
			footnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			footnote.theme_type_variation = &"Small"
			body.add_child(footnote)

	_controls.add_child(_menu_button("BACK", func() -> void: _show_page(_root)))


## Two settings, one button each, cycling their steps. Neither value is applied here — both
## are emitted and the shell applies/persists them (rule 6). Each button relabels in place.
func _build_settings() -> void:
	_settings.add_child(_title("SETTINGS"))

	_density_btn = _menu_button("", _on_density_pressed)
	_relabel_density()
	_settings.add_child(_density_btn)
	_settings.add_child(_help(DENSITY_HELP))

	_ui_scale_btn = _menu_button("", _on_ui_scale_pressed)
	_relabel_ui_scale()
	_settings.add_child(_ui_scale_btn)
	_settings.add_child(_help(UI_SCALE_HELP))

	_settings.add_child(_menu_button("BACK", func() -> void: _show_page(_root)))


func _help(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"Small"
	return label


func _on_density_pressed() -> void:
	_density = Dashboard.next_setting(_density)
	_relabel_density()
	dashboard_density_changed.emit(_density)


func _relabel_density() -> void:
	_density_btn.text = "DASHBOARD: %s" % Dashboard.key_of(_density).to_upper()


## The press rebuilds the theme, relayouting this menu under the finger that pressed it, so
## the button is relabelled before the signal goes out and focus is restored after.
func _on_ui_scale_pressed() -> void:
	_ui_scale = UiScale.next_user_scale(_ui_scale)
	_relabel_ui_scale()
	ui_scale_changed.emit(_ui_scale)
	_ui_scale_btn.grab_focus()


func _relabel_ui_scale() -> void:
	_ui_scale_btn.text = "UI SIZE: %d%%" % int(roundf(_ui_scale * 100.0))


## Every row on the CONTROLS sheet is a Label, so there's nothing for the focus ring to walk —
## without this a keyboard/gamepad player couldn't scroll it. BACK has no focus neighbour, so
## Up/Down are never consumed by focus navigation and arrive here.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet == null or _controls == null or not _controls.visible:
		return
	var step := int(UiTheme.px(self, SHEET_STEP))
	if event.is_action_pressed("ui_down", true):
		_sheet.scroll_vertical += step
	elif event.is_action_pressed("ui_up", true):
		_sheet.scroll_vertical -= step
	else:
		return
	get_viewport().set_input_as_handled()


## Pixel-laid-out parts (button min sizes, page margins) are computed once in _build_* and
## must be re-applied when UI SIZE changes the scale from inside this menu, else the open
## menu keeps stale sizes. Theme-driven parts relayout on their own.
func _notification(what: int) -> void:
	if what != NOTIFICATION_THEME_CHANGED or _root == null:
		return
	var margin := int(UiTheme.px(self, UiTheme.MARGIN))
	for page: VBoxContainer in [_root, _controls, _settings]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,
				Control.PRESET_MODE_MINSIZE, margin)
		for child in page.get_children():
			if child is Button:
				_size_button(child as Button)


## Step back one page; true if there was one. Called on Esc before deciding to resume, so
## Esc walks the overlay out the way it walked in.
func back() -> bool:
	if not _root.visible:
		_show_page(_root)
		return true
	return false


func _show_page(page: VBoxContainer) -> void:
	_root.visible = page == _root
	_controls.visible = page == _controls
	_settings.visible = page == _settings
	# Focus follows the page, else a keyboard player is left driving an invisible button.
	for child in page.get_children():
		if child is Button:
			(child as Button).grab_focus()
			break


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"Display"
	return label


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_size_button(b)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


func _size_button(b: Button) -> void:
	b.custom_minimum_size = Vector2(UiTheme.px(self, BUTTON_W), UiTheme.px(self, UiTheme.TOUCH_MIN))
