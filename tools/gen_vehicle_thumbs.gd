extends Node
## Vehicle card generator: renders the picture on every card in the vehicle selector, to
## src/ui/vehicle_thumbs/<id>.png, framed via VehicleShot (shared with the selector's live
## turntable). Must run WINDOWED (headless captures come back blank). Bodies are
## instantiated for real and frozen, so a semi's card carries the trailer it pulls up with.

const ShotStage := preload("res://tools/shot_stage.gd")

## Physics ticks before read-back: wheels are posed by RayWheel and the semi couples its
## trailer on a spawn countdown, so a capture too early gets half a rig.
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


## id -> scene path for every picture the selector can ask for. Catalogs are walked, not
## listed here, so a new variant or trailer gets a card automatically; DETACHED/BOBTAIL-style
## empty entries have nothing to photograph and the selector draws those as a plate.
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

	await ShotStage.settle(get_tree(), SETTLE_FRAMES)

	var bounds := VehicleShot.subject_bounds(inst)
	if bounds.size == Vector3.ZERO:
		_free_subject(inst)
		push_error("no visible geometry in " + scene_path)
		return false
	VehicleShot.frame(_camera, bounds, VehicleShot.VIEW_YAW_DEG)
	# Give the viewport two more frames to draw from where the camera now stands.
	await ShotStage.settle(get_tree(), 2)
	var out := VehicleShot.thumb_path(id)
	var ok := ShotStage.save_capture(_viewport, out)

	_free_subject(inst)

	if not ok:
		return false
	CardImport.ensure_import_settings(out)
	print("[vehicle thumbs] %s -> %s" % [id, out])
	return true


## Take the subject out before the next arrives: `remove_child` first, `queue_free` after
## (queue_free flushes at end of frame, after physics steps run).
func _free_subject(inst: Node3D) -> void:
	var host := inst.get_parent()
	if host != null:
		host.remove_child(inst)
	inst.queue_free()
