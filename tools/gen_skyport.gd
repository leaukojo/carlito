extends Node
## Author level 6, "Skyport" (the quadcopter playground): terrain, splat, roads and scene all
## come from here, and a re-run overwrites all of it. `sats`/`agl` are the only two contract
## signals a level can move; it also carries the WindField, the CurrentField and the game's one
## real water column (SEA_Y), which the boat's depth instrument has nowhere else to read. Canyon
## walls are sized off the drone's own sky-ray cone (W/D, see REACHES) — never make the canyon a
## trigger volume. Chain recorded in src/levels/island/level_6/level_6_gen.json (tools/CLAUDE.md).
##
## EVERYTHING IN THE WATER DERIVES FROM SEA_Y, never a literal waterline: the slipway apron
## (_ramp_x_at_y), the shoal crest, the channel marks and the measured leg all move when the sea
## does. `-- scaffold` runs _report_water(), which CHECKS the boat playground rather than
## claiming it: the corridors below were measured off the heightmap, and a sculpt that moves
## them fails the stage instead of shipping a channel that runs over the bar.
## No scatter in this level, so no stale-ground bake gate applies.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

const DIR := "res://src/levels/island/level_6"
const LEVEL_PATH := DIR + "/level_6.tscn"
const TITLE := "Level 6 - Skyport"

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")

# --- the island ------------------------------------------------------------------------
const SIZE := 512.0            ## world extent (X and Z), matching the other islands
const HEIGHT := 51.0           ## white-pixel amplitude; 765/15, so 3 m levels store exactly
## A sample is [0,1] over the terrain's Y and _norm clamps, so the seabed floors at 0 whatever
## _floor_y asks for: this IS the basin depth. Ceiling 6.6 — _repaint walks from REACHES[0].x,
## where _floor_y is 6.6, and skips columns under the sea, so a higher sea drops the westernmost
## reach's paint; Y_FLOOR (9) is where it floods the gorge outright.
const SEA_Y := 6.0
const SEA_DEPTH := SEA_Y + 3.0   ## kill box, measured DOWN: it must reach the basin floor at 0
## classify_splat's sand weight crosses 0.5 — the line you SEE — at 1.25x sand_height. 7.0 puts it
## at 8.75: 2.75 m of dry beach, and under the canyon bowl and coastal shelf at 9.
const SAND_HEIGHT := (SEA_Y + 2.75) / 1.25
const GEN_SEED := 60613
const FEATURE_SCALE := 260.0
const OCTAVES := 4
const FALLOFF_START := 0.72
const FALLOFF_END := 0.94
const COAST_ROUGHNESS := 0.45
const TERRACE_LEVELS := 3

## Every authored elevation sits on the 3 m lattice the road grid and the terrace bands use.
const Y_APRON := 18.0          ## home: spawns, tower course, runway
const Y_MESA_A := 24.0
const Y_MESA_B := 30.0
const Y_HIGHLAND := 42.0       ## the mesa the canyon is cut into — also the canyon RIM
const Y_FLOOR := 9.0           ## the canyon floor
const CANYON_D := Y_HIGHLAND - Y_FLOOR   ## 33 m: the D in every W/D below

const FLATTEN_MARGIN := 18.0   ## blend ring outside a stamped flat

# Flats, world XZ. Rect2 = (x_min, z_min, width, depth).
const HIGHLAND := Rect2(-175.0, -130.0, 320.0, 100.0)
const MESA_B := Rect2(-110.0, 20.0, 60.0, 50.0)
const MESA_A := Rect2(30.0, 10.0, 70.0, 55.0)
const APRON_SHELF := Rect2(-120.0, 100.0, 270.0, 60.0)

# --- the canyon --------------------------------------------------------------------------
const CANYON_Z := -85.0        ## centreline; the canyon runs along X
## Half-width against world X, piecewise smoothstepped between control points, so each REACH is
## a place you can hover and read a steady number.
const REACHES: Array[Vector2] = [
	Vector2(-175.0, 34.0),   # the bowl: wide enough to read as open sky, 9 of 16
	Vector2(-135.0, 34.0),
	Vector2(-125.0, 30.0),   # R1  W/D 0.91 -> 9 sats
	Vector2(-100.0, 30.0),
	Vector2(-90.0, 20.0),    # R2  W/D 0.61 -> 7 sats, hdop climbing
	Vector2(-65.0, 20.0),
	Vector2(-55.0, 14.0),    # R3  the `sats` bar on its warn threshold, still a 3D fix
	Vector2(-30.0, 14.0),
	Vector2(-20.0, 11.0),    # R4  2D fix: LOITER and RTL refused, failsafe reads GPS_LOST
	Vector2(5.0, 13.0),
	Vector2(15.0, 5.0),      # R5  W/D 0.15 -> 2 sats, and 0 under the viaduct's lid
	Vector2(115.0, 5.0),
	Vector2(118.0, 0.0),     # the head wall closes it
]
## West of the bowl the floor keeps descending, so the mouth floods into a fjord the boat can
## sail into; the beach where it dries out is where the car turns.
const INLET_X0 := -160.0
const INLET_X1 := -235.0
const INLET_Y := -3.0

## The slipway: a ramp off the apron's east end into the sea, stamped into the terrain and
## painted gravel (not a RoadPath). Where the boat and the car meet.
## No drivable descent into the canyon: measured, 33 m of drop needs ~165 m of run at a
## car-climbable grade but the bowl is only 70 m long, so any ramp breaches a walled reach's rim
## (one test cut left a rim 6 m short, 18% off that reach's W/D).
const SLIP_RAMP_A := Vector3(148.0, Y_APRON, 132.0)
const SLIP_RAMP_B := Vector3(198.0, -1.0, 132.0)
const RAMP_HALF_WIDTH := 8.0

# --- the boat playground ---------------------------------------------------------------
## The seabed is the flat pan `island_falloff` clamps to 0, so over the whole basin the sounder
## reads one number and the shoal warn can never fire. THE BAR IS WHAT MAKES 'depth' A READING:
## a drying sandbar off the slipway, west of the buoyed channel, so a boat that holds the marks
## stays in 5.6 m and one that cuts inside them watches the number fall through the shoal alarm
## and then ground. Crest 0.4 m proud of the sea, so the bar is VISIBLE as well as audible —
## and it needs no splat work, because classify_splat calls anything under 1.25 * SAND_HEIGHT
## sand already.
const SHOAL_CENTRE := Vector2(204.0, 190.0)   ## world XZ
const SHOAL_HALF := Vector2(10.0, 14.0)       ## the flat crest's half-extents
## The shoaling ring outside the crest: 20 m of blend takes the sounding from 5.6 m to aground
## over about four seconds at hull speed. A tighter ring reads as a cliff, not a shoal.
const SHOAL_MARGIN := 20.0
const SHOAL_CREST := SEA_Y + 0.4
## The buoyed channel: a straight north-south fairway down the east basin, measured flat at the
## pan depth over its whole length. Its west marks stand where the shoal's blend ring begins,
## which is the whole point of marking a channel.
const CHANNEL_X := 234.0
const CHANNEL_Z0 := 140.0    ## off the slipway
const CHANNEL_Z1 := 240.0    ## onto the measured leg below
const CHANNEL_HALF := 8.0    ## marks either side of the centreline
const CHANNEL_SPACING := 25.0
## The measured leg. NOT a measured mile — that is 1852 m and this map is 512 m across — but the
## same instrument: two marks a known distance apart, so STW against SOG is a stopwatch instead
## of a claim. It runs east-west, within 20 degrees of the tide's own set, so the whole drift
## lands along the track rather than across it: the log reads the same both ways and the clock
## does not.
const MILE_Z := 246.0
const MILE_X0 := 40.0
const MILE_X1 := 240.0
const MILE_HALF := 8.0
## The least water a fairway or a mark may stand in. The channel runs 30 m off a bar that dries,
## so a nudge to SHOAL_CENTRE or CHANNEL_X puts a mark on the sand or the fairway over it — and
## that is a level which reads as authored and sails as a trap. _report_water FAILS the scaffold
## on it rather than printing a number nobody re-reads.
const NAVIGABLE_MIN := 1.5

# --- roads --------------------------------------------------------------------------------
const ASPHALT_PROFILE := "res://kit/roads/asphalt_profile.tres"
const CONFORM_EPSILON := 0.05
const CONFORM_FALLOFF := 8.0
const MAX_SEG_LEN := 6.0
const MAX_SEG_ANGLE := 6.0
## RoadPath.SPLAT_PAINT_INSET, reproduced — that node's paint button is editor-only.
const SPLAT_PAINT_INSET := 1.0

