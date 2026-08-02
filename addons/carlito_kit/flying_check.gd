@tool
extends RefCounted
## "Find flying props" (palette toolbar): scans every placed kit piece under AuthoringRoot
## and flags the ones whose lowest point hovers above the ground — pieces placed without
## checking their height, or left behind when the terrain under them moved.
##
## The markers are plain Node3Ds added to the edited scene UNOWNED (the placement-ghost
## trick), so they are never serialized into the .tscn and never reach the bake input hash;
## they also vanish on scene reload. Clear removes them; Drop is the one-action fix.
##
## Support height under a piece is the ground-snap fallback chain: a downward physics ray
## from just under the piece (its own collider sits above that, so no exclusion bookkeeping
## is needed — and a prop standing on a road deck or a tile reads the deck, not the terrain
## beneath it), then each HeightmapTerrain's height sample. A piece over neither is reported
## as "no ground" rather than guessed at. Editor-only (addons/), so editor API is fine here.

## Parent node holding all markers. Named so a stale one is obvious, and skipped by scans.
const MARKER_ROOT := "__KitFlyingMarkers"

## Default hover (m) a piece may have before it counts as flying. Kit prefab origins are not
## all exactly at the mesh bottom, so a small tolerance keeps honest placements quiet.
const DEFAULT_TOLERANCE := 0.3

## How far below a piece the support ray looks. Past this the piece is "no ground".
const RAY_DOWN := 500.0

const MARKER_COLOR := Color(1.0, 0.25, 0.15)

## Marker sizing (m): a post spanning ground -> piece bottom, plus a beacon column above it
## so a prop hovering 20 cm is still findable from across the level.
const POST_THICKNESS := 0.6
const BEACON_HEIGHT := 25.0
const BEACON_THICKNESS := 0.3

