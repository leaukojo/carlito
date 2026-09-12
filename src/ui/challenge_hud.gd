class_name ChallengeHud
extends Control
## The objective + timer readout while a challenge attempt is running: "GOAL 2 / 4  0:07.3",
## with "PAR 12.0" appended when the def has one. boot.gd owns its lifetime — built in
## `_begin_challenge`, freed in `_end_challenge` — and hands it the runner to read each frame.
## No emoji; colour/type from the theme.

var _runner: ChallengeRunner
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Below both the top-edge Notice line (RESET's warning included) and CoachCue's banner
	# (offset_top 90) — an attempt can show either at the same time as this.
	panel.offset_top = UiTheme.px(self, 150.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.theme_type_variation = &"Title"
	panel.add_child(_label)


func set_runner(runner: ChallengeRunner) -> void:
	_runner = runner


func _process(_dt: float) -> void:
	if _runner == null or _runner.attempt == null:
		return
	var a := _runner.attempt
	var text := "GOAL %d / %d   %s S" % [
		mini(a.goal_index + 1, a.goal_count()), a.goal_count(), String.num(a.elapsed, 1)]
	if _runner.def.par_s > 0.0:
		text += "   PAR %s S" % String.num(_runner.def.par_s, 1)
	_label.text = text
