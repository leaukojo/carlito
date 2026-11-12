class_name ChallengeBriefing
extends Control
## Read-only briefing for a challenge already running (touch INFO button, boot.gd
## `_show_challenge_info`) — title, briefing, a HINT toggle, CLOSE. Unlike ChallengeSelect's
## briefing page this owns no START: the attempt underneath is already going, and RETRY is a
## separate button. Built in code, a transient overlay the shell frees. No emoji.

signal closed

var _def: ChallengeDef
var _hint_label: Label
var _col: VBoxContainer
var _wrapped: Array[Label] = []  ## the paragraphs held to a fixed reading width


## Called by the shell before add_child.
func setup(def: ChallengeDef) -> void:
	_def = def


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.SCRIM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var col := VBoxContainer.new()
	_col = col
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	var title := Label.new()
	title.text = _def.title.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	col.add_child(title)

	var briefing := Label.new()
	briefing.text = _def.briefing
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing.theme_type_variation = &"Lead"
	_wrapped.append(briefing)
	col.add_child(briefing)

	if _def.par_s > 0.0:
		var par := Label.new()
		par.text = "TIME LIMIT: %s S" % String.num(_def.par_s, 1)
		par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		par.theme_type_variation = &"Dim"
		col.add_child(par)

	if not _def.gearbox_text().is_empty():
		var gearbox := Label.new()
		gearbox.text = _def.gearbox_text()
		gearbox.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gearbox.theme_type_variation = &"Lead"
		col.add_child(gearbox)

	_hint_label = Label.new()
	_hint_label.text = _def.hint
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrapped.append(_hint_label)
	_hint_label.theme_type_variation = &"LeadDim"
	_hint_label.visible = false
	col.add_child(_hint_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(UiTheme.button(self, "HINT",
			func() -> void: _hint_label.visible = not _hint_label.visible))
	var close := UiTheme.button(self, "CLOSE", func() -> void: closed.emit())
	row.add_child(close)
	_apply_sizes()
	close.grab_focus()


## Pixel sizes follow the theme's scale, so a resize re-applies them (buttons take theirs from
## `UiTheme.size_button`).
func _apply_sizes() -> void:
	_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	for label in _wrapped:
		label.custom_minimum_size.x = UiTheme.px(self, 480.0)
	for b in _col.find_children("*", "Button", true, false):
		UiTheme.size_button(self, b as Button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _col != null:
		_apply_sizes()
