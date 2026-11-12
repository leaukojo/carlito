class_name ChallengeResult
extends Control
## The pass/fail result overlay: RETRY, plus NEXT and CHALLENGES on a pass, replacing the plain
## pass/fail notice. `setup()` stashes what to show; `_ready()` builds it once in the tree (theme
## scale needs a Control ancestor). RETRY is the same respawn the R key already performs
## mid-attempt — a challenge's runner resets the attempt on ANY respawn, so this button owns no
## logic of its own. NEXT walks the def's family list; CHALLENGES opens the grid instead. Leaving
## to the menu happens from the resumed attempt, not from here. Built in code, a transient
## overlay the shell frees. No emoji.

signal retry_requested
signal next_requested
signal challenges_requested

var _def: ChallengeDef
var _passed := false
var _elapsed_s := 0.0
var _message := ""
var _best_time := INF
var _is_new_best := false
var _has_next := false
var _col: VBoxContainer


## Called by the shell before add_child.
func setup(def: ChallengeDef, passed: bool, elapsed_s: float, message: String,
		best_time: float, is_new_best: bool, has_next: bool) -> void:
	_def = def
	_passed = passed
	_elapsed_s = elapsed_s
	_message = message
	_best_time = best_time
	_is_new_best = is_new_best
	_has_next = has_next


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
	title.text = ("PASSED" if _passed else "FAILED") + "  -  " + _def.title.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	col.add_child(title)

	var body := Label.new()
	if _passed:
		body.text = "%s S%s" % [String.num(_elapsed_s, 1), "  -  NEW BEST" if _is_new_best else ""]
	else:
		body.text = _message.to_upper()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.theme_type_variation = &"Title"
	col.add_child(body)

	if is_finite(_best_time):
		var best := Label.new()
		best.text = "BEST: %s S" % String.num(_best_time, 1)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.theme_type_variation = &"Dim"
		col.add_child(best)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var retry := UiTheme.button(self, "RETRY", func() -> void: retry_requested.emit())
	row.add_child(retry)
	if _passed:
		var next_btn := UiTheme.button(self, "NEXT", func() -> void: next_requested.emit())
		next_btn.disabled = not _has_next
		row.add_child(next_btn)
		row.add_child(UiTheme.button(self, "CHALLENGES", func() -> void: challenges_requested.emit()))

	_apply_sizes()
	retry.grab_focus()


## Pixel sizes follow the theme's scale, so a resize re-applies them.
func _apply_sizes() -> void:
	_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	for b in _col.find_children("*", "Button", true, false):
		UiTheme.size_button(self, b as Button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _col != null:
		_apply_sizes()
