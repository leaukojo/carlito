class_name ChaseCamera
extends Camera3D
## Chase camera on the BaseVehicle camera-target contract.
##
## Follows in _process using get_global_transform_interpolated(): physics runs at
## the locked 60 Hz with interpolation, so reading global_transform here
## would sample the raw tick and stutter.
##
## Four views, cycled by [method cycle] (the 'camera_view' action / touch VIEW button):
## CHASE (yaw-only follow, the default), HOOD (rigid to the body, full pitch/roll),
## ISO (fixed world-space 3/4 angle, orthogonal — reads level layout), TOP (overhead
## yaw-follow — reads slip/drift). Every view but HOOD pulls in when geometry blocks the
## line back to the vehicle, so a downslope or a road GridMap can't bury the camera.
## ISO and TOP additionally zoom on the mouse wheel ([method zoom]); CHASE and HOOD don't,
## their framing belongs to the vehicle rather than the level.

enum Mode {CHASE, HOOD, ISO, TOP}

## Never let the occlusion pull-in put the camera on the look-at point — look_at() errors
## out when origin and target coincide.
const MIN_PIVOT_DIST := 0.35

@export var target: Node3D
@export var distance := 6.0
@export var height := 2.5
@export var look_height := 1.2
@export var smoothing := 5.0  ## 1/s exponential position catch-up rate
@export_flags_3d_physics var collision_mask := 1  ## layers the camera may not pass through
@export var collision_margin := 0.3  ## keep-out distance from a hit surface
## Bonnet-cam seat offset in body space (-Z is forward). Fallback only: a vehicle scene
## with a "HoodCam" Marker3D child overrides it (marker position only, rotation ignored).
@export var hood_offset := Vector3(0.0, 1.35, -0.55)
@export var iso_offset := Vector3(14.0, 16.0, 14.0)  ## fixed world-space 3/4 view
@export var iso_size := 26.0  ## orthogonal frustum height for ISO
@export var top_height := 30.0
@export var top_back := 6.0  ## nudge behind the vehicle so it sits low in frame

## Mouse-wheel zoom, ISO and TOP only (CHASE/HOOD are framed by the vehicle, not the level).
const ZOOM_STEP := 1.12
const ZOOM_MIN := 0.12
const ZOOM_MAX := 3.0

var mode := Mode.CHASE

## Zoom multiplier per zoomable view, kept apart so switching views doesn't carry one
## view's framing into the other.
var _zoom := {Mode.ISO: 1.0, Mode.TOP: 1.0}

var _fov_perspective := 75.0
## Smoothed follow position BEFORE occlusion pull-in. Feeding the pulled-in position back
## into the next frame's lerp makes the camera oscillate in/out against a wall (shaking).
var _free_position := Vector3.ZERO
var _has_free := false
## Cached get_camera_framing() — constant per vehicle, so recompute only when the target
## changes instead of allocating a fresh Dictionary every frame on the follow path.
var _framing_cache: Dictionary
var _framing_target: Node3D = null


func _ready() -> void:
	# This node moves per rendered frame, not per physics tick — interpolating it
	# against stale physics snapshots would fight _process and judder.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fov_perspective = fov


## Advance to the next view and snap into it (a blend between, say, HOOD and TOP reads as
## the camera flying through the world, which is worse than a cut).
func cycle() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_apply_projection()
	snap()


## Step the current view's zoom (+1 = in, -1 = out). No-op outside ISO/TOP.
func zoom(steps: float) -> void:
	if not _zoom.has(mode):
		return
	_zoom[mode] = clampf(float(_zoom[mode]) * pow(ZOOM_STEP, -steps), ZOOM_MIN, ZOOM_MAX)
	# ISO is orthogonal, so its zoom IS the frustum size and lands at once; TOP moves the
	# camera and rides the normal follow smoothing.
	if mode == Mode.ISO:
		_apply_projection()


func _process(delta: float) -> void:
	_follow(1.0 - exp(-smoothing * delta))