## RoadLoop: apron shelf, west and south onto the highland, east along the north rim, ending
## pointed at the viaduct. Asphalt roads keep clear of the canyon rim by (half-width +
## conform_falloff) = 14 m — Conform flattens terrain to the deck across that ring, so a road
## any nearer fills the wall back in (measured: too close left a wall 5 m short, 15% off W/D).
## Only the viaduct sits over the slot; a bridge profile is exempt from Conform by design.
const LOOP_POINTS: Array[Vector3] = [
	Vector3(100.0, Y_APRON, 156.0),
	Vector3(20.0, Y_APRON, 158.0),
	Vector3(-60.0, Y_APRON, 154.0),
	Vector3(-116.0, Y_APRON, 128.0),
	Vector3(-150.0, 21.0, 96.0),
	Vector3(-160.0, 25.0, 60.0),
	Vector3(-142.0, 29.0, 28.0),
	Vector3(-104.0, 32.0, 12.0),
	Vector3(-60.0, 35.0, 4.0),
	Vector3(-34.0, 38.0, -10.0),
	Vector3(-20.0, Y_HIGHLAND, -32.0),
	Vector3(-10.0, Y_HIGHLAND, -52.0),
]
## Viaduct: a bridge_profile ribbon whose straight middle lies on the slot's centreline for
## 90 m, closed into a solid box with underside and end caps; its 12.1 m deck rests on both
## 5 m rims, so it's a lid (not a span) and the only geometry taking the last two satellites.
const VIADUCT_POINTS: Array[Vector3] = [
	Vector3(-10.0, Y_HIGHLAND, -52.0),
	Vector3(26.0, Y_HIGHLAND, CANYON_Z),
	Vector3(104.0, Y_HIGHLAND, CANYON_Z),
	Vector3(140.0, Y_HIGHLAND, -52.0),
]
## RimRoad: off the highland's east shoulder, down through mesa A, out to the slipway.
const RIM_POINTS: Array[Vector3] = [
	Vector3(140.0, Y_HIGHLAND, -52.0),
	Vector3(152.0, Y_HIGHLAND, -34.0),
	Vector3(158.0, 38.0, -8.0),
	Vector3(146.0, 34.0, 22.0),
	Vector3(120.0, 30.0, 48.0),
	Vector3(104.0, 26.0, 72.0),
	Vector3(100.0, 22.0, 92.0),
	Vector3(92.0, Y_APRON, 132.0),
	Vector3(100.0, Y_APRON, 156.0),
]

# --- splat --------------------------------------------------------------------------------
const CH_DIRT := 1      ## the canyon floor — brown against the grey walls, so the gorge reads
const CH_ROCK := 3      ## the canyon walls: painted, not left to auto-splat — see _repaint
## Half-width (m) of the rock band painted along each canyon rim.
const WALL_BAND := 3.0
const CH_PAD := 4       ## splatmap2.R — the marked landing/payload decks, this level's own
const CH_GRAVEL := 7
const CHANNEL_NAMES: Array[String] = [
	"Grass", "Dirt", "Sand", "Rock", "Pad", "Snow", "Asphalt", "Gravel",
]
const CHANNEL_GRIP: Array[float] = [0.8, 0.7, 0.6, 0.7, 0.95, 0.75, 1.0, 0.85]
## Safety yellow: a marked pad has to read as a MARKING against grass, rock and asphalt
## alike, and blend_sharpness 8 gives it a hard border for free.
const PAD_COLOR := Color(0.95, 0.78, 0.12)

# --- pads (12 m squares of CH_PAD; the GridMap decks land on the same centres) -------------
const PAD_SIZE := 12.0
const PAD_APRON := Vector2(30.0, 126.0)       ## payload PICKUP, east of the apron deck
const PAD_MESA_A := Vector2(65.0, 38.0)       ## payload DROP
const PAD_MESA_B := Vector2(-80.0, 45.0)
## The agl demo, on the south rim of reach R3 where no road runs. Only X is declared; Z derives
## from _half_width so the pad's north edge is the rim itself however the reach is retuned (a
## literal Z drifted 3 m off the lip the first time R3 was narrowed).
const PAD_RIM_X := -42.0
const PAD_SLIP := Vector2(130.0, 132.0)       ## payload DROP, beside the slipway

# --- spawns --------------------------------------------------------------------------------
const SPAWN_LAND := Vector3(-24.0, Y_APRON, 126.0)
## The plane wants a run, so it gets the shelf's whole southern strip: 260 m of flat at
## z = 104, south of the apron deck and north of nothing.
const SPAWN_PLANE := Vector3(-110.0, Y_APRON, 104.0)
const SPAWN_WATER := Vector3(212.0, SEA_Y + 0.3, 132.0)   ## the 0.3 is spawn clearance

# --- props -----------------------------------------------------------------------------------
## Nodes the `props` stage OWNS: a re-run replaces exactly these. The three RoadPaths belong
## to `scaffold` and are deliberately absent.
const OWNED_NODES: Array[String] = [
	"RoadsTiles", "RacingProps", "CommercialProps", "WatercraftProps",
]
const ROADS_MESHLIB := "res://kit/palettes/roads.meshlib"
const APRON_TILE := "tile-low"           ## plain 12 m concrete slab, 0.24 m deck
const MAST_PREFAB := "res://kit/prefabs/racing/flagCheckers.tscn"        ## 15.0 m mast
const GATE_PREFAB := "res://kit/prefabs/racing/overhead.tscn"            ## 15.4 m gantry, 6.6 m clear
const TOWER_PREFAB := "res://kit/prefabs/commercial/building-skyscraper-a.tscn"  ## 25.9 m
const GARAGE_PREFAB := "res://kit/prefabs/racing/pitsGarage.tscn"        ## 8.4 m
const MARKER_PREFAB := "res://kit/prefabs/racing/flagCheckersSmall.tscn" ## 3.6 m
const CARGO_PREFAB := "res://kit/prefabs/watercraft/cargo-container-a.tscn"
## The pickable payloads are not kit pieces (a crate under AuthoringRoot would weld into bake
## scenery); they sit at the level root instead, as real RigidBody3Ds the drone's hardpoint
## latches onto (src/levels/base/cargo_payload.gd). Crates, not the slipway's shipping
## containers: a 0.858 m / 2 kg box is a load the 1.2 m / 5 kg drone visibly sags under.
const PAYLOAD_SCENE := "res://src/levels/base/cargo_payload.tscn"
const SLIP_PREFAB := "res://kit/prefabs/watercraft/ramp-wide.tscn"
## Channel marks. Both are `collision_mode: "none"`, so they add no baked body and a boat that
## hits one is told by the depth, not by a crash. Their recipe aligns them "raw" — the artist's
## own waterline is the origin — which is why they are placed by _place_afloat rather than by
## _place, whose whole job is standing a piece's measured BASE on the ground.
const BUOY_PREFAB := "res://kit/prefabs/watercraft/buoy.tscn"
const MILE_PREFAB := "res://kit/prefabs/watercraft/buoy-flag.tscn"

const APRON_DECK_CENTER := Vector2(-24.0, 126.0)
const APRON_CELLS_X := 4
const APRON_CELLS_Z := 3
## The mast slalom, on the highland: clear of the north edge, of every road and of the rim.
const COURSE_X0 := 0.0
const COURSE_SPACING := 11.0
const COURSE_MASTS := 12
const COURSE_Z := -48.0
const COURSE_OFFSET := 8.0
## Gates sit BETWEEN masts (half-integer slots): the gantry's legs stand 7.7 m either side of
## its centre, which is where a mast would be.
const GATE_SLOTS: Array[float] = [2.5, 6.5, 10.5]
const TOWER_XZ := Vector2(-95.0, 30.0)   ## on mesa B: roof at 55.9 m
const GARAGE_XZ := Vector2(-70.0, 126.0) ## on the apron, west of the deck: roof at 26.4 m
const CARGO_XZ := Vector2(46.0, 120.0)
const CARGO_COUNT := 4
## Three crates on the PICKUP pad (PAD_APRON), one per DROP pad there is somewhere to take them
## to. Spaced so the hook's capture ray can only ever see one of them at a time.
const PAYLOAD_COUNT := 3
const PAYLOAD_SPACING := 3.0

# --- wind -----------------------------------------------------------------------------------
## Across the mast slalom (runs along X), so the course is a crosswind exercise. At 5 m/s the
## drone's PD position controller holds a bounded ~1.7 m offset downwind, gusting to ~2.7 m —
## felt on a hover, still easy to fly. One level-wide vector plus deterministic gust; no wind
## zones here.
const WIND_DIRECTION_DEG := 200.0
const WIND_SPEED := 5.0
const WIND_GUST := 3.0
const WIND_SEED := 60613

# --- current --------------------------------------------------------------------------------
## Sets across the mouth of the fjord, so leaving the slipway puts a crab angle between COG and
## HDG straight away; the tide reverses over four minutes.
const CURRENT_SET_DEG := 110.0
const CURRENT_DRIFT := 1.5
const CURRENT_PERIOD_S := 240.0
const CURRENT_OFFSET_S := 60.0

