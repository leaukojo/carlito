extends Node
## Author the ISOBUS farm playground into the free centre of level 1. Four features, each
## there to make one tractor signal visibly perform: FIELD (splat channel 4, ploughable soil),
## WALLOW (mud hollow with a cross-axle ridge course for diff_lock), RAMP (a climb needing
## fwd_drive/MFWD at the top), YARD (apron with shed/tank/implements to drive to).
## Game-mode tool scene (loads a level scene, needs autoloads registered). Chain recorded in
## src/levels/island/level_1/level_1_gen.json (tools/CLAUDE.md). Re-running `build` is
## deterministic but re-flattens on top of the previous flatten (slightly sharpens blend
## rims) — restore from tmp/level_1_original/ before changing the geometry constants below.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

const LEVEL_PATH := "res://src/levels/island/level_1/level_1.tscn"

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")

const ROADS_MESHLIB := "res://kit/palettes/roads.meshlib"
const APRON_TILE := "tile-low"           ## plain 12 m concrete slab, 0.24 m deck
const SHED_PREFAB := "res://kit/prefabs/industrial/building-h.tscn"
const TANK_PREFAB := "res://kit/prefabs/industrial/detail-tank.tscn"
const FENCE_PREFAB := "res://kit/prefabs/nature/fence_simple.tscn"
const FURROW_PREFAB := "res://kit/prefabs/nature/crops_dirtDoubleRow.tscn"
const IMPLEMENT_SCENES: PackedStringArray = [
	"res://src/vehicles/tractor/implements/plough.tscn",
	"res://src/vehicles/tractor/implements/harrow.tscn",
	"res://src/vehicles/tractor/implements/mower.tscn",
	"res://src/vehicles/tractor/implements/spreader.tscn",
]
## Implements are authored in the LOWERED pose with the origin on the lower pin line, and
## ground sits at y = -0.21 in that frame (see src/vehicles/tractor/implements/plough.tscn).
const IMPLEMENT_GROUND_OFFSET := 0.21

# --- splat channels -------------------------------------------------------------------
const CH_GRASS := 0
const CH_FIELD := 4     ## splatmap2.R — the ploughable soil, phase 6's "in soil" predicate
const CH_MUD := 5       ## splatmap2.G — wallow + haul ramp, grip 0.5
const CH_GRAVEL := 7    ## splatmap2.A — yard surround and farm tracks
## Packed*Array constructors are not constant expressions, so these are plain typed arrays
## converted at the call site (the same dodge HeightmapTerrain.default_channel_names uses).
const CHANNEL_NAMES: Array[String] = [
	"Grass", "Dirt", "Sand", "Rock", "Field", "Mud", "Asphalt", "Gravel",
]
const CHANNEL_GRIP: Array[float] = [0.8, 0.7, 0.6, 0.7, 0.7, 0.5, 1.0, 0.85]
## Fresh tilled loam: lighter than Mud (0.30/0.24/0.17), darker than Dirt (0.52/0.40/0.26),
## so the field reads as its own surface against both.
const FIELD_COLOR := Color(0.44, 0.29, 0.17)

# --- site geometry, world XZ metres. Rect2 = (x_min, z_min, width, depth). -------------
# The centre of level 1 is a 27 m terrace; the 36 m terrace sits west of it, flat over
# x in [-104, -72], z in [-16, +40]. Both measured off the committed heightmap.
const PLATEAU_Y := 27.0
const TERRACE_Y := 36.0

const FIELD_RECT := Rect2(-24, 26, 64, 90)        ## 64 x 90 m — ~90 m plough passes
const FURROW_RECT := Rect2(-24, 34, 18, 70)       ## the already-ploughed western strip
const PADDOCK_RECT := Rect2(-100, -16, 20, 44)    ## the haul ramp's destination, at 36 m

## The wallow sits between the yard pad (ends at z = 0) and the fence line, so leaving the yard
## for the field goes through it, though its west/east edges stay open to drive around.
const WALLOW_RECT := Rect2(-2, 4, 24, 14)
## The blend ring is the wallow's entry/exit ramp, so its width sets their grade: 8 m gives
## ~7.5% (half of a 4 m ring) so climbing out is a gentle roll, not a step.
const WALLOW_MARGIN := 8.0
const WALLOW_Y := 26.4                            ## 0.6 m below the plateau (3 height steps)
const RIDGE_AMPLITUDE := 0.4                      ## m; 2 steps of the 8-bit 0.2 m grid
const RIDGE_PITCH := 5.0                          ## m between crests, measured perpendicular
const RIDGE_TAPER := 3.0                          ## m of fade to nothing at the wallow rim
const RIM_SMOOTH_PASSES := 4                      ## evens the exit ramp's 8-bit staircase

## Haul ramp: three straight segments along z = RAMP_Z, grades 8.1 / 14.0 / 23.6 degrees. Sized
## against mu 0.5 (mud), rear static share 0.476: rear-drive alone tops out ~16.7 deg, all-wheel
## ~26.6 deg. Progressive so the crossover is a place on the hill, not a knife-edge threshold.
const RAMP_Z := -18.0
const RAMP_HALF_WIDTH := 8.0
const RAMP_PROFILE: Array[Vector2] = [   ## (world x, world y) along the climb
	Vector2(-42.0, 27.0),
	Vector2(-56.0, 29.0),
	Vector2(-70.0, 32.5),
	Vector2(-78.0, 36.0),
]

