@tool
extends EditorNode3DGizmoPlugin
## Viewport gizmo for ScatterRegion: draws the footprint border (box or polygon) in the
## region's local space while selected, so the author can see the area Regenerate will fill.
## Corner posts keep the border readable when it sinks into sloped ground.

const POST_HEIGHT := 2.0


func _init() -> void:
	create_material("footprint", Color(0.35, 0.95, 0.5))


func _get_gizmo_name() -> String:
	return "ScatterRegion"


# has_method probe, not carlito_scatter: only ScatterRegion has a footprint; ScatterCanvas has none.
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
