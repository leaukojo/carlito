class_name ShaderWarmup
extends RefCounted
## Front-loads shader compiles behind the loading screen. gl_compatibility has no ubershader:
## every material variant compiles synchronously on its first draw, so geometry scrolling into
## view (cresting a hill) hitches the frame it arrives. While begin() is in effect the renderer
## draws the WHOLE level every frame — each instance's culling box is grown past the level, so
## every chunk, scatter MultiMesh, prop and vehicle is submitted in its real passes (shadow
## cascades included) with its real vertex format and instancing. Nothing on screen changes:
## geometry outside the frustum is still clipped on the GPU. The cost is a few full-level frames,
## which the loading screen covers.
##
## Particles need a twin: an emitter that has never emitted is inactive and is never drawn, so
## growing its box compiles nothing. Each GPUParticles3D gets an emitting copy sharing its
## process and draw materials; the original is left alone (WheelDrive.update_dust rewrites its
## `emitting` every tick).
##
## Hidden instances (the plane's prop disc, a lamp lens) are never submitted however wide their
## box, so each is shown for the warmup frames and hidden again in end(); an instance under a
## hidden ANCESTOR still isn't drawn and compiles on its first reveal.
##
## Not covered: materials first seen after the load (a V / garage body swap, an E attachment)
## and light-count variants (headlights, night) still compile on the frame they first draw.
## Hiding that hitch needs the reveal delayed a few frames behind an off-screen compile pass,
## and `Level._spawn_vehicle` is called synchronously today — `ChallengeRunner.start()` and
## `boot.gd`'s `_on_vehicle_picked` -> `_on_attachment_picked` both read `Level.vehicle` on the
## line right after calling it. Covering the swap means either threading `await` through those
## call sites or a synchronous mid-frame flush (`RenderingServer.force_draw`, unused and
## unverified elsewhere in this codebase) — a real architecture change, not a bolt-on. Left
## uncovered on purpose until one of those is worth doing.

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