## Apron cell chosen by asking the GridMap where this point lands. Tiles are corner-anchored on
## a centre-true lattice ("align": "raw" in kit/import/roads.json), so a slab spans
## [12i, 12i+12], half a cell east/south of the request — offset to compensate; the code
## measures where tiles actually land and prints it regardless.
const APRON_CENTER := Vector2(6.0, -24.0)    ## -> tiles at x [-6, 30], z [-30, -6]
const APRON_CELLS_X := 3
const APRON_CELLS_Z := 2
const APRON_MARGIN := 6.0                    ## flattened + gravelled ring around the tiles
## Apron-local layout, metres from its south-west corner (the apron is 36 x 24 m).
const BUILDING_ROW_Z := 6.0                  ## shed + tank
## The parking row sits this far north so the tractor spawn has a trailer-length of clear
## concrete behind it: drawbar pin 1.6 m aft of chassis origin + tipper reaching 5.3 m aft of
## the pin needs ~6.9 m at -Z. 18.0 left only 6.1 m clear of the shed wall and the first E
## press at spawn was refused by the fit check; 22.0 leaves 3.2 m of slack.
const PARKING_ROW_Z := 22.0                  ## implements + tractor spawn
const SHED_X := 9.0
const SHED_YAW := PI                         ## frontage faces +Z, into the yard
const TANK_X := 30.0
const SPAWN_X := 3.0
const IMPLEMENT_X: Array[float] = [10.0, 17.0, 24.0, 31.0]

const GATE_X := Vector2(1.0, 14.0)           ## the gap left in the field fence
## Just inside the field's flat, so the fence stands on level ground rather than partway up
## the wallow's exit ramp (which now reaches all the way to the field edge).
const FENCE_Z := 26.5
const FENCE_SPAN := 5.0                      ## nature/fence_simple is 5 m per section

const FLATTEN_MARGIN := 6.0                  ## blend ring on every flattened rectangle
const TRACK_WIDTH := 10.0

## Farm nodes this tool owns: deleted and rebuilt on every `build` run.
const OWNED_NODES: PackedStringArray = [
	"RoadsTiles", "FarmProps", "FarmImplements", "ScatterCanvasFurrows",
]
const SPAWN_NODE := "FarmSpawn"

# --- terrain mapping, filled in by _read_terrain ---------------------------------------
var _terrain: Node = null
var _theight := 51.0
var _span := Vector2(512, 512)
var _torigin := Vector3.ZERO
var _iw := 0
var _ih := 0
var _sx := 1.0    ## height/splat pixels per metre on X
var _sz := 1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var stage := String(args[0]) if not args.is_empty() else "build"
	if stage != "build" and stage != "resnap":
		printerr("[farm] usage: -- build | resnap")
		get_tree().quit(1)
		return

	var packed := load(LEVEL_PATH) as PackedScene
	if packed == null:
		printerr("[farm] cannot load %s" % LEVEL_PATH)
		get_tree().quit(1)
		return
	var root := packed.instantiate()

	# `build` sculpts/paints/rebuilds every farm node; `resnap` re-snaps scatter Ys and
	# stamps the real ground hash once the sculpted PNG is reimported.
	var code := _build(root) if stage == "build" else _resnap(root)
	if code == 0:
		code = _save(root)
	root.free()
	get_tree().quit(code)


# ============================================================================== build


