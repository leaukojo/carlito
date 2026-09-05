extends Node
## One-shot generator for the Watercraft Pack boat variants: writes
## src/vehicles/watercraft/<variant>.tscn + <variant>_spec.tres. Deterministic and
## destructive-by-run, the regen path after a scale/feel change. Model origin sits at the
## resting waterline. Game-mode tool scene, not --script: boat.gd needs the InputRouter/
## Bridge autoloads to compile.

const OUT_DIR := "res://src/vehicles/watercraft"
const MODELS := "res://kit/raw/watercraft"   ## raw glbs; the packed .tscn embeds the
## meshes, so the glb is export-excluded and not needed at runtime.
const BOAT_SCRIPT := "res://src/vehicles/boat/boat.gd"
## The direct children this generator writes and may replace; everything else is hand-authored and transplanted.
const GENERATED_CHILDREN := ["CollisionShape3D", "Model", "Lamps"]

const BOAT_SCALE := 1.2  ## Kenney kit scale: speed-a lands at 2.1 m beam x 4.0 m LOA
## against the 1.8 m car. Not the recipe's prop scale of 2.0.
## GLB node names (lowercase) excluded from hull measurement and collision shape.
const EXCLUDE_COLLISION := ["sail"]

# Baseline spec (src/vehicles/boat/boat_spec.tres). Ground drive declared empty; all 6
# gear_ratios kept since auto_shift indexes up to byte 6 regardless.
const BOAT_BASE := {
	"torque_curve": [800, 120, 2500, 200, 4200, 210, 5200, 90],
	"idle_rpm": 800.0, "redline_rpm": 5200.0,
	"gear_ratios": [2.6, 1.9, 1.4, 1.05, 0.8, 0.62], "reverse_ratio": 2.0,
	"final_drive": 2.1, "efficiency": 0.9, "shift_up_rpm": 4400.0, "shift_down_rpm": 1800.0,
	"steer_speed": 2.2,
}

## Hull drag numbers include each hull's own `mass * 0.1` folded into drag_long/drag_lat; drop it and top speed gains ~20%.
##
## variant id -> overrides. draft_frac is share of hull height below the waterline. Top
## speed is roughly thrust_force / drag_long m/s (hand-built boat: 5200/380 = 13.7).
const VARIANTS := {
	# light and quick: least mass, eager rudder, modest power
	"boat-speed-a": {
		"mass": 600.0, "torque_mul": 1.0, "draft_frac": 0.22, "float_depth": 0.30,
		"thrust_force": 5200.0, "drag_long": 360.0, "drag_lat": 2060.0, "drag_yaw": 3800.0,
		"rudder_torque": 6500.0, "keel_extra": 0.15, "com_frac": 0.8,
		"steer_speed": 2.8,
	},
	# heavy and powerful: faster flat out, but slow to spin up and slow to turn
	"boat-speed-j": {
		"mass": 1400.0, "torque_mul": 1.6, "draft_frac": 0.26, "float_depth": 0.34,
		"thrust_force": 11000.0, "drag_long": 660.0, "drag_lat": 4340.0, "drag_yaw": 12000.0,
		"rudder_torque": 11000.0, "keel_extra": 0.25, "com_frac": 0.8,
		"steer_speed": 1.6,
	},
	# sailboat: the sail is decoration (no wind model); light hull, deep keel, slippery flanks.
	"boat-sail-a": {
		"mass": 500.0, "torque_mul": 0.55, "draft_frac": 0.20, "float_depth": 0.28,
		"thrust_force": 2200.0, "drag_long": 380.0, "drag_lat": 1250.0, "drag_yaw": 3200.0,
		"rudder_torque": 4200.0, "keel_extra": 0.60, "com_frac": 0.3,
		"steer_speed": 2.0,
	},
}

var _shape_report: Array = []  ## per-variant collision shape kind + hull vertex count


func _ready() -> void:
	var boat_script := load(BOAT_SCRIPT)
	var ok := 0
	for variant: String in VARIANTS:
		var ov: Dictionary = VARIANTS[variant]
		var geo := _analyze(MODELS.path_join(variant + ".glb"), float(ov["draft_frac"]))
		if geo.is_empty():
			continue
		var spec := _build_spec(ov, geo)
		var spec_path := OUT_DIR.path_join(variant + "_spec.tres")
		if ResourceSaver.save(spec, spec_path) != OK:
			push_error("failed to save " + spec_path)
			continue
		var scene := _build_scene(variant, boat_script, load(spec_path), ov, geo)
		var scene_path := OUT_DIR.path_join(variant + ".tscn")
		if _save_scene_stable(scene, scene_path) != OK:
			push_error("failed to save " + scene_path)
			continue
		ok += 1
	print("gen_boat_variants: wrote %d/%d variants" % [ok, VARIANTS.size()])
	print("collision shapes: ", ", ".join(_shape_report))
	get_tree().quit(0 if ok == VARIANTS.size() else 1)


