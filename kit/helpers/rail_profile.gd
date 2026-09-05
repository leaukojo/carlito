@tool
class_name RailProfile
extends RoadProfile
## Rail cross-section for RoadPath: a ballast trapezoid with two raised rail ribs at
## +/- gauge/2. A rail IS a RoadPath with this profile, so this subclasses RoadProfile
## and overrides only the three fns that describe the surface. Flat colors, no textures.
## Kenney train kit rail centres are +/-0.30 (gauge 0.60); at world scale 2.4 that is 1.44 m.
## Inherited lane_width/edge_line_width/shoulder_width do nothing here (gauge/rail_width/
## ballast_half_width describe the deck instead); drop_run/edge_drop ARE the ballast
## shoulder, splat_channel paints under the sleepers, base_depth > 0 gives a rail bridge.

## Material slots, index-matched to materials(). Same integers as the parent's SURFACE/EDGE_LINE.
const SLOT_BALLAST := RoadProfile.SLOT_SURFACE
const SLOT_RAIL := RoadProfile.SLOT_EDGE_LINE

## Degenerate-strip floor, applied to both axes (rib walls are vertical and must survive).
const MIN_STRIP := 0.0001

@export_group("Rail")
## Distance (m) between the two rail centrelines. 1.44 = standard gauge at the kit's scale.
@export var gauge := 1.44:
	set(value):
		gauge = value
		emit_changed()
## Width (m) of one rail rib (the visible railhead).
@export var rail_width := 0.24:
	set(value):
		rail_width = value
		emit_changed()
## Height (m) the rail ribs stand above the ballast top.
@export var rail_height := 0.12:
	set(value):
		rail_height = value
		emit_changed()
## Half-width (m) of the flat ballast top. A 3.17 m loco wants at least 1.6 here.
@export var ballast_half_width := 1.8:
	set(value):
		ballast_half_width = value
		emit_changed()
@export var ballast_material: Material:
	set(value):
		ballast_material = value
		emit_changed()
@export var rail_material: Material:
	set(value):
		rail_material = value
		emit_changed()


## Duck-typing marker: RoadPath's rail API and the Rail checkbox detect via has_method().
func is_carlito_rail_profile() -> bool:
	return true


## Left-to-right breakpoints with two rib bumps, the same {points, mats} contract the
## extruder consumes:
##
##   skirt  bed   [rib]        between rails       [rib]   bed  skirt
##                 __                                __
##   ___/‾‾‾‾‾‾‾‾‾|  |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|  |‾‾‾‾‾‾‾‾‾\___
func cross_section() -> Dictionary:
	var g := maxf(gauge, MIN_STRIP)
	var w := maxf(rail_width, 0.0)
	var h := maxf(rail_height, 0.0)
	var d := maxf(drop_run, 0.0)
	var xi := maxf(g * 0.5 - w * 0.5, 0.0)          # rib inner lateral
	var xo := g * 0.5 + w * 0.5                     # rib outer lateral
	var b := maxf(ballast_half_width, xo)           # bed never narrower than the rails
	var skirt := d > MIN_STRIP
	var xs := PackedFloat32Array([-b, -xo, -xo, -xi, -xi, xi, xi, xo, xo, b])
	var ys := PackedFloat32Array([0, 0, h, h, 0, 0, h, h, 0, 0])
	var slots := PackedInt32Array([SLOT_BALLAST,
			SLOT_RAIL, SLOT_RAIL, SLOT_RAIL,
			SLOT_BALLAST,
			SLOT_RAIL, SLOT_RAIL, SLOT_RAIL,
			SLOT_BALLAST])
	if skirt:
		xs.insert(0, -(b + d))
		ys.insert(0, -edge_drop)
		slots.insert(0, SLOT_BALLAST)
		xs.append(b + d)
		ys.append(-edge_drop)
		slots.append(SLOT_BALLAST)

	var points := PackedVector2Array()
	var mats := PackedInt32Array()
	for i in slots.size():
		if absf(xs[i + 1] - xs[i]) <= MIN_STRIP and absf(ys[i + 1] - ys[i]) <= MIN_STRIP:
			continue
		if points.is_empty():
			points.append(Vector2(xs[i], ys[i]))
		points.append(Vector2(xs[i + 1], ys[i + 1]))
		mats.append(slots[i])
	if base_depth > 0.0 and points.size() >= 2:
		var left := points[0]
		var right := points[points.size() - 1]
		points.append(Vector2(right.x, right.y - base_depth))
		points.append(Vector2(left.x, left.y - base_depth))
		points.append(left)
		mats.append_array(PackedInt32Array([SLOT_BASE, SLOT_BASE, SLOT_BASE]))
	return {"points": points, "mats": mats}


## Slot index -> Material. Slots 2/3 keep the parent's SHOULDER/BASE positions.
func materials() -> Array:
	return [ballast_material, rail_material, null, base_material]


func paved_half_width() -> float:
	return maxf(ballast_half_width, gauge * 0.5 + maxf(rail_width, 0.0) * 0.5)
