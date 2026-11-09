## Scene assembly shared by the body generators (`gen_kenney_vehicles.gd`, `gen_boat_variants.gd`),
## the sibling of `level_gen_io.gd`: the spec and scene save, the hand-authored children kept
## across a regen, the stolen GLB model, the generated convex hull and the headlight.

const StableSave := preload("res://tools/stable_save.gd")


## Saves `spec` as `<variant>_spec.tres`, builds the scene off the saved spec
## (`build_scene.call(spec)`) and saves it as `<variant>.tscn`; false (and a pushed error) when a
## save fails.
static func write_variant(out_dir: String, variant: String, spec: VehicleSpec,
		build_scene: Callable) -> bool:
	var spec_path := out_dir.path_join(variant + "_spec.tres")
	if StableSave.save(spec, spec_path) != OK:
		push_error("failed to save " + spec_path)
		return false
	var scene: PackedScene = build_scene.call(load(spec_path))
	var scene_path := out_dir.path_join(variant + ".tscn")
	if StableSave.save(scene, scene_path) != OK:
		push_error("failed to save " + scene_path)
		return false
	return true


static func scaled_curve(flat: Array, mul: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	@warning_ignore("integer_division")
	for i in flat.size() / 2:
		out.append(Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]) * mul))
	return out


static func add(scene_owner: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner


## Set owner recursively so pack() serialises the stolen GLB subtree into the vehicle scene.
static func own(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for c in node.get_children():
		own(c, scene_owner)


## Everything in the existing scene the generator does not rebuild, kept so it survives the old
## instance being freed. A whitelist of what the generator writes (`generated` plus collision), not
## a list of what to save, so a hand-added node is preserved by default. With no scene of its own
## yet, a variant starts from `fallback_path` when one is given.
##
## Returns {collision, extras}: collision goes back in first (before Model), extras last (after
## Lamps), matching authored child order so a no-op regen stays byte-identical. Extras are
## reparented (not duplicated) out of an instance loaded with GEN_EDIT_STATE_INSTANCE — plain
## `duplicate()` loses scene-instance state, so `pack()` would write an instanced child's
## properties back out explicitly (including `script=`), pinning the vehicle scene to today's
## version of that child's script. Collision shapes are plain nodes and stay a plain duplicate.
static func existing_children(out_dir: String, variant: String, generated: Array,
		fallback_path := "") -> Dictionary:
	var kept := {"collision": [], "extras": []}
	var path := out_dir.path_join(variant + ".tscn")
	if not ResourceLoader.exists(path) and not fallback_path.is_empty():
		path = fallback_path
	if not ResourceLoader.exists(path):
		return kept
	var scene := load(path) as PackedScene
	if scene == null:
		return kept
	var inst := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	for child in inst.get_children():
		if child is CollisionShape3D:
			(kept["collision"] as Array).append(child.duplicate())
		elif not (String(child.name) in generated):
			(kept["extras"] as Array).append(child)
	for extra: Node in kept["extras"]:
		inst.remove_child(extra)
	inst.free()
	return kept


## Collision is hand-authored (CollisionLower/CollisionUpper box pairs) and transplanted verbatim
## on regen rather than overwritten; only a brand-new variant gets the generated shape
## (`make_shape.call()` -> {shape, pos}) as a starting point.
static func add_collision(root: Node, variant: String, kept_collision: Array,
		make_shape: Callable, report: Array) -> void:
	if kept_collision.is_empty():
		var col: Dictionary = make_shape.call()
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = col["shape"]
		cs.position = col["pos"]
		add(root, root, cs)
	else:
		for cs in kept_collision:
			add(root, root, cs)
		report.append("%s=kept(%d)" % [variant, kept_collision.size()])


## Instances the GLB and steals its children (bar those `skip` names) into a `Model` node under
## `xform`, owned by `root`. Returns the Model node.
static func steal_model(root: Node, glb_path: String, xform: Transform3D,
		skip := Callable()) -> Node3D:
	var glb := (load(glb_path) as PackedScene).instantiate()
	var model := Node3D.new()
	model.name = "Model"
	model.transform = xform
	add(root, root, model)
	for child in glb.get_children():
		if skip.is_valid() and skip.call(child):
			continue
		glb.remove_child(child)
		child.owner = null  # drop the glb's ownership before re-parenting (quiets a warning)
		model.add_child(child)
		own(child, root)
	glb.free()
	return model


## Convex hull (QuickHull-simplified) of `pairs` ([Mesh, native transform]) under `xform`, each
## vertex's y held at `clamp_y` or above; null when degenerate.
static func hull_shape(pairs: Array, xform: Transform3D, clamp_y := -INF) -> ConvexPolygonShape3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for pair: Array in pairs:
		var full := xform * (pair[1] as Transform3D)
		for v in (pair[0] as Mesh).get_faces():
			var p := full * v
			p.y = maxf(p.y, clamp_y)
			st.add_vertex(p)
			n += 1
	if n >= 12:
		var hull := (st.commit() as ArrayMesh).create_convex_shape(true, true)
		if hull != null and hull.points.size() >= 4:
			return hull
	return null


static func headlight(spot_name: String, pos: Vector3) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.name = spot_name
	s.position = pos
	s.visible = false
	s.light_energy = 0.0
	s.spot_range = 28.0
	s.spot_angle = 38.0
	return s