# --- working state (world <-> pixel) ---------------------------------------------------------
var _iw := 0
var _ih := 0
var _sx := 1.0
var _sz := 1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var stage := String(args[0]) if not args.is_empty() else "scaffold"
	var code := 0
	match stage:
		"scaffold":  # writes the images/curves/.tscn text; run --import after
			code = _scaffold()
		"props":  # opens the scaffolded scene, hangs GridMap decks + kit pieces off AuthoringRoot
			code = _props()
		"probe":  # measures sats/agl against the baked collision; run after bake_levels
			code = await _probe()
		_:
			printerr("[skyport] usage: -- scaffold | props | probe")
			code = 1
	get_tree().quit(code)


# ============================================================================ stage: scaffold


func _scaffold() -> int:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cells := int(SIZE) + 1
	_iw = cells
	_ih = cells
	_sx = float(cells - 1) / SIZE
	_sz = _sx

	var heights := TerrainGen.generate_heights(TerrainGen.Preset.ISLAND, GEN_SEED,
			FEATURE_SCALE, OCTAVES, FALLOFF_START, FALLOFF_END, cells, cells,
			float(TERRACE_LEVELS) * 3.0 / HEIGHT, 0.6, COAST_ROUGHNESS)

	# --- sculpt: flats first, then the cut through them, then the roads' own shelves -----
	_flatten(heights, HIGHLAND, Y_HIGHLAND)
	_flatten(heights, MESA_B, Y_MESA_B)
	_flatten(heights, MESA_A, Y_MESA_A)
	_flatten(heights, APRON_SHELF, Y_APRON)
	_carve_canyon(heights)
	_carve_ramp(heights, SLIP_RAMP_A, SLIP_RAMP_B)
	# Before the splat pass, so the bar is classified sand by height like any other beach.
	_shoal(heights)

	var loop_curve := _curve(LOOP_POINTS)
	var viaduct_curve := _curve(VIADUCT_POINTS)
	var rim_curve := _curve(RIM_POINTS)
	var asphalt := ResourceLoader.load(ASPHALT_PROFILE)
	if asphalt == null:
		printerr("[skyport] cannot load %s" % ASPHALT_PROFILE)
		return 1
	_conform(heights, loop_curve, asphalt)
	_conform(heights, rim_curve, asphalt)

	# --- splat: auto-classify, then repaint what this level's own surfaces need ----------
	var px := SIZE / float(cells - 1)
	var splat := TerrainGen.build_splatmap(heights, HEIGHT, px, px, SAND_HEIGHT, 24.0, 40.0)
	var splat2 := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	splat2.fill(Color(0, 0, 0, 0))
	_repaint(splat, splat2)
	_paint_road_splat(splat, splat2, loop_curve, asphalt)
	_paint_road_splat(splat, splat2, rim_curve, asphalt)

	# --- write -----------------------------------------------------------------------------
	if not _write_png(heights, "%s/level_6_island_height.png" % DIR):
		return 1
	if not _write_png(splat, "%s/level_6_island_splat.png" % DIR):
		return 1
	if not _write_png(splat2, "%s/level_6_island_splat2.png" % DIR):
		return 1
	var curves := {
		"level_6_loop_curve.tres": loop_curve,
		"level_6_viaduct_curve.tres": viaduct_curve,
		"level_6_rim_curve.tres": rim_curve,
	}
	for file_name: String in curves:
		var path := "%s/%s" % [DIR, file_name]
		if ResourceSaver.save(curves[file_name] as Curve3D, path) != OK:
			printerr("[skyport] cannot save %s" % path)
			return 1
	_write_text("%s/level_6_info.tres" % DIR, _info_text())
	_write_text("%s/level_6_wind.tres" % DIR, _wind_text())
	_write_text("%s/level_6_current.tres" % DIR, _current_text())
	_write_text(LEVEL_PATH, _scene_text())

	_report_road(loop_curve, "RoadLoop")
	_report_road(viaduct_curve, "Viaduct")
	_report_road(rim_curve, "RimRoad")
	_report_sats()
	if not _report_water(heights):
		return 1
	print("[skyport] scaffold done. Run --import, then `-- props`.")
	return 0


# ------------------------------------------------------------------------------- sculpting


## Flatten `rect` to `target_y` with a soft blend ring, using the square brush stamp. Falloff
## derives from the longer half-extent since the square brush measures one Chebyshev distance
## against per-axis radii (same reasoning as gen_farm_playground's _flatten).
func _flatten(img: Image, rect: Rect2, target_y: float, margin := FLATTEN_MARGIN) -> void:
	var half_x := rect.size.x * 0.5 + margin
	var half_z := rect.size.y * 0.5 + margin
	var falloff := margin / maxf(half_x, half_z)
	var c := rect.get_center()
	BrushOps.stamp_height(img, _px_x(c.x), _px_z(c.y), half_x * _sx, half_z * _sz,
			BrushOps.FLATTEN, 1.0, falloff, _norm(target_y), true)


## The sandbar off the slipway: the round brush's FLATTEN, exactly as the flats above use it and
## for the same reason — FLATTEN lerps toward a target and RAISE accumulates, so this one is the
## op a scaffold replay lands on the same bytes.
##
## FLATTEN LOWERS AS WELL AS RAISES, so the ellipse has to stay off the shore: every heightmap
## sample the round brush reaches is seabed well under SHOAL_CREST (the highest anywhere in its
## bounding box is a 7.0 m terrain sample at world x 175, z 160, and that one is outside the
## ellipse). Move SHOAL_CENTRE toward the coast and this stamp cuts the beach down to the crest.
func _shoal(img: Image) -> void:
	var half_x := SHOAL_HALF.x + SHOAL_MARGIN
	var half_z := SHOAL_HALF.y + SHOAL_MARGIN
	var falloff := SHOAL_MARGIN / maxf(half_x, half_z)
	BrushOps.stamp_height(img, _px_x(SHOAL_CENTRE.x), _px_z(SHOAL_CENTRE.y),
			half_x * _sx, half_z * _sz,
			BrushOps.FLATTEN, 1.0, falloff, _norm(SHOAL_CREST), false)


## The canyon, written straight into the working image (no "cut a tapering slot" brush exists,
## not worth growing the kit API for one feature). Walls are one cell of horizontal run: one
## cell per world unit makes a 33 m drop a near-vertical face at zero extra baked vertices,
## which is what makes this level's headline feature affordable.
func _carve_canyon(img: Image) -> void:
	for pxi in range(_px_x(INLET_X1), _px_x(REACHES[REACHES.size() - 1].x) + 1):
		var wx := _world_x(pxi)
		var w := _half_width(wx)
		if w <= 0.0:
			continue
		var nv := _norm(_floor_y(wx))
		for pzi in range(_px_z(CANYON_Z - w), _px_z(CANYON_Z + w) + 1):
			if img.get_pixel(pxi, pzi).r > nv:
				img.set_pixel(pxi, pzi, Color(nv, nv, nv))


## The car's descent into the bowl: one constant-grade ramp cut diagonally into the north
## wall with the terrain brush's own ramp stamp, exactly as level 1's haul ramp is cut.
func _carve_ramp(img: Image, a: Vector3, b: Vector3) -> void:
	BrushOps.stamp_ramp(img,
			Vector2i(_px_x(a.x), _px_z(a.z)), _norm(a.y),
			Vector2i(_px_x(b.x), _px_z(b.z)), _norm(b.y),
			RAMP_HALF_WIDTH * _sx, RAMP_HALF_WIDTH * _sz, 1.0, 0.4)


## Where the slipway ramp crosses world height `y`. The apron piece belongs at the waterline, and
## a literal X stops meaning that the first time SEA_Y moves.
func _ramp_x_at_y(y: float) -> float:
	var t := (SLIP_RAMP_A.y - y) / (SLIP_RAMP_A.y - SLIP_RAMP_B.y)
	return lerpf(SLIP_RAMP_A.x, SLIP_RAMP_B.x, clampf(t, 0.0, 1.0))


