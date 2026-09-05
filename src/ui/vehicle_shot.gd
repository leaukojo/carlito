class_name VehicleShot
extends RefCounted
## Frames every picture of a vehicle: the selector card thumbnail (tools/gen_vehicle_thumbs.gd)
## and the live turntable beside it (vehicle_select.gd), so the two cannot drift apart.
## Camera distance comes from the instantiated body's measured AABB, never a typed number.
## Runtime-safe (no editor APIs) and lives under src/ because tools/* and kit/thumbs/* are
## export-excluded and the selector needs the PNGs at runtime.

const SceneBounds := preload("res://src/ui/scene_bounds.gd")

const THUMB_DIR := CardImport.VEHICLE_THUMB_DIR

## 8:5, captured at 2x the widest card so it stays crisp scaled up.
const CARD_ASPECT := 0.625
const CAPTURE_SIZE := Vector2i(384, 240)

const FOV := 32.0
## Fixed 3/4 view. Yaw is measured from dead ahead and a Godot body faces -Z, so yaw 0 puts the
## camera in front of the vehicle; shooting from behind gives a card of a boot lid.
const VIEW_PITCH_DEG := 22.0
const VIEW_YAW_DEG := 35.0
## Slack on the bounding sphere. Vehicles are long boxes, so a tight fit still leaves margin.
const FIT_MARGIN := 1.02

const BACKDROP := Color(0.09, 0.10, 0.13)  ## sits between UiTheme.BG and SURFACE


## Thumbnail for a variant id ("sedan-sports") or an attachment id (see id_for_scene).
static func thumb_path(id: String) -> String:
	return "%s/%s.png" % [THUMB_DIR, id]


## Attachments are named by scene path in their catalog, not by id:
## ".../trailers/tipper.tscn" -> "tipper". The empty entry (DETACHED / BOBTAIL) returns "".
static func id_for_scene(scene_path: String) -> String:
	return scene_path.get_file().get_basename() if not scene_path.is_empty() else ""


## Dress `vp` as a neutral showroom and return its camera. Isolated world, flat backdrop, key
## light plus fill. frame() positions the camera per subject.
static func build_stage(vp: SubViewport) -> Camera3D:
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.90)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -55.0, 0.0)
	key.light_energy = 1.4
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 130.0, 0.0)
	fill.light_energy = 0.45
	vp.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = FOV
	vp.add_child(cam)
	cam.current = true
	return cam


## Instantiate a vehicle/attachment scene for display. Set before the body enters the tree,
## because _ready acts on it: `display_only` keeps it out of InputRouter (whose vehicle slot is a
## plain assignment, so a preview would displace the driven body), and frozen KINEMATIC with no
## gravity keeps _physics_process running so RayWheels pose the wheel visuals — without a tick all
## four sit stacked at the origin. Returns null if the scene will not load.
static func spawn_display(scene_path: String) -> Node3D:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	var body := inst as RigidBody3D
	if body != null:
		if "display_only" in body:
			body.display_only = true
		body.gravity_scale = 0.0
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	return inst


## Run after add_child: a vehicle that owns other bodies pins them too. Duck-typed, so nothing
## here learns what a trailer is.
static func pin_display(inst: Node3D) -> void:
	if inst.has_method("set_display_frozen"):
		inst.set_display_frozen(true)


## Point `cam` at the subject from the 3/4 view, turned `yaw_deg`, far enough back that the
## bounding sphere fits. The turntable moves yaw: the camera orbits, never the body — rotating a
## frozen RigidBody3D fights the physics server for the transform it is already writing.
static func frame(cam: Camera3D, bounds: AABB, yaw_deg: float) -> void:
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.01)
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * FIT_MARGIN
	var dir := Basis(Vector3.UP, deg_to_rad(yaw_deg)) \
			* Vector3(0.0, sin(deg_to_rad(VIEW_PITCH_DEG)), -cos(deg_to_rad(VIEW_PITCH_DEG)))
	cam.global_position = center + dir.normalized() * dist
	cam.look_at(center, Vector3.UP)
	cam.near = maxf(0.05, dist - radius * 2.0)
	cam.far = dist + radius * 2.0 + 1.0


## The body plus any body it coupled to itself. A trailer is a child of the vehicle's PARENT, never
## of the vehicle (a dynamic body under another body gets the parent transform applied on top of
## the physics server's), so framing the vehicle subtree alone would crop nine metres off a semi.
## Rigid bodies only: the stage lights are VisualInstance3Ds and would drag the frame to origin.
static func subject_roots(inst: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = [inst]
	var host := inst.get_parent()
	if host == null:
		return out
	for child in host.get_children():
		if child != inst and child is RigidBody3D:
			out.append(child as Node3D)
	return out


## Bounds of the whole subject, ready for frame().
static func subject_bounds(inst: Node3D) -> AABB:
	return world_aabb(subject_roots(inst))


## Measured off the instantiated body (wheels included, RayWheel has posed them), never a spec.
static func world_aabb(roots: Array[Node3D]) -> AABB:
	return SceneBounds.world_aabb(roots)


static func visuals(node: Node) -> Array[VisualInstance3D]:
	return SceneBounds.visuals(node)
