@tool
class_name ArenaPreview
extends Node3D
## Authoring aid for a challenge course: shows the arena the course is laid over, in the editor
## only. A course is a runtime overlay and never arena content — zones authored inside an arena
## would be bake inputs and re-stale its bake on every tweak — so while authoring it is the course
## that carries the arena, never the reverse.
##
## The arena is named by its LevelRegistry id, a String, so the course takes no dependency on the
## level and instancing it at runtime never loads the arena a second time. The instance is an
## unowned internal child, so saving the course never writes it, and it is top-level at the world
## origin, where the arena sits at runtime, whatever the course root's own transform. At runtime
## this node frees itself. `ChallengeRegistry.problems` fails a preview naming a different arena
## than the def.

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