## Canyon half-width at world x: the REACHES table, smoothstepped between control points so
## each reach is a steady reading and the transitions are short. West of the bowl the mouth
## keeps the bowl's width all the way out to sea.
func _half_width(wx: float) -> float:
	var first := REACHES[0]
	var last := REACHES[REACHES.size() - 1]
	if wx > last.x:
		return 0.0
	if wx <= first.x:
		return first.y if wx >= INLET_X1 else 0.0
	for i in REACHES.size() - 1:
		var a := REACHES[i]
		var b := REACHES[i + 1]
		if wx > b.x:
			continue
		var t := clampf((wx - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		return lerpf(a.y, b.y, t * t * (3.0 - 2.0 * t))
	return 0.0


func _floor_y(wx: float) -> float:
	if wx >= INLET_X0:
		return Y_FLOOR
	return lerpf(Y_FLOOR, INLET_Y, clampf((INLET_X0 - wx) / (INLET_X0 - INLET_X1), 0.0, 1.0))


# --------------------------------------------------------------------------------- roads


func _curve(points: Array[Vector3]) -> Curve3D:
	var curve := Curve3D.new()
	for p in points:
		curve.add_point(p)
	for i in range(1, curve.point_count - 1):
		var h: Dictionary = RoadBuilder.smooth_handles(curve.get_point_position(i - 1),
				curve.get_point_position(i), curve.get_point_position(i + 1))
		curve.set_point_in(i, h["in"])
		curve.set_point_out(i, h["out"])
	return curve


## RoadPath._conform_terrain reproduced (editor-only, EditorUndoRedoManager) — a headless tool
## calls the pure core directly, same as tools/gen_rail_level.gd for level 5.
func _conform(heights: Image, curve: Curve3D, profile: Resource) -> void:
	var offsets := RoadBuilder.adaptive_offsets(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var fw: float = profile.call("full_half_width")
	var samples := PackedVector3Array()
	for o in offsets:
		var w := curve.sample_baked(o)
		samples.append(Vector3(w.x, w.z, _norm(w.y - CONFORM_EPSILON)))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-fw, 0), Vector2(fw, 0)]),
			PackedInt32Array([0]), offsets, false)
	var deck := PackedVector3Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck.append(Vector3(v.x, v.z, _norm(v.y - CONFORM_EPSILON)))
	var dirty := RoadBuilder.conform_heights(heights, samples, fw, CONFORM_FALLOFF,
			SIZE, SIZE, deck)
	if not dirty.has_area():
		printerr("[skyport] a conform changed nothing — the road missed the terrain")


## RoadPath._paint_splat reproduced, for the same reason and at the same INSET paved width,
## so a conformed road grips like asphalt instead of like the grass under its deck.
func _paint_road_splat(splat: Image, splat2: Image, curve: Curve3D, profile: Resource) -> void:
	var channel: int = profile.get("splat_channel")
	var pw: float = float(profile.call("paved_half_width")) - SPLAT_PAINT_INSET
	if pw <= 0.0:
		printerr("[skyport] profile too narrow to paint under")
		return
	var offsets := RoadBuilder.adaptive_offsets(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var samples := PackedVector2Array()
	for o in offsets:
		var w := curve.sample_baked(o)
		samples.append(Vector2(w.x, w.z))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-pw, 0), Vector2(pw, 0)]),
			PackedInt32Array([0]), offsets, false)
	var deck := PackedVector2Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck.append(Vector2(v.x, v.z))
	var images: Array[Image] = [splat, splat2]
	var units: Array[Color] = [
		BrushOps.unit_slice(channel, 0), BrushOps.unit_slice(channel, 1),
	]
	SplatPaint.paint_strip(images, units, samples, pw, SIZE, SIZE, deck)


# -------------------------------------------------------------------------------- painting


## Paint `rect` with `channel` at full strength and a hard edge into BOTH weight images. Full
## strength + hard edge is the kit's rule for a destructive paint: the shader pow-sharpens
## weights and grip_at sharpens identically, so this reads as a crisp low-poly border AND
## full surface grip, with none of the low-grip apron a feathered edge would leave.
func _paint(splat: Image, splat2: Image, rect: Rect2, channel: int) -> void:
	var c := rect.get_center()
	BrushOps.stamp_splat(splat, _px_x(c.x), _px_z(c.y),
			rect.size.x * 0.5 * _sx, rect.size.y * 0.5 * _sz,
			BrushOps.unit_slice(channel, 0), 1.0, 0.0, true)
	BrushOps.stamp_splat(splat2, _px_x(c.x), _px_z(c.y),
			rect.size.x * 0.5 * _sx, rect.size.y * 0.5 * _sz,
			BrushOps.unit_slice(channel, 1), 1.0, 0.0, true)


## Auto-splat ran after the sculpt, so flats already read grass and canyon walls read rock. What
## it cannot know is this level's own surfaces: the gravel floor/ramp and the CH_PAD decks.
func _repaint(splat: Image, splat2: Image) -> void:
	# Dirt floor then rock walls, one pixel column at a time to follow the taper exactly.
	#
	# The rock band is load-bearing, not cosmetic: auto-splat classifies from a central
	# difference, and a wall one cell wide has exactly one differing pixel row, so it painted a
	# single rock line with grass either side — a grass-to-rock fade down a 33 m cliff. A painted
	# band gives the crisp high-contrast border the low-poly look needs.
	for pxi in range(_px_x(REACHES[0].x), _px_x(REACHES[REACHES.size() - 1].x) + 1):
		var wx := _world_x(pxi)
		var w := _half_width(wx)
		if w <= 0.0 or _floor_y(wx) < SEA_Y:
			continue
		_stamp_both(splat, splat2, pxi, _px_z(CANYON_Z), 0.5, (w - 1.0) * _sz, CH_DIRT)
		for side: float in [-1.0, 1.0]:
			_stamp_both(splat, splat2, pxi, _px_z(CANYON_Z + side * w), 0.5,
					WALL_BAND * _sz, CH_ROCK)
	_paint_ramp(splat, splat2, SLIP_RAMP_A, SLIP_RAMP_B)
	for pad: Array in pads():
		_paint(splat, splat2, pad_rect(pad[0]), CH_PAD)


## One splat stamp into both weight images at a pixel centre (square, hard-edged, full
## strength). Each takes its own `unit_slice`, all-zero for the image its channel isn't in.
func _stamp_both(splat: Image, splat2: Image, cx: int, cz: int, rx: float, rz: float,
		channel: int) -> void:
	BrushOps.stamp_splat(splat, cx, cz, rx, rz, BrushOps.unit_slice(channel, 0), 1.0, 0.0, true)
	BrushOps.stamp_splat(splat2, cx, cz, rx, rz, BrushOps.unit_slice(channel, 1), 1.0, 0.0, true)


## The slipway's gravel, stamped along its centreline at the ramp half-width less a metre so
## the paint stays inside the cut rather than spilling onto the grass beside it.
func _paint_ramp(splat: Image, splat2: Image, a: Vector3, b: Vector3) -> void:
	var steps := 80
	var half := RAMP_HALF_WIDTH - 1.0
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		BrushOps.stamp_splat(splat, _px_x(p.x), _px_z(p.z), half * _sx, half * _sz,
				BrushOps.unit_slice(CH_GRAVEL, 0), 1.0, 0.0, false)
		BrushOps.stamp_splat(splat2, _px_x(p.x), _px_z(p.z), half * _sx, half * _sz,
				BrushOps.unit_slice(CH_GRAVEL, 1), 1.0, 0.0, false)


## The marked decks: [centre XZ, the ground Y it is painted on, is it a PAYLOAD target].
## Shared by the paint pass and the props stage so the yellow square and its corner flags can
## never land on different ground.
func pads() -> Array[Array]:
	return [
		[PAD_APRON, Y_APRON, true],
		[PAD_MESA_A, Y_MESA_A, true],
		[PAD_SLIP, Y_APRON, true],
		[PAD_MESA_B, Y_MESA_B, false],
		[Vector2(PAD_RIM_X, CANYON_Z - _half_width(PAD_RIM_X) - PAD_SIZE * 0.5),
			Y_HIGHLAND, false],
	]


func pad_rect(centre: Vector2) -> Rect2:
	return Rect2(centre.x - PAD_SIZE * 0.5, centre.y - PAD_SIZE * 0.5, PAD_SIZE, PAD_SIZE)


# --------------------------------------------------------------------------------- reports


## Seabed elevation at a world XZ, straight off the working image — the same sample
## HeightmapTerrain.height_at will return once this is written.
func _seabed(img: Image, wx: float, wz: float) -> float:
	return img.get_pixel(_px_x(wx), _px_z(wz)).r * HEIGHT


