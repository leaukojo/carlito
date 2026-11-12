class_name PauseMenu
extends Control
## The pause overlay: RESUME / RESPAWN / SPAWN POINT / LEVEL / SANDBOX / CONTROLS / SETTINGS.
## LEVEL is built only while a gamepad is the device in use (`State.level_row`): touch has it on the
## important buttons and the keyboard on 4. CHALLENGES is not here (touch and 5 reach it; the pad
## does not, by choice), nor GARAGE (Create, G and touch). Never tears the level down on its own.
## RESPAWN, SPAWN POINT and LEVEL are signals — respawning is the shell's to do (rule 6), SPAWN
## POINT lists names and hands back an index; this menu never learns what a level or vehicle is.
## CONTROLS, SETTINGS and SANDBOX own nothing either: CONTROLS is generated from ActionRegistry
## (same source the touch overlay reads), SETTINGS and SANDBOX emit new values for the shell to
## apply/persist (`docs/systems.md`, Pause overlay). Built in code, themed. No emoji.

const WorldConditions := preload("res://src/levels/base/world_conditions.gd")
const KeyShaper := preload("res://src/input/key_shaper.gd")

signal resume_requested
signal respawn_requested
## LEVEL picked: the shell opens that screen over this menu.
signal level_requested
## A SPAWN POINT page pick: the index into `State.spawns`. Moving there is the shell's to do.
signal spawn_picked(index: int)
## New Dashboard.Density setting picked; the shell applies it and writes it to user://.
signal dashboard_density_changed(setting: int)
## New UI-size multiplier picked; the shell applies it to UiScale and writes it to user://.
signal ui_scale_changed(factor: float)
## New KEY RESPONSE step picked (KeyShaper softening, 0..1); the shell hands it to InputRouter and
## writes it to user://.
signal key_softening_changed(amount: float)
## TRACTION CONTROL flipped (true = off); the shell hands it to InputRouter and writes it to user://.
signal tcs_off_changed(off: bool)
## STABILITY CONTROL flipped (true = off); the shell hands it to InputRouter and writes it to user://.
signal esc_off_changed(off: bool)
## AUTO HOLD flipped; the shell hands it to InputRouter and writes it to user://.
signal auto_hold_changed(on: bool)
## ANTI-LOCK BRAKES flipped (true = off); the shell hands it to InputRouter for the session.
signal abs_off_changed(off: bool)
## DIFFERENTIALS cycled; the shell hands it to InputRouter for the session.
signal axle_diff_changed(mode: VehicleInput.AxleDiff)
## STEERING flipped (true = PARALLEL); the shell hands it to InputRouter for the session.
signal parallel_steer_changed(on: bool)
## New wind/current preset or shared compass direction picked; the shell applies it to the
## current level and keeps it for the session.
signal conditions_changed(wind_preset: int, current_preset: int, from_deg: float)
## Day/night picked directly (as opposed to the N key, which flips it). Named apart from
## GameState.night_changed, which is the level's own broadcast of the result.
signal night_toggled(on: bool)

## A CONTROLS sheet column after the row's name: the key, the gamepad button, the on-screen
## button. In sheet order.
enum Column { KEY, PAD, TOUCH }

## What the shell hands over for the pages to open on: the SETTINGS and SANDBOX values as applied.
## Named fields, so a call site cannot transpose them.
class State extends RefCounted:
	## A gamepad is the device in use as the menu opens: the root carries LEVEL.
	var level_row := false
	## The CONTROLS sheet's columns (`sheet_columns`); every one when nothing is known.
	var columns: Array[Column] = [Column.KEY, Column.PAD, Column.TOUCH]
	var density: int = Dashboard.Density.COMPACT
	var ui_scale := UiScale.USER_DEFAULT
	var key_softening := KeyShaper.DEFAULT_SOFTENING
	var tcs_off := false
	var esc_off := false
	var auto_hold := false
	var abs_off := false
	var axle_diff := VehicleInput.AxleDiff.STOCK
	var parallel_steer := false
	var lab_locked := false  ## a challenge drives the stock hardware
	var wind_preset: int = WorldConditions.Preset.LEVEL
	var current_preset: int = WorldConditions.Preset.LEVEL
	var wind_from_deg := 0.0
	var night := false
	var conditions_locked := false  ## a challenge owns wind, current and lighting
	## The level's spawn points this body may use, by name; SPAWN POINT shows from two up.
	var spawns := PackedStringArray()