## Jump straight to the follow position (spawn/respawn/view change).
func snap() -> void:
	_follow(1.0)


func _follow(weight: float) -> void:
	if target == null:
		return
	var tt := target.get_global_transform_interpolated()
	if mode == Mode.HOOD:
		# Rigid to the body: the whole point of this view is feeling the pitch and roll.
		# Per-vehicle "HoodCam" marker wins over the one-size hood_offset fallback —
		# looked up per frame so switching vehicles can never serve a stale marker.
		var offset := hood_offset
		var marker := target.get_node_or_null(^"HoodCam") as Node3D
		if marker != null:
			offset = marker.position
		global_transform = Transform3D(tt.basis, tt * offset)
		_has_free = false
		return
	var f := _framing()
	var pivot := tt.origin + Vector3.UP * float(f.get("look_height", look_height))
	var desired := _desired_position(tt, f)
	_free_position = desired if not _has_free else _free_position.lerp(desired, weight)
	_has_free = true
	global_position = _unblocked(_free_position, pivot)
	# Keeping the previous orientation for a frame beats an error and an identity basis.
	if global_position.distance_squared_to(pivot) > MIN_PIVOT_DIST * MIN_PIVOT_DIST * 0.25:
		look_at(pivot)


## Pull [param pos] in along the pivot→camera line if terrain/geometry blocks it.
func _unblocked(pos: Vector3, pivot: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(pivot, pos, collision_mask)
	# Exclude the whole vehicle (the train hands back its loco + every wagon), so the pull-in
	# never treats the vehicle's own trailing bodies as occluders.
	if target.has_method("get_camera_exclude_bodies"):
		query.exclude = target.get_camera_exclude_bodies()
	elif target is PhysicsBody3D:
		query.exclude = [(target as PhysicsBody3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return pos
	var to_cam := pos - pivot
	if to_cam.length_squared() < MIN_PIVOT_DIST * MIN_PIVOT_DIST:
		return pos
	var dist: float = maxf(
			(hit.position as Vector3).distance_to(pivot) - collision_margin, MIN_PIVOT_DIST)
	return pivot + to_cam.normalized() * minf(dist, to_cam.length())


## Per-vehicle framing override (distance/height/look_height/top_height/iso_size); empty for
## every wheeled vehicle, enlarged by the train so the views clear the whole consist.
func _framing() -> Dictionary:
	if target != _framing_target:
		_framing_target = target
		_framing_cache = target.get_camera_framing() if target != null \
				and target.has_method("get_camera_framing") else {}
		# ISO ortho `size` is only set in _apply_projection (not read per frame like the
		# perspective distances), so a garage swap while in ISO would keep the previous
		# vehicle's size until the next camera cycle — re-apply it now for the new target.
		if mode == Mode.ISO:
			_apply_projection()
	return _framing_cache


func _desired_position(tt: Transform3D, f: Dictionary) -> Vector3:
	match mode:
		Mode.ISO:
			# Fixed world angle — deliberately does NOT follow yaw, so the level's roads
			# and grid stay readable while the vehicle turns under it.
			return tt.origin + iso_offset
		Mode.TOP:
			return tt.origin \
					+ Vector3.UP * float(f.get("top_height", top_height)) * float(_zoom[Mode.TOP]) \
					+ _back(tt) * top_back
		_:
			return tt.origin + _back(tt) * float(f.get("distance", distance)) \
					+ Vector3.UP * float(f.get("height", height))


## The target's flattened backwards direction (yaw only).
func _back(tt: Transform3D) -> Vector3:
	var back := tt.basis.z
	back.y = 0.0
	return back.normalized() if back.length_squared() > 0.001 else Vector3.BACK


func _apply_projection() -> void:
	if mode == Mode.ISO:
		projection = Camera3D.PROJECTION_ORTHOGONAL
		size = float(_framing().get("iso_size", iso_size)) * float(_zoom[Mode.ISO])
	else:
		projection = Camera3D.PROJECTION_PERSPECTIVE
		fov = _fov_perspective
