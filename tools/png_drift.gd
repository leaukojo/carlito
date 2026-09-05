# Compares two PNGs pixel-for-pixel; used by tools/rebuild_level.ps1 to classify a changed
# generated PNG (real drift vs. a non-idempotent sculpt moving pixels by 1-3 8-bit steps).
# Prints one machine-readable line the driver parses:
#   DRIFT px=<pixels differing> max=<largest per-channel step> total=<pixel count>
extends SceneTree


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() != 2:
		printerr("png_drift: expected <before> <after>")
		quit(2)
		return
	var before := Image.load_from_file(argv[0])
	var after := Image.load_from_file(argv[1])
	if before == null or after == null:
		printerr("png_drift: could not load one of the images")
		quit(2)
		return
	if before.get_width() != after.get_width() or before.get_height() != after.get_height():
		printerr("png_drift: size differs (%dx%d vs %dx%d)" % [
			before.get_width(), before.get_height(), after.get_width(), after.get_height()])
		quit(2)
		return
	var a := before.get_data()
	var b := after.get_data()
	if a.size() != b.size():
		printerr("png_drift: pixel format differs")
		quit(2)
		return
	var total := before.get_width() * before.get_height()
	# Bytes per pixel, so a differing pixel is counted once however many channels moved.
	@warning_ignore("integer_division")
	var stride := a.size() / total if total > 0 else 1
	var moved := 0
	var worst := 0
	for p in total:
		var hit := false
		for c in stride:
			var d: int = absi(a[p * stride + c] - b[p * stride + c])
			if d > 0:
				hit = true
				if d > worst:
					worst = d
		if hit:
			moved += 1
	print("DRIFT px=%d max=%d total=%d" % [moved, worst, total])
	quit(0)