## Widest sensible button in logical px (scaled through UiTheme), matching the garage.
const BUTTON_W := 260.0
## Widest a help line or note runs before it wraps, in logical px (scaled); narrower on a window
## that cannot hold it.
const TEXT_W := 480.0

## Row shows one key per action, else "W / Up / S / Down" becomes the widest thing on the page.
const DRIVE_FOOTNOTE := "Arrow keys also drive."
## Each Column's head on the sheet, in Column order; the sheet adds what (first) and why not (last).
const COLUMN_HEADS := ["KEY", "GAMEPAD", "TOUCH"]
## The drawn pad's two sets: the plain buttons (COLUMN_HEADS' GAMEPAD), then with L1 held.
const PAD_LAYER_HEAD := "HOLD L1"
## Under a drawn pad with greyed callouts, before their reasons.
const GREYED_PREFIX := "Greyed: "

## Help lines: short and plain, for a young player; the guide pages carry the detail. A row says
## whether it is saved (SAVED) or lasts until a reload (SESSION).
const SAVED := " Kept next time."
const SESSION := " Resets when you reload."

const DENSITY_HELP := "COMPACT shows speed, revs and warning lights. FULL adds more gauges."
const UI_SCALE_HELP := "Makes buttons and text bigger or smaller. 100% is the normal size."
const KEY_RESPONSE_HELP := "How fast the keys and on-screen pedals react. RAW is instant. REALISTIC is smooth."

## SANDBOX's two section headings.
const WORLD_HEAD := "WORLD"
const VEHICLE_HEAD := "VEHICLE"

const TCS_HELP := "Stops the wheels spinning when you speed up. OFF lets them spin and slide." + SAVED
const ESC_HELP := "Brakes one wheel to stop the car spinning out. OFF also turns off traction control." + SAVED
const AUTO_HOLD_HELP := "Keeps the brake on when you stop, until you press the accelerator." + SAVED
const ABS_HELP := "Stops the wheels locking when you brake hard, so you can still steer. OFF also turns off the other helpers." + SESSION
const AXLE_DIFF_HELP := "OPEN: one wheel can spin while the other stops. LOCKED: both wheels turn together, but tight turns feel stiff." + SESSION
const STEERING_HELP := "STOCK turns the inside wheel more, like a real car. PARALLEL turns both the same, so turns get wider." + SESSION

const WIND_HELP := "Changes the wind." + SESSION
const CURRENT_HELP := "Changes how the sea flows." + SESSION
const FROM_HELP := "Where the wind and the sea come from, for LIGHT and STRONG."
const NIGHT_HELP := "Day or night. The N key does this too."
const LOCKED_HELP := "Locked during a challenge."

## How far Up/Down move the CONTROLS sheet, in logical px (scaled). About two rows.
const SHEET_STEP := 64.0

var _root: VBoxContainer
var _controls: VBoxContainer
var _settings: VBoxContainer
var _sandbox: VBoxContainer
var _spawn_page: VBoxContainer
var _sheet: ScrollContainer  ## CONTROLS sheet's scroll area, driven by Up/Down (_unhandled_input)
var _sheet_ctx := {}  ## ActionRegistry.context the sheet was built for
var _pad_box: VBoxContainer  ## the drawn pad's sets, above the table; hidden when it does not fit
var _pad_diagrams: Array[PadDiagram] = []
var _pad_drawn := false  ## the pad is drawn, so the table has no GAMEPAD column
var _table: VBoxContainer  ## the sheet's groups, rebuilt when the pad is drawn or stops fitting
var _wrapped: Array[Label] = []  ## help lines and notes, re-fitted on a resize (`_fit_text`)
var _resume_btn: Button
var _density_btn: Button
var _ui_scale_btn: Button
var _key_response_btn: Button
var _tcs_btn: Button
var _esc_btn: Button
var _auto_hold_btn: Button
var _abs_btn: Button
var _axle_diff_btn: Button
var _steering_btn: Button
var _wind_btn: Button
var _current_btn: Button
var _from_btn: Button
var _night_btn: Button
## Active vehicle's capabilities from the shell — same read the touch buttons gate on.
var _caps := {}
var _level_row := false
var _density: int = Dashboard.Density.COMPACT
var _ui_scale := UiScale.USER_DEFAULT
var _key_softening := KeyShaper.DEFAULT_SOFTENING
var _tcs_off := false
var _esc_off := false
var _auto_hold := false
var _abs_off := false
var _axle_diff := VehicleInput.AxleDiff.STOCK
var _parallel_steer := false
var _lab_locked := false  ## a challenge drives the stock hardware: the LAB switches grey out
var _wind_preset: int = WorldConditions.Preset.LEVEL
var _current_preset: int = WorldConditions.Preset.LEVEL
var _wind_from_deg := 0.0
var _night := false
var _conditions_locked := false  ## a challenge owns wind, current and lighting: WORLD greys out
var _spawns := PackedStringArray()
var _columns: Array[Column] = State.new().columns