func _build(root: Node) -> int:
	if not _read_terrain(root):
		return 1
	var authoring := Groups.find_authoring(root)
	if authoring == null:
		printerr("[farm] level has no AuthoringRoot")
		return 1

	var height_img := _decode(_terrain.get("heightmap"))
	var splat := SplatPaint.decode(_terrain.get("splatmap"))
	var splat2 := SplatPaint.decode(_terrain.get("splatmap2"))
	if height_img == null or splat == null or splat2 == null:
		printerr("[farm] terrain is missing a heightmap / splatmap / splatmap2")
		return 1
	if height_img.get_format() != Image.FORMAT_L8:
		height_img.convert(Image.FORMAT_L8)
	_iw = height_img.get_width()
	_ih = height_img.get_height()
	_sx = float(_iw - 1) / maxf(_span.x, 0.001)
	_sz = float(_ih - 1) / maxf(_span.y, 0.001)
	if splat.get_size() != height_img.get_size() or splat2.get_size() != splat.get_size():
		printerr("[farm] heightmap and splatmap sizes disagree — refusing to paint")
		return 1

	# The apron is a real GridMap; build it first, measure the world rect its cells occupy,
	# and derive the yard pad, props and spawn from that.
	var built := _build_apron_gridmap()
	if built.is_empty():
		return 1
	var grid: GridMap = built["grid"]
	var apron: Rect2 = built["rect"]
	var deck_y: float = built["deck_y"]
	var yard_pad := apron.grow(APRON_MARGIN)
	print("[farm] apron tiles cover x %.1f..%.1f, z %.1f..%.1f, deck y %.2f" % [
			apron.position.x, apron.end.x, apron.position.y, apron.end.y, deck_y])

	# --- sculpt (authoring order: terrain first, everything else reads it back) ---------
	_flatten(height_img, FIELD_RECT, PLATEAU_Y)
	_flatten(height_img, PADDOCK_RECT, TERRACE_Y)
	_flatten(height_img, yard_pad, PLATEAU_Y)
	_ramp(height_img)
	_flatten(height_img, WALLOW_RECT, WALLOW_Y, WALLOW_MARGIN)
	_ridges(height_img)
	_smooth(height_img, _wallow_rim_rect(), RIM_SMOOTH_PASSES)

	# --- paint (later strokes win, so the gravel track visibly dies in the wallow) ------
	# Grass first over every rectangle whose slope we just removed, since auto-splat's old
	# dirt/rock on the hump and bank would otherwise survive on now-flat ground.
	var repairs: Array[Rect2] = [
		FIELD_RECT.grow(FLATTEN_MARGIN + 4.0), PADDOCK_RECT.grow(FLATTEN_MARGIN + 4.0),
		yard_pad.grow(FLATTEN_MARGIN), WALLOW_RECT.grow(WALLOW_MARGIN), _ramp_rect(),
	]
	for repair in repairs:
		_paint(splat, splat2, repair, CH_GRASS)
	_paint(splat, splat2, yard_pad, CH_GRAVEL)
	_paint(splat, splat2, _gate_track_rect(), CH_GRAVEL)
	_paint(splat, splat2, _ramp_track_rect(apron), CH_GRAVEL)
	_paint(splat, splat2, FIELD_RECT, CH_FIELD)
	_paint(splat, splat2, PADDOCK_RECT, CH_FIELD)
	_paint(splat, splat2, _ramp_rect(), CH_MUD)
	_paint(splat, splat2, WALLOW_RECT, CH_MUD)

	# --- level data the new surfaces need ----------------------------------------------
	_terrain.set("channel_names", PackedStringArray(CHANNEL_NAMES))
	_terrain.set("channel_grip", PackedFloat32Array(CHANNEL_GRIP))
	var mat := _terrain.get("material") as ShaderMaterial
	if mat == null:
		printerr("[farm] terrain material is not a ShaderMaterial — cannot recolour channel 4")
		return 1
	mat.set_shader_parameter(&"color5", FIELD_COLOR)

	# --- authoring nodes ----------------------------------------------------------------
	for owned in OWNED_NODES:
		var stale := authoring.get_node_or_null(NodePath(owned))
		if stale != null:
			authoring.remove_child(stale)
			stale.free()
	_add(authoring, grid, root)
	_build_props(authoring, root, height_img, apron, deck_y)
	_build_implements(authoring, root, apron, deck_y)
	_build_furrows(authoring, root, height_img)
	_build_spawns(root, apron, deck_y)

	# --- scatter: clear the farm footprint, re-snap the rest onto the new ground --------
	var footprint := _farm_footprint(apron)
	var cleared := 0
	var moved := 0
	for canvas in _scatter_canvases(root):
		cleared += _erase_rects(canvas, footprint)
		moved += _resnap_from_image(canvas, height_img)
		# Left empty: needs the reimported png, so `resnap` stamps it — skipping that stage
		# then fails the bake loudly instead of shipping props snapped to stale ground.
		canvas.set("stored_ground_hash", "")
	print("[farm] scatter: %d instances erased inside the farm, %d re-snapped" % [cleared, moved])

	if not _write(height_img, _terrain.get("heightmap")):
		return 1
	if not _write(splat, _terrain.get("splatmap")):
		return 1
	if not _write(splat2, _terrain.get("splatmap2")):
		return 1

	_report(height_img, splat, splat2, apron, deck_y)
	return 0


# -------------------------------------------------------------------------- sculpting


## Flatten `rect` to `target_y` with a soft blend ring `margin` wide, using the square brush
## stamp. Falloff derives from the longer half-extent so the hard core covers both axes
## (BrushOps' square brush measures one Chebyshev distance against per-axis radii).
func _flatten(img: Image, rect: Rect2, target_y: float, margin := FLATTEN_MARGIN) -> void:
	var half_x := rect.size.x * 0.5 + margin
	var half_z := rect.size.y * 0.5 + margin
	var falloff := margin / maxf(half_x, half_z)
	var c := rect.get_center()
	BrushOps.stamp_height(img, _px_x(c.x), _px_z(c.y), half_x * _sx, half_z * _sz,
			BrushOps.FLATTEN, 1.0, falloff, _norm(target_y), true)


## The band the wallow's exit ramp onto the field occupies — the blend ring on its north
## side, plus a metre of overlap into the flat at each end so the smooth pass has real
## ground to blend towards.
func _wallow_rim_rect() -> Rect2:
	return Rect2(WALLOW_RECT.position.x - WALLOW_MARGIN, WALLOW_RECT.end.y - 1.0,
			WALLOW_RECT.size.x + WALLOW_MARGIN * 2.0, WALLOW_MARGIN + 3.0)


## Run the terrain brush's SMOOTH mode over `rect`, `passes` times, hard-edged. The 8-bit
## heightmap makes the wallow's 0.6 m climb onto the field only three steps, uneven and
## non-monotonic where the field's and wallow's blend rings overlap; smoothing redistributes
## those risers evenly (can't add resolution, just stops the staircase being lumpy).
func _smooth(img: Image, rect: Rect2, passes: int) -> void:
	var c := rect.get_center()
	for _i in passes:
		BrushOps.stamp_height(img, _px_x(c.x), _px_z(c.y),
				rect.size.x * 0.5 * _sx, rect.size.y * 0.5 * _sz,
				BrushOps.SMOOTH, 1.0, 0.0, 0.0, true)


## The haul ramp: one BrushOps.stamp_ramp per profile segment. Each is a constant-grade
## drivable surface with round caps and a soft shoulder that blends into the existing bank.
func _ramp(img: Image) -> void:
	for i in RAMP_PROFILE.size() - 1:
		var a := RAMP_PROFILE[i]
		var b := RAMP_PROFILE[i + 1]
		BrushOps.stamp_ramp(img,
				Vector2i(_px_x(a.x), _px_z(RAMP_Z)), _norm(a.y),
				Vector2i(_px_x(b.x), _px_z(RAMP_Z)), _norm(b.y),
				RAMP_HALF_WIDTH * _sx, RAMP_HALF_WIDTH * _sz, 1.0, 0.45)


