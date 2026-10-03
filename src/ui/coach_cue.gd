class_name CoachCue
extends Control
## The one-line "you can drive this" cue, shown over the first frames of a session — the
## game opens straight into a level with no menu in front of it, so this teaches it once.
## One line, dismissed by the first input of any kind or a short timeout, never shown again
## within a session (`maybe_coach`).
##
## Listens on `_input`, which sees events without consuming them, so the press that dismisses
## the cue is also the press that drives the car. No emoji; colour/type from the theme.

## How long it stays if nobody touches anything, and how long it takes to go.
const DWELL_S := 8.0
const FADE_S := 0.6

## Families with a control axis ground vehicles don't have; get a cue every time you climb
## into one this session.
const COACH_FAMILIES := ["plane", "drone"]

## Session state: static, since a run boots one shell and it lives as long as the run does.
static var _coach_shown := false
## Families coached this session (see maybe_coach): the aircraft cue teaches a control set only
## relevant while flying, so it reappears each new flight of a session.
static var _coached_families := {}

## Vehicle family this cue is for, or "" for the first-visit line. Aircraft get their own
## because climb/descend has no ground-vehicle equivalent and nothing else names its keys.
var family := ""

var _dismissed := false


## Two cues: the first-visit line (first level of a session only) and the aircraft line (once per
## family per session, since climb/descend is undiscoverable). Aircraft takes precedence on a
## session's first body; the first-visit line is left unseen for the next ground vehicle.
static func maybe_coach(for_family: String, parent: Control) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if for_family in COACH_FAMILIES:
		if _coached_families.has(for_family):
			return
		_coached_families[for_family] = true
		_show_coach(for_family, parent)
		return
	if _coach_shown:
		return
	_coach_shown = true
	_show_coach("", parent)


static func _show_coach(for_family: String, parent: Control) -> void:
	var cue := CoachCue.new()
	cue.family = for_family  # before add_child: _ready() builds the label from it
	parent.add_child(cue)


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
