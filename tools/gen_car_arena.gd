extends Node
## Author the car challenge arena: terrain, splat, roads and scene, AND the course scenes the car
## challenges lay over it, all from here; a re-run overwrites all of it. Chain recorded in
## src/levels/island/car_arena/car_arena_gen.json (tools/CLAUDE.md).
##
## A flat plateau disc at Y_PLATEAU carrying three roads, each built by a Turtle from straights and
## true circular arcs, so every corner radius is a number here rather than a Catmull-Rom accident:
## - STRIP, z 0 from x -160 to 160: Car 1 (start up), Car 3 and Car 6 (stop in the box, lit and
##   blind, whose overrun zone covers the strip from x 48 to its east end) and Car 10 (speed trap).
## - CORNERS, north of the strip, x -160..105: four 90 deg corners, L R R L: Car 4 and Car 8 (one
##   course, steady and blinking).
## - WINDING, south of the strip, x -150..77: wide S-bends: Car 2 (easy turns) and Car 14
##   (cornering budget), one course.
## Off the strip, the plateau east of the corners road's end (x ~105) and the winding road's
## (x ~77) is empty on purpose: the room the rest of the car set builds on.
##
## `-- courses` writes the courses only, so it never re-stales the bake. Zones are placed by
## distance along the SAVED curves, so a course cannot sit off its road. The briefings in
## src/challenges/defs/car_*.tres quote STRIP_START_X, START_UP_SPAWN_X, START_UP_FINISH_X,
## BOX_GATE_X, BOX_GATE_TO_BOX, BOX_LENGTH, BOX_WIDTH, TRAP_FROM_X, TRAP_TO_X, SIGNAL_LENGTH,
## WINDING_R and the CORNER_TURNS order: move one, edit the briefing (and re-measure Car 14's par
## for WINDING_R).

const DIR := "res://src/levels/island/car_arena"
const COURSE_DIR := DIR + "/courses"
const LEVEL_PATH := DIR + "/car_arena.tscn"
const ARENA_ID := "car_arena"
const TITLE := "Car Arena"

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")

# --- the island ------------------------------------------------------------------------------
const SIZE := 512.0            ## world extent (X and Z), matching the other islands
const HEIGHT := 51.0           ## white-pixel amplitude; 765/15, so 3 m levels store exactly
const SEA_Y := 1.0
const SEA_DEPTH := 3.0
const SAND_HEIGHT := 2.0
const GEN_SEED := 70715
const FEATURE_SCALE := 260.0
const OCTAVES := 4
## The fractal is already tapering where the plateau blend ends, so the ring round the plateau
## reads as low coastal hills rather than a wall.
const FALLOFF_START := 0.70
const FALLOFF_END := 0.92
const COAST_ROUGHNESS := 0.35
const TERRACE_LEVELS := 2
## Everything drivable sits on this one flat, on the 3 m lattice.
const Y_PLATEAU := 6.0
const PLATEAU_R := 180.0       ## the flat disc, centred on the origin
const PLATEAU_BLEND := 18.0    ## blend ring outside it

# --- roads ---------------------------------------------------------------------------------------
const ASPHALT_PROFILE := "res://kit/roads/asphalt_profile.tres"
const CONFORM_EPSILON := 0.05
const CONFORM_FALLOFF := 8.0
const MAX_SEG_LEN := 6.0
const MAX_SEG_ANGLE := 6.0
## RoadPath.SPLAT_PAINT_INSET, reproduced — that node's paint button is editor-only.
const SPLAT_PAINT_INSET := 1.0
const MIN_RADIUS := 12.0       ## the scaffold fails on a tighter corner

const STRIP_START_X := -160.0
const STRIP_LENGTH := 320.0

const CORNERS_START := Vector2(-160.0, -35.0)
const CORNER_R := 15.0
## Signed sweeps, + = right. The corner course's L R R L.
const CORNER_TURNS: Array[float] = [-90.0, 90.0, 90.0, -90.0]
const CORNERS_FIRST_LEG := 75.0
const CORNERS_LEG := 60.0      ## straight between two arcs: 90 m vertex to vertex
const CORNERS_LAST_LEG := 70.0

const WINDING_START := Vector2(-150.0, 55.0)
const WINDING_R := 35.0
const WINDING_SWEEPS: Array[float] = [70.0, -140.0, 140.0, -70.0]
const WINDING_END_LEG := 15.0