## The cross-axle course in the wallow floor: a sine whose wavefronts run at 45 degrees to the
## yard -> field direction, so the rear wheels ride opposite phases and the axle articulates.
## Phase is (x + z), gradient magnitude sqrt(2), hence the sqrt(2) in wavelength (makes
## RIDGE_PITCH the true perpendicular crest spacing). Tapers to nothing over RIDGE_TAPER metres
## so no step forms at the wallow rim. Written straight into the working image (no ridge brush
## mode exists in the kit) rather than through BrushOps, the only such exception here.
func _ridges(img: Image) -> void:
	var amp := RIDGE_AMPLITUDE / _theight
	var wavelength := RIDGE_PITCH * sqrt(2.0)
	for pz in range(_px_z(WALLOW_RECT.position.y), _px_z(WALLOW_RECT.end.y) + 1):
		var wz := _world_z(pz)
		for px in range(_px_x(WALLOW_RECT.position.x), _px_x(WALLOW_RECT.end.x) + 1):
			var wx := _world_x(px)
			var edge := minf(minf(wx - WALLOW_RECT.position.x, WALLOW_RECT.end.x - wx),
					minf(wz - WALLOW_RECT.position.y, WALLOW_RECT.end.y - wz))
			var k := clampf(edge / RIDGE_TAPER, 0.0, 1.0)
			var w := k * k * (3.0 - 2.0 * k)   # smoothstep, the shape the brush falloff uses
			if w <= 0.0:
				continue
			var nv := clampf(img.get_pixel(px, pz).r
					+ w * amp * sin(TAU * (wx + wz) / wavelength), 0.0, 1.0)
			img.set_pixel(px, pz, Color(nv, nv, nv))


# --------------------------------------------------------------------------- painting


## Paint `rect` with `channel` at full strength and a hard edge into both weight images (each
## takes its own BrushOps.unit_slice). Full strength + hard edge is the kit's rule for a
## destructive paint: shader pow-sharpen and grip_at sharpen identically, giving a crisp
## low-poly border and full grip with no feathered low-grip apron.
func _paint(splat: Image, splat2: Image, rect: Rect2, channel: int) -> void:
	var c := rect.get_center()
	var cx := _px_x(c.x)
	var cz := _px_z(c.y)
	var rx := rect.size.x * 0.5 * _sx
	var rz := rect.size.y * 0.5 * _sz
	BrushOps.stamp_splat(splat, cx, cz, rx, rz, BrushOps.unit_slice(channel, 0), 1.0, 0.0, true)
	BrushOps.stamp_splat(splat2, cx, cz, rx, rz, BrushOps.unit_slice(channel, 1), 1.0, 0.0, true)


func _ramp_rect() -> Rect2:
	var last: Vector2 = RAMP_PROFILE[RAMP_PROFILE.size() - 1]
	var lo: float = minf(RAMP_PROFILE[0].x, last.x)
	var hi: float = maxf(RAMP_PROFILE[0].x, last.x)
	return Rect2(lo, RAMP_Z - RAMP_HALF_WIDTH, hi - lo, RAMP_HALF_WIDTH * 2.0)


## Gravel track from the yard's north edge up to the field gate. The wallow is painted over
## its middle afterwards — the track really does disappear into the mud.
func _gate_track_rect() -> Rect2:
	var cx := (GATE_X.x + GATE_X.y) * 0.5
	var z0 := WALLOW_RECT.position.y - 6.0
	return Rect2(cx - TRACK_WIDTH * 0.5, z0, TRACK_WIDTH, FENCE_Z + 4.0 - z0)


## Gravel track from the yard's west edge out to the foot of the haul ramp.
func _ramp_track_rect(apron: Rect2) -> Rect2:
	var foot: float = RAMP_PROFILE[0].x
	return Rect2(foot, RAMP_Z - TRACK_WIDTH * 0.5,
			maxf(apron.position.x - APRON_MARGIN - foot, 1.0), TRACK_WIDTH)


## Every rectangle the farm occupies — what scatter has to be cleared out of.
func _farm_footprint(apron: Rect2) -> Array[Rect2]:
	return [
		FIELD_RECT.grow(FLATTEN_MARGIN), PADDOCK_RECT.grow(FLATTEN_MARGIN),
		WALLOW_RECT.grow(WALLOW_MARGIN), _ramp_rect().grow(4.0),
		apron.grow(APRON_MARGIN + FLATTEN_MARGIN),
		_gate_track_rect(), _ramp_track_rect(apron),
		Rect2(FIELD_RECT.position.x, FENCE_Z - 3.0, FIELD_RECT.size.x, 6.0),   # the fence line
	]


# ---------------------------------------------------------------------- authoring nodes


## The yard apron as a real roads-palette GridMap. Cell indices come from asking the GridMap
## where APRON_CENTER lands (local_to_map); the world rect is measured back off the item mesh
## and palette transform, never a hand-guessed offset. Returns {} on failure.
func _build_apron_gridmap() -> Dictionary:
	var ml := load(ROADS_MESHLIB) as MeshLibrary
	if ml == null:
		printerr("[farm] cannot load %s" % ROADS_MESHLIB)
		return {}
	var item := ml.find_item_by_name(APRON_TILE)
	if item < 0:
		printerr("[farm] roads palette has no '%s' tile" % APRON_TILE)
		return {}
	var mesh := ml.get_item_mesh(item)
	if mesh == null:
		printerr("[farm] roads palette tile '%s' has no mesh" % APRON_TILE)
		return {}

	var grid := GridMap.new()
	grid.name = "RoadsTiles"
	grid.mesh_library = ml
	grid.cell_size = Vector3(12, 3, 12)
	grid.cell_center_y = false
	# Level 3's tile city uses the same offset: deck is 0.24 m thick, dropping the map 0.22 m
	# lands the driving surface 0.02 m above the plateau instead of behind a 24 cm lip.
	grid.position = Vector3(0, -0.22, 0)

	var y_cell := int(round(PLATEAU_Y / grid.cell_size.y))
	var origin := grid.local_to_map(Vector3(APRON_CENTER.x, PLATEAU_Y, APRON_CENTER.y))
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


