@tool
class_name RailProfile
extends RoadProfile
## Rail cross-section for RoadPath: a ballast trapezoid with two raised rail ribs at
## +/- gauge/2. A rail IS a RoadPath with this profile — Draw, Drape, Smooth, Conform,
## the fold guard and the bake all work on it untouched — so this subclasses RoadProfile
## (RoadPath.profile is typed to it) and overrides only the three fns that describe the
## surface. Flat colors, no textures (the Kenney low-poly bar).
##
## Geometry is measured, not guessed: the Kenney train kit's railroad-rail-straight has
## its rail verts at x = +/-0.25 and +/-0.35 (ribs 0.10 wide, centres +/-0.30 = gauge
## 0.60) on a 1.0-wide bed, and the loco is 1.32 wide. At the kit's chosen world scale
## 2.4 that is gauge 1.44 m — standard gauge 1.435 to within a centimetre — and a 3.17 m
## wide loco. See kit/roads/rail_profile.tres for the preset those numbers feed.
##
## INHERITED PROPERTIES THAT DO NOTHING HERE: lane_width, edge_line_width, shoulder_width
## (the deck is described by gauge / rail_width / ballast_half_width instead, and
## paved_half_width() is overridden to return ballast_half_width). Everything else keeps
## its inherited meaning: drop_run/edge_drop ARE the ballast shoulder, splat_channel is
## what "Paint splat under road" writes under the sleepers (7 = Gravel), and base_depth
## > 0 gives a rail bridge for free.

## Material slots, index-matched to materials(). Deliberately the SAME integers as the
## parent's SURFACE/EDGE_LINE so anything that indexes materials() by slot (RoadPath's
## ribbon_surfaces) cannot get a surprise.
const SLOT_BALLAST := RoadProfile.SLOT_SURFACE
const SLOT_RAIL := RoadProfile.SLOT_EDGE_LINE

## Degenerate-strip floor. Unlike the parent's lateral-only test this is applied to BOTH
## axes, because a rail's rib walls are vertical (zero lateral extent) and must survive.
const MIN_STRIP := 0.0001

@export_group("Rail")
## Distance between the two rail centrelines. 1.44 = standard gauge at the kit's scale.
@export var gauge := 1.44:
	set(value):
		gauge = value
		emit_changed()
## Width of one rail rib (the visible railhead).
@export var rail_width := 0.24:
	set(value):
		rail_width = value
		emit_changed()
## How far the rail ribs stand above the ballast top.
@export var rail_height := 0.12:
	set(value):
		rail_height = value
		emit_changed()
## Half the flat ballast top, outside which the drop skirt starts. Wide enough that the
## consist sits fully on the bed (a 3.17 m loco wants at least 1.6 here).
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


## Duck-typing marker: RoadPath's rail API and the road panel's Rail checkbox detect a
## rail by has_method(), never by class_name (the whole kit's contract).
func is_carlito_rail_profile() -> bool:
	return true


## Left-to-right breakpoints with two rib bumps, then the same {points, mats} contract
## the extruder consumes:
##
##   skirt  bed   [rib]        between rails       [rib]   bed  skirt
##                 __                                __
##   ___/‾‾‾‾‾‾‾‾‾|  |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|  |‾‾‾‾‾‾‾‾‾\___
##
## Winding comes out right for free: RoadBuilder.extrude's face normal is the segment
## direction rotated +90 degrees in the (lateral, y) plane, so a single left-to-right
## traversal gives bed-up, rib OUTER walls facing outward and rib INNER walls facing the
## track centre — the same reason the parent's bridge base walks its box in one go.
func cross_section() -> Dictionary:
	var g := maxf(gauge, MIN_STRIP)
	var w := maxf(rail_width, 0.0)
	var h := maxf(rail_height, 0.0)
	var d := maxf(drop_run, 0.0)
	var xi := maxf(g * 0.5 - w * 0.5, 0.0)          # rib inner lateral
	var xo := g * 0.5 + w * 0.5                     # rib outer lateral
	var b := maxf(ballast_half_width, xo)           # bed never narrower than the rails
	# 10 core breakpoints (bed edge, rib, between rails, rib, bed edge) = 9 strips; a
	# non-zero drop_run wraps one more point and one more strip around each end. A zero
	# drop_run removes the skirt entirely (the parent's rule) instead of leaving a
	# vertical wall standing at the bed edge — the both-axes filter below would keep it.
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
		# Both axes: the parent drops strips on lateral extent alone, which would delete
		# every rib wall (they are vertical by construction).
		if absf(xs[i + 1] - xs[i]) <= MIN_STRIP and absf(ys[i + 1] - ys[i]) <= MIN_STRIP:
			continue
		if points.is_empty():
			points.append(Vector2(xs[i], ys[i]))
		points.append(Vector2(xs[i + 1], ys[i + 1]))
		mats.append(slots[i])
	# Bridge base (base_depth > 0) rides the parent's box exactly as it does for roads:
	# the polyline continues around a box below the outermost points. Reuse it verbatim.
	if base_depth > 0.0 and points.size() >= 2:
		var left := points[0]
		var right := points[points.size() - 1]
		points.append(Vector2(right.x, right.y - base_depth))
		points.append(Vector2(left.x, left.y - base_depth))
		points.append(left)
		mats.append_array(PackedInt32Array([SLOT_BASE, SLOT_BASE, SLOT_BASE]))
	return {"points": points, "mats": mats}


## Slot index -> Material. Slots 2/3 (the parent's SHOULDER/BASE) keep their positions so
## the array stays index-compatible; only BASE is reachable, via base_depth.
func materials() -> Array:
	return [ballast_material, rail_material, null, base_material]


## The flattened band Conform targets: the ballast top, not the parent's lane arithmetic.
func paved_half_width() -> float:
	return maxf(ballast_half_width, gauge * 0.5 + maxf(rail_width, 0.0) * 0.5)
