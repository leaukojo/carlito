extends RefCounted
## Pure, unit-tested brush math for the editor-only terrain sculpt/paint brush
## (addons/carlito_kit/terrain_brush.gd). Deterministic, works in pixel space with
## separate x/z pixel radii (a world-circular brush stamps as an ellipse on a non-square
## terrain). Height image is greyscale (red = normalized height); splat weights are an
## 8-vector split across two RGBA images — 0..3 in splatmap, 4..7 in splatmap2.

enum { RAISE, LOWER, SMOOTH, FLATTEN }

## Normalized height change per full-strength, full-weight sample.
const RATE := 0.05


## Distance from brush centre; Euclidean = round brush, Chebyshev = square.
static func brush_dist(dx: float, dz: float, square: bool) -> float:
	if square:
		return maxf(absf(dx), absf(dz))
	return sqrt(dx * dx + dz * dz)


## Snap a world X/Z to the nearest lattice point (pitch `size`, anchored at `origin`).
static func snap_to_grid(x: float, z: float, size_x: float, size_z: float,
		origin_x: float, origin_z: float) -> Vector2:
	var sx := roundi((x - origin_x) / maxf(size_x, 1e-3)) * size_x + origin_x
	var sz := roundi((z - origin_z) / maxf(size_z, 1e-3)) * size_z + origin_z
	return Vector2(sx, sz)


## Radial brush weight for t (0 at centre, 1 at rim). `falloff` 0 = hard disk, 1 = smooth
## dome. `inclusive` includes the exact rim; the square brush needs it so abutting cells tile.
static func weight(t: float, falloff: float, inclusive := false) -> float:
	if t <= 0.0:
		return 1.0
	if t > 1.0:
		return 0.0
	if t >= 1.0 and not inclusive:
		return 0.0
	var inner := clampf(1.0 - falloff, 0.0, 1.0)
	if t <= inner:
		return 1.0
	var x := (t - inner) / maxf(1.0 - inner, 1e-4)
	return 1.0 - x * x * (3.0 - 2.0 * x)


static func sculpt_value(mode: int, value: float, avg: float, target: float,
		amount: float) -> float:
	match mode:
		RAISE:
			return clampf(value + amount * RATE, 0.0, 1.0)
		LOWER:
			return clampf(value - amount * RATE, 0.0, 1.0)
		SMOOTH:
			return clampf(lerpf(value, avg, amount), 0.0, 1.0)
		FLATTEN:
			return clampf(lerpf(value, target, amount), 0.0, 1.0)
	return value


## Stamp a sculpt op into the greyscale height image. Reads from a snapshot of the touched
## region (so smooth is unbiased by write order). Returns the tight dirty Rect2i.
static func stamp_height(img: Image, cx: int, cy: int, rx: float, rz: float,
		mode: int, strength: float, falloff: float, target: float, square := false) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	var x0 := clampi(cx - int(ceil(rx)) - 1, 0, iw - 1)
	var x1 := clampi(cx + int(ceil(rx)) + 1, 0, iw - 1)
	var y0 := clampi(cy - int(ceil(rz)) - 1, 0, ih - 1)
	var y1 := clampi(cy + int(ceil(rz)) + 1, 0, ih - 1)
	var src := img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	var sw := src.get_width()
	var sh := src.get_height()

	var minx := iw
	var miny := ih
	var maxx := -1
	var maxy := -1
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx := float(px - cx) / maxf(rx, 1e-4)
			var dz := float(py - cy) / maxf(rz, 1e-4)
			var t := brush_dist(dx, dz, square)
			if t > 1.0:
				continue
			var w := weight(t, falloff, square)
			if w <= 0.0:
				continue
			var lx := px - x0
			var ly := py - y0
			var value := src.get_pixel(lx, ly).r
			var nv := sculpt_value(mode, value, _avg(src, lx, ly, sw, sh), target,
					strength * w)
			img.set_pixel(px, py, Color(nv, nv, nv))
			minx = mini(minx, px); miny = mini(miny, py)
			maxx = maxi(maxx, px); maxy = maxi(maxy, py)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


## RGBA slice of the 8-channel unit vector for `channel` in splat image `image_index` (0 =
## splatmap holds 0..3, 1 = splatmap2 holds 4..7). All-zero in the other image.
static func unit_slice(channel: int, image_index: int) -> Color:
	var unit := Color(0, 0, 0, 0)
	match clampi(channel, 0, 7) - image_index * 4:
		0: unit.r = 1.0
		1: unit.g = 1.0
		2: unit.b = 1.0
		3: unit.a = 1.0
	return unit


