extends Node
## Stamp the "Asphalt" splat channel (channel 6 = splatmap2.B) into a level's terrain
## along its RoadPath corridors, so splat-paint friction (HeightmapTerrain.grip_at) can
## tell road from offroad. Roads themselves are welded geometry with no paint of their own;
## this paints the ground underneath their paved half-width so the XZ grip lookup reads
## asphalt on-road and the terrain's own channels off-road.
##
## Runs as a GAME-MODE tool scene, not --script (level scenes pull in scripts that only
## compile with autoloads registered — the bake_levels rationale). Run after --import:
##   godot --headless --path . res://tools/paint_road_asphalt.tscn -- src/levels/island/level_1/level_1.tscn
## then re-import so the edited PNGs are picked up:
##   godot --headless --path . --import
##
## Additive by design: it only writes pixels inside the CURRENT corridors (base channels
## zeroed there, asphalt set to 1). Re-run after editing roads leaves stale asphalt where a
## road used to be — re-run Auto-splat on the terrain first if you need a clean base.

const CENTERLINE_STEP := 0.5   ## m between centerline samples (short segments = smooth stamp)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level_path := "res://src/levels/island/level_1/level_1.tscn"
	if not args.is_empty():
		level_path = "res://" + String(args[0]).trim_prefix("res://")

	var packed := load(level_path) as PackedScene
	if packed == null:
		printerr("[paint-asphalt] cannot load %s" % level_path)
		get_tree().quit(1)
		return
	var root := packed.instantiate()

	var roads: Array = []
	var terrains: Array = []
	_collect(root, Transform3D.IDENTITY, roads, terrains)
	if roads.is_empty():
		printerr("[paint-asphalt] no RoadPaths in %s" % level_path)
		root.free()
		get_tree().quit(1)
		return
	if terrains.is_empty():
		printerr("[paint-asphalt] no HeightmapTerrain in %s" % level_path)
		root.free()
		get_tree().quit(1)
		return

	var code := 0
	for t in terrains:
		if not _paint_terrain(t, roads):
			code = 1
	root.free()
	get_tree().quit(code)


## Recursive gather carrying the world transform (the instance is untreed, so
## global_transform is off-limits — accumulate like the baker does).
func _collect(node: Node, xform: Transform3D, roads: Array, terrains: Array) -> void:
	for child in node.get_children():
		var cx := xform
		if child is Node3D:
			cx = xform * (child as Node3D).transform
		if child.has_method("is_carlito_road"):
			roads.append({"node": child, "xform": cx})
		elif child.has_method("grip_at") and child.has_method("contains_xz"):
			terrains.append({"node": child, "xform": cx})
		else:
			_collect(child, cx, roads, terrains)


func _paint_terrain(t: Dictionary, roads: Array) -> bool:
	var terrain: Node = t["node"]
	var txform: Transform3D = t["xform"]
	var splat_tex: Texture2D = terrain.get("splatmap")
	if splat_tex == null:
		printerr("[paint-asphalt] terrain '%s' has no splatmap" % terrain.name)
		return false
	var splat := splat_tex.get_image()
	if splat.is_compressed():
		splat.decompress()
	splat.convert(Image.FORMAT_RGBA8)
	var iw := splat.get_width()
	var ih := splat.get_height()

	var splat2_tex: Texture2D = terrain.get("splatmap2")
	var splat2: Image
	var splat2_path := ""
	if splat2_tex != null:
		splat2 = splat2_tex.get_image()
		if splat2.is_compressed():
			splat2.decompress()
		splat2.convert(Image.FORMAT_RGBA8)
		splat2_path = splat2_tex.resource_path
	else:
		splat2 = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
		splat2.fill(Color(0, 0, 0, 0))
		splat2_path = splat_tex.resource_path.get_basename().trim_suffix("_splat") + "_splat2.png"

	var size: Vector2 = terrain.get("terrain_size")
	var span_x := size.x
	var span_z := size.y
	var tx := txform.origin.x
	var tz := txform.origin.z
	# pixels per meter (assume the usual square terrain; used only for the bbox margin)
	var px_per_m := float(iw - 1) / span_x

	var painted := 0
	for r in roads:
		var road: Node = r["node"]
		var profile: Resource = road.get("profile")
		if profile == null:
			continue
		var path := road.get_node_or_null(^"Path") as Path3D
		if path == null or path.curve == null or path.curve.point_count < 2:
			continue
		var hw: float = profile.call("paved_half_width")
		if hw <= 0.0:
			continue
		var to_world: Transform3D = r["xform"] * path.transform
		var pts := _centerline_world_xz(path.curve, to_world)
		var margin := int(ceil(hw * px_per_m)) + 1
		for i in range(pts.size() - 1):
			painted += _stamp_segment(splat, splat2, pts[i], pts[i + 1], hw, margin,
					iw, ih, span_x, span_z, tx, tz)

	if painted == 0:
		print("[paint-asphalt] '%s': no corridor pixels overlapped — nothing painted." % terrain.name)
		return true

	var err := splat.save_png(splat_tex.resource_path)
	err = err | splat2.save_png(splat2_path)
	if err != OK:
		printerr("[paint-asphalt] PNG write failed for '%s'" % terrain.name)
		return false
	TerrainGen.ensure_import_settings(splat_tex.resource_path)
	TerrainGen.ensure_import_settings(splat2_path)
	print("[paint-asphalt] '%s': painted %d asphalt pixels -> %s + %s" % [
			terrain.name, painted, splat_tex.resource_path.get_file(), splat2_path.get_file()])
	return true


