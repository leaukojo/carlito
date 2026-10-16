@tool
class_name ArenaPreview
extends Node3D
## Editor-only authoring aid: shows the arena a challenge course is laid over. The course carries
## the arena, never the reverse (zones inside an arena would re-stale its bake on every tweak).
## Named by LevelRegistry id, so the course never depends on or reloads the level; an unowned,
## top-level internal child, so saving never writes it. Frees itself at runtime.

@export var arena := "":
	set(value):
		arena = value
		_rebuild()
		update_configuration_warnings()

var _preview: Node = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_rebuild()


func _get_configuration_warnings() -> PackedStringArray:
	if arena != "" and LevelRegistry.scene_of(arena) == "":
		return PackedStringArray(["'%s' is not a registered level id" % arena])
	return PackedStringArray()


func _rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
		_preview = null
	var path := LevelRegistry.scene_of(arena)
	if path == "":
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_preview = packed.instantiate()
	var spatial := _preview as Node3D
	if spatial != null:
		spatial.top_level = true
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	if spatial != null:
		spatial.global_transform = Transform3D.IDENTITY
