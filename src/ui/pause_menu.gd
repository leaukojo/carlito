class_name PauseMenu
extends Control
## The pause overlay — the one place everything is reachable from, now that the game boots
## straight into a level instead of asking you to pick one first.
##
## Esc used to tear the level down and drop you back at level select with no warning. It now
## opens this: RESUME / VEHICLE / LEVEL / CONTROLS / SETTINGS. VEHICLE and LEVEL are SIGNALS,
## not screens built here — the garage and level-select overlays are the shell's to create and
## free (standing rule 6), and this menu never learns what a level or a vehicle is. CONTROLS and
## SETTINGS are the exception: they are text and one toggle, they own nothing, so they live here
## as further pages of this same overlay. CONTROLS is GENERATED from ActionRegistry, which the
## touch overlay's buttons come from too, so the help and what is on screen cannot disagree.
##
## SETTINGS does not APPLY anything either — it emits the new value and the shell applies and
## persists it, the same way VEHICLE and LEVEL work.
##
## Built in code like every other shell screen, colour and type from the inherited theme.
## No emoji.

signal resume_requested
signal vehicle_requested
signal level_requested
## A new Dashboard.Density SETTING was picked. The shell owns applying it and writing it to
## user:// — this menu only knows it is an int with a name.
signal dashboard_density_changed(setting: int)

## Widest sensible button in logical px (scaled through UiTheme), matching the garage.
const BUTTON_W := 260.0

## The one thing the arrow-key and gamepad aliases are said in. Everything else on the sheet is
## read out of InputMap, but a row shows one key per action or "W / Up / S / Down" becomes the
## widest thing on the page for the least useful reason.
const DRIVE_FOOTNOTE := "Arrow keys and a gamepad also drive."

## One line under the density button saying what the modes are, because "COMPACT" alone does not
## tell you what you would lose.
const DENSITY_HELP := "AUTO uses the compact cluster on a small screen or while the bridge is live."

## How far Up/Down move the CONTROLS sheet, in logical px (scaled). About two rows.
const SHEET_STEP := 64.0

var _root: VBoxContainer
var _controls: VBoxContainer
var _settings: VBoxContainer
var _sheet: ScrollContainer  ## the CONTROLS sheet's scroll area, driven by Up/Down (see _unhandled_input)
var _resume_btn: Button
var _density_btn: Button
## The active vehicle's capabilities, from the shell (boot.gd _capabilities) — the same read the
## touch buttons gate on, so a control greyed here is a button that is not on screen.
var _caps := {}
## The dashboard density SETTING as the shell has it (Dashboard.Density, AUTO included).
var _density := Dashboard.Density.AUTO


## What the active vehicle can do (so the CONTROLS sheet greys what it does not have) and what the
## dashboard density is currently set to. Called by the shell BEFORE add_child (the VehicleSelect
## pattern) — the pages are built in _ready. Optional: with nothing handed over, capability-gated
## rows simply read as unavailable and the density reads AUTO.
func setup(caps: Dictionary, density_setting := Dashboard.Density.AUTO) -> void:
	_caps = caps
	_density = density_setting


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.SCRIM  # over a live (paused) scene, so a scrim rather than a backdrop
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow anything aimed at the world behind
	add_child(bg)

	_root = _page()
	_build_root()
	_controls = _page()
	_controls.visible = false
	_build_controls()
	_settings = _page()
	_settings.visible = false
	_build_settings()

	_resume_btn.grab_focus()  # keyboard/gamepad start point, like every other shell screen


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


## GENERATED FROM ActionRegistry — the whole point of the page. Every row, its grouping and its
## gating come from that one table, and every key string is read live out of InputMap, so a
## control cannot exist without appearing here and a rebinding cannot go stale. This replaces a
## hand-typed list that had drifted to ten missing actions.
##
## Three columns: what it does, the key, and — when the control does not apply to what you are
## driving right now — why not. Greying rather than hiding, because "the boat has no diff lock"
## teaches something and a missing row does not.
func _build_controls() -> void:
	_controls.add_child(_title("CONTROLS"))

	var ctx := ActionRegistry.context(GameState.current_vehicle, Bridge.is_active(), _caps)
	# Scrolls: the sheet is every bound action now, which does not fit a phone.
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

		# Centred as a block so the pairs line up instead of drifting apart on a wide window.
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


## One setting, one button, cycling AUTO / FULL / COMPACT / OFF. The value is not applied here —
## it is emitted, and the shell applies it to the dashboard and writes it to user://, so this
## screen still owns nothing (standing rule 6). The button relabels in place, and the cluster
## behind the scrim changes as you press it, which is the whole demonstration of what it does.
func _build_settings() -> void:
	_settings.add_child(_title("SETTINGS"))

	_density_btn = _menu_button("", _on_density_pressed)
	_relabel_density()
	_settings.add_child(_density_btn)

	var help := Label.new()
	help.text = DENSITY_HELP
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.theme_type_variation = &"Small"
	_settings.add_child(help)

	_settings.add_child(_menu_button("BACK", func() -> void: _show_page(_root)))


func _on_density_pressed() -> void:
	_density = Dashboard.next_setting(_density)
	_relabel_density()
	dashboard_density_changed.emit(_density)


func _relabel_density() -> void:
	_density_btn.text = "DASHBOARD: %s" % Dashboard.key_of(_density).to_upper()


## The CONTROLS sheet is taller than a phone and every row on it is a LABEL, so there is nothing
## inside it for the focus ring to walk down — without this a keyboard or gamepad player cannot
## scroll it at all (only a wheel or a finger could). BACK is the one focusable Control on that
## page and it has no focus neighbour, so Up/Down are never consumed by focus navigation and
## arrive here unhandled. Found in the Phase 7 navigation sweep.
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


## Step back one page; true if there was one to step back to. The shell calls this on Esc
## before it decides to resume, so Esc walks the overlay out the way it walked in.
func back() -> bool:
	if not _root.visible:
		_show_page(_root)
		return true
	return false


func _show_page(page: VBoxContainer) -> void:
	_root.visible = page == _root
	_controls.visible = page == _controls
	_settings.visible = page == _settings
	# Focus follows the page, or a keyboard player is left driving an invisible button.
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
	b.custom_minimum_size = Vector2(UiTheme.px(self, BUTTON_W), UiTheme.px(self, UiTheme.TOUCH_MIN))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b
