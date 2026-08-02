class_name CoachCue
extends Control
## The one-line "you can drive this" cue, shown over the first frames of a first visit.
##
## The game now opens in a level with a car sitting in it and no menu in front of it, which is
## the point — but someone who arrived not knowing this is a playable game still needs to be
## told once. So: one line, dismissed by the FIRST input of any kind (you already knew) or by
## a short timeout, and never shown again on this machine (ShellPrefs.coach_seen).
##
## It listens on `_input`, which sees events without consuming them: the press that dismisses
## the cue is also the press that drives the car. No emoji; colour and type from the theme.

## How long it stays if nobody touches anything, and how long it takes to go.
const DWELL_S := 8.0
const FADE_S := 0.6

## The vehicle family this cue is for, or "" for the first-visit "you can drive this" line. The
## AIRCRAFT get one of their own because climb/descend is a whole axis the ground vehicles do not
## have, and nothing on screen says which keys work it — see _text().
var family := ""

var _dismissed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never in the way of the touch pads

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


## What to say depends on what they are holding AND on what they are in. The touch overlay only
## shows on touch/web (TouchControls._should_show), so this asks the same question.
##
## The two aircraft lines lead with the thing that is otherwise undiscoverable: R / F, the climb
## axis, which no ground vehicle has and which no other piece of UI names. The drone's leads with
## ARM instead, because a disarmed quad answers NOTHING and reads as broken rather than as off.
## Keys are named here rather than pulled from ActionRegistry on purpose: the registry's labels are
## the settings sheet's sentences, and this line is one short sentence of its own.
func _text() -> String:
	var touch := UiScale.is_touch_display()
	match family:
		"plane":
			if touch:
				return "Hold GAS for throttle  -  UP / DOWN to climb and descend  -  MENU for everything else"
			return "W for throttle  -  R to climb, F to descend  -  A / D to steer  -  Esc for the menu"
		"drone":
			if touch:
				return "ARM the motors first  -  UP / DOWN to rise and sink  -  drag the stick to fly"
			return "T to arm the motors  -  R to go up, F to go down  -  W / S / A / D to fly"
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
