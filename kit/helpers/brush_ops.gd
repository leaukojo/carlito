extends RefCounted
## Pure, unit-tested brush math. The terrain sculpt/paint brush
## (addons/carlito_kit/terrain_brush.gd) is editor-only, but the per-pixel stamp math is
## plain Image arithmetic with no editor API, so it gets the same test discipline as
## TerrainGen/Drivetrain (tests/test_brush_ops.gd). Lives in kit/ (data +
## runtime-safe logic here, editor UX in addons/carlito_kit).
##
## Everything is deterministic and works in PIXEL space with separate x/z pixel radii, so a
## world-circular brush on a non-square terrain stamps as an ellipse in image space. The
## height image is greyscale (red channel = normalized height [0,1]); the splat weights are
## an 8-vector split across two RGBA images — channels 0..3 in the splatmap (R=grass, G=dirt,
## B=sand, A=rock — TerrainGen's channel order), 4..7 in the optional splatmap2.

# Sculpt modes (raise/lower shift the normalized height; smooth blurs; flatten pulls toward
# a captured target). Paint is a separate stamp (stamp_splat), not a sculpt mode.
enum { RAISE, LOWER, SMOOTH, FLATTEN }

## Normalized height change per full-strength, full-weight sample for raise/lower. Small so a
## drag ramps smoothly (samples are throttled by spacing in the brush) and 8-bit height PNGs
## still accumulate visibly (0.05 * 255 ~ 13 levels at full strength).
const RATE := 0.05


## Normalized distance from the brush centre for a pixel offset already divided by the
## per-axis pixel radii (so 1 = the rim on either axis). Euclidean gives the round brush;
## Chebyshev (the larger of the two) gives the square one — axis-aligned in image space,
## which is world-axis-aligned for our unrotated terrains.
static func brush_dist(dx: float, dz: float, square: bool) -> float:
	if square:
		return maxf(absf(dx), absf(dz))
	return sqrt(dx * dx + dz * dz)


## Snap a world X/Z to the nearest point of a lattice with pitch `size` anchored at `origin`
## (result = origin + size*round((v-origin)/size)). The caller bakes any half-cell offset into
## `origin` — the road GridMap's `cell_center_x/z = true` puts cell centres at
## `grid_origin + size*0.5 + size*k`, so passing `origin = grid_origin + size*0.5` lands on
## them. Axis-aligned, matching our unrotated terrains and GridMaps.
static func snap_to_grid(x: float, z: float, size_x: float, size_z: float,
		origin_x: float, origin_z: float) -> Vector2:
	var sx := roundi((x - origin_x) / maxf(size_x, 1e-3)) * size_x + origin_x
	var sz := roundi((z - origin_z) / maxf(size_z, 1e-3)) * size_z + origin_z
	return Vector2(sx, sz)


## Radial brush weight for a normalized distance t (0 at centre, 1 at the rim). `falloff`
## in [0,1] is the softness: 0 = a hard disk (weight 1 out to the rim), 1 = a smooth dome
## from the centre. The solid inner fraction is (1 - falloff); beyond it the weight
## smoothsteps down to 0 at t = 1.
##
## `inclusive` decides the EXACT rim (t == 1.0): normally excluded (weight 0), which keeps
## round-brush and ramp edges from double-covering. The square brush passes `inclusive = true`
## so a hard 12 m pad covers its full footprint and abutting cells tile with no seam — the
## rim then follows the falloff curve like any other point (so a soft square still fades, only
## a hard one — edge softness 0 — reaches the rim). See `stamp_height` / `stamp_splat`.
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


## One sculpt op on a normalized height value. `amount` is strength * weight (0..1): raise/
## lower add/subtract amount*RATE, smooth lerps toward the local average, flatten lerps
## toward the stroke's captured target. Result clamped to [0,1].
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


## Stamp a sculpt op into the greyscale height image, centred on pixel (cx, cy) with pixel
## radii (rx, rz). `square` swaps the round footprint for an axis-aligned square one. Reads
## base + neighbour heights from a snapshot of the touched region (so smooth is unbiased by
## the write order) and writes new heights back. Returns the tight dirty Rect2i in pixels
## (empty when nothing changed), which the brush unions for the undo snapshot and the
## incremental remesh.
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


## The RGBA slice of the 8-channel unit vector for `channel` (0..7) that belongs to splat
## image `image_index` (0 = splatmap holds channels 0..3, 1 = splatmap2 holds 4..7). All-zero
## when the channel lives in the OTHER image — and that is the whole trick: stamping both
## images with their slice lerps the far image's weights toward zero, so painting one channel
## fades the seven others no matter which image each lives in, with no cross-image bookkeeping.
static func unit_slice(channel: int, image_index: int) -> Color:
	var unit := Color(0, 0, 0, 0)
	match clampi(channel, 0, 7) - image_index * 4:
		0: unit.r = 1.0
		1: unit.g = 1.0
		2: unit.b = 1.0
		3: unit.a = 1.0
	return unit


## Stamp a splat-channel paint into an RGBA weight image: pulls each touched pixel toward
## `unit` (a unit_slice) by strength*weight. The splat shader renormalizes, so lerping toward
## the unit colour reads as "painting grass over dirt". `square` swaps the round footprint for
## an axis-aligned square one. Returns the dirty Rect2i in pixels — geometry depends only on
## the kernel, so the two images of a paint stroke always report the same rect.
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


## Lay a straight ramp between two points: every pixel within half-width of the SEGMENT a->b
## is pulled toward the height linearly interpolated along that segment, so the result is a
## constant-grade surface a vehicle can drive. `a_h`/`b_h` are normalized heights; the pixel
## half-widths (rx, rz) are the brush radius mapped to each image axis.
##
## All the geometry is done in "brush units" — the pixel offset divided by the per-axis half-
## width. That is the world metric scaled uniformly by 1/radius (rx = radius/metres_per_px_x
## and likewise for z), so projecting and measuring across in those units is metrically
## honest even on a non-square terrain, where a world-circular brush is an image-space
## ellipse. Clamping the projection to [0,1] rounds the ends into caps instead of letting the
## ramp run to infinity. Unlike a sculpt stamp there are no neighbour reads, so no region
## snapshot is needed. Returns the tight dirty Rect2i (empty when nothing changed).
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

	# The segment vector in brush units, and its squared length (0 for a degenerate A == B
	# ramp, which then behaves as a flatten disk at a_h rather than dividing by zero).
	var bx := float(b_px.x - a_px.x) / maxf(rx, 1e-4)
	var bz := float(b_px.y - a_px.y) / maxf(rz, 1e-4)
	var len2 := bx * bx + bz * bz

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


## Flood a whole weight image with one unit_slice — the bucket fill. Strength and falloff
## have no say (a fill is a fill), so this is just Image.fill with the stamp's dirty-rect
## contract, which lets the brush push it through the same region-undo path as a stroke.
static func fill_splat(img: Image, unit: Color) -> Rect2i:
	img.fill(unit)
	return Rect2i(0, 0, img.get_width(), img.get_height())


## Average of a pixel and its 4 clamped neighbours (the smooth kernel), read from the region
## snapshot so the blur is independent of write order.
static func _avg(src: Image, x: int, y: int, w: int, h: int) -> float:
	var acc := src.get_pixel(x, y).r
	var n := 1.0
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		acc += src.get_pixel(clampi(x + d.x, 0, w - 1), clampi(y + d.y, 0, h - 1)).r
		n += 1.0
	return acc / n
