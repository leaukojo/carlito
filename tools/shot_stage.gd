extends RefCounted
## Offscreen-capture sequence shared by the PNG-writing generators (gen_thumbs.gd,
## gen_level_thumbs.gd, gen_challenge_thumbs.gd, gen_vehicle_thumbs.gd): build the capture
## SubViewport, let it settle for N frames, then read back and write the image. Framing and subject
## setup are per-generator (kit prefabs, level overviews and vehicle turntables each pick their own
## camera and lighting) and stay there.

const FOG_HAZE := 0.25  ## fog_density * shot distance — see thin_fog


## A SubViewport sized and dressed for offscreen capture: isolated world, opaque, redrawn every
## frame (the default ONCE mode never updates a target nothing else is looking at).
static func build_viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp


## Let `frames` process frames pass so whatever was just added to or moved in the viewport
## lands in the render target before it is read back.
static func settle(tree: SceneTree, frames: int) -> void:
	for _i in frames:
		await tree.process_frame


## Read back `vp`'s render target and write it to `out_path`. Returns false (with a
## push_error) on a headless run, a blank capture or a failed write; the caller frees its subject
## either way. A headless run renders nothing, so writing would overwrite a committed card with a
## blank one.
static func save_capture(vp: SubViewport, out_path: String) -> bool:
	if DisplayServer.get_name() == "headless":
		push_error("headless run renders nothing; not writing " + out_path + " (run windowed)")
		return false
	var img := vp.get_texture().get_image()
	if img == null:
		push_error("blank capture for " + out_path)
		return false
	if img.save_png(out_path) != OK:
		push_error("cannot write " + out_path)
		return false
	return true


## A selector card: `save_capture`, then the card's import settings (`CardImport`) and a
## "<tag> -> <out_path>" line. False as `save_capture`.
static func save_card(vp: SubViewport, out_path: String, tag: String) -> bool:
	if not save_capture(vp, out_path):
		return false
	CardImport.ensure_import_settings(out_path)
	print("%s -> %s" % [tag, out_path])
	return true


## Fog is tuned for ground-level driving, so a wide shot reads as a white sheet; thin `level`'s to a
## fixed haze at the shot's own distance `dist` (m). Safe to mutate: Environment is duplicated per
## level.
static func thin_fog(level: Node3D, dist: float) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null or not env.fog_enabled:
			continue
		env.fog_density = minf(env.fog_density, FOG_HAZE / maxf(dist, 1.0))
		return