# --- splat -----------------------------------------------------------------------------------------
const CHANNEL_NAMES: Array[String] = [
	"Grass", "Dirt", "Sand", "Rock", "Snow", "Mud", "Asphalt", "Gravel",
]
const CHANNEL_GRIP: Array[float] = [0.8, 0.7, 0.6, 0.7, 0.75, 0.5, 1.0, 0.85]

# --- courses -----------------------------------------------------------------------------------------
## Every course zone is a box this tall, its base 1 m under the deck: it holds the body origin and
## every wheel contact on the road, and nothing flying over it.
const ZONE_HEIGHT := 6.0
const ZONE_BASE := -1.0
const SPAWN_CLEARANCE := 0.6
const MARK_LIFT := 0.03        ## paint sits this far over the deck
const WINDOW_GAP_MIN := 5.0    ## two windows of one course never come closer
const LINE_W := 0.4

## Car 1: the strip from its west end to a finish line 200 m on.
const START_UP_SPAWN_X := -150.0
const START_UP_FINISH_X := 50.0
## Car 3: a gate, then the box. The box starts where a car that crossed the gate at the minimum
## speed stops at the earliest (full brake from 50 km/h ~ 13 m, measured), so a crawl into it is
## impossible, and runs long enough for full braking at the gate to pass up to ~65 km/h.
const BOX_GATE_X := 20.0
const BOX_GATE_TO_BOX := 8.0
const BOX_LENGTH := 18.0
const BOX_WIDTH := 6.0
const BOX_OVERRUN_GAP := 2.0
## Zones across the strip span this much: going round a gate or the overrun on the grass is no
## way out.
const STRIP_ZONE_WIDTH := 60.0
## Car 10: the trap is the paved width, so leaving it by the side (anywhere but into the thin exit
## zone across its far end) fails.
const TRAP_FROM_X := -40.0
const TRAP_TO_X := 120.0
const TRAP_EXIT_LENGTH := 1.0
## Car 4: the signal window is the straight before each corner, the clear window starts after it.
const SIGNAL_LENGTH := 30.0
const CLEAR_FROM := 5.0
const CLEAR_TO := 22.0
const CORNER_ZONE_WIDTH := 24.0
const FINISH_BEFORE_END := 15.0

const WHITE := Color(0.95, 0.95, 0.95)
const YELLOW := Color(1.0, 0.8, 0.1)
const AMBER := Color(1.0, 0.5, 0.05)
const DARK := Color(0.12, 0.12, 0.12)

# --- working state (world <-> pixel) ---------------------------------------------------------------
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
		"courses":  # writes the course scenes from the saved curves
			code = _courses()
		_:
			printerr("[car-arena] usage: -- scaffold | courses")
			code = 1
	get_tree().quit(code)


# ================================================================================ the turtle


## A road built as straights and true circular arcs. Every arc is split into pieces of at most
## 45 deg, each one cubic with the standard 4/3 tan(a/4) handles, so the curve holds its radius to
## a few millimetres. Headings are compass degrees: 0 north (-Z), 90 east (+X), + turns right.
class Turtle:
	var pos: Vector3
	var heading := 0.0
	var points: Array[Vector3] = []
	var ins: Array[Vector3] = []
	var outs: Array[Vector3] = []
	## Named points: `<name>_in` / `_mid` / `_out` on an arc, and `<name>_c` its centre.
	var marks: Dictionary[String, Vector3] = {}

	func _init(start: Vector3, heading_deg: float) -> void:
		pos = start
		heading = heading_deg
		_push(Vector3.ZERO)

	func straight(length: float) -> void:
		var d := Turtle.dir(heading)
		outs[outs.size() - 1] = d * length / 3.0
		pos += d * length
		_push(-d * length / 3.0)

	func arc(radius: float, sweep_deg: float, mark_name := "") -> void:
		var s := signf(sweep_deg)
		var centre := pos + Turtle.dir(heading + 90.0 * s) * radius
		var pieces := ceili(absf(sweep_deg) / 45.0)
		var step := sweep_deg / float(pieces)
		var k := 4.0 / 3.0 * tan(deg_to_rad(absf(step)) / 4.0) * radius
		var start_heading := heading
		if mark_name != "":
			marks[mark_name + "_in"] = pos
			marks[mark_name + "_c"] = centre
			var mid_heading := start_heading + sweep_deg * 0.5
			marks[mark_name + "_mid"] = centre + Turtle.dir(mid_heading - 90.0 * s) * radius
		for i in pieces:
			outs[outs.size() - 1] = Turtle.dir(heading) * k
			heading += step
			pos = centre + Turtle.dir(heading - 90.0 * s) * radius
			_push(-Turtle.dir(heading) * k)
		if mark_name != "":
			marks[mark_name + "_out"] = pos

	func curve() -> Curve3D:
		var c := Curve3D.new()
		for i in points.size():
			c.add_point(points[i], ins[i], outs[i])
		return c

	func _push(handle_in: Vector3) -> void:
		points.append(pos)
		ins.append(handle_in)
		outs.append(Vector3.ZERO)

	static func dir(deg: float) -> Vector3:
		var r := deg_to_rad(deg)
		return Vector3(sin(r), 0.0, -cos(r))