## Dense world-XZ polyline of the curve centerline (Path child transform composed in).
func _centerline_world_xz(curve: Curve3D, to_world: Transform3D) -> Array:
	var length := curve.get_baked_length()
	var pts: Array = []
	var d := 0.0
	while d < length:
		var w := to_world * curve.sample_baked(d)
		pts.append(Vector2(w.x, w.z))
		d += CENTERLINE_STEP
	var wend := to_world * curve.sample_baked(length)
	pts.append(Vector2(wend.x, wend.z))
	return pts


## Set every splat pixel within `hw` of segment a->b to pure asphalt (base zeroed,
## splatmap2.B = 1). Returns the number of pixels written.
func _stamp_segment(splat: Image, splat2: Image, a: Vector2, b: Vector2, hw: float,
		margin: int, iw: int, ih: int, span_x: float, span_z: float,
		tx: float, tz: float) -> int:
	var pa := _world_to_px(a, iw, ih, span_x, span_z, tx, tz)
	var pb := _world_to_px(b, iw, ih, span_x, span_z, tx, tz)
	var minx := clampi(mini(pa.x, pb.x) - margin, 0, iw - 1)
	var maxx := clampi(maxi(pa.x, pb.x) + margin, 0, iw - 1)
	var miny := clampi(mini(pa.y, pb.y) - margin, 0, ih - 1)
	var maxy := clampi(maxi(pa.y, pb.y) + margin, 0, ih - 1)
	var count := 0
	for py in range(miny, maxy + 1):
		for px in range(minx, maxx + 1):
			var w := _px_to_world(px, py, iw, ih, span_x, span_z, tx, tz)
			if _dist_to_seg(w, a, b) <= hw:
				splat.set_pixel(px, py, Color(0, 0, 0, 0))
				splat2.set_pixel(px, py, Color(0, 0, 1, 0))
				count += 1
	return count


func _world_to_px(w: Vector2, iw: int, ih: int, span_x: float, span_z: float,
		tx: float, tz: float) -> Vector2i:
	var u := (w.x - tx + span_x * 0.5) / span_x
	var v := (w.y - tz + span_z * 0.5) / span_z
	return Vector2i(int(round(u * (iw - 1))), int(round(v * (ih - 1))))


func _px_to_world(px: int, py: int, iw: int, ih: int, span_x: float, span_z: float,
		tx: float, tz: float) -> Vector2:
	var u := float(px) / float(iw - 1)
	var v := float(py) / float(ih - 1)
	return Vector2(tx - span_x * 0.5 + u * span_x, tz - span_z * 0.5 + v * span_z)


## Distance from p to segment a->b (2D).
static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var d := ab.length_squared()
	var t := 0.0
	if d > 1e-9:
		t = clampf((p - a).dot(ab) / d, 0.0, 1.0)
	return p.distance_to(a + ab * t)
