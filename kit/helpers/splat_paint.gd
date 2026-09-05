extends RefCounted
## Pure splat-paint math for the destructive "Paint splat under ..." buttons: rasterizes
## a road strip or tile mesh-face footprint into the terrain's splat weight images at
## full strength with a hard edge, biased to undercover so paint stays hidden under the
## deck. Hard edge matches the splat shader's pow-sharpening, so it reads as a crisp
## low-poly border with full surface grip. Static, deterministic, editor-free
## (tests/test_splat_paint.gd). Both entry points take parallel `images`/`units` arrays —
## one BrushOps.unit_slice per weight image, so painting zeroes the other seven channels.


## Editable, uncompressed RGBA8 working copy of a splat texture, or null if unset.
static func decode(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Paint every pixel within `half_width` (m) of the centerline polyline (`samples`) or
## inside a deck triangle (`deck` — covers what the centerline sweep misses on yawing
## segments). Callers pass an already-inset half_width (RoadPath.SPLAT_PAINT_INSET).
static func paint_strip(images: Array[Image], units: Array[Color],
		samples: PackedVector2Array, half_width: float, span_x: float, span_z: float,
		deck := PackedVector2Array()) -> Rect2i:
	if samples.is_empty() or not _images_valid(images, units):
		return Rect2i()
	var iw := images[0].get_width()
	var ih := images[0].get_height()
	var pts := samples
	if pts.size() == 1:
		pts.append(pts[0])   # one degenerate segment (a paint dot)
	var sx := float(iw - 1) / maxf(span_x, 0.001)   # pixels per meter
	var sz := float(ih - 1) / maxf(span_z, 0.001)
	var rx := half_width * sx
	var rz := half_width * sz
	var hw2 := half_width * half_width
	var dirty := [iw, ih, -1, -1]   # plain Array: reference semantics for _paint

	for si in pts.size() - 1:
		var a := pts[si]
		var b := pts[si + 1]
		var ax := (a.x + span_x * 0.5) * sx
		var az := (a.y + span_z * 0.5) * sz
		var bx := (b.x + span_x * 0.5) * sx
		var bz := (b.y + span_z * 0.5) * sz
		var x0 := clampi(int(floor(minf(ax, bx) - rx)) - 1, 0, iw - 1)
		var x1 := clampi(int(ceil(maxf(ax, bx) + rx)) + 1, 0, iw - 1)
		var z0 := clampi(int(floor(minf(az, bz) - rz)) - 1, 0, ih - 1)
		var z1 := clampi(int(ceil(maxf(az, bz) + rz)) + 1, 0, ih - 1)
		var abx := b.x - a.x   # meters
		var abz := b.y - a.y
		var ab2 := abx * abx + abz * abz
		for pz in range(z0, z1 + 1):
			var pmz := float(pz) / sz - span_z * 0.5
			for px in range(x0, x1 + 1):
				var pmx := float(px) / sx - span_x * 0.5
				var t := 0.0
				if ab2 > 1e-12:
					t = clampf(((pmx - a.x) * abx + (pmz - a.y) * abz) / ab2, 0.0, 1.0)
				var dxm := pmx - (a.x + abx * t)
				var dzm := pmz - (a.y + abz * t)
				if dxm * dxm + dzm * dzm <= hw2:
					_paint(images, units, px, pz, dirty)

	var mask := _tri_mask(deck, iw, ih, sx, sz, span_x, span_z)
	for pz in ih:
		for px in iw:
			if mask[pz * iw + px] == 1:
				_paint(images, units, px, pz, dirty)
	return _dirty_rect(dirty)


## Paint every pixel inside one of the terrain-local XZ triangles (`tris`, a GridMap
## cell's actual item-mesh faces), then eroded by one pixel (8-neighbor) to keep the
## sharpened border under the mesh instead of bleeding past its edge.
static func paint_tris(images: Array[Image], units: Array[Color], tris: PackedVector2Array,
		span_x: float, span_z: float) -> Rect2i:
	if tris.size() < 3 or not _images_valid(images, units):
		return Rect2i()
	var iw := images[0].get_width()
	var ih := images[0].get_height()
	var sx := float(iw - 1) / maxf(span_x, 0.001)   # pixels per meter
	var sz := float(ih - 1) / maxf(span_z, 0.001)
	var dirty := [iw, ih, -1, -1]
	var mask := _tri_mask(tris, iw, ih, sx, sz, span_x, span_z)
	for pz in ih:
		for px in iw:
			if mask[pz * iw + px] != 1:
				continue
			if px == 0 or px == iw - 1 or pz == 0 or pz == ih - 1:
				continue
			var open := false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if mask[(pz + dz) * iw + px + dx] == 0:
						open = true
			if open:
				continue
			_paint(images, units, px, pz, dirty)
	return _dirty_rect(dirty)


## Full-image coverage mask (1 byte per pixel) of pixel centers inside any XZ triangle.
static func _tri_mask(tris: PackedVector2Array, iw: int, ih: int, sx: float, sz: float,
		span_x: float, span_z: float) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(iw * ih)
	for ti in range(0, tris.size() - 2, 3):
		var ta := tris[ti]
		var tb := tris[ti + 1]
		var tc := tris[ti + 2]
		var abx := tb.x - ta.x
		var abz := tb.y - ta.y
		var acx := tc.x - ta.x
		var acz := tc.y - ta.y
		var den := abx * acz - abz * acx
		if absf(den) < 1e-9:
			continue   # degenerate in XZ (a vertical face's projection)
		var x0 := clampi(int(floor((minf(ta.x, minf(tb.x, tc.x)) + span_x * 0.5) * sx)),
				0, iw - 1)
		var x1 := clampi(int(ceil((maxf(ta.x, maxf(tb.x, tc.x)) + span_x * 0.5) * sx)),
				0, iw - 1)
		var z0 := clampi(int(floor((minf(ta.y, minf(tb.y, tc.y)) + span_z * 0.5) * sz)),
				0, ih - 1)
		var z1 := clampi(int(ceil((maxf(ta.y, maxf(tb.y, tc.y)) + span_z * 0.5) * sz)),
				0, ih - 1)
		for pz in range(z0, z1 + 1):
			var pmz := float(pz) / sz - span_z * 0.5
			for px in range(x0, x1 + 1):
				var pmx := float(px) / sx - span_x * 0.5
				var apx := pmx - ta.x
				var apz := pmz - ta.y
				var w1 := (apx * acz - apz * acx) / den
				var w2 := (abx * apz - abz * apx) / den
				if w1 < -1e-6 or w2 < -1e-6 or w1 + w2 > 1.0 + 1e-6:
					continue
				mask[pz * iw + px] = 1
	return mask


static func _images_valid(images: Array[Image], units: Array[Color]) -> bool:
	if images.is_empty() or units.size() != images.size():
		return false
	var iw := images[0].get_width()
	var ih := images[0].get_height()
	if iw < 2 or ih < 2:
		return false
	for img in images:
		if img.get_width() != iw or img.get_height() != ih:
			return false
	return true


static func _paint(images: Array[Image], units: Array[Color], px: int, pz: int,
		dirty: Array) -> void:
	for i in images.size():
		images[i].set_pixel(px, pz, units[i])
	dirty[0] = mini(dirty[0], px)
	dirty[1] = mini(dirty[1], pz)
	dirty[2] = maxi(dirty[2], px)
	dirty[3] = maxi(dirty[3], pz)


static func _dirty_rect(dirty: Array) -> Rect2i:
	if int(dirty[2]) < 0:
		return Rect2i()
	return Rect2i(dirty[0], dirty[1],
			int(dirty[2]) - int(dirty[0]) + 1, int(dirty[3]) - int(dirty[1]) + 1)