## The markers pulse so they read against a busy level. Driven by the shader's TIME (the
## editor viewport animates it) — NOT by a per-frame tool tick, which the kit's authoring
## tools never use.
const BLINK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint;
uniform float hz;
void fragment() {
	float pulse = step(0.5, fract(TIME * hz));
	ALBEDO = mix(tint * 0.2, vec3(1.0), pulse);
}
"""
const BLINK_HZ := 1.5


## Every flying piece under the scene's AuthoringRoot, as
## [{piece: Node3D, gap: float, bottom: float, ground: float}], plus the pieces with no
## ground under them at all in `unsupported`. Returns {flying: Array, unsupported: Array}.
static func scan(scene_root: Node, tolerance := DEFAULT_TOLERANCE) -> Dictionary:
	var flying: Array = []
	var unsupported: Array = []
	if scene_root == null:
		push_warning("Kit: no scene open to check.")
		return {"flying": flying, "unsupported": unsupported}
	var authoring := _find_authoring(scene_root)
	if authoring == null:
		push_warning("Kit: no AuthoringRoot in the scene to check.")
		return {"flying": flying, "unsupported": unsupported}

	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(scene_root, terrains)
	var space: PhysicsDirectSpaceState3D = null
	if scene_root is Node3D:
		space = (scene_root as Node3D).get_world_3d().direct_space_state

	for node in authoring.find_children("*", "Node3D", true, false):
		if not node.has_method("is_carlito_kit_piece"):
			continue
		var piece := node as Node3D
		var bottom := _piece_bottom(piece)
		if is_nan(bottom):
			continue  # no render mesh — nothing to measure
		var ground := _support_y(space, terrains, piece.global_position, bottom)
		if is_nan(ground):
			unsupported.append({"piece": piece, "gap": 0.0, "bottom": bottom,
					"ground": 0.0})
			continue
		var gap := bottom - ground
		if gap > tolerance:
			flying.append({"piece": piece, "gap": gap, "bottom": bottom, "ground": ground})
	flying.sort_custom(func(a, b): return a["gap"] > b["gap"])
	return {"flying": flying, "unsupported": unsupported}


## Scan and drop a red marker post on each flying piece (ground -> piece bottom), with its
## hover printed beside it. Replaces any previous markers, so re-running after a fix is the
## way to re-check. Nothing is written to the scene (markers are unowned).
static func flag(scene_root: Node, tolerance := DEFAULT_TOLERANCE) -> void:
	clear(scene_root)
	var result := scan(scene_root, tolerance)
	var flying: Array = result["flying"]
	var unsupported: Array = result["unsupported"]
	if flying.is_empty() and unsupported.is_empty():
		print("Kit: no flying props (tolerance %.2f m)." % tolerance)
		return

	var root := Node3D.new()
	root.name = MARKER_ROOT
	(scene_root as Node3D).add_child(root)  # unowned on purpose -> never serialized

	for entry in flying:
		var piece: Node3D = entry["piece"]
		var marker := _marker(entry["bottom"] - entry["ground"], "%.2f m" % entry["gap"])
		root.add_child(marker)  # global_position needs the marker in the tree
		marker.global_position = Vector3(piece.global_position.x, entry["ground"],
				piece.global_position.z)
		print("Kit: flying %+.2f m  %s" % [entry["gap"], scene_root.get_path_to(piece)])
	for entry in unsupported:
		var piece: Node3D = entry["piece"]
		print("Kit: no ground under  %s" % scene_root.get_path_to(piece))
	print("Kit: %d flying prop(s), %d with no ground under them (tolerance %.2f m). " \
			% [flying.size(), unsupported.size(), tolerance]
			+ "Markers are editor-only and are not saved with the scene.")


## Remove the markers (also happens on its own when the scene is reloaded).
static func clear(scene_root: Node) -> void:
	if scene_root == null:
		return
	for child in scene_root.get_children():
		if child.name == MARKER_ROOT:
			scene_root.remove_child(child)
			child.queue_free()


## Move every flagged piece straight down so its lowest point rests on the ground, in ONE
## undoable action, then re-flag (so what is left is what the drop could not fix). Only the
## Y of each piece changes — X/Z/rotation are the author's. Pieces with no ground under
## them are left alone.
static func drop(scene_root: Node, undo: EditorUndoRedoManager,
		tolerance := DEFAULT_TOLERANCE) -> void:
	var flying: Array = scan(scene_root, tolerance)["flying"]
	if flying.is_empty():
		print("Kit: nothing to drop (tolerance %.2f m)." % tolerance)
		return
	undo.create_action("Drop flying props to ground", UndoRedo.MERGE_DISABLE, scene_root)
	for entry in flying:
		var piece: Node3D = entry["piece"]
		var to := piece.global_position - Vector3(0.0, entry["gap"], 0.0)
		undo.add_do_property(piece, "global_position", to)
		undo.add_undo_property(piece, "global_position", piece.global_position)
	undo.commit_action()
	print("Kit: dropped %d prop(s) to the ground." % flying.size())
	flag(scene_root, tolerance)


## Lowest world-space Y of a piece's MeshInstance3D descendants; NAN when it has none.
static func _piece_bottom(piece: Node3D) -> float:
	var low := INF
	for node in piece.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var mt := mi.global_transform
		var aabb := mi.mesh.get_aabb()
		for ci in 8:
			low = minf(low, (mt * aabb.get_endpoint(ci)).y)
	return low if is_finite(low) else NAN


## Support height under `xz`, starting just below the piece so its own collider is missed:
## physics ray -> terrain sample -> NAN (no ground).
static func _support_y(space: PhysicsDirectSpaceState3D, terrains: Array[Node],
		origin: Vector3, bottom: float) -> float:
	var from := Vector3(origin.x, bottom - 0.01, origin.z)
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_DOWN)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return (hit.position as Vector3).y
	for t in terrains:
		if t.contains_xz(origin):
			return float(t.height_at(origin))
	return NAN


## One marker (positioned by the caller once it is in the tree): a fat post filling the gap
## between the ground and the piece's bottom, a tall beacon column above it so the marker is
## visible from a distance, and the hover distance in text. Both columns blink.
static func _marker(gap: float, label: String) -> Node3D:
	var holder := Node3D.new()
	var mat := _material()

	var height := maxf(gap, 0.05)
	holder.add_child(_column(Vector3(POST_THICKNESS, height, POST_THICKNESS),
			height * 0.5, mat))
	holder.add_child(_column(
			Vector3(BEACON_THICKNESS, BEACON_HEIGHT, BEACON_THICKNESS),
			height + BEACON_HEIGHT * 0.5, mat))

	var text := Label3D.new()
	text.text = label
	text.modulate = MARKER_COLOR
	text.outline_size = 16
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.fixed_size = true  # stays legible from any distance — it is a locator, not signage
	text.pixel_size = 0.0015
	text.position = Vector3(0.0, height + BEACON_HEIGHT + 2.0, 0.0)
	holder.add_child(text)
	return holder


## A blinking box column centred at `center_y` above the marker's ground point.
static func _column(size: Vector3, center_y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, center_y, 0.0)
	return mi


static func _material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = BLINK_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", Vector3(MARKER_COLOR.r, MARKER_COLOR.g,
			MARKER_COLOR.b))
	mat.set_shader_parameter("hz", BLINK_HZ)
	return mat


static func _find_authoring(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("is_carlito_authoring"):
		return node
	for child in node.get_children():
		var found := _find_authoring(child)
		if found != null:
			return found
	return null
