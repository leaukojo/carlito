class_name ChallengeBriefing
extends Control
## Read-only briefing for a challenge already running (touch INFO button, boot.gd
## `_show_challenge_info`) — title, briefing, a HINT toggle, CLOSE. Unlike ChallengeSelect's
## briefing page this owns no START: the attempt underneath is already going, and RETRY is a
## separate button. Built in code, a transient overlay the shell frees. No emoji.

signal closed

var _def: ChallengeDef
var _hint_label: Label


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
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
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
	briefing.custom_minimum_size.x = UiTheme.px(self, 480.0)
	col.add_child(briefing)

	if _def.par_s > 0.0:
		var par := Label.new()
		par.text = "PAR: %s S" % String.num(_def.par_s, 1)
		par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		par.theme_type_variation = &"Small"
		col.add_child(par)

	_hint_label = Label.new()
	_hint_label.text = _def.hint
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size.x = UiTheme.px(self, 480.0)
	_hint_label.theme_type_variation = &"Dim"
	_hint_label.visible = false
	col.add_child(_hint_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(_btn("HINT", func() -> void: _hint_label.visible = not _hint_label.visible))
	var close := _btn("CLOSE", func() -> void: closed.emit())
	row.add_child(close)
	close.grab_focus()


func _btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UiTheme.px(self, 200.0), UiTheme.px(self, UiTheme.TOUCH_MIN))
	b.pressed.connect(on_press)
	return b