## Shed, tank and the field fence. Every piece positioned from its measured merged mesh AABB
## (centre on XZ, base on ground), never a guessed origin convention.
func _build_props(authoring: Node, root: Node, img: Image, apron: Rect2, deck_y: float) -> void:
	var props := Node3D.new()
	props.name = "FarmProps"
	_add(authoring, props, root)

	# Apron-local layout: south row (z + 6) holds the buildings, north row (z + 18) the parked
	# implements and spawn.
	var south_z := apron.position.y + BUILDING_ROW_Z
	# Yawed 180 so the shed's frontage faces +Z (into the yard), not the apron's back edge.
	_place(props, root, SHED_PREFAB, "Shed", Vector3(apron.position.x + SHED_X, deck_y, south_z),
			SHED_YAW)
	_place(props, root, TANK_PREFAB, "FuelTank",
			Vector3(apron.position.x + TANK_X, deck_y, south_z))

	# Field fence, with a gap for the gateway. No fence_gate piece: fences have "box"
	# collision, so a gate prefab would block its own opening — an open gap is the honest fix.
	var runs: Array[Vector2] = [
		Vector2(FIELD_RECT.position.x, GATE_X.x),
		Vector2(GATE_X.y, FIELD_RECT.end.x),
	]
	var n := 0
	for run in runs:
		for i in int(floor((run.y - run.x) / FENCE_SPAN)):
			var x := run.x + (float(i) + 0.5) * FENCE_SPAN
			_place(props, root, FENCE_PREFAB, "Fence%d" % n,
					Vector3(x, _height_at(img, x, FENCE_Z), FENCE_Z))
			n += 1
	print("[farm] props: shed + tank + %d fence sections" % n)


## The four implements parked on the apron. Each wrapped in a KitPiece with collision "none":
## mandatory, since LevelBaker._collect only harvests MeshInstance3D from inside a KitPiece —
## a plain Node3D would have its meshes silently dropped at bake.
func _build_implements(authoring: Node, root: Node, apron: Rect2, deck_y: float) -> void:
	var group := Node3D.new()
	group.name = "FarmImplements"
	_add(authoring, group, root)
	var z := apron.position.y + PARKING_ROW_Z
	for i in IMPLEMENT_SCENES.size():
		var scene := load(IMPLEMENT_SCENES[i]) as PackedScene
		if scene == null:
			printerr("[farm] cannot load implement %s" % IMPLEMENT_SCENES[i])
			continue
		var piece := KitPiece.new()
		piece.collision_mode = "none"
		piece.name = "Parked%s" % IMPLEMENT_SCENES[i].get_file().get_basename().capitalize()
		piece.position = Vector3(apron.position.x + IMPLEMENT_X[i],
				deck_y + IMPLEMENT_GROUND_OFFSET, z)
		_add(group, piece, root)
		_add(piece, scene.instantiate(), root)


## Furrow dressing on the field's western strip: a ScatterCanvas on the grid pattern, laying
## drive-through dirt rows. One side already ploughed, the rest bare to work.
func _build_furrows(authoring: Node, root: Node, img: Image) -> void:
	var prefab := load(FURROW_PREFAB) as PackedScene
	if prefab == null:
		printerr("[farm] cannot load %s" % FURROW_PREFAB)
		return
	var item := ScatterItem.new()
	item.prefab = prefab
	item.collision = false
	item.cast_shadow = false   # flat ground detail; the shadow pass is not worth it
	var table: Array[ScatterItem] = [item]

	var canvas := ScatterCanvas.new()
	canvas.name = "ScatterCanvasFurrows"
	canvas.paint_pattern = "grid"
	canvas.grid_step = Vector2(2.5, 2.34)   # the piece's own footprint: rows abut, no gaps
	canvas.yaw_jitter_deg = 0.0             # furrows run straight, they are not scattered
	canvas.scale_range = Vector2(1.0, 1.0)
	canvas.min_spacing = 0.0
	canvas.max_slope_deg = 20.0
	canvas.items = table
	_add(authoring, canvas, root)

	var placements := ScatterRegion.generate_grid_placements({
		"polygon": PackedVector2Array([
			FURROW_RECT.position, Vector2(FURROW_RECT.end.x, FURROW_RECT.position.y),
			FURROW_RECT.end, Vector2(FURROW_RECT.position.x, FURROW_RECT.end.y),
		]),
		"step": canvas.grid_step,
		"seed": 0,
		"weights": PackedFloat32Array([1.0]),
		"yaw_jitter_deg": 0.0,
		"scale_min": 1.0,
		"scale_max": 1.0,
	})
	var stored: Array[PackedFloat32Array] = []
	var count := 0
	for flat in placements:
		var out := PackedFloat32Array()
		@warning_ignore("integer_division")
		var instances := flat.size() / 4
		for j in instances:
			var o := j * 4
			out.append_array(PackedFloat32Array([
					flat[o], _height_at(img, flat[o], flat[o + 1]), flat[o + 1],
					flat[o + 2], flat[o + 3]]))
			count += 1
		stored.append(out)
	canvas.stored_transforms = stored
	canvas.stored_ground_hash = ""
	print("[farm] furrows: %d dirt rows over %.0f x %.0f m" % [
			count, FURROW_RECT.size.x, FURROW_RECT.size.y])