## The CONTROLS columns for the devices used this session (UiScale): the keyboard's, the pad's and
## touch's, each once used. With none of them (only the mouse so far), the keyboard's, or touch's
## on a touch display.
static func sheet_columns(keyboard: bool, pad: bool, touched: bool,
		touch_display: bool) -> Array[Column]:
	var out: Array[Column] = []
	if keyboard:
		out.append(Column.KEY)
	if pad:
		out.append(Column.PAD)
	if touched:
		out.append(Column.TOUCH)
	if out.is_empty():
		out.append(Column.TOUCH if touch_display else Column.KEY)
	return out


## Called by the shell before add_child; pages build in _ready. Optional: with nothing handed
## over, capability-gated rows read unavailable and every setting reads its default.
func setup(caps: Dictionary, state := State.new()) -> void:
	_caps = caps
	_level_row = state.level_row
	_density = state.density
	_ui_scale = state.ui_scale
	_key_softening = state.key_softening
	_tcs_off = state.tcs_off
	_esc_off = state.esc_off
	_auto_hold = state.auto_hold
	_abs_off = state.abs_off
	_axle_diff = state.axle_diff
	_parallel_steer = state.parallel_steer
	_lab_locked = state.lab_locked
	_wind_preset = state.wind_preset
	_current_preset = state.current_preset
	_wind_from_deg = state.wind_from_deg
	_night = state.night
	_conditions_locked = state.conditions_locked
	_spawns = state.spawns
	_columns = state.columns


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
	_sandbox = _page()
	_sandbox.visible = false
	_build_sandbox()
	_spawn_page = _page()
	_spawn_page.visible = false
	_build_spawns()

	_resume_btn.grab_focus()  # keyboard/gamepad start point


## A centred column filling the overlay. Every page is one of these; only one is visible.
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
	_root.add_child(_menu_button("RESPAWN", func() -> void: respawn_requested.emit()))
	if _spawns.size() >= 2:
		_root.add_child(_menu_button("SPAWN POINT", func() -> void: _show_page(_spawn_page)))
	if _level_row:
		_root.add_child(_menu_button("LEVEL", func() -> void: level_requested.emit()))
	_root.add_child(_menu_button("SANDBOX", func() -> void: _show_page(_sandbox)))
	_root.add_child(_menu_button("CONTROLS", func() -> void: _show_page(_controls)))
	_root.add_child(_menu_button("SETTINGS", func() -> void: _show_page(_settings)))


## Generated from ActionRegistry: every row, grouping and gate comes from that table, and key
## strings are read live from InputMap, so a control can't exist without appearing here and a
## rebinding can't go stale. Columns: what it does, then one per device used this session
## (`_columns`: the key, the gamepad button `ActionRegistry.pad_for`, the on-screen button
## `ActionRegistry.touch_for`), and why not if it doesn't apply. A row the current
## vehicle/attachment can never use (family/capability gate fails) is HIDDEN outright —
## `ActionRegistry.relevant_entry` — and so is one none of those devices reaches; a group whose
## rows are all hidden loses its heading. A row blocked only because the bridge owns it right now
## still shows, greyed, with its gate note, since that reason goes away on its own. GAMEPAD is
## drawn above the table (PadDiagram) where it fits, else a text column (`_fit_pad`).
func _build_controls() -> void:
	_controls.add_child(_title("CONTROLS"))

	_sheet_ctx = ActionRegistry.context(GameState.current_vehicle, Bridge.is_active(), _caps,
			InputRouter.bridge_drives())
	# Scrolls: every bound action doesn't fit a phone.
	_sheet = ScrollContainer.new()
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet.add_child(body)
	_controls.add_child(_sheet)
	_pad_box = VBoxContainer.new()
	body.add_child(_pad_box)
	_table = VBoxContainer.new()
	body.add_child(_table)
	if _columns.has(Column.PAD):
		_build_pad()
	_pad_drawn = _pad_fits(_sheet_width())
	_pad_box.visible = _pad_drawn
	_fill_table()

	_controls.add_child(_back_button(func() -> void: _show_page(_root)))


