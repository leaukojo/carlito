extends ChaseCamera
## Orbit camera for the Garage showroom. Extends ChaseCamera so Level's typed
## `camera` export and its target/snap wiring work unchanged, but replaces the chase
## behaviour with a mouse/touch orbit around a stationary (physics-frozen) vehicle.
##
## The target never moves, so plain global_position math is correct here — no
## interpolation (unlike ChaseCamera, which follows a moving body per rendered frame).

@export var min_pitch_deg := -70.0  ## look up at the underside
@export var max_pitch_deg := 75.0   ## look down from above (avoid the gimbal pole)
@export var min_distance := 3.0
@export var max_distance := 25.0    ## headroom for future larger vehicles
@export var orbit_speed := 0.008    ## radians per pixel of drag
@export var zoom_step := 1.5        ## metres per mouse-wheel notch
@export var pinch_zoom_speed := 0.03  ## metres per pixel of two-finger pinch delta

var _yaw := 0.6
var _pitch := 0.35
var _mouse_orbiting := false
var _touches: Dictionary = {}  ## touch index -> last screen position
var _pinch_distance := 0.0


func _process(_delta: float) -> void:
	_apply()


## Level calls this on spawn/respawn. Orbit has no smoothing, so it is the same as
## the per-frame update.
func snap() -> void:
	_apply()


## Place the camera on the orbit sphere around the target and look at the pivot.
func _apply() -> void:
	if target == null:
		return
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	distance = clampf(distance, min_distance, max_distance)
	var pivot := target.global_position + Vector3.UP * look_height
	var offset := Vector3(
			cos(_pitch) * sin(_yaw),
			sin(_pitch),
			cos(_pitch) * cos(_yaw)) * distance
	global_position = pivot + offset
	look_at(pivot)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance -= zoom_step
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance += zoom_step
	elif event is InputEventMouseMotion and _mouse_orbiting:
		_orbit((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_distance = _pinch_gap()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var gap := _pinch_gap()
			if _pinch_distance > 0.0:
				distance -= (gap - _pinch_distance) * pinch_zoom_speed
			_pinch_distance = gap
		else:
			_orbit(sd.relative)


func _orbit(relative: Vector2) -> void:
	_yaw -= relative.x * orbit_speed
	_pitch -= relative.y * orbit_speed


## Screen-space distance between the first two active touches (0 if fewer than two).
func _pinch_gap() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)