func _strip() -> Turtle:
	var t := Turtle.new(Vector3(STRIP_START_X, Y_PLATEAU, 0.0), 90.0)
	t.straight(STRIP_LENGTH)
	return t


func _corners() -> Turtle:
	var t := Turtle.new(Vector3(CORNERS_START.x, Y_PLATEAU, CORNERS_START.y), 90.0)
	t.straight(CORNERS_FIRST_LEG)
	for i in CORNER_TURNS.size():
		t.arc(CORNER_R, CORNER_TURNS[i], "c%d" % i)
		t.straight(CORNERS_LEG if i < CORNER_TURNS.size() - 1 else CORNERS_LAST_LEG)
	return t


func _winding() -> Turtle:
	var t := Turtle.new(Vector3(WINDING_START.x, Y_PLATEAU, WINDING_START.y), 90.0)
	t.straight(WINDING_END_LEG)
	for sweep in WINDING_SWEEPS:
		t.arc(WINDING_R, sweep)
	t.straight(WINDING_END_LEG)
	return t


## Road file name -> its Turtle. The one list both stages read.
func _roads() -> Dictionary[String, Turtle]:
	return {
		"car_arena_strip_curve.tres": _strip(),
		"car_arena_corners_curve.tres": _corners(),
		"car_arena_winding_curve.tres": _winding(),
	}


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
	# The plateau: the round brush's FLATTEN, which lerps to a target, so a replay lands on the
	# same bytes.
	var half := PLATEAU_R + PLATEAU_BLEND
	BrushOps.stamp_height(heights, _px_x(0.0), _px_z(0.0), half * _sx, half * _sz,
			BrushOps.FLATTEN, 1.0, PLATEAU_BLEND / half, _norm(Y_PLATEAU), false)

	var asphalt := ResourceLoader.load(ASPHALT_PROFILE)
	if asphalt == null:
		printerr("[car-arena] cannot load %s" % ASPHALT_PROFILE)
		return 1
	var roads := _roads()
	var ok := true
	for file_name in roads:
		var curve := roads[file_name].curve()
		ok = _report_road(curve, file_name, asphalt) and ok
		_conform(heights, curve, asphalt)
	if not ok:
		return 1

	var px := SIZE / float(cells - 1)
	var splat := TerrainGen.build_splatmap(heights, HEIGHT, px, px, SAND_HEIGHT, 22.0, 38.0)
	var splat2 := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	splat2.fill(Color(0, 0, 0, 0))
	for file_name in roads:
		_paint_road_splat(splat, splat2, roads[file_name].curve(), asphalt)

	if not _write_png(heights, "%s/car_arena_island_height.png" % DIR):
		return 1
	if not _write_png(splat, "%s/car_arena_island_splat.png" % DIR):
		return 1
	if not _write_png(splat2, "%s/car_arena_island_splat2.png" % DIR):
		return 1
	for file_name in roads:
		var path := "%s/%s" % [DIR, file_name]
		if ResourceSaver.save(roads[file_name].curve(), path) != OK:
			printerr("[car-arena] cannot save %s" % path)
			return 1
	_write_text("%s/car_arena_info.tres" % DIR, _info_text())
	_write_text(LEVEL_PATH, _scene_text())
	print("[car-arena] scaffold done. Run --import, then `-- courses`, then bake.")
	return 0