## A tractor spawn on the apron, "tractor" removed from the island's road-side spawn.
## Level.pick_spawn takes the first marker that accepts the family, so the filters must be
## disjoint or the farm spawn would never be reached.
func _build_spawns(root: Node, apron: Rect2, deck_y: float) -> void:
	var stale := root.get_node_or_null(NodePath(SPAWN_NODE))
	if stale != null:
		root.remove_child(stale)
		stale.free()
	for node in root.find_children("*", "Marker3D", true, false):
		if not node.has_method("accepts"):
			continue
		var types: PackedStringArray = node.get("vehicle_types")
		var idx := types.find("tractor")
		if idx >= 0:
			types.remove_at(idx)
			node.set("vehicle_types", types)
	var spawn := VehicleSpawn.new()
	spawn.name = SPAWN_NODE
	spawn.vehicle_types = PackedStringArray(["tractor"])
	# West end of the parking row, facing +Z: the four implements are lined up to the right,
	# the gate and the field straight ahead.
	spawn.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(apron.position.x + SPAWN_X,
			deck_y + 1.0, apron.position.y + PARKING_ROW_Z))
	_add(root, spawn, root)


# =================================================================== resnap (stage two)


## Re-snap every scatter canvas against the reimported heightmap and stamp the ground hash
## (ScatterBase.ground_hash reads the texture, not the in-memory image, hence the reimport).
## Not ScatterBase.snap_ground: that reads `global_position`, needing a SceneTree, and this
## level is instantiated detached (joining the tree would run Level._ready and spawn vehicles).
## A clean run reports zero moved, proving the png round-tripped exactly.
func _resnap(root: Node) -> int:
	if not _read_terrain(root):
		return 1
	var img := _decode(_terrain.get("heightmap"))
	if img == null:
		printerr("[farm] cannot decode the terrain heightmap")
		return 1
	_iw = img.get_width()
	_ih = img.get_height()
	_sx = float(_iw - 1) / maxf(_span.x, 0.001)
	_sz = float(_ih - 1) / maxf(_span.y, 0.001)
	var canvases := _scatter_canvases(root)
	if canvases.is_empty():
		printerr("[farm] no scatter canvases found")
		return 1
	var ground := ScatterBase.ground_hash(root)
	var moved := 0
	var dropped := 0
	for canvas in canvases:
		moved += _resnap_from_image(canvas, img)
		dropped += _drop_off_terrain(canvas)
		canvas.set("stored_ground_hash", ground)
	print("[farm] resnap: %d canvases, %d instances moved, %d dropped (off the terrain)"
			% [canvases.size(), moved, dropped])
	return 0


## Drop stored instances whose world XZ lies outside the terrain extent — the tree-free
## equivalent of HeightmapTerrain.contains_xz (a floating instance is worse than a missing one).
func _drop_off_terrain(canvas: Node) -> int:
	var to_world := (canvas as Node3D).transform
	var after: Array[PackedFloat32Array] = []
	var removed := 0
	for flat: PackedFloat32Array in canvas.get("stored_transforms"):
		var kept := PackedFloat32Array()
		@warning_ignore("integer_division")
		var instances := flat.size() / ScatterBase.STRIDE
		for j in instances:
			var o := j * ScatterBase.STRIDE
			var world := to_world * Vector3(flat[o], flat[o + 1], flat[o + 2])
			if absf(world.x - _torigin.x) > _span.x * 0.5 \
					or absf(world.z - _torigin.z) > _span.y * 0.5:
				removed += 1
				continue
			kept.append_array(flat.slice(o, o + ScatterBase.STRIDE))
		after.append(kept)
	canvas.set("stored_transforms", after)
	return removed


# ====================================================================== shared helpers


func _read_terrain(root: Node) -> bool:
	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(root, terrains)
	if terrains.is_empty():
		printerr("[farm] level has no HeightmapTerrain")
		return false
	_terrain = terrains[0]
	_theight = float(_terrain.get("height"))
	_span = _terrain.get("terrain_size")
	_torigin = (_terrain as Node3D).position
	return true


