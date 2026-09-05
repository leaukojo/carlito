@tool
class_name ScatterItem
extends Resource
## One entry in a scatter item table. `prefab` is a PackedScene (never a path string) so
## the stale-bake hash tracks it automatically.

@export var prefab: PackedScene
## Relative pick weight against the region's other items (<= 0 never picked).
@export var weight := 1.0
## Off = zero physics (grass tufts, small rocks): no dev collision, no baked shapes.
@export var collision := true
## Instance count at/above which bake emits one MultiMeshInstance3D per chunk instead of
## merging verts. -1 = baker default.
@export var bake_threshold_override := -1
## Off = baked MultiMeshes skip shadows (small vegetation). Below-threshold instances always cast.
@export var cast_shadow := true