# --- spec ------------------------------------------------------------------------------

func _build_spec(ov: Dictionary, geo: Dictionary) -> VehicleSpec:
	var spec := VehicleSpec.new()
	spec.mass = float(ov["mass"])
	# COM below the waterline (origin), as a share of the draft: the boats' righting moment.
	spec.center_of_mass = Vector3(0, -float(geo["draft"]) * float(ov["com_frac"]), 0)
	# No ground drive: the gear byte it still publishes is scaled by Drivetrain.DEFAULT_ROAD_RADIUS.
	spec.torque_curve = _scaled_curve(BOAT_BASE["torque_curve"], float(ov["torque_mul"]))
	spec.idle_rpm = float(BOAT_BASE["idle_rpm"])
	spec.redline_rpm = float(BOAT_BASE["redline_rpm"])
	spec.gear_ratios = PackedFloat32Array(BOAT_BASE["gear_ratios"])
	spec.reverse_ratio = float(BOAT_BASE["reverse_ratio"])
	spec.final_drive = float(BOAT_BASE["final_drive"])
	spec.efficiency = float(BOAT_BASE["efficiency"])
	spec.shift_up_rpm = float(BOAT_BASE["shift_up_rpm"])
	spec.shift_down_rpm = float(BOAT_BASE["shift_down_rpm"])
	# No max_steer_deg; `rudder_torque` turns the hull, `steer_speed` slews the rudder axis.
	spec.steer_speed = float(ov.get("steer_speed", BOAT_BASE["steer_speed"]))
	spec.headlight_paths.assign([NodePath("Lamps/Headlight")])
	return spec


func _scaled_curve(flat: Array, mul: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	@warning_ignore("integer_division")
	for i in flat.size() / 2:
		out.append(Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]) * mul))
	return out


# --- scene -----------------------------------------------------------------------------

func _build_scene(variant: String, scene_script: Variant, spec: VehicleSpec,
		ov: Dictionary, geo: Dictionary) -> PackedScene:
	var hull: AABB = geo["hull"]      # hull-only box, body space, origin at the waterline
	var loa := hull.size.z
	var beam := hull.size.x
	var draft := float(geo["draft"])
	var float_depth := float(ov["float_depth"])

	var root := RigidBody3D.new()
	root.name = variant.to_pascal_case()
	root.set_script(scene_script)
	root.set("spec", spec)

	# Buoyancy: four probes at the hull quarters, float_depth below the waterline.
	root.set("probe_points", PackedVector3Array([
		Vector3(-beam * 0.42, -float_depth, -loa * 0.40),
		Vector3(beam * 0.42, -float_depth, -loa * 0.40),
		Vector3(-beam * 0.42, -float_depth, loa * 0.40),
		Vector3(beam * 0.42, -float_depth, loa * 0.40),
	]))
	root.set("float_depth", float_depth)
	# Outdrive at the stern (+Z after the 180 deg flip), below the waterline.
	root.set("prop_offset", Vector3(0, -draft * 0.6, loa * 0.45))
	root.set("thrust_force", float(ov["thrust_force"]))
	root.set("rudder_torque", float(ov["rudder_torque"]))
	root.set("drag_long", float(ov["drag_long"]))
	root.set("drag_lat", float(ov["drag_lat"]))
	root.set("drag_yaw", float(ov["drag_yaw"]))
	root.set("keel_offset", -(draft + float(ov["keel_extra"])))

	var col := _body_shape(variant, geo)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = col["shape"]
	cs.position = col["pos"]
	_add(root, root, cs)

	# Body model: GLB children stolen into a Model node (180 deg Y flip, kit scale, centring, waterline drop).
	var glb := (load(MODELS.path_join(variant + ".glb")) as PackedScene).instantiate()
	var model := Node3D.new()
	model.name = "Model"
	model.transform = geo["xform"]
	_add(root, root, model)
	for child in glb.get_children():
		glb.remove_child(child)
		child.owner = null  # drop the glb's ownership before re-parenting (quiets a warning)
		model.add_child(child)
		_own(child, root)
	glb.free()

	var lamps := Node3D.new()
	lamps.name = "Lamps"
	_add(root, root, lamps)
	var spot := SpotLight3D.new()
	spot.name = "Headlight"
	spot.position = Vector3(0, hull.size.y * 0.15, -loa * 0.45)
	spot.visible = false
	spot.light_energy = 0.0
	spot.spot_range = 28.0
	spot.spot_angle = 38.0
	_add(root, lamps, spot)

	# Hand-authored children (e.g. "HoodCam"), transplanted last to match editor child order.
	for extra: Node in _existing_extras(variant):
		_add(root, root, extra)

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Everything in the existing scene not in GENERATED_CHILDREN. Reparented, not duplicated, so an instanced child re-serialises as a one-line instance.
func _existing_extras(variant: String) -> Array:
	var extras: Array = []
	var path := OUT_DIR.path_join(variant + ".tscn")
	if not ResourceLoader.exists(path):
		return extras
	var scene := load(path) as PackedScene
	if scene == null:
		return extras
	var inst := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	for child in inst.get_children():
		if not (String(child.name) in GENERATED_CHILDREN):
			extras.append(child)
	for extra: Node in extras:
		inst.remove_child(extra)
	inst.free()
	return extras