func _scatter_canvases(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect_scatter(root, out)
	return out


func _collect_scatter(node: Node, out: Array[Node]) -> void:
	if node.is_in_group(Groups.SCATTER):
		out.append(node)
	for child in node.get_children():
		_collect_scatter(child, out)


## Add `child` under `parent` and give it the level root as owner, which is what makes
## PackedScene.pack serialize it.
func _add(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root


## Instance a kit prefab, yaw it, and sit it on the ground at `at`, positioned from its measured
## merged mesh AABB (rotated centre on target XZ, base on target Y) — measuring after rotation
## matters, a prefab whose origin isn't its centre would walk sideways when yawed.
func _place(parent: Node, root: Node, path: String, node_name: String, at: Vector3,
		yaw := 0.0) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("[farm] cannot load %s" % path)
		return
	var piece := scene.instantiate() as Node3D
	var turn := Basis(Vector3.UP, yaw)
	var aabb: AABB = Transform3D(turn, Vector3.ZERO) * _merged_aabb(piece, Transform3D.IDENTITY)
	piece.name = node_name
	piece.transform = Transform3D(turn,
			at - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z))
	_add(parent, piece, root)
	if not node_name.begins_with("Fence"):   # the fence run is 10 identical sections
		print("[farm]   %s: %.1f x %.1f x %.1f m at (%.1f, %.1f), footprint x %.1f..%.1f z %.1f..%.1f" % [
				node_name, aabb.size.x, aabb.size.y, aabb.size.z, at.x, at.z,
				at.x - aabb.size.x * 0.5, at.x + aabb.size.x * 0.5,
				at.z - aabb.size.z * 0.5, at.z + aabb.size.z * 0.5])


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


## Drop every stored instance of `canvas` whose world XZ falls inside any of `rects` — the
## rectangle sibling of ScatterCanvas.erase_within, which is radius-based.
func _erase_rects(canvas: Node, rects: Array[Rect2]) -> int:
	var to_world := (canvas as Node3D).transform
	var after: Array[PackedFloat32Array] = []
	var removed := 0
	for flat: PackedFloat32Array in canvas.get("stored_transforms"):
		var kept := PackedFloat32Array()
		@warning_ignore("integer_division")
		var instances := flat.size() / ScatterBase.STRIDE
		for j in instances:
			var o := j * ScatterBase.STRIDE
			var world := to_world * Vector3(flat[o], flat[o + 1], flat[o + 2])
			var inside := false
			for rect in rects:
				if rect.has_point(Vector2(world.x, world.z)):
					inside = true
					break
			if inside:
				removed += 1
				continue
			kept.append_array(flat.slice(o, o + ScatterBase.STRIDE))
		after.append(kept)
	canvas.set("stored_transforms", after)
	return removed


## Re-snap a canvas's stored Ys onto `img`, bilinearly. Both stages go through this: during
## `build` the terrain node still reads the OLD (pre-sculpt) texture, and during `resnap`
## the terrain's own height_at is unusable on a detached level (see _resnap).
func _resnap_from_image(canvas: Node, img: Image) -> int:
	var to_world := (canvas as Node3D).transform
	var to_local := to_world.affine_inverse()
	var after: Array[PackedFloat32Array] = []
	var moved := 0
	for flat: PackedFloat32Array in canvas.get("stored_transforms"):
		var kept := PackedFloat32Array()
		@warning_ignore("integer_division")
		var instances := flat.size() / ScatterBase.STRIDE
		for j in instances:
			var o := j * ScatterBase.STRIDE
			var world := to_world * Vector3(flat[o], flat[o + 1], flat[o + 2])
			var entry := flat.slice(o, o + ScatterBase.STRIDE)
			var ground_pos: Vector3 = to_local * Vector3(world.x,
					_height_at(img, world.x, world.z), world.z)
			if absf(ground_pos.y - flat[o + 1]) > 0.005:
				moved += 1
			entry[1] = ground_pos.y
			kept.append_array(entry)
		after.append(kept)
	canvas.set("stored_transforms", after)
	return moved


func _decode(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	return img


## Write a working image back over the png the terrain texture came from.
##
## Checked against the level's own directory first — load-bearing: a copy of these pngs left
## anywhere in the project brings a `.import` sidecar claiming the same uid://, so Godot's
## import scan resolves the level's texture to the copy and this function sculpts the backup
## while the real level stays untouched, silently. Fail loudly here instead.
func _write(img: Image, tex: Texture2D) -> bool:
	var path := tex.resource_path
	if path.is_empty():
		printerr("[farm] a terrain texture has no source png")
		return false
	var expected := LEVEL_PATH.get_base_dir()
	if path.get_base_dir() != expected:
		printerr("[farm] '%s' resolves to %s, outside %s — a duplicate uid:// is hijacking it"
				% [path.get_file(), path, expected])
		return false
	if img.save_png(path) != OK:
		printerr("[farm] failed to write %s" % path)
		return false
	TerrainGen.ensure_import_settings(path)
	print("[farm] wrote %s" % path)
	return true


func _save(root: Node) -> int:
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		printerr("[farm] PackedScene.pack failed")
		return 1
	if ResourceSaver.save(packed, LEVEL_PATH) != OK:
		printerr("[farm] cannot save %s" % LEVEL_PATH)
		return 1
	print("[farm] saved %s" % LEVEL_PATH)
	return 0


# --- world <-> pixel mapping (HeightmapTerrain's own convention: the grid spans
# [-span/2, +span/2] in the terrain's local frame, one cell per world unit) ---


func _norm(world_y: float) -> float:
	return clampf(world_y / maxf(_theight, 0.001), 0.0, 1.0)


func _px_x(world_x: float) -> int:
	return clampi(int(round((world_x - _torigin.x + _span.x * 0.5) * _sx)), 0, _iw - 1)


func _px_z(world_z: float) -> int:
	return clampi(int(round((world_z - _torigin.z + _span.y * 0.5) * _sz)), 0, _ih - 1)


func _world_x(px: int) -> float:
	return float(px) / _sx - _span.x * 0.5 + _torigin.x


func _world_z(pz: int) -> float:
	return float(pz) / _sz - _span.y * 0.5 + _torigin.z


## Bilinear world height off the working image — HeightmapTerrain.height_at, but reading the
## image we are in the middle of sculpting rather than the exported texture.
func _height_at(img: Image, world_x: float, world_z: float) -> float:
	var u := clampf((world_x - _torigin.x + _span.x * 0.5) / _span.x, 0.0, 1.0) * float(_iw - 1)
	var v := clampf((world_z - _torigin.z + _span.y * 0.5) / _span.y, 0.0, 1.0) * float(_ih - 1)
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, _iw - 1)
	var y1 := mini(y0 + 1, _ih - 1)
	var tx := u - float(x0)
	var ty := v - float(y0)
	var top := lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, tx)
	var bot := lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, tx)
	return _torigin.y + lerpf(top, bot, ty) * _theight


# ------------------------------------------------------------------- acceptance report


