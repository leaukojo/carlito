extends Node
const SCENES := {
	"plane": "res://src/vehicles/plane/plane.tscn",
	"tractor": "res://src/vehicles/kenney/tractor-kenney.tscn",
	"semi": "res://src/vehicles/truck/semi.tscn",
	"drone": "res://src/vehicles/drone/drone.tscn",
	"sedan": "res://src/vehicles/kenney/sedan.tscn",
}
func _ready() -> void:
	for k in SCENES:
		var n: Node = load(SCENES[k]).instantiate()
		add_child(n)
		await get_tree().process_frame
		print(">>> freeing ", k)
		n.free()
		await get_tree().process_frame
		await get_tree().process_frame
	print(">>> end")
	get_tree().quit()
