@tool
class_name KitPiece
extends Node3D
## Root of every generated kit prefab (kit/prefabs/**). Carries how this piece
## participates in collision: "none" decoration; "box" one box; "footprint" tightest
## box/cylinder over the standing area, extruded full height; "hull" one convex hull;
## "multiconvex" several hulls; "weld" drivable, joins the level's welded body at bake.
## The generator pre-builds box/footprint/hull/multiconvex shapes in a "DevCollision"
## child so unbaked levels are playable; "weld" pieces get a dev trimesh instead.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

@export_enum("none", "box", "footprint", "hull", "multiconvex", "weld") var collision_mode := "box"


## `_init`, not `_enter_tree`: the baker instantiates scatter templates out of the tree.
func _init() -> void:
	add_to_group(Groups.KIT_PIECE)