## The boat playground's numbers, MEASURED off the sculpted image rather than asserted from the
## constants above, and a GATE rather than a report: false fails the scaffold. Water depths are
## below the SURFACE; the sounder reads under-keel clearance, which is this less the hull's own
## float_depth, so the shoal alarm bites a little sooner than these figures read. A dry bar is
## reported as a negative depth on purpose — it is the one that has to be visible.
func _report_water(img: Image) -> bool:
	var ok := true
	print("[skyport] sea y %.1f, shoal crest y %.1f (%.1f m proud)" % [
			SEA_Y, SHOAL_CREST, SHOAL_CREST - SEA_Y])
	var dry := 0
	for wx in range(int(SHOAL_CENTRE.x - 40.0), int(SHOAL_CENTRE.x + 40.0) + 1):
		if _seabed(img, float(wx), SHOAL_CENTRE.y) >= SEA_Y:
			dry += 1
	print("[skyport] sandbar at x %.0f, z %.0f: %d m of dry crest across its centreline" % [
			SHOAL_CENTRE.x, SHOAL_CENTRE.y, dry])
	if dry <= 0:
		printerr("[skyport] the sandbar never breaks the surface — nothing to see and no ground to hit")
		ok = false
	print("[skyport]   across the bar, water below the surface (x, m):")
	var across := ""
	for wx in range(int(SHOAL_CENTRE.x - 40.0), int(SHOAL_CENTRE.x + 41.0), 8):
		across += "  %d:%+.1f" % [wx, SEA_Y - _seabed(img, float(wx), SHOAL_CENTRE.y)]
	print("[skyport]  %s" % across)

	var worst := INF
	var worst_mark := INF
	var down := ""
	for wz in range(int(CHANNEL_Z0), int(CHANNEL_Z1) + 1):
		worst = minf(worst, SEA_Y - _seabed(img, CHANNEL_X, float(wz)))
		worst_mark = minf(worst_mark, SEA_Y - _seabed(img, CHANNEL_X - CHANNEL_HALF, float(wz)))
		worst_mark = minf(worst_mark, SEA_Y - _seabed(img, CHANNEL_X + CHANNEL_HALF, float(wz)))
	for wz in range(int(CHANNEL_Z0), int(CHANNEL_Z1) + 1, 20):
		down += "  %d:%+.1f" % [wz, SEA_Y - _seabed(img, CHANNEL_X - CHANNEL_HALF - 14.0, float(wz))]
	print("[skyport] channel x %.0f, z %.0f..%.0f (%.0f m): least depth %.2f m, at the marks %.2f m" % [
			CHANNEL_X, CHANNEL_Z0, CHANNEL_Z1, CHANNEL_Z1 - CHANNEL_Z0, worst, worst_mark])
	print("[skyport]   14 m INSIDE the west marks (z, m): %s" % down)
	if minf(worst, worst_mark) < NAVIGABLE_MIN:
		printerr("[skyport] the channel or a mark stands in %.2f m — under NAVIGABLE_MIN %.1f" % [
				minf(worst, worst_mark), NAVIGABLE_MIN])
		ok = false

	var leg := INF
	for wx in range(int(MILE_X0), int(MILE_X1) + 1):
		leg = minf(leg, SEA_Y - _seabed(img, float(wx), MILE_Z))
	print("[skyport] measured leg z %.0f, x %.0f..%.0f (%.0f m): least depth %.2f m" % [
			MILE_Z, MILE_X0, MILE_X1, MILE_X1 - MILE_X0, leg])
	print("[skyport]   set %.0f deg at %.1f m/s peak, %.0f deg off the leg — the drift is along it" % [
			CURRENT_SET_DEG, CURRENT_DRIFT, absf(CURRENT_SET_DEG - 90.0)])
	if leg < NAVIGABLE_MIN:
		printerr("[skyport] the measured leg crosses %.2f m — under NAVIGABLE_MIN %.1f" % [
				leg, NAVIGABLE_MIN])
		ok = false
	# The gates stand off the leg, and the whole leg has to stay ON the terrain: outside it the
	# sounder publishes its -1 and a timed run would read as no bottom rather than as deep water.
	for gate_x: float in [MILE_X0, MILE_X1]:
		for gate_z: float in [MILE_Z - MILE_HALF, MILE_Z + MILE_HALF]:
			if absf(gate_x) > SIZE * 0.5 or absf(gate_z) > SIZE * 0.5:
				printerr("[skyport] a measured-leg gate at %.0f,%.0f is off the terrain — no sounding there" % [
						gate_x, gate_z])
				ok = false
			elif SEA_Y - _seabed(img, gate_x, gate_z) < NAVIGABLE_MIN:
				printerr("[skyport] a measured-leg gate at %.0f,%.0f stands in %.2f m" % [
						gate_x, gate_z, SEA_Y - _seabed(img, gate_x, gate_z)])
				ok = false
	return ok


## The canyon's design numbers, evaluated against the drone's own sky-ray pattern (not
## remembered), so a change to SKY_RAYS/SKY_MASK_DEG moves this table with it. A lower bound;
## `-- probe` measures the real thing.
func _report_sats() -> void:
	var pattern := DroneSensors.sky_pattern(DroneSensors.SKY_RAYS, DroneSensors.SKY_MASK_DEG)
	print("[skyport] canyon: rim y %.0f, floor y %.0f, D %.0f m" % [
			Y_HIGHLAND, Y_FLOOR, CANYON_D])
	print("[skyport] PREDICTED from W/D, walls modelled as infinitely long — a LOWER BOUND on")
	print("[skyport] sats. `-- probe` measures the real thing against the baked collision.")
	print("[skyport]   %-12s %5s %6s %5s %6s  %s" % ["where", "W", "W/D", "sats", "hdop", "fix"])
	for probe: float in [-150.0, -112.0, -78.0, -42.0, -8.0, 60.0]:
		_report_probe(pattern, probe, Y_FLOOR, false)
	# Under the lid, and 12 m up at the warn-line reach.
	_report_probe(pattern, 60.0, Y_FLOOR, true)
	_report_probe(pattern, -42.0, Y_FLOOR + 12.0, false)


func _report_probe(pattern: PackedVector3Array, wx: float, craft_y: float,
		lidded: bool) -> void:
	var w := _half_width(wx)
	var d := Y_HIGHLAND - craft_y
	# How far a shallow ray must run along the canyon before it clears the viaduct's deck,
	# measured to the NEARER end of its straight middle.
	var lid := 0.0
	if lidded:
		lid = minf(absf(wx - VIADUCT_POINTS[1].x), absf(VIADUCT_POINTS[2].x - wx))
	var visible := 0
	for i in pattern.size():
		var r := pattern[i]
		if absf(r.z) / r.y > w / d:
			continue                                  # a wall took it
		if lidded and absf(r.x) / r.y < lid / d:
			continue                                  # the lid took it
		visible |= 1 << i
	var sats := DroneSensors.sats(visible, pattern.size())
	var fix: String = ["NO FIX", "TIME", "2D", "3D"][DroneSensors.fix_type(sats)]
	var note := " lid" if lidded else (" +%.0fm" % (craft_y - Y_FLOOR) if craft_y > Y_FLOOR else "")
	print("[skyport]   x %+5.0f%-6s %5.0f %6.2f %5d %6.2f  %s" % [
			wx, note, w, w / d, sats, DroneSensors.hdop(pattern, visible), fix])


