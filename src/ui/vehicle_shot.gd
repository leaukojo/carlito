class_name VehicleShot
extends RefCounted
## Every picture of a vehicle in this project is framed here: the thumbnail on a selector card
## (written by tools/gen_vehicle_thumbs.gd) and the live turntable beside it
## (src/ui/vehicle_select.gd). One file so the card and the preview cannot drift into two
## different framings of the same machine — the same job LevelShot does for levels.
##
## Nothing here is guessed. The camera distance comes from the instantiated body's own measured
## AABB, so a 1.8 m car and a 15 m artic each land in the frame at their own size rather than at
## a number somebody typed. Runtime-safe (no editor APIs): the shipped selector loads this, which
## is also why it lives under src/ and writes its PNGs there — tools/* and kit/thumbs/* are
## export-excluded and the selector needs the pictures at runtime.

## Where the card PNGs live. Under src/ for the export reason above.
const THUMB_DIR := "res://src/ui/vehicle_thumbs"

## Card aspect and capture size — 8:5, at 2x the widest card so it stays crisp when scaled up.
const CARD_ASPECT := 0.625
const CAPTURE_SIZE := Vector2i(384, 240)

const FOV := 32.0
## Fixed 3/4 view: high enough to read the roof and the layout, low enough to keep the silhouette.
## The yaw is the turntable's starting angle and the one every still is shot from, measured from
## dead ahead — a Godot body faces -Z, so yaw 0 is the camera in FRONT of it. Shot from behind, a
## car card is a boot lid and a semi card is a pair of trailer doors.
const VIEW_PITCH_DEG := 22.0
const VIEW_YAW_DEG := 35.0
## Slack around the subject's bounding sphere. Vehicles are long boxes, so their sphere is mostly
## air at the ends and a tight fit still leaves visible margin.
const FIT_MARGIN := 1.02

const BACKDROP := Color(0.09, 0.10, 0.13)  ## sits between UiTheme.BG and SURFACE


## Thumbnail for a variant id ("sedan-sports") or an attachment id (see id_for_scene).
static func thumb_path(id: String) -> String:
	return "%s/%s.png" % [THUMB_DIR, id]


## Thumbnail id for an attachment, which is named by SCENE PATH in its catalog rather than by an
## id — ".../trailers/tipper.tscn" -> "tipper". The catalogs' empty entry (DETACHED / BOBTAIL) has
## no picture of its own and returns "".
static func id_for_scene(scene_path: String) -> String:
	return scene_path.get_file().get_basename() if not scene_path.is_empty() else ""


## Dress `vp` as a neutral showroom and return its camera. Isolated world (own_world_3d), a flat
## backdrop, a key light and a fill so the far side of the body is not a silhouette. The camera is
## positioned per subject by frame().
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


## Instantiate a vehicle/attachment scene for DISPLAY. Everything that has to be true before the
## body enters the tree is set here, because _ready is what acts on it:
##
## - `display_only` keeps it out of InputRouter, whose vehicle slot is a plain assignment — a
##   preview body would otherwise take the driven body's place and null it again on free.
## - frozen KINEMATIC with no gravity, the garage showroom's pose: _physics_process still runs, so
##   the RayWheels pose the wheel visuals (without a tick all four sit stacked at the origin), the
##   body just never moves and never falls.
##
## Returns null for a scene that will not load, so callers can report which one.
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


## Second half of spawn_display, run AFTER add_child: a vehicle that owns other bodies is asked to
## pin them too. Duck-typed exactly as garage.gd does it, so nothing here learns what a trailer is
## — and the semi's flag also exempts a display rig from deciding its own trailer does not fit.
static func pin_display(inst: Node3D) -> void:
	if inst.has_method("set_display_frozen"):
		inst.set_display_frozen(true)


## Point `cam` at the subject from the fixed 3/4 view, turned `yaw_deg` about it, far enough back
## that its bounding sphere fits the frustum. The turntable is this call with a moving yaw — the
## CAMERA orbits, never the body: rotating a frozen RigidBody3D (or its parent) fights the physics
## server for the transform it is already writing.
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


## What the shot is OF: the body, plus any body it coupled to itself. The semi's trailer is a child
## of the vehicle's PARENT and never of the vehicle (a dynamic RigidBody3D under another body gets
## the parent transform applied on top of the one the physics server writes), so framing the
## vehicle subtree alone would crop nine metres of the machine you picked. Rigid bodies only — the
## stage's own lights are VisualInstance3Ds too, and their AABBs would drag the frame to the origin.
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


## World-space bounds of everything visible under each root — MEASURED off the instantiated body
## (wheels included, since RayWheel has posed them by the time this is asked), never a spec number.
static func world_aabb(roots: Array[Node3D]) -> AABB:
	var out := AABB()
	var first := true
	for root in roots:
		if root == null or not is_instance_valid(root):
			continue
		for vi in visuals(root):
			var local := vi.get_aabb()
			var g := vi.global_transform
			for i in 8:
				var corner := local.position + Vector3(
						local.size.x if (i & 1) else 0.0,
						local.size.y if (i & 2) else 0.0,
						local.size.z if (i & 4) else 0.0)
				var w := g * corner
				if first:
					out = AABB(w, Vector3.ZERO)
					first = false
				else:
					out = out.expand(w)
	return out


static func visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(visuals(child))
	return found
