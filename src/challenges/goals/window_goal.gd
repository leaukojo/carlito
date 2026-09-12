class_name WindowGoal
extends ChallengeGoal
## Base of the goals judged while the body is inside `zone` and settled when it leaves. Entry
## counts on a tick whose path crossed the zone, so a gate thinner than one tick of travel cannot
## be skipped. With `exit_zone`, only leaving INTO it settles the goal, and any other way out
## fails: a speed trap left by the side, a corridor left through its roof, a window reversed back
## out of. Without one, leaving by any face settles it.

enum Where { BEFORE, INSIDE, LEFT, STRAYED }

@export var zone: StringName
@export var exit_zone: StringName = &""   ## empty: any way out

var _zone: ZoneShape
var _exit: ZoneShape
var _entered := false


func reset() -> void:
	super()
	_entered = false


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	var out := _missing(zone, _zone)
	_exit = null
	if exit_zone != &"":
		_exit = zones.get(exit_zone) as ZoneShape
		out.append_array(_missing(exit_zone, _exit))
	return out


## Where the body is against the window this tick. INSIDE marks the window entered.
func _where(frame: ChallengeFrame) -> Where:
	if _entered and _exit != null and _touched(_exit, frame):
		return Where.LEFT
	if _touched(_zone, frame):
		_entered = true
		return Where.INSIDE
	if not _entered:
		return Where.BEFORE
	return Where.LEFT if _exit == null else Where.STRAYED


func _strayed() -> Status:
	message = "left %s without going through %s" % [zone, exit_zone]
	return Status.FAIL
