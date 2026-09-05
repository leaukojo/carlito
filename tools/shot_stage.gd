extends RefCounted
## Offscreen-capture sequence shared by the PNG-writing generators (gen_thumbs.gd,
## gen_level_thumbs.gd, gen_vehicle_thumbs.gd): build the capture SubViewport, let it settle
## for N frames, then read back and write the image. Framing and subject setup are per-
## generator (kit prefabs, level overviews and vehicle turntables each pick their own camera
## and lighting) and stay there.


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
## push_error) on a blank capture or a failed write; the caller frees its subject either way.
static func save_capture(vp: SubViewport, out_path: String) -> bool:
	var img := vp.get_texture().get_image()
	if img == null:
		push_error("blank capture for " + out_path)
		return false
	if img.save_png(out_path) != OK:
		push_error("cannot write " + out_path)
		return false
	return true