## The plain set, then the L1 set when the vehicle has one, each under its heading and above a
## line saying why its greyed callouts are greyed.
func _build_pad() -> void:
	for layer in [false, true]:
		if layer and PadDiagram.callouts(_sheet_ctx, true).is_empty():
			continue
		var heading := Label.new()
		heading.text = PAD_LAYER_HEAD if layer else COLUMN_HEADS[Column.PAD]
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.theme_type_variation = &"Title"
		_pad_box.add_child(heading)
		var diagram := PadDiagram.new()
		diagram.setup(_sheet_ctx, layer)
		_pad_box.add_child(diagram)
		_pad_diagrams.append(diagram)
		var notes := diagram.greyed_notes()
		if not notes.is_empty():
			var note := Label.new()
			note.text = GREYED_PREFIX + ", ".join(notes)
			_wrap(note)
			note.theme_type_variation = &"MutedSmall"
			_pad_box.add_child(note)


## The width the sheet lays out in: the page between its margins, less the scroll bar.
func _sheet_width() -> float:
	return size.x - 2.0 * UiTheme.px(self, UiTheme.MARGIN) \
			- _sheet.get_v_scroll_bar().get_combined_minimum_size().x


func _pad_fits(available: float) -> bool:
	if _pad_diagrams.is_empty():
		return false
	for diagram in _pad_diagrams:
		if diagram.needed_width() > available:
			return false
	return true


## Draw the pad, or fall back to the text column, as `available` px now allow.
func _fit_pad(available: float) -> void:
	var drawn := _pad_fits(available)
	if drawn == _pad_drawn:
		return
	_pad_drawn = drawn
	_pad_box.visible = drawn
	_fill_table()


func _fill_table() -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var ctx := _sheet_ctx
	var columns := _columns.duplicate()
	if _pad_drawn:
		columns.erase(Column.PAD)
	for group in ActionRegistry.Group.values():
		var rows: Array[Dictionary] = []
		var cells: Array[PackedStringArray] = []  ## per row, its text in each of `columns`
		for entry in ActionRegistry.in_group(group):
			if not ActionRegistry.relevant_entry(entry, ctx):
				continue
			var texts := PackedStringArray()
			for column in columns:
				texts.append(_sheet_cell(entry, column))
			if "".join(texts) == "":
				continue
			rows.append(entry)
			cells.append(texts)
		if rows.is_empty():
			continue
		var heading := Label.new()
		heading.text = ActionRegistry.GROUP_TITLES[group]
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.theme_type_variation = &"Title"
		_table.add_child(heading)

		# Centred as a block so pairs line up instead of drifting apart on a wide window.
		var grid := GridContainer.new()
		grid.columns = columns.size() + 2
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var heads := [""]
		for column in columns:
			heads.append(COLUMN_HEADS[column])
		heads.append("")
		for head: String in heads:
			var head_label := Label.new()
			head_label.text = head
			head_label.theme_type_variation = &"MutedSmall"
			grid.add_child(head_label)
		for r in rows.size():
			var entry := rows[r]
			var applies := ActionRegistry.applies_entry(entry, ctx)
			var what := Label.new()
			what.text = String(entry["label"])
			what.theme_type_variation = &"Muted" if not applies else &""
			grid.add_child(what)
			for text in cells[r]:
				var cell := Label.new()
				cell.text = text
				cell.theme_type_variation = &"MutedSmall" if not applies else &"Dim"
				grid.add_child(cell)
			var note := Label.new()
			note.text = ActionRegistry.gate_note(entry, ctx)
			note.theme_type_variation = &"MutedSmall"
			grid.add_child(note)
		_table.add_child(grid)

		if group == ActionRegistry.Group.DRIVE and _columns.has(Column.KEY):
			var footnote := Label.new()
			footnote.text = DRIVE_FOOTNOTE
			footnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			footnote.theme_type_variation = &"Small"
			_table.add_child(footnote)


static func _sheet_cell(entry: Dictionary, column: Column) -> String:
	match column:
		Column.KEY:
			return ActionRegistry.keys_for(entry)
		Column.PAD:
			return ActionRegistry.pad_for(entry)
	return ActionRegistry.touch_for(entry)