func _report_road(curve: Curve3D, label: String) -> void:
	var length := curve.get_baked_length()
	var radius := RoadBuilder.min_turn_radius(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var worst := 0.0
	var step := 4.0
	var o := 0.0
	while o + step <= length:
		var a := curve.sample_baked(o)
		var b := curve.sample_baked(o + step)
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		worst = maxf(worst, absf(b.y - a.y) / maxf(run, 0.001))
		o += step
	# Where the tightest corner is, not just how tight: a radius under the ribbon's own
	# half-width pinches the inside edge into a slit, so the useful readout is which
	# control point to move.
	var tight := Vector3.ZERO
	var tight_r := INF
	var t := 4.0
	while t + 4.0 <= length:
		var a := curve.sample_baked(t - 4.0)
		var b := curve.sample_baked(t)
		var c := curve.sample_baked(t + 4.0)
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var bc := Vector2(c.x - b.x, c.z - b.z)
		var turn := absf(ab.angle_to(bc))
		var r := (ab.length() + bc.length()) * 0.5 / maxf(turn, 1e-4)
		if r < tight_r:
			tight_r = r
			tight = b
		t += 4.0
	print("[skyport] %s: %.0f m, min turn radius %.1f m (tightest near %.0f,%.0f), steepest grade %.0f%%" % [
			label, length, radius, tight.x, tight.z, worst * 100.0])


# ================================================================================ stage: props


func _props() -> int:
	var packed := ResourceLoader.load(LEVEL_PATH) as PackedScene
	if packed == null:
		printerr("[skyport] cannot load %s — run `-- scaffold` and --import first" % LEVEL_PATH)
		return 1
	var root := packed.instantiate()
	var code := _build_props(root)
	if code == 0:
		var out := PackedScene.new()
		if out.pack(root) != OK:
			printerr("[skyport] PackedScene.pack failed")
			code = 1
		elif ResourceSaver.save(out, LEVEL_PATH) != OK:
			printerr("[skyport] cannot save %s" % LEVEL_PATH)
			code = 1
		else:
			print("[skyport] saved %s" % LEVEL_PATH)
	root.free()
	return code


func _build_props(root: Node) -> int:
	var authoring := Groups.find_authoring(root)
	if authoring == null:
		printerr("[skyport] level has no AuthoringRoot")
		return 1
	# Idempotent: a re-run replaces the nodes this stage owns. The three RoadPaths are
	# scaffold's and deliberately absent from this list.
	for owned in OWNED_NODES:
		var stale := authoring.get_node_or_null(NodePath(owned))
		if stale != null:
			authoring.remove_child(stale)
			stale.free()
	# Payloads hang off the level root, not AuthoringRoot, so cleaned up separately.
	var stale_payloads := root.get_node_or_null(^"Payloads")
	if stale_payloads != null:
		root.remove_child(stale_payloads)
		stale_payloads.free()

	var built := _build_apron_gridmap()
	if built.is_empty():
		return 1
	var grid: GridMap = built["grid"]
	var apron: Rect2 = built["rect"]
	_add(authoring, grid, root)
	print("[skyport] apron deck covers x %.1f..%.1f, z %.1f..%.1f, deck y %.2f" % [
			apron.position.x, apron.end.x, apron.position.y, apron.end.y, built["deck_y"]])

	_build_tower_course(authoring, root)
	_build_pads(authoring, root, built["deck_y"])
	var water := authoring.get_node_or_null(^"WatercraftProps")
	if water != null:
		_build_channel(water, root)
	_build_payloads(root)
	return 0


## The buoyed channel and the measured leg. Holding a line of marks with the tide on the beam is
## what turns COG against HDG into a visible crab angle.
func _build_channel(water: Node, root: Node) -> void:
	var pairs := int((CHANNEL_Z1 - CHANNEL_Z0) / CHANNEL_SPACING) + 1
	for i in pairs:
		var z := CHANNEL_Z0 + CHANNEL_SPACING * float(i)
		_place_afloat(water, root, BUOY_PREFAB, "ChannelW%d" % i,
				Vector2(CHANNEL_X - CHANNEL_HALF, z))
		_place_afloat(water, root, BUOY_PREFAB, "ChannelE%d" % i,
				Vector2(CHANNEL_X + CHANNEL_HALF, z))
	print("[skyport] channel: %d mark pairs, x %.0f +/- %.0f, z %.0f..%.0f" % [
			pairs, CHANNEL_X, CHANNEL_HALF, CHANNEL_Z0, CHANNEL_Z1])
	# The leg's ends are gates rather than single marks, so the stopwatch has an instant to
	# start on: you time crossing BETWEEN a pair, not passing one.
	var ends := [MILE_X0, MILE_X1]
	for i in ends.size():
		var x: float = ends[i]
		_place_afloat(water, root, MILE_PREFAB, "MileN%d" % i, Vector2(x, MILE_Z - MILE_HALF))
		_place_afloat(water, root, MILE_PREFAB, "MileS%d" % i, Vector2(x, MILE_Z + MILE_HALF))
	print("[skyport] measured leg: %.0f m between the gates, z %.0f" % [
			MILE_X1 - MILE_X0, MILE_Z])


## The crates the drone's hardpoint picks up, on the pickup pad. A direct child of the level
## (see PAYLOAD_SCENE), the only nodes this generator makes that aren't bake input. Laid on the
## pad's own Y directly: the payload scene's origin is its base, so ground height is placement.
func _build_payloads(root: Node) -> void:
	var scene := ResourceLoader.load(PAYLOAD_SCENE) as PackedScene
	if scene == null:
		printerr("[skyport] cannot load %s" % PAYLOAD_SCENE)
		return
	var group := Node3D.new()
	group.name = "Payloads"
	root.add_child(group)
	group.owner = root
	var span := float(PAYLOAD_COUNT - 1) * PAYLOAD_SPACING
	for i in PAYLOAD_COUNT:
		var crate := scene.instantiate() as Node3D
		crate.name = "Payload%d" % i
		crate.position = Vector3(PAD_APRON.x,
				Y_APRON, PAD_APRON.y - span * 0.5 + float(i) * PAYLOAD_SPACING)
		group.add_child(crate)
		crate.owner = root
	print("[skyport] %d payload crates on the pickup pad at x %.0f, z %.0f" % [
			PAYLOAD_COUNT, PAD_APRON.x, PAD_APRON.y])


## The apron: a real roads-palette GridMap, cell indices from asking the GridMap where
## APRON_DECK_CENTER falls (never a hand-guessed offset). Returns {} on failure.
func _build_apron_gridmap() -> Dictionary:
	var ml := ResourceLoader.load(ROADS_MESHLIB) as MeshLibrary
	if ml == null:
		printerr("[skyport] cannot load %s" % ROADS_MESHLIB)
		return {}
	var item := ml.find_item_by_name(APRON_TILE)
	if item < 0:
		printerr("[skyport] roads palette has no '%s' tile" % APRON_TILE)
		return {}
	var mesh := ml.get_item_mesh(item)
	if mesh == null:
		printerr("[skyport] roads palette tile '%s' has no mesh" % APRON_TILE)
		return {}

	var grid := GridMap.new()
	grid.name = "RoadsTiles"
	grid.mesh_library = ml
	grid.cell_size = Vector3(12, 3, 12)
	grid.cell_center_y = false
	# Level 3's tile city uses exactly this offset: the tile deck is 0.24 m thick and sits on
	# the cell base, so dropping the map 0.22 m lands the driving surface 0.02 m above the
	# plateau instead of behind a 24 cm lip.
	grid.position = Vector3(0, -0.22, 0)

	var y_cell := int(round(Y_APRON / grid.cell_size.y))
	var origin := grid.local_to_map(Vector3(APRON_DECK_CENTER.x, Y_APRON, APRON_DECK_CENTER.y))
	var i0 := origin.x - int((APRON_CELLS_X - 1) / 2.0)
	var j0 := origin.z - int((APRON_CELLS_Z - 1) / 2.0)
	var mesh_xform := ml.get_item_mesh_transform(item)
	var bounds := AABB()
	var first := true
	for di in APRON_CELLS_X:
		for dj in APRON_CELLS_Z:
			var cell := Vector3i(i0 + di, y_cell, j0 + dj)
			grid.set_cell_item(cell, item)
			var placed := Transform3D(Basis.IDENTITY, grid.map_to_local(cell))
			var world: AABB = grid.transform * placed * mesh_xform * mesh.get_aabb()
			bounds = world if first else bounds.merge(world)
			first = false
	return {
		"grid": grid,
		"rect": Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z),
		"deck_y": bounds.end.y,
	}


## The tower course: a gated mast slalom on the highland, north of the canyon and clear of every
## road, where a drone has room to fly between hover points. `flagCheckers` is a 15 m mast with
## FOOTPRINT collision (solid only at the pole).
func _build_tower_course(authoring: Node, root: Node) -> void:
	var props := Node3D.new()
	props.name = "RacingProps"
	_add(authoring, props, root)
	for i in COURSE_MASTS:
		var x := COURSE_X0 + COURSE_SPACING * float(i)
		var z := COURSE_Z + (COURSE_OFFSET if i % 2 == 0 else -COURSE_OFFSET)
		_place(props, root, MAST_PREFAB, "Mast%d" % i, Vector3(x, Y_HIGHLAND, z))
	# Yawed a quarter turn: the gantry is 15.4 m wide across its own X and the course runs
	# along world X, so unrotated it would put a leg in the flight path instead of an opening.
	for i in GATE_SLOTS.size():
		var gx := COURSE_X0 + COURSE_SPACING * GATE_SLOTS[i]
		_place(props, root, GATE_PREFAB, "Gate%d" % i, Vector3(gx, Y_HIGHLAND, COURSE_Z),
				PI * 0.5)


## The pad ladder and payload targets. The two buildings are here for their roofs: both carry
## `box` collision, so their tops are flat landable decks 8.4 m and 25.9 m up. Everything
## positioned from its measured merged AABB, never a guessed origin (see _place).
func _build_pads(authoring: Node, root: Node, deck_y: float) -> void:
	var commercial := Node3D.new()
	commercial.name = "CommercialProps"
	_add(authoring, commercial, root)
	# Roof at mesa B + 25.92 = 55.9 m: the top of the ladder, and 47 m above the canyon floor.
	_place(commercial, root, TOWER_PREFAB, "PadTower",
			Vector3(TOWER_XZ.x, Y_MESA_B, TOWER_XZ.y))

	var racing := authoring.get_node_or_null(^"RacingProps")
	if racing != null:
		# Roof at the apron + 8.4 = 26.4 m: the low rung, one hop off the deck.
		_place(racing, root, GARAGE_PREFAB, "PadGarage",
				Vector3(GARAGE_XZ.x, Y_APRON, GARAGE_XZ.y), PI)
		# Corner flags on the three PAYLOAD pads, so a marked square reads as a target from
		# the air as well as off the splat.
		var n := 0
		for pad: Array in pads():
			if not bool(pad[2]):
				continue
			var rect := pad_rect(pad[0])
			for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y),
					rect.end, Vector2(rect.position.x, rect.end.y)]:
				_place(racing, root, MARKER_PREFAB, "PadFlag%d" % n,
						Vector3(corner.x, float(pad[1]), corner.y))
				n += 1

	var water := Node3D.new()
	water.name = "WatercraftProps"
	_add(authoring, water, root)
	# The slipway's own apron at the waterline. `ramp-wide` is a weld-mode piece, so it joins
	# the level-wide drivable body and the car really can drive onto it.
	_place(water, root, SLIP_PREFAB, "Slipway",
			Vector3(_ramp_x_at_y(SEA_Y), SEA_Y - 0.4, SLIP_RAMP_B.z), PI * 0.5)
	# Slipway scenery. These are shipping containers at their own honest scale — the drone's
	# liftable payloads are the crates in _build_payloads, and are not kit pieces at all.
	for i in CARGO_COUNT:
		_place(water, root, CARGO_PREFAB, "Cargo%d" % i,
				Vector3(CARGO_XZ.x, deck_y, CARGO_XZ.y + float(i) * 3.2), PI * 0.5)


