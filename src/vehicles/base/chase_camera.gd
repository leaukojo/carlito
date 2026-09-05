class_name ChaseCamera
extends Camera3D
## Chase camera on the BaseVehicle camera-target contract. It follows in _process via
## get_global_transform_interpolated(), since reading global_transform would sample the raw 60 Hz
## physics tick and stutter.
##
## Four views, cycled by [method cycle]: CHASE (yaw-only follow, default), HOOD (rigid to the
## body), ISO (fixed 3/4 angle, orthogonal) and TOP (overhead yaw-follow). Every view but HOOD
## pulls in when geometry blocks the line back to the vehicle, and ISO and TOP zoom on the wheel.

enum Mode {CHASE, HOOD, ISO, TOP}

const Layers := preload("res://src/physics/collision_layers.gd")

const MIN_PIVOT_DIST := 0.35  ## look_at() errors if origin and target coincide

@export var target: Node3D
@export var distance := 6.0
@export var height := 2.5
@export var look_height := 1.2
@export var smoothing := 5.0  ## 1/s exponential position catch-up rate
## SOLID, not every layer: including Containment, the map wall off the coast, as an occluder
## pulls the camera into the vehicle at the beach.
@export_flags_3d_physics var collision_mask := Layers.SOLID
@export var collision_margin := 0.3  ## keep-out distance from a hit surface
## Bonnet-cam offset in body space (-Z forward); overridden by a "HoodCam" Marker3D child.
@export var hood_offset := Vector3(0.0, 1.35, -0.55)
@export var iso_offset := Vector3(14.0, 16.0, 14.0)  ## fixed world-space 3/4 view
@export var iso_size := 26.0  ## orthogonal frustum height for ISO
@export var top_height := 30.0
@export var top_back := 6.0  ## nudge behind the vehicle so it sits low in frame

const ZOOM_STEP := 1.12
const ZOOM_MIN := 0.12
const ZOOM_MAX := 3.0

var mode := Mode.CHASE

var _zoom := {Mode.ISO: 1.0, Mode.TOP: 1.0}  ## per-view, so switching views keeps its own framing

var _fov_perspective := 75.0
var _free_position := Vector3.ZERO  ## smoothed follow pos before occlusion pull-in (avoids wall shake)
var _has_free := false
var _query := PhysicsRayQueryParameters3D.new()  ## occlusion ray, refilled each frame in `_unblocked`
var _framing_cache: Dictionary  ## cached get_camera_framing(), recomputed only on target change
var _framing_target: Node3D = null


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  ## moves per rendered frame
	_fov_perspective = fov


## Advance to the next view and snap into it (blending views reads as flying through the world).
func cycle() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_apply_projection()
	snap()


## Step the current view's zoom (+1 = in, -1 = out). No-op outside ISO/TOP.
func zoom(steps: float) -> void:
	if not _zoom.has(mode):
		return
	_zoom[mode] = clampf(float(_zoom[mode]) * pow(ZOOM_STEP, -steps), ZOOM_MIN, ZOOM_MAX)
	if mode == Mode.ISO:  ## orthogonal: zoom is the frustum size, lands at once
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
		# A "HoodCam" marker wins over hood_offset, and the whole transform is composed, so a
		# vehicle that aims its marker (the drone's gimbal) gets that aim.
		var xf := Transform3D(Basis.IDENTITY, hood_offset)
		var marker := target.get_node_or_null(^"HoodCam") as Node3D
		if marker != null:
			xf = marker.transform
		global_transform = tt * xf
		_has_free = false
		return
	var f := _framing()
	var pivot := tt.origin + Vector3.UP * float(f.get("look_height", look_height))
	var desired := _desired_position(tt, f)
	_free_position = desired if not _has_free else _free_position.lerp(desired, weight)
	_has_free = true
	global_position = _unblocked(_free_position, pivot)
	if global_position.distance_squared_to(pivot) > MIN_PIVOT_DIST * MIN_PIVOT_DIST * 0.25:
		look_at(pivot)


## Pull [param pos] in along the pivot→camera line if terrain/geometry blocks it.
func _unblocked(pos: Vector3, pivot: Vector3) -> Vector3:
	_query.from = pivot
	_query.to = pos
	_query.collision_mask = collision_mask
	# Exclude the whole vehicle (a train's loco plus every wagon) so the pull-in never treats its
	# own trailing bodies as occluders. Rebuilt per frame, since a consist can couple or uncouple.
	if target.has_method("get_camera_exclude_bodies"):
		_query.exclude = target.get_camera_exclude_bodies()
	elif target is PhysicsBody3D:
		_query.exclude = [(target as PhysicsBody3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return pos
	var to_cam := pos - pivot
	if to_cam.length_squared() < MIN_PIVOT_DIST * MIN_PIVOT_DIST:
		return pos
	var dist: float = maxf(
			(hit.position as Vector3).distance_to(pivot) - collision_margin, MIN_PIVOT_DIST)
	return pivot + to_cam.normalized() * minf(dist, to_cam.length())


## Per-vehicle framing override; empty for wheeled vehicles, enlarged by the train.
func _framing() -> Dictionary:
	if target != _framing_target:
		_framing_target = target
		_framing_cache = target.get_camera_framing() if target != null \
				and target.has_method("get_camera_framing") else {}
		# Re-apply now, or a garage swap while in ISO keeps the previous vehicle's size.
		if mode == Mode.ISO:
			_apply_projection()
	return _framing_cache


func _desired_position(tt: Transform3D, f: Dictionary) -> Vector3:
	match mode:
		Mode.ISO:
			return tt.origin + iso_offset  ## fixed world angle, ignores yaw
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