## Stamp a splat-channel paint into an RGBA weight image: pulls each pixel toward `unit`
## (a unit_slice) by strength*weight. The splat shader renormalizes, so this reads as
## "painting grass over dirt".
static func stamp_splat(img: Image, cx: int, cy: int, rx: float, rz: float,
		unit: Color, strength: float, falloff: float, square := false) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	var x0 := clampi(cx - int(ceil(rx)) - 1, 0, iw - 1)
	var x1 := clampi(cx + int(ceil(rx)) + 1, 0, iw - 1)
	var y0 := clampi(cy - int(ceil(rz)) - 1, 0, ih - 1)
	var y1 := clampi(cy + int(ceil(rz)) + 1, 0, ih - 1)

	var minx := iw
	var miny := ih
	var maxx := -1
	var maxy := -1
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx := float(px - cx) / maxf(rx, 1e-4)
			var dz := float(py - cy) / maxf(rz, 1e-4)
			var t := brush_dist(dx, dz, square)
			if t > 1.0:
				continue
			var w := weight(t, falloff, square)
			if w <= 0.0:
				continue
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(unit, clampf(strength * w, 0.0, 1.0)))
			minx = mini(minx, px); miny = mini(miny, py)
			maxx = maxi(maxx, px); maxy = maxi(maxy, py)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


## Lay a straight ramp between two points: pixels within half-width of segment a->b are
## pulled toward the height lerped along it, giving a constant-grade drivable surface.
## Geometry runs in "brush units" (pixel offset / half-width) so measuring stays metrically
## honest on a non-square terrain.
static func stamp_ramp(img: Image, a_px: Vector2i, a_h: float, b_px: Vector2i, b_h: float,
		rx: float, rz: float, strength: float, falloff: float) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	var pad_x := int(ceil(rx)) + 1
	var pad_z := int(ceil(rz)) + 1
	var x0 := clampi(mini(a_px.x, b_px.x) - pad_x, 0, iw - 1)
	var x1 := clampi(maxi(a_px.x, b_px.x) + pad_x, 0, iw - 1)
	var y0 := clampi(mini(a_px.y, b_px.y) - pad_z, 0, ih - 1)
	var y1 := clampi(maxi(a_px.y, b_px.y) + pad_z, 0, ih - 1)

	var bx := float(b_px.x - a_px.x) / maxf(rx, 1e-4)
	var bz := float(b_px.y - a_px.y) / maxf(rz, 1e-4)
	var len2 := bx * bx + bz * bz   # degenerate A == B behaves as a flatten disk at a_h

	var minx := iw
	var miny := ih
	var maxx := -1
	var maxy := -1
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var ax := float(px - a_px.x) / maxf(rx, 1e-4)
			var az := float(py - a_px.y) / maxf(rz, 1e-4)
			var t := 0.0 if len2 < 1e-12 else clampf((ax * bx + az * bz) / len2, 0.0, 1.0)
			var ox := ax - bx * t
			var oz := az - bz * t
			var across := sqrt(ox * ox + oz * oz)
			if across > 1.0:
				continue
			var w := weight(across, falloff)
			if w <= 0.0:
				continue
			var value := img.get_pixel(px, py).r
			var nv := clampf(lerpf(value, lerpf(a_h, b_h, t), clampf(strength * w, 0.0, 1.0)),
					0.0, 1.0)
			img.set_pixel(px, py, Color(nv, nv, nv))
			minx = mini(minx, px); miny = mini(miny, py)
			maxx = maxi(maxx, px); maxy = maxi(maxy, py)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


## Flood a whole weight image with one unit_slice, with the stamp's dirty-rect contract.
static func fill_splat(img: Image, unit: Color) -> Rect2i:
	img.fill(unit)
	return Rect2i(0, 0, img.get_width(), img.get_height())


static func _avg(src: Image, x: int, y: int, w: int, h: int) -> float:
	var acc := src.get_pixel(x, y).r
	var n := 1.0
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		acc += src.get_pixel(clampi(x + d.x, 0, w - 1), clampi(y + d.y, 0, h - 1)).r
		n += 1.0
	return acc / n