## Read the finished data back and print what it actually is. These are the numbers the
## design was sized against, so they get measured rather than asserted in a comment.
func _report(img: Image, splat: Image, splat2: Image, apron: Rect2, deck_y: float) -> void:
	print("\n[farm] ---- acceptance ----")

	var hits := 0
	var total := 0
	var worst := 0.0
	var z := FIELD_RECT.position.y + 2.0
	while z <= FIELD_RECT.end.y - 2.0:
		var x := FIELD_RECT.position.x + 2.0
		while x <= FIELD_RECT.end.x - 2.0:
			var h := _height_at(img, x, z)
			total += 1
			if absf(h - PLATEAU_Y) <= 0.11:
				hits += 1
			worst = maxf(worst, absf(_height_at(img, x + 1.0, z) - h))
			worst = maxf(worst, absf(_height_at(img, x, z + 1.0) - h))
			x += 2.0
		z += 2.0
	print("[farm] field %.0f x %.0f m: %.1f%% of samples within 0.11 m of %.1f m, worst 1 m step %.2f m" % [
			FIELD_RECT.size.x, FIELD_RECT.size.y,
			100.0 * float(hits) / maxf(float(total), 1.0), PLATEAU_Y, worst])

	for i in RAMP_PROFILE.size() - 1:
		var a := RAMP_PROFILE[i]
		var b := RAMP_PROFILE[i + 1]
		var run := absf(b.x - a.x)
		var rise := _height_at(img, b.x, RAMP_Z) - _height_at(img, a.x, RAMP_Z)
		print("[farm] ramp segment %d: run %.0f m, measured rise %.2f m = %.1f deg (design %.1f deg)" % [
				i + 1, run, rise, rad_to_deg(atan(rise / run)),
				rad_to_deg(atan((b.y - a.y) / run))])

	var lo := INF
	var hi := -INF
	var cross := 0.0
	var wz := WALLOW_RECT.position.y + RIDGE_TAPER
	while wz <= WALLOW_RECT.end.y - RIDGE_TAPER:
		var wx := WALLOW_RECT.position.x + RIDGE_TAPER
		while wx <= WALLOW_RECT.end.x - RIDGE_TAPER:
			var h := _height_at(img, wx, wz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			# 1.06 m is the tractor's rear track (kenney/tractor-kenney_spec.tres).
			cross = maxf(cross, absf(_height_at(img, wx + 0.53, wz)
					- _height_at(img, wx - 0.53, wz)))
			wx += 0.5
		wz += 0.5
	print("[farm] wallow floor %.2f..%.2f m (%.2f m under the plateau), ridges %.2f m peak-to-peak" % [
			lo, hi, PLATEAU_Y - lo, hi - lo])
	print("[farm] wallow max left/right ground step across the 1.06 m rear track: %.2f m" % cross)

	# The exit ramp onto the field is the wallow's blend ring. Report average grade over the
	# climb alongside the worst single 1 m facet (the 8-bit floor at 0.2 m steps, not a design
	# choice — quoting it alone would make a gentle ramp look like a wall). `back` counts
	# pixels where the profile goes down on the way up.
	var rim_x := WALLOW_RECT.get_center().x
	var facet := 0.0
	var back := 0
	var low := _height_at(img, rim_x, WALLOW_RECT.end.y)
	var high := low
	var run := WALLOW_MARGIN + 2.0
	for step in int(run):
		var z0 := WALLOW_RECT.end.y + float(step)
		var d := _height_at(img, rim_x, z0 + 1.0) - _height_at(img, rim_x, z0)
		facet = maxf(facet, absf(d))
		if d < -0.01:
			back += 1
		high = maxf(high, _height_at(img, rim_x, z0 + 1.0))
	var avg := (high - low) / run
	print("[farm] wallow -> field exit ramp: %.1f m climb over %.0f m = %.1f%% (%.1f deg) average," % [
			high - low, run, avg * 100.0, rad_to_deg(atan(avg))]
			+ " worst 1 m facet %.2f m, %d backward step(s)" % [facet, back])

	# grip_at reads the terrain's cached splat images (still pre-paint here), so sharpen the
	# freshly painted weights the same way it does instead.
	var probes: Array[Array] = [
		["field ", FIELD_RECT.get_center()],
		["mud   ", WALLOW_RECT.get_center()],
		["ramp  ", Vector2(RAMP_PROFILE[2].x, RAMP_Z)],
		["gravel", Vector2(apron.get_center().x, apron.position.y - 3.0)],
		["grass ", Vector2(FIELD_RECT.end.x + 20.0, FIELD_RECT.get_center().y)],
	]
	for probe in probes:
		var p: Vector2 = probe[1]
		print("[farm] grip at %s (%6.1f, %6.1f) = %.2f" % [probe[0], p.x, p.y,
				_grip_at(splat, splat2, p)])
	print("[farm] apron deck y %.2f — spawn and parked implements sit on it" % deck_y)
	print("[farm] ---- now run --import, then this tool again with `resnap` ----\n")


## HeightmapTerrain.grip_at against our freshly painted images: pow-sharpen every weight by
## the shader's blend_sharpness, renormalize, and mix channel_grip.
func _grip_at(splat: Image, splat2: Image, p: Vector2) -> float:
	var mat := _terrain.get("material") as ShaderMaterial
	var sharp: Variant = mat.get_shader_parameter(&"blend_sharpness") if mat != null else null
	var exponent := float(sharp) if sharp != null else 8.0
	var c0 := splat.get_pixel(_px_x(p.x), _px_z(p.y))
	var c1 := splat2.get_pixel(_px_x(p.x), _px_z(p.y))
	var total := 0.0
	var grip := 0.0
	for i in 8:
		var raw: float = (c0 if i < 4 else c1)[i & 3]
		var w := pow(raw, exponent)
		total += w
		grip += w * CHANNEL_GRIP[i]
	return 1.0 if total < 0.001 else grip / total
