extends Node
## Vehicle card generator: renders the picture on every card in the vehicle selector, to
## src/ui/vehicle_thumbs/<id>.png. Two sets, one pipeline:
##
##   BODIES       every VehicleCatalog.VARIANTS entry, by variant id ("sedan-sports.png")
##   ATTACHMENTS  every ImplementCatalog / TrailerCatalog scene, by basename ("tipper.png")
##
## Framing, lighting and the display pose all come from VehicleShot, which the live turntable in
## the selector uses too — so the still on the card and the model rotating beside it are the same
## picture of the same machine.
##
## MUST run WINDOWED (a real GPU context) — headless has no renderer, so the SubViewport captures
## come back blank. It is a GAME-MODE tool scene rather than --script for the same reason
## gen_level_thumbs is: --script mode cannot compile scripts that name autoloads (BaseVehicle
## reaches InputRouter), and only a live SceneTree renders frames.
##   godot --path . res://tools/gen_vehicle_thumbs.tscn                 # everything
##   godot --path . res://tools/gen_vehicle_thumbs.tscn -- semi tipper  # named ids only
##
## The bodies are instantiated FOR REAL, frozen and hovering (VehicleShot.spawn_display), so what
## the card shows is what spawns — a semi's card carries the trailer it really pulls up with.

## Physics ticks before read-back. The wheels are posed by RayWheel and the semi couples its
## trailer on a spawn countdown, so a capture too early is a body with its wheels stacked at the
## origin, or half a rig. SemiTractor.SPAWN_COUPLE_TICKS is the number to clear.
const SETTLE_FRAMES := 45

var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	var only := OS.get_cmdline_user_args()
	DirAccess.open("res://").make_dir_recursive(VehicleShot.THUMB_DIR.trim_prefix("res://"))

	_viewport = SubViewport.new()
	_viewport.size = VehicleShot.CAPTURE_SIZE
	add_child(_viewport)
	_camera = VehicleShot.build_stage(_viewport)

	var jobs := _jobs()
	var written := 0
	var failed := 0
	for id: String in jobs:
		if not only.is_empty() and not only.has(id):
			continue
		if await _shoot(id, String(jobs[id])):
			written += 1
		else:
			failed += 1
	print("[vehicle thumbs] wrote %d image(s), %d failed" % [written, failed])
	get_tree().quit(1 if failed > 0 else 0)


## id -> scene path, for every picture the selector can ask for. The catalogs are walked rather
## than listed here, so a variant or a trailer added later gets a card without touching this file;
## their empty entries (DETACHED / BOBTAIL) are real cycle entries with nothing to photograph, and
## the selector draws those as a plate rather than a picture.
func _jobs() -> Dictionary:
	var out := {}
	for variant: String in VehicleCatalog.VARIANTS:
		out[variant] = VehicleCatalog.scene_of(variant)
	for path in ImplementCatalog.IMPLEMENTS + TrailerCatalog.TRAILERS:
		var id := VehicleShot.id_for_scene(path)
		if id.is_empty():
			continue
		if out.has(id):
			push_error("thumbnail id collision: '%s' is both a variant and an attachment" % id)
			continue
		out[id] = path
	return out


func _shoot(id: String, scene_path: String) -> bool:
	var inst := VehicleShot.spawn_display(scene_path)
	if inst == null:
		push_error("cannot instantiate " + scene_path)
		return false
	_viewport.add_child(inst)
	VehicleShot.pin_display(inst)

	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var bounds := VehicleShot.subject_bounds(inst)
	if bounds.size == Vector3.ZERO:
		_free_subject(inst)
		push_error("no visible geometry in " + scene_path)
		return false
	VehicleShot.frame(_camera, bounds, VehicleShot.VIEW_YAW_DEG)
	# The camera moved after the last rendered frame; give the viewport two more to draw from
	# where it now stands before the texture is read back.
	await get_tree().process_frame
	await get_tree().process_frame
	var img := _viewport.get_texture().get_image()

	_free_subject(inst)

	if img == null:
		push_error("blank capture for " + scene_path)
		return false
	var out := VehicleShot.thumb_path(id)
	if img.save_png(out) != OK:
		push_error("cannot write " + out)
		return false
	CardImport.ensure_import_settings(out)
	print("[vehicle thumbs] %s -> %s" % [id, out])
	return true


## Take the subject out of the stage before the next one arrives. `remove_child` first and
## `queue_free` after, the semi's own _drop_trailer discipline: queue_free flushes at the end of
## the frame and physics steps run before that, so a deferred free alone leaves the old rig in the
## world while the next one is being laid. Only the vehicle root is touched — a body that owns
## another body drops it in its own _exit_tree, and freeing the trailer here as well would be a
## second queue_free on the same node.
func _free_subject(inst: Node3D) -> void:
	var host := inst.get_parent()
	if host != null:
		host.remove_child(inst)
	inst.queue_free()