## Set owner recursively so pack() serialises the stolen GLB subtree into the vehicle scene.
func _own(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for c in node.get_children():
		_own(c, scene_owner)


## Convex hull of the HULL meshes (rigging excluded); box fallback if degenerate.
func _body_shape(variant: String, geo: Dictionary) -> Dictionary:
	var xform: Transform3D = geo["xform"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for pair: Array in geo["hull_pairs"]:
		var full := xform * (pair[1] as Transform3D)
		for v in (pair[0] as Mesh).get_faces():
			st.add_vertex(full * v)
			n += 1
	if n >= 12:
		var shape := (st.commit() as ArrayMesh).create_convex_shape(true, true)
		if shape != null and shape.points.size() >= 4:
			_shape_report.append("%s=hull(%d)" % [variant, shape.points.size()])
			return {"shape": shape, "pos": Vector3.ZERO}
	push_warning("%s: convex hull degenerate, falling back to box" % variant)
	var hull: AABB = geo["hull"]
	var box := BoxShape3D.new()
	box.size = hull.size
	_shape_report.append("%s=box" % variant)
	return {"shape": box, "pos": hull.get_center()}


func _add(scene_owner: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner


# --- geometry --------------------------------------------------------------------------

## Analyse a Watercraft GLB into geometry the spec/scene builders share:
##   xform:      body-model transform — 180 deg Y flip (pack +Z bow -> project -Z) + kit
##               scale + x/z centring on the hull, dropped so y = 0 is the waterline
##   hull:       hull-only AABB after xform (probe/prop/lamp placement, box fallback)
##   hull_pairs: [Mesh, native transform] for the hull meshes (collision hull source)
##   draft:      metres of hull below the waterline
func _analyze(path: String, draft_frac: float) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("cannot load " + path)
		return {}
	var inst := scene.instantiate()
	var hull_pairs: Array = []
	_collect_hull(inst, Transform3D.IDENTITY, hull_pairs)
	inst.free()
	if hull_pairs.is_empty():
		push_error(path + ": no hull meshes")
		return {}

	var native := AABB()
	var first := true
	for pair: Array in hull_pairs:
		for v in (pair[0] as Mesh).get_faces():
			var p: Vector3 = (pair[1] as Transform3D) * v
			if first:
				native = AABB(p, Vector3.ZERO)
				first = false
			else:
				native = native.expand(p)

	var c := native.get_center()
	var draft := draft_frac * native.size.y * BOAT_SCALE
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * BOAT_SCALE)
	# native y = 0 is the hull bottom; drop the model by the draft so y = 0 is the waterline.
	var xform := Transform3D(basis, Vector3(
			BOAT_SCALE * c.x, -BOAT_SCALE * native.position.y - draft, BOAT_SCALE * c.z))
	return {"xform": xform, "hull_pairs": hull_pairs, "draft": draft,
			"hull": _xform_aabb(native, xform)}


## Collect hull mesh pairs; EXCLUDE_COLLISION subtrees are skipped.
func _collect_hull(node: Node, xform: Transform3D, hull_pairs: Array) -> void:
	if String(node.name).to_lower() in EXCLUDE_COLLISION:
		return
	var nx := xform
	if node is Node3D:
		nx = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		hull_pairs.append([(node as MeshInstance3D).mesh, nx])
	for child in node.get_children():
		_collect_hull(child, nx, hull_pairs)


## AABB of `aabb` after `xform` (8 corners; xform is rotation+uniform-scale+translation).
func _xform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var out := AABB(xform * aabb.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xform * (aabb.position + Vector3(
				aabb.size.x if (i & 1) else 0.0,
				aabb.size.y if (i & 2) else 0.0,
				aabb.size.z if (i & 4) else 0.0)))
	return out


# --- stable save (strip churny per-node unique_id, like gen_kenney_vehicles) -----------

var _unique_id_re := RegEx.create_from_string(" unique_id=\\d+")


func _save_scene_stable(packed: PackedScene, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(packed, path)
	if err != OK or before.is_empty():
		return err
	var after := FileAccess.get_file_as_string(path)
	if after != before and _unique_id_re.sub(after, "", true) == _unique_id_re.sub(before, "", true):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(before)
	return OK