## Add `child` under `parent` and give it the level root as owner, which is what makes
## PackedScene.pack serialize it.
func _add(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root


## Instance a kit prefab, yaw it, and sit it on the ground at `at`, positioned from its measured
## merged mesh AABB (rotated centre on target XZ, base on target Y). Measuring after rotation
## matters: a prefab whose origin isn't its centre would walk sideways when yawed.
func _place(parent: Node, root: Node, path: String, node_name: String, at: Vector3,
		yaw := 0.0) -> void:
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		printerr("[skyport] cannot load %s" % path)
		return
	var piece := scene.instantiate() as Node3D
	var turn := Basis(Vector3.UP, yaw)
	var aabb: AABB = Transform3D(turn, Vector3.ZERO) * _merged_aabb(piece, Transform3D.IDENTITY)
	piece.name = node_name
	piece.transform = Transform3D(turn,
			at - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z))
	_add(parent, piece, root)
	if not (node_name.begins_with("Mast") or node_name.begins_with("PadFlag")):
		print("[skyport]   %s: %.1f x %.1f x %.1f m, base y %.2f, top y %.2f" % [
				node_name, aabb.size.x, aabb.size.y, aabb.size.z, at.y, at.y + aabb.size.y])


## Instance a kit prefab and float it at `xz`, ORIGIN ON THE WATERLINE. The counterpart of
## _place, and not a variant of it: _place stands a piece's measured base on a ground Y, which
## is exactly wrong for a mark whose recipe keeps the authored waterline as its origin (the
## `align: "raw"` entry in kit/import/watercraft.json). Measured all the same, because a mark
## the boat cannot see is not a mark.
func _place_afloat(parent: Node, root: Node, path: String, node_name: String,
		xz: Vector2) -> void:
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		printerr("[skyport] cannot load %s" % path)
		return
	var piece := scene.instantiate() as Node3D
	piece.name = node_name
	piece.position = Vector3(xz.x, SEA_Y, xz.y)
	_add(parent, piece, root)
	if node_name.ends_with("0"):
		var aabb := _merged_aabb(piece, Transform3D.IDENTITY)
		print("[skyport]   %s: %.1f x %.1f x %.1f m, %.1f m of it above the water" % [
				node_name, aabb.size.x, aabb.size.y, aabb.size.z, aabb.end.y])


func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var aabb := AABB()
	var first := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		aabb = xform * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		var cx := xform
		if child is Node3D:
			cx = xform * (child as Node3D).transform
		var ca := _merged_aabb(child, cx)
		if ca.size != Vector3.ZERO or ca.position != Vector3.ZERO:
			aabb = ca if first else aabb.merge(ca)
			first = false
	return aabb


# --- the probe points (stage `probe`) -----------------------------------------------------
## Where to stand the sensors. Each is a claim this level makes about `sats` or `agl`, and the
## probe stage measures it against the baked collision rather than against the W/D table.
const PROBES: Array[Array] = [
	["apron, on the deck", Vector3(-24.0, Y_APRON + 1.0, 126.0)],
	["over the sea", Vector3(212.0, 20.0, 132.0)],
	["canyon bowl floor", Vector3(-150.0, Y_FLOOR + 1.0, CANYON_Z)],
	["canyon R1 floor", Vector3(-112.0, Y_FLOOR + 1.0, CANYON_Z)],
	["canyon R2 floor", Vector3(-78.0, Y_FLOOR + 1.0, CANYON_Z)],
	["canyon R3 floor", Vector3(-42.0, Y_FLOOR + 1.0, CANYON_Z)],
	["canyon R4 floor", Vector3(-8.0, Y_FLOOR + 1.0, CANYON_Z)],
	["slot, west of the lid", Vector3(16.0, Y_FLOOR + 1.0, CANYON_Z)],
	["slot, under the lid", Vector3(65.0, Y_FLOOR + 1.0, CANYON_Z)],
	["R3, 12 m up", Vector3(-42.0, Y_FLOOR + 12.0, CANYON_Z)],
	["R3, 24 m up", Vector3(-42.0, Y_FLOOR + 24.0, CANYON_Z)],
	["rim pad, on the deck", Vector3(PAD_RIM_X, Y_HIGHLAND + 1.0,
			CANYON_Z - 14.0 - PAD_SIZE * 0.5)],
	["rim pad, 12 m out over the canyon", Vector3(PAD_RIM_X, Y_HIGHLAND + 1.0, CANYON_Z)],
	["tower roof", Vector3(TOWER_XZ.x, Y_MESA_B + 25.92 + 1.0, TOWER_XZ.y)],
	["over the mast course", Vector3(68.0, Y_HIGHLAND + 20.0, COURSE_Z)],
]

## Fly the sensors without flying: load the baked level, stand at a list of points, and run the
## drone's own `DroneSensors.sweep_sky` / `measure_agl` against the real physics space.
## `_report_sats` in scaffold is an analytic W/D prediction; this is the measurement, and
## disagreement means the geometry isn't what the table thinks. Catches a wall that didn't bake.
func _probe() -> int:
	var packed := ResourceLoader.load(LEVEL_PATH) as PackedScene
	if packed == null:
		printerr("[skyport] cannot load %s" % LEVEL_PATH)
		return 1
	var level := packed.instantiate()
	add_child(level)
	# Level._ready spawns the default vehicle; free it, since this measures the world, not a
	# drone sitting on the apron. Two physics frames let the baked swap and the free settle.
	await get_tree().physics_frame
	# Stop every _process in the level first: ChaseCamera follows the vehicle by node, so
	# freeing the body under a live camera logs an is_inside_tree error every frame.
	level.propagate_call(&"set_process", [false])
	for child in level.get_children():
		if child is RigidBody3D:
			level.remove_child(child)
			child.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := (level as Node3D).get_world_3d().direct_space_state
	if space == null:
		printerr("[skyport] no physics space")
		return 1
	# Nothing to exclude: every RigidBody3D was freed above, and the map's containment box is
	# masked out by `Layers.SOLID` inside DroneSensors rather than enumerated here.
	var query := DroneSensors.make_query([] as Array[RID])
	var pattern := DroneSensors.sky_pattern(DroneSensors.SKY_RAYS, DroneSensors.SKY_MASK_DEG)

	print("[skyport] MEASURED against the baked collision")
	print("[skyport]   %-26s %5s %6s %7s  %s" % ["where", "sats", "hdop", "agl", "fix"])
	for probe: Array in PROBES:
		var at: Vector3 = probe[1]
		var visible := DroneSensors.sweep_sky(space, at, pattern, 0, 0,
				DroneSensors.SKY_RAYS, query)
		var sats := DroneSensors.sats(visible, pattern.size())
		var agl := DroneSensors.measure_agl(space, at, query)
		var fix: String = ["NO FIX", "TIME", "2D", "3D"][DroneSensors.fix_type(sats)]
		print("[skyport]   %-26s %5d %6.2f %7.1f  %s" % [
				probe[0], sats, DroneSensors.hdop(pattern, visible), agl, fix])
	level.queue_free()
	return 0


# ============================================================================ text artifacts


