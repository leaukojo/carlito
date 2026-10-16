class_name ShaderWarmup
extends RefCounted
## Front-loads shader compiles behind the loading screen by drawing the whole level for a few
## frames. The original particle emitter is left alone (WheelDrive.update_dust owns `emitting`).
## What it covers and what it doesn't: docs/systems.md § Shell, touch controls & garage.

## GeometryInstance3D.extra_cull_margin's range maximum: metres, wider than any level.
const CULL_MARGIN := 16384.0

var _margins: Array = []  ## [GeometryInstance3D, float] pairs, the margins to restore
var _hidden: Array[GeometryInstance3D] = []  ## instances shown for the warmup, to re-hide
var _twins: Array[GPUParticles3D] = []


## Grow every instance under `root` and start a twin per particle emitter. `root` must be in
## the tree (twins take their original's global transform).
static func begin(root: Node) -> ShaderWarmup:
	var warmup := ShaderWarmup.new()
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node is GPUParticles3D:
			warmup._twin(root, node as GPUParticles3D)
			continue
		var gi := node as GeometryInstance3D
		warmup._margins.append([gi, gi.extra_cull_margin])
		gi.extra_cull_margin = CULL_MARGIN
		if not gi.visible:
			warmup._hidden.append(gi)
			gi.visible = true
	return warmup


## Put every margin back and free the twins. Safe after `root` (or any of it) is freed.
func end() -> void:
	for entry: Array in _margins:
		if is_instance_valid(entry[0]):
			(entry[0] as GeometryInstance3D).extra_cull_margin = entry[1]
	_margins.clear()
	for gi in _hidden:
		if is_instance_valid(gi):
			gi.visible = false
	_hidden.clear()
	for twin in _twins:
		if is_instance_valid(twin):
			twin.queue_free()
	_twins.clear()


func _twin(root: Node, source: GPUParticles3D) -> void:
	var twin := source.duplicate() as GPUParticles3D
	twin.name = "WarmupTwin"
	twin.visibility_aabb = AABB(-Vector3.ONE * CULL_MARGIN, Vector3.ONE * CULL_MARGIN * 2.0)
	twin.amount_ratio = 1.0
	twin.emitting = true
	root.add_child(twin)
	twin.global_transform = source.global_transform
	_twins.append(twin)
