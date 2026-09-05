class_name CoachCue
extends Control
## The one-line "you can drive this" cue, shown over the first frames of a first visit — the
## game opens straight into a level with no menu in front of it, so this teaches it once.
## One line, dismissed by the first input of any kind or a short timeout, never shown again
## on this machine (ShellPrefs.coach_seen).
##
## Listens on `_input`, which sees events without consuming them, so the press that dismisses
## the cue is also the press that drives the car. No emoji; colour/type from the theme.

## How long it stays if nobody touches anything, and how long it takes to go.
const DWELL_S := 8.0
const FADE_S := 0.6

## Vehicle family this cue is for, or "" for the first-visit line. Aircraft get their own
## because climb/descend has no ground-vehicle equivalent and nothing else names its keys.
var family := ""

var _dismissed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never blocks the touch pads

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = UiTheme.px(self, 90.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var label := Label.new()
	label.text = _text()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"Title"
	panel.add_child(label)

	await get_tree().create_timer(DWELL_S).timeout
	_dismiss()


## What to say depends on input mode and family. Aircraft lines lead with R/F (climb), the
## otherwise-undiscoverable axis; the drone leads with ARM, since a disarmed quad answers
## nothing and reads as broken. Keys are named here, not pulled from ActionRegistry: that
## registry's labels are the settings sheet's sentences, this is its own short line.
func _text() -> String:
	var touch := UiScale.is_touch_display()
	match family:
		"plane":
			if touch:
				return "Hold GAS for throttle  -  UP / DOWN to climb and descend  -  MENU for everything else"
			return "W for throttle  -  R to climb, F to descend  -  A / D to steer  -  Esc for the menu"
		"drone":
			if touch:
				return "ARM the motors first  -  UP / DOWN to rise and sink  -  MODE for alt hold"
			return "T to arm  -  R / F to go up and down  -  W A S D to fly  -  Z for flight mode"
	if touch:
		return "Hold GAS to drive  -  drag the stick to steer  -  MENU for everything else"
	return "W to drive  -  A / D to steer  -  Esc for the menu"


func _input(event: InputEvent) -> void:
	if _dismissed:
		return
	if event is InputEventKey or event is InputEventJoypadButton \
			or event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.is_pressed():
			_dismiss()


func _dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_S)
	tween.tween_callback(queue_free)
