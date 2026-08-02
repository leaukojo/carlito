@tool
extends EditorNode3DGizmoPlugin
## Viewport gizmo for ScatterRegion: draws the footprint border — box or
## polygon — in the region's local space while the node is selected, so an author
## can see the area Regenerate will fill. Corner posts keep the border readable
## when it sinks into sloped ground (the loop is drawn flat at the node's Y).
## Editor-only, so it lives in the addon (the editor/runtime split); the
## region is detected by its duck-typed marker like everywhere else.

const POST_HEIGHT := 2.0


func _init() -> void:
	create_material("footprint", Color(0.35, 0.95, 0.5))


func _get_gizmo_name() -> String:
	return "ScatterRegion"


# Keyed on footprint_polygon, not is_carlito_scatter: only ScatterRegion has a footprint to
# draw — the hand-painted ScatterCanvas (also a scatter node) has none.
func _has_gizmo(node: Node3D) -> bool:
	return node.has_method("footprint_polygon")


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var region := gizmo.get_node_3d()
	var poly: PackedVector2Array = region.call("footprint_polygon")
	if poly.size() < 2:
		return
	var lines := PackedVector3Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		lines.append(Vector3(a.x, 0, a.y))
		lines.append(Vector3(b.x, 0, b.y))
		lines.append(Vector3(a.x, 0, a.y))
		lines.append(Vector3(a.x, POST_HEIGHT, a.y))
	gizmo.add_lines(lines, get_material("footprint", gizmo))