## RoadPath._conform_terrain reproduced (editor-only, EditorUndoRedoManager) — a headless tool
## calls the pure core directly, same as tools/gen_skyport.gd.
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
		printerr("[car-arena] a conform changed nothing — the road missed the terrain")


## RoadPath._paint_splat reproduced, for the same reason and at the same INSET paved width,
## so a conformed road grips like asphalt instead of like the grass under its deck.
func _paint_road_splat(splat: Image, splat2: Image, curve: Curve3D, profile: Resource) -> void:
	var channel: int = profile.get("splat_channel")
	var pw: float = float(profile.call("paved_half_width")) - SPLAT_PAINT_INSET
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


## Length and tightest radius, and FALSE when a corner is under MIN_RADIUS or the road's full
## width leaves the plateau disc anywhere.
func _report_road(curve: Curve3D, label: String, profile: Resource) -> bool:
	var fw: float = profile.call("full_half_width")
	var radius := RoadBuilder.min_turn_radius(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var reach := 0.0
	for o in RoadBuilder.adaptive_offsets(curve, MAX_SEG_LEN, MAX_SEG_ANGLE):
		var w := curve.sample_baked(o)
		reach = maxf(reach, Vector2(w.x, w.z).length() + fw)
	print("[car-arena] %s: %.0f m, min turn radius %.1f m, reaches r %.1f of the %.0f m plateau" % [
			label, curve.get_baked_length(), radius, reach, PLATEAU_R])
	var ok := true
	if radius < MIN_RADIUS:
		printerr("[car-arena] %s: a corner is tighter than %.0f m" % [label, MIN_RADIUS])
		ok = false
	if reach > PLATEAU_R:
		printerr("[car-arena] %s: leaves the plateau" % label)
		ok = false
	return ok


# ============================================================================= stage: courses


func _courses() -> int:
	DirAccess.make_dir_recursive_absolute(COURSE_DIR)
	var curves: Dictionary[String, Curve3D] = {}
	var roads := _roads()
	for file_name in roads:
		var curve := ResourceLoader.load("%s/%s" % [DIR, file_name]) as Curve3D
		if curve == null:
			printerr("[car-arena] cannot load %s — run `-- scaffold` first" % file_name)
			return 1
		# The saved curve is what the level drives on. A turtle that has moved since means the
		# scaffold is stale, and zones placed from it would sit off the road.
		var t := roads[file_name]
		var stale := curve.point_count != t.points.size()
		for p in t.points:
			stale = stale or curve.get_closest_point(p).distance_to(p) > 0.5
		if stale:
			printerr("[car-arena] %s no longer matches the scaffold — re-run it" % file_name)
			return 1
		curves[file_name] = curve
	var strip := curves["car_arena_strip_curve.tres"]
	var corners := curves["car_arena_corners_curve.tres"]
	var winding := curves["car_arena_winding_curve.tres"]
	var turtle := roads["car_arena_corners_curve.tres"]

	var built := {
		"car_start_up": _start_up(strip),
		"car_easy_turns": _easy_turns(winding),
		"car_box_stop": _box_stop(strip, true),
		"car_box_blind": _box_stop(strip, false),
		"car_turn_signals": _turn_signals(corners, turtle),
		"car_speed_trap": _speed_trap(strip),
	}
	# All or none: a course that failed to build leaves the others unwritten too.
	if built.values().has(null):
		for root: Variant in built.values():
			if root != null:
				(root as Node).free()
		return 1
	for id: String in built:
		if not _pack(built[id] as Node3D, "%s/%s_course.tscn" % [COURSE_DIR, id]):
			return 1
	print("[car-arena] courses done.")
	return 0


## Car 1: spawn at the strip's west end, a finish line down the road.
func _start_up(strip: Curve3D) -> Node3D:
	var root := _course_root("CarStartUpCourse")
	var mats := _materials()
	_spawn(root, strip, START_UP_SPAWN_X - STRIP_START_X)
	var at := START_UP_FINISH_X - STRIP_START_X
	_zone(root, "Finish", strip, at - 0.5, at + 0.5, STRIP_ZONE_WIDTH)
	var markers := _markers(root)
	_line(markers, strip, at, 1.0, mats["white"], "FinishLine")
	_posts(markers, strip, at, mats["dark"], "Finish")
	return root


## Car 2: the whole winding road, start to finish.
func _easy_turns(winding: Curve3D) -> Node3D:
	var root := _course_root("CarEasyTurnsCourse")
	var mats := _materials()
	_spawn(root, winding, 8.0)
	var at := winding.get_baked_length() - FINISH_BEFORE_END
	_zone(root, "Finish", winding, at - 0.5, at + 0.5, STRIP_ZONE_WIDTH)
	var markers := _markers(root)
	_line(markers, winding, at, 1.0, mats["white"], "FinishLine")
	_posts(markers, winding, at, mats["dark"], "Finish")
	return root


## Car 3 and Car 6: gate, box and the overrun past it, on the strip. Car 6's box is unmarked (a
## painted one would show in the fog), so the two courses differ only by the paint.
func _box_stop(strip: Curve3D, marked: bool) -> Node3D:
	var root := _course_root("CarBoxStopCourse" if marked else "CarBoxBlindCourse")
	var mats := _materials()
	_spawn(root, strip, START_UP_SPAWN_X - STRIP_START_X)
	var gate := BOX_GATE_X - STRIP_START_X
	var box0 := gate + BOX_GATE_TO_BOX
	var box1 := box0 + BOX_LENGTH
	var over0 := box1 + BOX_OVERRUN_GAP
	_zone(root, "Gate", strip, gate - 0.25, gate + 0.25, STRIP_ZONE_WIDTH)
	_zone(root, "Box", strip, box0, box1, BOX_WIDTH)
	_zone(root, "Overrun", strip, over0, strip.get_baked_length(), STRIP_ZONE_WIDTH)
	var markers := _markers(root)
	_line(markers, strip, gate, LINE_W, mats["white"], "GateLine")
	_posts(markers, strip, gate, mats["dark"], "Gate")
	if marked:
		_outline(markers, strip, box0, box1, BOX_WIDTH, mats["yellow"], "Box")
	return root


## Car 10: a trap the paved width of the strip, and the thin exit across its far end.
func _speed_trap(strip: Curve3D) -> Node3D:
	var root := _course_root("CarSpeedTrapCourse")
	var mats := _materials()
	_spawn(root, strip, START_UP_SPAWN_X - STRIP_START_X)
	var from := TRAP_FROM_X - STRIP_START_X
	var to := TRAP_TO_X - STRIP_START_X
	_zone(root, "Trap", strip, from, to, _paved_width())
	_zone(root, "TrapExit", strip, to, to + TRAP_EXIT_LENGTH, _paved_width())
	var markers := _markers(root)
	_line(markers, strip, from, LINE_W, mats["amber"], "TrapStartLine")
	_posts(markers, strip, from, mats["dark"], "TrapStart")
	_line(markers, strip, to, LINE_W, mats["white"], "TrapEndLine")
	_posts(markers, strip, to, mats["dark"], "TrapEnd")
	return root


## Car 4: a signal window before each corner and a clear window after it, then a finish.
func _turn_signals(corners: Curve3D, turtle: Turtle) -> Node3D:
	var root := _course_root("CarTurnSignalsCourse")
	var mats := _materials()
	var markers := _markers(root)
	_spawn(root, corners, 8.0)
	var windows: Array[Vector2] = []
	for i in CORNER_TURNS.size():
		var o_in := corners.get_closest_offset(turtle.marks["c%d_in" % i])
		var o_out := corners.get_closest_offset(turtle.marks["c%d_out" % i])
		var n := i + 1
		windows.append(Vector2(o_in - SIGNAL_LENGTH, o_in))
		windows.append(Vector2(o_out + CLEAR_FROM, o_out + CLEAR_TO))
		_zone(root, "Signal%d" % n, corners, o_in - SIGNAL_LENGTH, o_in, CORNER_ZONE_WIDTH)
		_zone(root, "Clear%d" % n, corners, o_out + CLEAR_FROM, o_out + CLEAR_TO,
				CORNER_ZONE_WIDTH)
		_line(markers, corners, o_in - SIGNAL_LENGTH, LINE_W, mats["amber"], "SignalLine%d" % n)
		_line(markers, corners, o_out + CLEAR_FROM, LINE_W, mats["white"], "ClearLine%d" % n)
		_chevron(markers, turtle, "c%d" % i, mats["amber"], mats["dark"], "Chevron%d" % n)
	var end := corners.get_baked_length() - FINISH_BEFORE_END
	windows.append(Vector2(end - 0.5, end + 0.5))
	if windows[0].x < 8.0 + WINDOW_GAP_MIN:
		printerr("[car-arena] the first signal window starts on top of the spawn")
		root.free()
		return null
	for i in range(1, windows.size()):
		if windows[i].x - windows[i - 1].y < WINDOW_GAP_MIN:
			printerr("[car-arena] corner windows %d and %d are under %.0f m apart" % [
					i - 1, i, WINDOW_GAP_MIN])
			root.free()
			return null
	_zone(root, "Finish", corners, end - 0.5, end + 0.5, CORNER_ZONE_WIDTH)
	_line(markers, corners, end, 1.0, mats["white"], "FinishLine")
	_posts(markers, corners, end, mats["dark"], "Finish")
	return root


# ------------------------------------------------------------------------------ course pieces


func _course_root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var preview := ArenaPreview.new()
	preview.name = "ArenaPreview"
	preview.arena = ARENA_ID
	root.add_child(preview)
	return root


func _markers(root: Node3D) -> Node3D:
	var markers := Node3D.new()
	markers.name = "Markers"
	root.add_child(markers)
	return markers


## The road's frame at `offset`: origin on the deck centreline, local Z along the direction of
## travel, Y up.
func _frame(curve: Curve3D, offset: float) -> Transform3D:
	var length := curve.get_baked_length()
	var o := clampf(offset, 0.0, length)
	var a := curve.sample_baked(clampf(o - 0.5, 0.0, length))
	var b := curve.sample_baked(clampf(o + 0.5, 0.0, length))
	var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var x := Vector3.UP.cross(t)
	return Transform3D(Basis(x, Vector3.UP, t), curve.sample_baked(o))


## A VehicleSpawn on the deck facing along the road: a car's forward is its -Z.
func _spawn(root: Node3D, curve: Curve3D, offset: float) -> void:
	var f := _frame(curve, offset)
	var spawn := VehicleSpawn.new()
	spawn.name = "Spawn"
	spawn.vehicle_types = PackedStringArray(["car"])
	spawn.transform = Transform3D(Basis(-f.basis.x, Vector3.UP, -f.basis.z),
			f.origin + Vector3.UP * SPAWN_CLEARANCE)
	root.add_child(spawn)


## A box zone over the road between two offsets, aligned with the road at their middle.
func _zone(root: Node3D, zone_name: String, curve: Curve3D, from: float, to: float,
		width: float) -> void:
	var f := _frame(curve, (from + to) * 0.5)
	var zone := ChallengeZone.new()
	zone.name = zone_name
	zone.size = Vector3(width, ZONE_HEIGHT, to - from)
	zone.transform = Transform3D(f.basis,
			f.origin + Vector3.UP * (ZONE_BASE + ZONE_HEIGHT * 0.5))
	root.add_child(zone)


## A painted line across the road's paved width at `offset`, `thickness` along the road.
func _line(markers: Node3D, curve: Curve3D, offset: float, thickness: float, mat: Material,
		node_name: String) -> void:
	var f := _frame(curve, offset)
	_paint(markers, node_name, Transform3D(f.basis, f.origin + Vector3.UP * MARK_LIFT),
			Vector2(_paved_width(), thickness), mat)


## A painted rectangle outline between two offsets, `width` across.
func _outline(markers: Node3D, curve: Curve3D, from: float, to: float, width: float,
		mat: Material, node_name: String) -> void:
	var f := _frame(curve, (from + to) * 0.5)
	var lift := f.origin + Vector3.UP * MARK_LIFT
	var length := to - from
	var hw := width * 0.5 - LINE_W * 0.5
	var hl := length * 0.5 - LINE_W * 0.5
	_paint(markers, node_name + "Near", Transform3D(f.basis, lift - f.basis.z * hl),
			Vector2(width, LINE_W), mat)
	_paint(markers, node_name + "Far", Transform3D(f.basis, lift + f.basis.z * hl),
			Vector2(width, LINE_W), mat)
	_paint(markers, node_name + "Left", Transform3D(f.basis, lift - f.basis.x * hw),
			Vector2(LINE_W, length), mat)
	_paint(markers, node_name + "Right", Transform3D(f.basis, lift + f.basis.x * hw),
			Vector2(LINE_W, length), mat)


## Two posts just off the road's edges at `offset`, so a line reads from the chase camera.
func _posts(markers: Node3D, curve: Curve3D, offset: float, mat: Material,
		node_name: String) -> void:
	var f := _frame(curve, offset)
	var out := _paved_width() * 0.5 + 1.5
	for side: float in [-1.0, 1.0]:
		var at := f.origin + f.basis.x * out * side + Vector3.UP * 1.25
		_solid(markers, "%sPost%s" % [node_name, "L" if side < 0.0 else "R"],
				Transform3D(f.basis, at), Vector3(0.25, 2.5, 0.25), mat)


## A board on a post outside a corner, facing the arc's centre so the approach sees it.
func _chevron(markers: Node3D, turtle: Turtle, corner: String, board: Material, post: Material,
		node_name: String) -> void:
	var mid: Vector3 = turtle.marks[corner + "_mid"]
	var centre: Vector3 = turtle.marks[corner + "_c"]
	var outward := Vector3(mid.x - centre.x, 0.0, mid.z - centre.z).normalized()
	var base := mid + outward * (_paved_width() * 0.5 + 4.0)
	var facing := Basis(Vector3.UP.cross(outward), Vector3.UP, outward)
	_solid(markers, node_name + "Post", Transform3D(facing, base + Vector3.UP * 0.9),
			Vector3(0.2, 1.8, 0.2), post)
	_solid(markers, node_name, Transform3D(facing, base + Vector3.UP * 1.8),
			Vector3(3.0, 0.9, 0.12), board)


func _paint(markers: Node3D, node_name: String, xform: Transform3D, size: Vector2,
		mat: Material) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.material = mat
	_mesh_node(markers, node_name, xform, mesh)


func _solid(markers: Node3D, node_name: String, xform: Transform3D, size: Vector3,
		mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	_mesh_node(markers, node_name, xform, mesh)


## A course marker is paint and posts only: no collision (a course is not baked, so anything
## solid here would be a live body in the attempt) and no shadow.
func _mesh_node(markers: Node3D, node_name: String, xform: Transform3D, mesh: Mesh) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.transform = xform
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.add_child(node)


func _materials() -> Dictionary:
	var out := {}
	for key: String in ["white", "yellow", "amber", "dark"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = {"white": WHITE, "yellow": YELLOW, "amber": AMBER, "dark": DARK}[key]
		mat.roughness = 0.9
		out[key] = mat
	return out


func _paved_width() -> float:
	var profile := ResourceLoader.load(ASPHALT_PROFILE)
	return float(profile.call("paved_half_width")) * 2.0


func _pack(root: Node3D, path: String) -> bool:
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var packed := PackedScene.new()
	var ok := packed.pack(root) == OK and ResourceSaver.save(packed, path) == OK
	root.free()
	if not ok:
		printerr("[car-arena] cannot save %s" % path)
		return false
	print("[car-arena] wrote %s" % path)
	return true


# ============================================================================ text artifacts


func _info_text() -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo" format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("car")
default_vehicle = "car"
""" % TITLE


func _scene_text() -> String:
	var f := _frame(_strip().curve(), START_UP_SPAWN_X - STRIP_START_X)
	var spawn := Transform3D(Basis(-f.basis.x, Vector3.UP, -f.basis.z),
			f.origin + Vector3.UP * SPAWN_CLEARANCE)
	return """[gd_scene format=3]

[ext_resource type="Script" path="res://src/levels/base/level.gd" id="1_level"]
[ext_resource type="Resource" path="res://src/levels/island/car_arena/car_arena_info.tres" id="2_info"]
[ext_resource type="Script" path="res://src/vehicles/base/chase_camera.gd" id="3_cam"]
[ext_resource type="Script" path="res://src/levels/base/vehicle_spawn.gd" id="4_spawn"]
[ext_resource type="Script" path="res://src/levels/base/heightmap_terrain.gd" id="5_terrain"]
[ext_resource type="Texture2D" path="res://src/levels/island/car_arena/car_arena_island_height.png" id="6_height"]
[ext_resource type="Texture2D" path="res://src/levels/island/car_arena/car_arena_island_splat.png" id="7_splat"]
[ext_resource type="Shader" path="res://kit/terrain/terrain_splat.gdshader" id="8_shader"]
[ext_resource type="Script" path="res://src/water/water_surface.gd" id="9_water"]
[ext_resource type="Script" path="res://kit/helpers/authoring_root.gd" id="10_authoring"]
[ext_resource type="Environment" path="res://src/levels/base/default_env.tres" id="11_env"]
[ext_resource type="Script" path="res://kit/helpers/road_path.gd" id="12_road"]
[ext_resource type="Resource" path="res://kit/roads/asphalt_profile.tres" id="13_asphalt"]
[ext_resource type="Resource" path="res://src/levels/island/car_arena/car_arena_strip_curve.tres" id="14_strip"]
[ext_resource type="Resource" path="res://src/levels/island/car_arena/car_arena_corners_curve.tres" id="15_corners"]
[ext_resource type="Resource" path="res://src/levels/island/car_arena/car_arena_winding_curve.tres" id="16_winding"]
[ext_resource type="Texture2D" path="res://src/levels/island/car_arena/car_arena_island_splat2.png" id="17_splat2"]
[ext_resource type="Script" path="res://src/levels/base/world_bounds.gd" id="18_bounds"]

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
shader_parameter/color5 = Color(0.92, 0.94, 0.97, 1)
shader_parameter/color6 = Color(0.3, 0.24, 0.17, 1)
shader_parameter/color7 = Color(0.22, 0.22, 0.24, 1)
shader_parameter/color8 = Color(0.62, 0.6, 0.56, 1)
shader_parameter/splatmap = ExtResource("7_splat")
shader_parameter/splatmap2 = ExtResource("17_splat2")
shader_parameter/blend_sharpness = 8.0
shader_parameter/roughness_value = 1.0

[node name="CarArena" type="Node3D"]
script = ExtResource("1_level")
info = ExtResource("2_info")

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
transform = {spawn}
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("car")

[node name="Sea" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {sea_y}, 0)
script = ExtResource("9_water")
size = Vector2({size_plus}, {size_plus})
depth = {sea_depth}
far_sea_extent = 1900.0

[node name="Bounds" type="StaticBody3D" parent="."]
script = ExtResource("18_bounds")
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
splatmap2 = ExtResource("17_splat2")
channel_names = PackedStringArray({channel_names})
channel_grip = PackedFloat32Array({channel_grip})
sand_height = {sand_height}
dirt_slope_deg = 22.0
rock_slope_deg = 38.0

[node name="AuthoringRoot" type="Node3D" parent="."]
script = ExtResource("10_authoring")
chunk_size = 64.0
metadata/_custom_type_script = "uid://t88htpmwukbg"

[node name="Strip" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_asphalt")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/Strip"]
curve = ExtResource("14_strip")

[node name="Corners" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_asphalt")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/Corners"]
curve = ExtResource("15_corners")

[node name="Winding" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_asphalt")
conform_falloff = {conform_falloff}
conform_epsilon = {conform_epsilon}
metadata/_custom_type_script = "uid://cpl5vh8pdc04w"

[node name="Path" type="Path3D" parent="AuthoringRoot/Winding"]
curve = ExtResource("16_winding")
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
		"spawn": var_to_str(spawn),
	})


# ==================================================================================== helpers


func _write_png(img: Image, path: String) -> bool:
	if img.save_png(path) != OK:
		printerr("[car-arena] failed to write %s" % path)
		return false
	TerrainGen.ensure_import_settings(path)
	print("[car-arena] wrote %s" % path)
	return true


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[car-arena] cannot write %s" % path)
		return
	f.store_string(text)
	print("[car-arena] wrote %s" % path)


# World <-> pixel, HeightmapTerrain's own convention: the grid spans [-span/2, +span/2] in
# the terrain's local frame at one cell per world unit, and this terrain sits at the origin.


func _norm(world_y: float) -> float:
	return clampf(world_y / HEIGHT, 0.0, 1.0)


func _px_x(world_x: float) -> int:
	return clampi(int(round((world_x + SIZE * 0.5) * _sx)), 0, _iw - 1)


func _px_z(world_z: float) -> int:
	return clampi(int(round((world_z + SIZE * 0.5) * _sz)), 0, _ih - 1)