## Three settings, one button each, cycling their steps. No value is applied here — each is
## emitted and the shell applies/persists it (rule 6). Each button relabels in place.
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

	_key_response_btn = _menu_button("", _on_key_response_pressed)
	_relabel_key_response()
	_settings.add_child(_key_response_btn)
	_settings.add_child(_help(KEY_RESPONSE_HELP))

	_settings.add_child(_back_button(func() -> void: _show_page(_root)))


## WORLD, then VEHICLE, each a heading over cycling buttons + short help. Ten rows outgrow a
## phone, so they scroll and follow the focused one. Nothing is applied here (rule 6).
func _build_sandbox() -> void:
	_sandbox.add_child(_title("SANDBOX"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL  # centred while it fits
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(rows)
	_sandbox.add_child(scroll)
	_build_world(rows)
	_build_vehicle(rows)
	_sandbox.add_child(_back_button(func() -> void: _show_page(_root)))


## Wind/current/direction/time-of-day. Wind and current are disabled (with a reason) on a family
## whose physics never reads the `WindField`/`CurrentField`. The shell keeps the values for the
## session and applies them to the current (and every future) level.
func _build_world(box: VBoxContainer) -> void:
	box.add_child(_heading(WORLD_HEAD))
	var family := GameState.current_vehicle

	_wind_btn = _menu_button("", _on_wind_pressed)
	_relabel_wind()
	box.add_child(_wind_btn)
	var wind_help := _help(WIND_HELP)
	if not WorldConditions.WIND_FAMILIES.has(family):
		_wind_btn.disabled = true
		wind_help.text = "no effect on the %s" % family
	box.add_child(wind_help)

	_current_btn = _menu_button("", _on_current_pressed)
	_relabel_current()
	box.add_child(_current_btn)
	var current_help := _help(CURRENT_HELP)
	if not WorldConditions.CURRENT_FAMILIES.has(family):
		_current_btn.disabled = true
		current_help.text = "no effect on the %s" % family
	box.add_child(current_help)

	_from_btn = _menu_button("", _on_from_pressed)
	_relabel_from()
	box.add_child(_from_btn)
	var from_help := _help(FROM_HELP)
	box.add_child(from_help)

	_night_btn = _menu_button("", _on_night_pressed)
	_relabel_night()
	box.add_child(_night_btn)
	var night_help := _help(NIGHT_HELP)
	box.add_child(night_help)

	if _conditions_locked:
		for btn: Button in [_wind_btn, _current_btn, _from_btn, _night_btn]:
			btn.disabled = true
		for help: Label in [wind_help, current_help, from_help, night_help]:
			help.text = LOCKED_HELP


## The driver aids (saved), then the LAB switches on the machine's own hardware (session-only):
## A/B switches, disabled (with a reason) on a body without the hardware, in a challenge, which
## drives stock, and under a live bridge (`_lab_off_reason`).
func _build_vehicle(box: VBoxContainer) -> void:
	box.add_child(_heading(VEHICLE_HEAD))

	_tcs_btn = _menu_button("", _on_tcs_pressed)
	_relabel_tcs()
	box.add_child(_tcs_btn)
	box.add_child(_help(TCS_HELP))

	_esc_btn = _menu_button("", _on_esc_pressed)
	_relabel_esc()
	box.add_child(_esc_btn)
	box.add_child(_help(ESC_HELP))

	_auto_hold_btn = _menu_button("", _on_auto_hold_pressed)
	_relabel_auto_hold()
	box.add_child(_auto_hold_btn)
	box.add_child(_help(AUTO_HOLD_HELP))

	_abs_btn = _menu_button("", _on_abs_pressed)
	_relabel_abs()
	box.add_child(_abs_btn)
	var abs_help := _help(ABS_HELP)
	var lab_off := _lab_off_reason()
	if lab_off != "":
		_abs_btn.disabled = true
		abs_help.text = lab_off
	elif not bool(_caps.get("abs", false)):
		_abs_btn.disabled = true
		abs_help.text = "no ABS on the %s" % GameState.current_variant
	box.add_child(abs_help)

	# A body with its own DIFF LOCK key (the tractors) teaches the lesson there: no row.
	if not bool(_caps.get("diff_lock", false)):
		_axle_diff_btn = _menu_button("", _on_axle_diff_pressed)
		_relabel_axle_diff()
		box.add_child(_axle_diff_btn)
		var diff_help := _help(AXLE_DIFF_HELP)
		if lab_off != "":
			_axle_diff_btn.disabled = true
			diff_help.text = lab_off
		elif not bool(_caps.get("axle_diff", false)):
			_axle_diff_btn.disabled = true
			diff_help.text = "the %s cannot switch this" % GameState.current_variant
		box.add_child(diff_help)

	_steering_btn = _menu_button("", _on_steering_pressed)
	_relabel_steering()
	box.add_child(_steering_btn)
	var steering_help := _help(STEERING_HELP)
	if lab_off != "":
		_steering_btn.disabled = true
		steering_help.text = lab_off
	elif not bool(_caps.get("ackermann", false)):
		_steering_btn.disabled = true
		steering_help.text = "the %s cannot switch this" % GameState.current_variant
	box.add_child(steering_help)


## Why every LAB switch is greyed ("" when none): a challenge drives stock, and the switches act on
## local input only, so a live bridge (fallback included) leaves them acting on nothing. Read when
## the page builds, like the CONTROLS sheet: a bridge that connects under the pause shows on reopen.
func _lab_off_reason() -> String:
	if _lab_locked:
		return LOCKED_HELP
	if Bridge.is_active():
		return ActionRegistry.BRIDGE_SETS_NOTE
	return ""


## One button per spawn point, in the level's order (the first is its default).
func _build_spawns() -> void:
	_spawn_page.add_child(_title("SPAWN POINT"))
	for i in _spawns.size():
		_spawn_page.add_child(_menu_button(_spawns[i].to_upper(),
				func() -> void: spawn_picked.emit(i)))
	_spawn_page.add_child(_back_button(func() -> void: _show_page(_root)))


## A SANDBOX section's heading.
func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"Title"
	return label


func _help(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Small"
	return _wrap(label)


## Centred, wrapping at TEXT_W (`_fit_text`), so a long help line is a short paragraph.
func _wrap(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wrapped.append(label)
	_fit_text(label)
	return label


## A wrapping label's width: TEXT_W, or the page between its margins when that is narrower (never
## below a button's width, so an unsized overlay still lays out).
func _fit_text(label: Label) -> void:
	var room := size.x - 2.0 * UiTheme.px(self, UiTheme.MARGIN)
	label.custom_minimum_size.x = clampf(room, UiTheme.px(self, BUTTON_W),
			UiTheme.px(self, TEXT_W))


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


func _on_key_response_pressed() -> void:
	_key_softening = KeyShaper.next_softening(_key_softening)
	_relabel_key_response()
	key_softening_changed.emit(_key_softening)


func _relabel_key_response() -> void:
	_key_response_btn.text = "KEY RESPONSE: %s" % KeyShaper.softening_label(_key_softening)


func _on_tcs_pressed() -> void:
	_tcs_off = not _tcs_off
	_relabel_tcs()
	tcs_off_changed.emit(_tcs_off)


func _relabel_tcs() -> void:
	# The LAB's ABS off or locked diffs take ESC with them and STABILITY CONTROL off takes TC with it
	# (`InputRouter.arbitrate_local`), whatever this setting.
	var lab := _lab_esc_cause()
	_tcs_btn.text = "TRACTION CONTROL: %s" % ("OFF (WITH %s)" % lab if lab != ""
			else "OFF (WITH ESC)" if _esc_off else "OFF" if _tcs_off else "ON")


func _on_esc_pressed() -> void:
	_esc_off = not _esc_off
	_relabel_esc()
	_relabel_tcs()
	esc_off_changed.emit(_esc_off)


func _relabel_esc() -> void:
	var lab := _lab_esc_cause()
	_esc_btn.text = "STABILITY CONTROL: %s" % ("OFF (WITH %s)" % lab if lab != ""
			else "OFF" if _esc_off else "ON")


func _on_auto_hold_pressed() -> void:
	_auto_hold = not _auto_hold
	_relabel_auto_hold()
	auto_hold_changed.emit(_auto_hold)


func _relabel_auto_hold() -> void:
	_auto_hold_btn.text = "AUTO HOLD: %s" % ("ON" if _auto_hold else "OFF")


func _on_abs_pressed() -> void:
	_abs_off = not _abs_off
	_relabel_abs()
	_relabel_esc()
	_relabel_tcs()
	abs_off_changed.emit(_abs_off)


func _relabel_abs() -> void:
	_abs_btn.text = "ANTI-LOCK BRAKES: %s" % ("OFF" if _abs_off else "ON")


func _on_axle_diff_pressed() -> void:
	_axle_diff = posmod(_axle_diff + 1, VehicleInput.AxleDiff.size()) as VehicleInput.AxleDiff
	_relabel_axle_diff()
	_relabel_esc()
	_relabel_tcs()
	axle_diff_changed.emit(_axle_diff)


func _relabel_axle_diff() -> void:
	_axle_diff_btn.text = "DIFFERENTIALS: %s" % VehicleInput.AxleDiff.find_key(_axle_diff)


func _on_steering_pressed() -> void:
	_parallel_steer = not _parallel_steer
	_relabel_steering()
	parallel_steer_changed.emit(_parallel_steer)


func _relabel_steering() -> void:
	_steering_btn.text = "STEERING: %s" % ("PARALLEL" if _parallel_steer else "STOCK")


## What the LAB takes ESC off with on this body ("" for nothing), as the router gates it: never in a
## challenge, under a live bridge, nor on a body without the hardware (`InputRouter.lab_raw`).
func _lab_esc_cause() -> String:
	var lab := InputRouter.lab_raw(_abs_off, _axle_diff, _parallel_steer, _caps,
			_lab_off_reason() != "")
	return InputRouter.lab_esc_cause(bool(lab[&"abs_off"]),
			int(lab[&"axle_diff"]) as VehicleInput.AxleDiff)


func _on_wind_pressed() -> void:
	_wind_preset = WorldConditions.next_preset(_wind_preset)
	_relabel_wind()
	conditions_changed.emit(_wind_preset, _current_preset, _wind_from_deg)


func _relabel_wind() -> void:
	_wind_btn.text = "WIND: %s" % WorldConditions.PRESET_LABELS[_wind_preset]


func _on_current_pressed() -> void:
	_current_preset = WorldConditions.next_preset(_current_preset)
	_relabel_current()
	conditions_changed.emit(_wind_preset, _current_preset, _wind_from_deg)


func _relabel_current() -> void:
	_current_btn.text = "WATER CURRENT: %s" % WorldConditions.PRESET_LABELS[_current_preset]


func _on_from_pressed() -> void:
	_wind_from_deg = fposmod(_wind_from_deg + WorldConditions.DIRECTION_STEP_DEG, 360.0)
	_relabel_from()
	conditions_changed.emit(_wind_preset, _current_preset, _wind_from_deg)


func _relabel_from() -> void:
	_from_btn.text = "FROM: %s" % WorldConditions.compass_label(_wind_from_deg)


func _on_night_pressed() -> void:
	_night = not _night
	_relabel_night()
	night_toggled.emit(_night)


func _relabel_night() -> void:
	_night_btn.text = "TIME: %s" % ("NIGHT" if _night else "DAY")


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
	# A resize need not change the theme (UiScale keeps a scale it already has): refit on both.
	if (what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED) and _pad_box != null:
		_fit_pad(_sheet_width())
		for label in _wrapped:
			_fit_text(label)
	if what != NOTIFICATION_THEME_CHANGED or _root == null:
		return
	var margin := int(UiTheme.px(self, UiTheme.MARGIN))
	for page: VBoxContainer in [_root, _controls, _settings, _sandbox, _spawn_page]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,
				Control.PRESET_MODE_MINSIZE, margin)
		for b in _buttons_of(page):
			_size_button(b)


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
	_sandbox.visible = page == _sandbox
	_spawn_page.visible = page == _spawn_page
	# Focus follows the page, else a keyboard player is left driving an invisible button.
	for b in _buttons_of(page):
		if not b.disabled:
			b.grab_focus()
			break


## `page`'s buttons in tree order, SANDBOX's inside its scroll included.
static func _buttons_of(page: Node) -> Array[Button]:
	var out: Array[Button] = []
	for node in page.find_children("*", "Button", true, false):
		out.append(node as Button)
	return out


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


func _back_button(on_press: Callable) -> Button:
	var b := _menu_button("BACK", on_press)
	b.theme_type_variation = &"Back"
	return b


func _size_button(b: Button) -> void:
	b.custom_minimum_size = Vector2(UiTheme.px(self, BUTTON_W), UiTheme.px(self, UiTheme.TOUCH_MIN))
