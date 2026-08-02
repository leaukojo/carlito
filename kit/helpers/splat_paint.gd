extends RefCounted
## Pure splat-paint math for the destructive "Paint splat under ..." buttons (RoadPath's
## paint-under-road, the palette dock's paint-under-tiles): rasterizes a road strip or a
## tile's actual mesh-face footprint into the terrain's splat weight images at FULL
## strength with a hard edge, biased to UNDERCOVER (the road strip is inset by its
## caller, the tile mask eroded here) so the paint always stays hidden under the deck. Full strength + hard edge on purpose: the splat shader pow-sharpens
## weights and grip_at sharpens the same way, so a hard paint reads as a crisp low-poly
## border AND full surface grip, with none of the low-grip apron a feathered edge would
## reintroduce. Same terrain-local conventions and pixel mapping as RoadBuilder's conform
## math (px = (x + span*0.5) / span * (iw-1), separate x/z scales); everything is static,
## deterministic and editor-free (tests/test_splat_paint.gd).
##
## Both entry points take parallel `images` / `units` arrays — one BrushOps.unit_slice per
## weight image. Painting a channel's slice into BOTH images zeroes the other seven
## channels at the pixel, whichever image each lives in. All images must share one size
## (a mismatched splatmap2 already has a terrain config warning; callers skip it).


## Editable, uncompressed RGBA8 working copy of a splat texture, or null when unset or
## undecodable. get_image() returns a copy, so painting it never touches the live texture.
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


## Paint every pixel whose center lies within `half_width` (m) of the centerline polyline
## (`samples`: terrain-local XZ, meters — callers sample AT the extrusion's ring offsets)
## or inside a deck triangle (`deck`: terrain-local XZ verts, 3 per triangle — a strip
## extruded on the ribbon's frames at the SAME half_width, which covers what the
## centerline sweep misses on yawing segments). Callers pass an already-inset half_width
## (undercoverage bias — see RoadPath.SPLAT_PAINT_INSET). Returns the tight dirty Rect2i in pixels (empty if
## nothing painted, or on empty/mismatched input). Same inputs -> identical bytes.
static func paint_strip(images: Array[Image], units: Array[Color],
		samples: PackedVector2Array, half_width: float, span_x: float, span_z: float,
		deck := PackedVector2Array()) -> Rect2i:
	if samples.is_empty() or not _images_valid(images, units):
		return Rect2i()
	var iw := images[0].get_width()
	var ih := images[0].get_height()
	var pts := samples
	if pts.size() == 1:
		pts.append(pts[0])   # local CoW copy: one degenerate segment (a paint dot)
	var sx := float(iw - 1) / maxf(span_x, 0.001)   # pixels per meter
	var sz := float(ih - 1) / maxf(span_z, 0.001)
	var rx := half_width * sx
	var rz := half_width * sz
	var hw2 := half_width * half_width
	var dirty := [iw, ih, -1, -1]   # plain Array: reference semantics for _paint

	# Centerline pass: pixel centers within half_width of the nearest point on any
	# segment. Pixels the padded box over-covers simply fail the distance test.
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

	# Deck raster pass: pixel centers inside a deck triangle. No erosion here — the
	# caller already insets the deck strip laterally (see RoadPath.SPLAT_PAINT_INSET).
	var mask := _tri_mask(deck, iw, ih, sx, sz, span_x, span_z)
	for pz in ih:
		for px in iw:
			if mask[pz * iw + px] == 1:
				_paint(images, units, px, pz, dirty)
	return _dirty_rect(dirty)


## Paint every pixel whose center lies inside one of the terrain-local XZ triangles
## (`tris`: meters, 3 verts per triangle — a GridMap cell's actual item-mesh faces
## projected to XZ, so a curve tile paints only the curve, never its full cell AABB),
## then ERODED by one pixel (8-neighbor, diagonals included): a covered pixel with any
## uncovered neighbor is dropped. Undercoverage on purpose — splat weights are bilinear-sampled, so a painted
## pixel bleeds up to one pixel outward; eroding keeps the sharpened border under the
## mesh instead of peeking past its edge. Returns the tight dirty Rect2i in pixels.
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
			# 8-neighbor erosion — diagonals INCLUDED: at a convex corner (two road
			# tiles meeting at an angle) a 4-neighbor check keeps the corner pixel
			# (both its axis neighbors lie on the L's arms) and its bilinear bleed
			# peeks diagonally past the mesh edge. Off-image counts as uncovered (a
			# mesh reaching the map border still stays inset).
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


## Full-image coverage mask (1 byte per pixel) of pixel centers inside any XZ triangle —
## the shared barycentric raster (the conform_heights raster with the plane-height math
## dropped). Interior shared edges stay covered (the small negative tolerance), so a
## triangulated surface never gets pinholes along its own seams.
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
			continue   # degenerate in XZ: a vertical face's projection
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


## Shared input guard: at least one image, parallel units, all sizes equal and paintable.
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


## Write the unit colors into every image at (px, pz) and grow the dirty bounds
## ([minx, minz, maxx, maxz] — a plain Array so mutation reaches the caller).
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