func _info_text() -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("drone", "plane", "car", "truck", "tractor", "boat")
default_vehicle = "drone"
""" % TITLE


## The level's weather: a resource, since that is what Level.wind is.
func _wind_text() -> String:
	return """[gd_resource type="Resource" script_class="WindField" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/levels/base/wind_field.gd" id="1_wind"]

[resource]
script = ExtResource("1_wind")
direction_deg = %s
speed = %s
gust_speed = %s
gust_seed = %d
""" % [WIND_DIRECTION_DEG, WIND_SPEED, WIND_GUST, WIND_SEED]


## The level's tide, likewise a resource, since that is what Level.current is.
func _current_text() -> String:
	return """[gd_resource type="Resource" script_class="CurrentField" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/levels/base/current_field.gd" id="1_current"]

[resource]
script = ExtResource("1_current")
set_deg = %s
drift = %s
tide_period_s = %s
tide_offset_s = %s
""" % [CURRENT_SET_DEG, CURRENT_DRIFT, CURRENT_PERIOD_S, CURRENT_OFFSET_S]


func _scene_text() -> String:
	return """[gd_scene load_steps=24 format=3]

[ext_resource type="Script" path="res://src/levels/base/level.gd" id="1_level"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_info.tres" id="2_info"]
[ext_resource type="Script" path="res://src/vehicles/base/chase_camera.gd" id="3_cam"]
[ext_resource type="Script" path="res://src/levels/base/vehicle_spawn.gd" id="4_spawn"]
[ext_resource type="Script" path="res://src/levels/base/heightmap_terrain.gd" id="5_terrain"]
[ext_resource type="Texture2D" path="res://src/levels/island/level_6/level_6_island_height.png" id="6_height"]
[ext_resource type="Texture2D" path="res://src/levels/island/level_6/level_6_island_splat.png" id="7_splat"]
[ext_resource type="Shader" path="res://kit/terrain/terrain_splat.gdshader" id="8_shader"]
[ext_resource type="Script" path="res://src/water/water_surface.gd" id="9_water"]
[ext_resource type="Script" path="res://kit/helpers/authoring_root.gd" id="10_authoring"]
[ext_resource type="Environment" path="res://src/levels/base/default_env.tres" id="11_env"]
[ext_resource type="Script" path="res://kit/helpers/road_path.gd" id="12_road"]
[ext_resource type="Resource" path="res://kit/roads/asphalt_profile.tres" id="13_asphalt"]
[ext_resource type="Resource" path="res://kit/roads/bridge_profile.tres" id="14_bridge"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_loop_curve.tres" id="15_loop"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_viaduct_curve.tres" id="16_viaduct"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_rim_curve.tres" id="17_rim"]
[ext_resource type="Texture2D" path="res://src/levels/island/level_6/level_6_island_splat2.png" id="18_splat2"]
[ext_resource type="Script" path="res://src/levels/base/world_bounds.gd" id="19_bounds"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_wind.tres" id="20_wind"]
[ext_resource type="Resource" path="res://src/levels/island/level_6/level_6_current.tres" id="21_current"]

[sub_resource type="PlaneMesh" id="SeaBedMesh"]
size = Vector2({size_plus}, {size_plus})

[sub_resource type="StandardMaterial3D" id="SeaBedMat"]
albedo_color = Color(0.83, 0.76, 0.55, 1)

[sub_resource type="ShaderMaterial" id="SplatMat"]
shader = ExtResource("8_shader")
shader_parameter/grass_color = Color(0.35, 0.55, 0.25, 1)
shader_parameter/dirt_color = Color(0.52, 0.4, 0.26, 1)
shader_parameter/sand_color = Color(0.83, 0.76, 0.55, 1)
shader_parameter/rock_color = Color(0.45, 0.44, 0.42, 1)
shader_parameter/color5 = Color({pad_r}, {pad_g}, {pad_b}, 1)
shader_parameter/color6 = Color(0.92, 0.94, 0.97, 1)
shader_parameter/color7 = Color(0.22, 0.22, 0.24, 1)
shader_parameter/color8 = Color(0.62, 0.6, 0.56, 1)
shader_parameter/splatmap = ExtResource("7_splat")
shader_parameter/splatmap2 = ExtResource("18_splat2")
shader_parameter/blend_sharpness = 8.0
shader_parameter/roughness_value = 1.0

[node name="Level6" type="Node3D"]
script = ExtResource("1_level")
info = ExtResource("2_info")
wind = ExtResource("20_wind")
current = ExtResource("21_current")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = ExtResource("11_env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, 0.354, -0.354, 0, 0.707, 0.707, 0.5, -0.612, 0.612, 0, 40, 0)
light_color = Color(1, 0.96, 0.88, 1)
shadow_enabled = true
directional_shadow_mode = 0
directional_shadow_max_distance = 150.0

[node name="ChaseCamera" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 6)
script = ExtResource("3_cam")

[node name="Spawn" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {sx}, {sy}, {sz})
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("car", "truck", "tractor", "drone")

[node name="PlaneSpawn" type="Marker3D" parent="."]
transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, {px}, {py}, {pz})
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("plane")

[node name="WaterSpawn" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {wx}, {wy}, {wz})
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("boat")
is_water = true

[node name="Sea" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {sea_y}, 0)
script = ExtResource("9_water")
size = Vector2({size_plus}, {size_plus})
depth = {sea_depth}
far_sea_extent = 1900.0

[node name="Bounds" type="StaticBody3D" parent="."]
script = ExtResource("19_bounds")
extent = Vector2({size_plus}, {size_plus})

[node name="SeaBed" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.01, 0)
mesh = SubResource("SeaBedMesh")
surface_material_override/0 = SubResource("SeaBedMat")

[node name="Island" type="StaticBody3D" parent="."]
script = ExtResource("5_terrain")
heightmap = ExtResource("6_height")
terrain_size = Vector2({size}, {size})
height = {height}
material = SubResource("SplatMat")
preset = 0
gen_seed = {seed}
feature_scale = {feature_scale}
gen_octaves = {octaves}
falloff_start = {falloff_start}
falloff_end = {falloff_end}
coast_roughness = {coast_roughness}
terrace_levels = {terrace_levels}
splatmap = ExtResource("7_splat")
splatmap2 = ExtResource("18_splat2")
channel_names = PackedStringArray({channel_names})
channel_grip = PackedFloat32Array({channel_grip})
sand_height = {sand_height}
dirt_slope_deg = 24.0
rock_slope_deg = 40.0

[node name="AuthoringRoot" type="Node3D" parent="."]
script = ExtResource("10_authoring")
chunk_size = 64.0
metadata/_custom_type_script = "uid://t88htpmwukbg"

[node name="RoadLoop" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_asphalt")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/RoadLoop"]
curve = ExtResource("15_loop")

[node name="Viaduct" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("14_bridge")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/Viaduct"]
curve = ExtResource("16_viaduct")

[node name="RimRoad" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_asphalt")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/RimRoad"]
curve = ExtResource("17_rim")
""".format({
		"size": SIZE, "size_plus": SIZE + 48.0, "height": HEIGHT, "sea_y": SEA_Y,
		"sea_depth": SEA_DEPTH, "sand_height": SAND_HEIGHT,
		"seed": GEN_SEED, "feature_scale": FEATURE_SCALE, "octaves": OCTAVES,
		"falloff_start": FALLOFF_START, "falloff_end": FALLOFF_END,
		"coast_roughness": COAST_ROUGHNESS, "terrace_levels": TERRACE_LEVELS,
		"channel_names": '"%s"' % '", "'.join(CHANNEL_NAMES),
		"channel_grip": ", ".join(PackedStringArray(
				CHANNEL_GRIP.map(func(g: float) -> String: return str(g)))),
		"conform_falloff": CONFORM_FALLOFF, "conform_epsilon": CONFORM_EPSILON,
		"pad_r": PAD_COLOR.r, "pad_g": PAD_COLOR.g, "pad_b": PAD_COLOR.b,
		"sx": SPAWN_LAND.x, "sy": SPAWN_LAND.y + 0.6, "sz": SPAWN_LAND.z,
		"px": SPAWN_PLANE.x, "py": SPAWN_PLANE.y + 0.6, "pz": SPAWN_PLANE.z,
		"wx": SPAWN_WATER.x, "wy": SPAWN_WATER.y, "wz": SPAWN_WATER.z,
	})


# ==================================================================================== helpers


func _write_png(img: Image, path: String) -> bool:
	if img.save_png(path) != OK:
		printerr("[skyport] failed to write %s" % path)
		return false
	TerrainGen.ensure_import_settings(path)
	print("[skyport] wrote %s" % path)
	return true


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[skyport] cannot write %s" % path)
		return
	f.store_string(text)
	print("[skyport] wrote %s" % path)


# World <-> pixel, HeightmapTerrain's own convention: the grid spans [-span/2, +span/2] in
# the terrain's local frame at one cell per world unit, and this terrain sits at the origin.


func _norm(world_y: float) -> float:
	return clampf(world_y / HEIGHT, 0.0, 1.0)


func _px_x(world_x: float) -> int:
	return clampi(int(round((world_x + SIZE * 0.5) * _sx)), 0, _iw - 1)


func _px_z(world_z: float) -> int:
	return clampi(int(round((world_z + SIZE * 0.5) * _sz)), 0, _ih - 1)


func _world_x(px: int) -> float:
	return float(px) / _sx - SIZE * 0.5
